# Pending feature triage

`cyberfox1337x.function("dawnwalker_pending_feature_triage")`

## Purpose

`feature-contract-matrix.json` inventories 65 pictured controls. Sixteen are advertised by
the `0.3.16-pilot` bridge and eleven of those are pilot live-verified. This note records
offline reflection triage for controls that are still `pending-reflection`, so later work
starts from evidence instead of from the screenshot concept.

Nothing here promotes a capability, changes the bridge, or authorizes a mutation. A control
listed as reachable is reachable *in contract only*. Every one of them still requires the
`liveGate` in `feature-contract-matrix.json`: populated `exactTargetObjectOrClass`,
`exactSetterFunctionPropertyOrHook`, `readbackOrObservablePostcondition`,
`disableOrRollbackPath`, and `offlineTestCase`, followed by a live run on the pinned build.

## Pinned evidence base

All findings below come from the captured dump for the pinned build only and must be
rejected on any identity mismatch:

- `captured-dump/2026-09-02-object-dump/UE4SS_ObjectDump.txt` — loaded object graph.
- `captured-dump/2026-09-02-jmap/Dawnwalker-5.5.4-256181+dw1-pc-256181-shipping-patch2-all-97b7e501.jmap`
- `captured-dump/2026-09-02-uht-incomplete/UHTHeaderDump/` — 17,987 reflected headers.

The object dump proves that an object existed at capture time. It does not prove what a
live container held, and a class default object is not a live instance. Both limits are
load-bearing below.

## The Gameplay Attribute descriptor constraint

Movement and stat values in this build are `FGameplayAttributeData` fields on GAS attribute
sets, declared `BlueprintReadOnly`. The validated write route is:

```cpp
// UHTHeaderDump/DogwoodCombat/Public/CombatBlueprintFunctionLibrary.h:39-40
static void SetAttributeValue(UAbilitySystemComponent* AttributeOwner,
                              UPARAM(Ref) FGameplayAttribute& AttributeToSet,
                              float AttributeValue);
```

That call needs an `FGameplayAttribute` descriptor, which cannot be constructed from Lua.
The only route proven in this project is to *borrow* a descriptor from a loaded
`UGameplayEffect`'s `Modifiers[].Attribute`, as designed in `SUPER-JUMP-DESCRIPTOR-PROBE.md`
and `CARRY-CAPACITY-FEASIBILITY.md`. Whether a borrowable descriptor exists therefore
decides feasibility for every attribute-backed control, and it must be verified per
attribute.

## Triage results

| Control | Exact target found | Setter found | Blocker |
|---|---|---|---|
| Super Jump | Yes | Yes | Live run never performed |
| Speed Multiplier | Yes | Route known | No borrowable descriptor |
| Unlock All Skills | Yes | Yes | No exact per-trait restore |
| Fall Damage | Yes (live) | No | No control surface |
| Time of Day | Class only | Property is writable | No live instance |
| Weather | Yes | No | Notification events only |
| **Add Item** | **Yes** | **Yes + exact inverse** | **Live run only** |
| Kill All Enemies | Yes | Yes | Enumeration unproven; irreversible |

### Super Jump — blocked on a live run only

`UPlayerMovementAttributeSet.JumpVelocity` is the authoritative value, at offset `0xA0` on
the attribute set held at `ADawnwalkerPlayerCharacter` offset `0xCC8`. Writing
`UCharacterMovementComponent.JumpZVelocity` directly is a false semantic alias: the GAS
attribute-change delegate recomputes and overwrites it.

A borrowable descriptor source does exist and is loaded:
`/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.GE_WolfBoost_JumpIncrease_C`
at `UE4SS_ObjectDump.txt:230247,248489-248490`.

This is the furthest-advanced pending control. A complete read-only probe and its offline
harness already exist and pass, and the full live procedure is written down. It needs the
one bounded live QA run in `SUPER-JUMP-DESCRIPTOR-PROBE.md` under "Next safe gate" —
nothing more can be established offline.

### Speed Multiplier — blocked, no borrowable descriptor

`UPlayerMovementAttributeSet` carries the exact intended target, `MaxSpeedModifier`, at
offset `0x80` (`UE4SS_ObjectDump.txt:52122`), alongside `WalkSpeed`, `RunSpeed`,
`SprintSpeed`, `CombatStrafingSpeed`, `CombatBackwardSpeedRatio`, and `GapSqueezeSpeed`.

No loaded gameplay effect modifies it. `MaxSpeedModifier` occurs exactly once in the object
dump, as its own property declaration, and three times in the JMAP, all of which are
declaration sites rather than modifier entries. The `GE_SwiftAdvance_AttackSpeed_Lvl1..4`
effects are attack-speed effects and do not reference it.

This is the same blocker class as Extended Parry Window: the write route is known but the
required payload is absent from the pinned evidence. Do not fabricate a descriptor, and do
not substitute `UCharacterMovementComponent.MaxWalkSpeed` — that repeats the `JumpZVelocity`
alias mistake. This control stays unavailable until a genuine descriptor source is found.

