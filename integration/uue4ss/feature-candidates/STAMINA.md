# Independent stamina discovery candidate

Status, 2026-09-06 UTC: **Native read-only probe implemented; twelve offline test groups pass. Sprint, dodge, omniblock, and directional-block adjustments are not implemented or verified in game.** The probe is not installed, registered, or connected to the menu. No shared bridge, current driver, capability, or production pin was changed.

## Concrete delivered behavior

`StaminaReadOnlyProbe.lua` obtains native `FGameplayAttribute` descriptors from the local player's actual `AbilitySystemComponent:GetAllAttributes`. It passes those original descriptors to reflected read-only functions. It never constructs a guessed descriptor table or writes `BaseValue`/`CurrentValue`.

For each selected attribute, it checks descriptor name and owner type, stable native struct address, `GetAttributeSet(descriptor.AttributeOwner)` agreement with the player's actual attribute-set property, and `GetDebugStringFromGameplayAttribute`. It then compares `ASC:GetGameplayAttributeValue` with captured `CurrentValue` and `AbilitySystemBlueprintLibrary:GetFloatAttributeBaseFromAbilitySystemComponent` with captured `BaseValue`. A native read is marked verified only when the return shape is exactly a finite number followed by `true`. Missing, false, reordered, extra, nonfinite, or mismatched return/out-bool values are recorded as unverified. This intentionally preserves the live ABI question instead of inferring success from a matching number alone.

| Channel | Actual reflected attribute | Scope |
| --- | --- | --- |
| Sprint | `PlayerAttributeSet.SprintStaminaCostMultiplier` | Independent cost attribute; numeric semantics and actual cost remain unverified. |
| Dodge | `PlayerAttributeSet.DodgeStaminaCostMultiplier` | Independent cost attribute, plus a separate observed `CombatComponentBase:GetDodgeStaminaCost()` result. |
| Omniblock | `CharDevAttributeSet.OmniblockStaminaCostMultiplier` | Omniblock only; not evidence of directional blocking. |
| Directional block restoration | `CharDevAttributeSet.DirectionalBlockStaminaRestoreMultiplier` and `.DirectionalBlockStaminaRestoreModifier` | Restoration/reward fields, not directional-block cost controls. |

The probe also records the exact loaded player combat config, its `StaminaDamageEffectClass`, `OmniblockStaminaDamageEffectClass`, `BlockStaminaRegenEffectClass`, and `CombatActionStaminaCosts` table. This supplies concrete provenance for investigating directional blocking without claiming the formulas or table rows have been decoded. It reads `IsVampire()` and rejects a form change, world/player/ASC/attribute-set identity change, or cross-channel attribute drift during the capture. Each channel and the combat section retain independent failure details when the overall context is stable.

The exact-build gate requires Steam `25129649`, executable SHA-256 `7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853`, metadata SHA-256 `CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6`, and the current boot ID. Local controller/pawn and ASC owner identities must agree. Descriptors are bounded to 1,024 entries and duplicated selected names fail their channels. No hooks, hotkeys, effects, setters, forced asset loads, generic stamina locks, or capability advertisements are present. `mutation_authorized=false`, `gameplay_verified=false`, and an empty capability list are unconditional.

## Running and integration

Offline commands, from the project root:

```powershell
lua integration/uue4ss/feature-candidates/tests/StaminaReadOnlyProbe.Tests.lua
luac -p integration/uue4ss/feature-candidates/StaminaReadOnlyProbe.lua integration/uue4ss/feature-candidates/tests/StaminaReadOnlyProbe.Tests.lua
```

Twelve groups cover five independent channels, real descriptor pass-through, native result-shape ambiguity, getter disagreement, missing/duplicate descriptors, wrong owner/ASC set, build/thread/local-player guards, form changes, cross-channel drift, independent combat failure, bounded arrays, mutation exclusion, and exact native signatures/attribute names in the current captured headers. Both Lua files have executable `cyberfox1337x.function_signature` markers. These are mock/static checks; no live getter has yet been verified.

The root coordinator can call `Probe.run(deps)` inside a separately reviewed current-build read-only game-thread callback, with `get_identity`, `is_in_game_thread`, `get_player`, `get_player_controller`, and `static_find_object`. Use the existing verified player resolver and attestation issuer; do not handwrite an attestation or reinterpret `ok=true` as native success. The result is a bounded plain-data table suitable for the existing read-only report formatter. Review each channel's `ok`, `getter_verified`, and native getter diagnostics separately. No probe dependency is shared with the independently owned focus module.

## Exact remaining implementation boundaries

1. Computer Use stopped the coordinating turn on a browser-URL verification failure. No app/game input may resume until the tool permits supported recovery. No candidate was staged by this agent.
2. Once the coordinator resumes a recorded disposable offline save, capture separate human/vampire and in-combat/out-of-combat reports. Preserve native descriptor owner names/addresses, base/current values, native values, found flags, return types, real dodge cost, and effect/table identities. A header signature does not prove Lua out-parameter marshaling.
3. The reflected mutation candidate is `CombatBlueprintFunctionLibrary.SetAttributeValue(ASC, FGameplayAttribute& AttributeToSet, float AttributeValue)`. Its reference/out descriptor ABI remains unverified. No direct write adapter was added: read-only by-value success would still not prove this by-reference setter or its aggregation/restoration behavior.
4. Determine the actual formula for each cost path before choosing menu numbers. A zero base multiplier cannot safely be assumed to mean zero cost, and a restoration modifier is not a cost multiplier. Inspect the authorized original mod archive or the concrete current effect/table data; no archive bytes were obtained this turn.
5. Implement each supported per-action setter with its own original snapshot, bounded range, independent readback, rollback, and recovery only after those prerequisites. Test actual isolated sprint, dodge, directional-block hits, and omniblock consumption in each form, followed by exact restoration, repeated adjustments, combinations, streaming/reload, reconnect, and application exit. Keep broad Unlimited Stamina disabled during these tests so it cannot mask individual costs.

## Source and credit

[nectarines, Stamina and Sprint Tweaks](https://www.nexusmods.com/thebloodofdawnwalker/mods/17), version 0.3.0, updated September 3, 2026; primary page checked September 6 UTC. The author distributes a sprint module and a combined block/dodge module. The latest changelog claims directional-block fixes and both forms; an older tested-version subsection still says 0.1.0. Those author claims are not evidence that our independent runtime controls work. Settings credit remains **feature inspiration; independently implemented**. The user's granted reuse permission is acknowledged; no code/assets were copied, and no new loader/dependency was introduced.

Authoritative local sources: fresh `DogwoodStats.hpp` lines 270-272 and 842-843; `GameplayAbilities.hpp` lines 286-292, 1244, 1248, and 1409-1411; `DogwoodCombat.hpp` lines 1249 and 1291-1303; `Dawnwalker.hpp` line 1599. Related: `ATTACK-SPEED.md`, the current-build read-only candidate README, and `analysis/dawnwalker-uue4ss/REQUESTED-RUNTIME-FEATURE-DISCOVERY.md`.
