#Requires -Version 5.1
param(
  [Parameter(Mandatory=$true)][string]$BuildDirectory,
  [string]$SourceArchive = (Join-Path $PSScriptRoot 'SeamlessLoopMusic-8dfc00c8e9a6781babd0ba3a06e68228db5a3267-source.zip'),
  [string]$CMake = 'cmake'
)
$ErrorActionPreference = 'Stop'
$expected = '5b98a2eb1eeecf2e386116064005f4b6fb8657f74009eedd0101eb7607257cc7'
if ((Get-FileHash -LiteralPath $SourceArchive -Algorithm SHA256).Hash -ine $expected) { throw 'Source archive checksum mismatch.' }
if (Test-Path -LiteralPath $BuildDirectory) { throw 'Choose a new build directory; existing contents are preserved.' }
$destination = [IO.Path]::GetFullPath($BuildDirectory)
New-Item -ItemType Directory -Path $destination | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $SourceArchive).Path, (Join-Path $destination 'source'))
$source = Join-Path $destination 'source\seamless-loop-music-8dfc00c8e9a6781babd0ba3a06e68228db5a3267\loopfinder'
$build = Join-Path $destination 'build'
$env:TrackFileAccess = 'false'
& $CMake -S $source -B $build -G 'Visual Studio 17 2022' -A x64 -DBUILD_TEST=ON
if ($LASTEXITCODE -ne 0) { throw 'Native CMake configure failed.' }
& $CMake --build $build --config Release --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
Write-Output (Join-Path $build 'Release\loopfinder.dll')
