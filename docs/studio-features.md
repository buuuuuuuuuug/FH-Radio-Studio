# Editing and playlist workflow

## Track configuration

Configure TD, PD, TL-A/TL-B and PL-A/PL-B in the song editor. Manual refinement
uses an independent undo history, saved-configuration restore and optional loop
suggestions. Both waveforms have Ctrl-wheel zoom and an overview for panning.
Playback pages the visible range near an edge instead of scrolling continuously.

Settings exposes one **loop combination key** (Alt by default). Hold it with the
existing beat/10ms/1ms adjustment keys to move both loop endpoints. Letter and
function keys are supported; collisions are rejected. Releasing the held key
stops repeat until the adjustment key is pressed again. All shortcut hints follow
custom settings. Previous/next song wraps and defaults to Shift+Up/Down.

PL may follow TL automatically, with per-song temporary override and one-time
synchronization. Preview defaults to one seam repetition with two seconds before
and after. Saved marker data remains separate from analysis suggestions.

## Library and playlists

Search by song, artist or filename, filter and sort consistently on both pages.
Drag library column boundaries within their minimum widths. Ctrl multi-select
and Shift range-select support batch assignment; double-click a custom track to
edit it. Ctrl+D opens the editor assignment dialog, where 1–9 selects a station.

Unfinished tracks may be assigned, but station cards highlight them and package
builds remain blocked until all required markers are confirmed. Capacity checks
apply when assigning and when disabling expansion. Playlist changes are drafts
until saved, support undo/redo and participate in the unsaved-changes prompt.

Station columns adapt automatically or use 2–6 columns when the window fits.
Height can be set manually from 160–1200, fit all stations or fit one row. One-row
mode waits for scrolling to stop before snapping. Appearance settings include
custom accent colors, page width and manual refinement width.

## Timing transfer

Import UTF-8 text/CSV/TSV/JSON or XLSX, up to 8 MB and 10,000 rows. Preview checks
unique song identity, marker order and track duration. Applying requires the same
input and project snapshot, and creates a backup before writing. Columns are:

```csv
Filename,Radio_station,TD,PD,TL-A,TL-B,PL-A,PL-B
song.wav,R1,0:12.000,2:40.000,0:30.000,2:20.000,,
```

Radio_station is optional and ignored unless station assignment is enabled.
Use R1–R9 (multiple stations separated by semicolons). Filename can match filename,
title, title_artist or artist_title; automatic mode requires a unique match.
Legacy TL1/TL2/PL1/PL2 headers are still accepted. Duplicate aliases are rejected.
Blank cells are allowed and incomplete groups are never confirmed; explicit
blanks clear existing values only when overwrite is enabled. Omitted columns
remain unchanged. Export uses the same headers and preserves partial data.

## Building packages

Quality is adjustable from 1–100, default 50. The panel lists the nine main radio
banks with individual and total size estimates. Vorbis is variable bitrate: the
estimate includes a separate conservative margin and cannot guarantee game
compatibility. Actual file size limits are checked during the build. Deployment
defaults to mediapc overlays; writing media is an explicit option with existing
ownership and integrity checks.

Audio conversion and loudness processing write directly to the first numbered
slot WAV. Repeated slots use hard links when available, with a copy fallback.
Each radio releases its WAV and FSB work files after its final bank passes
validation, while radios continue building in parallel. Unchanged banks remain
reusable from the completed package and manifest. Disk-space checks budget the
active radios, copy fallback, completed outputs and baseline completion files.
The explicit `--skip-bank` inspection mode retains slot WAVs.

## Sample positions and RadioInfo imports

Timing transfer accepts integer sample positions at a fixed 48000 Hz. CSV exports use the same columns for time and samples; choose the matching data
form when importing. The file import dialog also accepts RadioInfo XML directly.
Blank nodes remain incomplete; the existing overwrite, preview and backup rules apply.
RadioInfo XML imports read only R1–R9 Event playlists and uniquely match title/artist.
Optional XML station assignment updates only the Event draft and preserves FreeRoam.
Other sample rates and conflicting marker definitions are reported rather than converted.

See [the illustrated overview](../README.md) and
[complete changes and interchange rules](改动说明-详细版.md).
