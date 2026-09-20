"""Validate and compose a new V11 candidate; never overwrite or install one.

V11 differs from the frozen V10 candidate in exactly one payload: the private preview renderer,
which moves from DawnwalkerPrivateEyeRendererV10.lua to DawnwalkerPrivateEyeRendererV11.lua. The
bounded runtime profile is deliberately unchanged, so the manifest stays at schema 8 / revision 9
- the transaction helper requires revision == schema + 1, and a materially new profile would need
an explicit forward schema, policy, issuer and test agreement that this correction does not need.
Because the profile is unchanged the frozen V10 issuer (itself the V9 issuer, reused verbatim) is
reused rather than rewritten.
"""
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


cyberfox1337x("dawnwalker_eye_candidate_v11_composer")
ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).resolve().parent
TESTS = SOURCE.parent / "tests"
FROZEN = ROOT / "qa/eye-appearance/native-pilot-candidate-v10"
DESTINATION = ROOT / "qa/eye-appearance/native-pilot-candidate-v11"
PREVIOUS_MANIFEST = "E96875BD6A14E3A19711D3AE4A7A96421E0794E39D009266CF06A1597437F10F"
PREVIOUS_ISSUER = "B0688C564A6926B5040E1D880CB4F3E849386FFFAB24DFD3A6C84CE647ABA050"
SCRIPTS = "Mods/DawnwalkerRequestedReadOnly/Scripts/"
LUA_BIN = Path("C:/Users/Cyberfox1337/AppData/Local/Programs/Lua/bin")
README_SOURCE = ROOT / "qa/eye-appearance/V11-SESSION-PILOT.md"
# The only staged leaf whose source changes. Every other payload is reused byte-identically
# from the frozen V10 candidate after its recorded hash is re-verified.
REPLACEMENTS = {"DawnwalkerPrivateEyeRenderer.lua": "DawnwalkerPrivateEyeRendererV11.lua"}
RENDERER_PROVENANCE = "analysis/dawnwalker-uue4ss/probes/DawnwalkerPrivateEyeRendererV11.lua"
EXPECTED_LUA_PAYLOADS = 19
EXPECTED_PAYLOADS = 21
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
    "privateRendererGroups": ("DawnwalkerPrivateEyeRendererV11", "DawnwalkerPrivateEyeRenderer"),
    "sessionPilotGroups": ("DawnwalkerEyeSessionPilot", "DawnwalkerEyeSessionPilot"),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def no_links(path: Path) -> None:
    for entry in (path, *path.parents):
        if entry.is_symlink() or entry.is_junction():
            raise ValueError(f"Linked candidate/source path refused: {entry}")


