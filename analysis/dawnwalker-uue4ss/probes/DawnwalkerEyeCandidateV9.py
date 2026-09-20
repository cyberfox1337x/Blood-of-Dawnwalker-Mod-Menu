"""Validate and compose a new V9 candidate; never overwrite or install one."""
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


cyberfox1337x("dawnwalker_eye_candidate_v9_composer")
ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).resolve().parent
TESTS = SOURCE.parent / "tests"
FROZEN = ROOT / "qa/eye-appearance/native-pilot-candidate-v8b"
DESTINATION = ROOT / "qa/eye-appearance/native-pilot-candidate-v9"
PREVIOUS_MANIFEST = "E7D9FFF612A4D323B7D3F3FBCD242EA25DD776C47FC8332F58ED117358F27AE3"
PREVIOUS_ISSUER = "FFC59A36E8BC0B17DBCE4EB66088836C2FC3AC43A1F533FA6A23BB8E26A5209D"
SCRIPTS = "Mods/DawnwalkerRequestedReadOnly/Scripts/"
LUA_BIN = Path("C:/Users/Cyberfox1337/AppData/Local/Programs/Lua/bin")
REPLACEMENTS = {
    "main.lua": "DawnwalkerEyeNativeBootstrapV9.lua",
    "ReadOnlyDriver.lua": "DawnwalkerEyeNativeDriverV9.lua",
    "EyeDiscoveryProbe.lua": "DawnwalkerEyeNativeDispatchV9.lua",
}
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
EXTRA = ["DawnwalkerHumanEyeBindings.lua", "DawnwalkerEyeSessionDispatch.lua", "DawnwalkerEyeSessionHost.lua",
         "DawnwalkerEyePreviewSession.lua", "DawnwalkerPrivateEyeRenderer.lua", "DawnwalkerEyeSessionPilot.lua"]
EXTRA_SOURCES = {"DawnwalkerPrivateEyeRenderer.lua": "DawnwalkerPrivateEyeRendererV9.lua"}
SESSION_PROFILE = {"maximumHostsPerBoot": 1, "maximumHostLifetimeMs": 300000, "maximumResponses": 64,
    "maximumPreviewSessions": 3, "leaseMs": 10000, "maximumPreviewLifetimeMs": 30000,
    "minimumFrameIntervalMs": 100, "maximumFramesPerPreview": 12, "pollIntervalMs": 100,
    "requestByteLimit": 32768, "responseByteLimit": 262144, "ownerSource": "session-start-attestation-nonce",
    "channelRoot": "qa/eye-appearance/native-channel", "channelFiles": ["command.txt", "response.txt", "response.tmp", "channel.ready"],
    "frameRoot": "qa/eye-appearance/native-frames", "wireVersion": 1,
    "commandOperations": ["inspect", "open", "enqueue", "step", "renew", "cancel", "apply", "restore", "ack", "close"],
    "producesUnrequestedFrames": False, "restoresOnStop": False, "productionReady": False,
    "cleanupReserveResponses": 8, "cleanupReserveMs": 30000}
