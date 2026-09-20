# Dawnwalker HookEngineTick bridge pilot

`cyberfox1337x.function("dawnwalker_hook_engine_tick_bridge_pilot_document")`

This is an isolated, reversible analysis profile for the official pinned single-player build. It is not a production or release profile, does not launch Dawnwalker, and does not create runtime proof automatically. It promotes only from a new, exact inert-smoke transaction after the user has launched offline, exited normally, reviewed the installed loader's fresh `UE4SS.log`, and explicitly approved both the clean log and the one-hook pilot. The current `0.3.21-pilot` source keeps Unlimited Weight withdrawn, retains the live-verified bounded Quest Journal path from `0.3.7`, the Add Gold contract and persistence proof from `0.3.8`, the fail-closed teardown-state retention added in `0.3.9`, and the global F9 Add Gold binding that `0.3.10` proved live; it adds the two-axis Combat difficulty controls that `0.3.11` through `0.3.15` could not iterate safely, Add Item on `0.3.17`, the Add Level plus Unblock Trait additions of `0.3.18`, the FName-safe roster resolution of `0.3.19`, the all-shapes roster unwrap of `0.3.20`, and the deferred later-tick unblock verification of `0.3.21`. Version `0.3.19` is the FName-safe correction of `0.3.18`: the Unblock Trait handler crashed the game live because raw Lua strings were passed into `const FName&` parameters, so `0.3.19` resolves ids through the `GetAllTraits()` roster and never passes a raw request string into an FName-typed engine call. Promoted `0.3.19` was then probed live: Add Level passed a bounded level-1-to-2 cycle with exact readback and save restore, while the same session proved Unblock Trait could not resolve any id because the live `GetAllTraits()` container returns wrapped entries that only the ForEach read shape unwrapped. Version `0.3.20` corrects that by unwrapping every container entry on all three read shapes; its live probe then proved roster resolution works (112 traits enumerated) and that `UnblockTraitToLevel` commits its level exactly one game beat late, so version `0.3.21` defers the readback verdict to a bounded later-tick verification and never reports a succeeded call as a failure; its live probe then passed on boot `1788474671-718541`. Historical `0.3.8` and `0.3.10` evidence remains tied to those exact bridge identities. The `0.3.9` teardown retry is the only source change carried forward that still has no live run of its own.

## Exact pilot boundary

- `HookEngineTick = 1` is the only enabled `Hook*` setting.
- `DawnwalkerModBridge : 1` is the only enabled mod.
- UE4SS GUI console remains disabled and load-all-assets remains disabled.
- The bridge is copied at promotion time from `integration/uue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua`; a second editable template copy is not maintained.
- The current bridge source identifies itself as `0.3.21-pilot` and advertises exactly these 19 capability IDs after a valid playable `ADawnwalkerPlayerCharacter` is available and no teardown retry is pending:

  - Player: `player:infinite-health`, `player:unlimited-stamina`, `player:blood-energy`, `player:god-mode`, `player:player-info`, `player:trait-points`, `player:add-gold`, `player:add-level`, and `player:unblock-trait`.
  - Inventory: `inventory:add-item`.
  - Combat: `combat:infinite-blood-energy`, `combat:rpg-difficulty`, and `combat:action-difficulty`.
  - Quests: `quests:journal-readback`.
  - Teleport: `teleport:save-location` and `teleport:teleport-saved-location`.
  - Visuals: `visuals:hud-visible`.
  - World: `world:game-speed` and `world:location-readback`.

- Every UObject call is queued through the EngineTick game-thread route and guarded by the bridge's protected command execution. A capability is not advertised while the game thread or the Dawnwalker player pawn is unavailable.
- The installed settings, mod registry, bridge source, active state file, and transaction-local state file are all snapshotted before any promoted byte is written.
- Any promotion failure restores all five snapshots. The existing full `Rollback` action still captures the pilot tree and restores the original pre-install loader baseline.

## Current verification status

