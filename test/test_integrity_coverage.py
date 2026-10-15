from backend.fh_radio_studio_cli.common import md5_file
from backend.fh_radio_studio_cli.integrity import _apply_package_coverage


def test_unchanged_package_is_reported_as_original():
    plan = {
        "files": [
            {
                "install_relative_path": "media/audio/RadioInfo_CN.xml",
                "md5": "original",
                "recorded_baseline_md5": "original",
                "baseline_status": "ok",
            }
        ]
    }
    _apply_package_coverage(plan, {"media/audio/RadioInfo_CN.xml": "original"})
    assert plan["files"][0]["package_diff_status"] == "unchanged"
    assert plan["files"][0]["coverage_status"] == "original"


def test_untrusted_overlay_is_not_reported_as_original(tmp_path):
    overlay = tmp_path / "mediapc/audio/RadioInfo_CN.xml"
    overlay.parent.mkdir(parents=True)
    overlay.write_bytes(b"other-mod")
    plan = {
        "files": [
            {
                "install_relative_path": "media/audio/RadioInfo_CN.xml",
                "md5": "original",
                "recorded_baseline_md5": "original",
                "baseline_status": "ok",
            }
        ]
    }
    _apply_package_coverage(plan, {"media/audio/RadioInfo_CN.xml": "original"}, game_dir=tmp_path)
    item = plan["files"][0]
    assert item["md5"] == "original"
    assert item["effective_md5"] == md5_file(overlay)
    assert item["coverage_status"] == "changed"


def test_custom_overlay_matching_package_is_covered(tmp_path):
    overlay = tmp_path / "mediapc/audio/RadioInfo_CN.xml"
    overlay.parent.mkdir(parents=True)
    overlay.write_bytes(b"our-package")
    plan = {
        "files": [
            {
                "install_relative_path": "media/audio/RadioInfo_CN.xml",
                "md5": "original",
                "recorded_baseline_md5": "original",
                "baseline_status": "ok",
            }
        ]
    }
    _apply_package_coverage(
        plan, {"media/audio/RadioInfo_CN.xml": md5_file(overlay)}, game_dir=tmp_path
    )
    assert plan["files"][0]["package_diff_status"] == "modified"
    assert plan["files"][0]["coverage_status"] == "covered"