# Each staged leaf is tested using the matching source-specific fixture.
SUITES = {
    "nativePilotGroups": ("DawnwalkerEyeNativePilot", "DawnwalkerEyeNativePilot"),
    "previewGroups": ("DawnwalkerEyePreviewFrameReadOnlyProbe", "DawnwalkerEyePreviewReadOnlyProbe"),
    "exportCameraGroups": ("DawnwalkerEyeFrameExportProbe", "DawnwalkerEyeFrameExportProbe"),
    "variantReadOnlyGroups": ("DawnwalkerEyeVariantReadOnlyProbe", "DawnwalkerEyeVariantReadOnlyProbe"),
    "privatePreviewGroups": ("DawnwalkerPrivateEyePreviewV9Probe", "DawnwalkerPrivateEyePreviewProbe"),
    "geometryGroups": ("DawnwalkerEyePreviewGeometry", "DawnwalkerEyePreviewGeometry"),
    "driverGroups": ("DawnwalkerEyeNativeDriverV9", "ReadOnlyDriver"),
    "dispatchGroups": ("DawnwalkerEyeNativeDispatchV9", "EyeDiscoveryProbe"),
    "humanIrisGroups": ("DawnwalkerHumanIrisRoundtripProbe", "DawnwalkerHumanIrisRoundtripProbe"),
    "inventoryIrisCaptureGroups": ("DawnwalkerInventoryEyeCaptureProbe", "DawnwalkerInventoryEyeCaptureProbe"),
    "bootstrapGroups": ("DawnwalkerEyeNativeBootstrapV9", "main"),
    "appearanceSourcesGroups": ("DawnwalkerAppearanceSourcesV9", "DawnwalkerAppearanceSourcesV9"),
    "geometryV8Groups": ("DawnwalkerEyePreviewGeometryV8", "DawnwalkerEyePreviewGeometryV8"),
    "humanEyeBindingsGroups": ("DawnwalkerHumanEyeBindings", "DawnwalkerHumanEyeBindings"),
    "sessionDispatchGroups": ("DawnwalkerEyeSessionDispatch", "DawnwalkerEyeSessionDispatch"),
    "sessionHostGroups": ("DawnwalkerEyeSessionHost", "DawnwalkerEyeSessionHost"),
    "previewSessionGroups": ("DawnwalkerEyePreviewSession", "DawnwalkerEyePreviewSession"),
    "privateRendererGroups": ("DawnwalkerPrivateEyeRendererV9", "DawnwalkerPrivateEyeRenderer"),
    "sessionPilotGroups": ("DawnwalkerEyeSessionPilot", "DawnwalkerEyeSessionPilot"),
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
    if len(syntax) != 19:
        raise ValueError("Expected exactly nineteen staged Lua payloads")
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


def compose_issuer(issuer: str) -> str:
    old_schema = "$manifest.schema -ne 7 -or $manifest.revision -ne 8"
    if issuer.count(old_schema) != 1 or issuer.count("'schema=7'") != 1:
        raise ValueError("Frozen issuer schema guard differs")
    issuer = issuer.replace(old_schema, "$manifest.schema -ne 8 -or $manifest.revision -ne 9")
    issuer = issuer.replace("'schema=7'", "'schema=8'")
    payload_end = "'Mods/DawnwalkerRequestedReadOnly/Scripts/DawnwalkerEyePreviewGeometryV8.lua')"
    scripts_end = "'DawnwalkerEyePreviewGeometryV8.lua', 'attestation.txt')"
    if issuer.count(payload_end) != 1 or issuer.count(scripts_end) != 1:
        raise ValueError("Frozen issuer payload allowlist changed")
    issuer = issuer.replace(payload_end, "'Mods/DawnwalkerRequestedReadOnly/Scripts/DawnwalkerEyePreviewGeometryV8.lua',\n    "
        + ",\n    ".join("'" + SCRIPTS + name + "'" for name in EXTRA) + ")")
    issuer = issuer.replace(scripts_end, "'DawnwalkerEyePreviewGeometryV8.lua', "
        + ", ".join("'" + name + "'" for name in EXTRA) + ", 'attestation.txt')")
    validate_end = "'private-preview-roundtrip', 'human-iris-pair-roundtrip')]"
    intent_end = "    'human-iris-pair-roundtrip' = 'human-iris-pair-roundtrip'"
    frame_end = "'private-preview-roundtrip', 'human-iris-pair-roundtrip')) {"
    nonce_line = "$nonce = [Guid]::NewGuid().ToString('N')"
    for anchor in (validate_end, intent_end, frame_end, nonce_line):
        if issuer.count(anchor) != 1:
            raise ValueError("Frozen issuer session insertion point differs: " + anchor)
    issuer = issuer.replace(validate_end, "'private-preview-roundtrip', 'human-iris-pair-roundtrip', 'session-start', 'session-stop')]")
    issuer = issuer.replace(intent_end, intent_end + "\n    'session-start' = 'eye-session-start'; 'session-stop' = 'eye-session-stop'")
    issuer = issuer.replace(frame_end, "'private-preview-roundtrip', 'human-iris-pair-roundtrip', 'session-start')) {")
    channel_block = r"""
if ($Operation -ceq 'session-start') {
    $channelRoot = Join-Path $projectRoot 'qa\eye-appearance\native-channel'
    $expectedChannelRoot = 'C:\Users\Cyberfox1337\Documents\ChatGPT\The Blood of DawnWalker\qa\eye-appearance\native-channel'
    if ([IO.Path]::GetFullPath($channelRoot) -ine $expectedChannelRoot) { throw 'Native channel root differs from frozen host.' }
    $channelBootDirectory = Join-Path $channelRoot $BootId
    $channelDirectory = Join-Path $channelBootDirectory $nonce
    Assert-EyeNoReparseAncestors -LiteralPath $channelDirectory
    if (Test-Path -LiteralPath $channelDirectory) { throw 'Native channel owner directory already exists.' }
    New-Item -ItemType Directory -Path $channelDirectory | Out-Null
    Assert-EyeNoReparseAncestors -LiteralPath $channelDirectory
    if (@(Get-ChildItem -LiteralPath $channelDirectory -Force).Count -ne 0) { throw 'New native channel is not empty.' }
}
"""
    issuer = issuer.replace(nonce_line, nonce_line + channel_block.rstrip())
    return issuer


def main() -> None:
    no_links(DESTINATION)
    if DESTINATION.exists():
        raise ValueError("V9 destination already exists; composer never overwrites a candidate")
    no_links(FROZEN / "manifest.json")
    if sha256(FROZEN / "manifest.json") != PREVIOUS_MANIFEST:
        raise ValueError("Frozen V8B manifest changed")
    no_links(FROZEN / "New-EyePilotAttestation.ps1")
    if sha256(FROZEN / "New-EyePilotAttestation.ps1") != PREVIOUS_ISSUER:
        raise ValueError("Frozen V8B issuer changed")
    manifest = json.loads((FROZEN / "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest["schema"] != 7 or manifest["revision"] != 8 or len(manifest["payload"]) != 15:
        raise ValueError("Frozen V8B profile differs")
    inputs = []
    for record in manifest["payload"]:
        previous = FROZEN / record["path"]
        no_links(previous)
        if sha256(previous) != record["sha256"] or previous.stat().st_size != record["bytes"]:
            raise ValueError("Frozen V8B payload changed: " + record["path"])
        replacement = REPLACEMENTS.get(record["path"].removeprefix(SCRIPTS)) if record["path"].startswith(SCRIPTS) else None
        selected = SOURCE / replacement if replacement else previous
        no_links(selected)
        inputs.append((record["path"], selected, sha256(selected)))
    for name in EXTRA:
        selected = SOURCE / EXTRA_SOURCES.get(name, name)
        no_links(selected)
        inputs.append((SCRIPTS + name, selected, sha256(selected)))
    # Validate an isolated temporary copy before exposing a candidate directory.
    with tempfile.TemporaryDirectory(prefix="dawnwalker-eye-v9-") as temporary:
        stage = Path(temporary)
        if stage.resolve().parent != Path(tempfile.gettempdir()).resolve() or not stage.name.startswith("dawnwalker-eye-v9-"):
            raise ValueError("Temporary validation directory escaped its explicit root")
        no_links(stage)
        for relative, selected, expected in inputs:
            destination = stage / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(selected, destination)
            if sha256(destination) != expected:
                raise ValueError("Source changed while staging: " + relative)
        evidence = validate(stage)
        issuer = compose_issuer((FROZEN / "New-EyePilotAttestation.ps1").read_text(encoding="utf-8-sig"))
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
        shutil.copyfile(ROOT / "qa/eye-appearance/V9-SESSION-PILOT.md", stage / "README.md")
        manifest.update(schema=8, revision=9, preparedAtUtc=datetime.now(timezone.utc).isoformat(), privatePreviewProfile=PROFILE, appearanceLimits=APPEARANCE_LIMITS, sessionProfile=SESSION_PROFILE)
        manifest["privatePreviewLimits"].update(maxFramesPerAttempt=9, renderTargetFormat=2, captureSource=9, targetGamma=0)
        for key, leaf in [("bootstrap", "main.lua"), ("driver", "ReadOnlyDriver.lua"),
                          ("dispatch", "EyeDiscoveryProbe.lua")]:
            manifest["sourceProvenance"][key] = "analysis/dawnwalker-uue4ss/probes/" + REPLACEMENTS[leaf]
        manifest["sourceProvenance"].update(appearanceSources="analysis/dawnwalker-uue4ss/probes/DawnwalkerAppearanceSourcesV9.lua",
            geometryV8="analysis/dawnwalker-uue4ss/probes/DawnwalkerEyePreviewGeometryV8.lua")
        manifest["sourceProvenance"].update(humanEyeBindings="analysis/dawnwalker-uue4ss/probes/DawnwalkerHumanEyeBindings.lua",
            sessionDispatch="analysis/dawnwalker-uue4ss/probes/DawnwalkerEyeSessionDispatch.lua",
            sessionHost="analysis/dawnwalker-uue4ss/probes/DawnwalkerEyeSessionHost.lua",
            previewSession="analysis/dawnwalker-uue4ss/probes/DawnwalkerEyePreviewSession.lua",
            privateRenderer="analysis/dawnwalker-uue4ss/probes/DawnwalkerPrivateEyeRendererV9.lua",
            sessionPilot="analysis/dawnwalker-uue4ss/probes/DawnwalkerEyeSessionPilot.lua")
        manifest["operationProfile"].extend([
            {"operation": "session-start", "intent": "eye-session-start", "mutatesRuntime": True, "writesArtifacts": True, "requiresEyeBaseline": False},
            {"operation": "session-stop", "intent": "eye-session-stop", "mutatesRuntime": True, "writesArtifacts": False, "requiresEyeBaseline": False}])
        manifest["offlineTests"] = {record["manifestKey"]: record["groups"] for record in evidence["suites"]}
        manifest["observedEvidence"].extend([
            "qa/eye-appearance/live-20260906/human-variant-observe-v8b.json",
            "qa/eye-appearance/live-20260906/human-private-preview-v8b.json",
            "qa/eye-appearance/live-20260906/human-private-preview-v8b-cleanup.json",
            "qa/eye-appearance/live-20260906/human-private-preview-v8b-correspondence.json"])
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
