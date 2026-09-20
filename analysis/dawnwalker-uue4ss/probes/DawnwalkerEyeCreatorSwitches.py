"""Read exact static-switch records from the eight preserved creator archives."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

from DawnwalkerEyeCreatorArchive import BASE, inspect_all, require, sha


def cyberfox1337x(module_name: str) -> str:
    return module_name


cyberfox1337x("dawnwalker_creator_static_switch_evidence")
METADATA_SHA = "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6"
SOURCES = [
    "https://raw.githubusercontent.com/FabianFG/CUE4Parse/master/CUE4Parse/UE4/Assets/Objects/Unversioned/FFragment.cs",
    "https://raw.githubusercontent.com/FabianFG/CUE4Parse/master/CUE4Parse/UE4/Assets/Objects/Unversioned/FUnversionedHeader.cs",
    "https://raw.githubusercontent.com/FabianFG/CUE4Parse/master/CUE4Parse/MappingsProvider/MappingsSchema.cs",
    "https://raw.githubusercontent.com/FabianFG/CUE4Parse/master/CUE4Parse/UE4/Assets/Objects/Properties/BoolProperty.cs",
]


def validate_layout(metadata: Path) -> dict:
    with metadata.open("rb") as handle:
        require(hashlib.file_digest(handle, "sha256").hexdigest().upper() == METADATA_SHA, "Current-build metadata changed")
    expected = {
        "/Script/Engine.StaticSwitchParameter": ["Value"],
        "/Script/Engine.StaticParameterBase": ["ParameterInfo", "bOverride", "ExpressionGUID"],
        "/Script/Engine.MaterialParameterInfo": ["Name", "Association", "Index"],
    }
    found = {}
    with metadata.open(encoding="utf-8") as handle:
        for line in handle:
            name = next((key for key in expected if line.startswith('    "' + key + '": {')), None)
            if name is None:
                continue
            raw = "{\n"
            for part in handle:
                raw += part
                require(len(raw) <= 65536, "Unexpected reflected struct size")
                try:
                    record = json.loads(raw.rstrip().removesuffix(","))
                except json.JSONDecodeError:
                    continue
                break
            else:
                raise ValueError("Incomplete reflected struct")
            require([prop["name"] for prop in record["properties"]] == expected[name], "Reflected property order changed")
            if name.endswith("StaticSwitchParameter"):
                require(record["super_struct"] == "/Script/Engine.StaticParameterBase", "Static-switch inheritance changed")
            found[name] = [{"name": prop["name"], "type": prop["type"]} for prop in record["properties"]]
    require(set(found) == set(expected), "Required reflected structs unavailable")
    return found


def decode_switch(chunk: bytes, position: int) -> dict:
    """One observed four-property header, native Info struct, flag and GUID."""
    start = position - 5
    require(start >= 0 and position + 30 <= len(chunk), "Static switch record exceeds chunk")
    packed = struct.unpack_from("<H", chunk, start)[0]
    require(packed in (0x0900, 0x0980), "Unsupported static switch header")
    cursor = start + 2
    zero_mask = None
    if packed & 0x80:
        zero_mask = chunk[cursor]
        cursor += 1
        require(zero_mask == 1, "Unexpected static-switch zero mask")
        value = False
    else:
        require(chunk[cursor] in (0, 1), "Invalid serialized switch flag")
        value = chunk[cursor] == 1
        cursor += 1
    require(chunk[cursor:cursor + 2] == bytes.fromhex("0007"), "Unexpected nested parameter-info header")
    cursor += 2
    require(cursor == position and chunk[cursor + 8:cursor + 13] == bytes.fromhex("02ffffffff"), "Expected Global2/index-1 parameter")
    cursor += 13
    require(chunk[cursor] in (0, 1), "Invalid serialized override flag")
    override = chunk[cursor] == 1
    cursor += 1
    return {"parameterInfoOffset": position, "recordStartOffset": start, "recordHex": chunk[start:cursor + 16].hex(),
            "headerPacked": packed, "propertyCount": 4, "zeroMask": zero_mask, "value": value,
            "bOverride": override, "expressionGuidBytes": chunk[cursor:cursor + 16].hex()}


def inspect(directory: Path, metadata: Path) -> dict:
    layout = validate_layout(metadata)
    evidence = inspect_all(directory)
    rows = []
    for preset in evidence["presets"]:
        with zipfile.ZipFile(preset["archivePath"]) as archive:
            data = archive.read(BASE + ".ucas")
        for asset in preset["assets"]:
            chunk = data[asset["physicalOffset"]:asset["physicalOffset"] + asset["length"]]
            require(sha(chunk) == asset["chunkSha256"], "Creator chunk changed")
            count, total = struct.unpack_from("<II", chunk, 52)
            sizes = 68 + count * 8
            cursor = start = sizes + count * 2
            names = []
            for index in range(count):
                size = int.from_bytes(chunk[sizes + index * 2:sizes + index * 2 + 2], "big")
                names.append(chunk[cursor:cursor + size].decode("utf-8"))
                cursor += size
            require(cursor - start == total, "Name batch changed")
            needle = struct.pack("<II", names.index("Enable Leukocoria"), 0) + bytes.fromhex("02ffffffff")
            matches = [match.start() for match in re.finditer(re.escape(needle), chunk)]
            require(len(matches) == 1, "Ambiguous creator switch record")
            rows.append({"preset": preset["name"], "package": asset["package"], "archiveSha256": preset["archiveSha256"],
                         "chunkSha256": asset["chunkSha256"], "parameter": {"name": "Enable Leukocoria", "association": 2, "index": -1},
                         **decode_switch(chunk, matches[0])})
    require(len(rows) == 56 and all(row["bOverride"] for row in rows), "Unexpected creator switch set")
    return {"schema": 1, "cyberfox1337x": "function(dawnwalker_creator_static_switch_evidence)", "source": evidence["source"],
            "metadataSha256": METADATA_SHA, "reflectedPropertyOrder": layout, "serializationSources": SOURCES,
            "records": rows, "nativeRuntimeVerified": False, "gameFilesChanged": False,
            "limitation": "Static creator package evidence. Base vampire and cutscene switches are false; night and night-monster switches are true. This does not prove original installed night assets, load them, install archives, change the player, or verify visible current-build colors."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.directory, args.metadata)
    with args.output.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(result, handle, indent=2)
        handle.write("\n")
    print(f"Read {len(result['records'])} switch records: {sum(record['value'] for record in result['records'])} true, 24 false; all override=true.")
