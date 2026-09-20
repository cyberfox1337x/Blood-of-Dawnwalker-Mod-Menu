# Dawnwalker Mod Menu v3.2

v3.2 adds exact Corruption levels, individual perk grants and three respec depths
to the v3.1 gothic-kawaii interface and equipment tools. See CHANGELOG.md for the
complete history.

**After setting an exact Corruption level, press +1 raw charge (optionally -1
afterward), or drink blood, so the game refreshes the new level's gameplay
effects.**

## Downloads and upgrading

The existing two-package arrangement remains: UE4SS Setup supplies the compatible
loader and helpers; Mod Menu supplies F12SkillPoint and shared ModMenu.
Existing users with a compatible setup need only the updated menu, not new loader settings.
Keep v1 outside the game's Mods folder; do not run duplicate enabled copies.
The frozen v1 source and published packages are unchanged.

## Features and controls

### Keyboard and Player

- **F6**: open or close the menu after loading a save.
- **F12 / F11**: add or remove one unused skill point.
- **Refill stamina now**: one immediate stamina refill.
- **Rapid stamina refill**: repeatedly replenishes stamina while enabled; the
  meter may briefly decrease before the next refill.
- **Quick fill activation charge**: quickly replenishes combat activation charges.
- **No ability cooldown (quick reset)**: quickly clears cooldowns while enabled.
  Abilities still require normal costs and eligibility.
- **Player status**: refresh the displayed health and stamina percentages.

### Auto Parry — new in Player

- Enable **Auto parry while blocking**, then hold right mouse to block. Sets the
  player's eligible block-to-parry chance to 100% through the game's own attribute.
- Stays active during normal play until toggled OFF. ON/OFF behavior was confirmed
  in gameplay. Safety checks may also stop it on death, character changes,
  unavailable objects or independent changes to the affected value.
- OFF restores the previous value if the mod still owns the override; independent
  game changes are preserved. The base attribute value is not changed.
- WASD controls are not intercepted. Does not change parry timing, attack damage
  or ability costs. Unblockable and wrong-direction attacks are not guaranteed.
- Defaults OFF at script startup. Turn OFF before saving, loading or reloading
  scripts: persistence across save/reload has NOT been verified.
- Original attribute-based implementation. UniversalAutoParry is not required;
  its DLL, code and signatures are not included. Avoid combining parry overrides.

### Progression

- **Skill points**: add or remove a chosen amount, or clear the unused balance.
  Removing unused points does not unlearn skills.
- **Experience (XP)**: grant XP using the available reward sizes.
- **Corruption**: set the attained level directly from 1–15, or adjust raw charge
  within the current level. Exact level changes reset within-level charge to zero.
  After setting a level, press **+1 raw charge** (optionally **-1** afterward), or
  drink blood, to refresh gameplay effects. Lowering the value does not reverse
  quests, dialogue, unlocks, achievements or other triggered events.
- **Fast travel shrines**: unlock shrine travel points after confirmation.
  Does not complete associated quests; there is no menu undo for saved unlocks.
- **Three respec depths**: Light preserves Ultimates and broad earned protections;
  Medium removes supported Ultimates but keeps the broad protection policy; Full
  restores ranks only for the five named critical abilities. Every mode previews
  the KEEP list and refund before changing anything.
- If removable ranks cost more than the spent-points ledger, the difference may
  come from legendary-consumable upgrades. The preview identifies the difference
  and requires a separate **Convert and respec** confirmation. Continuing converts
  it into skill points; consumed items are not restored. **Cancel** makes no change.
- **Grant selected Ultimate**: directly grants one of the nine Ultimates at rank 1,
  bypassing normal prerequisites, exclusivity and skill-point cost.
- **Grant Specific Perk**: search the complete loaded trait list, select a target
  rank and grant only that perk. This bypasses prerequisites, exclusivity, manuals,
  quests and skill-point cost; the menu verifies unrelated perks and point ledgers.
- **Unlock Everything / Max All Traits**: maxes the full trait database, including
  ordinary, hidden, manual, quest and boss traits—not only the nine Ultimates.
  It also marks recipe/manual-based skill access as learned/read and can be used
  repeatedly.

### Inventory and Warnings

