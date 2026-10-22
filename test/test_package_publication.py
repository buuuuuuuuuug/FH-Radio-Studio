import argparse
import json
import os
from pathlib import Path

import pytest

from backend.fh_radio_studio_cli import package_publication as publication
from backend.fh_radio_studio_cli.bank_reuse import atomic_package_build
from backend.fh_radio_studio_cli.common import CliError


def package(path, contents):
    (path / "package").mkdir(parents=True)
    (path / publication.MANIFEST).write_text(json.dumps({"test": contents}))
    (path / "package/bank").write_text(contents)


def test_held_old_package_preserves_completed_new_package_and_retry_skips_build(
    tmp_path, monkeypatch
):
    target = tmp_path / "current"
    package(target, "old")
    original_rename = Path.rename
    original_replace = Path.replace
    calls = []

    def locked(path, destination):
        if path == target:
            raise PermissionError("directory held open")
        return original_rename(path, destination)

    monkeypatch.setattr(Path, "rename", locked)

    def file_locked(path, destination):
        if path == target / "package/bank":
            raise PermissionError("bank held open")
        return original_replace(path, destination)

    monkeypatch.setattr(Path, "replace", file_locked)
    monkeypatch.setattr(publication.time, "sleep", lambda _: None)

    @atomic_package_build
    def build(args):
        calls.append(1)
        package(Path(args.out_dir), "new")
        return 0

    with pytest.raises(CliError, match="无需重新编码"):
        build(argparse.Namespace(out_dir=str(target)))
    assert (target / "package/bank").read_text() == "old"
    ready = publication.completed_packages(target)
    assert len(ready) == 1
    assert (ready[0] / "package/bank").read_text() == "new"
    monkeypatch.setattr(Path, "rename", original_rename)
    monkeypatch.setattr(Path, "replace", original_replace)
    publication.cmd_publish_package(
        argparse.Namespace(out_dir=str(target), ready_dir=str(ready[0]))
    )
    assert (target / "package/bank").read_text() == "new"
    assert calls == [1]
    assert publication.completed_packages(target) == []


def test_transient_lock_is_retried_without_reencoding(tmp_path, monkeypatch):
    target = tmp_path / "current"
    package(target, "old")
    stage = tmp_path / ".current-building-test"
    package(stage, "new")
    publication.mark_complete(target, stage)
    original = Path.rename
    count = 0

    def rename(path, destination):
        nonlocal count
        if path == target:
            count += 1
            if count < 3:
                raise PermissionError("scanner")
        return original(path, destination)

    monkeypatch.setattr(Path, "rename", rename)
    monkeypatch.setattr(publication.time, "sleep", lambda _: None)
    publication.publish_completed(target, stage)
    assert count == 3
    assert (target / "package/bank").read_text() == "new"


def test_changed_manifest_and_unowned_stage_are_rejected(tmp_path):
    target = tmp_path / "current"
    stage = tmp_path / ".current-building-test"
    package(stage, "new")
    publication.mark_complete(target, stage)
    (stage / publication.MANIFEST).write_text("{}")
    with pytest.raises(CliError, match="已变化"):
        publication.publish_completed(target, stage)
    assert stage.exists()
    with pytest.raises(CliError, match="超出"):
        publication.publish_completed(target, tmp_path.parent / "unrelated")


def test_incomplete_failed_build_is_cleaned(tmp_path):
    target = tmp_path / "current"

    @atomic_package_build
    def build(args):
        (Path(args.out_dir) / "partial").write_text("partial")
        return 1

    assert build(argparse.Namespace(out_dir=str(target))) == 1
    assert not list(tmp_path.glob(".current-building-*"))


@pytest.mark.skipif(os.name != "nt", reason="Windows directory sharing semantics")
@pytest.mark.parametrize("subfolder", ["", "package"])
def test_real_windows_directory_handle_allows_publication_without_closing_folder(
    tmp_path, subfolder
):
    import ctypes
    from ctypes import wintypes

    target = tmp_path / "current"
    package(target, "old")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.DWORD,
        wintypes.DWORD,
        wintypes.LPVOID,
        wintypes.DWORD,
        wintypes.DWORD,
        wintypes.HANDLE,
    ]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    # Omit FILE_SHARE_DELETE to reproduce a directory held open by another program.
    handle = kernel.CreateFileW(str(target / subfolder), 0x80000000, 1, None, 3, 0x02000000, None)
    assert handle != wintypes.HANDLE(-1).value, ctypes.get_last_error()

    @atomic_package_build
    def build(args):
        package(Path(args.out_dir), "new")
        return 0

    try:
        assert build(argparse.Namespace(out_dir=str(target))) == 0
        assert (target / "package/bank").read_text() == "new"
    finally:
        kernel.CloseHandle(handle)