The corrected `0.3.1-pilot` reached a playable pawn with the earlier 12-capability handshake. A later `0.3.2-pilot` experiment advertised Unlimited Weight, but live inspection proved its selected gameplay effect was already part of normal game state and only permits over-limit pickups. It does not disable the inventory weight limit or clear encumbrance, so that implementation is retired. The `0.3.3-pilot` source removed that handler and capability. Reversible `0.3.4-pilot`, `0.3.5-pilot`, and `0.3.6-pilot` Quest Journal attempts all rejected safely without mutation while refining the live wrapper contract. Corrected `0.3.7-pilot` passed on boot `1788414524-513788`: automated QA returned two bounded quests, including tracked `Withering Away`, while all six unrelated queries stayed valid and the active set stayed empty. The pinned artifacts are `dawnwalker-live-pilot-qa-20260903T055247Z.json` (SHA-256 `B4123167CA1CE198A92377C08648F795F5D2398AD8C902E8D835E875AF3D4FF4`) and `dawnwalker-quest-journal-live-success-20260903T055441Z.json` (SHA-256 `E679C347A0F1D6F59EAB37A5613D66D85983720E1D34FE0E60E6F5D7A1FCBC25`). Version `0.3.8-pilot` introduced Add Gold and was promoted as a separate historical artifact. Version `0.3.9-pilot` retained the same 14 capabilities and added unresolved teardown-state retention without deployment. Promoted `0.3.10-pilot` added the F9 binding and passed its own safe-reversible suite, pinned at `qa/pilot-evidence/dawnwalker-live-pilot-qa-20260903T065937Z.json`, alongside the hotkey artifact `qa/pilot-evidence/dawnwalker-0.3.10-hotkeys-live-20260903T070604Z.json` (SHA-256 `38616500F68E74E5DC9689BF516435152654A90D5EE450FB347B28E3E2E4D9E2`). Versions `0.3.11-pilot` through `0.3.15-pilot` each added the two Combat difficulty axes and each failed its live read-only suite closed. Every one of those runs rejected the `combat:rpg-difficulty` query because the Action difficulty `ParryWindowMultipliers` map could not be walked through the live UE4SS container ABI: `0.3.11`, `0.3.12`, `0.3.13`, and `0.3.15` reported `attempt to call a nil value` and `0.3.14` reported `a function requiring userdata as param #1`. One `0.3.13` run additionally timed out on a `player:trait-points` query. None of the five mutated anything, and their artifacts are retained as failure evidence. Current `0.3.16-pilot` adds the nil-return TMap-compatible iteration and is the first source to pass both live suites at 16 capabilities. The prior Focus cooldown control remains withdrawn because live failure and binary inspection proved its debug setter and getter are shipping stubs. Existing pilot evidence for the remaining controls establishes:

- Player Info and Location Readback returned valid live values;
- HUD Visible completed a visible-hidden-visible set, query, and exact-restoration cycle;
- Game Speed completed a 1.0x-1.1x-1.0x set, query, and exact-restoration cycle;
- RPG Difficulty and Action Difficulty each completed an independent `Story -> Normal -> Story` set, query, and exact-restoration cycle while the other axis, both settings owner values, every object identity, and all four config fingerprints stayed unchanged;
- Trait Points completed a visible `0 -> 1` mutation, a normal-save reload at `1`, a visible `1 -> 0` restoration, a second reload at baseline, and exact restoration of the protected 76-file pre-test save tree;
- Save Location and Teleport to Saved Location completed a two-point same-session round trip with zero coordinate error at both destinations and returned the player to the moved point; and
- Infinite Health, Unlimited Stamina, Infinite Blood Energy, and God Mode each completed an exclusive owner-state, setter, readback, disable, and exact-baseline restoration cycle. These four controls still need hands-on endurance proof while health, stamina, or blood is actively changing before their full gameplay promises are marked live-verified.

Consequently:

