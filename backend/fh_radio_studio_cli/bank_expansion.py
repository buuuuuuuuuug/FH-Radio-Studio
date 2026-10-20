"""Build expanded radio banks from trusted originals, with explicit sound indexing.

The format requirements are documented by the RaDX research project; this module
implements a full-bank rebuild rather than its single-track append procedure.
"""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path

from .common import CliError

BANK_SIZE_LIMIT = 2**31
MASK = 0xFFFFFFFF


def _rot(value: int, shift: int) -> int:
    return ((value << shift) | (value >> (32 - shift))) & MASK


def sound_hash(name: str) -> int:
    """Jenkins lookup3/hashlittle2, FMOD's sorted SoundName key."""
    data = name.encode("utf-8")
    a = b = c = (0xDEADBEEF + len(data)) & MASK
    pos = 0
    while len(data) - pos > 12:
        x, y, z = struct.unpack_from("<3I", data, pos)
        a, b, c = (a + x) & MASK, (b + y) & MASK, (c + z) & MASK
        a = ((a - c) & MASK) ^ _rot(c, 4)
        c = (c + b) & MASK
        b = ((b - a) & MASK) ^ _rot(a, 6)
        a = (a + c) & MASK
        c = ((c - b) & MASK) ^ _rot(b, 8)
        b = (b + a) & MASK
        a = ((a - c) & MASK) ^ _rot(c, 16)
        c = (c + b) & MASK
        b = ((b - a) & MASK) ^ _rot(a, 19)
        a = (a + c) & MASK
        c = ((c - b) & MASK) ^ _rot(b, 4)
        b = (b + a) & MASK
        pos += 12
    tail = data[pos:]
    if tail:
        a = (a + int.from_bytes(tail[:4], "little")) & MASK
        b = (b + int.from_bytes(tail[4:8], "little")) & MASK
        c = (c + int.from_bytes(tail[8:12], "little")) & MASK
        c = ((c ^ b) - _rot(b, 14)) & MASK
        a = ((a ^ c) - _rot(c, 11)) & MASK
        b = ((b ^ a) - _rot(a, 25)) & MASK
        c = ((c ^ b) - _rot(b, 16)) & MASK
        a = ((a ^ c) - _rot(c, 4)) & MASK
        b = ((b ^ a) - _rot(a, 14)) & MASK
        c = ((c ^ b) - _rot(b, 24)) & MASK
    return (b << 32) | c


def expanded_sound_name(radio: int, identity: str) -> str:
    token = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:24]
    return f"HZ6_CUSTOM_R{radio}_{token}"


def _chunks(raw: bytes, start: int, end: int):
    cursor = start
    while cursor < end:
        if cursor + 8 > end:
            raise CliError("Truncated RIFF chunk header")
        tag, size = struct.unpack_from("<4sI", raw, cursor)
        stop = cursor + 8 + size
        padded_stop = stop + (size & 1)
        if padded_stop > end:
            raise CliError(f"RIFF chunk {tag!r} exceeds its parent")
        yield tag, cursor, cursor + 8, stop
        cursor = padded_stop


def _find(raw: bytes, wanted: bytes):
    found = []

    def visit(start, end):
        for tag, offset, body, stop in _chunks(raw, start, end):
            if tag == wanted:
                found.append((offset, body, stop))
            if tag == b"LIST":
                visit(body + 4, stop)

    if raw[:4] != b"RIFF" or len(raw) < 12:
        raise CliError("Expected a RIFF radio bank")
    end = struct.unpack_from("<I", raw, 4)[0] + 8
    if end > len(raw):
        raise CliError("RIFF size exceeds file")
    visit(12, end)
    if len(found) != 1:
        raise CliError(f"Expected exactly one {wanted!r} chunk, got {len(found)}")
    return found[0]


