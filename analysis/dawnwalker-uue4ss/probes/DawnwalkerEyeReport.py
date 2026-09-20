"""Read completed, bounded eye discovery/native pilot reports without touching the runtime."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import unquote


def cyberfox1337x(module_name: str) -> str:
    return module_name


cyberfox1337x("dawnwalker_eye_report_reader")
BEGIN = re.compile(r"\[DawnwalkerRequestedReadOnly\] report_begin boot_id=(\d+-\d+) nonce=([0-9a-fA-F]{32})")
END = re.compile(r"\[DawnwalkerRequestedReadOnly\] report_end ok=(true|false) mutation_authorized=false gameplay_verified=false")
PILOT_BEGIN = re.compile(r"\[DawnwalkerEyeNativePilot\] report_begin boot_id=(\d+-\d+) nonce=([0-9a-fA-F]{32}) operation=([a-z-]+)")
PILOT_END = re.compile(r"\[DawnwalkerEyeNativePilot\] report_end ok=(true|false) operation=([a-z-]+) gameplay_verified=false")
OPERATIONS = {"observe", "export", "private-instance-roundtrip", "color-roundtrip", "camera-roundtrip"}
V4_OPERATIONS = {"variant-observe", "private-preview-roundtrip"}
V5_OPERATIONS = {"human-iris-pair-roundtrip"}
V9_OPERATIONS = {"session-start", "session-stop"}


def read_reports(path: Path) -> list[dict]:
    if path.stat().st_size > 20 * 1024 * 1024:
        raise ValueError("Expected a bounded current-session log of at most 20 MiB")
    data = path.read_bytes()
    records, active = [], None
    for line in data.decode("utf-8-sig", errors="replace").splitlines():
        pilot_begin = PILOT_BEGIN.search(line)
        begin = pilot_begin or BEGIN.search(line)
        if begin:
            if active is not None:
                raise ValueError("Nested/incomplete report boundary")
            active = {"bootId": begin.group(1), "nonce": begin.group(2), "fields": {}, "bytes": 0,
                      "kind": "eye_pilot" if pilot_begin else "eye_discovery"}
            if pilot_begin:
                active["operation"] = begin.group(3)
                if active["operation"] not in OPERATIONS | V4_OPERATIONS | V5_OPERATIONS | V9_OPERATIONS:
                    raise ValueError("Unknown native eye operation")
            continue
        if active is None:
            continue
        end = (PILOT_END if active["kind"] == "eye_pilot" else END).search(line)
        if end:
            fields = active.pop("fields")
            if active["kind"] == "eye_pilot":
                schema = fields.get("eye_pilot.schema")
                allowed_by_schema = {"2": OPERATIONS, "3": OPERATIONS | V4_OPERATIONS,
                                     "4": OPERATIONS | V4_OPERATIONS | V5_OPERATIONS,
                                     "5": OPERATIONS | V4_OPERATIONS | V5_OPERATIONS,
                                     "6": OPERATIONS | V4_OPERATIONS | V5_OPERATIONS,
                                     "7": OPERATIONS | V4_OPERATIONS | V5_OPERATIONS,
                                     "8": OPERATIONS | V4_OPERATIONS | V5_OPERATIONS | V9_OPERATIONS}
                if schema not in allowed_by_schema or active["operation"] not in allowed_by_schema[schema]:
                    raise ValueError("Unknown native pilot schema/operation combination")
                active["envelopeSchema"] = int(schema)
                expected = {"schema": schema, "boot_id": active["bootId"], "nonce": active["nonce"],
                            "operation": active["operation"], "gameplay_verified": "false", "production_capabilities": "none",
                            "ok": end.group(1)}
                if end.group(2) != active["operation"] or any(fields.get("eye_pilot." + key) != value for key, value in expected.items()):
                    raise ValueError("Native pilot envelope identity, operation or verification flags disagree")
            elif fields.get("eye_discovery.mutation_authorized") != "false" or fields.get("eye_discovery.gameplay_verified") != "false":
                raise ValueError("Report lacks its expected read-only flags")
            active["ok"] = end.group(1) == "true"
            active["fields"] = fields
            active["sourceSha256"] = hashlib.sha256(data).hexdigest().upper()
            records.append(active)
            active = None
            continue
        position = line.find(active["kind"] + ".")
        if position < 0:
            continue
        entry = line[position:]
        key, separator, value = entry.partition("=")
        if not separator or key in active["fields"]:
            raise ValueError("Malformed or duplicate report field")
        active["bytes"] += len(entry.encode("utf-8")) + 1
        if active["bytes"] > 1048576:
            raise ValueError("Eye report exceeds its one MiB transport bound")
        active["fields"][key] = unquote(value)
    if active is not None:
        raise ValueError("Incomplete eye report; preserve the source and wait for report_end")
    return records


def nested_fields(fields: dict, prefix: str) -> dict:
    """Preserve native scalar strings and one-based Lua index keys; never infer receipt types."""
    result = {}
    for key, value in fields.items():
        if not key.startswith(prefix + "."):
            raise ValueError("Field outside expected report namespace")
        parts = key[len(prefix) + 1:].split(".")
        if len(parts) > 20 or any(not part for part in parts):
            raise ValueError("Malformed nested native report field")
        target = result
        for part in parts[:-1]:
            target = target.setdefault(part, {})
            if not isinstance(target, dict):
                raise ValueError("Native report scalar/object field collision")
        if parts[-1] in target:
            raise ValueError("Native report object/scalar field collision")
        target[parts[-1]] = value
    return result


def summarize(report: dict) -> dict:
    fields = report["fields"]
    if report["kind"] == "eye_pilot":
        return {"schema": report["envelopeSchema"], "cyberfox1337x": "function(dawnwalker_eye_native_report_summary)",
                "bootId": report["bootId"], "nonce": report["nonce"], "operation": report["operation"],
                "sourceSha256": report["sourceSha256"], "operationOk": report["ok"],
                "gameplayVerified": False, "productionCapabilities": [], "fields": fields,
                "native": nested_fields(fields, "eye_pilot"),
                "errors": {key: value for key, value in fields.items() if key.endswith(".reason")},
                "limitation": "Native operation evidence. Scalar values remain exact reported strings and Lua array indexes remain one-based object keys. This is not a production EyeSession or a verified frame/settings receipt."}
    identity = {key.removeprefix("eye_discovery.identity."): value for key, value in fields.items()
                if key.startswith("eye_discovery.identity.")}
    head_address = fields.get("eye_discovery.materials.head_mesh.address")
    meshes = []
    for key, value in fields.items():
        if re.fullmatch(r"eye_discovery\.materials\.materials\.\d+\.address", key) and value == head_address:
            prefix = key.removesuffix("address")
            meshes.append({name.removeprefix(prefix): item for name, item in fields.items() if name.startswith(prefix)})
    dolls = {key.removeprefix("eye_discovery.preview."): value for key, value in fields.items()
             if key.startswith("eye_discovery.preview.dolls.")}
    return {"schema": 1, "cyberfox1337x": "function(dawnwalker_eye_report_summary)",
            "bootId": report["bootId"], "nonce": report["nonce"], "sourceSha256": report["sourceSha256"],
            "captureStable": report["ok"], "mutationAuthorized": False, "gameplayVerified": False,
            "previewVerified": False, "identity": identity, "headMeshes": meshes, "dolls": dolls,
            "materialReferenceCountsScope": "head-mesh-only" if fields.get("eye_discovery.materials.scope") == "eye-head-material-discovery" else "observed-player-meshes-only",
            "errors": {key: value for key, value in fields.items() if key.endswith(".reason")},
            "limitation": "Observed metadata only. Head membership or an eye-like name does not establish editable eye semantics."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--nonce", help="Select an exact issued nonce; defaults to the last completed eye report")
    parser.add_argument("--output", type=Path, help="Optional new JSON artifact; existing output is never overwritten")
    args = parser.parse_args()
    reports = read_reports(args.log)
    if args.nonce:
        reports = [report for report in reports if report["nonce"] == args.nonce]
        if len(reports) != 1:
            raise SystemExit("Exact nonce did not identify one completed report")
    if not reports:
        raise SystemExit("No completed eye report in this log")
    text = json.dumps(summarize(reports[-1]), indent=2, ensure_ascii=False) + "\n"
    if args.output:
        with args.output.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print(args.output.resolve())
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
