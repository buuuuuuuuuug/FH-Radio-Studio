import argparse
import json
import os
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
from xml.etree import ElementTree as ET

import pytest

from backend.fh_radio_studio_cli import package as pkg
from backend.fh_radio_studio_cli.bank_reuse import (
    atomic_package_build,
    file_sha256,
    load_previous_units,
    published_path,
    radio_fingerprint,
    reusable_bank,
    stamp_unit,
)
from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.file_lock import exclusive_file_lock


def previous_package(tmp_path, radio=9, fingerprint="input"):
    root = tmp_path / "current/package"
    bank = root / f"media/audio/FMODBanks/R{radio}.bank"
    bank.parent.mkdir(parents=True, exist_ok=True)
    bank.write_bytes(b"encoded-bank")
    unit = {
        "radio": radio,
        "target_bank_name": bank.name,
        "music": [{"title": "Song"}],
        "assignments": [{"slot_index": 0, "target_sound_name": "S"}],
    }
    stamp_unit(unit, fingerprint, bank)
    (root / "fh_radio_studio_package_manifest.json").write_text(
        json.dumps({"radios": [unit], "skip_bank": False}), encoding="utf-8"
    )
    return root, bank, unit


def test_verified_bank_is_copied_without_touching_previous(tmp_path):
    root, bank, unit = previous_package(tmp_path)
    old_hash = file_sha256(bank)
    previous = load_previous_units(root.parent)
    candidate = reusable_bank(previous, radio=9, bank_name=bank.name, fingerprint="input")
    result = candidate.copy_to(tmp_path / "new")
    assert result["bank_reused"] is True
    assert file_sha256(tmp_path / "new" / bank.name) == old_hash == file_sha256(bank)
    assert result["assignments"] == unit["assignments"]
    assert reusable_bank(previous, radio=9, bank_name=bank.name, fingerprint="changed") is None


@pytest.mark.parametrize("damage", ["bank", "missing", "manifest", "legacy", "skip"])
def test_unreliable_previous_output_is_never_reused(tmp_path, damage):
    root, bank, _ = previous_package(tmp_path)
    manifest = root / "fh_radio_studio_package_manifest.json"
    data = json.loads(manifest.read_text())
    if damage == "bank":
        bank.write_bytes(b"corrupt-bank")
    elif damage == "missing":
        bank.unlink()
    elif damage == "manifest":
        data["radios"][0]["music"][0]["title"] = "Edited"
    elif damage == "legacy":
        data["radios"][0].pop("bank_build")
    elif damage == "skip":
        data["skip_bank"] = True
    manifest.write_text(json.dumps(data))
    assert (
        reusable_bank(
            load_previous_units(root.parent), radio=9, bank_name=bank.name, fingerprint="input"
        )
        is None
    )


def test_source_content_changes_even_with_identical_stat_invalidate(tmp_path):
    source = tmp_path / "source.wav"
    source.write_bytes(b"aaa")
    stat = source.stat()
    bank = tmp_path / "original.bank"
    bank.write_bytes(b"bank")

    def fingerprint():
        return radio_fingerprint(
            radio=9,
            source_bank=bank,
            target_names=["S"],
            tracks=[{"sha256": file_sha256(source)}],
            settings={"quality": 50},
            engine="engine",
        )

    before = fingerprint()
    source.write_bytes(b"bbb")
    os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns))
    assert fingerprint() != before


@pytest.mark.parametrize("failure", ["exception", "return", "missing-manifest"])
def test_failed_build_preserves_old_package_and_cleans_owned_staging(tmp_path, failure):
    root, bank, _ = previous_package(tmp_path)
    before = file_sha256(bank)

    @atomic_package_build
    def build(args):
        assert bank.is_file()
        assert args.reuse_package == str(root.parent)
        (Path(args.out_dir) / "partial").write_text("partial")
        if failure == "exception":
            raise CliError("encoding failed")
        return 1 if failure == "return" else 0

    args = argparse.Namespace(out_dir=str(root.parent))
    if failure == "return":
        assert build(args) == 1
    else:
        with pytest.raises(CliError):
            build(args)
    assert file_sha256(bank) == before
    assert not list(tmp_path.glob(".current-*"))
    assert args.out_dir == str(root.parent)