### Unlock All Skills — blocked on rollback, not on reach

This one is unusually well positioned and is worth stating precisely, because its blocker is
safety rather than discovery.

The target is `UCharacterDevelopmentSubsystem` — the *same* game-instance subsystem the
bridge already resolves and has live-verified for `player:trait-points` via
`SetTraitPointsAmount`. Resolution is therefore already proven.

The exact setter exists:

```cpp
// CharacterDevelopmentSubsystem.h:184-185
void UnlockAllTraits(bool bUnlock, bool bUnblock, bool bUnhide, bool bUnblockNextLevelOnly);
```

A genuine per-trait readback surface also exists: the `AllTraits` array
(`CharacterDevelopmentSubsystem.h:116`) plus `GetTraitLevel`, `GetOnceBoughtTraitLevel`,
`GetTraitUnblockedLevel`, `IsTraitHidden`, `IsTraitEquipped`, `IsTraitLevelBlocked`,
`GetSpentTraitPointAmount`, and `GetTraitPointAmount`. A complete pre-mutation snapshot is
constructible.

The blocker is restoration fidelity, and a fuller reading of the header narrows it. A
reconstruct path does exist: `ResetAllTraits()` (`CharacterDevelopmentSubsystem.h:248`)
clears state, and `UnlockTrait(Trait, Level, bTriggerBoughtEvent, bUnlockParent,
bShowNotification)` accepts flags that suppress the bought event and the notification, so a
snapshotted level can be reapplied quietly. `GetAllTraits()` (`436`) supplies public
enumeration and `UTraitAsset.Skill_ID` supplies a stable identity key that survives across
sessions.

That is a best-effort reconstruct, not an exact inverse, and it must not be described as one.
`GetOnceBoughtTraitLevel` (`361`) is a second state dimension with no corresponding setter;
`IsLockedByQuest` (`307`) state and granted-ability rebinding through the subsystem's
`TraitToGrantedAbilityMap` are unverified across a reset; and the subsystem implements
`ISaveGameInterface`, so everything it holds is save-backed.

The design is therefore an explicit one-way, operator-acknowledged action guarded by a
mandatory closed-game save backup, with best-effort restore offered only as a convenience.
See `UNLOCK-ALL-SKILLS-FEASIBILITY.md`.

### Fall Damage — blocked, no control surface

`UFallDamageComponent` is confirmed live on the player, not merely reflected, at
`BP_PlayerCharacter_C_2147480032.FallDamageComponent` (`UE4SS_ObjectDump.txt:373491`), and is
referenced from `ADawnwalkerPlayerCharacter` offset `0xCA0` (`UE4SS_ObjectDump.txt:67207`).

It exposes no control. The whole reflected surface is a private `UFallDamageConfig*`
(`FallDamageComponent`, offset `0xD0`), a private `TWeakObjectPtr<ADawnwalkerCharacterBase>
OwnerCharacter`, and one handler, `OnMovementModeChanged`. There is no enable flag, no
multiplier, and no setter.

Nulling the private config pointer or writing into the shared `UFallDamageConfig` asset are
both rejected: the first is an unreflected direct property write with no defined rollback,
and the second is process-global rather than player-scoped and would leak into unrelated
characters.

### Time of Day — blocked, no live instance

`ADayNightCycle` declares `float SolarTime` as `BlueprintReadWrite, EditAnywhere` at offset
`0x2B8`, which is the only writable time value found.

It has no live instance. The object dump contains exactly three `DayNightCycle` entries: the
`Class` (`67701`), the `SolarTime` property (`67702`), and the class default object
`Default__DayNightCycle` (`161209`). Writing a CDO does not affect the running world, and the
Super Jump research already established that a global lookup landing on a CDO is not an
identity contract.

`ATimeOfDay` does not fill the gap. Its callable surface is cosmetic only — `SetViewDistance`,
`SetFogDistance`, `SetCloudShadowStrength`, `SetCloudShadowOnSurfaceStrength`,
`SetCloudShadowOnAtmosphereStrength`, `SetCastCloudsShadows` — and everything time-related on
it is `BlueprintImplementableEvent` (`OnDayTimeChangedFromSystem`,
`OnDayTimeInterpolationStartedFromSystem`), which are notifications *out of* the system, not
controls into it.

A live capture taken while a day/night cycle actor is actually spawned could change this
result. The current pinned evidence does not support the control.

### Weather — blocked, no control surface

Weather reaches the game as `OnChangedWeatherFromSystem(BlendTime, Clouds, Rain, Storm)` and
`OnChangedWeatherPresetFromSystem(...)`, both `BlueprintImplementableEvent` on `ATimeOfDay`,
plus `EWeatherTypeIntensity` in `DogwoodSystem`. Implementable events cannot be called to
drive the system. The only authoring route found is `QuestNodeChangeWeather`, which is quest
graph content rather than a callable runtime contract. `SkyCreatorPlugin` weather presets are
editor-side settings.

