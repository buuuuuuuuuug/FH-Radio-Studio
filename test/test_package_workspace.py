import argparse
import os
from pathlib import Path
from test.test_bank_expansion import bank
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.package import (
    _cleanup_package_audio_after_build,
    _require_package_workspace_space,
)
from backend.fh_radio_studio_cli.package_workspace import (
    cleanup_audio_workspace,
    finish_radio_audio,
    stage_wav,
)


def test_workspace_shortage_is_rejected_before_creating_audio(tmp_path):
    original = tmp_path / "original.bank"
    original.write_bytes(bank(["A", "B"]))
    out = tmp_path / "output"
    args = argparse.Namespace(out_dir=str(out), quality=50, bank=None, expand_slots=True)
    with (
        patch(
            "backend.fh_radio_studio_cli.package.read_track_metadata",
            return_value=SimpleNamespace(duration_sec=120),
        ),
        patch("backend.fh_radio_studio_cli.package.find_station"),
        patch(
            "backend.fh_radio_studio_cli.package.resolve_target_bank_for_station",
            return_value=original,
        ),
        patch(
            "backend.fh_radio_studio_cli.package.shutil.disk_usage",
            return_value=SimpleNamespace(free=0),
        ),
    ):
        with pytest.raises(CliError, match="磁盘空间不足"):
            _require_package_workspace_space(
                args, tmp_path, object(), [{"radio": 9, "sources": [tmp_path / "song.wav"]}]
            )
    assert not out.exists()


@pytest.mark.parametrize("fails", [False, True])
def test_audio_copies_are_removed_after_success_or_failure(tmp_path, fails):
    keep = tmp_path / "package/result.bank"
    keep.parent.mkdir()
    keep.write_bytes(b"package")
    encoded = tmp_path / "work/fsbank_out/result.fsb"
    encoded.parent.mkdir(parents=True)
    encoded.write_bytes(b"encoded")

    @_cleanup_package_audio_after_build
    def run(args):
        for folder in ["prepared", "fsbank_stage"]:
            path = Path(args.out_dir) / "work" / folder / "copy.wav"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"generated")
        if fails:
            raise CliError("original build failure")
        return 7

    args = argparse.Namespace(out_dir=str(tmp_path), skip_bank=False)
    if fails:
        with pytest.raises(CliError, match="original build failure"):
            run(args)
    else:
        assert run(args) == 7
    assert not (tmp_path / "work/prepared").exists()
    assert not (tmp_path / "work/fsbank_stage").exists()
    assert keep.read_bytes() == b"package"
    assert not encoded.exists()


def test_skip_bank_keeps_audio_for_inspection(tmp_path):
    @_cleanup_package_audio_after_build
    def run(args):
        path = tmp_path / "work/prepared/song.wav"
        path.parent.mkdir(parents=True)
        path.write_bytes(b"inspect")

    run(argparse.Namespace(out_dir=str(tmp_path), skip_bank=True))
    assert (tmp_path / "work/prepared/song.wav").read_bytes() == b"inspect"


def test_repeated_slot_links_generated_audio_without_touching_source(tmp_path):
    first = tmp_path / "0001.wav"
    repeated = tmp_path / "0002.wav"
    first.write_bytes(b"processed-pcm")
    stage_wav(first, first)
    stage_wav(first, repeated)
    assert os.path.samefile(first, repeated)
    repeated.unlink()
    assert first.read_bytes() == b"processed-pcm"


def test_unsupported_links_fall_back_to_an_independent_copy(tmp_path, monkeypatch):
    first = tmp_path / "0001.wav"
    repeated = tmp_path / "0002.wav"
    first.write_bytes(b"processed-pcm")

    def no_links(*args):
        raise OSError("hard links unsupported")

    monkeypatch.setattr("backend.fh_radio_studio_cli.package_workspace.os.link", no_links)
    stage_wav(first, repeated)
    assert not os.path.samefile(first, repeated)
    assert first.read_bytes() == repeated.read_bytes() == b"processed-pcm"


def test_staging_never_overwrites_an_existing_slot(tmp_path):
    first, occupied = tmp_path / "0001.wav", tmp_path / "0002.wav"
    first.write_bytes(b"new")
    occupied.write_bytes(b"existing")
    with pytest.raises(CliError, match="已存在"):
        stage_wav(first, occupied)
    assert occupied.read_bytes() == b"existing"


def test_radio_finishes_release_only_its_audio_after_bank_validation(tmp_path):
    stage = tmp_path / "work/fsbank_stage/R1"
    encoded = tmp_path / "work/fsbank_out/R1"
    other = tmp_path / "work/fsbank_stage/R2/0001.wav"
    other.parent.mkdir(parents=True)
    other.write_bytes(b"another worker")
    for path in [stage / "0001.wav", encoded / "0001.fsb"]:
        path.parent.mkdir(parents=True)
        path.write_bytes(b"transient")
    result = tmp_path / "package/R1.bank"
    result.parent.mkdir()
    result.write_bytes(bank(["A", "B"]))
    before = result.read_bytes()
    args = argparse.Namespace(out_dir=str(tmp_path), skip_bank=False)
    with pytest.raises(CliError, match="校验失败"):
        finish_radio_audio(args, stage, encoded, result, 3)
    assert stage.is_dir() and encoded.is_dir()
    finish_radio_audio(args, stage, encoded, result, 2)
    assert not stage.exists() and not encoded.exists()
    assert other.read_bytes() == b"another worker"
    assert result.read_bytes() == before


