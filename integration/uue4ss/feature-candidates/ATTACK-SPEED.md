# Player attack-speed candidate

Status, 2026-09-06 UTC: **Implemented and tested offline; not integrated or verified in game.** The root coordinator owns installation, game input, and live state. This module registers no hooks or capabilities and changes no files when loaded.

## Implementation

`AttackSpeedController.lua` retains the existing five-mode contract and accepts a multiplier from 0.5 to 2.0. Every adjustment uses the first captured per-mode originals, so repeated changes do not compound. It validates all targets before writing, verifies both attack rates and unrelated values after writing, and restores through the same native fields. A retained inverse journal handles setters that fail before or after mutation. An inverse failure on one field does not skip the other field; a later `restore()` can retry. Unexpected outside edits or player/world/config/mode changes retain the snapshot and refuse to overwrite the new state. Readbacks report uncertainty instead of a successful multiplier when rates drift or restoration is pending.

`AttackSpeedNativeAdapter.lua` resolves the current local controller/pawn, owned player combat component, getter/property config agreement, and five `CombatModes` entries. It requires mapped, valid `UScriptStruct` wrappers with stable struct/property addresses. Its only assignments are `MetricsScalingSettings.AttackPlayrate` and `.StrongAttackPlayrate`. The unrelated fingerprint covers all other 24 fields of `FMetricsScalingSettings` plus `DodgeStaminaCost`. No global time, damage, stamina, dodge, block, parry, or NPC field is assigned.

Each resolution scans at most 4,096 loaded `CombatComponentBase` objects and at most 64 map entries per non-player component. It checks every NPC map key for a shared mode/config and requires an actual non-player witness. A scan can reject unavailable/template/unowned objects; preserve that result for review rather than skipping arbitrary records. The scan observes loaded components only and **does not prove player-only asset semantics after streaming or spawning**.

The adapter pins this isolated candidate to Steam `25129649`, executable SHA-256 `7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853`, and fresh metadata SHA-256 `CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6`. These constants do not change production compatibility pins.

## Host interface and integration dependency

Construct `Adapter.new(deps)` with `get_identity`, `is_in_game_thread`, `get_player`, `get_player_controller`, `find_all_of`, and `get_write_review`. The identity provider must be the coordinator's current verified installer/session data, including a boot ID. Calls must execute synchronously on the verified game thread. The controller is constructed with `Controller.new(adapter.resolve)`.

Without a native review, `adapter.resolve()` can return a read-only context with `npc_isolation_verified=false` and a `write_review_error`; each mode's `read()` remains available. Controller application and direct adapter writes refuse that context. `get_write_review()` must return a review with exact `context_identity`, exact `mode_set_identity`, `native_struct_write_verified=true`, `player_only_assets_verified=true`, and the recorded `evidence_id`. This is a host contract for real evidence, not an alternative permission token or proof generator. No such review exists in this implementation. Do not populate it from a successful mock test, metadata comparison, archive description, or the loaded-NPC scan alone.

When eventually integrated, use one controller instance per boot, serialize actions with the existing bridge transaction lock, preserve pending snapshots after errors, and invoke restoration before teardown. Do not automatically apply to replacement worlds or modes. The command handler must catch failures, report them through the existing error response, and publish values only from `read()`. Avoid polling `resolve()` each frame: `FindAllOf` scans the full native object array. Keep the existing global-game-speed command separate. Add a capability only after the host review and gameplay evidence gates have passed; this candidate does not modify `main.lua`, the renderer, the installer, or capability contracts.

## Fresh evidence still required

1. Restore supported Computer Use and stage the reviewed current-build read-only driver through the root coordinator's isolated transaction. Preserve exact identity, boot, visible save slot, player/world IDs, and raw `attack_modes` observations.
2. Capture all five concrete mode paths/addresses and all metric scalars. Run the bounded `CombatComponentBase` ownership scan read-only. Review the mode assets and NPC configs, including streamed/spawned NPCs; resolve any alias or unavailable-object failure using observed evidence.
3. Establish mapped-struct address stability and perform a separately reviewed, bounded native write/readback/inverse experiment on a disposable backed-up offline save. The production controller must not fabricate a native review to perform its own prerequisite experiment. Record exact before, applied, inverse, and after values on the same concrete objects and prove no unrelated scalar changed.
4. Exercise activation, 1.25x to 1.5x changes, repeat use, disable, and original restoration. Record light/combo/heavy attack timing independently of world time and compare unchanged NPC, dodge, block, and parry behavior. Charged attacks, focus abilities, and weapon arts have no contract here.
5. Test sword, vampire sword, hand-to-hand/claws and fistfight transitions, new NPC arrival, save reload, reconnection, and application exit/restart. A changed identity currently refuses mutation and retains restoration state; automatic cross-world recovery is not implemented. Decide any broader transition contract from those observations, not mock assumptions.

## Verification

Run from the project root:

```powershell
lua integration/uue4ss/feature-candidates/tests/AttackSpeedController.Tests.lua
lua integration/uue4ss/feature-candidates/tests/AttackSpeedNativeAdapter.Tests.lua
luac -p integration/uue4ss/feature-candidates/AttackSpeedController.lua integration/uue4ss/feature-candidates/AttackSpeedNativeAdapter.lua integration/uue4ss/feature-candidates/tests/AttackSpeedController.Tests.lua integration/uue4ss/feature-candidates/tests/AttackSpeedNativeAdapter.Tests.lua
```

Controller: 12 passing test groups. Adapter: 11 passing test groups, including concrete controller/adapter roundtrip, only-two-field mutation, NPC alias under an unrelated enum, mapped-struct identity changes, stale session review, native-float bounds, and actual captured-header checks for class paths and scan class. Syntax validation passes for all four Lua files. These tests use mocks and static metadata; no native or gameplay success is implied. All four Lua files carry executable `cyberfox1337x.function_signature` markers. Runtime lead independently reviewed recovery/identity/review gating; no blocking issue was reported, with loaded-object enumeration behavior retained as a live discovery dependency.

## Evidence and credit

- Fresh `qa/discovery-current-build-20260906/fresh-metadata/CXXHeaderDump/DogwoodCombat.hpp`: `FMetricsScalingSettings` at 312, `UCombatComponentBase` at 1091, `GetConfig` at 1258, `CombatModes` at 1362, `UCombatMode` at 1549, `UPlayerCombatComponent` at 1949.
- Fresh `Engine.hpp`: `K2_GetPawn` at 9536 and `IsLocalController` at 9541.
- Bundled pinned UE4SS documentation: `Docs/lua-api/classes/uscriptstruct.md`, `tmap.md`, and `global-functions/findallof.md`. These document typed property assignment and container access; their existence does not verify this game's live marshaling.
- [Grimpil, Faster Attacks - Player Attack Speed](https://www.nexusmods.com/thebloodofdawnwalker/mods/57), version 1, updated September 3, 2026; metadata and description checked September 6 UTC. The source describes two attack-specific rates, separate from global speed, with selected special abilities excluded. Settings attribution remains **feature inspiration; independently implemented**. No creator archive, source code, or asset was copied, and no new dependency was added. The user's granted reuse permission is acknowledged; source acquisition and any additional conditions remain distinct from implementation evidence.
- Related workspace record: `analysis/dawnwalker-uue4ss/REQUESTED-RUNTIME-FEATURE-DISCOVERY.md` and the current-build read-only candidate README.