### Add Item — reachable, reversible, blocked on a live run only

This is the strongest remaining candidate and the only pending control found with a genuine
exact inverse.

The target is `UInventoryComponent`, which the bridge **already resolves and has
live-verified** for `player:add-gold`, including the dual-route identity check that requires
the player's `GetInventoryComponent()` and `UInventorySubsystem.GetPlayerInventoryComponent()`
to return the same `UObject` address. Nothing new is needed to reach it.

`FItemHandle` is opaque — the reflected struct exposes no fields
(`DogwoodInventory/Public/ItemHandle.h`) — so it cannot be built in Lua. A factory removes
that blocker:

```cpp
// DogwoodInventory/Public/InventoryBlueprintFunctionLibrary.h:50
static FItemHandle GetItemHandle(const UObject* InWorldContextObject,
                                 const UItemBaseDataAsset* ItemAsset, uint8 ItemLevel);
```

Its CDO `/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary` is loaded
(`UE4SS_ObjectDump.txt:154332`), and 1,650 `ITM_*` assets under
`/Game/_Dawnwalker/Inventory/Items/` are loaded and therefore resolvable with
`StaticFindObject`. `GetHandleForAssetInInventory(ItemAsset)`
(`InventoryComponent.h:195`) is a second, independent handle route usable as a cross-check.

The full contract:

| Field | Route |
|---|---|
| Target | `UInventoryComponent`, dual-route identity, already live-proven |
| Setter | `TryAddItem(handle, quantity, bSkipNewItemCheck)` — `InventoryComponent.h:120` |
| Readback | `GetItemQuantity(handle, bMatchAssetOnly)` — `:192` |
| Inverse | `RemoveItem(handle, quantity)` — `:138` |

All five `liveGate` evidence fields are fillable, and unlike Unlock All Skills the inverse is
exact: add *n*, verify baseline + *n*, remove *n*, verify baseline. Treat `EInventoryResult`
from `TryAddItem` the way Add Gold treats its return — the exact readback is authoritative.

Cautions for the eventual pilot: resolve only by exact asset path and reject an asset that is
not loaded rather than calling `StaticLoadObject`; bound the quantity per command as Add Gold
does; refuse quest items (`ITM_Quest_*`) in a first pilot, since granting or removing one can
desynchronise quest state; and keep the closed-game save backup, because inventory is
save-backed.

### Kill All Enemies — setter proven, enumeration and reversibility are the blockers

`UCombatComponentBase` exposes `UFUNCTION(BlueprintCallable) void Kill()`
(`DogwoodCombat/Public/CombatComponentBase.h:435`). This is the *same* component class the
bridge already drives for Infinite Health through `SetHealthPercent` and `LockHealth`, and
`UNPCCombatComponent : public UCombatComponentBase`
(`DogwoodCombat/Public/NPCCombatComponent.h:31`) inherits it, so the call is available on NPCs.

Two blockers remain, and the second is decisive:

- **Enumeration is unproven.** Reaching every live enemy needs a bounded world actor walk, and
  no such traversal has been proven safe in this project. The existing bridge only ever
  resolves the player and named subsystems. A `FindAllOf`-style sweep would also have to
  exclude the player, companions, quest-critical NPCs, and already-dead actors.
- **There is no inverse.** Death is not reversible in-session, and NPC death is save-backed and
  quest-relevant. Like Unlock All Skills this can only ever be a one-way, backup-gated action,
  and it is considerably more dangerous because killing a quest NPC can render a save
  unfinishable.

Do not pilot this before Add Item. If it is ever attempted, it needs a strict allowlist of
hostile-only actors, not a blanket sweep.

## What offline work cannot settle

Every control above that is not already withdrawn ends at the same place: a live run on the
pinned build. Offline reflection can supply an exact target, setter, and readback, and can
disprove a bad route, but it cannot observe a gameplay postcondition or prove a rollback.
Those require Dawnwalker running with the bridge promoted, plus the closed-game save backup
and restoration discipline already used for Add Gold and Trait Points.

## Recommended order

1. **Add Item** — the best target. Complete contract, an exact inverse, and it reuses the
   already-proven inventory identity route. Pilot it first, non-quest items only.
2. **Super Jump** — offline work is genuinely complete. Run the existing bounded read-only
   probe procedure; it is read-only and applies no effect.
3. **Unlock All Skills** — contract and offline harness are done
   (`UNLOCK-ALL-SKILLS-FEASIBILITY.md`, `npm run test:unlock-all-skills`). It is one-way, so
   it needs an explicit operator decision rather than more reflection.
4. **Speed Multiplier** — reopen only if a descriptor source for `MaxSpeedModifier` is found
   in a future capture.
5. **Time of Day** — reopen only with a capture taken while a `DayNightCycle` actor is live.
6. **Kill All Enemies** — needs a proven bounded actor walk and a hostile-only allowlist
   before it can be considered. Lowest priority of the reachable set.
7. **Fall Damage / Weather** — no route; do not revisit without new reflected surface.