def test_successful_build_publishes_only_when_complete(tmp_path):
    root, bank, _ = previous_package(tmp_path)

    @atomic_package_build
    def build(args):
        assert bank.read_bytes() == b"encoded-bank"
        stage = Path(args.out_dir)
        new = stage / "package"
        new.mkdir()
        (new / "fh_radio_studio_package_manifest.json").write_text("{}")
        (new / "new.bank").write_bytes(b"new-bank")
        assert published_path(args, new / "new.bank") == root / "new.bank"
        return 0

    assert build(argparse.Namespace(out_dir=str(root.parent))) == 0
    assert (root / "new.bank").read_bytes() == b"new-bank"
    assert not list(tmp_path.glob(".current-*"))


def test_does_not_replace_an_unrelated_directory(tmp_path):
    target = tmp_path / "sources"
    target.mkdir()
    (target / "song.wav").write_bytes(b"audio")

    @atomic_package_build
    def build(args):
        raise AssertionError("must not run")

    with pytest.raises(CliError):
        build(argparse.Namespace(out_dir=str(target)))
    assert (target / "song.wav").read_bytes() == b"audio"


def test_only_changed_radio_is_selected_for_rebuild(tmp_path, monkeypatch):
    source_a = tmp_path / "a.wav"
    source_a.write_bytes(b"audio-a")
    source_b = tmp_path / "b.wav"
    source_b.write_bytes(b"audio-b")
    bank_a = tmp_path / "R1.bank"
    bank_a.write_bytes(b"bank-a")
    bank_b = tmp_path / "R2.bank"
    bank_b.write_bytes(b"bank-b")
    groups = [{"radio": 1, "sources": [source_a]}, {"radio": 2, "sources": [source_b]}]
    args = argparse.Namespace(
        skip_bank=False,
        reuse_package=None,
        bank=None,
        baseline_manifest=None,
        quality=50,
        bpm="0",
        expand_slots=False,
        loudness_offset_lu=0,
    )
    monkeypatch.setattr(pkg, "engine_signature", lambda *a: "engine")
    monkeypatch.setattr(pkg, "_project_dir_for_args", lambda *a: None)
    monkeypatch.setattr(
        pkg, "find_station", lambda root, radio: ET.Element("RadioStation", Number=str(radio))
    )
    monkeypatch.setattr(
        pkg,
        "resolve_target_bank_for_station",
        lambda audio, station, radio, bank: bank_a if radio == 1 else bank_b,
    )
    monkeypatch.setattr(pkg, "parse_fsb5", lambda bank: SimpleNamespace(num_samples=1))
    monkeypatch.setattr(pkg, "target_names_for_bank", lambda *a: ["S"])
    monkeypatch.setattr(pkg, "guess_metadata", lambda path: ("Artist", path.stem))
    monkeypatch.setattr(pkg, "timing_override_for", lambda data, path, **kw: data.get(path.name))
    initial, _ = pkg._plan_radio_bank_reuse(args, tmp_path, None, groups, {}, {}, None, None)
    root = tmp_path / "prior/package"
    banks = root / "media/audio/FMODBanks"
    banks.mkdir(parents=True)
    units = []
    for radio in [1, 2]:
        bank = banks / f"R{radio}.bank"
        bank.write_bytes(b"encoded")
        unit = {"radio": radio, "target_bank_name": bank.name, "music": [], "assignments": []}
        stamp_unit(unit, initial[radio], bank)
        units.append(unit)
    (root / "fh_radio_studio_package_manifest.json").write_text(json.dumps({"radios": units}))
    args.reuse_package = str(root.parent)
    _, reused = pkg._plan_radio_bank_reuse(args, tmp_path, None, groups, {}, {}, None, None)
    assert set(reused) == {1, 2}
    _, reused = pkg._plan_radio_bank_reuse(
        args, tmp_path, None, groups, {"b.wav": {"markers_sec": {"TrackDrop": 1}}}, {}, None, None
    )
    assert set(reused) == {1}
    args.quality = 60
    _, reused = pkg._plan_radio_bank_reuse(args, tmp_path, None, groups, {}, {}, None, None)
    assert reused == {}
    args.quality = 50
    args.expand_slots = True
    _, reused = pkg._plan_radio_bank_reuse(args, tmp_path, None, groups, {}, {}, None, None)
    assert reused == {}
    args.expand_slots = False
    _, reused = pkg._plan_radio_bank_reuse(
        args, tmp_path, None, groups, {}, {"safe_min_lufs": -12}, None, None
    )
    assert reused == {}
    assert (
        pkg._build_radio_package_units_from_plan(
            args,
            tmp_path,
            tmp_path,
            None,
            [],
            tmp_path,
            tmp_path,
            tmp_path,
            tmp_path,
            None,
            None,
            {},
            {},
            {},
            None,
        )
        == []
    )


