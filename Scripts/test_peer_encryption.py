#!/usr/bin/env python3
"""Local MSE interoperability against Transmission 4.x (no public swarm).

Build live_probe first: cargo build --manifest-path rust/sweep-rqbit/Cargo.toml --bin live_probe
Requires transmission-daemon on PATH and a local non-loopback IPv4 address
(Transmission filters loopback peers received from trackers). No public swarm,
DHT, port mapping, or changes to the normal Transmission configuration.
"""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import ipaddress
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen


def bencode(value):
    if isinstance(value, int):
        return b'i' + str(value).encode() + b'e'
    if isinstance(value, bytes):
        return str(len(value)).encode() + b':' + value
    if isinstance(value, dict):
        return b'd' + b''.join(bencode(k) + bencode(v) for k, v in sorted(value.items())) + b'e'
    raise TypeError(type(value))


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


class RPC:
    def __init__(self, port):
        self.url = f'http://127.0.0.1:{port}/transmission/rpc'
        self.token = ''

    def call(self, method, **arguments):
        for _ in range(2):
            req = Request(self.url, json.dumps({'method': method, 'arguments': arguments}).encode(),
                          {'X-Transmission-Session-Id': self.token, 'Content-Type': 'application/json'})
            try:
                with urlopen(req, timeout=3) as response:
                    result = json.load(response)
                assert result['result'] == 'success', result
                return result['arguments']
            except HTTPError as error:
                if error.code != 409:
                    raise
                self.token = error.headers['X-Transmission-Session-Id']
        raise RuntimeError('RPC session negotiation failed')


def wait_for(condition, seconds=30):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = condition()
        if result:
            return result
        time.sleep(0.1)
    raise TimeoutError('local interoperability condition did not complete')


