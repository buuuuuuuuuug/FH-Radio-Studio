import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

from backend.fh_radio_studio_cli.bank_expansion import (
    _find,
    _fsb_records,
    _read_stbl,
    _rebuild_riff,
    expanded_sound_name,
    rebuild_expanded_bank,
    sound_hash,
    validate_expanded_bank_bytes,
)
from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.radio_xml import patch_package_xml_tree


def chunk(tag, payload):
    return struct.pack("<4sI", tag, len(payload)) + payload + b"\0" * (len(payload) & 1)


def fsb(count, names=False, cues=False, peak=True):
    records = bytearray()
    for i in range(count):
        records.extend(struct.pack("<Q", 1 | (8 << 1) | (1 << 5) | (i * 2 << 6) | (1000 << 34)))
        parts = ([(4, b"cue-template")] if cues else []) + [(11, b"vorbis")]
        if peak:
            parts.append((13, struct.pack("<f", 0.5)))
        for j, (kind, body) in enumerate(parts):
            records.extend(
                struct.pack("<I", (kind << 25) | (len(body) << 1) | (j + 1 < len(parts)))
            )
            records.extend(body)
    table = b""
    if names:
        data = b""
        offsets = []
        for i in range(count):
            offsets.append(4 * count + len(data))
            data += f"{i+1:04}".encode() + b"\0"
        table = struct.pack(f"<{count}I", *offsets) + data
    header = bytearray(60)
    struct.pack_into(
        "<4s6I", header, 0, b"FSB5", 1, count, len(records), len(table), count * 32, 15
    )
    return bytes(header) + records + table + bytes([123]) * count * 32


def bank(names):
    pairs = sorted((sound_hash(n), i) for i, n in enumerate(names))
    count = len(pairs)
    stbl = (
        struct.pack("<IiH", 1, 0, count)
        + b"".join(struct.pack("<Q", k) for k, _ in pairs)
        + struct.pack("<H", count)
        + b"".join(i.to_bytes(3, "little") for _, i in pairs)
        + struct.pack("<I", 4)
    )
    payload = fsb(count, cues=True)
    sndh = struct.pack("<3I", 524291, 0, len(payload))
    proj = b"PROJ" + chunk(b"SNDH", sndh) + chunk(b"STBL", stbl)
    body = b"FEV " + chunk(b"LIST", proj) + chunk(b"SND ", b"\0" * 16 + payload)
    raw = b"RIFF" + struct.pack("<I", len(body)) + body
    _, start, stop = _find(raw, b"SND ")
    sndh = struct.pack("<3I", 524291, raw.find(b"FSB5", start, stop), len(payload))
    return _rebuild_riff(raw, {b"SNDH": sndh})


class ExpansionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.old_names = ["HZ6_R9_TrackA", "HZ6_R9_TrackB"]
        self.original = self.root / "original.bank"
        self.original.write_bytes(bank(self.old_names))

    def tearDown(self):
        self.temp.cleanup()

    def build(self, names, filename="expanded.bank"):
        out = self.root / filename
        stats = rebuild_expanded_bank(self.original, fsb(len(names), names=True), names, 2, out)
        validate_expanded_bank_bytes(out.read_bytes(), names)
        return out, stats

    def test_odd_and_even_stbl_sizes(self):
        for count in [3, 4, 7, 8]:
            with self.subTest(count=count):
                names = self.old_names + [f"HZ6_CUSTOM_R9_{i}" for i in range(count - 2)]
                out, stats = self.build(names)
                raw = out.read_bytes()
                _, body, end = _find(raw, b"STBL")
                self.assertEqual(end - body, 16 + 11 * count)
                self.assertEqual(stats["expanded_slots"], count - 2)
                _, sb, se = _find(raw, b"SND ")
                records, _ = _fsb_records(raw[raw.find(b"FSB5", sb, se) : se])
                self.assertEqual(len(records), count)
                self.assertTrue(all(list(c) == [4, 11, 13] for _, c in records))

    def test_reordered_audio_indices(self):
        names = ["HZ6_CUSTOM_R9_NEW", *reversed(self.old_names)]
        out, _ = self.build(names)
        raw = out.read_bytes()
        _, b, e = _find(raw, b"STBL")
        table = _read_stbl(raw[b:e])
        self.assertEqual(table[sound_hash(self.old_names[0])], 2)
        self.assertEqual(table[sound_hash(self.old_names[1])], 1)

    def test_delete_then_rebuild_from_baseline(self):
        self.build(self.old_names + ["HZ6_CUSTOM_R9_NEW"])
        out, stats = self.build(self.old_names, "after_delete.bank")
        self.assertEqual(stats["expanded_slots"], 0)
        raw = out.read_bytes()
        _, b, e = _find(raw, b"STBL")
        self.assertNotIn(sound_hash("HZ6_CUSTOM_R9_NEW"), _read_stbl(raw[b:e]))

    def test_lost_original_mapping_rejected(self):
        with self.assertRaises(CliError):
            self.build(["different", self.old_names[1]])

    def test_missing_peak_metadata_rejected(self):
        with self.assertRaises(CliError):
            rebuild_expanded_bank(
                self.original,
                fsb(3, peak=False),
                self.old_names + ["extra"],
                2,
                self.root / "bad.bank",
            )

    def test_duplicate_sound_names_rejected(self):
        with self.assertRaises(CliError):
            self.build(self.old_names + [self.old_names[0]])

    def test_size_guard(self):
        with patch("backend.fh_radio_studio_cli.bank_expansion.BANK_SIZE_LIMIT", 100):
            with self.assertRaises(CliError):
                self.build(self.old_names + ["extra"])

    def test_stable_names_do_not_depend_on_order(self):
        self.assertEqual(expanded_sound_name(9, "track-key"), expanded_sound_name(9, "track-key"))
        self.assertNotEqual(
            expanded_sound_name(9, "track-key"), expanded_sound_name(8, "track-key")
        )

    def test_xml_sample_and_both_playlists(self):
        tree = ET.ElementTree(
            ET.fromstring(
                '<RadioInfo><RadioStations><RadioStation Number="9"><SampleList Type="Track"/>'
                '<PlayList Type="FreeRoam"/><PlayList Type="Event"/></RadioStation></RadioStations></RadioInfo>'
            )
        )
        assignments = []
        for i in range(3):
            assignments.append(
                {
                    "target_sound_name": f"new{i}",
                    "sample_length": 48000,
                    "sample_rate": 48000,
                    "display_name": f"歌 {i}",
                    "artist": "歌手",
                    "markers": {},
                    "bpm": "100",
                    "playlist_entry": True,
                    "playlist_types": ["FreeRoam", "Event"],
                    "playlist_slots": {"FreeRoam": i + 1, "Event": i + 1},
                }
            )
        package = {"radio": 9, "expansion_enabled": True, "assignments": assignments}
        stats = patch_package_xml_tree(tree, package, "only")
        self.assertEqual(stats["missing_samples"], 0)
        self.assertEqual(len(tree.findall(".//Sample")), 3)
        self.assertEqual(len(tree.findall(".//Entry")), 6)
        # Idempotence and deletion are critical when rebuilding an expanded project.
        patch_package_xml_tree(tree, package, "only")
        self.assertEqual(len(tree.findall(".//Sample")), 3)
        package["assignments"] = assignments[:2]
        patch_package_xml_tree(tree, package, "only")
        self.assertEqual(len(tree.findall(".//Entry")), 4)


if __name__ == "__main__":
    unittest.main()
