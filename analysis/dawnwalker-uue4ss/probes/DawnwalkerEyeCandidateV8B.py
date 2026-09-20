"""Validate and compose a new V8B candidate; never overwrite or install one."""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def cyberfox1337x(module_name: str) -> str:
    return module_name


cyberfox1337x("dawnwalker_eye_candidate_v8b_composer")
ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).resolve().parent
TESTS = SOURCE.parent / "tests"
FROZEN = ROOT / "qa/eye-appearance/native-pilot-candidate-v8"
DESTINATION = ROOT / "qa/eye-appearance/native-pilot-candidate-v8b"
PREVIOUS_MANIFEST = "C1BB95EA720494109376302EFE65D6555D86B369E625EFCE1E64D93CE78921F4"
PREVIOUS_ISSUER = "543AEF96EF88283C13063E9892F3C50EE44E556E46D7E4B56388477C92DBF4A2"
SCRIPTS = "Mods/DawnwalkerRequestedReadOnly/Scripts/"
LUA_BIN = Path("C:/Users/Cyberfox1337/AppData/Local/Programs/Lua/bin")
REPLACEMENTS = {
    "DawnwalkerPrivateEyePreviewProbe.lua": "DawnwalkerPrivateEyePreviewV9Probe.lua",
    "DawnwalkerAppearanceSources.lua": "DawnwalkerAppearanceSourcesV9.lua",
}
RENAMED_PAYLOADS = {"DawnwalkerAppearanceSources.lua": "DawnwalkerAppearanceSourcesV9.lua"}

PROFILE = {
    "maximumExports": 9, "maximumOwnedRenderTargets": 1, "maximumDimension": 1024,
    "viewPhases": ["front", "yaw-min", "yaw-max", "eyes-closeup", "head-zoom-min",
                   "head-zoom-max", "eyes-zoom-min", "eyes-zoom-max", "restored-front"],
    "selectedViewExposureCandela": 20, "captureSource": 9, "renderTargetFormat": 2,
    "targetGamma": 0, "maximumLights": 2, "lightingChannel": 2,
}
APPEARANCE_LIMITS = {"maximumMeshes": 32, "maximumMaterials": 256, "maximumAttachedActors": 8,
    "maximumActorDepth": 4, "maximumSceneNodes": 128, "maximumSceneDepth": 12,
    "maximumGroomGroupsPerComponent": 16, "maximumGroomGroups": 64}
