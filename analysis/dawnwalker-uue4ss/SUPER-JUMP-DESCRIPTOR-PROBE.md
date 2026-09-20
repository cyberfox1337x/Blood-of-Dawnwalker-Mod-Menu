# Super Jump descriptor probe

`cyberfox1337x.function("dawnwalker_super_jump_descriptor_probe_contract")`

## Outcome

Super Jump is not a working gameplay feature yet. The pinned build has an exact authoritative `JumpVelocity` Gameplay Ability System attribute and a plausible loaded descriptor source, but the descriptor has not been passed through the live UE4SS ABI. The only implemented artifact in this phase is a standalone, disabled-by-construction, read-only probe module:

- `probes/DawnwalkerSuperJumpDescriptorReadOnlyProbe.lua`
- `tests/DawnwalkerSuperJumpDescriptorReadOnlyProbe.Tests.lua`

The module is not a mod entrypoint, does not schedule itself, is absent from the bridge capability list, and is absent from every installer and release artifact. Importing it only returns a table with `run` and `format_result`; a future operator must deliberately supply the live dependencies and invoke `run` on the game thread. It calls no setter, applies or removes no Gameplay Effect, writes no property, loads no asset, and never returns mutation authorization.

The active promoted/repaired bridge and its exact advertised capability contract stay untouched. This probe must not be described as a Super Jump toggle or as live proof.

## Pinned build

All addresses and reflected contracts below apply only when `official-build.json:7-18,20-34` matches:

- Steam app `3751260`, build `25014996`, depot manifest `116071877880222957`.
- Unreal Engine `5.5.4`, product `dw1-pc-256181-shipping-patch2-all-CL-256181`.
- `Dawnwalker.exe` length `176,484,216` and SHA-256 `31D6271093358CA859C5D98CD5BF226113285FED41532F3B76881DDA7BE8278A`.

The JMAP runtime image base was `0x7ff79e9d0000`. Native addresses in this note are executable RVAs and must be rejected on any hash mismatch.

## Exact runtime contract

### Player, ASC, and attribute-set identity

- `ADawnwalkerPlayerCharacter` derives from the Dawnwalker humanoid character base: `UHTHeaderDump/Dawnwalker/Public/DawnwalkerPlayerCharacter.h:85-86`.
- `ADawnwalkerPlayerControllerBase.PossessedCharacter` provides a game-specific possession cross-check: `UHTHeaderDump/Dawnwalker/Public/DawnwalkerPlayerControllerBase.h:30-31` and `UE4SS_ObjectDump.txt:67396`.
- The generic reflected possession links are `AController.K2_GetPawn()` at `UHTHeaderDump/Engine/Public/Controller.h:105-106` and `APawn.GetController()` at `UHTHeaderDump/Engine/Public/Pawn.h:168-169`; `IsLocalPlayerController()` is at `Controller.h:117-118`, while the direct controller `Pawn` and pawn `Controller` fields are at `Controller.h:34-35` and `Pawn.h:66-67`.
- The inherited `AbilitySystemComponent` is at `0x918`: `UHTHeaderDump/Dawnwalker/Public/DawnwalkerCharacterBase.h:49-50`, `CXXHeaderDump/Dawnwalker.hpp:1264-1267`, and `UE4SS_ObjectDump.txt:66925-66928`.
- The direct `MovementAttributeSet` is at `0xCC8`: `UHTHeaderDump/Dawnwalker/Public/DawnwalkerPlayerCharacter.h:132-133`, `CXXHeaderDump/Dawnwalker.hpp:1470-1477`, and `UE4SS_ObjectDump.txt:67207-67212`.
- The captured live player, `DWPlayerMovementComponent`, ASC, `PlayerMovementAttributeSet`, and `FallDamageComponent` occur at `UE4SS_ObjectDump.txt:373439,373441,373446,373470,373491`. The corresponding CDO objects at `265250,265252,265257,265281,265303` prove that a global `FindFirstOf` lookup is not an identity contract.
- The independent ASC resolver is `/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:GetAbilitySystemComponent`, reflected at `UE4SS_ObjectDump.txt:35797-35799`.
- Its exact CDO is `/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary`, captured at `UE4SS_ObjectDump.txt:151313` and JMAP `2374737,2376231,2395565`.
- The independent attribute-set resolver is `UAbilitySystemComponent::GetAttributeSet(TSubclassOf<UAttributeSet>)`: `UHTHeaderDump/GameplayAbilities/Public/AbilitySystemComponent.h:351-353`.

