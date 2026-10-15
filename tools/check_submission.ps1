param([switch]$SkipFormat)
$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
try {
    if (-not $SkipFormat) {
        uv run --locked pre-commit run --all-files --show-diff-on-failure
        if ($LASTEXITCODE -ne 0) { throw 'Formatting checks failed' }
    }
    uv run --locked python -m compileall -q backend tools test
    if ($LASTEXITCODE -ne 0) { throw 'Python compile checks failed' }
    uv run --locked pytest
    if ($LASTEXITCODE -ne 0) { throw 'Python tests failed' }
    uv run --locked python tools/test/create_mock_game.py --reset
    if ($LASTEXITCODE -ne 0) { throw 'Mock game generation failed' }
    uv run --locked pytest test/test_cli_mock_game.py::test_full_project_flow_builds_baseline_and_deploys_to_mock
    if ($LASTEXITCODE -ne 0) { throw 'Full-flow fixture generation failed' }
    Push-Location -LiteralPath app
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'Flutter package resolution failed' }
        flutter analyze --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed' }
        flutter test --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
    } finally { Pop-Location }
} finally { Pop-Location }