def _rebuild_riff(raw: bytes, replacements: dict[bytes, bytes]) -> bytes:
    def build(start, end):
        out = bytearray()
        for tag, _, body, stop in _chunks(raw, start, end):
            payload = replacements.get(tag)
            if payload is None:
                payload = (
                    raw[body : body + 4] + build(body + 4, stop)
                    if tag == b"LIST"
                    else raw[body:stop]
                )
            out.extend(struct.pack("<4sI", tag, len(payload)))
            out.extend(payload)
            if len(payload) & 1:
                out.append(0)
        return bytes(out)

    old_end = struct.unpack_from("<I", raw, 4)[0] + 8
    payload = raw[8:12] + build(12, old_end)
    result = b"RIFF" + struct.pack("<I", len(payload)) + payload + raw[old_end:]
    if len(result) >= BANK_SIZE_LIMIT:
        raise CliError("Expanded radio bank must be smaller than 2 GiB")
    return result


def _fsb_records(fsb: bytes):
    if fsb[:4] != b"FSB5" or len(fsb) < 60:
        raise CliError("Invalid FSB5 header")
    count, headers, names, data_size = struct.unpack_from("<4I", fsb, 8)
    if count < 1 or 60 + headers + names + data_size > len(fsb):
        raise CliError("Invalid FSB5 sizes")
    records = []
    cursor = 60
    for _ in range(count):
        if cursor + 8 > 60 + headers:
            raise CliError("Truncated FSB5 sample")
        basic = fsb[cursor : cursor + 8]
        word = struct.unpack("<Q", basic)[0]
        more = word & 1
        cursor += 8
        chunks = {}
        while more:
            if cursor + 4 > 60 + headers:
                raise CliError("Truncated FSB5 metadata")
            extra = struct.unpack_from("<I", fsb, cursor)[0]
            size = (extra >> 1) & 0xFFFFFF
            kind = (extra >> 25) & 0x7F
            more = extra & 1
            cursor += 4
            if cursor + size > 60 + headers or kind in chunks:
                raise CliError("Invalid FSB5 metadata length or duplicate kind")
            chunks[kind] = fsb[cursor : cursor + size]
            cursor += size
        records.append((basic, chunks))
    return records, fsb[60 + headers + names : 60 + headers + names + data_size]


def _normalize_fsb(fsb: bytes, cue_template: bytes | None) -> bytes:
    records, audio = _fsb_records(fsb)
    header_records = bytearray()
    metadata_kinds = [4, 11, 13] if cue_template is not None else [11, 13]
    for basic, chunks in records:
        if 11 not in chunks or 13 not in chunks:
            raise CliError("Expansion requires Vorbis and peak-volume metadata")
        # FH6 content-update banks have no embedded cue chunk. Match the
        # original bank instead of requiring cues or copying them from another bank.
        chunks.pop(4, None)
        if cue_template is not None:
            chunks[4] = cue_template
        if set(chunks) != set(metadata_kinds):
            raise CliError(f"Unsupported FSB5 metadata kinds: {sorted(chunks)}")
        word = struct.unpack("<Q", basic)[0] | 1
        header_records.extend(struct.pack("<Q", word))
        for kind in metadata_kinds:
            payload = chunks[kind]
            extra = (kind << 25) | (len(payload) << 1) | (kind != 13)
            header_records.extend(struct.pack("<I", extra))
            header_records.extend(payload)
    header = bytearray(fsb[:60])
    struct.pack_into("<3I", header, 12, len(header_records), 0, len(audio))
    return bytes(header) + bytes(header_records) + audio


def _read_stbl(body: bytes):
    if len(body) < 16:
        raise CliError("Invalid STBL header")
    count = struct.unpack_from("<H", body, 8)[0]
    key_end = 10 + 8 * count
    if len(body) != 16 + 11 * count or struct.unpack_from("<H", body, key_end)[0] != count:
        raise CliError("Unexpected STBL layout")
    keys = struct.unpack_from(f"<{count}Q", body, 10)
    indices = [
        int.from_bytes(body[key_end + 2 + 3 * i : key_end + 5 + 3 * i], "little")
        for i in range(count)
    ]
    if list(keys) != sorted(set(keys)):
        raise CliError("STBL hashes must be strictly sorted")
    return dict(zip(keys, indices))


