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
- The SeamlessLoopMusic repository has an MIT license, but its native build
  also links third-party components. In the inspected source, aubio is linked
  statically and has a GPL-3.0 license file. The top-level MIT notice alone is
  not a complete redistribution notice for the native binary.
- See [source and distribution notes](third-party-notices.md). This repository
  does not include the native DLL; verify component notices and corresponding
  source requirements before preparing a public binary bundle.

The backend converts sources to a temporary float WAV at their original sample
rate. Returned PCM frame positions map directly to seconds; channel count does
not multiply timestamps. Source files are never rewritten. Native execution is
isolated in the existing cancellable CLI process. Cache identity includes source
path, size, modification time, native library hash and analysis parameters.

Missing libraries, unsupported or empty audio, invalid pairs, and no-result cases
produce visible errors while preserving markers and manual editing. Native loops
do not silently fall back to the legacy algorithm.
