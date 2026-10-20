"""Malformed bank sections must fail before reading adjacent metadata or audio."""

import struct
from test.test_bank_expansion import fsb

import pytest

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.fsb5 import parse_fsb5_bytes, rewrite_fsb5_names


@pytest.mark.parametrize(
    "section",
    [
        "short-headers",
        "extra-header",
        "extra-size",
        "short-offsets",
        "offset",
        "termination",
        "utf8",
    ],
)
def test_fsb_sections_are_bounded(section):
    raw = bytearray(fsb(2, names=True))
    headers, names = struct.unpack_from("<II", raw, 12)
    table = 60 + headers
    if section == "short-headers":
        struct.pack_into("<I", raw, 12, 7)
    elif section == "extra-header":
        struct.pack_into("<I", raw, 8, 1)
        struct.pack_into("<I", raw, 12, 8)
    elif section == "extra-size":
        struct.pack_into("<I", raw, 68, (11 << 25) | (0xFFFFFF << 1) | 1)
    elif section == "short-offsets":
        struct.pack_into("<I", raw, 16, 1)
    elif section == "offset":
        struct.pack_into("<I", raw, table, names)
    elif section == "termination":
        raw[table + 8 : table + names] = b"X" * (names - 8)
    else:
        raw[table + 8] = 255
    with pytest.raises(CliError):
        parse_fsb5_bytes(raw)
    with pytest.raises(CliError):
        rewrite_fsb5_names(raw, ["A", "B"])


def test_valid_named_bank_round_trips_unicode_names():
    renamed = rewrite_fsb5_names(fsb(2, names=True), ["歌曲 A", "Track B"])
    assert [sample.name for sample in parse_fsb5_bytes(renamed).samples] == ["歌曲 A", "Track B"]
