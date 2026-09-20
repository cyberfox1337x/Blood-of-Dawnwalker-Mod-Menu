"""Read bounded V6-V9 cleanup observations without changing the original operation result."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import unquote

from DawnwalkerEyeReport import nested_fields


def cyberfox1337x(module_name: str) -> str:
    return module_name


cyberfox1337x("dawnwalker_eye_cleanup_report_reader")
BEGIN = re.compile(r"\[DawnwalkerEyeCleanupObservation\] report_begin boot_id=(\d+-\d+) nonce=([a-fA-F0-9]{32}) operation=private-preview-roundtrip after_frames=(1|3|30)$")
END = re.compile(r"\[DawnwalkerEyeCleanupObservation\] report_end operation=private-preview-roundtrip after_frames=(1|3|30) gameplay_verified=false$")


def read_observations(path: Path, nonce: str) -> dict:
    if not re.fullmatch(r"[a-fA-F0-9]{32}", nonce):
        raise ValueError("Exact nonce required")
    if path.stat().st_size > 20 * 1024 * 1024:
        raise ValueError("Current-session log exceeds 20 MiB")
    data = path.read_bytes()
    active, records, unique = None, [], set()
    for line in data.decode("utf-8-sig", errors="replace").splitlines():
        begin = BEGIN.search(line)
        if begin:
            if active is not None:
                raise ValueError("Nested or incomplete cleanup observation")
            active = {"bootId": begin[1], "nonce": begin[2], "afterFrames": int(begin[3]), "fields": {}, "bytes": 0}
            continue
        if active is None:
            continue
        end = END.search(line)
        if end:
            fields = active.pop("fields")
            requested = str(active["afterFrames"])
            schema = fields.get("eye_cleanup.schema")
            if schema not in {"5", "6", "7", "8"}:
                raise ValueError("Unknown cleanup observation envelope schema")
            expected = {"schema": schema, "boot_id": active["bootId"], "nonce": active["nonce"],
                        "operation": "private-preview-roundtrip", "requested_frames": requested,
                        "mutation_authorized": "false", "gameplay_verified": "false", "production_capabilities": "none",
                        "schedule.requested_frames": requested,
                        "observation.kind": "native-private-preview-cleanup-observation", "observation.schema": "1",
                        "observation.boot_id": active["bootId"], "observation.nonce": active["nonce"].lower(),
                        "observation.after_frames": requested}
            if end[1] != requested or any(fields.get("eye_cleanup." + key) != value for key, value in expected.items()):
                raise ValueError("Cleanup envelope or operation identity mismatch")
            complete = fields.get("eye_cleanup.schedule.schedule_complete")
            if complete not in {"true", "false"}:
                raise ValueError("Missing cleanup scheduler completion evidence")
            if complete == "true":
                values = [fields.get("eye_cleanup.schedule." + key, "") for key in ("started_frame", "observed_frame", "elapsed_frames")]
                if any(not value.isdigit() for value in values):
                    raise ValueError("Completed cleanup frame evidence is not integral")
                started, observed, elapsed = map(int, values)
                if observed - started != elapsed or not active["afterFrames"] <= elapsed <= 120:
                    raise ValueError("Cleanup frame advancement is inconsistent")
            key = (active["bootId"], active["nonce"], active["afterFrames"])
            if key in unique:
                raise ValueError("Repeated cleanup observation for one request/frame")
            unique.add(key)
            if active["nonce"] == nonce:
                active["native"] = nested_fields(fields, "eye_cleanup")
                records.append(active)
                if len(records) > 3:
                    raise ValueError("Cleanup request exceeds three observations")
            active = None
            continue
        position = line.find("eye_cleanup.")
        if position >= 0:
            key, separator, value = line[position:].partition("=")
            if not separator or key in active["fields"]:
                raise ValueError("Malformed or duplicate cleanup field")
            active["bytes"] += len(line[position:].encode("utf-8")) + 1
            if active["bytes"] > 65536 or len(active["fields"]) >= 1024:
                raise ValueError("Cleanup observation exceeds its byte/field budget")
            active["fields"][key] = unquote(value)
    if active is not None:
        raise ValueError("Incomplete cleanup report; wait for its end marker")
    if not records or len({record["bootId"] for record in records}) != 1:
        raise ValueError("Nonce did not identify cleanup observations from one boot")
    if len({record["native"]["schema"] for record in records}) != 1:
        raise ValueError("Cleanup request contains mixed candidate envelope schemas")
    return {"schema": 1, "cyberfox1337x": "function(dawnwalker_eye_cleanup_evidence)",
            "bootId": records[0]["bootId"], "nonce": nonce, "operation": "private-preview-roundtrip",
            "sourceSha256": hashlib.sha256(data).hexdigest().upper(), "observations": sorted(records, key=lambda item: item["afterFrames"]),
            "allScheduledObservationsPresent": {record["afterFrames"] for record in records} == {1, 3, 30},
            "gameplayVerified": False, "productionCapabilities": [],
            "limitation": "Read-only lifecycle observations. Scheduler completion is not actor destruction, and this does not amend the original operation or prove rendered frames."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--nonce", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    text = json.dumps(read_observations(args.log, args.nonce), indent=2) + "\n"
    if args.output:
        with args.output.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print(args.output.resolve())
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