The probe therefore starts from an exact live, local `DawnwalkerPlayerControllerBase`; requires `K2_GetPawn`, direct `Pawn`, and `PossessedCharacter` to be the same current `DawnwalkerPlayerCharacter`; and requires the player's getter/direct controller links plus both objects' worlds to agree. It then resolves the direct ASC and attribute set, requires both `GetOuter()` links to equal that same player, and requires the Blueprint-library ASC plus `ASC.GetAttributeSet(PlayerMovementAttributeSet)` to resolve the same exact addresses. It repeats controller, player, world, ASC, attribute-set, source-class, source-CDO, and descriptor identity checks after all read-only calls.

### Authoritative jump value

- `UPlayerMovementAttributeSet.JumpVelocity` is a Blueprint-read-only `FGameplayAttributeData`: `UHTHeaderDump/DogwoodStats/Public/PlayerMovementAttributeSet.h:7-35`, specifically `32-33`.
- Its captured layout is offset `0xA0`: `CXXHeaderDump/DogwoodStats.hpp:893-899`, `UE4SS_ObjectDump.txt:52116-52124`, and JMAP `1700342-1700439` with the field at `1700423-1700431`.
- `UCharacterMovementComponent.JumpZVelocity` is only the downstream movement value at `0x1A8`: `UHTHeaderDump/Engine/Public/CharacterMovementComponent.h:39-40` and JMAP `1878054-1878060`.
- `GetMaxJumpHeight` is reflected at `UHTHeaderDump/Engine/Public/CharacterMovementComponent.h:600-604` and JMAP `1880349-1880374`; its thunk is RVA `0x4F64B70`, and native body RVA `0x4F4E378` derives ballistic height from `JumpZVelocity` and gravity.
- Pinned native initialization RVA `0x172ACCC-0x172ADA1` resolves the player/ASC, constructs the `JumpVelocity` descriptor through helper RVA `0x1CBACE8-0x1CBAD7F`, and subscribes to the ASC attribute-change delegate. The helper binds `PlayerMovementAttributeSet`, `/Script/DogwoodStats`, and `JumpVelocity` from data RVAs `0x77009E2`, `0x7700D60`, and `0x7700CD8`.
- The delegate callback at RVA `0x25C7D2C-0x25C7D49` clamps the new GAS value to at least zero and writes it to movement offsets `0x1A8` and `0x1360`.

Directly writing `JumpZVelocity` is therefore a false semantic alias. It skips the authoritative GAS value and the private synchronized cache, and a later attribute notification can overwrite it.

### Descriptor source and readback

The captured object graph contains the exact loaded class and CDO:

- `/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.GE_WolfBoost_JumpIncrease_C`
- `UE4SS_ObjectDump.txt:230247,248489-248490`

The reflected container contract is `UGameplayEffect.Modifiers: TArray<FGameplayModifierInfo>` at `UHTHeaderDump/GameplayAbilities/Public/GameplayEffect.h:50-51`, whose `FGameplayModifierInfo.Attribute` descriptor is at `GameplayModifierInfo.h:14-15`.

The dump proves that the source objects existed, not what their live `Modifiers` array contained. The probe uses only `StaticFindObject`; it deliberately refuses `StaticLoadObject`, `LoadAsset`, or any other asset-loading fallback. The exact class must return the exact located CDO from `GetCDO()`. It accepts the source only when a bounded container walk finds exactly one total modifier and that modifier's descriptor has:

- `AttributeName == JumpVelocity`
- `AttributeOwner == /Script/DogwoodStats.PlayerMovementAttributeSet`, by both exact path and exact class-object identity
- a positive stable `GetStructAddress()`

The probe supports two read-only UE4SS container shapes: documented `TArray:ForEach` and a bounded one-based indexed fallback. Both reject more than 16 entries, missing entries, iteration exceptions, and any count other than exactly one. This is intentional because a different live nested-container ABI has already demonstrated that `ForEach` cannot be assumed for every reflected container.

The descriptor then must pass both read-only calls:

- `AbilitySystemBlueprintFunctionLibrary.GetDebugStringFromGameplayAttribute`, with both `PlayerMovementAttributeSet` and `JumpVelocity` present.
- `AbilitySystemComponent.GetGameplayAttributeValue`: `UHTHeaderDump/GameplayAbilities/Public/AbilitySystemComponent.h:348-350`, JMAP `2382673-2382782`, thunk RVA `0x16FE1FC`.

The returned finite value must equal `MovementAttributeSet.JumpVelocity.CurrentValue` within a relative `1e-5` tolerance. An explicit `bFound == false` rejects. UE4SS builds that do not surface the out bool may still pass only when the numeric readback agrees exactly; the structured output marks the flag as `not-returned` instead of pretending it was explicit.

