# Sweep Feature Backlog

Sweep should feel like a compact, native macOS torrent client with the care
and information density of classic clients such as Transmission, early uTorrent,
and eMule. The goal is to recover useful craft that many mainstream clients
lost: readable state, rich progress information, and direct controls without
turning the app into a dashboard.

## Direct Wi-Fi in the macOS app, November 25, 2026

The opt-in macOS setting uses a signed launch daemon registered with
`SMAppService`. The helper opens a bridged `vmnet` interface on physical
Wi-Fi, acquires a guest IPv4 lease, and attaches it to an ephemeral `utun`.
Four interface-scoped IPv4 routes belong to that private interface. Only the
authenticated Sweep client’s TCP and UDP sockets can use the guest link.
Quitting Sweep closes the interface and its routes. The helper exits when
idle, and macOS retains its approval. The app verifies the helper’s signature
against the bundled executable and recreates the registration if an older
helper answers after an update.

rqbit binds peer sockets, DHT and tracker sockets to that interface. The
bridge’s compatibility announce uses the session’s HTTP client and tracker
policy. Direct mode uses IPv4, keeps system DNS, and disables local multicast
peer discovery. App updates and other ordinary connections follow system
routing.

In two isolated launches of the installed, signed app, the original torrent’s
HTTP tracker reached Working and the same swarm also transferred data from a
trackerless magnet. The latter started with eight DHT node contacts and no
supplied peer addresses. The original file produced 39 verified pieces (78 MiB),
and the trackerless magnet produced two (4 MiB). An independent reader
matched each piece against the original torrent’s SHA-1 hashes. A separate process bound to Sweep’s private interface
could not complete a connection. Its ordinary connection to the same public
server used Red Shield’s Latvian exit. The physical Wi-Fi scope had no route to
that server, and the private routes disappeared after each quit.

## Trackerless download over Wi-Fi with Red Shield connected, November 25, 2026

We compared the same public, 2.98 GiB torrent on Red Shield (`utun4`) and
direct Wi-Fi (`en0`). The direct test paired IPv4 sockets bound to Wi-Fi with
temporary, interface-scoped host routes through the Wi-Fi gateway. Ordinary
traffic to the same destinations continued to use Red Shield.

| Test | Through Red Shield | Direct Wi-Fi |
| --- | --- | --- |
| HTTP announce to both IPv4 addresses of the torrent's tracker | Both timed out | Both replied, 30 distinct peer endpoints in total |
| DHT `get_peers` for the same info hash at the same 31 nodes | 0 replies | 22 replies, 26 distinct peer endpoints |
| rqbit magnet, trackers off, starting with eight DHT node contacts and zero supplied peers | 0 DHT replies or peer candidates in 34 s | 56 DHT candidates, two uTP handshakes, metadata verified in 0.42 s |
| Sweep engine, original torrent file added paused and resumed, same DHT contacts, trackers off, uTP only | 0 peers or bytes in 45 s | Four pieces totaling 8,220,530 bytes by 14 s. All four SHA-1 hashes matched the original torrent in an independent check. |

The eight starting contacts were DHT nodes that had answered the earlier
lookup. With a fresh node table, direct Wi-Fi received bootstrap replies
but found no peers within 34 seconds using the limited set of routed addresses.
In a separate comparison we supplied the same 18 DHT-discovered peers to
rqbit on both interfaces. Only direct uTP recovered the target metadata.
TCP recovered Ubuntu control metadata on both interfaces. Reachability for
the tested swarm depended on the route. The point of failure within the VPN
path remains unknown.

This earlier test used a fixed list of destinations. The app at the time
used the system route, and its initial HTTP announces for freshly started
torrent files used a separate HTTP client. The test used the paused-add and
resume path to exclude those announces. After cleanup, all 59
tested public IPv4 addresses routed through `utun4` and had no Wi-Fi-scoped
route. Raw results and piece hashes are in `BuildArtifacts/VPNRouting-2026-11-25/swarm/`.

## Direct Wi-Fi routing on macOS, November 25, 2026

With Red Shield connected, we added a 12-second IPv4 host route to Cloudflare's
`1.0.0.1` through the Wi-Fi gateway, scoped to `en0`. We opened fresh sockets
to that address and compared a TLS-verified HTTPS trace and a UDP DNS query.

| Socket | Before the route | During the route | After removal |
| --- | --- | --- | --- |
| Automatic | VPN exit in Latvia, DNS replied | Same VPN exit, DNS replied | Same VPN exit, DNS replied |
| Bound to Wi-Fi with `IP_BOUND_IF` | Network unreachable | Different public IP in Russia, DNS replied | Network unreachable |

The ordinary route stayed on `utun4` throughout. The temporary route could
serve any program explicitly bound to `en0` for that address. This test
verified a direct path for a single IPv4 destination. The swarm comparison
above exercised additional IPv4 destinations. IPv6 bypass remains untested.
Local results are in `BuildArtifacts/VPNRouting-2026-11-25/scoped-ipv4.log`.

## Red Shield VPN routing on macOS, November 24, 2026

Red Shield installed two half-default routes for each address family on
`utun4` (`0/1` and `128.0/1` for IPv4, `::/1` and `8000::/1` for IPv6).
These more specific routes won over the Wi-Fi default for the public endpoints
tested. Red Shield's own transport process sent its outer UDP traffic on `en0`.
Tailscale owned separate tailnet and DNS routes on `utun7`. Its earlier fix
selected routes by destination and forced TCP relays because its direct UDP
sockets were bound to Wi-Fi. Sweep leaves rqbit's interface selection to
macOS. Outbound TCP peers get a socket for their address family. HTTP(S)
trackers use reqwest, UDP trackers have a socket per endpoint, and DHT and
uTP each reuse a UDP socket for multiple destinations. A wildcard listener
accepts incoming peers. The installed app's public TCP connection and outgoing UDP sockets
appeared on `utun4` in `nettop`. Its local peer discovery socket on UDP 6771
uses multicast across interfaces and also appeared on `utun7`. System DNS
listed both Tailscale's supplemental resolver and the VPN resolver. The
resolver used for an individual lookup was not measured.