def test_publication_rename_failure_rolls_back_old_package(tmp_path, monkeypatch):
    root, bank, _ = previous_package(tmp_path)
    original_rename = Path.rename

    def rename(path, destination):
        if path.name.startswith(".current-building-"):
            raise OSError("simulated publish failure")
        return original_rename(path, destination)

    monkeypatch.setattr(Path, "rename", rename)

    @atomic_package_build
    def build(args):
        package = Path(args.out_dir) / "package"
        package.mkdir()
        (package / "fh_radio_studio_package_manifest.json").write_text("{}")
        return 0

    with pytest.raises(CliError, match="已保留"):
        build(argparse.Namespace(out_dir=str(root.parent)))
    assert bank.read_bytes() == b"encoded-bank"
    from backend.fh_radio_studio_cli.package_publication import completed_packages

    ready = completed_packages(root.parent)
    assert len(ready) == 1
    assert (ready[0] / "package/fh_radio_studio_package_manifest.json").is_file()


def test_previous_package_accepts_all_supported_path_forms(tmp_path):
    root, bank, _ = previous_package(tmp_path)
    for path in [root.parent, root, root / "fh_radio_studio_package_manifest.json"]:
        assert (
            reusable_bank(
                load_previous_units(path), radio=9, bank_name=bank.name, fingerprint="input"
            )
            is not None
        )


@pytest.mark.parametrize("radios", [None, 7, "invalid", {}])
def test_malformed_optional_reuse_list_falls_back_to_rebuilding(tmp_path, radios):
    path = tmp_path / "fh_radio_studio_package_manifest.json"
    path.write_text(json.dumps({"radios": radios}), encoding="utf-8")
    assert load_previous_units(path) == []


def test_nonfinite_reuse_metadata_does_not_block_fresh_build(tmp_path):
    root, bank, unit = previous_package(tmp_path)
    unit["music"][0]["bpm"] = float("nan")
    path = root / "fh_radio_studio_package_manifest.json"
    path.write_text(json.dumps({"radios": [unit]}), encoding="utf-8")
    assert (
        reusable_bank(load_previous_units(root), radio=9, bank_name=bank.name, fingerprint="input")
        is None
    )


def test_concurrent_build_of_the_same_output_is_rejected_before_work_starts(tmp_path):
    root, old_bank, _ = previous_package(tmp_path)
    calls = []

    @atomic_package_build
    def build(args):
        calls.append(args.out_dir)
        return 1

    lock = root.parent.with_name(".current.build.lock")
    with exclusive_file_lock(lock):
        with pytest.raises(CliError, match="正在构建"):
            build(argparse.Namespace(out_dir=str(root.parent)))
    assert not calls
    assert old_bank.read_bytes() == b"encoded-bank"
    assert not list(tmp_path.glob(".current-*"))
    assert build(argparse.Namespace(out_dir=str(root.parent))) == 1
    assert len(calls) == 1


def test_business_timeout_is_not_misreported_as_another_build(tmp_path):
    @atomic_package_build
    def build(args):
        raise TimeoutError("audio analysis deadline")

    with pytest.raises(TimeoutError, match="audio analysis deadline"):
        build(argparse.Namespace(out_dir=str(tmp_path / "current")))
