"""Inspect the eight local Su4enka v1 eye archives; never extract or modify packages."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zipfile


def cyberfox1337x(module_name: str) -> str:
    return module_name


cyberfox1337x("dawnwalker_eye_creator_archive_inspection")
ARCHIVES = {
    "Blue": "65d6ec1c03bd02c7af7213b7e0849b09569c88e84ac851d65de68be4b0dcac38",
    "Cyan": "982ac7544b092cae67ea4b88f711e8d755b70b9e4efe66265cf7ff1d759bfb1d",
    "Green": "3df0bb6d27e24997caab4957817a7bfb663c07ea507eeef1ba96c68b1afcbf2d",
    "Orange": "f53dc0b76c58c493e72e989479c8360d1ec25d4bcb47f0e1e5816c6f3b2d76d4",
    "Red": "5516ae679280ae4d1cd0acc6f1ea9b9235cab541467964ddc5be763dc1eb0dc4",
    "Rose": "7e3ecaf779fd78eb6076692ddc2464324d6789b1bd2bd0d5f450c6f231078a86",
    "Violet": "860017e18e2fd8fd24952aa7fca182f3ec398d3d2c55e35b97e9786013888ce7",
    "Yellow": "a52157bda9a9086fd2002a5df5d12ed485efe552067126308b8920c2081e9348",
}
BASE = "Dawnwalker/Content/Paks/CoenVampireEyes_Color_P"
SOURCE = "https://www.nexusmods.com/thebloodofdawnwalker/mods/26"


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def inspect_archive(path: Path, color: str) -> dict:
    require(path.stat().st_size <= 65536, "Unexpected archive size")
    archive = path.read_bytes()
    require(sha(archive).lower() == ARCHIVES[color], "Archive is not the inspected creator v1 payload")
    with zipfile.ZipFile(path) as handle:
        require(sorted(handle.namelist()) == sorted(BASE + suffix for suffix in (".pak", ".utoc", ".ucas")), "Unexpected archive entries")
        require(all(info.file_size <= 200000 for info in handle.infolist()), "Oversized archive member")
        files = {suffix: handle.read(BASE + suffix) for suffix in (".pak", ".utoc", ".ucas")}
    toc, data = files[".utoc"], files[".ucas"]
    require(toc[:16] == b"-==--==--==--==-" and toc[16] == 8, "Unexpected IoStore version")
    header, count, blocks, block_record, methods = struct.unpack_from("<IIIII", toc, 20)
    require((header, count, blocks, block_record, methods) == (144, 8, 8, 12, 0), "Unexpected IoStore layout")
    require(toc[80] == 8, "Expected indexed, unencrypted and unsigned creator container")
    require(struct.unpack_from("<I", toc, 44)[0] == 65536, "Unexpected logical block size")
    assets = []
    for index in range(count):
        chunk_id = toc[header + index * 12:header + (index + 1) * 12]
        logical_pos = header + count * 12 + index * 10
        logical = int.from_bytes(toc[logical_pos:logical_pos + 5], "big")
        length = int.from_bytes(toc[logical_pos + 5:logical_pos + 10], "big")
        require(logical == index * 65536 and 0 < length < 65536, "Unexpected chunk/block mapping")
        block_pos = header + count * 22 + index * 12
        block = toc[block_pos:block_pos + 12]
        offset = int.from_bytes(block[:5], "little")
        compressed = int.from_bytes(block[5:8], "little")
        uncompressed = int.from_bytes(block[8:11], "little")
        require(compressed == uncompressed == length and block[11] == 0, "Compressed or split chunks are unsupported")
        require(offset + length <= len(data), "Chunk exceeds UCAS")
        if chunk_id[-1] == 6:
            require(index == count - 1, "Unexpected container-header chunk")
            continue
        require(chunk_id[-1] == 1, "Unexpected native package chunk type")
        chunk = data[offset:offset + length]
        require(struct.unpack_from("<I", chunk)[0] == 0, "Versioned package unsupported")
        num_names, num_bytes = struct.unpack_from("<II", chunk, 52)
        require(1 <= num_names <= 128 and num_bytes <= 4096, "Unexpected name batch")
        sizes = 68 + num_names * 8
        start = cursor = sizes + num_names * 2
        names = []
        for name_index in range(num_names):
            size = int.from_bytes(chunk[sizes + name_index * 2:sizes + name_index * 2 + 2], "big")
            require(0 < size < 256 and cursor + size <= len(chunk), "Wide or malformed native name")
            names.append(chunk[cursor:cursor + size].decode("utf-8"))
            cursor += size
        require(cursor - start == num_bytes and len(names) == len(set(names)), "Native name batch mismatch")
        package_index, package_number = struct.unpack_from("<II", chunk, 8)
        require(package_number == 0 and package_index < len(names), "Unexpected package name")
        package = names[package_index]
        require(package.startswith("/Game/_Dawnwalker/") and "MI_Coen_Eyeball_" in package and "Vampire" in package, "Not a scoped vampire eye material")
        parameter_index = names.index("Leukocoria_Color")
        parameter_info = struct.pack("<II", parameter_index, 0) + bytes((2, 255, 255, 255, 255))
        matches = [match.start() for match in re.finditer(re.escape(parameter_info), chunk)]
        require(len(matches) == 1, "Ambiguous native parameter record")
        position = matches[0]
        require(chunk[position - 4:position] == bytes((0, 7, 0, 7)), "Unexpected parameter/value unversioned fragments")
        vector_start = position + len(parameter_info)
        value = struct.unpack_from("<ffff", chunk, vector_start)
        require(all(math.isfinite(channel) for channel in value) and value[3] == 1 and min(value) >= 0 and max(value) < 6, "Unexpected creator vector domain")
        scrubbed = chunk[:vector_start] + bytes(16) + chunk[vector_start + 16:]
        assets.append({"package": package, "chunkId": chunk_id.hex(), "chunkSha256": sha(chunk),
                       "physicalOffset": offset, "length": length, "parameterInfoOffset": position,
                       "parameter": {"name": "Leukocoria_Color", "association": 2, "index": -1},
                       "vectorOffset": vector_start, "vectorBytes": chunk[vector_start:vector_start + 16].hex(),
                       "value": dict(zip("RGBA", value)), "otherBytesSha256": sha(scrubbed)})
    require(len(assets) == 7 and len({asset["package"] for asset in assets}) == 7, "Expected seven distinct creator material packages")
    return {"name": color, "archivePath": str(path.resolve()), "archiveSha256": sha(archive),
            "members": [{"name": BASE + suffix, "bytes": len(content), "sha256": sha(content)} for suffix, content in files.items()],
            "assets": sorted(assets, key=lambda asset: asset["package"])}


def inspect_all(directory: Path) -> dict:
    records = []
    for color in ARCHIVES:
        matches = list(directory.glob(f"{color} 26 1*.zip"))
        require(len(matches) == 1, f"Expected exactly one {color} creator archive")
        records.append(inspect_archive(matches[0], color))
    baseline = {asset["package"]: asset["otherBytesSha256"] for asset in records[0]["assets"]}
    require(all({asset["package"]: asset["otherBytesSha256"] for asset in record["assets"]} == baseline for record in records),
            "Creator presets differ outside the expected sixteen vector bytes")
    return {"schema": 1, "cyberfox1337x": "function(dawnwalker_eye_creator_archive_evidence)",
            "creator": "Su4enka", "source": SOURCE, "version": "1", "presets": records,
            "sameAssetBytesExceptLeukocoriaColor": True, "nativeRuntimeVerified": False, "colorSpaceVerified": False,
            "maximumObservedComponent": max(asset["value"][channel] for record in records for asset in record["assets"] for channel in "RGB"),
            "limitation": "Static byte evidence for seven vampire material variants. Colors include HDR components and left/right/night differences. No human material, shader activation, exact current-build compatibility, live effect, shared material mutation, archive installation or production capability is established."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect_all(args.directory)
    with args.output.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(result, handle, indent=2)
        handle.write("\n")
    print(f"Validated {len(result['presets'])} archives, 56 material records, 7 identical asset sets except vector16. Output: {args.output.resolve()}")


if __name__ == "__main__":
    main()
