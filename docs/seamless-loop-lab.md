# LoopLab experimental engine integration

LoopLab integrates the SeamlessLoopMusic native engine as an optional experimental
feature. The source repository does not include a prepared portable runtime or
user projects; native dependencies must be provided separately.

Enable **SeamlessLoopMusic** in Overview / Basic settings. It replaces TL and PL
loop search. Manual mode decodes the waveform and invokes only the native loop
engine, without loading AI models. AI mode retains beat, structure and point
analysis while using the native loop candidates without legacy loop reranking.

Suggested pairs appear only in the right panel of manual loop refinement. They
are suggestions: select a pair, audition the B-to-A transition, adjust if needed,
then confirm and save. Existing confirmed markers are retained during analysis.
TL and PL get the same ranked suggestions; they remain separately editable unless
the existing automatic PL synchronization setting is enabled.

The matching percentage is the native algorithm's score, not a probability or a
guarantee of a musically seamless transition. Bar counts are not invented.

## Native dependency

- Upstream: https://github.com/CPUrising/seamless-loop-music
- ABI: `loopfinder/include/loopfinder/loopfinder_api.h`, `lf_analyze_file`
- Reference engine: portable 1.11.0 `loopfinder.dll` (not committed here)
- SHA256: `c32f872e30d9c4ff17a322a1a2a2dda35c3ea488cd0bcfa10a8ebeb8ca871585`
- Pinned corresponding source: upstream v1.11.0 commit
  `8dfc00c8e9a6781babd0ba3a06e68228db5a3267`. The official DLL hash matches the
  bundled reference. An unmodified source rebuild has the same executable
  `.text` section and matching loop endpoints in the recorded audio checks.
- Component notices, provenance and rebuild instructions are maintained in
  [native distribution materials](licenses/seamless-loop-music/README.md).
  They include aubio GPL-3.0-or-later, KissFFT BSD-3-Clause, and the applicable
  MIT/MIT-0 notices, rather than describing the entire DLL as MIT.
- `tools/build_release.ps1` attaches these notices and the complete pinned source
  ZIP next to the DLL. The packaging helper verifies the source and binary hashes
  and places the required app-local C++/OpenMP runtimes next to the native library.
- See [source and distribution notes](third-party-notices.md) for the separate
  FMOD SDK distribution question. Completing native-engine materials does not
  provide an FMOD redistribution grant or relicense the whole application.

The backend converts sources to a temporary float WAV at their original sample
rate. Returned PCM frame positions map directly to seconds; channel count does
not multiply timestamps. Source files are never rewritten. Native execution is
isolated in the existing cancellable CLI process. Cache identity includes source
path, size, modification time, native library hash and analysis parameters.

Missing libraries, unsupported or empty audio, invalid pairs, and no-result cases
produce visible errors while preserving markers and manual editing. Native loops
do not silently fall back to the legacy algorithm.
