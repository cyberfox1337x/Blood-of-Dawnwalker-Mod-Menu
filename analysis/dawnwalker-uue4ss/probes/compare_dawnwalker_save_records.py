"""Compare protected baseline/change/inverse saves without guessing field semantics."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import tempfile

from dawnwalker_save_format import (
    InstalledOodleCodec, RESEARCH_NODE_NAMES, cyberfox1337x, digest,
    parse_envelope, parse_name_table, parse_node_table, read_bounded, require,
)

cyberfox1337x.function("dawnwalker_save_record_pair_comparison")


def record_map(contents: bytes, codec: InstalledOodleCodec) -> dict[str, bytes]:
    envelope = parse_envelope(contents)
    payload = b"".join(codec.decompress(chunk) for chunk in envelope.chunks)
    names = parse_name_table(payload, envelope)
    nodes = parse_node_table(payload, envelope, names)
    selected = {}
    for node in nodes:
        if node.name not in RESEARCH_NODE_NAMES:
            continue
        require(node.name not in selected, "Ambiguous duplicate research record name")
        # SN+directory-index is structural and may move between otherwise equivalent saves.
        selected[node.name] = payload[node.absolute_offset - 32:node.absolute_offset - 36 + node.size]
    return selected


def compare_records(baseline: dict[str, bytes], changed: dict[str, bytes], inverse: dict[str, bytes]) -> list[dict]:
    require(baseline.keys() == changed.keys() == inverse.keys(), "Named subsystem inventory differs across the save triplet")
    result = []
    for name, original in sorted(baseline.items()):
        probe = changed[name]
        restored = inverse[name]
        same_size = len(original) == len(probe) == len(restored)
        positions = [index + 4 for index, (before, after) in enumerate(zip(original, probe)) if before != after] if same_size else []
        result.append({
            "name": name,
            "baselineRecordBytes": len(original) + 4,
            "changedRecordBytes": len(probe) + 4,
            "inverseRecordBytes": len(restored) + 4,
            "sameSize": same_size,
            "baselineBodySha256": digest(original),
            "changedBodySha256": digest(probe),
            "inverseBodySha256": digest(restored),
            "bodyChanged": probe != original,
            "inverseRestoresOriginalBody": restored == original,
            "changedRecordRelativeBytePositions": positions,
            "semanticFieldVerified": False,
        })
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--changed", type=Path, required=True)
    parser.add_argument("--inverse", type=Path, required=True)
    parser.add_argument("--codec", type=Path, required=True)
    parser.add_argument("--codec-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sources = {label: getattr(args, label).resolve() for label in ("baseline", "changed", "inverse")}
    require(len(set(sources.values())) == 3, "Three separately captured save copies are required")
    require(args.output.resolve() not in sources.values(), "The report cannot replace a save")
    copied = Path(tempfile.mkdtemp(prefix="dawnwalker-save-triplet-"))
    original_hashes = {}
    for label, source in sources.items():
        original_hashes[label] = digest(read_bounded(source))
        shutil.copy2(source, copied / f"{label}.sav")
        require(digest(read_bounded(copied / f"{label}.sav")) == original_hashes[label], "Source changed while copying")
    codec = InstalledOodleCodec(args.codec, args.codec_sha256)
    records = {label: record_map(read_bounded(copied / f"{label}.sav"), codec) for label in sources}
    compared = compare_records(records["baseline"], records["changed"], records["inverse"])
    require(all(digest(read_bounded(source)) == original_hashes[label] for label, source in sources.items()), "A source save changed during comparison")
    report = {
        "schemaVersion": 1,
        "cyberfox1337x": "function(dawnwalker_save_record_pair_comparison)",
        "scope": "Structural baseline/change/inverse comparison. Correlation alone does not prove gameplay field semantics or edited-save loading.",
        "copiedDirectory": str(copied),
        "sourceSha256": original_hashes,
        "sourceSavesUnchanged": True,
        "verifiedEditableFields": [],
        "records": compared,
    }
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(report, output, indent=2)
        output.write("\n")
    print(json.dumps({"report": str(args.output), "sourceSavesUnchanged": True, "recordsCompared": len(compared)}))


if __name__ == "__main__":
    main()
