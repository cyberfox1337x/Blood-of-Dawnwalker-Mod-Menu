# Focus native readback and camera discovery

2026-09-06 UTC. **Implemented source; not installed; Not verified in game.** This is concrete current-build read-only integration code, not a working Focus editor. No production capabilities, UI controls, build pins, loader configuration, or saves changed.

## Reference and boundaries

[Focus Tweaks](https://www.nexusmods.com/thebloodofdawnwalker/mods/81) by **Caites**, version 1.2.1, was freshly reviewed. The author describes detection/smell distance increases, reduced zoom and FOV override, and a separate optional brighter-target postprocessing package. The main download uses UE4SS; the optional download uses Paks containers. The page claims game version 1.0.3 compatibility without this project's exact executable identity. No additional contributor is named. The user's permission is acknowledged; no third-party code or assets were downloaded, imported, or redistributed. Existing Settings attribution remains valid.

The source uses the locally captured CL-257186 headers, not inferred Nexus implementation details. It pins build `25129649`, executable SHA-256 `7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853`, and JMAP SHA-256 `CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6`. These pins authorize only the bounded observation scope through a separately attested host; they grant no gameplay compatibility.

## Delivered files

- `FocusReadOnlyProbe.lua`: standalone module returning `run(deps)`. No entrypoint, scheduling, native property writes, gameplay effects, descriptor fabrication, forced asset load, or capability advertisement.
- `tests/FocusReadOnlyProbe.Tests.lua`: executable Lua regression fixtures plus assertions against the actual fresh native headers. Both code files include valid `cyberfox1337x` signatures.

## Concrete native attribute path

1. Resolve the local player through the supplied controller and player getters. Require `IsLocalPlayerController`, pawn/controller agreement, shared world, `bIsInFocusMode`, and `IsVampire` stability.
2. Follow the player's `CharacterAttributeSet` and `AbilitySystemComponent`; verify owner/outer links, `ASC.GetAttributeSet(PlayerAttributeSet)` equality, and the independently resolved Blueprint-library ASC.
3. Obtain actual `FGameplayAttribute` instances using `ASC.GetAllAttributes`. Require one unique descriptor for each of `MaxFocusRange`, `MaxFocusSmellRange`, `ActiveFocusRange`, and `ActiveFocusSmellRange`, with exact native owner class and valid native struct identity. Keep the complete returned array alive during all borrowed calls.
4. Pass each borrowed descriptor to `GetDebugStringFromGameplayAttribute`, `ASC.GetGameplayAttributeValue`, and the Blueprint-library `GetFloatAttributeFromAbilitySystemComponent` / `GetFloatAttributeBaseFromAbilitySystemComponent`. Compare native effective/base values with the corresponding `GameplayAttributeData` values.
5. Record numeric values, boolean presence, return count and ordered return types. Only exact `number, boolean(true)` shapes across all three getters set the observation's `native_getter_verified` flag. A matching number without an observable found flag, or a reordered/extra-nil shape, remains explicitly unverified. An explicit false flag, numeric mismatch, or ambiguous result rejects the attribute section.
6. Recheck all four attributes after the camera read, plus ASC/attribute-set and player/world/focus/form identities. A cross-channel or late change discards the entire partial snapshot.

The current native header does not expose `GetNumericAttributeBase` or `GetNumericAttribute` as reflected callable functions. This probe does not invent those aliases. No setter is invoked or represented as validated. Base and effective values can differ because of aggregation; assigning both directly would not establish a safe persistent or reversible edit.

## Concrete camera path

Follow `player.FollowCamera` (`URebelCameraComponent`) and its bounded `CameraModeStack`. Require every observed mode's `GetCameraComponent()` and `GetTargetActor()` to match this camera/player. Identify `UFocusAbilityCameraMode` by class, not a name substring or global first instance. Capture stack handles, camera type, mode state, default/effective FOV and postprocessing flag.

For actual Focus modes, enumerate the inherited `CameraOffsets` map using the reflected `ECameraType` domain (0..3). Capture each real `FCameraOffset`'s FOV override flag/value, pivot offset, target XYZ, and pitch-curve flag. Recheck stack membership and selected camera type. A missing Focus mode outside Focus is reported as absent; no default object is substituted.

This discovers candidate zoom/FOV ownership and values. It does not set global FOV, change generic exploration cameras, edit curves, rewrite postprocess materials, or assume the optional highlight assets are equivalent to a scalar property.

## Host integration contract

`run(deps)` requires these functions:

| Dependency | Required result |
|---|---|
| `get_identity()` | Fresh host-verified `build_id`, `executable_sha256`, `metadata_sha256`, `boot_id` |
| `is_in_game_thread()` | Native `IsInGameThread()` result inside the bounded EngineTick callback |
| `get_player()` | Current local `DawnwalkerPlayerCharacter` |
| `get_controller()` | Current local player controller |
| `static_find_object(path)` | Native lookup; only the exact PlayerAttributeSet class and AbilitySystemBlueprintLibrary CDO are requested |

The result includes `ok`, `attributes`, `camera`, current context/form state, empty capabilities, and permanent `mutation_authorized=false` / `gameplay_verified=false`. `ok=true` only means the overall identity remained stable; inspect each section's `ok` and `native_getter_verified` independently. The existing bounded report formatter can serialize the result when a reviewed host explicitly passes it there.

The shared current-build read-only driver and attestation issuer remain unchanged. Before live use, a separate reviewed host integration must include this module in its verified installation inventory, invoke it only inside the attested callback, and preserve its report with boot/build/selected-save evidence. Do not silently copy it into the existing candidate and assume that issuer's original three-script check covers the new file.

## Verification and remaining gates

Passed:

```powershell
lua integration/uue4ss/feature-candidates/tests/FocusReadOnlyProbe.Tests.lua
# 19 test groups
luac -p integration/uue4ss/feature-candidates/FocusReadOnlyProbe.lua
luac -p integration/uue4ss/feature-candidates/tests/FocusReadOnlyProbe.Tests.lua
```

Coverage includes exact native names/fields, metadata/thread rejection before player access, possession/default-object rejection, descriptor identity/owner/duplicates/missing names/container bounds, native getter mismatch and unsupported output shapes, omitted found flags, independent ASC mismatch, ownership checks, camera absence, stack/enum bounds, camera and cross-attribute drift, and world/focus/vampire transitions. Source checks reject native setters, gameplay effects, camera push/pop, file/process operations, asset loads and scheduling. A peer review caught return-shape and cross-channel drift evidence gaps; both were fixed and covered by regression tests.

Remaining: supported Computer Use recovery; isolated attested captures outside Focus, during stable Focus, after exit/reentry, and in both character forms on a designated backed-up save. Review actual out-parameter marshaling, active/max range relationships, native effect aggregation and camera stack ownership before any setter pilot. A future mutator needs exact baseline, setter/readback/inverse, compare-before-restore, state-change cleanup, and visible gameplay evidence. Target highlighting additionally needs actual postprocess/material ownership and parameter semantics or an explicitly reviewed optional asset package. No current-turn game test was possible because the coordinator's browser URL-verification interruption halted computer input.

Authoritative local headers: `qa/discovery-current-build-20260906/fresh-metadata/CXXHeaderDump/{Dawnwalker,DogwoodStats,DogwoodCombat,GameplayAbilities,RebelCamera,RebelCamera_enums}.hpp`.
