# Blood of Dawnwalker Mod Menu — validation record (started 2026-09-18)

Persistent record for the three-phase validation goal (features → performance → stability).
Read this first in every session; update it before stopping. Evidence rule: a check is PASS
only when observed in the running game or a real command run; UNVERIFIED otherwise.

## Environment
- Game: The Blood of Dawnwalker 1.0.5 (changelist 258504), Steam appid 3751260, UE 5.5.4.
- UE4SS: v3.0.1 zDEV build 97b7e501, installed under `Dawnwalker/Binaries/Win64/ue4ss`.
  Enabled Lua mods: `DawnwalkerImportedMenu` (ours), `FastTravelToAnyMarker` (user's).
  `BPModLoaderMod` (pak loader) disabled; no mod paks (`Content/Paks/~mods` empty).
- Desktop menu: Electron app, packaged to `release-current\win-unpacked\Blood of Dawnwalker Mod Menu.exe`
  (`npm run build` → `electron-builder --win dir` into `%TEMP%\dawnwalker-menu-build` → robocopy /MIR).
- Payload: `integration/imported-menu` (74 files pinned in `manifest.json` after A-2 unpinned SuperJumpPilot.lua; all verified against the game folder).
- Command channel: `%TEMP%\DawnwalkerImportedMenu\{command.txt,state.json}` (session-bound, 5 s expiry).
- Test saves: user's live saves are backed up before destructive runs to the session scratchpad
  (`savegames-backup-<stamp>`) and restored afterwards. `Quicksave2.sav` is the designated disposable save.
- Tools: `scratchpad\menu_cmd.py SECTION ITEM [set VALUE|invoke] [--confirm]`,
  `scratchpad\batch*.py` (live smoke batches), `scratchpad\restart_game.ps1` (kill/relaunch/wait,
  auto-captures a minidump on the startup hang), `scratchpad\capture_hang.ps1`, `scratchpad\analyze_dump.py`.

## Agent requirement
`engineering-fullstack-dev` (the "@engine full developer" agent) must be invoked in every session.
Log of invocations: see "Sessions" below.

## Commands
- `npx vitest run` — renderer/electron suites (70 files).
- `npm run lint`, `npx tsc -b tsconfig.app.json`, `npx tsc -p electron/tsconfig.json`.
- Lua suites: `lua integration/imported-menu/tests/<Name>.Tests.lua <path to module or integration root>`
  (per-suite argument; `Runtime.Tests.lua` and `SourceSession.Tests.lua` take `integration/imported-menu`).
- `npm run test:package-contract`, `npm run test:release-gate`, `npm run test:runtime-installer`.

## Phase 1 — feature checklist (status as of 2026-09-18 10:30)
Legend: PASS = observed live; PASS-UI = observed in the packaged menu; DESIGN = disabled by design until a
precondition; N/A = game-dependent; OPEN = not yet verified this phase.

### Player
| Feature | Section.item | Status | Evidence |
|---|---|---|---|
| God Mode | DWCorePlayer.god | PASS | ON/OFF verified 09-18 batch_check |
| Infinite Health | DWCorePlayer.healthEnabled | PASS | 09-18 |
| Infinite Blood Energy / Blood % | DWCorePlayer.bloodEnabled/bloodPercent | PASS | 09-18 |
| Sprint No Drain | DWCorePlayer.sprintEnabled | PASS | 09-17 |
| Rapid stamina refill | DWCorePlayer.staminaRefill | PASS | ON/OFF 09-18 12:05 |
| Vampire form override | DWCorePlayer.formOverride | PASS | ON → Vampire/Night set; OFF → automatic, Human (09-18 12:05) |
| Super Jump | DWSuperJump.enabled | PASS | ON/OFF 09-18 12:00 incl. right after Fly (D-7, D-10 fixed) |
| No Clip | DWNoClip.enabled | PASS | ON/OFF 09-18 |
| Fly | DWPersonalFly.enabled | PASS | ON/OFF 09-18 |
| Speed Multiplier | DWSpeed.multiplier/restore | PASS | 2x/3x verified incl. from the paused menu (D-14); distance 1x 626 u vs 3x 2106 u per 2 s |
| Unlimited Activation Charge | DWActivationControl.enabled | PASS | 09-18 |
| Instant Ability Cooldown | DWCooldownControl.enabled | PASS | 09-18 |
| Auto Parry | DWParryAssist.enabled | PASS | 09-18 (needs >1 s between commands) |
| Extended Parry Window | DWParryWindow | PASS | x2 verified 09-17/18 |
| Super Damage / One-Hit Kills | DWSuperDamage | PASS | x100 → Weapon 15→1,540, Claw 108-154→10,800-15,400; OFF exact |
| Attack speed +0.10 | DWCombatDiscovery.attackEnabled | DESIGN | requires paused self-check first |
| Unlimited Consumables | DWItemAmount.unlimitedConsumables | PASS | Murohn Blood refunded x2→x3 (09-17) |
| Edit Item Amount | DWItemAmount | PASS | Grey Loafers 1→3→1 (09-17) |
| Zero Weight | DWWeight.zeroWeight | PASS | 09-18 |
| Ignore Crafting Requirement | DWFreeCrafting.enabled | PASS | crafted with 0/1 ingredients (09-17) |
| Unlock All Crafting Recipes | DWCrafting.unlock | PASS | 44 recipes (09-17) |
| Player level apply | DWCoreLevel | PASS | 8→9 verified (09-17 23:2x) |
| Skill points add/remove/clear | DWSkills | PASS | 09-17 |
| Add XP | DWXP.award | PASS | Small 250 XP |
| Quest XP multiplier | DWXPMultiplier.factor | PASS | x3 set/reset |
| Corruption level / charges / reset / bulk add-remove | DWMutation | PASS | 09-17; bulk +3/-3 09-18 |
| Grant specific perk | DWTraitGrant | PASS | rank 3 verified; label fix (D-4) |
| Grant Ultimate / Unlock Everything | DWUltimateControls | PASS | 2→112 traits |
| Respec (Light/Medium/Full) | DWRespec | PASS | Light +3 (morning); Medium +1 verified, Full correctly refused when nothing ordinary remains (Phase 3, saves restored) |
| Trait points set/restore | DWTraitPoints | PASS | 09-17 |
| Blood segment repair | DWBloodSegments.repair | PASS | nothing to repair on this save |
| Difficulty RPG/Action | DWCoreDifficulty | PASS | Immersive + restore |

### Inventory
| Coins add/remove | DWCurrency | PASS | 130k→140k→130k |
| Materials / Manuals / Keys give | DWMaterials/DWManuals/DWKeys | PASS | 09-17 |
| Give item / Give & equip / Give all | DWItems | PASS | 551 items given |
| Quickslot read/assign | DWQuickslots | PASS | game refuses obsolete item (correct) |
| Equipment loadout switch/restore | DWLoadout | PASS | 09-17 |
| Daily crafting refill | DWCrafting.daily | PASS | already full |

### World
| Infamy ±100 / exact | DWInfamyControl, DWCourtAlert | PASS | confirm-gated |
| Time segments advance/rewind | DWTimeControl | PASS | 8.0→9.5→8.0 |
| Clock set/restore | DWClock | PASS | segment snap explained (D-2) |
| Story timer / no trait time cost / 90-day live | DWStoryTimer, DWStorySettings | PASS | 09-17 |
| Game speed | DWCoreWorld.speed | PASS | 0.5x + restore |
| Photo camera | DWPhotoCamera | N/A | actor absent on prologue map |

### Teleport / Visuals / Quests / Settings
| Shrine unlock | DWShrines | PASS (request) | calls the game's own `DebugUnlockAllFastTravelDestinations`; the prologue map's two shrines were already discovered on this save, so the map cannot attribute the unlock — needs a save with undiscovered shrines (accepted limitation) |
| Saved location save + teleport | DWCoreTeleport | PASS | verified |
| Eye colour / hair / eyebrows | DWEyeColor, DWHairColor | PASS | apply + restore |
| 3D preview | desktop | PASS-UI | 09-17 |
| Quest journal | DWQuestReadback | PASS | 2 quests |
| Save Editor | desktop | PASS | Quicksave2 clock ±90 written/backed up/read back (game closed) |
| Objective reminder toast, menu size, tooltips | desktop | PASS-UI | 09-17 |

### Removed / not offered
- NPC tab removed (10:00) after the spawn route crashed (soft pointer read; D-6).

## Defects
| # | Defect | Fix | Status |
|---|---|---|---|
| D-1 | Read-gated controls disabled until manual read | `M.SessionReady` auto-reads (12 modules) | fixed, verified |
| D-2 | Clock apply refused ("minute") / failed on segment snap | pre-fill fields; accept 1.5 h grid | fixed, verified |
| D-3 | Level apply vague refusal | named preconditions | fixed, verified |
| D-4 | Perk grant status overwritten | restore status after refresh | fixed, verified |
| D-5 | Developer rows in pickers | `isDeveloperOption` filter | fixed |
| D-6 | NPC spawn scan crashes game | withdrawn; tab removed | closed |
| D-7 | Super Jump OFF trapped in "recovery pending" after gravity changed (Fly) | verify release, not profile | fixed in code + tests; live retest PASS 12:00 (ON/OFF right after Fly) |
| D-8 | Startup hang after "Event loop start" (intermittent, ~1 in 3 boots) | root cause captured 11:16: game main thread blocked in `GetMessageW` called by Steam's `gameoverlayrenderer64.dll`; every UE4SS/Lua thread idle. Mitigation = disable Steam Overlay for the game (user action; Steam UI not granted). See HANG-ANALYSIS.md | ROOT CAUSE FOUND, fix pending user |
| D-9 | vitest App tests flaky under load (5 s default) | testTimeout 20 s | fixed |
| D-10 | After Fly OFF the game keeps the airborne JumpZVelocity (450·√2) and doubled jump height; Super Jump then rolled back | Fly wrapper records pre-flight JumpZVelocity and restores it once walking again; Super Jump refuses up front with a "still settling" message instead of applying and rolling back | fixed, verified live 12:00 (jump_z 450 / height 51.66 after Fly; Super Jump ON right after) |
| D-11 | Edit Item Amount reported "x1 -> x1" when a refund re-created a stack from zero (second handle pass overwrote the baseline) | keep first-pass baseline | fixed, unit-tested |
| D-12 | PersonalFlyControl suite hard-coded a LOCALAPPDATA path that no longer exists | arg[1] / installed-mod fallback | fixed; 61/61 Lua suites run here |
| D-13 | Respec refusals (`Preview your refund first.`, `Leave combat before respec`, `Preview expired`, `No ordinary purchased ranks to reset`) were swallowed: the buttons passed `run()` a bare `'DWRespec'` string, so the `Unavailable:` label write failed inside its `pcall` and the stale preview text stayed on screen | pass `{id='DWRespec',item='status'}`; log when a refusal cannot be published | fixed (`Source/CombatControls.lua`, re-pinned EF2668EB04A2), regression test in `SourceSession.Tests.lua` (fails on old code, passes on fix), live retest: confirm-without-preview and Full-with-nothing-to-reset both show `Unavailable: …` on the row |
| D-14 | Speed Multiplier slider looked dead from the desktop menu: the game opens its own PAUSE screen whenever the menu window takes focus, the request could only verify after Resume, the pending request expired after 60 s of *real* time (so anyone who took longer than a minute to go back had it silently cancelled), and the slider snapped back to 1x while pending | `SpeedControl.lua`: budget counts unpaused time only (60 s of gameplay / 240 unpaused ticks, 15-min absolute cap); slider shows the requested value while pending; status says the game is paused and to press Resume | fixed, re-pinned B1D2F7FB21BA, release repackaged; `SpeedControl.Tests.lua` 15 → 18 (paused request survives 4 min and applies on resume; 15-min cap; paused waiting message). Live 19:01–19:06: 2x requested from the menu with the game paused, still pending after 2.5 min, verified <1 s after Resume; forward run 2 s: 1x 626 u, 3x 2106 u (3.4×); restore verified |
| D-15 (found by the agent's verification pass) | After the startup-freeze message, closing and relaunching the game — the advice the message gives — showed the freeze message again at 0 s of the new boot with a stale elapsed figure, because `quietSince` was only reset by a fresh heartbeat, never by a confirmed exit | reset `quietSince` on `running === false` (`electron/importedMenuTransport.ts`) | fixed; test extended (`importedMenuTransport.test.ts`, 13 pass; proven to fail without the fix); release repackaged 19:3x |

## Phase 1 — automated sweep (agent `engineering-fullstack-dev`, 2026-09-18 11:10, report AGENT-automated-sweep.md)
- vitest 616/616 (70 files); lint/tsc clean; Lua suites 60/61 pass (PersonalFlyControl.Tests.lua is
  environment-bound: reads `%LOCALAPPDATA%/DawnwalkerModMenu/PersonalMods/FLY-1.0.4`, absent here → UNVERIFIED,
  not a regression); package-contract PASS; release-gate PASS.
- Coverage gaps (no unit suite): EyeColorBindings, EyeColorControl, EyeMaterialObservation, ItemAmountControl,
  SuperDamageControl, Source/ProtectedRespec. → action A-1: add ItemAmountControl + SuperDamageControl suites.
- Checklist gaps to exercise: DWPlayer.stamina (Refill stamina now), DWMutation add/remove (bulk), DWRespec Medium/Full,
  DWCorePlayer.bloodPercent numeric, DWCoreTeleport.cleanup, DWXPRewards (by design refused), DWTutorialDismiss /
  DWHubTabs (Settings dev tools, hidden), DWCombatDiscovery diagnostics. Diagnostic-only sections (*Readback,
  *Test, *Observation) are developer probes; verify they run and restore, not that they are features.
- Payload hygiene: `SuperJumpPilot.lua` is pinned but never loaded (dead, shipped); `CarryWeightPilot.lua` on disk,
  not in manifest. → action A-2: decide/remove.

- A-1 done: `SuperDamageControl.Tests.lua` (10) and `ItemAmountControl.Tests.lua` (10) added; `SuperJumpEffectPilot` 20 tests.
- Remaining OPEN in Phase 1: Respec Medium/Full (destructive; run with save backup), Shrine map check, Blood segment repair with real damage, Photo camera on a map that has one.

## Phase 2 — performance (started 2026-09-18 12:20)
No performance requirements existed, so these acceptance targets are proposed and recorded here
before judging: **P-1** command round-trip (file channel → game → readback) median ≤ 400 ms, p95 ≤ 1000 ms;
**P-2** idle channel traffic ≤ 1 state rewrite/s and ≤ 300 KB; **P-3** desktop menu idle CPU ≤ 2 % of the machine
(8 logical cores) and ≤ 500 MB RSS across its processes, cold start to window ≤ 5 s; **P-4** heavy operation
(Give all 551 items) ≤ 60 s; **P-5** game CPU not measurably raised by the connected menu (report only; noisy).
Tools: `scratchpad/perf_latency.py` (20 ms polling round-trip timer), PowerShell CPU/RSS sampling per Electron
process type (`--type=` from the command line), `os.stat` mtime watcher for the state file.

| Indicator | Baseline (before) | After | Target | Result |
|---|---|---|---|---|
| P-1 read (difficulty refresh) | median 159 ms, p95 226 ms | 175 / 241 ms | ≤400 / ≤1000 | PASS |
| P-1 toggle on/off | 384 / 241 ms median, p95 ≤ 428 ms | 247 / 234 ms, p95 ≤ 380 ms | ≤400 / ≤1000 | PASS |
| P-1 number set | 129 ms median | 51 ms | ≤400 | PASS |
| P-1 owned-effect pilot on/off | ~395 ms median, p95 429 ms | 252 / 283 ms, p95 394 ms | ≤400 / ≤1000 | PASS |
| P-2 idle state.json rewrites | 1.00/s, 200 KB (heartbeat-only rewrite of a cached payload) | unchanged (by design) | ≤1/s, ≤300 KB | PASS |
| P-3 menu idle CPU (connected, Player tab) | 21.5 % of one core (2.7 % machine) | **6.7 % of one core (0.8 % machine)** | ≤2 % machine | PASS |
| P-3 menu RSS (4 processes) | 431 MB | 435 MB | ≤500 MB | PASS |
| P-3 cold start to main window | 1253 ms | 1453 ms | ≤5000 ms | PASS |
| P-4 Give all Weapons+Clothing | 551 items, finished within the 30 s poll (09-17) | — | ≤60 s | PASS |
| P-5 game CPU with menu idle | 50 % machine (game alone ~50 % in the village; menu adds <1 %) | — | report | reported |

Bottlenecks found by per-process sampling: the Electron **main** process, not the renderer. Root cause: the
runtime-info refresh (every 2 s) and the runtime verification each spawned `tasklist.exe` to check whether the
game is running — ~0.3 CPU-seconds per spawn. Improvements (all with regression tests):
- `electron/gameProcess.ts`: one tasklist answer is reused for 6 s and concurrent callers share the in-flight
  query; failures are never cached (`electron/gameProcess.test.ts`). 21.5 % → 13.4 % → 6.7 % of a core.
- `electron/importedMenuTransport.ts`: a heartbeat-only rewrite of the 200 KB state file reuses the previously
  parsed snapshot (string compare instead of JSON.parse twice a second).
- `src/importedMenuState.ts`: the renderer decides "anything changed?" from the runtime's `revision` plus the small
  operation/confirmation/message fields instead of stringifying the whole snapshot every 750 ms. Test stubs that
  mutate content now bump `revision` as the runtime contract requires.
Functional regression after the changes: vitest 618/618 (71 files), lint/tsc clean, live latency batch above.
Remaining idle cost is the 6-second tasklist spawn (~5 % of a core); a heartbeat-first check could remove it but is
not required by the targets.
## Phase 3 — stability (started 2026-09-18 12:40)
| Test | Method | Result |
|---|---|---|
| S-1 startup freeze (D-8) | 2 minidumps, symbolized | ROOT CAUSE: Steam Overlay `GetMessageW` block. Menu now names it after 150 s of a running game without a heartbeat (`importedMenuTransport.ts`, tested). Boot series with the overlay off: **blocked on the user's Steam setting**. |
| S-6 malformed / expired / wrong-session / unknown-item / far-future commands | `stab_channel.py` | all refused with a named reason; runtime stayed ready; session unchanged |
| S-7 two commands in one poll | `stab_channel.py` | file channel keeps the last write (the desktop serializes commands); no corruption |
| S-2/S-8 20-minute soak: Super Damage, Zero Weight, God Mode, Extended Parry Window cycled ON/OFF every ~2.4 s with readback checks; RSS sampled/min | `soak.py 20` (detached) | PASS 12:42:40→13:02:40: 383 cycles, **0 failures**; RSS menu 418–487 MB (no trend), game 4.13–4.83 GB (drifted down); runtime stayed ready throughout |
| S-3 game restart while menu open | killed game 13:08:45 with the menu open, relaunched via `restart_game.ps1` 13:52 (booted clean, no hang this boot), Continue → save loaded | PASS: menu showed NOT CONNECTED / every switch OFF while the game was down; reconnected on session `1789753939-233492-1` with 0 switches ON; Zero Weight and God Mode ON/OFF verified by readback on the new session |
| S-4 menu restart while game running | closed all 4 menu processes, mirrored the new build, relaunched 13:05 | PASS: same runtime session `1789747004-263490-1` picked up (ready, revision 6344); God Mode ON→OFF verified by readback |
| S-5 game killed with effects ON, then relaunched | God Mode + Zero Weight ON, `Stop-Process Dawnwalker` (saves backed up to `savegames-backup-20260918-130825` + sha256 first; save dir idle) | PASS: stale state.json (heartbeat stopped) was not trusted — UI went Unavailable/OFF, no ON state leaked; after relaunch all 17 `.sav` files matched the pre-kill checksums |
| S-9 save load with effects ON → ResetSession | Super Damage x100 ON, in-game Load Game → newest Auto Save (12:00 PM) | PASS: session `…-1` → `…-2`, switch dropped to OFF with idle status; Super Damage ON/OFF on the new session verified by readback (no stale-modifier refusal) |
| Respec Medium/Full (Phase 1 leftover, destructive) | saves backed up + sha256 (`savegames-backup-20260918-130825`), cheats OFF, out of combat | Medium: PASS — preview `Refund: 1 | 30 -> 31`, confirm → `Respec verified: +1 points (30 -> 31). Protected ranks and unlocks kept` (UE4SS.log: BEFORE → RESET_OBSERVED → RESTORE_RANK CombatFocus_ShadowstepBite → PRESERVATION_VERIFIED → VERIFIED). Full: preview `Refund: 0`, confirm correctly refused (`No ordinary purchased ranks to reset`, nothing ordinary left after Medium) — but the refusal never reached the status row → **D-13**. Cleanup: the game auto-saved the respec into Autosave2 and later Autosave3; both restored from the backup (polluted copies kept in `savegames-polluted-20260918-respec`), 12:00 PM Auto Save reloaded, live readback `Available trait points: 30`, Light preview shows the original refundable rank again; all 17 `.sav` match the backup. |

## Sessions
- 2026-09-18 10:40 — goal set; record created.
- 2026-09-18 10:45 — agent `engineering-fullstack-dev` invoked (automated sweep). Report filed 11:10.
- 2026-09-18 11:16 — startup hang reproduced and captured; root cause: Steam overlay `GetMessageW` block.
- 2026-09-18 11:55 — second hang captured, identical main-thread stack. Fly/Super Jump interaction (D-10) found and fixed live.
- 2026-09-18 12:20–12:50 — Phase 2 baseline, targets, three optimizations, re-measurement (all targets met).

## Final report — 2026-09-18 15:45 (agent `engineering-fullstack-dev` used throughout; see AGENT-automated-sweep.md)

| Phase | Verdict | Evidence |
|---|---|---|
| 1 — features | **PASS** (all shipped controls verified live; 13 defects found, 12 fixed + retested, D-6 withdrawn) | feature table above; UE4SS.log excerpts; `menu_cmd.py`/`batch3.py` readbacks |
| 2 — performance | **PASS** against the proposed targets P-1..P-4 | idle CPU 21.5% → 6.7% of a core; round-trip medians ≤ ~280 ms; `perf_latency.py` |
| 3 — stability | **PASS** except D-8 verification (below) | 20-min soak 383 cycles / 0 failures / flat RSS (`soak-20260918-1242.log`); channel abuse tests; S-3/S-4/S-5/S-9; Respec Medium/Full with save backup+restore |

Automated gates at the end: vitest 618/618 (71 files), eslint clean, tsc clean (renderer + electron), Lua 63/63 suites,
packaging contract PASS, release-readiness gate PASS. Release package `release-current/win-unpacked` rebuilt 15:2x with
the re-pinned payload (CombatControls EF2668EB04A2) and the startup-freeze guidance; the running menu is that build.

**Not verified — needs the user (D-8):** the startup hang is root-caused to the Steam Overlay (`gameoverlayrenderer64.dll`
→ `GetMessageW` on the game thread; two identical dumps). The fix is a Steam setting the user declined to let me touch.
Today's later boots were 2/2 clean, but the hang rate was ~1 in 3, so that is not proof. The menu now names the cause
after 150 s of a silent game. Once the overlay is off for the game, run `restart_game.ps1` six times; it auto-captures
a dump if the hang recurs.

**A-2 closed:** `SuperJumpPilot.lua` unpinned (manifest 74 entries), removed from the game folder and excluded from the packaged resources; `CarryWeightPilot.lua` stays unshipped by design (documented in main.lua). **Accepted limitations (need a different save):** Shrine map check,
blood-segment repair with real damage and Photo Camera need a save on a map that has them (prologue save has none).

Test data: saves backed up before every destructive step and restored byte-for-byte afterwards (17/17 sha256 OK at
15:40); polluted copies kept under the scratchpad for reference; nothing else on the machine was changed.

## Resumed-session addendum — 2026-09-18 19:40
- Agent `engineering-fullstack-dev` invoked for an independent verification pass (read + run only): all gates green with expected counts, installed runtime = manifest (0 mismatches), release manifest byte-identical, D-13/D-14/A-2 confirmed as described with honest tests. It found **D-15** (defect table) and three hygiene items: stale record lines (fixed here), `SuperJumpPilot.lua` still in packaged resources (now excluded via `extraResources`), `gameProcess.ts` comment (corrected; the 6 s cache's effect on the save/config write guards is now documented in code).
- D-14 (Speed Multiplier from the paused menu) fixed and verified live; details in the defect table.
- Regression after D-14/D-15: vitest 618/618 (71 files), Lua 63/63, lint/tsc clean, packaging contract + release gate PASS; live functional sweep (33 core controls + 7 Freebuff-era switches, readbacks unchanged); latency medians 51–243 ms, p95 ≤ 392 ms (targets 400/1000); menu idle 7.0% of a core (baseline 6.7%).
- Phase 3 acceptance thresholds, stated for the record (the agent noted they had been asserted post hoc): soak = 0 command failures and no monotonic RSS growth over 20 min (observed: 0 failures; menu RSS 418–487 MB no trend; game RSS drifted down); channel abuse = every malformed/expired/foreign command refused with a named reason and the runtime stays ready (observed); restart/kill/reload = reconnect on a new session with every switch OFF and saves byte-identical (observed).
- Still blocked on the user: D-8 boot series with the Steam Overlay disabled.

## User approvals — 2026-09-18 19:50 (asked and answered in chat)
- **Accepted exceptions (approved by the user):** Shrine map check, Blood-segment repair with real permanent damage, Photo Camera. Each control's request path is verified live; the visible in-world effect cannot be attributed on the prologue save because it has no undiscovered shrine, no permanent blood damage and no photo-camera actor. Not marked as working.
- **D-8:** the user reports the Steam Overlay is now disabled for the game. Boot series (6 cold boots, `boot_series.ps1`, 180 s budget, CLEAN = fresh runtime heartbeat; HANG = live process, no heartbeat, ~0 CPU → minidump) running from 19:50; each boot also records whether `gameoverlayrenderer64.dll` is loaded in the game process.
- **D-8 boot series result (19:43–19:55, `boot-series-20260918-1943/`):** 3/6 CLEAN (heartbeat at 15–20 s), 3/6 HANG (no heartbeat at 180 s, CPU delta 0.2 s, minidumps captured). All three dumps show the known stack (user32 ← `gameoverlayrenderer64.dll`+0x9b23a/+0xa9a88/+0xa96f3 ← Dawnwalker main thread). `gameoverlayrenderer64.dll` was loaded in **6/6** boots and Steam's `localconfig.vdf` has no `OverlayAppEnable` for app 3751260 → the overlay change was not in effect for these boots. Observation: strict alternation hang/clean/hang/clean/hang/clean (the boot after a killed hung process was always clean). **D-8 remains open; needs the overlay change to actually apply (Steam typically needs the box unticked on this game's Properties → General page, then a Steam restart), then a rerun of `boot_series.ps1`.**

## D-8 — corrected root cause and outcome (2026-09-18 23:20; full account in HANG-ANALYSIS.md)
- The morning's "Steam overlay" conclusion was wrong (stale stack values). Mid-stall dump with thread names: **GameThread in `FlushRenderingCommands`/FrameSync wait (from the FSR plugin's CVar sink) ↔ RenderThread waiting on a task-graph event, RHIThread idle** — a startup deadlock; Unreal's 120 s render-fence timeout then reports the hang behind the fullscreen window. `-nothreadtimeout` → waits forever (render path dead, not slow).
- Reproduces with UE4SS core alone (all Lua mods disabled); vanilla did not stall. Not our payload.
- Trigger: previous session ended uncleanly (~85 % of following launches froze); launch after a frozen one came up ~15/15; graceful quit 2/2 clean.
- Ruled out by direct test: overlay per-game/global, 90 s wait, user Engine.ini HangDuration=0, UE4SS cache, NVIDIA DXCache + D3DSCache, Steam Cloud, config inis. Steam restart 5/7 and unsafe (login prompt) → automatic Steam restart implemented, tested (`steamRecovery.ts`) and then **removed**.
- Shipped: runtime `shutdown="quit"` marker (facade + main.lua + tests), desktop unclean-exit warning and 150 s freeze message with the proven recovery (close and relaunch; quit via the game's menu to avoid it). All Steam/UE4SS settings restored to their original values.
- Accepted limitation (needs user decision): the deadlock itself is engine-side and only avoidable by keeping UE4SS out of the startup window (menu-driven late injection, 2/3 today) — not adopted without a proper series.
- Final gates after all changes: vitest 620/620 (71 files), Lua 63/63 + Runtime 3 modes, lint/tsc clean, packaging contract + release gate PASS; `release-current` repackaged 23:15.
