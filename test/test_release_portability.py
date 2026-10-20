import os
import subprocess
from pathlib import Path

import pytest

from tools.prepare_release_runtime import remove_managed_python_aliases


def directory_link(alias: Path, target: Path) -> None:
    if os.name == "nt":
        subprocess.run(
            ["cmd", "/c", "mklink", "/J", str(alias), str(target)],
            check=True,
            capture_output=True,
        )
    else:
        alias.symlink_to(target, target_is_directory=True)


def test_python_alias_removed_without_losing_versioned_interpreter(tmp_path):
    python_dir = tmp_path / "python"
    target = python_dir / "cpython-3.12.13-windows-x86_64-none"
    target.mkdir(parents=True)
    executable = target / "python.exe"
    executable.write_bytes(b"versioned interpreter")
    alias = python_dir / "cpython-3.12-windows-x86_64-none"
    directory_link(alias, target)

    remove_managed_python_aliases(python_dir)
    remove_managed_python_aliases(python_dir)

    assert not alias.exists()
    assert executable.read_bytes() == b"versioned interpreter"
    assert list(python_dir.iterdir()) == [target]


def test_python_link_outside_runtime_is_rejected_and_preserved(tmp_path):
    python_dir = tmp_path / "python"
    python_dir.mkdir()
    external = tmp_path / "external"
    external.mkdir()
    executable = external / "python.exe"
    executable.write_bytes(b"external interpreter")
    alias = python_dir / "cpython-3.12-windows-x86_64-none"
    directory_link(alias, external)

    with pytest.raises(ValueError, match="Unexpected Python runtime link"):
        remove_managed_python_aliases(python_dir)

    assert alias.exists()
    assert executable.read_bytes() == b"external interpreter"
