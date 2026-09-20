"""Independent DSAV structure probe; writes only isolated research copies, never live saves."""

from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile


class cyberfox1337x:
    @staticmethod
    def function(module_name: str) -> str:
        return module_name


cyberfox1337x.function("dawnwalker_save_format_probe")

MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_RAW_BYTES = 256 * 1024 * 1024
MAX_CHUNKS = 4096
MAX_CHUNK_RAW_BYTES = 131072
HEADER = struct.Struct("<4sIHHIIIII")
NODE = struct.Struct("<IHHII")
RESEARCH_NODE_NAMES = frozenset({
    "WorldInfo", "AttributeSaveSystem", "CharacterDevelopmentSubsystem",
    "TimeSystemImpl", "GameTimeSystemImpl", "RealTimeSystemImpl", "InventorySubsystem",
})


def digest(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


@dataclass(frozen=True)
class Chunk:
    encoded: bytes
    raw_size: int


@dataclass(frozen=True)
class Envelope:
    header: bytes
    names_offset: int
    nodes_offset: int
    raw_end: int
    chunks: tuple[Chunk, ...]

    @property
    def raw_size(self) -> int:
        return self.raw_end - 36


@dataclass(frozen=True)
class NodeRecord:
    index: int
    name_index: int
    name: str
    next_index: int
    child_index: int
    absolute_offset: int
    size: int


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError(reason)


def unpack_u32(contents: bytes, offset: int) -> int:
    require(0 <= offset <= len(contents) - 4, "Truncated uint32 field")
    return struct.unpack_from("<I", contents, offset)[0]


def parse_envelope(contents: bytes) -> Envelope:
    require(64 <= len(contents) <= MAX_FILE_BYTES, "Unsupported or oversized DSAV file")
    magic, data_start, version, game_version, word12, names, nodes, raw_end, encoded_size = HEADER.unpack_from(contents)
    require(magic == b"DSAV" and data_start == 36, "Unknown DSAV header")
    require((version, game_version, word12) == (134, 5, 2), "Unverified DSAV version or container mode")
    require(36 < names < nodes < raw_end <= MAX_RAW_BYTES + 36, "Invalid decoded section bounds")
    require(contents[32:36] == b"DSAV", "Missing chunk container marker")
    encoded_end = 36 + encoded_size
    require(36 < encoded_end <= len(contents) - 12, "Invalid encoded container length")
    cursor = 36
    chunks = []
    while cursor < encoded_end:
        require(len(chunks) < MAX_CHUNKS and cursor + 12 <= encoded_end, "Invalid chunk count or header bounds")
        require(contents[cursor:cursor + 4] == b"CHNK", "Missing CHNK marker")
        encoded_length, raw_length = struct.unpack_from("<II", contents, cursor + 4)
        require(0 < encoded_length <= MAX_FILE_BYTES and 0 < raw_length <= MAX_CHUNK_RAW_BYTES, "Invalid chunk length")
        stop = cursor + 12 + encoded_length
        require(stop <= encoded_end, "Chunk extends beyond the encoded region")
        chunks.append(Chunk(contents[cursor + 12:stop], raw_length))
        cursor = stop
    require(contents[cursor:cursor + 4] == b"VASD", "Missing encoded-region closing marker")
    count = unpack_u32(contents, cursor + 4)
    require(count == len(chunks) and count > 0, "Chunk directory count differs")
    require(cursor + 12 + count * 8 == len(contents), "Truncated directory or unexplained trailing bytes")
    for index, chunk in enumerate(chunks):
        lengths = struct.unpack_from("<II", contents, cursor + 8 + index * 8)
        require(lengths == (len(chunk.encoded), chunk.raw_size), "Chunk directory lengths differ")
    require(contents[-4:] == b"VASD", "Missing file closing marker")
    require(sum(chunk.raw_size for chunk in chunks) == raw_end - 36, "Decoded length sum differs from the header")
    return Envelope(contents[:32], names, nodes, raw_end, tuple(chunks))


def encode_envelope(envelope: Envelope, chunks: tuple[Chunk, ...] | None = None) -> bytes:
    selected = envelope.chunks if chunks is None else chunks
    require(len(selected) == len(envelope.chunks), "Research encoder preserves the original chunk partition")
    require([chunk.raw_size for chunk in selected] == [chunk.raw_size for chunk in envelope.chunks], "Raw chunk lengths cannot change")
    body = b"".join(b"CHNK" + struct.pack("<II", len(chunk.encoded), chunk.raw_size) + chunk.encoded for chunk in selected)
    header = bytearray(envelope.header)
    struct.pack_into("<I", header, 28, len(body))
    directory = struct.pack("<I", len(selected)) + b"".join(struct.pack("<II", len(chunk.encoded), chunk.raw_size) for chunk in selected)
    encoded = bytes(header) + b"DSAV" + body + b"VASD" + directory + b"VASD"
    parse_envelope(encoded)
    return encoded


def parse_name_table(payload: bytes, envelope: Envelope) -> tuple[str, ...]:
    start, end = envelope.names_offset - 36, envelope.nodes_offset - 36
    require(payload[start:start + 4] == b"NAME" and payload[end - 4:end] == b"NAME", "Invalid NAME table markers")
    length = unpack_u32(payload, start + 4)
    require(start + 8 + length == end - 4, "NAME table byte length differs")
    names = []
    cursor = start + 8
    while cursor < end - 4:
        length = payload[cursor]
        cursor += 1
        require(length > 0 and cursor + length <= end - 4, "Truncated or unsupported name encoding")
        name = payload[cursor:cursor + length].decode("utf-8", errors="strict")
        require("\x00" not in name, "Embedded terminator in name table")
        names.append(name)
        cursor += length
        require(len(names) <= 65535, "Too many name entries")
    return tuple(names)


def parse_node_table(payload: bytes, envelope: Envelope, names: tuple[str, ...]) -> tuple[NodeRecord, ...]:
    require(len(payload) == envelope.raw_size, "Decoded payload length differs")
    start = envelope.nodes_offset - 36
    require(payload[start:start + 4] == b"DWNT" and payload[-4:] == b"DWNT", "Invalid DWNT table markers")
    require(start + 6 <= len(payload), "Truncated node count")
    count = struct.unpack_from("<H", payload, start + 4)[0]
    require(count > 0 and start + 6 + count * NODE.size + 4 == len(payload), "Node count and table length differ")
    records = []
    for index in range(count):
        name_index, next_index, child_index, offset, size = NODE.unpack_from(payload, start + 6 + index * NODE.size)
        require(1 <= name_index <= len(names), "Node refers to an invalid name")
        require(36 <= offset and size >= 4 and offset + size <= envelope.names_offset, "Node extends outside the record region")
        require(payload[offset - 36:offset - 32] == b"SN" + struct.pack("<H", index), "Node marker and directory index differ")
        require(all(link == 65535 or index < link < count for link in (next_index, child_index)), "Invalid or cyclic node forward link")
        records.append(NodeRecord(index, name_index, names[name_index - 1], next_index, child_index, offset, size))
    require(records[0].name == "Root" and records[0].absolute_offset == 36 and records[0].size == envelope.names_offset - 36, "Root record does not span the record region")
    for record in records:
        if record.child_index != 65535:
            child = records[record.child_index]
            require(record.absolute_offset < child.absolute_offset and child.absolute_offset + child.size <= record.absolute_offset + record.size, "Child record is outside its parent")
        if record.next_index != 65535:
            following = records[record.next_index]
            require(following.absolute_offset >= record.absolute_offset + record.size, "Next record overlaps its predecessor")
    return tuple(records)


class InstalledOodleCodec:
    """Calls a supplied, hash-verified installed codec in place; nothing is redistributed."""

    def __init__(self, codec_path: Path, expected_sha256: str):
        require(os.name == "nt" and ctypes.sizeof(ctypes.c_void_p) == 8, "The installed codec requires 64-bit Windows Python")
        require(codec_path.is_file() and not codec_path.is_symlink(), "Codec must be an ordinary installed file")
        require(digest(codec_path.read_bytes()) == expected_sha256.lower(), "Installed codec SHA-256 mismatch")
        self.library = ctypes.CDLL(str(codec_path.resolve()))
        pointer, number, integer = ctypes.c_void_p, ctypes.c_ssize_t, ctypes.c_int
        self.decompress_function = self.library.OodleLZ_Decompress
        self.decompress_function.argtypes = [pointer, number, pointer, number, integer, integer, integer, pointer, number, pointer, pointer, pointer, number, integer]
        self.decompress_function.restype = number
        self.compress_function = self.library.OodleLZ_Compress
        self.compress_function.argtypes = [integer, pointer, number, pointer, integer, pointer, pointer, pointer, pointer, number]
        self.compress_function.restype = number
        self.capacity_function = self.library.OodleLZ_GetCompressedBufferSizeNeeded
        self.capacity_function.argtypes = [integer, number]
        self.capacity_function.restype = number

    def decompress(self, chunk: Chunk) -> bytes:
        require(0 < chunk.raw_size <= MAX_CHUNK_RAW_BYTES, "Unbounded decoded chunk")
        output = ctypes.create_string_buffer(chunk.raw_size)
        # FuzzSafe=1; these observed chunks carry no Oodle quantum CRC; ThreadPhaseAll=3.
        decoded = self.decompress_function(chunk.encoded, len(chunk.encoded), output, chunk.raw_size, 1, 0, 0, None, 0, None, None, None, 0, 3)
        require(decoded == chunk.raw_size, "Oodle did not decode the complete chunk")
        return output.raw

    def compress_unchanged(self, payload: bytes) -> Chunk:
        require(0 < len(payload) <= MAX_CHUNK_RAW_BYTES, "Unbounded input chunk")
        # Kraken=8, Fast=3 from the SDK API; Fast reproduced both observed chunks exactly.
        capacity = self.capacity_function(8, len(payload))
        require(0 < capacity <= MAX_CHUNK_RAW_BYTES * 2, "Unbounded compressed capacity")
        output = ctypes.create_string_buffer(capacity)
        written = self.compress_function(8, payload, len(payload), output, 3, None, None, None, None, 0)
        require(0 < written <= capacity, "Oodle compression failed")
        chunk = Chunk(output.raw[:written], len(payload))
        require(self.decompress(chunk) == payload, "Codec roundtrip changed payload bytes")
        return chunk


def read_bounded(path: Path) -> bytes:
    require(path.is_file() and not path.is_symlink(), "Source must be an ordinary file")
    require(path.stat().st_size <= MAX_FILE_BYTES, "Source file exceeds the research size bound")
    contents = path.read_bytes()
    require(len(contents) <= MAX_FILE_BYTES, "Source file grew beyond the research size bound")
    return contents


def probe_save(copied_path: Path, codec: InstalledOodleCodec) -> dict:
    original = read_bounded(copied_path)
    envelope = parse_envelope(original)
    require(encode_envelope(envelope) == original, "Unchanged container roundtrip differs")
    raw_chunks = tuple(codec.decompress(chunk) for chunk in envelope.chunks)
    payload = b"".join(raw_chunks)
    names = parse_name_table(payload, envelope)
    records = parse_node_table(payload, envelope, names)
    recompressed_chunks = tuple(codec.compress_unchanged(raw) for raw in raw_chunks)
    recompressed = encode_envelope(envelope, recompressed_chunks)
    reread = parse_envelope(recompressed)
    require(b"".join(codec.decompress(chunk) for chunk in reread.chunks) == payload, "Recompressed container changed decoded bytes")
    copied_path.with_suffix(".payload.bin").write_bytes(payload)
    copied_path.with_suffix(".unchanged-recompressed.research.bin").write_bytes(recompressed)
    selected_records = []
    for record in records:
        if record.name in RESEARCH_NODE_NAMES:
            contents = payload[record.absolute_offset - 36:record.absolute_offset - 36 + record.size]
            selected_records.append({
                "name": record.name, "nodeIndex": record.index, "absoluteDecodedOffset": record.absolute_offset,
                "sizeBytes": record.size, "sha256": digest(contents), "prefixHex": contents[:96].hex(),
                "semanticFieldsVerified": [],
            })
    return {
        "fileName": copied_path.name, "sourceSha256": digest(original), "encodedBytes": len(original),
        "decodedBytes": len(payload), "decodedSha256": digest(payload), "chunkCount": len(envelope.chunks),
        "chunks": [{"encodedBytes": len(chunk.encoded), "decodedBytes": chunk.raw_size} for chunk in envelope.chunks],
        "nameCount": len(names), "nodeCount": len(records), "unchangedContainerByteExact": True,
        "recompressedBytes": len(recompressed), "recompressedByteExact": recompressed == original,
        "recompressedPayloadByteExact": True, "selectedNodeRecords": selected_records,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-directory", type=Path, required=True)
    parser.add_argument("--codec", type=Path, required=True)
    parser.add_argument("--codec-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    source = arguments.source_directory.resolve()
    output = arguments.output.resolve()
    require(source != output and source not in output.parents, "Evidence output must remain outside the source save directory")
    source_files = sorted(path for path in source.glob("*.sav") if path.name.lower() != "rebelsettings.sav")
    require(0 < len(source_files) <= 128, "Expected between one and 128 gameplay saves")
    before = {path.name: digest(read_bounded(path)) for path in source_files}
    copied_directory = Path(tempfile.mkdtemp(prefix="dawnwalker-save-format-research-"))
    for path in source_files:
        shutil.copyfile(path, copied_directory / path.name)
        require(digest(read_bounded(copied_directory / path.name)) == before[path.name], "Source changed during copying")
    codec = InstalledOodleCodec(arguments.codec, arguments.codec_sha256)
    reports = [probe_save(copied_directory / path.name, codec) for path in source_files]
    after = {path.name: digest(read_bounded(path)) for path in source_files}
    require(before == after, "Source saves changed during research")
    evidence = {
        "schemaVersion": 1, "checkedAt": datetime.now(timezone.utc).isoformat(),
        "scope": "Independent read-only save-format research using isolated copies. No gameplay field edits, live save writes, or game-load validation.",
        "codec": {"path": str(arguments.codec.resolve()), "sha256": arguments.codec_sha256.lower(), "source": "Locally installed Unreal Engine 5.6 Oodle 2.9.10 SDK runtime; not copied or bundled"},
        "copiedDirectory": str(copied_directory), "sourceSavesUnchanged": before == after,
        "verifiedEditableFields": [], "saves": reports,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"evidence": str(output), "copiedDirectory": str(copied_directory), "saveCount": len(reports), "allContainerRoundtripsExact": all(report["unchangedContainerByteExact"] for report in reports), "allRecompressedPayloadsExact": all(report["recompressedPayloadByteExact"] for report in reports), "sourceSavesUnchanged": before == after}))


if __name__ == "__main__":
    main()
