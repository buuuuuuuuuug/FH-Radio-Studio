import argparse
import contextlib
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from backend.fh_radio_studio_cli.cli import build_parser
from backend.fh_radio_studio_cli.common import CliError, md5_file
from backend.fh_radio_studio_cli.deploy import cmd_deploy_package
from backend.fh_radio_studio_cli.deployment_paths import (
    deployment_relative_path,
    effective_game_file,
)
from backend.fh_radio_studio_cli.game import audio_dir_for, effective_audio_dir_for
from backend.fh_radio_studio_cli.integrity import _apply_package_coverage


class DeploymentTargetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game = self.root / "game"
        self.package = self.root / "package"
        self.names = [
            "media/audio/RadioInfo_CN.xml",
            "media/audio/FMODBanks/R9_Tracks_CU1.assets.bank",
            "media/Stripped/StringTables/CHS.zip",
        ]
        original_files = []
        for name in self.names:
            original = self.game / name
            source = self.package / name
            original.parent.mkdir(parents=True, exist_ok=True)
            source.parent.mkdir(parents=True, exist_ok=True)
            original.write_bytes(b"original-" + name.encode())
            source.write_bytes(b"custom-" + name.encode())
            original_files.append(dict(install_relative_path=name, md5=md5_file(original)))
        self.baseline = self.root / "baseline.json"
        self.baseline.write_text(json.dumps({"files": original_files}), encoding="utf-8")
        (self.package / "fh_radio_studio_package_manifest.json").write_text("{}", encoding="utf-8")
        self.fingerprint = self.root / "fingerprint.json"

    def deploy(self, target="mediapc", yes=True, force=False):
        args = argparse.Namespace(
            game_dir=str(self.game),
            package_dir=str(self.package),
            target_root=target,
            baseline_manifest=str(self.baseline),
            last_applied_manifest=str(self.fingerprint),
            force=force,
            yes=yes,
            preferred_path=str(self.root / "UserPreferredLang"),
        )
        with contextlib.redirect_stdout(io.StringIO()):
            return cmd_deploy_package(args)

    def test_default_parser_and_path_mapping(self):
        args = build_parser().parse_args(["deploy-package", str(self.package)])
        self.assertEqual(args.target_root, "mediapc")
        self.assertEqual(
            deployment_relative_path(self.names[2]), "mediapc/Stripped/StringTables/CHS.zip"
        )
        for path in [
            "/media/audio/file",
            "media/audio/../../file",
            "media/C:/file",
            "mediapc/audio/file",
        ]:
            with self.assertRaises(CliError):
                deployment_relative_path(path)

    def test_overlay_leaves_all_original_files_untouched_and_records_real_paths(self):
        before = {n: (self.game / n).read_bytes() for n in self.names}
        self.assertEqual(self.deploy(), 0)
        for name in self.names:
            self.assertEqual((self.game / name).read_bytes(), before[name])
            self.assertEqual(
                (self.game / deployment_relative_path(name)).read_bytes(),
                (self.package / name).read_bytes(),
            )
        record = json.loads(self.fingerprint.read_text(encoding="utf-8"))
        self.assertEqual(record["deployment_target"], "mediapc")
        self.assertTrue(
            all(p["install_relative_path"].startswith("mediapc/") for p in record["package_files"])
        )

    def test_switch_to_original_removes_only_owned_overlays(self):
        self.deploy()
        (self.game / "mediapc/unrelated.txt").write_text("keep", encoding="utf-8")
        self.deploy("media")
        for name in self.names:
            self.assertEqual((self.game / name).read_bytes(), (self.package / name).read_bytes())
            self.assertFalse((self.game / deployment_relative_path(name)).exists())
        self.assertTrue((self.game / "mediapc/unrelated.txt").exists())
        self.assertEqual(json.loads(self.fingerprint.read_text())["deployment_target"], "media")

    def test_untrusted_overlay_fails_before_any_write(self):
        conflict = self.game / deployment_relative_path(self.names[2])
        conflict.parent.mkdir(parents=True)
        conflict.write_bytes(b"other-mod")
        with self.assertRaises(CliError):
            self.deploy()
        self.assertFalse((self.game / deployment_relative_path(self.names[0])).exists())
        self.assertEqual(conflict.read_bytes(), b"other-mod")

    def test_media_write_cannot_be_shadowed_by_an_unowned_override(self):
        conflict = self.game / deployment_relative_path(self.names[0])
        conflict.parent.mkdir(parents=True)
        conflict.write_bytes(b"other-mod")
        before = (self.game / self.names[0]).read_bytes()
        with self.assertRaises(CliError):
            self.deploy("media", force=True)
        self.assertEqual((self.game / self.names[0]).read_bytes(), before)
        self.assertEqual(conflict.read_bytes(), b"other-mod")

    def test_dry_run_and_effective_integrity(self):
        self.deploy(yes=False)
        self.assertFalse((self.game / "mediapc").exists())
        self.assertFalse(self.fingerprint.exists())
        self.deploy()
        name = self.names[0]
        source_md5 = md5_file(self.package / name)
        original_md5 = md5_file(self.game / name)
        plan = {"files": [dict(install_relative_path=name, md5=original_md5)]}
        _apply_package_coverage(plan, {name: source_md5}, game_dir=self.game)
        entry = plan["files"][0]
        self.assertEqual(entry["md5"], original_md5)
        self.assertEqual(entry["effective_md5"], source_md5)
        self.assertEqual(entry["effective_install_relative_path"], "mediapc/audio/RadioInfo_CN.xml")

    def test_playback_reads_overlay_but_pristine_reads_still_use_media(self):
        self.assertEqual(effective_audio_dir_for(self.game), self.game / "media/audio")
        self.deploy()
        self.assertEqual(effective_audio_dir_for(self.game), self.game / "mediapc/audio")
        self.assertEqual(audio_dir_for(self.game), self.game / "media/audio")
        self.assertEqual(
            effective_game_file(self.game, self.names[2]),
            self.game / "mediapc/Stripped/StringTables/CHS.zip",
        )


if __name__ == "__main__":
    unittest.main()
