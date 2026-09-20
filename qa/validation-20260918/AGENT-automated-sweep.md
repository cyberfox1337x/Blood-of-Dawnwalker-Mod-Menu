# Phase 1 automated sweep — 2026-09-18 (agent: engineering-fullstack-dev)

Read-and-run audit only. Nothing under `src/`, `electron/`, `integration/imported-menu` or the game folder
was edited or launched. All commands run from the project root
`C:\Users\Cyberfox1337\Documents\ChatGPT\The Blood of DawnWalker`. Raw logs are in the session scratchpad
(`vitest.log`, `lint-tsc.log`, `lua-suites.log`, `ps-suites.log`).

## 1. Commands run and results

| Command | Result | Detail |
|---|---|---|
| `npx vitest run` | PASS (exit 0) | 70 files passed (70), 616 tests passed (616), 0 skipped, duration 192.39 s. One expected stderr line from a test exercising an invalid saved setting ("Unable to load the quest reminder setting ... reminders stay off."). Slowest test: `scripts/Dispatch-DawnwalkerPilotCommand.test.mjs` 6.27 s. |
| `npm run lint` (`eslint . --max-warnings 0`) | PASS (exit 0) | no output |
| `npx tsc -b tsconfig.app.json` | PASS (exit 0) | no output |
| `npx tsc -p electron/tsconfig.json` | PASS (exit 0) | no output |
| Lua suites (61 files, see section 2) | 60 PASS / 1 FAIL | The one failure (`PersonalFlyControl`) is environment-bound; verbatim below. |
| `lua integration/imported-menu/tests/Runtime.Tests.lua integration/imported-menu shutdown` | PASS (exit 0) | extra mode |
| `lua integration/imported-menu/tests/Runtime.Tests.lua integration/imported-menu non-game-thread` | PASS (exit 0) | extra mode |
| `npm run test:package-contract` | PASS (exit 0) | `"passed": true`, target `nsis-x64-only`, portable `false`, 11 pipeline stages listed |
| `npm run test:release-gate` | PASS (exit 0) | "Dawnwalker release readiness gate tests passed." |

Not run (not requested): `npm run test:runtime-installer`, `npm run test:lua` (bridge packaging validator, different payload),
`node --test qa/player-current-build/*.test.mjs`.

### The one failure, verbatim

Suite: `integration/imported-menu/tests/PersonalFlyControl.Tests.lua`. The suite ignores `arg[1]` (root is hardcoded at
line 3) and reads a fixture from `os.getenv("LOCALAPPDATA") .. "/DawnwalkerModMenu/PersonalMods/FLY-1.0.4/Scripts/"`
(line 15). That directory does not exist on this machine (`C:\Users\Cyberfox1337\AppData\Local\DawnwalkerModMenu\PersonalMods`
is absent). Same output for every argument tried (module path, integration root, `main.lua`):

```
C:\Users\Cyberfox1337\AppData\Local\Programs\Lua\bin\lua.exe: ...gration/imported-menu/tests/PersonalFlyControl.Tests.lua:17: Original FLY initialization must expose the reviewed adapter
stack traceback:
	[C]: in function 'assert'
	...gration/imported-menu/tests/PersonalFlyControl.Tests.lua:17: in main chunk
	[C]: in ?
```

Already documented as environment-bound in `qa/carry-weight-pilot-withdrawal-20260917/REPORT.md` (the FLY sibling
"has moved to the game's own Mods folder"). Status for this sweep: UNVERIFIED, not a regression. `PersonalFlyControl.lua`
itself is exercised only by this suite, so the Fly adapter currently has no passing automated coverage.

## 2. Lua suites — argument that worked and reported count

Runner: for each `tests/<Name>.Tests.lua`, tried in order `Scripts/<Name>.lua`, `Scripts/Source/<Name>.lua`,
`Scripts/<Name>Control.lua`, `integration/imported-menu`, `Scripts/main.lua`; first exit-0 recorded.
`Scripts/` = `integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/`.