- **Coins**: add or remove the selected amount.
- **Crafting materials**: select a material and grant the chosen quantity.
- **Skill manuals**: select a loaded character-development manual and add one
  physical copy. The menu does not mark it read or directly unlock its skill;
  read/use the manual normally in game. Duplicate or out-of-order manuals may
  not provide another unlock.
- **Keys & key items — unsafe**: searches loaded inventory assets for probable
  keys and grants one physical copy after confirmation. It does not advance the
  quest or acquisition event that normally awards the key.
- **Items and equipment**: browse eligible items and grant the selected quantity
  and applicable equipment level. Quest and ordinary readable items are excluded
  from this general browser; manuals and keys have their own panels.
- **Give all Weapons + Clothing**: grants one of every indexed weapon and clothing
  item, applying the selected level where supported. The queue waits for each
  inventory operation to finish before its 20 ms pause. Consumables, materials,
  recipes and junk remain individually selectable but are excluded from bulk
  granting after a native crash was traced to the Recipe4 asset.
- **Warnings & Limitations**: summarizes irreversible changes, known respec and
  time restrictions, achievement behavior, menu-open FPS impact and compatibility.

### Infamy — new in World

- **Increase Infamy (+100 points)** adds one milestone's worth of Infamy.
- **Decrease Infamy (-100 points)** removes the same amount.
- Preserves partial progress: 145 becomes 245 or 45. Clamps to the validated 0–900
  range, so adjustments can be smaller at the limits.
- Requires confirmation and a living player out of combat. Each change is checked
  against the requested result.
- Repeat successful changes are allowed. Failed mutation verification blocks
  further writes until you reload your backup and restart.
- Can trigger world or quest events. Lowering Infamy is not an undo and does not
  guarantee reversal of every world-difficulty effect.

### Time Segments — new in World

- **Advance 1 segment** moves the clock forward by one segment.
- **Rewind 1 segment** moves the clock backward by one segment.
- One segment is 1.5 game hours in the validated configuration (eight per phase).
- Both directions and repeated changes work without a once-per-session limit.
- Wait roughly one second for verification before pressing again. If verification
  fails, reload your backup and restart instead of saving or retrying.
- Forward advances cross day/night boundaries and midnight through the game's
  native segment progression. Forward progression may advance the campaign
  deadline and timed quests. During rollover, wait for the transition to finish;
  the menu verifies the result without issuing another advance.
- Rewind only moves among slots within the current day/phase. It cannot return to
  a previous day, cross backward through a day/night boundary or restore quests.
- Leave combat, dialogue and cutscenes, turn combat cheats OFF and retain a manual
  backup. Advancing time may progress timed quests; rewinding does not undo events.

Health/god mode and heal-wounds are not supported menu features. GodMode.lua is
retained only for cleanup of previously mod-owned flags.

## Warnings and limitations

- **Cheats will trigger achievements.** Saved progression and inventory changes
  remain after the mod is removed.
- Full Respec currently may keep **Font of Life** and **Mandrake Ward**. This known
  exception is intentionally unchanged.
- **Light Respec** keeps supported Ultimates and broad earned protections.
  **Medium Respec** removes supported Ultimates but retains broad earned, quest,
  boss-blood and manual-access protections. **Full Respec** restores ranks only
  for Compel Soul, Astral Communion, Voracious Bite, Mercurial Fervour and Wolf
  Transform after the native reset. The native Font of Life/Mandrake Ward
  exception may still remain.
  Legendary-consumable upgrades may be converted into skill points; consumed
  items are not restored.
- Bulk Unlock affects ordinary, hidden, manual, quest and boss traits and marks
  recipe/manual-based skill access as learned/read. It is repeatable. Grant
  Ultimate bypasses its normal prerequisites, exclusivity and skill-point cost.
- Give Manual adds a physical manual without directly changing read/unlock state.
  Receiving or using a manual outside its intended progression order may still
  have save consequences, and duplicate manuals may do nothing.
- Give Key adds only the physical key. It does not advance the related quest
  state, so a wrong or duplicate key may remain permanently, bypass progression,
  duplicate a later reward or leave the inventory and quest ledger mismatched.
- Unlock All Shrines permanently changes map progression. Lowering Infamy or an
  attained Corruption level does not undo world or quest events. Exact Corruption
  changes require the +1-charge or blood-drinking refresh described above.
- Time can move forward across days. Backward movement is limited to slots within
  the current day/phase: the mod cannot return to a previous day or reverse quests.