def test_cleanup_cannot_remove_audio_outside_its_workspace(tmp_path):
    original = tmp_path / "sources"
    original.mkdir()
    source = original / "song.wav"
    source.write_bytes(b"original")
    with pytest.raises(CliError, match="超出"):
        cleanup_audio_workspace(tmp_path, original)
    assert source.read_bytes() == b"original"


def test_truncated_final_bank_keeps_the_radio_workspace(tmp_path):
    stage, encoded = tmp_path / "work/stage/R1", tmp_path / "work/encoded/R1"
    for path in [stage, encoded]:
        path.mkdir(parents=True)
    result = tmp_path / "truncated.bank"
    result.write_bytes(bank(["A", "B"])[:-1])
    args = argparse.Namespace(out_dir=str(tmp_path), skip_bank=False)
    with pytest.raises(CliError):
        finish_radio_audio(args, stage, encoded, result, 2)
    assert stage.is_dir() and encoded.is_dir()


def test_direct_preparation_writes_numeric_slots_once(tmp_path, monkeypatch):
    from backend.fh_radio_studio_cli import package as pkg

    stage = tmp_path / "work/fsbank_stage/R1"
    sources = [tmp_path / "song-a.mp3", tmp_path / "song-b.mp3"]
    writes = []

    def prepare(source, destination, *args, **kwargs):
        writes.append((source, destination))
        destination.write_bytes(source.name.encode())
        return {}, {"sample_rate": 48000, "samples": 48000}, {}

    monkeypatch.setattr(pkg, "_metadata_cache_path_for_args", lambda args: None)
    monkeypatch.setattr(pkg, "_read_loudness_cache_entry", lambda *args: {"status": "ok"})
    monkeypatch.setattr(pkg, "_measure_loudness_cache_misses", lambda *args, **kw: {})
    monkeypatch.setattr(pkg, "build_custom_set_loudness_profile", lambda *args, **kw: {})
    monkeypatch.setattr(pkg, "prepare_loudness_matched_audio", prepare)
    monkeypatch.setattr(pkg, "guess_metadata", lambda source: ("Artist", source.stem))
    monkeypatch.setattr(pkg, "timing_override_for", lambda *args, **kw: {})
    monkeypatch.setattr(pkg, "_all_core_markers_overridden", lambda *args: True)
    monkeypatch.setattr(pkg, "build_markers", lambda *args: {})
    monkeypatch.setattr(pkg, "_track_key_for_package_source", lambda *args: None)
    monkeypatch.setattr(pkg, "_project_path_for_manifest", lambda args, path: str(path))
    args = argparse.Namespace(bpm="0", baseline_manifest=None, loudness_offset_lu=0)
    tracks = pkg.prepare_music_tracks(
        sources, args, stage, {}, None, loudness_envelope={"ready": True}, slot_filename_width=4
    )
    assert [path.name for _, path in writes] == ["0001.wav", "0002.wav"]
    assert len(tracks) == len(sources) == len(writes)
    assert not (tmp_path / "work/prepared").exists()
    assert (stage / "0001.wav").read_bytes() == b"song-a.mp3"
    assert (stage / "0002.wav").read_bytes() == b"song-b.mp3"


def test_workspace_budget_releases_finished_radios_and_budgets_copy_fallback(tmp_path):
    original = tmp_path / "original.bank"
    original.write_bytes(bank(["A", "B"]))
    args = argparse.Namespace(
        out_dir=str(tmp_path / "output"), quality=50, bank=None, expand_slots=False, skip_bank=False
    )
    groups = [{"radio": i, "sources": [tmp_path / f"song-{i}.wav"]} for i in [1, 2, 3]]
    # One active radio has two 1000-second PCM slots even if hard links fail:
    # ~384 MB PCM, plus all final banks + one active FSB and reserve: under 1 GB.
    with (
        patch(
            "backend.fh_radio_studio_cli.package.read_track_metadata",
            return_value=SimpleNamespace(duration_sec=1000),
        ),
        patch("backend.fh_radio_studio_cli.package.find_station"),
        patch(
            "backend.fh_radio_studio_cli.package.resolve_target_bank_for_station",
            return_value=original,
        ),
        patch("backend.fh_radio_studio_cli.package._radio_package_worker_count", return_value=1),
        patch(
            "backend.fh_radio_studio_cli.package.shutil.disk_usage",
            return_value=SimpleNamespace(free=1000 * 1024**2),
        ),
    ):
        _require_package_workspace_space(args, tmp_path, object(), groups)
        args.skip_bank = True
        with pytest.raises(CliError, match="磁盘空间不足"):
            _require_package_workspace_space(args, tmp_path, object(), groups)


def test_workspace_budget_includes_baseline_completion_without_counting_reused_banks_twice(
    tmp_path,
):
    import json

    baseline = tmp_path / "baseline.json"
    baseline.write_text(
        json.dumps(
            {
                "files": [
                    {
                        "install_relative_path": "media/audio/FMODBanks/R1.bank",
                        "size": 300 * 1024**2,
                    },
                    {
                        "install_relative_path": "media/Stripped/StringTables/CN.zip",
                        "size": 20 * 1024**2,
                    },
                ]
            }
        ),
        encoding="utf-8",
    )
    args = argparse.Namespace(out_dir=str(tmp_path), quality=50, baseline_manifest=str(baseline))
    with patch(
        "backend.fh_radio_studio_cli.package.shutil.disk_usage",
        return_value=SimpleNamespace(free=350 * 1024**2),
    ):
        with pytest.raises(CliError, match="磁盘空间不足"):
            _require_package_workspace_space(args, tmp_path, object(), [])
        _require_package_workspace_space(
            args, tmp_path, object(), [], reused_bytes=1024**2, reused_bank_names={"R1.bank"}
        )