- fourteen complete capability promises are pilot live-verified in `feature-contract-matrix.json`: the original eight plus RPG Difficulty, Action Difficulty, Trait Points, Add Item, Add Level, and Unblock Trait;
- four resource-lock controls have live control-cycle evidence but remain static-only for release purposes until their damage or consumption endurance tests pass;
- Add Level is pilot-live-verified. Promoted `0.3.19` completed a bounded one-way level-1-to-2 live cycle on boot `1788472141-542542` with three consistent readbacks (setter readback, independent `player:player-info`, and the read-only query) plus real level-up postconditions (blood maximum 300 to 342, trait points 22 to 23), and the closed-game 89-file pretest tree was restored with zero differences; the evidence artifact is `qa/pilot-evidence/dawnwalker-add-level-live-20260903T215316Z.json`. Unblock Trait is pilot-live-verified. Promoted `0.3.21` completed a bounded one-way unblock on boot `1788474671-718541`: `Human_ToughSkin|1` committed to level 1 through the deferred later-tick verification, the repeat dispatch confirmed `already unblocked to level 1`, and the closed-game 91-file pretest tree was restored with zero differences; the evidence artifact is `qa/pilot-evidence/dawnwalker-add-level-unblock-trait-live-20260903T223408Z.json`;
- Blood Energy remains the one advertised direct setter with no live cycle of its own;
- Unlimited Weight is not advertised or interactive. A replacement requires a verified player-only carry-capacity attribute setter plus immediate weight-state recalculation, readback, and exact rollback;
- Add Gold passed an automated live in-memory cycle under historical `0.3.8-pilot`: query `0`, add `+1`, verify `1`, add `-1`, verify exact baseline `0`, with unchanged boot identity and an empty final active set. That artifact is `qa/pilot-evidence/dawnwalker-live-pilot-qa-20260903T062333Z.json` (SHA-256 `71DF3D8B64C2C34E2EE82AE74557E904F3854B0EEDD2614E55AD98CBD36B919A`). The separate `qa/pilot-evidence/dawnwalker-add-gold-live-persistence-20260903T064209Z.json` artifact (SHA-256 `21AE16140B8B05C29DE252169B724844C857351777BB67BA6DCE3FB626056F49`) pins the visible `0 -> 10000` UI action and exact inverse plus a `+1` save/reload and `-1` save/reload across boots `1788416226-130670`, `1788416890-617197`, and `1788417347-822554`, ending at baseline `0`. The post-test tree is quarantined recoverably; the original `qa/save-backups/gold-pretest-20260903T055722Z` tree was restored while the game was closed with 61/61 files and zero path, length, or SHA-256 differences. Promoted `0.3.10` bound F9 to the same `+10000` action and proved it live: `qa/pilot-evidence/dawnwalker-0.3.10-hotkeys-live-20260903T070604Z.json` (SHA-256 `38616500F68E74E5DC9689BF516435152654A90D5EE450FB347B28E3E2E4D9E2`) pins an exact `0 -> 10000` menu readback triggered from game focus, a helper inverse back to `0`, a normal exit, and 61/61 original save files restored at zero path, length, or SHA-256 differences;
- none is production verified or eligible for the release payload;
- the production proof file must not be created from the existing smoke evidence; and
- every game-facing desktop control must remain capability-gated and release-locked.

Version `0.3.17-pilot` added `inventory:add-item`. It reuses the exact inventory identity
route already live-verified for Add Gold, builds the opaque `FItemHandle` only through the
reflected `InventoryBlueprintFunctionLibrary.GetItemHandle` factory, treats `GetItemQuantity`
as the sole authority, and carries an exact inverse (`RemoveItem` reverses `TryAddItem`). It
refuses quest items and never calls `StaticLoadObject`. Its bounded live cycle passed on boot
`1788460416-158410` (exact `0 -> 1 -> 0` quantity cycle on `ITM_Clothing_ChestCommon1` plus
all seven guard rejections), so the matrix marks it `pilot-live-verified` for that bounded
scope; larger quantities, stackables, equipped items, and reload persistence remain unproven.