The comparison used fresh diagnostic sessions with local discovery off. Each
pair used the same input and kept the VPN connected.

| Test | System-selected interface | Explicit bind to Red Shield |
| --- | --- | --- |
| Ubuntu magnet, only its two publisher HTTPS tracker URLs | Zero candidates in 45 s | Zero candidates in 45 s |
| Same magnet with four additional HTTPS trackers from the October control, TCP peers | Metadata in 13 s, 8 IPv4 sockets connected | Metadata in 14 s, 8 IPv4 sockets connected |
| Same additional trackers, uTP peers | 39 candidates, zero sockets connected in 48 s | 41 candidates, zero sockets connected in 48 s |
| Fresh DHT bootstrap | 9 queries, zero replies in 25 s | 9 queries, zero replies in 25 s |
| Independent IPv4 probes with a fresh socket per endpoint, two requests each | 0/3 DHT addresses and 0/3 UDP trackers replied | Same |
| Independent UDP controls | Both IPv4 DNS and both STUN endpoints replied. The IPv6 DNS control timed out. | Same |

On a shared IPv4 UDP socket, the DNS and STUN controls returned matching
transactions from the expected endpoints in both orders. The October
first-destination behavior did not recur with these controls. In a separate
TCP download through the system-selected route, eight 256 KiB pieces matched
the SHA-1 hashes in the publisher's torrent file (2 MiB total). At inspection
time both incomplete, running torrents in the Mac app had only HTTP or UDP
trackers configured and neither had a working tracker recorded.

