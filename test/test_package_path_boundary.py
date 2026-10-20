import json

import pytest

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.package import complete_package_from_baseline


@pytest.mark.parametrize(
    "relative",
    [
        "../outside.txt",
        "../../outside.txt",
        "/outside.txt",
        "C:/outside.txt",
        "media/audio/file:stream",
    ],
)
def test_baseline_completion_cannot_write_outside_package(tmp_path, relative):
    package = tmp_path / "package"
    package.mkdir()
    outside = tmp_path / "outside.txt"
    outside.write_bytes(b"existing user data")
    manifest = tmp_path / "baseline_manifest.json"
    manifest.write_text(
        json.dumps({"files": [{"install_relative_path": relative}]}), encoding="utf-8"
    )
    with pytest.raises(CliError):
        complete_package_from_baseline(package, str(manifest))
    assert outside.read_bytes() == b"existing user data"
    assert list(package.iterdir()) == []