EXTRA = []
# Each staged leaf is tested using the matching source-specific fixture.
SUITES = {
    "nativePilotGroups": ("DawnwalkerEyeNativePilot", "DawnwalkerEyeNativePilot"),
    "previewGroups": ("DawnwalkerEyePreviewFrameReadOnlyProbe", "DawnwalkerEyePreviewReadOnlyProbe"),
    "exportCameraGroups": ("DawnwalkerEyeFrameExportProbe", "DawnwalkerEyeFrameExportProbe"),
    "variantReadOnlyGroups": ("DawnwalkerEyeVariantReadOnlyProbe", "DawnwalkerEyeVariantReadOnlyProbe"),
    "privatePreviewGroups": ("DawnwalkerPrivateEyePreviewV9Probe", "DawnwalkerPrivateEyePreviewProbe"),
    "geometryGroups": ("DawnwalkerEyePreviewGeometry", "DawnwalkerEyePreviewGeometry"),
    "driverGroups": ("DawnwalkerEyeNativeDriverV8", "ReadOnlyDriver"),
    "dispatchGroups": ("DawnwalkerEyeNativeDispatchV8", "EyeDiscoveryProbe"),
    "humanIrisGroups": ("DawnwalkerHumanIrisRoundtripProbe", "DawnwalkerHumanIrisRoundtripProbe"),
    "inventoryIrisCaptureGroups": ("DawnwalkerInventoryEyeCaptureProbe", "DawnwalkerInventoryEyeCaptureProbe"),
    "bootstrapGroups": ("DawnwalkerEyeNativeBootstrapV8", "main"),
    "appearanceSourcesGroups": ("DawnwalkerAppearanceSourcesV9", "DawnwalkerAppearanceSourcesV9"),
    "geometryV8Groups": ("DawnwalkerEyePreviewGeometryV8", "DawnwalkerEyePreviewGeometryV8"),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def no_links(path: Path) -> None:
    for entry in (path, *path.parents):
        if entry.is_symlink() or entry.is_junction():
            raise ValueError(f"Linked candidate/source path refused: {entry}")


def run(command: list[str]) -> str:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60, check=False)
    if result.returncode:
        raise ValueError(f"Offline validation failed: {command!r}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def validate(stage: Path) -> dict:
    script_root = stage / SCRIPTS
    syntax = []
    for script in sorted(script_root.glob("*.lua")):
        run([str(LUA_BIN / "luac.exe"), "-p", str(script)])
        syntax.append({"path": script.relative_to(stage).as_posix(), "sha256": sha256(script)})
    if len(syntax) != 13:
        raise ValueError("Expected exactly thirteen staged Lua payloads")
    records = []
    for key, (test_name, module_name) in SUITES.items():
        test = TESTS / (test_name + ".Tests.lua")
        no_links(test)
        test_hash = sha256(test)
        output = run([str(LUA_BIN / "lua.exe"), str(test), str(script_root / (module_name + ".lua"))])
        groups = len(re.findall(r"^PASS (?!\d+ )[^\r\n]+", output, flags=re.MULTILINE))
        if not groups or test_hash != sha256(test):
            raise ValueError("Missing measured groups or test source changed: " + test_name)
        records.append({"manifestKey": key, "test": test.relative_to(ROOT).as_posix(),
                        "testSha256": test_hash, "groups": groups,
                        "payload": SCRIPTS + module_name + ".lua"})
    return {"schema": 1, "cyberfox1337x": "function(dawnwalker_eye_offline_validation)",
            "fixtureOnly": True, "runtimeVerified": False, "syntax": syntax, "suites": records,
            "totalGroups": sum(record["groups"] for record in records)}


def main() -> None:
    no_links(DESTINATION)
    if DESTINATION.exists():
        raise ValueError("V8B destination already exists; composer never overwrites a candidate")
    no_links(FROZEN / "manifest.json")
    if sha256(FROZEN / "manifest.json") != PREVIOUS_MANIFEST:
        raise ValueError("Frozen V8 manifest changed")
    no_links(FROZEN / "New-EyePilotAttestation.ps1")
    if sha256(FROZEN / "New-EyePilotAttestation.ps1") != PREVIOUS_ISSUER:
        raise ValueError("Frozen V8 issuer changed")
    manifest = json.loads((FROZEN / "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest["schema"] != 7 or manifest["revision"] != 8 or len(manifest["payload"]) != 15:
        raise ValueError("Frozen V8 profile differs")
    if manifest["privatePreviewProfile"] != PROFILE or manifest["appearanceLimits"] != APPEARANCE_LIMITS:
        raise ValueError("Frozen V8 limits/profile differs")
    inputs = []
    for record in manifest["payload"]:
        previous = FROZEN / record["path"]
        no_links(previous)
        if sha256(previous) != record["sha256"] or previous.stat().st_size != record["bytes"]:
            raise ValueError("Frozen V8 payload changed: " + record["path"])
        replacement = REPLACEMENTS.get(record["path"].removeprefix(SCRIPTS)) if record["path"].startswith(SCRIPTS) else None
        selected = SOURCE / replacement if replacement else previous
        no_links(selected)
        relative = record["path"]
        leaf = relative.removeprefix(SCRIPTS)
        if leaf in RENAMED_PAYLOADS:
            relative = SCRIPTS + RENAMED_PAYLOADS[leaf]
        inputs.append((relative, selected, sha256(selected)))
    for name in EXTRA:
        selected = SOURCE / name
        no_links(selected)
        inputs.append((SCRIPTS + name, selected, sha256(selected)))
    # Validate an isolated temporary copy before exposing a candidate directory.
    with tempfile.TemporaryDirectory(prefix="dawnwalker-eye-v8b-") as temporary:
        stage = Path(temporary)
        if stage.resolve().parent != Path(tempfile.gettempdir()).resolve() or not stage.name.startswith("dawnwalker-eye-v8b-"):
            raise ValueError("Temporary validation directory escaped its explicit root")
        no_links(stage)
        for relative, selected, expected in inputs:
            destination = stage / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(selected, destination)
            if sha256(destination) != expected:
                raise ValueError("Source changed while staging: " + relative)
        evidence = validate(stage)
        issuer = (FROZEN / "New-EyePilotAttestation.ps1").read_text(encoding="utf-8-sig")
        if issuer.count("$manifest.schema -ne 7 -or $manifest.revision -ne 8") != 1 or issuer.count("'schema=7'") != 1:
            raise ValueError("Frozen issuer schema guard differs")
        if issuer.count("DawnwalkerAppearanceSources.lua") != 2:
            raise ValueError("Frozen appearance helper issuer allowlists differ")
        issuer = issuer.replace("DawnwalkerAppearanceSources.lua", "DawnwalkerAppearanceSourcesV9.lua")
        (stage / "New-EyePilotAttestation.ps1").write_text(issuer, encoding="utf-8", newline="\n")
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        if powershell is None:
            raise ValueError("PowerShell parser is unavailable")
        issuer_path = str(stage / "New-EyePilotAttestation.ps1").replace("'", "''")
        run([powershell, "-NoProfile", "-Command",
             "$tokens=$null; $parseErrors=$null; [System.Management.Automation.Language.Parser]::ParseFile('"
             + issuer_path + "',[ref]$tokens,[ref]$parseErrors) | Out-Null; if ($parseErrors.Count) { throw ($parseErrors | Out-String) }"])
        evidence["issuerSyntaxVerified"] = True
        evidence["issuerSha256"] = sha256(stage / "New-EyePilotAttestation.ps1")
        shutil.copyfile(ROOT / "qa/eye-appearance/V8B-NATIVE-PILOT.md", stage / "README.md")
        manifest.update(schema=7, revision=8, preparedAtUtc=datetime.now(timezone.utc).isoformat(), privatePreviewProfile=PROFILE, appearanceLimits=APPEARANCE_LIMITS)
        manifest["privatePreviewLimits"].update(maxFramesPerAttempt=9, renderTargetFormat=2, captureSource=9, targetGamma=0)
        manifest["sourceProvenance"]["privatePreview"] = "analysis/dawnwalker-uue4ss/probes/DawnwalkerPrivateEyePreviewV9Probe.lua"
        manifest["sourceProvenance"]["appearanceSources"] = "analysis/dawnwalker-uue4ss/probes/DawnwalkerAppearanceSourcesV9.lua"
        manifest["offlineTests"] = {record["manifestKey"]: record["groups"] for record in evidence["suites"]}
        manifest["observedEvidence"].append("qa/eye-appearance/live-20260906/human-private-preview-v8.json")
        manifest["payload"] = [{"path": relative, "bytes": (stage / relative).stat().st_size,
                                "sha256": sha256(stage / relative)} for relative, _, _ in inputs]
        for record in evidence["suites"]:
            source_key = record["manifestKey"].removesuffix("Groups")
            provenance = ROOT / manifest["sourceProvenance"][source_key]
            no_links(provenance)
            if sha256(provenance) != sha256(stage / record["payload"]):
                raise ValueError("Recorded source provenance differs from tested payload: " + source_key)
            record["source"] = provenance.relative_to(ROOT).as_posix()
            record["sourceSha256"] = sha256(provenance)
        for relative, selected, expected in inputs:
            if sha256(selected) != expected or sha256(stage / relative) != expected:
                raise ValueError("Source or tested payload changed before freeze: " + relative)
        (stage / "offline-validation.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8", newline="\n")
        (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
        no_links(DESTINATION)
        shutil.copytree(stage, DESTINATION)
    print(json.dumps({"candidate": str(DESTINATION), "manifestSha256": sha256(DESTINATION / "manifest.json"),
                      "issuerSha256": sha256(DESTINATION / "New-EyePilotAttestation.ps1"),
                      "payloadFiles": len(inputs), "offlineGroups": evidence["totalGroups"],
                      "gameFilesChanged": False}, indent=2))


if __name__ == "__main__":
    main()
