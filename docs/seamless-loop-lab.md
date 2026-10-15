# SeamlessLoopMusic experimental branch

This branch is based on `studio/layout-stable-20261014`. Stable sources, portable
runtime, preferences and project remain separate from the experiment.

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
- Bundled engine: local portable 1.11.0 `loopfinder.dll`
- SHA256: `c32f872e30d9c4ff17a322a1a2a2dda35c3ea488cd0bcfa10a8ebeb8ca871585`
- MIT license accompanies the bundled library.

The backend converts sources to a temporary float WAV at their original sample
rate. Returned PCM frame positions map directly to seconds; channel count does
not multiply timestamps. Source files are never rewritten. Native execution is
isolated in the existing cancellable CLI process. Cache identity includes source
path, size, modification time, native library hash and analysis parameters.

Missing libraries, unsupported or empty audio, invalid pairs, and no-result cases
produce visible errors while preserving markers and manual editing. Native loops
do not silently fall back to the legacy algorithm.
