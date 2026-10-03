# Sweep Feature Backlog

Sweep should feel like a compact, native macOS torrent client with the care
and information density of classic clients such as Transmission, early uTorrent,
and eMule. The goal is to recover useful craft that many mainstream clients
lost: readable state, rich progress information, and direct controls without
turning the app into a dashboard.

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