`AbilitySystemComponent.GetGameplayEffectCount(exactEffectClass, nil, false)` is also sampled as read-only evidence. It must be a finite non-negative integer, but it is never used as an ownership claim and the probe never applies or removes that effect.

## Structured result

`Probe.run` returns a nested Lua record containing source, descriptor, identity, and base/current/effective readbacks. `Probe.format_result` provides a bounded delimiter-safe summary beginning with:

```text
schema_version=1;probe_id=player:super-jump-descriptor;evidence_class=development-read-only;passed=1;mutation_authorized=0;release_visible=0;stage=read-only-complete
```

Success includes the exact source path, source class/CDO addresses, modifier count and iteration ABI, attribute name/owner and descriptor address, controller/player/world/ASC/attribute-set addresses, resolver/ownership cross-checks, base/current/ASC values, the source-effect count, the explicit-or-not-returned found-flag status, and the debug-string check. Every result carries the same schema/probe/evidence identity plus `mutation_authorized=0` and `release_visible=0`; every failure also emits a bounded stage. A pass proves only that this borrowed descriptor survived read-only UE4SS calls on one stable identity.

## Competing owners, persistence, and rollback

- The game owns the Wolf Boost effect. `UE4SS_ObjectDump.txt:264237` shows a separate `FActiveGameplayEffectHandle JumpIncreaseEffect` in Vampire Sprint. A future feature must never apply, remove, edit, or count this effect as bridge ownership.
- Active Gameplay Effects can change `JumpVelocity.CurrentValue`; the bridge must not poll or rewrite it.
- No mutation occurs in this probe, so there is no runtime rollback state and no intentional save effect. A probe failure likewise requires no restoration.
- A future setter pilot would still be save-risk-unknown. It must use a disposable copied save, capture byte hashes, avoid intentional saving, restore the exact owned GAS base value through a separately reviewed setter, and verify hashes after rollback.
- A future owner must be bound to the exact player/world/ASC/attribute-set/descriptor identities and use compare-before-restore semantics. It must never transfer or reapply state after respawn, possession, world change, form change, or mod unload.

## Offline verification

The dedicated Lua harness statically rejects setter/effect-application/property-write/asset-load/scheduling patterns and verifies:

- the successful exact descriptor and independent resolver path;
- structured evidence and permanent `mutation_authorized=false`;
- both bounded container ABIs;
- wrong attribute name or owner rejection;
- extra-modifier rejection;
- non-local/wrong controller, possession disagreement, controller-link disagreement, world disagreement, and outer mismatch rejection;
- ASC and attribute-set resolver disagreement rejection;
- effective/direct value disagreement and explicit `bFound=false` rejection;
- missing loaded effect and invalid source-effect-count rejection;
- mid-probe controller, player, source-class, or source-CDO identity replacement rejection;
- zero setter/effect mutation calls and zero off-contract asset lookup calls.

Run it offline with:

```powershell
lua analysis/dawnwalker-uue4ss/tests/DawnwalkerSuperJumpDescriptorReadOnlyProbe.Tests.lua analysis/dawnwalker-uue4ss/probes/DawnwalkerSuperJumpDescriptorReadOnlyProbe.lua
```

## Next safe gate

Do not add a bridge capability or a Super Jump UI control yet. After the active bridge repair is stable, a separately authorized operator may perform one bounded live QA run:

1. Copy a disposable save outside the live save directory and record hashes of every save file before launch.
2. Reconfirm the pinned executable byte length and SHA-256, start a normal gameplay world, and make no intentional save.
3. Supply only wrappers for exact-object lookup, current local controller lookup, and current local player lookup; invoke `Probe.run` exactly once on the game thread.
4. Retain the complete `Probe.format_result` line. Accept only `passed=1`, the exact probe/evidence identifiers, `mutation_authorized=0`, `release_visible=0`, all stable identities, exactly one modifier, and matching direct/ASC values.
5. Discard the loaded module and exit without saving. There are no hooks, loops, callbacks, cached handles, or owned gameplay effects to unregister or restore.
6. Re-hash the save directory and reject the trial if any byte changed unexpectedly.

Any missing object, ABI exception, identity drift, extra modifier, descriptor mismatch, invalid count, or readback disagreement is a hard fail and must not be retried through a mutating fallback. Only an exact read-only pass can justify separately designing a one-shot setter/readback/compare-and-restore pilot. It cannot justify release exposure by itself.
