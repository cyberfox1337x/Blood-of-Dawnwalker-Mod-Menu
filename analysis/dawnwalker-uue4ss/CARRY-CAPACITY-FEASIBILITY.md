# Carry-capacity feasibility

`cyberfox1337x.function("dawnwalker_carry_capacity_feasibility")`

## Outcome

`GE_EnableWeightLimitExceed_C` is not an Unlimited Weight effect. Its observed normal-player baseline count is already one, and its only relevant behavior is granting `Inventory.CanExceedWeightLimit`. Native `TryAddItem` uses that tag to permit adding an item after a prospective weight check would otherwise fail. The effect does not change the weight limit, clear `bWeightExceeded`, or suppress encumbrance. It is game-owned baseline state and must never be removed or used as bridge toggle state.

The replacement control remains withdrawn. The GAS carry-capacity path is expressible as a read-only feasibility probe, but it is not authorized for mutation until the probe passes inside the pinned UE4SS runtime and a separate set/readback/rollback pilot proves exact restoration.

## Exact engine contract

- `UInventoryComponent.WeightLimit` is the raw float at `0x158`.
- `UInventoryComponent.GetWeightLimit()` at native `0x142887030` returns raw `WeightLimit` when the raw value is non-positive. For a positive raw value it returns `WeightLimit + UCharDevAttributeSet.CarryWeightCapacityModifier`.
- Internal `HasWeightLimit` at `0x142887188` is exactly `GetWeightLimit() > 0`.
- `TryAddItem` at `0x145D9A764-0x145D9A799` skips its weight rejection when there is no positive effective limit. If a positive limit exists, `CanExceedWeightLimit()` only bypasses that rejection.
- The private recalculation routine at `0x1428883A4` sets `bWeightExceeded` false for an effective limit of exactly zero; otherwise it compares current weight to effective limit. Its changed branch writes `bWeightExceeded` at `0x430` and broadcasts `OnWeightExceededChanged` at `0x398`.
- Inventory registers an ASC change callback for `CarryWeightCapacityModifier` at `0x142885FFA-0x142886030`. The callback at `0x1421BC564` jumps to the private recalculation routine. A correct GAS base-value setter therefore has the derived-state notification path that a raw `WeightLimit` property write lacks.

Static reflection identifies the candidate setter as:

```cpp
UFUNCTION(BlueprintCallable)
static void SetAttributeValue(
    UAbilitySystemComponent* AttributeOwner,
    UPARAM(Ref) FGameplayAttribute& AttributeToSet,
    float AttributeValue);
```

The exact `FGameplayAttribute` descriptor is available without constructing a struct: borrow `Modifiers[1].Attribute` from the loaded CDO for `/Game/_Dawnwalker/Player/CharacterDevelopment/Traits/GameplayEffects/GE_Trait_Shared_StrongBack_Level_1.GE_Trait_Shared_StrongBack_Level_1_C`. The probe must verify `AttributeName == CarryWeightCapacityModifier` and `AttributeOwner == /Script/DogwoodStats.CharDevAttributeSet` before passing it anywhere. Borrowing the descriptor does not authorize applying or modifying any Strong Back effect.

Strong Back levels 1, 2, and 3 are the only loaded effects found modifying this attribute. Their infinite `AddBase` magnitudes are `+30`, `+60`, and `+100`. They are character-progression state, not bridge assets, and must not be applied, removed, stacked, or edited by the menu.

## Read-only probe

[`probes/DawnwalkerCarryCapacityReadOnlyProbe.lua`](probes/DawnwalkerCarryCapacityReadOnlyProbe.lua) performs no gameplay mutation. On the EngineTick game-thread route it:

1. Resolves the exact `SetAttributeValue` UFunction and validates its three reflected parameter types.
2. Resolves the exact Strong Back Level 1 CDO and its single carry-capacity modifier.
3. Validates the descriptor name, owner, and stable struct address.
4. Captures player, world, inventory, ASC, and CharDev attribute-set identities plus raw limit, effective limit, current weight, `bWeightExceeded`, `CanExceedWeightLimit`, `BaseValue`, and `CurrentValue`.
5. Requires `GetWeightLimit()` to match the native formula and requires cached `bWeightExceeded` to match the native derived state.
6. Passes the borrowed descriptor only to `GetDebugStringFromGameplayAttribute` and `GetGameplayAttributeValue`, both read-only calls, and verifies the result against `GameplayAttributeData.CurrentValue`.
7. Reports `mutation_authorized=0` even after a successful read-only run.

The checked-in UE4SS documentation states that struct values are supported as userdata, `TArray:ForEach` yields an Unreal parameter whose `get()` returns the element, and `UScriptStruct` values can be passed through reflected calls. That makes the route representable. It does not substitute for running this exact probe in the pinned game. Until the runtime log reports `result=read-only-pass`, descriptor passing is statically feasible but not live-proven.

## Fail-closed future handler design

The production capability must stay absent while any step below is unproven.

### Query

- Resolve the exact live identity and descriptor every time.
- Return current weight, raw/effective limit, attribute base/current values, and `bWeightExceeded` as telemetry.
- Treat `CanExceedWeightLimit()` as separate game-state telemetry only. Never turn it into Unlimited Weight readback.
- Report enabled only when the current session owns a verified snapshot and the current base/current/effective state matches that owned post-state.

### Enable

1. Reject unless the read-only probe contract passes on the same player, world, inventory, ASC, CharDev attribute set, and descriptor identity.
2. Snapshot exact `BaseValue`, `CurrentValue`, raw `WeightLimit`, effective `GetWeightLimit()`, current weight, and `bWeightExceeded` before calling a setter.
3. Reject non-finite values, a stale cached bool, any existing bridge owner, or a changed object identity.
4. Use only `CombatBlueprintFunctionLibrary.SetAttributeValue` with the validated descriptor. Do not write `GameplayAttributeData`, raw `WeightLimit`, or `bWeightExceeded` directly.
5. Prefer a separately reviewed high finite effective-capacity target for the first mutation pilot. The engine's exact zero-limit sentinel is attractive, but deriving it through a modifier requires exact floating-point cancellation and can drift if another modifier changes.
6. Require post-state `BaseValue`, `CurrentValue`, effective limit, and `bWeightExceeded` to match the predicted values. If any check fails, immediately restore through the same setter and verify the full baseline before returning rejection.
7. Publish ownership only after all postconditions pass.

### Disable, teardown, or identity change

1. Verify the same player, world, inventory, ASC, CharDev attribute set, and descriptor identities.
2. Verify the bridge-owned post-state has not drifted.
3. Restore the exact captured `BaseValue` through `SetAttributeValue`.
4. Verify exact `BaseValue`, expected `CurrentValue`, original effective limit, and original `bWeightExceeded`. The inventory attribute callback must naturally perform the derived-state update and delegate broadcast.
5. Clear ownership only after successful verification. A failure remains explicit and must not fall back to direct property writes, removing effects by class, or removing the pre-existing `GE_EnableWeightLimitExceed_C`.

## Current gate

| Evidence | State |
|---|---|
| Wrong effect semantics disproved | Complete |
| Exact capacity formula and zero-limit sentinel | Complete |
| Exact Blueprint setter signature | Complete |
| Exact Strong Back descriptor source | Complete |
| UE4SS struct-userdata route documented | Complete |
| Borrowed descriptor passed in pinned live runtime | Not run |
| Setter mutation plus full readback | Not run |
| Exact rollback while below baseline limit | Not run |
| Exact rollback while above baseline limit | Not run |
| Production capability | Withdrawn |

No bridge, renderer, installer, release artifact, or live game file is changed by this feasibility phase.