| Suite | Result | arg[1] that worked | Reported count / last line |
|---|---|---|---|
| ActivationRecovery | PASS | `Scripts/Source/ActivationControl.lua` | 5 PASS lines, no count line |
| AttackRateObservation | PASS | `Scripts/AttackRateObservation.lua` | 11 attack observation groups passed |
| AttackSpeedEffectPilot | PASS | `Scripts/AttackSpeedEffectPilot.lua` | 11 attack effect pilot groups passed |
| BloodSegmentControl | PASS | `Scripts/BloodSegmentControl.lua` | 6 Blood segment tests passed |
| CarryCapacityEffectPilot | PASS | `Scripts/CarryCapacityEffectPilot.lua` | 21 carry-capacity effect pilot groups passed |
| CarryCapacityReadOnlyProbe | PASS | `Scripts/CarryCapacityReadOnlyProbe.lua` | harness passed (no count) |
| CarryWeightCheck | PASS | `Scripts/CarryWeightCheck.lua` | 15 CarryWeightCheck tests passed |
| CarryWeightPilot | PASS | `Scripts/CarryWeightPilot.lua` | harness passed (no count) — module is NOT loaded by main.lua and NOT in manifest |
| ClockControl | PASS | `Scripts/ClockControl.lua` | 9 Clock tests passed |
| CombatAttributeInspection | PASS | `Scripts/CombatAttributeInspection.lua` | 14 groups passed + action block passed |
| CombatDiscovery | PASS | `Scripts/CombatDiscovery.lua` | 16 combat discovery groups passed |
| CorePlayerControl | PASS | `Scripts/CorePlayerControl.lua` | 37 CorePlayerControl tests passed |
| CorruptionReset | PASS | `integration/imported-menu` | 8 Corruption reset tests passed |
| CourtAlertControl | PASS | `Scripts/CourtAlertControl.lua` | 14 Court alert tests passed |
| CraftingControl | PASS | `Scripts/CraftingControl.lua` | 10 Crafting tests passed |
| DawnwalkerSuperJumpDescriptorReadOnlyProbe | PASS | `Scripts/DawnwalkerSuperJumpDescriptorReadOnlyProbe.lua` | harness passed (no count) |
| DifficultyControl | PASS | `Scripts/DifficultyControl.lua` | 9 DifficultyControl tests passed |
| EquipmentLoadoutControl | PASS | `Scripts/EquipmentLoadoutControl.lua` | 10 Equipment loadout tests passed |
| Facade | PASS | `integration/imported-menu` | PASSED 12 imported facade tests; "Catalog sections=28 bytes=25452" |
| FallDamageObservation | PASS | `Scripts/FallDamageObservation.lua` | 1 PASS line, no count |
| FallDamageReadback | PASS | `Scripts/FallDamageReadback.lua` | 5 fall damage readback tests passed |
| FallDropDiagnostic | PASS | `Scripts/FallDropDiagnostic.lua` | 1 PASS line, no count |
| FallDropRegistration | PASS | `Scripts/main.lua` | 1 PASS line, no count |
| FormToggleControl | PASS | `Scripts/FormToggleControl.lua` | 17 form toggle tests passed |
| FreeCraftingControl | PASS | `Scripts/FreeCraftingControl.lua` | 9/9 free-crafting tests passed (one expected "hooks unavailable" line is part of a negative test) |
| GiveAndEquip | PASS | `integration/imported-menu` | ALL GiveAndEquip tests passed |
| HairColorControl | PASS | `Scripts/HairColorControl.lua` | 5+ PASS lines, no count line |
| HubTabControl | PASS | `Scripts/HubTabControl.lua` | 9 hub tab tests passed |
| HubTagProbe | PASS | `Scripts/HubTagProbe.lua` | 27 hub tag probe tests passed |
| JumpDescriptorReadback | PASS | `Scripts/JumpDescriptorReadback.lua` | 8 jump descriptor adapter tests passed |
| JumpTrajectoryDiagnostic | PASS | `Scripts/JumpTrajectoryDiagnostic.lua` | 7 jump trajectory diagnostic tests passed |
| MovementEffectReadback | PASS | `Scripts/MovementEffectReadback.lua` | 6 movement effect readback tests passed |
| NoClipFlightInput | PASS | `Scripts/NoClipFlightInput.lua` | 9 flight input tests passed |
| NoClipPilot | PASS | `Scripts/NoClipPilot.lua` | 12 No Clip pilot tests passed |
| **PersonalFlyControl** | **FAIL (env-bound)** | none (arg ignored) | assert at line 17, see section 1 |
| PhotoCameraControl | PASS | `Scripts/PhotoCameraControl.lua` | 7 Photo camera tests passed |
| PlayerLevelControl | PASS | `Scripts/PlayerLevelControl.lua` | 8 PlayerLevel tests passed |
| PlayerMovementReadback | PASS | `Scripts/PlayerMovementReadback.lua` | 6 movement readback tests passed |
| PlayerResolver | PASS | `Scripts/PlayerResolver.lua` | 13 player resolver tests passed |
| QuestReadback | PASS | `Scripts/QuestReadback.lua` | 7 QuestReadback tests passed |
| QuickslotAssign | PASS | `integration/imported-menu` | 10 Quickslot tests passed |
| Runtime | PASS | `integration/imported-menu` (+ `shutdown`, `non-game-thread` modes) | 1 PASS line per mode |
| SavedLocationControl | PASS | `Scripts/SavedLocationControl.lua` | 8 SavedLocation tests passed |
| SourceSession | PASS | `integration/imported-menu` | 4+ PASS lines, no count line |
| SpeedControl | PASS | `Scripts/SpeedControl.lua` | 15 speed pending control tests passed |
| SpeedDescriptorReadback | PASS | `Scripts/SpeedDescriptorReadback.lua` | 8 speed descriptor readback tests passed |
| SpeedDiagnostic | PASS | `Scripts/main.lua` | 6 speed diagnostic tests passed |
| SpeedProfilePilot | PASS | `Scripts/SpeedProfilePilot.lua` | 10 private speed profile tests passed |
| StorySettingsControl | PASS | `Scripts/StorySettingsControl.lua` | 11 StorySettings tests passed |
| StoryTimer | PASS | `Scripts/StoryTimerControl.lua` | 7 Story Timer tests passed |
| SuperDamageEffectPilot | PASS | `Scripts/SuperDamageEffectPilot.lua` | 16/16 super-damage pilot tests passed |
| SuperJumpControl | PASS | `Scripts/SuperJumpControl.lua` | 5 Super Jump control tests passed |
| SuperJumpEffectPilot | PASS | `Scripts/SuperJumpEffectPilot.lua` | 19 super jump effect tests passed |
| SuperJumpPilot | PASS | `Scripts/SuperJumpPilot.lua` | 15 Super Jump pilot tests passed — module is pinned in manifest but NOT loaded by main.lua |
| TraitPointControl | PASS | `Scripts/TraitPointControl.lua` | 8 Trait point tests passed |
| TutorialDismissControl | PASS | `Scripts/TutorialDismissControl.lua` | 21 Stuck popup tests passed |
| WorldControl | PASS | `Scripts/WorldControl.lua` | 7 WorldControl tests passed |
| XPAwardObservationControl | PASS | `Scripts/XPAwardObservationControl.lua` (arg ignored; root hardcoded) | 5+ PASS lines, no count line |
| XPMultiplierControl | PASS | `Scripts/XPMultiplierControl.lua` | 11 XP multiplier tests passed |
| XPRewardControl | PASS | `Scripts/XPRewardControl.lua` | 16 XP reward control tests passed |
| XPRewardReadback | PASS | `Scripts/XPRewardReadback.lua` | 10 XP reward readback tests passed |

