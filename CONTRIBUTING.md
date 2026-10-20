# Contributing

Read [the development guide](docs/development.md) for setup, architecture,
data contracts and the repository's commit-message format.

## Contribution workflow

1. Fork the upstream repository if you do not have write access.
2. Create a branch for one coherent change. Keep generated projects, personal
   audio, model caches, runtime environments and delivery archives outside Git.
3. Reproduce the problem with a focused test, then make the smallest change
   that addresses its cause. Preserve existing project data and public contracts.
4. Run the checks below and document any checks that require unavailable tools
   or models. Use mock game files; never run destructive tests against a real
   game installation or a personal project.
5. Review the diff, including new files, and create commits using the format
   `[type][scope] summary`. Fix commits include `Root cause:` and `Fix:` paragraphs.
6. Push the branch to your own fork when ready, then open a pull request against
   the upstream branch agreed with the maintainer. Explain the user-visible
   behavior, validation and relevant limitations; respond to review on that branch.

Creating a fork, committing, pushing, opening a pull request and publishing a
release are separate actions. Check the remote owner and target branch before
performing any remote action.

## Required local checks

From the repository root, with `uv`, Python 3.12 and Flutter available:

```powershell
uv sync --locked
.\tools\check_submission.ps1
```

The check script runs formatting, Python tests, fixture generation, Flutter
analysis and Flutter tests. Fixture generation must precede the catalog and
screen tests. For focused development, use the commands in the development guide.

Native encoding, audio playback and optional AI models require additional local
tools. State exactly which real integrations were exercised; passing mocked tests
does not establish in-game compatibility or audio quality.

## Architectural boundaries

- The Python CLI owns game formats, audio processing, manifests and deployment.
- Flutter owns presentation, editor drafts and UI state. Use structured CLI
  results and the centralized `UvRuntime` process helpers.
- A cancelled or superseded task must not update a new project or a disposed UI.
- Validate complete input before replacing saved data. Keep temporary output
  separate until publication succeeds, and preserve the last complete result.

GitHub's [contribution walkthrough](https://docs.github.com/en/get-started/exploring-projects-on-github/contributing-to-a-project)
explains forks, branches, commits, pushes and pull requests.
