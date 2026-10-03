#!/usr/bin/env python3
"""Local-only, throttled BitTorrent seed for repeatable iOS background/UI testing.

Run: python3 Scripts/live_activity_fixture.py /tmp/sweep-background-fixture
Open magnet.txt in Sweep. Change rate-kib.txt while running to adjust the rate.
The private torrent uses only its loopback tracker. No external services or VPN
changes are needed. Ctrl-C stops both servers. Payload is deterministic test data.
"""
import argparse
import asyncio
import hashlib
import json
import socket
import struct
from pathlib import Path
from urllib.parse import quote


def bencode(value):
    if isinstance(value, int):
        return b'i' + str(value).encode() + b'e'
    if isinstance(value, bytes):
        return str(len(value)).encode() + b':' + value
    if isinstance(value, str):
        return bencode(value.encode())
    if isinstance(value, list):
        return b'l' + b''.join(map(bencode, value)) + b'e'
    return b'd' + b''.join(bencode(k) + bencode(v) for k, v in sorted(value.items())) + b'e'


def bdecode(data, offset=0):
    if data[offset:offset+1] == b'i':
        end = data.index(b'e', offset)
        return int(data[offset+1:end]), end+1
    if data[offset:offset+1] == b'd':
        result = {}; offset += 1
        while data[offset:offset+1] != b'e':
            key, offset = bdecode(data, offset)
            result[key], offset = bdecode(data, offset)
        return result, offset+1
    colon = data.index(b':', offset)
    size = int(data[offset:colon]); offset = colon+1
    return data[offset:offset+size], offset+size


async def main(args):
    root = args.directory
    root.mkdir(parents=True, exist_ok=True)
    rate_file = root / 'rate-kib.txt'
    rate_file.write_text(str(args.rate_kib))
    piece_size = 65536
    piece = bytes(n % 251 for n in range(piece_size))
    size = args.size_mib * 1024 * 1024
    count = size // piece_size
    name = 'Background transfer — Sweep test data.bin'
    info = bencode({b'length': size, b'name': name.encode(), b'piece length': piece_size,
                    b'pieces': hashlib.sha1(piece).digest() * count, b'private': 1})
    info_hash = hashlib.sha1(info).digest()
    served = 0

    async def peer(reader, writer):
        nonlocal served
        def send(message):
            writer.write(struct.pack('!I', len(message)) + message)
        try:
            handshake = await asyncio.wait_for(reader.readexactly(68), 20)
            if handshake[28:48] != info_hash:
                return
            writer.write(b'\x13BitTorrent protocol' + b'\x00\x00\x00\x00\x00\x10\x00\x00'
                         + info_hash + b'-SW0001-fixtureseed0')
            send(b'\x14\x00' + bencode({b'm': {b'ut_metadata': 1}, b'metadata_size': len(info)}))
            bitfield = bytes([255]) * (count // 8)
            if count % 8:
                bitfield += bytes([255 << (8-count % 8) & 255])
            send(b'\x05' + bitfield)
            send(b'\x01')
            await writer.drain()
            metadata_id = 1
            while True:
                length = struct.unpack('!I', await reader.readexactly(4))[0]
                if length > 1_000_000:
                    return
                if not length:
                    continue
                message = await reader.readexactly(length)
                if message[0] == 20 and len(message) >= 2:
                    header, _ = bdecode(message[2:])
                    if message[1] == 0:
                        metadata_id = header.get(b'm', {}).get(b'ut_metadata', 1)
                    elif message[1] == 1 and header.get(b'msg_type') == 0:
                        index = header[b'piece']
                        chunk = info[index*16384:(index+1)*16384]
                        send(bytes([20, metadata_id]) + bencode({b'msg_type': 1, b'piece': index,
                                                               b'total_size': len(info)}) + chunk)
                elif message[0] == 6:
                    index, begin, length = struct.unpack('!III', message[1:])
                    if index >= count or begin + length > piece_size or length > 16384:
                        return
                    try:
                        rate = max(1, float(rate_file.read_text())) * 1024
                    except (ValueError, OSError):
                        rate = args.rate_kib * 1024
                    await asyncio.sleep(length / rate)
                    send(b'\x07' + struct.pack('!II', index, begin) + piece[begin:begin+length])
                    served += length
                    if served % (1024*1024) == 0:
                        print(f'Served {served // (1024*1024)} MiB', flush=True)
                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionError, TimeoutError, ValueError, KeyError):
            pass
        finally:
            writer.close()

    seed = await asyncio.start_server(peer, '127.0.0.1', 0)
    seed_port = seed.sockets[0].getsockname()[1]

    async def tracker(reader, writer):
        try:
            await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'), 10)
            body = bencode({b'interval': 15, b'complete': 1, b'incomplete': 0,
                            b'peers': socket.inet_aton('127.0.0.1') + struct.pack('!H', seed_port)})
            writer.write(b'HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: '
                         + str(len(body)).encode() + b'\r\n\r\n' + body)
            await writer.drain()
        except (ConnectionError, asyncio.IncompleteReadError, TimeoutError):
            pass
        finally:
            writer.close()

    announce = await asyncio.start_server(tracker, '127.0.0.1', 0)
    tracker_url = f'http://127.0.0.1:{announce.sockets[0].getsockname()[1]}/announce'
    # Preserve the already-encoded info dictionary when writing metainfo.
    torrent = b'd8:announce' + bencode(tracker_url) + b'4:info' + info + b'e'
    (root / 'fixture.torrent').write_bytes(torrent)
    (root / 'magnet.txt').write_text(f'magnet:?xt=urn:btih:{info_hash.hex()}&dn={quote(name)}&tr={quote(tracker_url, safe="")}')
    print(json.dumps({'directory': str(root), 'infoHash': info_hash.hex(), 'bytes': size,
                      'pieceLength': piece_size, 'seedPort': seed_port, 'tracker': tracker_url}), flush=True)
    async with seed, announce:
        await asyncio.gather(seed.serve_forever(), announce.serve_forever())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--size-mib', type=int, default=64)
    parser.add_argument('--rate-kib', type=float, default=128)
    args = parser.parse_args()
    if args.size_mib < 1 or args.rate_kib <= 0:
        parser.error('size and rate must be positive')
    try:
        asyncio.run(main(args))
    except KeyboardInterrupt:
        pass
