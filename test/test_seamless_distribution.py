import hashlib
import json
import zipfile

import pytest

from tools import prepare_seamless_distribution as distribution


@pytest.fixture
def native_bundle(tmp_path, monkeypatch):
    app = tmp_path / "app"
    engine = app / "toolchain/tools/audio/seamless/loopfinder.dll"
    engine.parent.mkdir(parents=True)
    engine.write_bytes(b"known native engine")
    for name in distribution.RUNTIMES:
        (app / name).write_bytes(name.encode())
    archive = tmp_path / "source.zip"
    prefix = f"seamless-loop-music-{distribution.COMMIT}/"
    with zipfile.ZipFile(archive, "w") as source:
        for relative in (
            "LICENSE",
            "loopfinder/CMakeLists.txt",
            "loopfinder/include/loopfinder/loopfinder_api.h",
            "loopfinder/third_party/aubio/COPYING",
            "loopfinder/third_party/aubio/src/aubio.h",
            "loopfinder/third_party/aubio/src/config.h",
            "loopfinder/third_party/kiss_fft.c",
            "loopfinder/third_party/stb_vorbis.c",
            "loopfinder/third_party/dr_wav.h",
        ):
            source.writestr(prefix + relative, "source or license")
    dll_hash = distribution.sha256(engine)
    archive_hash = distribution.sha256(archive)
    notices = tmp_path / "notices"
    notices.mkdir()
    (notices / "license.txt").write_text("license\n", encoding="utf-8", newline="\n")
    (notices / "provenance.json").write_text(
        json.dumps(
            {
                "dll_sha256": dll_hash,
                "source_sha256": archive_hash,
                "notice_sha256": {"license.txt": hashlib.sha256(b"license\n").hexdigest()},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(distribution, "DLL_SHA256", dll_hash)
    monkeypatch.setattr(distribution, "SOURCE_SHA256", archive_hash)
    monkeypatch.setattr(distribution, "NOTICES", notices)
    return app, archive, engine, notices


def test_distribution_attaches_offline_source_and_native_runtime(native_bundle):
    app, archive, engine, _ = native_bundle
    before = engine.read_bytes()
    result = distribution.prepare(app, archive)
    destination = engine.parent / "distribution"
    assert (destination / distribution.SOURCE_NAME).read_bytes() == archive.read_bytes()
    assert (destination / "license.txt").read_text(encoding="utf-8") == "license\n"
    assert engine.read_bytes() == before
    for name in distribution.RUNTIMES:
        assert (engine.parent / name).read_bytes() == (app / name).read_bytes()
    assert result["engine_sha256"] == distribution.sha256(engine)


def test_distribution_accepts_windows_notice_line_endings(native_bundle):
    app, archive, engine, notices = native_bundle
    (notices / "license.txt").write_bytes(b"license\r\n")
    distribution.prepare(app, archive)
    assert (engine.parent / "distribution/license.txt").read_bytes() == b"license\r\n"


@pytest.mark.parametrize("component", ["dll", "archive", "notice", "runtime"])
def test_distribution_rejects_incomplete_inputs_before_writing(native_bundle, component):
    app, archive, engine, notices = native_bundle
    if component == "dll":
        engine.write_bytes(b"unverified engine version")
    elif component == "archive":
        archive.write_bytes(b"corrupted or unrelated source")
    elif component == "notice":
        (notices / "license.txt").write_text("changed license", encoding="utf-8")
    else:
        (app / "vcomp140.dll").unlink()
    with pytest.raises(ValueError):
        distribution.prepare(app, archive)
    assert not (engine.parent / "distribution").exists()