Version `0.3.18-pilot` added `player:add-level` and `player:unblock-trait`. Its live Add
Level probes advanced the character level, but its Unblock Trait probe crashed the game with
an access violation (`EXCEPTION_ACCESS_VIOLATION` reading `0x70`) while the save tree
remained untouched: `GetTrait`, `GetTraitUnblockedLevel`, and `UnblockTraitToLevel` all take
`const FName&`, and the pinned UE4SS build does not marshal a raw Lua string into that
parameter. Version `0.3.19-pilot` is the FName-safe correction. It resolves the requested id
against the bounded `GetAllTraits()` roster (the same bounded container read the Unlock All
Skills planner probe proved) and only ever passes the matched trait's own `Skill_ID` value to
FName-typed calls, so an unknown or malformed id is rejected before any engine call is made.
Promoted `0.3.19` was live-probed on boot `1788472141-542542`. Add Level passed a bounded
one-way cycle and is `pilot-live-verified` (see above). Unblock Trait rejected safely -- the
crash fix held -- but every id was refused with "a trait roster entry was no longer valid":
the live `GetAllTraits()` container returns wrapped remote values on the table and numeric
read shapes, and only the ForEach shape unwrapped entries, so `resolve_trait_id` could never
validate a trait. Version `0.3.20-pilot` fixes that: `read_bounded_container` now unwraps
every entry on all three shapes before `IsValid`/`IsA` validation, and the offline harness
covers wrapped rosters via `npm run test:add-level`. After its promotion and smoke launch,
`0.3.20` was probed live: roster resolution works end to end (112 traits enumerated, unknown
ids rejected cleanly), `UnblockTraitToLevel` really commits to the requested level for
active-tree traits, and the game commits that state exactly one beat late -- so the
same-dispatch readback stayed stale and `0.3.20` reported failure on calls that actually
succeeded (a `|2` request read back 0 in its own dispatch and 2 in the next). Version
`0.3.21-pilot` fixes that by deferring the verdict: a commit-pending unblock is re-read on
later bridge ticks (bounded at 40, ~6 s at the 150 ms poll cadence) and only answered once
the committed level is observable; the offline harness now covers the deferred success,
supersession, and bounded-window exhaustion paths. `0.3.21` then passed its own fresh
promotion, inert-smoke launch, and live probe on boot `1788474671-718541` (Add Level
1 -> 2 with exact readbacks, `Human_ToughSkin|1` committed to level 1 and confirmed by
the repeat dispatch, and a zero-difference 91-file save restore), and the matrix flag moved.

The detailed static evidence and per-capability rollback limitations are recorded in `feature-contract-matrix.json`. Static reflection names, a clean loader log, an accepted bridge command, or a UI state change are not substitutes for an observed gameplay postcondition and verified rollback.

## UE4SS startup diagnostics

With the one-hook profile, UE4SS can report that `ProcessLocalScriptFunction` is unavailable and can emit disabled/unavailable hook notices for LoadMap, InitGameState, BeginPlay, EndPlay, ULocalPlayerExec, CallFunctionByNameWithArguments, and ProcessConsoleExec before the Dawnwalker bridge starts. Those exact pre-mod notices are expected because their corresponding hooks remain deliberately disabled. They are not bridge-command failures and must not be "fixed" by enabling extra hooks.

The live-QA classifier preserves the raw log and exempts only those exact messages. A DawnwalkerModBridge failure, EngineTick hook failure, non-allowlisted hook failure, generic error/fatal/failure, access violation, or crash marker remains actionable. The current live log also contains two separate UE4SS pattern-scan failures for `FUObjectHashTables::Get()` and `ConsoleManagerSingleton`; they are not hidden or reclassified, although the active bridge path does not call either scanner result.

## Capability rollback boundaries

