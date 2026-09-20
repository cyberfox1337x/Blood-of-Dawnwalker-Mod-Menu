"""Malformed container and indexed-record tests; no game files or native codec required."""

from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "probes"))
from dawnwalker_save_format import (  # noqa: E402
    Chunk, HEADER, NODE, cyberfox1337x, encode_envelope, parse_envelope,
    parse_name_table, parse_node_table,
)

cyberfox1337x.function("dawnwalker_save_format_tests")


def fixture() -> tuple[bytes, bytes]:
    records = b"SN\x00\x00SN\x01\x00\x12\x34\x56\x78"
    names = b"\x04Root\x05Probe"
    name_table = b"NAME" + struct.pack("<I", len(names)) + names + b"NAME"
    name_offset = 36 + len(records)
    node_offset = name_offset + len(name_table)
    table = b"DWNT\x02\x00" + NODE.pack(1, 65535, 1, 36, len(records)) + NODE.pack(2, 65535, 65535, 40, 8) + b"DWNT"
    payload = records + name_table + table
    encoded = b"opaque-chunk-bytes"
    body = b"CHNK" + struct.pack("<II", len(encoded), len(payload)) + encoded
    header = HEADER.pack(b"DSAV", 36, 134, 5, 2, name_offset, node_offset, 36 + len(payload), len(body))
    contents = header + b"DSAV" + body + b"VASD" + struct.pack("<III", 1, len(encoded), len(payload)) + b"VASD"
    return contents, payload


class SaveEnvelopeTests(unittest.TestCase):
    def test_exact_unchanged_roundtrip_preserves_opaque_chunk_bytes(self):
        contents, _ = fixture()
        envelope = parse_envelope(contents)
        self.assertEqual(encode_envelope(envelope), contents)
        self.assertEqual(envelope.chunks[0].encoded, b"opaque-chunk-bytes")

    def test_recompression_changes_only_encoded_lengths_and_chunk_bytes(self):
        contents, _ = fixture()
        envelope = parse_envelope(contents)
        replacement = Chunk(b"different-compression", envelope.chunks[0].raw_size)
        rewritten = encode_envelope(envelope, (replacement,))
        self.assertEqual(rewritten[:28], contents[:28])
        self.assertEqual(parse_envelope(rewritten).chunks[0], replacement)

    def test_rejects_every_truncated_prefix(self):
        contents, _ = fixture()
        for end in range(len(contents)):
            with self.subTest(end=end), self.assertRaises(ValueError):
                parse_envelope(contents[:end])

    def test_refuses_unknown_version_mode_and_header(self):
        contents, _ = fixture()
        for offset, replacement in [(0, b"GVAS"), (4, struct.pack("<I", 37)), (8, b"\x87\x00"), (10, b"\x06\x00"), (12, struct.pack("<I", 3))]:
            changed = bytearray(contents)
            changed[offset:offset + len(replacement)] = replacement
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                parse_envelope(bytes(changed))

    def test_bounds_overflowing_section_offsets_before_decoding(self):
        contents, _ = fixture()
        for offset in [16, 20, 24, 28, 40, 44]:
            changed = bytearray(contents)
            struct.pack_into("<I", changed, offset, 0xFFFFFFFF)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                parse_envelope(bytes(changed))

    def test_rejects_missing_container_and_chunk_markers(self):
        contents, _ = fixture()
        for offset in [32, 36, len(contents) - 20, len(contents) - 4]:
            changed = bytearray(contents)
            changed[offset] ^= 0x40
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                parse_envelope(bytes(changed))

    def test_rejects_mismatched_directory_count_and_lengths(self):
        contents, _ = fixture()
        for offset in [len(contents) - 16, len(contents) - 12, len(contents) - 8]:
            changed = bytearray(contents)
            struct.pack_into("<I", changed, offset, 99)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                parse_envelope(bytes(changed))

    def test_rejects_trailing_bytes_and_changed_raw_partition(self):
        contents, _ = fixture()
        with self.assertRaises(ValueError):
            parse_envelope(contents + b"unexplained")
        envelope = parse_envelope(contents)
        with self.assertRaises(ValueError):
            encode_envelope(envelope, (Chunk(b"x", 1),))
        with self.assertRaises(ValueError):
            encode_envelope(envelope, ())


class SaveIndexedRecordTests(unittest.TestCase):
    def setUp(self):
        self.contents, self.payload = fixture()
        self.envelope = parse_envelope(self.contents)
        self.names = parse_name_table(self.payload, self.envelope)

    def test_resolves_names_and_bounded_node_records(self):
        self.assertEqual(self.names, ("Root", "Probe"))
        records = parse_node_table(self.payload, self.envelope, self.names)
        self.assertEqual(records[1].name, "Probe")
        self.assertEqual(records[1].absolute_offset, 40)
        self.assertEqual(records[1].size, 8)
        self.assertEqual(self.payload[4:12], b"SN\x01\x00\x12\x34\x56\x78")

    def test_rejects_bad_name_length_and_invalid_utf8(self):
        start = self.envelope.names_offset - 36
        for offset, replacement in [(start + 4, b"\xff\xff\xff\xff"), (start + 8, b"\xff"), (start + 9, b"\xff"), (start + 8, b"\x00")]:
            changed = bytearray(self.payload)
            changed[offset:offset + len(replacement)] = replacement
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                parse_name_table(bytes(changed), self.envelope)

    def test_rejects_invalid_name_id_record_bounds_and_cycle(self):
        record_start = self.envelope.nodes_offset - 36 + 6 + NODE.size
        mutations = [
            (record_start, struct.pack("<I", 99)),
            (record_start + 8, struct.pack("<I", 1)),
            (record_start + 12, struct.pack("<I", 999)),
            (record_start + 4, struct.pack("<H", 0)),
        ]
        for offset, replacement in mutations:
            changed = bytearray(self.payload)
            changed[offset:offset + len(replacement)] = replacement
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                parse_node_table(bytes(changed), self.envelope, self.names)

    def test_rejects_wrong_sn_index_and_truncated_node_directory(self):
        changed = bytearray(self.payload)
        changed[6] = 99
        with self.assertRaisesRegex(ValueError, "marker"):
            parse_node_table(bytes(changed), self.envelope, self.names)
        with self.assertRaisesRegex(ValueError, "length"):
            parse_node_table(self.payload[:-1], self.envelope, self.names)

    def test_rejects_wrong_dwnt_footer_and_directory_count(self):
        changed = bytearray(self.payload)
        changed[-1] ^= 1
        with self.assertRaisesRegex(ValueError, "markers"):
            parse_node_table(bytes(changed), self.envelope, self.names)
        changed = bytearray(self.payload)
        struct.pack_into("<H", changed, self.envelope.nodes_offset - 36 + 4, 1000)
        with self.assertRaisesRegex(ValueError, "count"):
            parse_node_table(bytes(changed), self.envelope, self.names)


if __name__ == "__main__":
    unittest.main()