Suites that hardcode `integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/` and ignore `arg[1]`:
`PersonalFlyControl`, `SpeedControl`, `XPAwardObservationControl` (they must be run from the project root).

## 3. Module coverage table

73 Lua files on disk (61 in `Scripts/`, 12 in `Scripts/Source/`); manifest pins 75 files total.
"Dedicated" = a same-named `<Module>.Tests.lua` exists. "Indirect" = another suite loads it.

### Scripts/ (adapters)

| Module | Dedicated suite | Passes | Indirect coverage | Loaded by main.lua |
|---|---|---|---|---|
| AttackRateObservation | yes | PASS | — | yes |
| AttackSpeedEffectPilot | yes | PASS | — | yes |
| BloodSegmentControl | yes | PASS | — | yes |
| CarryCapacityEffectPilot | yes | PASS | CarryWeightCheck | yes |
| CarryCapacityReadOnlyProbe | yes | PASS | — | yes |
| CarryWeightCheck | yes | PASS | — | yes |
| CarryWeightPilot | yes | PASS | — | **no** (withdrawn 09-17; not in manifest; file still on disk) |
| ClockControl | yes | PASS | — | yes |
| CombatAttributeInspection | yes | PASS | — | yes |
| CombatDiscovery | yes | PASS | CombatAttributeInspection | yes |
| CorePlayerControl | yes | PASS | Facade | yes |
| CourtAlertControl | yes | PASS | — | yes |
| CraftingControl | yes | PASS | FreeCraftingControl | yes |
| DawnwalkerSuperJumpDescriptorReadOnlyProbe | yes | PASS | JumpDescriptorReadback | yes |
| DawnwalkerXPAwardObservation | **no** | — | XPAwardObservationControl (loads it) | yes |
| DifficultyControl | yes | PASS | Facade | yes |
| EquipmentLoadoutControl | yes | PASS | — | yes |
| EyeColorBindings | **no** | — | **none** | via EyeColorControl |
| EyeColorControl | **no** | — | **none** | yes |
| EyeMaterialObservation | **no** | — | **none** | via EyeColorControl |
| FallDamageObservation | yes | PASS | — | yes |
| FallDamageReadback | yes | PASS | — | yes |
| FallDropDiagnostic | yes | PASS | FallDropRegistration (main.lua block) | yes |
| FormToggleControl | yes | PASS | — | yes |
| FreeCraftingControl | yes | PASS | — | yes |
| HairColorControl | yes | PASS | — | yes |
| HubTabControl | yes | PASS | — | yes |
| HubTagProbe | yes | PASS | HubTabControl | yes |
| ImportedMenuFacade | Facade.Tests.lua | PASS | GiveAndEquip, QuickslotAssign, SourceSession, XPAwardObservationControl, XPRewardControl, PersonalFlyControl | yes |
| ImportedSourceLoader | **no** | — | Facade, GiveAndEquip | yes |
| ItemAmountControl | **no** | — | **none** | yes |
| JumpDescriptorReadback | yes | PASS | — | yes |
| JumpTrajectoryDiagnostic | yes | PASS | — | yes |
| MovementEffectReadback | yes | PASS | — | yes |
| NoClipFlightInput | yes | PASS | — | yes |
| NoClipPilot | yes | PASS | — | yes |
| PersonalFlyControl | yes | **FAIL (env-bound)** | — | yes |
| PhotoCameraControl | yes | PASS | — | yes |
| PlayerLevelControl | yes | PASS | Facade | yes |
| PlayerMovementReadback | yes | PASS | — | yes |
| PlayerResolver | yes | PASS | — | yes |
| QuestReadback | yes | PASS | Facade | yes |
| SavedLocationControl | yes | PASS | Facade | yes |
| SpeedControl | yes | PASS | — | yes |
| SpeedDescriptorReadback | yes | PASS | — | yes |
| SpeedProfilePilot | yes | PASS | SpeedControl | yes |
| StorySettingsControl | yes | PASS | Facade | yes |
| StoryTimerControl | StoryTimer.Tests.lua | PASS | Facade | yes |
| SuperDamageControl | **no** | — | **none** (only SuperDamageEffectPilot, its dependency, is tested) | yes (twice: DWSuperDamage, DWParryWindow) |
| SuperDamageEffectPilot | yes | PASS | — | yes |
| SuperJumpControl | yes | PASS | — | yes |
| SuperJumpEffectPilot | yes | PASS | SuperJumpControl | yes |
| SuperJumpPilot | yes | PASS | — | **no** (superseded by SuperJumpControl+EffectPilot; still pinned in manifest) |
| TraitPointControl | yes | PASS | — | yes |
| TutorialDismissControl | yes | PASS | — | yes |
| WorldControl | yes | PASS | Facade | yes |
| XPAwardObservationControl | yes | PASS | — | yes |
| XPMultiplierControl | yes | PASS | — | yes |
| XPRewardControl | yes | PASS | — | yes |
| XPRewardReadback | yes | PASS | — | yes |
| main | Runtime.Tests.lua (+FallDropRegistration, SpeedDiagnostic read blocks of it) | PASS | 14 suites reference it | entry point |

