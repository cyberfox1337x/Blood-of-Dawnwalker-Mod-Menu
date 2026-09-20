# Current-build Player resource regression

This isolated candidate targets Steam build 25129649 / CL-257186. The production contracts remain unchanged. Staging does not grant gameplay compatibility. Existing reflection comparison reports 1627 matching native objects; marshaling, ownership and gameplay need fresh evidence.

`Stage-PlayerPilot.ps1` prepared a local exact-identity contract, verified archive copy, inert templates and bridge-pilot templates. `staging-validation.json` records validation. Bridge source is deliberately taken from the canonical integration path by the existing verifier; revalidate immediately before promotion if another worker changes it.

## Desktop operator sequence

Keep the full verified current save backup and installed eye transaction. With the game closed, preserve current eye logs/output, then use that transaction's own rollback procedure and verify it. Do not reuse its state directory for this pilot. Restoring an older baseline may restore an old enabled gameplay bridge; replace it with the inert candidate before launching.

From the project root, after that rollback:

```powershell
$playerRoot = (Resolve-Path -LiteralPath 'qa\player-current-build').Path
$contractPath = Join-Path $playerRoot 'official-build.player-pilot.json'
$stateRoot = Join-Path $playerRoot 'state'
$archivePath = Join-Path $playerRoot 'vendor\zDEV-UE4SS_v3.0.1-1111-g97b7e501.zip'
Import-Module '.\analysis\dawnwalker-uue4ss\DawnwalkerReflectionTools.psm1' -Force
Invoke-DawnwalkerReflectionInstall -ContractPath $contractPath -ArchivePath $archivePath -TemplatesRoot (Join-Path $playerRoot 'templates') -StateRoot $stateRoot -ReplaceExisting -WhatIf
Invoke-DawnwalkerReflectionInstall -ContractPath $contractPath -ArchivePath $archivePath -TemplatesRoot (Join-Path $playerRoot 'templates') -StateRoot $stateRoot -ReplaceExisting -Confirm:$false
```

Inspect installed inert settings/registry, then launch normally to the main menu and exit normally. Preserve the fresh log, visible smoke result and identity. With the game stopped and smoke reviewed:

```powershell
$identity = Test-DawnwalkerOfficialBuild -ContractPath $contractPath -RequireStopped
if (-not $identity.installationEligible) { throw 'Current build identity changed.' }
$smokeLog = Join-Path $identity.paths.win64 'ue4ss\UE4SS.log'
Enable-DawnwalkerBridgePilot -ContractPath $contractPath -StateRoot $stateRoot -PilotTemplatesRoot (Join-Path $playerRoot 'templates\bridge-pilot') -SmokeLogPath $smokeLog -ApproveCleanSmokeLog -ApproveHookEngineTickPilot -WhatIf
Enable-DawnwalkerBridgePilot -ContractPath $contractPath -StateRoot $stateRoot -PilotTemplatesRoot (Join-Path $playerRoot 'templates\bridge-pilot') -SmokeLogPath $smokeLog -ApproveCleanSmokeLog -ApproveHookEngineTickPilot -Confirm:$false
```

The helper checks stopped identity, matching unpromoted inert transaction, source invariants, approved single EngineTick hook, smoke log and installed payload. Do not edit ownership records to force acceptance.

Launch and load the protected offline save. Keep the character stationary outside combat for the strict baseline roundtrip; natural regeneration or depletion between commands can legitimately cause baseline mismatch and must be investigated rather than ignored. Close the desktop bridge client while the standalone harness owns transport. Record fresh boot ID. First run the command below with `--execute read-only` and a separate unused evidence filename, then run the roundtrip:

```powershell
node qa/player-current-build/resource-roundtrip.mjs --execute resource-roundtrip --boot-id OBSERVED_BOOT_ID --bridge-root "$env:TEMP\DawnwalkerModMenuBridge" --game-exe $identity.paths.executable --evidence qa/player-current-build/resource-live-UNIQUE.json
```

Use an unused evidence filename. The runner verifies the exact executable hash and length before issuing commands. It parses the actual canonical Lua capability list and requires that exact advertised subset through the existing transport; it does not pretend the absent Sprint capability exists. The older full-suite runner still expects its default capability list and should not be used unchanged. The isolated runner only dispatches player-info, health, stamina and God Mode. It tests independent toggles plus both release orders of overlapping God/individual owners; each successful disable gets independent baseline readback. A possibly applied enable is included in cleanup even if its response is lost. A changed/disconnected session is not sent stale rollback. Cleanup failures stay explicit in evidence.

Optional `--hold-ms 10000` adds a bounded enabled interval for the desktop operator. A passing run is **command/readback and restoration evidence**, not invulnerability, damage prevention, sprint endurance or absence of one-frame death. Those require separate visible action and sampled-resource evidence using `scripts/Sample-DawnwalkerPlayerState.mjs`. Do not label gameplay complete from this harness alone.

After tests, disable all owned controls, verify the empty active set, close normally, preserve outputs, and restore the complete protected save backup with a path/length/hash comparison. If reverting runtime, use `Invoke-DawnwalkerReflectionRollback` with this exact contract and state root; preserve the resulting baseline's identity before any further launch.

## Offline validation

```powershell
node --test qa/player-current-build/resource-roundtrip.test.mjs
```

Five tests cover successful ownership roundtrips, lost enable response cleanup, replacement-session refusal, incorrect shared-owner unlock detection, and refusal to interfere with preexisting active capabilities. No live command is issued by importing the harness or running its tests.

## Bounded numeric roundtrip

`numeric-roundtrip.mjs` tests only Blood Energy, Trait Points and Gold, with all baselines queried before mutation. Blood uses an absolute percentage target of 80; Trait Points uses baseline plus one then its absolute baseline; Gold uses a delta of plus one then minus one. No level, trait unlock, respec or item command is allowed. If blood already equals 80, that step is explicitly skipped rather than counted as a distinct mutation.

```powershell
node --test qa/player-current-build/numeric-roundtrip.test.mjs
node qa/player-current-build/numeric-roundtrip.mjs --execute numeric-roundtrip --boot-id OBSERVED_BOOT_ID --bridge-root "$env:TEMP\DawnwalkerModMenuBridge" --game-exe $identity.paths.executable --evidence qa/player-current-build/numeric-live-UNIQUE.json
```

Six fake-only tests cover full restoration, lost gold enable response, lost inverse response without duplicate subtraction, unrelated balance changes, boot replacement and trait setter bounds. After any potentially applied mutation, cleanup queries first and only restores if the observed amount is the original baseline or the exact owned target. Unexpected changes require protected-save recovery; they are not overwritten. A lost inverse response is checked independently and never retried blindly. Keep the same stationary living pawn, with no gameplay, form, save, possession or session transition during the run. This establishes immediate readback restoration only; close-game save restoration and any reload proof remain separate.
