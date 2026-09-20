"""Compose a new offline V6 candidate from the frozen V5 payload and reviewed V6 sources."""
from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path


def cyberfox1337x(module_name: str) -> str:
    return module_name


cyberfox1337x("dawnwalker_eye_candidate_v6_composer")
ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).resolve().parent
FROZEN = ROOT / "qa/eye-appearance/native-pilot-candidate-v5"
DESTINATION = ROOT / "qa/eye-appearance/native-pilot-candidate-v6"
PREVIOUS_MANIFEST = "99E45B2AE111DC59AC2C47C964833B4A0DE4E1F71DE366F688CCDA9F842C5DE7"
SCRIPTS = "Mods/DawnwalkerRequestedReadOnly/Scripts/"
REPLACEMENTS = {
    "main.lua": "DawnwalkerEyeNativeBootstrapV6.lua",
    "ReadOnlyDriver.lua": "DawnwalkerEyeNativeDriverV6.lua",
    "EyeDiscoveryProbe.lua": "DawnwalkerEyeNativeDispatchV6.lua",
    "DawnwalkerPrivateEyePreviewProbe.lua": "DawnwalkerPrivateEyePreviewV6Probe.lua",
}
CLEANUP = {"operation": "private-preview-roundtrip", "afterFrames": [1, 3, 30],
           "maximumReports": 3, "maximumReportBytes": 65536, "mutatesRuntime": False,
           "route": "EngineTick", "scheduler": "ExecuteInGameThreadAfterFrames"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def update_reviewed_facts(manifest: dict) -> None:
    manifest.update(schema=5, revision=6, preparedAtUtc=datetime.now(timezone.utc).isoformat(), cleanupObservations=CLEANUP)
    prefix = "analysis/dawnwalker-uue4ss/probes/"
    manifest["sourceProvenance"].update(privatePreview=prefix + REPLACEMENTS["DawnwalkerPrivateEyePreviewProbe.lua"],
                                        driver=prefix + REPLACEMENTS["ReadOnlyDriver.lua"],
                                        dispatch=prefix + REPLACEMENTS["EyeDiscoveryProbe.lua"],
                                        bootstrap=prefix + REPLACEMENTS["main.lua"])
    manifest["offlineTests"].update(privatePreviewGroups=28, driverGroups=18, bootstrapGroups=3)
    if sum(manifest["offlineTests"].values()) != 136:
        raise ValueError("Reviewed V6 Lua test counts differ")


def no_links(path: Path) -> None:
    for entry in (path, *path.parents):
        if entry.is_symlink() or entry.is_junction():
            raise ValueError(f"Linked candidate/source path refused: {entry}")


def main() -> None:
    no_links(DESTINATION)
    if DESTINATION.exists():
        raise ValueError("V6 destination already exists; this composer never overwrites a candidate")
    no_links(FROZEN / "manifest.json")
    if sha256(FROZEN / "manifest.json") != PREVIOUS_MANIFEST:
        raise ValueError("Frozen V5 manifest changed")
    manifest = json.loads((FROZEN / "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest["schema"] != 4 or manifest["revision"] != 5 or len(manifest["payload"]) != 13:
        raise ValueError("Frozen V5 profile differs")
    inputs = []
    for record in manifest["payload"]:
        previous = FROZEN / record["path"]
        no_links(previous)
        if sha256(previous) != record["sha256"] or previous.stat().st_size != record["bytes"]:
            raise ValueError("Frozen V5 payload changed: " + record["path"])
        replacement = REPLACEMENTS.get(record["path"].removeprefix(SCRIPTS)) if record["path"].startswith(SCRIPTS) else None
        selected = SOURCE / replacement if replacement else previous
        no_links(selected)
        if not selected.is_file():
            raise ValueError("Missing reviewed V6 source: " + str(selected))
        inputs.append((record["path"], selected))
    DESTINATION.mkdir()
    for relative, selected in inputs:
        destination = DESTINATION / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(selected, destination)
    issuer = (FROZEN / "New-EyePilotAttestation.ps1").read_text(encoding="utf-8-sig")
    issuer = issuer.replace("$manifest.schema -ne 4", "$manifest.schema -ne 5 -or $manifest.revision -ne 6")
    issuer = issuer.replace("'schema=4'", "'schema=5'")
    (DESTINATION / "New-EyePilotAttestation.ps1").write_text(issuer, encoding="utf-8", newline="\n")
    shutil.copyfile(ROOT / "qa/eye-appearance/V6-NATIVE-PILOT.md", DESTINATION / "README.md")
    update_reviewed_facts(manifest)
    manifest["payload"] = [{"path": relative, "bytes": (DESTINATION / relative).stat().st_size,
                            "sha256": sha256(DESTINATION / relative)} for relative, _ in inputs]
    (DESTINATION / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"candidate": str(DESTINATION), "manifestSha256": sha256(DESTINATION / "manifest.json"),
                      "issuerSha256": sha256(DESTINATION / "New-EyePilotAttestation.ps1"),
                      "payloadFiles": len(inputs), "gameFilesChanged": False}, indent=2))


if __name__ == "__main__":
    main()