def run(command: list[str]) -> str:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120, check=False)
    if result.returncode:
        raise ValueError(f"Offline validation failed: {command!r}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def validate(stage: Path) -> dict:
    script_root = stage / SCRIPTS
    syntax = []
    for script in sorted(script_root.glob("*.lua")):
        run([str(LUA_BIN / "luac.exe"), "-p", str(script)])
        syntax.append({"path": script.relative_to(stage).as_posix(), "sha256": sha256(script)})
    if len(syntax) != EXPECTED_LUA_PAYLOADS:
        raise ValueError(f"Expected exactly {EXPECTED_LUA_PAYLOADS} staged Lua payloads")
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


def verify_issuer(issuer: str) -> None:
    """The bounded profile is unchanged, so the frozen issuer is reused exactly as written."""
    guard = "$manifest.schema -ne 8 -or $manifest.revision -ne 9"
    if issuer.count(guard) != 1 or issuer.count("'schema=8'") != 1:
        raise ValueError("Frozen V10 issuer schema guard differs; V11 reuses it unchanged")
    for anchor in ("'session-start' = 'eye-session-start'", "'session-stop' = 'eye-session-stop'",
                   "'" + SCRIPTS + "DawnwalkerPrivateEyeRenderer.lua'"):
        if issuer.count(anchor) != 1:
            raise ValueError("Frozen V10 issuer session or payload allowlist differs: " + anchor)


def main() -> None:
    no_links(DESTINATION)
    if DESTINATION.exists():
        raise ValueError("V11 destination already exists; composer never overwrites a candidate")
    no_links(FROZEN / "manifest.json")
    if sha256(FROZEN / "manifest.json") != PREVIOUS_MANIFEST:
        raise ValueError("Frozen V10 manifest changed")
    no_links(FROZEN / "New-EyePilotAttestation.ps1")
    if sha256(FROZEN / "New-EyePilotAttestation.ps1") != PREVIOUS_ISSUER:
        raise ValueError("Frozen V10 issuer changed")
    no_links(README_SOURCE)
    manifest = json.loads((FROZEN / "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest["schema"] != 8 or manifest["revision"] != 9 or len(manifest["payload"]) != EXPECTED_PAYLOADS:
        raise ValueError("Frozen V10 profile differs")
    replaced = 0
    inputs = []
    for record in manifest["payload"]:
        previous = FROZEN / record["path"]
        no_links(previous)
        if sha256(previous) != record["sha256"] or previous.stat().st_size != record["bytes"]:
            raise ValueError("Frozen V10 payload changed: " + record["path"])
        replacement = REPLACEMENTS.get(record["path"].removeprefix(SCRIPTS)) if record["path"].startswith(SCRIPTS) else None
        selected = SOURCE / replacement if replacement else previous
        no_links(selected)
        if replacement:
            replaced += 1
            if sha256(selected) == record["sha256"]:
                raise ValueError("The V11 renderer payload is identical to V10; there is nothing to compose")
        inputs.append((record["path"], selected, sha256(selected)))
    if replaced != len(REPLACEMENTS):
        raise ValueError("The frozen V10 manifest does not carry every replaced payload")
    # Validate an isolated temporary copy before exposing a candidate directory.
    with tempfile.TemporaryDirectory(prefix="dawnwalker-eye-v11-") as temporary:
        stage = Path(temporary)
        if stage.resolve().parent != Path(tempfile.gettempdir()).resolve() or not stage.name.startswith("dawnwalker-eye-v11-"):
            raise ValueError("Temporary validation directory escaped its explicit root")
        no_links(stage)
        for relative, selected, expected in inputs:
            destination = stage / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(selected, destination)
            if sha256(destination) != expected:
                raise ValueError("Source changed while staging: " + relative)
        evidence = validate(stage)
        issuer_text = (FROZEN / "New-EyePilotAttestation.ps1").read_text(encoding="utf-8-sig")
        verify_issuer(issuer_text)
        (stage / "New-EyePilotAttestation.ps1").write_text(issuer_text, encoding="utf-8", newline="\n")
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        if powershell is None:
            raise ValueError("PowerShell parser is unavailable")
        issuer_path = str(stage / "New-EyePilotAttestation.ps1").replace("'", "''")
        run([powershell, "-NoProfile", "-Command",
             "$tokens=$null; $parseErrors=$null; [System.Management.Automation.Language.Parser]::ParseFile('"
             + issuer_path + "',[ref]$tokens,[ref]$parseErrors) | Out-Null; if ($parseErrors.Count) { throw ($parseErrors | Out-String) }"])
        evidence["issuerSyntaxVerified"] = True
        evidence["issuerSha256"] = sha256(stage / "New-EyePilotAttestation.ps1")
        shutil.copyfile(README_SOURCE, stage / "README.md")
        # Schema, revision and every bounded profile stay exactly as V10 recorded them.
        manifest.update(preparedAtUtc=datetime.now(timezone.utc).isoformat())
        manifest["sourceProvenance"]["privateRenderer"] = RENDERER_PROVENANCE
        manifest["offlineTests"] = {record["manifestKey"]: record["groups"] for record in evidence["suites"]}
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
                      "payloadFiles": len(inputs), "replacedPayloads": replaced,
                      "offlineGroups": evidence["totalGroups"], "gameFilesChanged": False}, indent=2))


if __name__ == "__main__":
    main()