- Infinite Health, Unlimited Stamina, Infinite Blood Energy, and God Mode use shared owner-aware in-memory baselines. The final owner release unlocks the resource and restores the captured percentage. All four live enable/readback/disable/exact-restoration cycles passed; controlled damage or consumption endurance still needs proof.
- Blood Energy and Trait Points are direct setters with readback but no retained automatic baseline. Record the original value before testing. Trait Points is confirmed save-backed, so an exact closed-game save backup and verified restoration are mandatory: `0.3.16` passed a visible `0 -> 1` mutation, a normal-save reload at `1`, a visible `1 -> 0` restoration, a second reload at baseline, and exact restoration of the protected 76-file pre-test save tree, pinned at `qa/pilot-evidence/dawnwalker-trait-points-live-persistence-20260903T084603Z.json` (SHA-256 `9332B897BBE1C60DBF2B2423EA8AE25C8C52F681E80F4AA0E499158CFE54F373`). The handler retains a baseline only for a failed or mismatched mutation, so every successful mutation stays save-backed until the operator restores it deliberately. Extreme values and downstream trait-purchase behavior remain untested.
- Unlimited Weight is withdrawn. `GE_EnableWeightLimitExceed_C` is explicitly forbidden in the pilot payload because it controls pickup permission rather than the weight-limit/encumbrance mechanic. The bridge rejects `player:unlimited-weight`, and no replacement may be exposed until its real attribute route proves recalculation and rollback.
- Quest Journal is read-only and pilot live-verified. It obtains open quests through `GetOpenedQuests(out)`, consumes the passed TArray out table's one-based numeric entries directly, performs bounded game-thread traversal, and has no disable path because it rejects values and calls no tracking, completion, objective, or save-state mutation API.
- Add Gold resolves the inventory both from the live player and `UInventorySubsystem`, requires the same UObject address, calls `AddCurrency(Coin=0, signed delta)`, ignores its unreliable reflected return, and accepts only exact `GetCurrencyQuantity(Coin=0)` readback. Each command is capped at absolute `10,000` with signed-int32 overflow/underflow guards. A mismatch may inverse only the exact observed bounded delta while all identities remain stable; otherwise it fails closed. Historical `0.3.8` has exact in-memory, visible positive-action, inverse, normal-save persistence, and exact-baseline reload proof. The renderer accepts positive additions only. Current F9 sends the fixed value `10000` through that same renderer function; it cannot bypass interaction eligibility, capability advertisement, in-flight locking, main-process reauthorization, session identity, or exact readback.
- RPG Difficulty and Action Difficulty share one two-axis snapshot bound to the live player, world, `UCombatSubsystem`, its assigned `DifficultyConfig`, and the non-CDO `URebelGameUserSettings` singleton, together with both baseline enum levels, both owner values, and stable fingerprints for all four Action/RPG config entries. Each axis accepts only Story=0, Normal=1, Immersive=2, or Nightmare=3 after the matching config map contains the value; MAX=4 and everything else are rejected. Rollback restores the axes independently and verifies exact level/settings/config/owner postconditions. The bridge never overwrites another owner of settings 69/70; it relinquishes ownership only when the live subsystem already matches the new owner values, refuses stale-object setters after world drift, calls no setter when a config fingerprint changed, and retains an unresolved partial restore that blocks further difficulty mutation until an exact same-world retry succeeds. The `0.3.16` live cycle set and restored both axes independently from `Story -> Normal -> Story` and ended with an empty active set.
- Player Info and Location Readback are read-only and passed playable-pawn transport/readback tests.
- No Cooldowns is not advertised. The Focus debug functions are compiled as nonfunctional shipping stubs. The engine-wide `AbilitySystem.IgnoreCooldowns` switch is only an experimental candidate because it affects all Gameplay Abilities, including enemies, and has no live scope or rollback proof.
- Extended Parry Window is not advertised. `GE_ParryWindowMultiplier_C` has an exact player ASC apply/remove/readback route, but its modifier magnitude is `SetByCaller` under `Stats.CustomModifier` and no captured asset or caller supplies the authoritative enabled value. The reflected `1.0` attribute baseline and separate `1.2` vampire configuration are not evidence for that payload. The control stays unavailable rather than guessing a magnitude.
- Save Location is bridge-session memory only. Saved entries disappear on player/session change or bridge restart.
- Teleport to Saved Location restores the origin only when destination verification fails. A successful teleport remains applied. The live two-point round trip passed with zero coordinate error and returned the player to the selected saved point.
- HUD Visible and Game Speed restore the immediately preceding value only when their same-command readback fails. Their live mutation/query/restoration tests passed and ended with an empty active set; `1.0` is the normal game-speed reset.
- Loader rollback removes/restores the loader and bridge transaction. It does not itself reverse gameplay or overwrite newer saves.

## Teardown-state retention