- Do not reload scripts while respec or another verified operation is running.
  If verification fails, do not save or retry; reload an earlier save and restart.
- The menu uses the engine cursor instead of ModMenu's custom cursor, eliminating
  the custom 16 ms cursor-position polling loop. UE4SS overlay rendering can still
  reduce FPS while the menu is open; normal performance returns after closing it.
- The supplied setup keeps HookLoadMap disabled due to its reproduced crash.
  Game or UE4SS updates may require a compatibility update.

## Tested versions

- Steam game build **25129649**, Unreal Engine **5.5.4**.
- Dawnwalker.exe SHA-256:
  `7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853`.
- UE4SS shipping build **v3.0.1-1111**, commit
  `97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1`.
- UE4SS.dll SHA-256:
  `FB1839EE91F71F83D508D44A2763A15AC1BB0C5FB4E504AC0FCFCA64376A054A`.
- dwmapi.dll SHA-256:
  `74EFB8F6F368830EC80BE031B4E1EEE7006F228B9EDD5C1877FE27A8E29DC6CD`.

The signatures included here are those used in the successful local configuration.
They are build-specific compatibility files, not a promise of future compatibility.
This is a third-party repack of an upstream pre-release runtime, not an official
UE4SS release or a universal loader for other games.

## Bundled helper mods: tested versus disabled

| Helper | Included setup state | Coverage |
| --- | --- | --- |
| CheatManagerEnablerMod | Enabled | Tested together with the menu and helpers below |
| ConsoleCommandsMod | Enabled | Same combined setup |
| ConsoleEnablerMod | Enabled | Same combined setup; F10/tilde console bindings |
| Keybinds | Enabled | Same combined setup |
| BPModLoaderMod | Enabled | Same combined setup; see LoadMap limitation |
| BPML_GenericFunctions | Enabled | Same combined setup; see LoadMap limitation |
| SplitScreenMod | Disabled | Kept at its off default; not tested, not identified as faulty |
| LineTraceMod | Disabled | Kept at its off default; not tested, not identified as faulty |

All eight are included as stock helper files; the last two remain disabled in
mods.txt. No standard helper was removed because it was proven to cause the crash.
Successful coexistence does NOT certify every console command, helper feature,
third-party Blueprint mod, map transition, or cutscene. The menu itself does not
require the cheat/console/Blueprint helpers; UEHelpers and shared ModMenu are required.
Development probes, raw-reset experiments, logs and personal state are not included.

## Hooks: enabled versus disabled

These were enabled together in the successful local setup, not individually certified:

| Hook | Setting |
| --- | --- |
| HookProcessInternal | 1 |
| HookProcessLocalScriptFunction | 1 |
| HookInitGameState | 1 |
| HookCallFunctionByNameWithArguments | 1 |
| HookBeginPlay | 1 |
| HookEndPlay | 1 |
| HookLocalPlayerExec | 1 |
| HookAActorTick | 1 |
| HookEngineTick | 1 |
| HookGameViewportClientTick | 1 |
| HookUObjectProcessEvent | 1 |
| HookProcessConsoleExec | 1 |
| HookUStructLink | 1 |
| **HookLoadMap** | **0 — disabled workaround** |

The observed access violation reproduced with this menu DISABLED. Matching-symbol
analysis located the fault in UE4SS's LoadMap post-callback bridge; the underlying
signature/ABI cause was not conclusively established. Disabling only HookLoadMap
avoided that reproduced crash. Earlier tests disabling ProcessInternal and
ProcessLocalScriptFunction did NOT resolve it; both were re-enabled in the passing setup.

IMPORTANT: HookLoadMap=0 may impair Blueprint mods that depend on map-load callbacks.
This is not compatibility with every default hook or every mod. Do not turn it back
on and assume the previously reproduced crash is fixed.

## Installation

1. Close the game. Back up your saves and existing loader/mod files.
2. For a fresh compatible setup, extract the UE4SS Setup ZIP into
   `<game folder>/Dawnwalker/Binaries/Win64`. dwmapi.dll goes beside Dawnwalker.exe;
   the ue4ss folder goes there too. Do NOT replace an existing proxy DLL blindly.
3. Extract the Mod Menu ZIP into that same Win64 directory, merging folders.
   It adds `ue4ss/Mods/F12SkillPoint` and `ue4ss/Mods/shared/ModMenu`.