def run_case(root, probe, daemon, incoming, local_address, transport):
    case = root / ('incoming' if incoming else 'outgoing')
    case.mkdir()
    sweep_dir = case / 'sweep'; sweep_dir.mkdir()
    transmission_dir = case / 'transmission'; transmission_dir.mkdir()
    config = case / 'config'; config.mkdir()
    payload = bytes(n % 251 for n in range(1_048_576))
    (sweep_dir if incoming else transmission_dir).joinpath('interop.bin').write_bytes(payload)
    rpc_port, transmission_port, sweep_port = free_port(), free_port(), free_port()

    class Tracker(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            query = parse_qs(urlparse(self.path).query)
            is_transmission = query.get('peer_id', [''])[0].startswith('-TR')
            port = sweep_port if incoming else transmission_port
            # Only the intended initiator receives the other client's address.
            send_peer = is_transmission == incoming
            peers = socket.inet_aton(local_address) + struct.pack('!H', port) if send_peer else b''
            body = bencode({b'interval': 1, b'complete': 1, b'incomplete': 1, b'peers': peers})
            self.send_response(200); self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)

    tracker = ThreadingHTTPServer(('127.0.0.1', 0), Tracker)
    threading.Thread(target=tracker.serve_forever, daemon=True).start()
    tracker_url = f'http://127.0.0.1:{tracker.server_port}/announce'
    info = {b'name': b'interop.bin', b'length': len(payload), b'piece length': 65536,
            b'private': 0, b'pieces': b''.join(hashlib.sha1(payload[n:n+65536]).digest()
                                             for n in range(0, len(payload), 65536))}
    torrent = bencode({b'announce': tracker_url.encode(), b'info': info})
    torrent_path = case / 'fixture.torrent'; torrent_path.write_bytes(torrent)
    magnet_path = case / 'fixture.magnet'
    magnet_path.write_text(f'magnet:?xt=urn:btih:{hashlib.sha1(bencode(info)).hexdigest()}&tr={tracker_url}')
    processes = []
    log_files = []
    observations = []
    def start(args, log, env=None):
        output = open(log, 'w'); log_files.append(output)
        process = subprocess.Popen(args, stdout=output, stderr=subprocess.STDOUT, env=env)
        processes.append(process)
        return process
    try:
        start([daemon, '-f', '-g', str(config), '-p', str(rpc_port), '-P', str(transmission_port),
               '-w', str(transmission_dir), '-r', '127.0.0.1', '-i', local_address, '-T', '-O', '-Y',
               '-M', '-er', '--preferred-transports', transport, '--log-level', 'debug'], case / 'transmission.log')
        rpc = RPC(rpc_port)
        def ready():
            try:
                return rpc.call('session-get')
            except (URLError, ConnectionError):
                return False
        wait_for(ready)
        rpc.call('session-set', **{'speed-limit-up': 256, 'speed-limit-up-enabled': True,
                                  'speed-limit-down': 256, 'speed-limit-down-enabled': True})
        def add_transmission():
            rpc.call('torrent-add', metainfo=base64.b64encode(torrent).decode(), paused=False,
                     **{'download-dir': str(transmission_dir)})
        def state():
            return rpc.call('torrent-get', fields=['id', 'percentDone', 'peers', 'status', 'errorString'])['torrents']
        if not incoming:
            add_transmission()
            wait_for(lambda: state() and state()[0]['percentDone'] == 1)
        env = dict(os.environ, SWEEP_PROBE_TRANSPORT=transport, SWEEP_PROBE_DISCOVERY='trackers',
                   SWEEP_PROBE_LISTEN_ADDR=f'{local_address}:{sweep_port}')
        if incoming:
            env['SWEEP_PROBE_SEED_SECONDS'] = '20'
        child = start([str(probe), str(torrent_path if incoming else magnet_path), str(sweep_dir),
                       str(len(payload)), '30'], case / 'sweep.log', env)
        if incoming:
            wait_for(lambda: 'state=live' in (case / 'sweep.log').read_text())
            add_transmission()
        encrypted = False
        def complete():
            nonlocal encrypted
            rows = state()
            if rows:
                observations.append(rows[0])
                encrypted |= any(peer['isEncrypted'] for peer in rows[0]['peers'])
                if incoming:
                    return rows[0]['percentDone'] == 1
            return not incoming and child.poll() is not None
        wait_for(complete, 35)
        assert encrypted, 'Transmission never reported an encrypted peer'
        assert child.wait(timeout=25) == 0, (case / 'sweep.log').read_text()
        target = (transmission_dir if incoming else sweep_dir) / 'interop.bin'
        assert target.read_bytes() == payload, 'download differs from seeded bytes'
        print(f'{case.name}: encrypted transfer verified byte-for-byte (metadata + payload)' if not incoming
              else f'{case.name}: encrypted incoming payload transfer verified byte-for-byte', flush=True)
    finally:
        (case / 'rpc-observations.json').write_text(json.dumps(observations, indent=2))
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
        for log in log_files:
            log.close()
        tracker.shutdown(); tracker.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='New directory to retain evidence (otherwise temporary).')
    parser.add_argument('--transport', choices=['tcp', 'utp'], default='tcp')
    parser.add_argument('--local-address', required=True, help='An IPv4 address assigned to this Mac (for example ipconfig getifaddr en0).')
    args = parser.parse_args()
    address = ipaddress.IPv4Address(args.local_address)
    if address.is_loopback or address.is_unspecified or address.is_multicast:
        parser.error('Use a non-loopback address assigned to this Mac.')
    with socket.socket() as check:
        check.bind((str(address), 0))
    probe = Path(__file__).resolve().parents[1] / 'rust/target/debug/live_probe'
    daemon = shutil.which('transmission-daemon')
    if not daemon or not probe.exists():
        parser.error('Build live_probe and install transmission-daemon before running this check.')
    def run(root):
        run_case(root, probe, daemon, False, str(address), args.transport)
        run_case(root, probe, daemon, True, str(address), args.transport)
    if args.output:
        args.output.mkdir(parents=True, exist_ok=False)
        run(args.output.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='sweep-mse-') as directory:
            run(Path(directory))


if __name__ == '__main__':
    main()