def test_directory_fallback_removes_obsolete_files_and_keeps_nested_folders(tmp_path, monkeypatch):
    target = tmp_path / "current"
    package(target, "old")
    (target / "obsolete").write_text("old")
    stage = tmp_path / ".current-building-test"
    package(stage, "new")
    (stage / "added").write_text("new file")
    publication.mark_complete(target, stage)
    original = Path.rename
    monkeypatch.setattr(publication.time, "sleep", lambda _: None)

    def held(path, destination):
        if path == target:
            raise PermissionError("folder is open")
        return original(path, destination)

    monkeypatch.setattr(Path, "rename", held)
    publication.publish_completed(target, stage)
    assert (target / "added").read_text() == "new file"
    assert not (target / "obsolete").exists()
    assert not stage.exists()
    assert (target / "package/bank").read_text() == "new"


def test_interrupted_inplace_publish_rolls_back_before_retry(tmp_path):
    from backend.fh_radio_studio_cli.package_transaction import journal_path, recover_inplace

    target = tmp_path / "current"
    package(target, "old")
    backup = tmp_path / ".current-previous-test"
    (backup / "package").mkdir(parents=True)
    (target / "package/bank").replace(backup / "package/bank")
    (target / "package/bank").write_text("partial new")
    (target / "added").write_text("partial new")
    journal_path(target).write_text(
        json.dumps(
            {
                "version": 1,
                "target": "current",
                "backup": backup.name,
                "old": ["package/bank", publication.MANIFEST],
                "new": ["package/bank", publication.MANIFEST, "added"],
            }
        )
    )
    recover_inplace(target)
    assert (target / "package/bank").read_text() == "old"
    assert not (target / "added").exists()
    assert not journal_path(target).exists()


def test_deferred_build_never_replaces_current_and_complete_stage_survives_cancel_cleanup(
    tmp_path, capsys
):
    target = tmp_path / "current"
    package(target, "old")

    @atomic_package_build
    def build(args):
        package(Path(args.out_dir), "new")
        return 0

    assert build(argparse.Namespace(out_dir=str(target), defer_publish=True)) == 0
    assert "FH_RADIO_STUDIO_PACKAGE_READY " in capsys.readouterr().out
    assert (target / "package/bank").read_text() == "old"
    ready = publication.completed_packages(target)[0]
    publication.cmd_discard_package_build(
        argparse.Namespace(out_dir=str(target), build_dir=str(ready))
    )
    assert ready.exists()
    publication.cmd_publish_package(argparse.Namespace(out_dir=str(target), ready_dir=str(ready)))
    assert (target / "package/bank").read_text() == "new"


def test_cancel_cleanup_only_removes_owned_incomplete_stage(tmp_path):
    target = tmp_path / "current"
    stage = tmp_path / ".current-building-test"
    stage.mkdir()
    (stage / "partial").write_text("partial")
    publication.cmd_discard_package_build(
        argparse.Namespace(out_dir=str(target), build_dir=str(stage))
    )
    assert not stage.exists()
    with pytest.raises(CliError):
        publication.cmd_discard_package_build(
            argparse.Namespace(out_dir=str(target), build_dir=str(tmp_path / "unrelated"))
        )


@pytest.mark.skipif(os.name != "nt", reason="Windows file sharing semantics")
def test_exclusively_held_bank_rolls_back_other_files_and_remains_retryable(tmp_path):
    import ctypes
    from ctypes import wintypes

    target = tmp_path / "current"
    package(target, "old")
    (target / "a-first").write_text("old first")
    stage = tmp_path / ".current-building-test"
    package(stage, "new")
    publication.mark_complete(target, stage)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.DWORD,
        wintypes.DWORD,
        wintypes.LPVOID,
        wintypes.DWORD,
        wintypes.DWORD,
        wintypes.HANDLE,
    ]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    folder = kernel.CreateFileW(str(target), 0x80000000, 1, None, 3, 0x02000000, None)
    bank = kernel.CreateFileW(str(target / "package/bank"), 0x80000000, 1, None, 3, 0, None)
    assert folder != wintypes.HANDLE(-1).value
    assert bank != wintypes.HANDLE(-1).value
    try:
        with pytest.raises(CliError, match="无需重新编码"):
            publication.publish_completed(target, stage)
        assert (target / "a-first").read_text() == "old first"
        assert (target / "package/bank").read_text() == "old"
        assert publication.completed_packages(target) == [stage]
    finally:
        kernel.CloseHandle(bank)
        kernel.CloseHandle(folder)
    publication.publish_completed(target, stage)
    assert (target / "package/bank").read_text() == "new"


def test_deployment_refuses_unfinished_publication(tmp_path):
    from backend.fh_radio_studio_cli.deploy import _deploy_package
    from backend.fh_radio_studio_cli.package_transaction import journal_path

    target = tmp_path / "current"
    package(target, "old")
    journal_path(target).write_text("{}")
    (target / "package/media").mkdir()
    with pytest.raises(CliError, match="正在替换"):
        _deploy_package(argparse.Namespace(package_dir=str(target)), tmp_path / "game")