### Scripts/Source/ (imported originals, loaded through ImportedSourceLoader allowlist)

| Module | Dedicated suite | Passes | Indirect coverage |
|---|---|---|---|
| ActivationControl | ActivationRecovery.Tests.lua | PASS | Facade catalog boot |
| CombatControls | **no** | — | SourceSession (loads + drives stamina refill), Facade catalog boot |
| CooldownControl | **no** | — | Facade catalog boot only (registration smoke) |
| CorruptionLevelControl | CorruptionReset.Tests.lua | PASS | Facade catalog boot |
| GameplayMenu | **no** | — | CorruptionReset, GiveAndEquip, QuickslotAssign, Facade |
| GodMode | **no** | — | Facade catalog boot only; UI hidden in production (`hideUI=true`) |
| InfamyControl | **no** | — | Facade catalog boot only (registration smoke) |
| ParryAssist | **no** | — | Facade catalog boot only (registration smoke) |
| ProtectedRespec | **no** | — | **none** (lazy-required from CombatControls; never instantiated in tests) |
| TimeControl | **no** | — | SourceSession (loads + drives), Facade catalog boot |
| TraitGrant | **no** | — | SourceSession (loads + drives), Facade catalog boot |
| UltimateResearch | **no** | — | Facade catalog boot only (registration smoke) |