Version `0.3.9-pilot`, retained unchanged by current `0.3.21-pilot`, corrects a fail-open state-loss path in the source only. The earlier teardown loop attempted at most seven resource/snapshot restorations but then cleared every record even when one or more restorations failed. A failed unlock, setter, object-identity check, or readback could therefore erase the captured baseline and UObject handles needed for a safe retry.

The corrected teardown clears session state only after every bounded restoration reports verified success. When any operation rejects or throws, it retains unresolved resource baselines, owners, snapshots, and object handles; rebuilds the published active set from those retained records; withdraws all advertised capabilities; refuses to adopt a new player/world identity; and retries the same bounded teardown on a later once-per-second game-thread identity probe. Successful operations remove only their own resolved records, so later attempts focus on what remains. If unload occurs off the game thread and cannot be queued, pending restore state is retained instead of being explicitly discarded. If bound objects remain permanently invalid, the bridge stays fail closed and the operator must exit without saving and use the applicable backup/rollback procedure.

`DawnwalkerBridgeTeardownState.Tests.lua` exercises one resource lock and one snapshot together. It forces two restore failures, verifies that the next identity remains blocked and a new command is rejected, then allows a later retry and requires exact health/HUD baseline restoration before capabilities return. It separately covers the unload-without-game-thread retention path and a later safe retry. This is static harness evidence only; `teardownFailureRetryLiveRun` remains false in the feature matrix.

## Screenshot concepts not supported by the pinned-build evidence

These prototype concepts must not appear as functioning release controls:

- **Humanity:** no exact gameplay property, setter, or readback was found.
- **Red Essence:** the reflected resource is **Trait Points**; inventory currency evidence identifies **Coin**, not Red Essence.
- **No Durability Loss:** no item durability mutation contract or durability-loss event was found.
- **Teleport to Player:** the supported mode is offline single player, so there is no remote player target.
- **Spawn Boat** and **Spawn Companion** variants: do not expose them until each has both an exact spawn contract and a concrete verified asset/class pair. A type name or search hit alone is insufficient.
- **Extended Parry Window:** the effect and safe exact-handle rollback chain are reflected, but the required `Stats.CustomModifier` set-by-caller magnitude is not. Do not expose this control until an authoritative caller or asset pins that value.

## Promotion procedure

Start only after any earlier dump/capture transaction has been rolled back. Dawnwalker must remain closed during every install or promotion command.

1. Create a fresh inert-smoke transaction:

   ```powershell
   .\Install-DawnwalkerReflectionTools.ps1 -Action Install -WhatIf
   .\Install-DawnwalkerReflectionTools.ps1 -Action Install
   ```

2. Manually launch Dawnwalker offline to the main menu, observe stable loader startup, and exit normally. Review the installed `Dawnwalker\Binaries\Win64\ue4ss\UE4SS.log`. Do not continue if it contains an error, fatal failure, access violation, or crash marker.

3. Reconfirm that Dawnwalker is closed, then preview the gated promotion. Both switches are deliberate attestations, including for preview:

   ```powershell
   .\Install-DawnwalkerReflectionTools.ps1 `
     -Action PromoteBridgePilot `
     -ApproveCleanSmokeLog `
     -ApproveHookEngineTickPilot `
     -WhatIf
   ```

4. If the preview passes and its source/log hashes match the reviewed files, promote without `-WhatIf`:

   ```powershell
   .\Install-DawnwalkerReflectionTools.ps1 `
     -Action PromoteBridgePilot `
     -ApproveCleanSmokeLog `
     -ApproveHookEngineTickPilot
   ```

The command fails closed unless the pinned build is still exact and stopped, both state files describe the same unpromoted inert-smoke transaction, every installed baseline byte except the runtime `UE4SS.log` matches its recorded SHA-256 inventory, the exact installed log is less than 24 hours old and clean, and all template/source invariants still hold immediately before copying.

## Rollback

Do not terminate the game through the tooling. Exit normally, confirm it is closed, preview rollback, then restore the complete pre-install baseline:

```powershell
.\Install-DawnwalkerReflectionTools.ps1 -Action Rollback -WhatIf
.\Install-DawnwalkerReflectionTools.ps1 -Action Rollback
```

The rollback capture retains the current pilot loader tree and its log for analysis. It does not overwrite the user's newer saves.
