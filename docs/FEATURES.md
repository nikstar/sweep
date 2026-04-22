# Sweep Feature Backlog

Sweep should feel like a compact, native macOS torrent client with the care
and information density of classic clients such as Transmission, early uTorrent,
and eMule. The goal is to recover useful craft that many mainstream clients
lost: readable state, rich progress information, and direct controls without
turning the app into a dashboard.

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

- Size
- ETA
- Progress percentage
- Remaining amount

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

### Trackers

- Add tracker details similar to Transmission.
- Show announce URL.
- Show scrape URL when available.
- Show status and last error.
- Show last announce time.
- Show next announce time.
- Show seeders, leechers, and downloads when available.

### Files

- Show all files in the torrent.
- Support file priority.
- Support download or skip.
- Show per-file progress.
- Use the same segmented progress style as the main list.

### Peers

- Show peer IP addresses.
- Show available feature flags.
- Show country flags or country code when resolved.
- Show peer availability.
- Show peer client when available.
- Show transfer rates when available.

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
- [ ] Add live tracker announce status once rqbit exposes it.
- [ ] Add peer client, country, and availability once rqbit exposes it or Sweep adds resolvers.

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

## Implementation Notes

- Prefer compact native AppKit and SwiftUI controls that match macOS conventions.
- Keep the main list optimized for scanning a small set of active torrents.
- Avoid adding visual density that does not improve torrent management.
- Expose missing rqbit data through the Rust bridge as needed instead of faking UI states.
- Make detailed columns configurable rather than permanently visible.
- Treat advanced progress bars as first-class torrent state, not decoration.