### Modules with NO suite of their own (summary)

Adapters: `DawnwalkerXPAwardObservation`, `EyeColorBindings`, `EyeColorControl`, `EyeMaterialObservation`,
`ImportedSourceLoader`, `ItemAmountControl`, `SuperDamageControl`.
Source: `CombatControls`, `CooldownControl`, `GameplayMenu`, `GodMode`, `InfamyControl`, `ParryAssist`,
`ProtectedRespec`, `TimeControl`, `TraitGrant`, `UltimateResearch`.

Of these, the ones with **zero** automated coverage of any kind (not even loaded by another suite):
`EyeColorBindings`, `EyeColorControl`, `EyeMaterialObservation`, `ItemAmountControl`, `SuperDamageControl`,
`Source/ProtectedRespec`. Note the checklist marks Eye colour, Edit Item Amount, Unlimited Consumables, Super Damage,
Extended Parry Window and Respec (Light) as live PASS; those are live observations only, with no unit-level guard.

## 4. Checklist cross-check against registered sections

Method: grep `menu.Register({ id =` / `ModMenu.Register({id=` across `Scripts/**/*.lua` (62 registrations), resolve
each `id`/`ID`/`SECTION` variable to its `DW*` literal, then compare with the `Section.item` column in
`TESTING-RECORD.md`.

### Checklist ids that resolve — all 25 named `section.item` pairs exist in code
`DWCorePlayer.{god,healthEnabled,bloodEnabled,bloodPercent,sprintEnabled,staminaRefill,formOverride}`,
`DWSuperJump.enabled`, `DWNoClip.enabled`, `DWPersonalFly.enabled`, `DWSpeed.{multiplier,restore}`,
`DWActivationControl.enabled`, `DWCooldownControl.enabled`, `DWParryAssist.enabled`, `DWCombatDiscovery.attackEnabled`,
`DWItemAmount.unlimitedConsumables`, `DWWeight.zeroWeight`, `DWFreeCrafting.enabled`, `DWCrafting.{unlock,daily}`,
`DWXP.award`, `DWXPMultiplier.factor`, `DWBloodSegments.repair`, `DWCoreWorld.speed`. All other checklist rows name a
section only; every one of those sections (`DWSuperDamage`, `DWParryWindow`, `DWCoreLevel`, `DWSkills`, `DWMutation`,
`DWTraitGrant`, `DWUltimateControls`, `DWRespec`, `DWTraitPoints`, `DWCoreDifficulty`, `DWCurrency`, `DWMaterials`,
`DWManuals`, `DWKeys`, `DWItems`, `DWQuickslots`, `DWLoadout`, `DWInfamyControl`, `DWCourtAlert`, `DWTimeControl`,
`DWClock`, `DWStoryTimer`, `DWStorySettings`, `DWPhotoCamera`, `DWShrines`, `DWCoreTeleport`, `DWEyeColor`,
`DWHairColor`, `DWQuestReadback`) is registered.

### Registered sections/controls MISSING from the checklist

Gameplay-affecting (write to game state) — these are real Phase 1 gaps:

| Section id | Title / tab | Interactive controls | Module |
|---|---|---|---|
| DWHubTabs | Hub tabs / World | tab(dropdown), refresh, unlock, unlockAll, restore, owned | HubTabControl |
| DWTutorialDismiss | Stuck popup / World | refresh, dismiss, force, collapse, widgets, scan, queue, close | TutorialDismissControl |
| DWXPRewards | Quest & combat XP rewards / Player | refresh, restore, owned (drives XP reward row overrides) | XPRewardControl |
| DWMutation (partial) | Corruption / Progression | checklist says "level / charges / reset"; code also has `add`, `remove`, `addOne`, `removeOne`, `amount`, `owned` | Source/CorruptionLevelControl |
| DWRespec (partial) | Skill Respec / Progression | checklist covers Light only; `armMedium`, `armFull` + `confirm` are OPEN (record already says "Medium/Full OPEN") | Source/CombatControls |
| DWCoreTeleport (partial) | Saved locations / Teleport | checklist covers save + teleport; `cleanup` checkbox not listed | SavedLocationControl |
| DWCorePlayer (partial) | Player controls | `bloodRecovery`, `stamina`, `health`, `blood` (numeric fields), `refresh` not listed; `formOverride` is OPEN | CorePlayerControl |
| DWCombatDiscovery (partial) | Attack speed / Player | checklist has only `attackEnabled` (DESIGN); `attackCheck` (paused roundtrip — the precondition itself), `attackObserve`, `attackObserveStop`, `inspect`, `inspectEffect`, `inspectAttributes` not listed | CombatDiscovery |
| DWCoreDifficulty (partial) | Difficulty / Player | `restore`, `owned` implied by "Immersive + restore"; fine | DifficultyControl |
| DWStorySettings (partial) | Story settings / World | `daysEnabled`, `dayOwned`, `traits` — checklist row "no trait time cost / 90-day live" covers them loosely | StorySettingsControl |
| DWPlayer | Player Status / Player | `stamina` button (refill), `refresh` | Source/GameplayMenu |

Read-only / diagnostic sections (no game-state writes except owned pilots) — not on the checklist at all:

| Section id | Title | Controls | Module |
|---|---|---|---|
| DWHubTags | Hub tab tags (read only) | arm, report, tag(dropdown), checkTab, testRelease | HubTagProbe |
| DWXPReadback | XP reward diagnostics | refresh | XPRewardReadback |
| DWXPAwardObservation | XP award observation diagnostics | start, getter, read, stop, owned | XPAwardObservationControl |
| DWFallReadback | Fall damage diagnostics | refresh | FallDamageReadback |
| DWFallObservation | Fall dispatch diagnostics | start, read, stop, owned | main.lua + FallDamageObservation |
| DWFallDropTest | Bounded fall diagnostic | drop200, drop400, owned (moves the player) | main.lua + FallDropDiagnostic |
| DWJumpEffectTest | Controlled jump diagnostic | roundtrip (applies + removes an effect) | main.lua + SuperJumpEffectPilot |
| DWJumpTrajectoryTest | Physical jump diagnostic | run, owned (performs two jumps) | main.lua + JumpTrajectoryDiagnostic |
| DWSpeedProfileTest | Controlled speed diagnostic | roundtrip, roundtrip_unpaused, owned | main.lua + SpeedProfilePilot |
| DWSpeedReadback | Speed descriptor diagnostics | refresh | SpeedDescriptorReadback |
| DWJumpReadback | Jump descriptor diagnostics | refresh | JumpDescriptorReadback |
| DWMovementReadback | Movement diagnostics | refresh | PlayerMovementReadback |
| DWMovementEffectReadback | Movement effect diagnostics | refresh | MovementEffectReadback |
| DWMenuWarnings | Warnings & Limitations | labels only | Source/GameplayMenu |

Registered in code but NOT reachable in production (non-gaps, listed for completeness):
- `DWGodMode` (Source/GodMode) — registration is behind `if not hideUI`; GameplayMenu passes `true`. God Mode is
  surfaced as `DWCorePlayer.god`, which the checklist already covers.
- `DWCombatControls` — a state key read by CorePlayerControl, never a registered section.
- `DWSuperJump` from `SuperJumpPilot.lua` — file is pinned in `manifest.json` but `main.lua` never loads it; the live
  `DWSuperJump` section comes from `SuperJumpControl.lua`.
- `DWWeight` is registered by `CarryWeightCheck.lua`; `CarryWeightPilot.lua` is on disk, untracked by the manifest,
  loaded by nothing.

## 5. Observations (no action taken)

1. `PersonalFlyControl.Tests.lua` cannot pass on this machine; the fixture path it asserts is gone. Either the test
   needs a repo-local fixture or it should skip with an explicit reason instead of failing. Not changed.
2. Six modules have zero automated coverage while their features are marked live PASS (section 3).
3. `SuperJumpPilot.lua` ships in the payload (manifest-pinned) but is dead code; `CarryWeightPilot.lua` is a leftover on
   disk outside the manifest. Not changed.
4. `TESTING-RECORD.md` "Commands" says `npx vitest run` covers 70 files — confirmed (70/70, 616 tests).
5. The Facade catalog boot asserts exactly 28 sections; production `main.lua` registers many more (adapters loaded with
   the UE environment). The 28 is a test-fixture subset, not the live count.