The working path was HTTPS peer discovery followed by TCP peer traffic.
Binding the socket to the VPN did not restore the unanswered services.
Selective filtering and unreachable remote endpoints remain possible. Red
Shield also says torrent availability can vary by location. [Provider FAQ, question 26](https://redshieldvpn.com/en/faq)

The installed app had also stopped listening on its persisted DHT port. A
separate loopback regression reproduced one way this can happen. After 24
hours of cumulative bootstrap retry delays, rqbit could terminate the entire
DHT worker when all bootstrap hosts failed. The patch keeps the existing
jittered retry interval for the session's lifetime. In a test with 48 hours of
simulated silence, the original worker failed to recover. The patched node
and a newly reachable bootstrap node exchanged DHT replies in both directions.
With both peer transports and both discovery methods enabled, the patched
engine also resolved the Ubuntu control with the additional trackers in 13 s.
The installed process had no recorded worker exit reason, so the cause of that
specific socket closure is uncertain.

Local probe logs, per-process interface samples, UDP reply validation, and
piece hash results are under `BuildArtifacts/VPNRouting-2026-11-24/`.

## Lost Highway Discovery Investigation, October 26, 2026

Investigated the installed Mac build (`00359dd`) and magnet
`0a4e63611eb6192a1bbb2e9b64b10a49a0740a20`. The user reported 26 seeders and
5 leechers on the index page. Browser site-safety policy prevented reading that
page, so its count, timestamp, and data source were not independently verified.
The VPN, routes, and user torrent settings were left unchanged.

| Check | Result |
| --- | --- |
| Original seven trackers, Sweep, 125 seconds | Zero peer addresses, sockets, handshakes, or metadata; automatic retry ran. Two tracker hostnames failed DNS; UDP trackers timed out. |
| Same magnet, clean Transmission 4.1.3 session, 180 seconds | Zero connected peers or metadata; all seven trackers failed. No payload downloaded. |
| Four additional HTTPS trackers, Sweep | Three responded; six unique peers initially, eight on a later check. All connection attempts timed out before a BitTorrent handshake. |
| Same HTTPS trackers, clean Transmission, 180 seconds | Three successful tracker responses, zero seeders reported, zero connected peers or metadata. Reported peer counts overlap and include our temporary announcements. |
| Independent TCP connections to all eight returned peer endpoints | All timed out, outside rqbit and Transmission. |
| Independent DHT pings | No response from five resolved addresses across Transmission, libtorrent, BitTorrent, and uTorrent bootstrap services; two probes per address. |
| Independent UDP tracker connect requests | No response from OpenTrackr, open.stealth.si, or tracker.torrent.eu.org. |
| UDP controls on the unchanged route | Public DNS and Google/Cloudflare STUN replied. This is not a blanket UDP failure. |
| Official Ubuntu magnet control | Sweep resolved complete metadata in about 13 seconds, including TCP peer connections and PEX. Repeated successfully with TCP only; successful peer routes use `utun6`. No ISO payload requested. |
| Five HTTP tracker alternatives | No usable announce response within the 125-second probe. Independent TCP connected to OpenTrackr and open.tracker.cl, but their HTTP requests timed out; the other endpoints timed out during TCP connection setup. |

The immediate problem is discovery reachability followed by unreachable peers
from the limited reachable trackers, before encryption or metadata negotiation.
The control swarm proves that peer connections and metadata exchange can work
through the current VPN route. Matching Transmission failures and independent
socket probes provide no evidence that replacing rqbit would fix this swarm.
Selective filtering or endpoint unavailability remains possible; these tests
cannot identify the exact VPN, upstream, firewall, or remote component responsible.
The index count is not a list of reachable peers and does not establish current
availability through these trackers. DHT could discover additional peers, but its
UDP bootstrap traffic currently receives no replies.

Useful follow-ups: editable tracker lists with explicit additions, a clear
"no reachable discovery sources" explanation, bounded HTTP announce deadlines
(the upstream client has no request deadline, so a silent server can remain
"Announcing" until the outer metadata attempt is cancelled), and transport
statistics that distinguish cancellation from in-flight attempts. Do not infer
successful connectivity from cached DHT nodes or site seed counts, or append a
large unverified tracker list as a presumed fix. A second network/VPN route would
be needed to isolate the remaining network hypothesis; none was changed here.

Raw logs, isolated Transmission configurations/observations, original and test
magnets, and independent UDP/TCP probe results are retained locally under
`BuildArtifacts/LostHighwayDiagnostics/`. Diagnostic processes are stopped.
Protocol references: [DHT/BEP 5](https://www.bittorrent.org/beps/bep_0005.html),
[Transmission bootstrap implementation](https://github.com/transmission/transmission/blob/4.1.3/libtransmission/tr-dht.cc),
and the [maintained tracker list](https://github.com/ngosang/trackerslist).

## macOS Parity, October 26, 2026

- macOS uses the same metadata retries, DHT persistence/health, metadata PEX,
  MSE/PE and TCP/uTP fallback, and download-folder handling as iOS. Discovery
  diagnostics and peer transport labels are shared too.
- The Mac inspector remembers its section across relaunches and provides compact
  Play/episode navigation and Pause/Resume/Retry controls above the tabs.
- Files expose Play/Open using the original payload in its default Mac app,
  including existing partial files. Playback still depends on the reader and
  available bytes. Movie identification and naturally sorted episodes reuse
  `TorrentMedia`; path validation and openability reuse `TorrentFileLocation`.
- Download All, Videos Only, Only This File, and checkboxes use the shared queued
  selection/persistence logic. Pending changes disable selection controls; the
  last real file cannot be deselected. Padding is hidden from selection counts.
- All 43 shared tests and macOS/iOS Debug builds pass. A personal-team signed
  universal Release build was installed in `/Applications/Sweep.app`; its
  signatures and static linkage pass verification. The installed app restored
  all three existing torrents, displayed the movie/file/selection controls,
  and retained the Files tab after another quit and relaunch.

## iOS Details and Media Actions, October 4, 2026

Follow-up: Live Activity recovery and partial files

- Lock Screen cards now use ActivityKit's translucent dark tint with light
  foreground content, instead of its opaque default background. The system owns
  the material and shape; Reduce Transparency and dimmed displays get stronger
  backgrounds for legibility.
- Live Activities exist while download work is active. Pause, failure, and removal
  end and dismiss the card immediately; Resume/Retry starts a fresh activity.
  Completion in the foreground dismisses immediately too. Background completion
  leaves a summary for at most two minutes, cleared sooner when Sweep reopens or
  new work starts. Adoption keeps the newest active card and dismisses duplicates.
  This follows [Apple's lifecycle guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities)
  to end when work stops and retain only a useful, brief final summary. Unrelated
  action/startup errors are still preserved in session health.
- Play/Open accepts existing partial files, including preallocated files and
  files being checked. The shared location helper still rejects missing files,
  directories, padding, and unsafe paths. Opening does not imply completion.
- AVKit reads the original payload. Missing media headers/chunks may prevent
  playback; Try Again and Reload Video create a fresh asset to read newly arrived
  bytes. Reload preserves the current playback position where available.
- External-app actions use an `NSItemProvider` open-in-place representation of
  the original file exposed through Sweep's Documents provider. The recipient
  chooses whether to request it in place or import a copy. Cross-app behavior
  depends on that player; no compatible external player was installed in the
  simulator. This is local partial-file access, not piece-prioritized streaming.
- Verified on the persistent iPhone 17 Pro Max: translucent cards in light/dark
  appearance, an actual 90-second metadata timeout, and recovery after relaunch.
  Pause immediately removed the card; Resume created it again. Completion while
  locked retained the 100% summary, and returning to Sweep cleared it immediately.
  A second metadata timeout dismissed the card; Retry cleared the torrent error
  and foreground completion left no residual card.
  A partial MP4 failed with its header missing, then played after adding the
  header to the same file and retrying while its final quarter was still absent.
  Reload continued at the current position after more bytes arrived.
  The external-app sheet displayed the partial video. All 42 shared tests and
  macOS, iOS Simulator, and unsigned iOS device builds pass.
  Temporary fixtures were removed; the original download and simulator data remain.

Earlier details improvements:

- Details remembers its last selected tab across torrents and app relaunches.
  Play and Pause/Resume are prominent buttons above the inspector tabs.
- Shared file metadata identifies a main movie while excluding artwork,
  samples, extras, and padding. Episode collections are naturally ordered and
  each video has its own Play action. Comparable movie collections do not get
  an arbitrary primary video.
- Local videos use AVKit when supported. Unsupported formats offer
  Open in Another App; the supplied MKV requires a compatible external player.
  Playback is foreground-only. Partial-file behavior is described above.
- File rows have 44-point menu targets, visible Download switches, and direct
  Play/Open buttons. Selection includes Download All, Videos Only, and Only This
  File. Queued edits use the latest selection; paused torrents can be edited
  before engine restoration, then apply those saved choices on Resume.
- List separators explicitly align with the torrent titles. File actions adapt
  to light/dark appearance and accessibility text sizes.
- All 40 shared tests pass, as do macOS, iOS device, and simulator builds. On the
  persistent iPhone 17 Pro Max simulator, native movie/episode playback, the MKV
  fallback, selection persistence/Resume, tab restoration, and both appearances
  were checked. Generated media fixtures were removed afterward; the existing
  real download and simulator data were preserved.

## Download Layout and Local Installation, October 4, 2026

- Rootless multi-file magnets and `.torrent` files now use a named containing
  folder. Single files and an existing common root retain their layout. Unsafe
  torrent names fall back to the info hash when choosing the folder name.
- Rust snapshots expose the exact output directory. The shared store persists
  it and restores it without applying folder creation again. Older downloads
  retain their existing destinations. Reveal/Open uses actual payload paths.
- Five Rust tests pass, including local single/multi-file magnet transfers,
  byte-for-byte verification, a fresh engine restoring the same directory, and
  cancellation/discovery diagnostics. All 34 shared Swift tests pass, including
  destination persistence, restoration policy, and payload location checks.
- The supplied eight-file Hemingway download was organized into its named
  folder with a database backup. All 940 piece hashes match before and after the
  move. The installed Mac app restored it at 100% on two launches; the unrelated
  single-file download retained its path and completed state.
- `Scripts/install_macos.sh` builds Release by default, verifies personal-team
  development signing, safely replaces `/Applications/Sweep.app`, and launches
  it. The Mac Release and unsigned iOS device builds pass. Installation and
  relaunch of the signed local Mac app were verified.

## Discovery Reliability, October 17, 2026

- Metadata discovery now retries after a 90-second attempt, with 15/30/60/120-second
  backoff. Pausing or removing a pending magnet cancels both the active attempt
  and any scheduled retry. The inspector shows the attempt and countdown rather
  than treating a temporary lack of reachable peers as a permanent torrent error.
- The shared inspector separates tracker/DHT/PEX candidates, connected sockets,
  BitTorrent handshakes, metadata-capable peers, metadata blocks, and failures at
  each stage. Candidate sources can overlap; counts reset for each attempt.
- PEX introductions are consumed while resolving metadata, including from peers
  that support PEX but do not have metadata themselves. Candidate queues and
  per-source sets are bounded, and duplicate endpoints are suppressed per attempt.
- DHT routing tables are saved under Application Support/Sweep/Network and reused
  on launch. Both address families are restored, writes flush before replacement,
  and the UDP socket binds an available port. Fixed a duplicate-query bug that
  discarded a successful DHT reply and queried the same node again.
- Session Health distinguishes cached contacts from current reachability, with
  query/reply/timeout counts, last reply age, bootstrap DNS address counts and
  failures, and persistence errors. Two DNS bootstrap names resolving to three
  addresses are a starting set, not a cap on the routing table.
- Local regressions verify cancellation during backoff, PEX-assisted metadata
  resolution, a single DHT response being sufficient, and IPv4/IPv6 cache reload.
  Shared Swift tests cover retry presentation and cached nodes without replies.
- On the existing Mac VPN path, the iOS 26 simulator still receives no DHT replies.
  This establishes an observed network symptom, not which layer is filtering it
  or whether the phone's path behaves identically. The VPN was unchanged.

## Peer Compatibility, October 17, 2026

- MSE/PE negotiation now wraps TCP, uTP, and SOCKS peer streams using the pinned
  Apache-2.0 `urtorrent-mse` 0.14.3 protocol implementation. Plaintext remains the
  first outgoing attempt; a failed wire handshake triggers MSE on that transport,
  followed by the alternative TCP/uTP transport if enabled. SOCKS never falls back
  to a direct connection. Incoming connections accept plaintext and MSE.
- Tracker announces now advertise peer encryption support. Peer details show
  `tcp (MSE)` / `uTP (MSE)` for MSE-negotiated connections. MSE can negotiate
  plaintext or RC4 payloads; the label identifies the negotiation protocol.
- Fixed fragmented BitTorrent handshakes, optional/additive BEP 10 extension
  maps, and reporting the local peer ID instead of the remote ID on incoming
  connections. Subsequent extension maps update outgoing message IDs without
  restarting metadata requests or PEX tasks.
- The stream adapter bounds negotiation bytes, preserves buffered bytes after the
  handshake, and handles partial writes, Pending, and write cancellation without
  losing cipher position. Four adapter regressions and one extension-map test pass.
- Nine wrapper tests pass, including a fresh attempt recovering automatically
  after a tracker initially returns no peers, and uTP succeeding after a TCP
  endpoint accepts connections but rejects both plaintext and MSE handshakes.
- `Scripts/test_peer_encryption.py` verifies incoming and outgoing transfers
  against Transmission 4.1.3 with encryption required, using a generated 1 MiB
  fixture and a local tracker, with DHT/LSD and port mapping disabled. Outgoing
  metadata resolution and payload transfer pass; incoming payload transfer passes;
  both payloads match byte-for-byte and Transmission reports encrypted peers.
  Repeating both directions with `--transport utp` also passes.
  Pass `--local-address` with this Mac's existing non-loopback IPv4 address because
  Transmission intentionally rejects tracker-supplied loopback peers. No network
  settings or normal Transmission configuration are changed. The existing VPN
  remains connected.
- `live_probe` supports `SWEEP_PROBE_LISTEN_ADDR` and
  `SWEEP_PROBE_SEED_SECONDS` for controlled interoperability checks, and prints
  discovery sources/stages, retry state, DHT reply counters, and peer transports.

A fresh 125-second metadata-only probe of `021e7e8456515a36514d00ca54ab1d664f92a79e`
completed the first 90-second attempt, waited 15 seconds, and started attempt 2.
The HTTPS tracker returned one peer (zero seeders / one leecher). Neither TCP nor
uTP connected; socket/BitTorrent/metadata success counters stayed zero. DHT sent
18 queries and received zero replies. No payload was requested. This remains a
reachability failure before encryption or metadata negotiation on this Mac's
current path; it does not establish the cause of the phone's failure.

The bridge build now reuses its explicit host target for UniFFI generation,
avoiding a duplicate native Rust library build. This was exposed by low disk space
during multi-architecture validation. Only generated compiler outputs were cleaned;
app containers and downloaded files were preserved.

Final validation: macOS Debug, unsigned iOS device, and the designated iOS 26
simulator build pass. The simulator app resolved and downloaded the encrypted
Transmission fixture, displayed `tcp (MSE)` in Peers, matched the source bytes,
and restored it at 100% after relaunch. The test download was removed afterward.
The original completed download was preserved. Device packaging remains
static Rust linkage, iPhone-only / iOS 26, with no internal embedded frameworks
or CommonCrypto symbol references.

Remaining compatibility work includes BEP 55 hole punching and evaluating an
explicit encryption preference. MSE does not repair unreachable sockets or a DHT
path that receives no UDP replies. Phone-specific reachability still needs actual
phone observations; simulator results describe the Mac's network path.

## Magnet Connectivity Investigation, October 15, 2026

Investigated the phone report for v1 info hash
`021e7e8456515a36514d00ca54ab1d664f92a79e`. The live measurements below are
from the Mac's existing network path, not the phone; the VPN was unchanged.

- A fresh, 90-second metadata-only probe received one peer from the HTTPS
  tracker. No UDP tracker completed an announce. DHT remained at zero IPv4
  and IPv6 nodes, and neither TCP nor uTP established a peer connection.
  The peer failed at connection setup, before a BitTorrent/metadata handshake.
- A 20-second tracker-only repeat received two addresses from the HTTPS
  tracker, which reported zero seeders and two leechers. Neither address
  connected. These results do not verify or disprove swarm counts reported
  by other trackers or the phone on a different path.
- Independent IPv4 DHT `find_node` requests to all three addresses resolved
  from rqbit's two bootstrap hostnames also received no replies. Separate
  sockets, one shared socket, and reversed shared-socket destination order each
  timed out. This does not identify the filtering layer or establish a phone
  diagnosis, but it does not reproduce the earlier tracker destination-pinning
  issue: there were no DHT replies to compare.
- Source inspection confirms DHT, TCP, uTP, and metadata exchange are enabled.
  DHT routing tables are not persisted. Peer exchange is supported after metadata
  resolves, but the magnet metadata reader ignores PEX messages. MSE/PE peer
  encryption and BEP 55 hole punching are not implemented in the pinned engine.
- The 90-second terminal failure is Sweep policy. Within an attempt, each unique
  peer endpoint is tried once; repeated announcements of that endpoint do not
  retry it. TCP/uTP racing ends at socket connection, so a subsequent BitTorrent
  handshake failure does not trigger a second attempt over the other transport.

Next work should distinguish discovery sources, socket setup, BitTorrent
handshakes, and metadata responses in the UI; persist validated DHT contacts;
and replace terminal metadata timeouts with cancellable retries using backoff.
Encrypted peer support and PEX during metadata acquisition are separate
compatibility improvements, not proven explanations for this failed connection.

`live_probe` now supports `SWEEP_PROBE_METADATA_ONLY=1`, which forces a paused
add and exits after resolution without requesting payload. It retains final
tracker results (including reported swarm counts), transport counters, and the
last peer error on add failure. Use `SWEEP_PROBE_DISCOVERY=dht|trackers|both`
and `SWEEP_PROBE_TRANSPORT=tcp|utp|both` to isolate paths. The CLI builds, all five
Rust tests pass, and a local fixture confirms metadata-only success with zero
peer connections and zero downloaded bytes. Probe logs are under the ignored
`BuildArtifacts/MetadataInvestigation/` directory.

## macOS Validation, October 3, 2026

On the original VPN connection, the supplied real-world magnet did not deliver
metadata or payload in rqbit.
During the initial pass, two direct UDP tracker checks succeeded and returned peers
(216 seeders / 114 leechers, and 129 seeders / 100 leechers at the time). rqbit found
peers and established TCP/uTP connections, but metadata handshakes timed out or
disconnected. An independent TCP BitTorrent handshake check against 24 returned
peers also failed: 22 timeouts and two refused connections. This does not establish
whether the underlying cause is the network path, peer compatibility, or an
engine defect. Some tracker and DHT bootstrap hostnames also failed DNS lookup.

The original Mac UI remained on “Adding…” and had no saved torrent record while
waiting. Quitting at that point lost the request. Changes from this pass:

- [x] Save a pending magnet before discovery and show it immediately in the list.
- [x] Pause explicitly cancels Rust discovery; Resume retries failures.
- [x] Bound discovery to 90 seconds and retain a visible per-torrent error.
- [x] Restore pending torrents independently; paused torrents stay paused without
  requiring network metadata.
- [x] Cache resolved `.torrent` bytes and restore selected files before resuming.
- [x] Reject stale polling results after user actions, and clean up late add results
  after removal.
- [x] Separate engine refresh, persistence, startup, and action errors; successful
  polling no longer erases an unrelated action error.
- [x] Report macOS engine startup failure instead of silently loading demo torrents.
- [x] Add an inspectable Session Health popover with the last engine response,
  pending operations, storage availability, and torrent error count.
- [x] Verify a synthetic 1 MiB loopback transfer byte-for-byte, cached metadata
  restoration, and Rust task cancellation in automated tests.
- [x] Verify the updated Mac UI: the pending row appears immediately, paused state
  survives relaunch, active discovery restarts on relaunch, and the 90-second
  timeout leaves a selected error row with Resume enabled.
- [x] Show discovery counters and the latest peer failure in Activity and Peers,
  plus actual tracker responses before metadata arrives. Retain the last attempt
  after timeout and stop active counts on pause.
- [x] Correct unresolved magnet announces: use a nonzero unknown-size sentinel
  instead of announcing `left=0` (a completed seed).
- [x] Correct encrypted-transport advertising. This rqbit revision has plaintext
  peer handshakes only; the previous compatibility patch incorrectly advertised
  `supportcrypto=1`. Both announce paths now send `supportcrypto=0`.

Follow-up control runs used Transmission 4.1.3 on the same Mac and network, with
fresh temporary configuration/data folders, no port mapping, and a 512 kB/s
limit. An encryption-preferred run resolved metadata in 9 seconds and downloaded
1,671,168 bytes by 24 seconds. All nine connected peers were encrypted; both peers
sending payload were encrypted. Another control run reached about 500 kB/s.
A separate fresh control preferring unencrypted connections had no connected
peers, metadata, or payload throughout its 102-second observation window.

Rqbit still failed after both announce corrections: 328 candidates were attempted,
all 328 failed, and no metadata arrived in 90 seconds. Supplying the control
client's resolved `.torrent` metadata directly also yielded no payload and no
live peers over a further 90-second transfer window. The local tracker/peer test
successfully resolves a magnet and transfers a synthetic 1 MiB payload, so the
basic protocol path works. This evidence prioritizes public-peer transport
compatibility rather than Swift state or a dead swarm. It does not prove whether
plaintext is blocked on the network path or rejected by those peers.

The discovery counters are session diagnostics, not persisted payload-peer
counts. Tracker failures and responses retain their timestamps. DHT bootstrap
health still needs a dedicated model. Protocol encryption signaling is described
in [libtorrent's settings reference](https://www.libtorrent.org/reference-Settings.html#announce_crypto_support).

Verification now includes 20 Swift tests and three Rust integration tests plus the UDP tracker regression test, both
Apple app builds, regeneration from an empty `BuildArtifacts/`, and application
of the full patch series to the pinned pristine rqbit sources.

After the user changed VPN connections, the same rqbit build resolved the magnet
from a fresh folder in about seven seconds and downloaded 8 MiB of verified
pieces seven seconds later. A fresh run from cached metadata also transferred
payload. No VPN settings or system routes were changed during these tests.
Plaintext peer transfers therefore work on the current path; the earlier result
does not establish that peer encryption is required by this swarm.

The live restoration test exposed a separate engine race: calling Resume while
rqbit is still checking files starts another initializer. One initializer can
leave the torrent paused while the internal intent flag says running. A
command-line reproduction stayed paused without payload; waiting for the initial
check before Resume fixes it. File selection now also waits for checking, so
restored selections can be applied while the torrent is paused.

- [x] Separate checked bytes from downloaded bytes across the bridge. Preserve
  the last saved payload count while checking, then accept the verified result,
  including a lower count if pieces are missing or corrupt.
- [x] Exercise immediate Resume after adding cached metadata and verify payload
  transfer from a local seed in the Rust integration test.
- [x] Expose per-session TCP/uTP connection attempts, successes, and failures by
  address family, DHT table sizes and outstanding requests, and live peers by
  transport. Socket connections do not imply completed BitTorrent handshakes.
- [x] Replace the raw “Live” label with Downloading, Connecting to peers, or
  Waiting for data.

Further isolation found a reproducible UDP routing issue on the current path.
Sending tracker connect requests to two distinct endpoints through one socket
produced transaction-matching replies from the **first** endpoint, even for the
second destination. Reversing destination order reversed the pinned endpoint.
The same behavior occurred with IPv4 sockets and IPv4-mapped IPv6 sockets.
Separate sockets reached both endpoints correctly. This is observed behavior of
the current network path; the VPN implementation and its internal policy were
not inspected or changed.

Rqbit multiplexed UDP trackers through one socket and matched replies by
transaction ID alone. Depending on which destination went first, this produced
all-timeout sessions or false “Working” results for unrelated trackers. The new
patch uses one socket per tracker endpoint and rejects replies from an unexpected
source. A deterministic loopback test covers both flow isolation and rejection
of foreign replies. With the patch, the previously failing TCP + trackers-only
fresh-magnet test resolved metadata and downloaded 11.6 MB within a few seconds.

The patched native Mac app restored the saved running transfer at 1,368,501,305
bytes and completed all 1,865,526,329 bytes. An independent read of the resulting
file verified all 890 SHA-1 piece hashes against the cached torrent metadata.
Paused restoration was also checked at 41.7% before resuming. The app was left
open with the completed transfer. macOS and iOS builds, 20 Swift tests, the three
Rust integration tests, the UDP tracker regression, and application of all eight
patches to pristine pinned sources passed.

The pre-fix isolation matrix is useful evidence, not a general VPN verdict:

| Probe | Observed stage |
| --- | --- |
| TCP + trackers, twice | All tracker paths failed before any peer attempt |
| uTP + trackers | 371 candidates, 371 attempts, zero connected uTP sockets, metadata timeout |
| TCP + DHT only | Three IPv4 DHT table entries, no peer candidates within 40 seconds |
| Independent UDP requests | One destination per socket worked; multiple destinations were pinned to the first |
| TCP + isolated tracker sockets, after fix | Metadata and verified payload succeeded |

The earlier count of 17 “Working” trackers was unreliable because response
source validation was missing. TCP transport is proven on this connection;
uTP and effective DHT peer discovery remain unverified. Both use shared UDP
sockets upstream and warrant the same flow-isolation investigation. No IPv6
route was available in the inspected routing table; zero IPv6 attempts should
not be read as an interoperability test.

Highest-priority remaining work:

1. **DHT/uTP routing and network failure stages.** Investigate per-destination UDP
   flows for DHT and uTP on relayed paths. Add DHT bootstrap resolution/query outcomes,
   per-torrent peer discovery sources, and separate connect/handshake/metadata
   failure counters. The new session transport counters and metadata errors help
   locate failures, but cannot by themselves attribute a failure to VPN filtering.
2. **Encrypted peer transport.** MSE/PE remains a compatibility feature worth
   implementing with independent-client tests. Successful plaintext transfers on
   the current connection mean it is not a prerequisite for this public swarm.
3. **Lifecycle and durable state.** Add graceful shutdown/flush, bounded retry
   policy, and failure-injection coverage for disk errors and concurrent commands.
   Reduce writes of transient speed/progress samples to SQLite. Pending magnets
   are now durable; `.torrent` file adds still wait in the add sheet.
4. **Mac interaction polish.** Validate sorting, multiple selection, keyboard
   actions, and dense layouts with several real torrents and long error messages.
   Keep pending, checking, paused, stalled, and failed states easy to distinguish.
5. **Platform consistency.** Shared startup and diagnostics now cover both apps.
   Continue simulator coverage for background interruptions, long idle periods,
   accessibility, and save destinations. Background mode and failures are now visible.

## iOS Validation, October 3, 2026

The project now uses one persistent simulator: **iPhone 17 Pro Max, iOS 26.0**.
Its local UDID and reuse instructions are recorded in `AGENTS.md`. Keep its app
data across builds so updates and restoration remain part of normal testing.

- [x] Build and run the Rust-backed iOS app in Simulator.
- [x] Download the real-world magnet from an empty app session. Independently
  verify the 1,865,526,329-byte payload against all 890 torrent piece hashes.
- [x] Preserve completed and paused transfers across forced relaunches.
- [x] Add a magnet with Start Paused and relaunch before metadata exists. It
  remains paused, with no cached metadata or payload, until explicitly resumed.
- [x] Relaunch during metadata discovery and restart discovery from the saved source.
- [x] Interrupt a running transfer at 168,930,361 bytes; restore its 9.1% payload
  progress while checking files, then resume downloading to completion.
- [x] Install updated builds over the app. Simulator actually changed the data
  container UUID; rebased download paths found the existing completed payload.
- [x] Open every inspector section, inspect file locations, and present the
  native file share sheet. Verify deletion removes this test's record and payload.
- [x] Show malformed-magnet errors inside the Add sheet without dismissing it.
- [x] Remove a redundant row tap gesture that prevented inspector navigation.
- [x] Keep inspector actions tied to the displayed torrent after another magnet
  changes global selection. Verify with two torrents; retain the original target
  in deletion confirmations and remove the temporary paused test record afterward.
- [x] Share real startup failure handling, pause/resume/retry decisions, status
  descriptions, and file-location resolution in `SweepCore`. iOS no longer
  substitutes demo torrents when the engine or database fails.
- [x] Share progress bars, status icons, metadata discovery metrics, and Session
  Health in `SweepUI`, while retaining native platform navigation/presentation.
  iOS Health is accessible from the list and inspector and includes storage,
  refresh errors, DHT contacts, and TCP/uTP counters by address family.
- [x] Split the 851-line iOS inspector into section views and shared controls.
- [x] Pass 24 shared tests, macOS build, iOS Simulator build, and unsigned iOS
  device build. Added regression coverage for failed engine startup preserving
  saved transfers, separate storage failures, sandbox relocation, and safe nested
  file resolution. Retry uses the same action decision on both platforms.

The VPN and host routing were unchanged. Background execution and Live Activity
validation now have a dedicated simulator pass below. Other iOS priorities are
accessible layouts at large Dynamic Type sizes, multiple-file selection through
the UI, and save destinations. DHT/uTP and encryption gaps described above are
shared engine concerns, not separate iOS implementations.

## iOS Background Execution and Live Activities, October 3, 2026

The same iPhone 17 Pro Max simulator now has a repeatable local transfer fixture.
`Scripts/live_activity_fixture.py` provides a private torrent, loopback HTTP
tracker, metadata exchange, and a throttled TCP seed with deterministic contents:

```sh
python3 Scripts/live_activity_fixture.py /tmp/sweep-background-fixture
```

Open its `magnet.txt` link in Sweep. Edit `rate-kib.txt` while it runs to change
transfer speed; Ctrl-C stops the servers. Remove this test torrent and its data
before repeating a fresh-download test. The fixture requires no VPN changes.

Implemented:

- Continuous digital silence using a mixing playback session replaces the quiet
  tone and repeated finite-background-task renewal. Audio is stopped in the
  foreground, when disabled, and when no download work remains. Async starts
  cannot revive a session after cancellation. Interruption/reset handlers and
  visible errors replace swallowed failures.
- One lifecycle monitor publishes the final activity before releasing audio.
  It reads current background state rather than capturing the initial scene phase.
- Serialized ActivityKit requests/updates/end calls, adoption after relaunch,
  dismissal detection, foreground-only creation, and a 30-second cooldown after request failures.
  Health shows activity authorization/state, update time, background mode/state,
  errors, toggles, and an explicit Show Again action.
- Separate metadata, checking, waiting, downloading, paused, failed, and completed
  states. Pause and errors no longer manufacture 100% completion. Batch totals
  remain stable when individual downloads finish. Checking an old completed file
  during restoration does not replace the current paused activity.
- Unchanged active downloads receive a 10-second heartbeat with a 60-second stale
  deadline. Paused states have no stale deadline. Stale active views hide old rates
  and ask the user to reopen Sweep. Final completion remains for two minutes.
- A 14-point Lock Screen margin, system-managed background and semantic colors,
  clearer filename/progress/status/rate hierarchy, and a less crowded expanded
  Dynamic Island. The widget and application share the pure activity projection
  in `SweepActivities`; the extension still has no database/engine dependency.

Simulator evidence:

- Downloaded the synthetic 67,108,864-byte payload; independently verified all
  1,024 SHA-1 piece hashes. Completed while locked; the final activity showed
  Download complete at 100%, followed by background audio becoming idle.
- During a measured locked interval, saved payload grew from 42,139,648 to
  44,957,696 bytes between 20:22:55 and 20:24:22 local time. The transfer also
  continued through longer background intervals and resumed after a simulator
  restart and several app replacements/relaunches.
- Paused at 58,195,968 bytes (86.7%), force-relaunched, and verified the same
  paused activity remained after more than a minute. Resume continued the file.
- Cleared the activity on the Lock Screen. Health reported Dismissed without
  recreating it; Show Live Activity Again restored it. The activity toggle
  immediately ended/recreated the activity with Off/Active health states.
- Inspected actual Lock Screen cards in light and dark appearance:
  [downloading in dark mode](screenshots/live-activity-dark.jpg),
  [paused after relaunch](screenshots/live-activity-paused.jpg), and
  [completed](screenshots/live-activity-complete.jpg).
- Compact and expanded Dynamic Island content appeared in the system accessibility
  tree, but the simulator screenshot surface omitted the island contents. Its
  visual layout still needs a reliable capture; Lock Screen rendering was verified.
- All 33 Swift tests pass (24 core + 9 activity tests); macOS, iOS Simulator, and
  unsigned iOS device builds pass. Built app declares audio/location background
  modes and Live Activity support. Only the existing App Intents metadata warning
  remains. VPN and host network settings were unchanged.

Next work: interruption/media-service-reset injection, prolonged background and
idle tests, Dynamic Island capture, larger Dynamic Type layouts, and the legacy
location mode.

## Main List

### Two-Line Layout

- Embrace a two-line torrent row layout.
- Keep the title on the first line.
- Add a dynamic second line below the title, similar to Transmission:
  - current state
  - progress summary
  - error text when present
  - other concise contextual status
- Add a dedicated speed column showing:
  - download speed
  - upload speed
- Add a dedicated peers column showing peer counts in a compact up/down style.

### Configurable Columns

Add more columns and make column visibility configurable:

- [x] Size
- [x] ETA
- [x] Progress percentage
- [x] Remaining amount
- [x] Use native table column customization for visibility and ordering.
- [x] Support option-click progress cells to switch between detailed and taller bar modes.

### Row Shortcut Buttons

Add compact shortcut buttons near the title, inspired by Transmission:

- Pause or resume
- Show in Finder

### Status Icon

Show a compact status icon on the leading edge of each row:

- Blue down arrow for downloading
- Green up arrow for seeding or uploading
- Circle or stop symbol for paused or stopped
- Distinct error state

### Progress Bar

Replace the basic progress bar with a segmented availability bar:

- Represent downloaded pieces faithfully by segment.
- Represent currently downloading pieces distinctly.
- Represent available pieces distinctly when data is exposed by the engine.
- Change bar color based on torrent state:
  - downloading
  - completed
  - paused
  - error
- Reuse the same visual language in the files inspector.

## Toolbar

The toolbar should be compact and action-oriented.

- Remove the title from the toolbar.
- Add torrent file.
- Add URL or magnet link.
- Pause selected torrents.
- Resume selected torrents.
- Delete selected torrent from the list.
- Delete selected torrent and files, with confirmation.
- Show Info inspector.

## Sidebar

- Remove the sidebar.
- Sweep is targeting a low number of entries.
- Use filtering or grouping only when a real workflow requires it.

## Info Inspector

The Info inspector should remain a separate auxiliary macOS window with tabs.

- [x] Use a compact inspector layout aligned with the tab control.
- [x] Avoid nested containers and duplicate section headers.
- [x] Keep rows dense enough for a classic macOS utility panel.

### Trackers

- [x] Add tracker details similar to Transmission.
- [x] Show announce URL.
- [x] Show scrape URL when available.
- [x] Show status and last error.
- [x] Show last announce time.
- [x] Show next announce time.
- [x] Show seeders, leechers, and downloads when available.

### Files

- [x] Show all files in the torrent.
- [ ] Support full file priority tiers if rqbit exposes them.
- [x] Support download or skip.
- [x] Show per-file progress.
- [x] Use the same segmented progress style as the main list.

### Peers

- [x] Show peer IP addresses.
- [x] Show available feature flags.
- [ ] Show country flags or country code when resolved.
- [x] Show peer availability.
- [x] Show peer client when available.
- [x] Show transfer rates when available.

## Bottom Status Line

Add a compact bottom status line with aggregate session info:

- Total download speed
- Total upload speed
- Optional session status such as DHT, tracker, or port state when useful

## Infrastructure Tasks

These tasks should happen alongside the UI work so the interface is backed by
real torrent state rather than cosmetic placeholders.

### Engine Snapshot Contract

- [x] Add aggregate session transfer stats to the engine model.
- [x] Expose piece progress in a compact form that can drive segmented progress bars.
- [x] Expose per-file progress using the same progress model where possible.
- [x] Expose tracker details that are available from rqbit without hiding missing data.
- [x] Expose peer details with room for client, flags, country, and availability.
- [x] Add live tracker announce status once rqbit exposes it.
- [x] Add peer client, feature flags, and availability once rqbit exposes it or Sweep adds resolvers.
- [ ] Add peer country only if we choose a resolver that does not add avoidable dependency weight.

### Persistence

- [x] Store UI preferences with sqlite-data.
- [x] Persist visible torrent list columns.
- [x] Keep live transfer details out of persistent storage unless they are needed for
  restoring the session.

### Main Window Foundation

- [x] Remove the sidebar.
- [x] Keep the toolbar focused on transfer actions.
- [x] Drive bottom status from aggregate transfer stats.
- [x] Make optional columns configurable before adding more columns permanently.
- [x] Use two-line torrent rows with compact inline pause/reveal shortcuts.
- [x] Make speed and peers configurable columns.
- [x] Require confirmation before deleting downloaded files.
- [x] Smooth displayed transfer rates so speed and ETA are less erratic.
- [ ] Represent peer availability in the main progress bar once aggregate availability is exposed.

## Implementation Notes

- Prefer compact native AppKit and SwiftUI controls that match macOS conventions.
- Keep the main list optimized for scanning a small set of active torrents.
- Avoid adding visual density that does not improve torrent management.
- Expose missing rqbit data through the Rust bridge as needed instead of faking UI states.
- Make detailed columns configurable rather than permanently visible.
- Treat advanced progress bars as first-class torrent state, not decoration.