def rebuild_expanded_bank(
    original: Path, encoded: bytes, names: list[str], original_count: int, output: Path
) -> dict:
    raw = original.read_bytes()
    _, snd_body, snd_end = _find(raw, b"SND ")
    _, stbl_body, stbl_end = _find(raw, b"STBL")
    _, sndh_body, sndh_end = _find(raw, b"SNDH")
    fsb_offset = raw.find(b"FSB5", snd_body, snd_end)
    if fsb_offset < 0:
        raise CliError("Cannot expand an empty/stub bank")
    old_records, _ = _fsb_records(raw[fsb_offset:snd_end])
    if len(old_records) != original_count:
        raise CliError("Original FSB count changed during build")
    cues = old_records[0][1].get(4)
    if cues == b"":
        raise CliError(f"Original radio bank has an empty cue template: {original.name}")
    new_fsb = _normalize_fsb(encoded, cues)
    records, _ = _fsb_records(new_fsb)
    if len(names) != len(records) or len(set(names)) != len(names):
        raise CliError("Expanded FSB names/count mismatch")
    old_keys = _read_stbl(raw[stbl_body:stbl_end])
    new_keys = {sound_hash(name): i for i, name in enumerate(names)}
    if len(new_keys) != len(names):
        raise CliError("Expanded SoundName hash collision")
    # Original keys must continue to resolve, even when FSBank reorders records.
    if not set(old_keys).issubset(new_keys):
        raise CliError("Expanded bank would lose original SoundName mappings")
    if len(new_keys) > 65535:
        raise CliError("STBL index count exceeds 16-bit limit")
    pairs = sorted(new_keys.items())
    count = len(pairs)
    stbl = (
        raw[stbl_body : stbl_body + 8]
        + struct.pack("<H", count)
        + b"".join(struct.pack("<Q", k) for k, _ in pairs)
        + struct.pack("<H", count)
        + b"".join(i.to_bytes(3, "little") for _, i in pairs)
        + raw[stbl_end - 4 : stbl_end]
    )
    sndh = bytearray(raw[sndh_body:sndh_end])
    if len(sndh) != 12:
        raise CliError("Unsupported radio bank SNDH layout")
    struct.pack_into("<II", sndh, 4, 0, len(new_fsb))
    replacements = {
        b"STBL": stbl,
        b"SNDH": bytes(sndh),
        b"SND ": raw[snd_body:fsb_offset] + new_fsb,
    }
    result = _rebuild_riff(raw, replacements)
    _, body, stop = _find(result, b"SND ")
    final_offset = result.find(b"FSB5", body, stop)
    struct.pack_into("<I", sndh, 4, final_offset)
    replacements[b"SNDH"] = bytes(sndh)
    result = _rebuild_riff(raw, replacements)
    validate_expanded_bank_bytes(result, names)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result)
    return {
        "old_fsb5_size": snd_end - fsb_offset,
        "new_fsb5_size": len(new_fsb),
        "delta": len(result) - len(raw),
        "expanded_slots": len(names) - original_count,
        "stbl_entries": count,
        "expansion_validated": True,
    }


def validate_expanded_bank_bytes(raw: bytes, names: list[str]) -> None:
    _, snd, stop = _find(raw, b"SND ")
    _, stbl, stbl_stop = _find(raw, b"STBL")
    _, sndh, _ = _find(raw, b"SNDH")
    offset, size = struct.unpack_from("<II", raw, sndh + 4)
    if not snd <= offset < stop or raw[offset : offset + 4] != b"FSB5" or offset + size != stop:
        raise CliError("SNDH offset/length does not match the audio payload")
    records, audio = _fsb_records(raw[offset : offset + size])
    if len(records) != len(names):
        raise CliError("Expanded bank record count mismatch")
    mappings = _read_stbl(raw[stbl:stbl_stop])
    for i, ((basic, chunks), name) in enumerate(zip(records, names)):
        if mappings.get(sound_hash(name)) != i or list(chunks) not in ([4, 11, 13], [11, 13]):
            raise CliError("Expanded sound lookup or metadata order mismatch")
        data_offset = ((struct.unpack("<Q", basic)[0] >> 6) & 0xFFFFFFF) * 16
        if data_offset >= len(audio):
            raise CliError("Expanded sample data offset is outside audio payload")
    if len(raw) >= BANK_SIZE_LIMIT:
        raise CliError("Expanded bank exceeds the 2 GiB limit")
