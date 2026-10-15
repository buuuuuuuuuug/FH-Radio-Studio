# Submission review

This review covers both the expansion branch and the SeamlessLoopMusic branch.
No real project, installed app, game file, music source or model download is an
input to the portable checks. Machine-specific delivery evidence is archived
outside the source tree. Git history is preserved; use a source archive when a
history-free handoff is needed.

## Correctness changes

| Area | Problem | Change |
| --- | --- | --- |
| Saved project data | Direct truncating writes could leave partial JSON. | One shared atomic UTF-8 writer uses private same-volume temporary files, flushes before rename and retries transient Windows sharing errors. |
| Invalid data | Failed reads could become empty replacement data. | Settings, timing save/remove and playlist save refuse malformed existing documents and preserve them. Projects needing migration are not overwritten with startup defaults. |
| Waveform cache | Concurrent writers shared a temporary name or could downgrade detailed data. | Independent temporary names plus a per-source read/merge/write queue preserve detailed envelopes. |
| File coverage | Newly calculated diff status was not passed to the coverage decision; overlay differences could look original. | Use the calculated diff and effective overlay hash consistently. |
| Shared radio capacity | Individual scenes could fit while their union exceeded the physical bank. | All assignment entry points check distinct sources across scenes; failed assignment leaves drafts unchanged. |
| Track identity | A name/artist collision could select an unrelated local file. | Assignment reconstruction uses the catalog source mapping and skips unresolved identities. Legacy and durable identities for the same file are deduplicated. |
| Timing import | Duplicate header aliases could silently overwrite fields; malformed XLSX indices could leak raw errors. | Reject ambiguous headers, bound input reads before parsing and report structured CLI failures. |
| Buffered preferences | Closing during a column resize could lose the latest width. | Flush pending column widths before controller disposal; ignore non-finite height updates. |
| Portability | Startup and CLI contained one developer's test-project paths and a test-only command veto. | Let the project picker/settings select projects; remove private restrictions from generic source. Installed local test copies are unchanged. |
| Import status | Turning off library navigation could hide an already active import. | Keep its existing progress button visible until the import completes. |

## Cleanup

- Consolidate iteration-specific delivery notes into `studio-features.md`.
- Remove local protection inventories, one-time edit/delivery scripts and three
  unused UI modules from the source tree, retaining an external local archive.
- Remove the placeholder test and redundant shortcut validation loop.
- Apply the repository's Python and Dart formatters and update stale assertions
  to the current display name, search label, explicit saved-playlist behavior,
  buffered preferences and explicit media deployment target.
- Add `tools/check_submission.ps1` and Flutter analysis to CI. Full-flow mock
  fixtures must be generated before catalog and screen integration tests.

## Validation and practical limits

See the delivery report accompanying this source for exact test counts, commit
IDs, logs and source archive hashes. New regression coverage exercises failed
serialization/rename, damaged saved documents, concurrent cache writes, detail
preservation, shared bank capacity, assignment rollback, source identity,
ambiguous headers and effective overlay status. Existing waveform, shortcut,
refinement, import/export, preview, layout and deployment tests are retained.

Tests use simulated game files and controlled audio; they do not prove the
resulting bank plays correctly inside FH6. Heavy AI model inference and native
audio listening are not revalidated by this source-only audit. There is no
project format migration or deliberate feature removal in this cleanup.

The existing synchronous catalog/XML reader remains an architectural boundary
for a future dedicated change: move its complete structured output to the CLI
and make loading asynchronous. This review removes its unsafe name-matching
fallback but does not attempt that broader provider/API migration.
