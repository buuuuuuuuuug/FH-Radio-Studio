"""Attach pinned native-engine source and notices to a Windows app bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path

COMMIT = "8dfc00c8e9a6781babd0ba3a06e68228db5a3267"
DLL_SHA256 = "c32f872e30d9c4ff17a322a1a2a2dda35c3ea488cd0bcfa10a8ebeb8ca871585"
SOURCE_SHA256 = "5b98a2eb1eeecf2e386116064005f4b6fb8657f74009eedd0101eb7607257cc7"
SOURCE_NAME = f"SeamlessLoopMusic-{COMMIT}-source.zip"
SOURCE_URL = f"https://codeload.github.com/CPUrising/seamless-loop-music/zip/{COMMIT}"
ROOT = Path(__file__).resolve().parents[1]
NOTICES = ROOT / "docs" / "licenses" / "seamless-loop-music"
RUNTIMES = ("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll", "vcomp140.dll")


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_inputs(engine: Path, archive: Path) -> None:
    if sha256(engine) != DLL_SHA256:
        raise ValueError("Unknown loopfinder.dll; update its provenance before packaging")
    if sha256(archive) != SOURCE_SHA256:
        raise ValueError("SeamlessLoopMusic source archive checksum mismatch")
    prefix = f"seamless-loop-music-{COMMIT}/"
    required = (
        "LICENSE",
        "loopfinder/CMakeLists.txt",
        "loopfinder/include/loopfinder/loopfinder_api.h",
        "loopfinder/third_party/aubio/COPYING",
        "loopfinder/third_party/aubio/src/aubio.h",
        "loopfinder/third_party/aubio/src/config.h",
        "loopfinder/third_party/kiss_fft.c",
        "loopfinder/third_party/stb_vorbis.c",
        "loopfinder/third_party/dr_wav.h",
    )
    with zipfile.ZipFile(archive) as source:
        for relative in required:
            if not source.read(prefix + relative):
                raise ValueError(f"Missing corresponding source: {relative}")


def prepare(app_dir: Path, archive: Path) -> dict:
    engine_dir = app_dir / "toolchain" / "tools" / "audio" / "seamless"
    engine = engine_dir / "loopfinder.dll"
    # Complete all checks before changing the bundle.
    verify_inputs(engine, archive)
    manifest = json.loads((NOTICES / "provenance.json").read_text(encoding="utf-8"))
    if manifest["dll_sha256"] != DLL_SHA256 or manifest["source_sha256"] != SOURCE_SHA256:
        raise ValueError("Native notices and pinned inputs disagree")
    for name, expected in manifest["notice_sha256"].items():
        if Path(name).name != name:
            raise ValueError(f"Invalid native notice filename: {name}")
        # Git checkouts may use CRLF on Windows; hash the same UTF-8/LF text.
        text = (NOTICES / name).read_text(encoding="utf-8")
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != expected:
            raise ValueError(f"Native notice checksum mismatch: {name}")
    for name in RUNTIMES:
        if not (app_dir / name).is_file():
            raise ValueError(f"Missing app-local Visual C++/OpenMP runtime: {name}")
    destination = engine_dir / "distribution"
    shutil.copytree(NOTICES, destination, dirs_exist_ok=True)
    shutil.copyfile(archive, destination / SOURCE_NAME)
    # Python loads the engine in a separate process. Keep its dependencies next
    # to the DLL instead of relying on the Flutter process or system installs.
    for name in RUNTIMES:
        destination_runtime = engine_dir / name
        if not destination_runtime.exists() or sha256(destination_runtime) != sha256(
            app_dir / name
        ):
            shutil.copyfile(app_dir / name, destination_runtime)
    result = {
        "source_commit": COMMIT,
        "engine_sha256": DLL_SHA256,
        "source_sha256": SOURCE_SHA256,
        "source_archive": f"distribution/{SOURCE_NAME}",
        "runtimes": {name: sha256(engine_dir / name) for name in RUNTIMES},
    }
    (engine_dir / "distribution-manifest.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-dir", type=Path, required=True)
    parser.add_argument("--source-archive", type=Path)
    args = parser.parse_args()
    archive = args.source_archive
    if archive is None:
        archive = ROOT / ".fh-radio-studio-dev" / "downloads" / SOURCE_NAME
        if not archive.exists():
            archive.parent.mkdir(parents=True, exist_ok=True)
            temporary = archive.with_suffix(".download")
            try:
                with urllib.request.urlopen(SOURCE_URL, timeout=90) as response:
                    with temporary.open("wb") as output:
                        shutil.copyfileobj(response, output)
                if sha256(temporary) != SOURCE_SHA256:
                    raise ValueError("Downloaded source archive checksum mismatch")
                temporary.replace(archive)
            finally:
                temporary.unlink(missing_ok=True)
    print(json.dumps(prepare(args.app_dir, archive), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