4. The menu includes enabled.txt. Do not leave duplicate renamed copies enabled.
5. Start the game, load a save, and press F6. Combat toggles start OFF.

The loader package includes a clean mods.txt and tested UE4SS-settings.ini.
Existing users must compare/merge these instead of overwriting their mod list,
settings, proxy or signatures. The menu package does not overwrite them.
Existing shared ModMenu versions should be backed up before replacement.
No personal preferences, save files, runtime-session files or logs are distributed.

## Respec safety and accounting

The game keeps parallel saves, and v3.2 does not require a backup checkbox. You
should still retain a pre-respec save. For an external backup, close the game and copy the entire
`%LOCALAPPDATA%/Dawnwalker/Saved/SaveGames` folder to a separate safe location.

Leave combat and turn cheats off. Preview the refund and named KEEP list, then
confirm within 90 seconds. Cancel is available only before confirmation.
While respec runs, do not spend points, enter combat, save, load saves or reload scripts.

Light and Medium retain previously owned essential/always-equipped and
quest/boss-blood ranks; Shadowstorm is included when previously owned. Full keeps
only the five named critical ranks. All modes preserve per-trait unlock-access
bookkeeping, and no mode grants an unearned boss ability. When a trait is protected,
all of its previously owned ranks are kept rather than only its base rank.

Only removed ordinary ranks are refunded, at CURRENT configured costs. Protected
ranks and unexplained historical spent points are excluded. Example verified
during development: 4 available / 55 spent -> 48 available / 11 spent; refund 44.
The remaining 11 is retained ledger value, not an asserted 11-point fee.
The user confirmed the corrected points and protected abilities persisted after reload.

Successful respecs can be repeated in the same script session. A failed or
partially verified mutation blocks another attempt until the game is restarted.
Light Respec preserves all nine known Ultimates. Medium includes supported
Ultimates in the reset and refund calculation while retaining broad earned
protections. Full restores ranks only for Compel Soul, Astral Communion, Voracious
Bite, Mercurial Fervour and Wolf Transform. Font of Life and Mandrake Ward may
still remain because the game's native reset does not clear them.

If verification fails, partial changes may have occurred: do NOT save or retry.
Reload an earlier save. Keep UE4SS.log before restarting for diagnosis.

## Performance and compatibility scope

No noticeable gameplay performance impact was reported on the validated system.
No benchmark CSV or quantified FPS/frametime result was supplied;
this is not a zero-overhead guarantee. Menu polling stops when closed; combat timers
run only while enabled. First-use item indexing and respec perform temporary work.

The Dawnwalker menu selects `cursorMode="engine"`. This avoids creating and moving
a ModMenu-owned pointer every 16 ms. The menu itself still has to render and handle
input while open, so this optimization does not promise zero menu-open FPS cost.

v3.2 Auto Parry checks cached player state every 200 ms while enabled, without
global object scans or repeatedly forcing the attribute. Infamy/time changes
run on button presses; time adds delayed verification only while an operation runs.
No quantified v3.2 benchmark has been recorded.

Other game builds, future patches, all hardware, every cutscene and unrelated
third-party mods are outside the verified scope. Retest after game/UE4SS updates.
Do not report this build as universally compatible or patch-proof.

## Disable / uninstall / reporting

Turn cheats off and close the game. To disable only the menu, move F12SkillPoint
outside Mods, or disable its mods.txt entry AND remove/rename enabled.txt.
Changing mods.txt alone may not disable a folder with enabled.txt.
Keep shared libraries if another mod uses them. Uninstallation does not undo saved
points, inventory, shrine or respec changes; use your pre-change save for that.
Do not remove the shared UE4SS loader when other mods depend on it.

For reports include game build, UE4SS version, enabled mods, relevant settings,
steps and UE4SS.log. Redact personal paths before posting publicly.

## Credits and license notices

UE4SS: https://github.com/UE4SS-RE/RE-UE4SS — MIT, copyright 2022 Narknon.
Shared menu: https://github.com/mattdavida/ue4ss-ModMenu — MIT, copyright 2026 Matthew arvidson.
The original licenses and third-party notices are retained in the appropriate ZIP.
The loader's existing notices document unresolved upstream dependency-license records;
this package preserves that disclosure and does not claim a complete legal audit.

This document applies to Dawnwalker Mod Menu v3.2.
