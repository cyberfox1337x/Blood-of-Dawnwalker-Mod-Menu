# Unlock All Skills feasibility

`cyberfox1337x.function("dawnwalker_unlock_all_skills_feasibility")`

## Outcome

Unlock All Skills is **reachable in contract but is not a reversible control**. It is designed
here as an explicit one-way, operator-acknowledged action guarded by a mandatory closed-game
save backup, with a best-effort reconstruct offered only as a convenience and never as a
rollback guarantee.

Nothing in this phase is implemented in the bridge. `player:unlock-all-skills` is **not** an
advertised capability, is absent from `CONTROL_CAPABILITIES`, and is absent from every
installer and release artifact. This document is a contract and a test design. Promotion
requires the `liveGate` in `feature-contract-matrix.json` plus a live run on the pinned build.

## Why this one is different

Every other mutating control the bridge advertises restores an exact captured baseline and
verifies it by readback. This one cannot. `UCharacterDevelopmentSubsystem` implements
`ISaveGameInterface`, so its state is save-backed — already demonstrated by the Trait Points
persistence run, where a `0 -> 1` change survived a normal save and reload. A trait unlock is
therefore a durable change to real progression, not a session-local toggle.

The honest framing is a destructive operation with a backup, in the same spirit as the
patcher rules: back up first, act deliberately, verify, and keep a recovery path that does not
depend on the mutation being undoable.

## Pinned build

Applies only when `official-build.json` still matches: Steam app `3751260`, build `25014996`,
`Dawnwalker.exe` length `176,484,216`, SHA-256
`31D6271093358CA859C5D98CD5BF226113285FED41532F3B76881DDA7BE8278A`. Reject on any mismatch.

## Exact runtime contract

### Target

`UCharacterDevelopmentSubsystem`, a `UGameInstanceSubsystem`
(`UHTHeaderDump/DogwoodCharacterDevelopment/Public/CharacterDevelopmentSubsystem.h:46`).

This is the **same live object** the bridge already resolves and has live-verified for
`player:trait-points` through `SetTraitPointsAmount`
(`CharacterDevelopmentSubsystem.h:217-218`, `main.lua:468-480`). Resolution and identity
checking are therefore already proven in this codebase and must be reused unchanged rather
than reimplemented.

### Enumeration and identity

- `TArray<UTraitAsset*> GetAllTraits() const` — `CharacterDevelopmentSubsystem.h:436`.
- `UTraitAsset.Skill_ID` (`FName`) — `TraitAsset.h:19-20`. This is the snapshot key. Do **not**
  key the snapshot on `UObject` addresses; they do not survive a session change, and the whole
  point of the snapshot is to outlive one.
- `UTraitAsset.MaxTraitLevel` — `TraitAsset.h:67-68`, used to bound per-trait level checks.
- `UTraitAsset.ParentSkills` (`TArray<FName>`) — `TraitAsset.h:22-23`, relevant because
  `UnlockTrait` takes a `bUnlockParent` flag.

The enumeration walk is bounded. Reject a `GetAllTraits` result that is not a table, that
exceeds a hard cap of 4096 entries, that contains a nil or non-`UTraitAsset` entry, or that
contains a duplicate or empty `Skill_ID`. The same two container ABI shapes proven necessary
for the Quest Journal `TArray` and the difficulty `TMap` apply here and must both be
supported, with any incomplete iteration treated as a hard rejection.

### Snapshot fields

Per trait, keyed by `Skill_ID`:

| Field | Source |
|---|---|
| `level` | `GetTraitLevel(Trait)` — `:340` |
| `onceBoughtLevel` | `GetOnceBoughtTraitLevel(Trait)` — `:361` |
| `unblockedLevel` | `GetTraitUnblockedLevel(Skill_ID)` — `:334` |
| `hidden` | `IsTraitHidden(Trait)` — `:295` |
| `equipped` | `IsTraitEquipped(Trait)` — `:298` |
| `questLocked` | `IsLockedByQuest(Trait, level)` — `:307` |

Global:

| Field | Source |
|---|---|
| `traitPoints` | `GetTraitPointAmount()` — `:337` |
| `spentTraitPoints` | `GetSpentTraitPointAmount()` — `:352` |

The snapshot must be written to disk **before** the mutation, next to the save backup, and
must include the bridge version, boot identity, subsystem address, and a SHA-256 of its own
serialized body. A snapshot that cannot be persisted is a hard abort — the mutation must not
proceed on an in-memory-only record.

### Action

```cpp
// CharacterDevelopmentSubsystem.h:184-185
void UnlockAllTraits(bool bUnlock, bool bUnblock, bool bUnhide, bool bUnblockNextLevelOnly);
```

Invoke as `UnlockAllTraits(true, true, true, false)`.

### Postcondition

Re-enumerate and require, for every trait: `GetTraitLevel(Trait) >= snapshot.level` and
`IsTraitHidden(Trait) == false`. At least one trait must show a strict increase, otherwise the
call did nothing and the result is reported as no-op rather than success. Every `Skill_ID`
present in the snapshot must still be present after the call; a changed trait roster
invalidates the run.

## Best-effort reconstruct — explicitly not a rollback

Offered as a convenience only. The operator must be told, in the UI and in the command result,
that the authoritative recovery path is the closed-game save backup.

1. `ResetAllTraits()` — `CharacterDevelopmentSubsystem.h:248`.
2. For each snapshot entry with `level > 0`, in ascending `Tier` then ascending `level` order:
   `UnlockTrait(Trait, level, /*bTriggerBoughtEvent=*/false, /*bUnlockParent=*/false,
   /*bShowNotification=*/false)` — `:178-179`. The two false flags exist precisely to suppress
   the bought event and the notification, so the reconstruct stays quiet.
3. `SetTraitPointsAmount(snapshot.traitPoints)` — `:217-218`, the already-live-verified setter.
4. For each snapshot entry with `equipped == true`:
   `SetTraitEquipped(Trait, true, /*bForce=*/true, SlotId)` — `:220-221`.
5. Verify per trait that `GetTraitLevel` equals `snapshot.level` and that
   `GetTraitPointAmount()` equals `snapshot.traitPoints`. Report per-trait mismatches
   individually; do not collapse them into a single boolean.

### Known fidelity gaps

These are why this is not a rollback, and they must be stated in the result rather than hidden:

- **`onceBoughtLevel` has no setter.** `GetOnceBoughtTraitLevel` is a distinct state dimension
  from `GetTraitLevel` with no corresponding write route anywhere in the reflected surface. It
  cannot be restored.
- **`ResetAllTraits()` semantics are unverified.** Whether it refunds points, clears
  `onceBought` history, fires `OnTraitsReset` consumers, or revokes granted abilities is not
  established by static evidence.
- **Granted abilities.** The subsystem holds `TraitToGrantedAbilityMap` and
  `AbilityToTraitMap` (`:122-125`) and a `PlayerASC` weak pointer. Whether a reset-then-relock
  cycle rebinds Gameplay Abilities identically is unverified.
- **Quest-locked traits.** `IsLockedByQuest` state may not survive a reset, and re-unlocking a
  quest-locked trait could desynchronise quest state.
- **Slot IDs.** `IsTraitEquipped` returns a boolean; the reflected surface does not expose a
  complete per-trait slot readback, so step 4 cannot guarantee the original slot layout.

## Mandatory operator protocol

1. Close Dawnwalker normally. Confirm it is not running.
2. Copy the entire save tree to `qa/save-backups/unlock-all-skills-pretest-<UTC>` and record
   relative path, length, and SHA-256 for every file. This is the same discipline the Add Gold
   and Trait Points persistence runs used, where the original trees were restored at 61/61 and
   76/76 files with zero differences.
3. Reconfirm the pinned executable length and SHA-256.
4. Launch offline, reach a playable pawn, take the snapshot, and persist it.
5. Perform exactly one `UnlockAllTraits(true, true, true, false)` call and capture the
   postcondition.
6. Exit normally. Re-hash the save tree and record what changed.
7. Recovery, if wanted, is restoring the backup tree with the game closed — not the
   reconstruct.

## Offline verification

A Lua harness in the style of `DawnwalkerDifficultyPilot.Tests.lua` and
`DawnwalkerAddGoldPilot.Tests.lua` must cover, against a fake subsystem:

- bounded enumeration, the 4096 cap, and both container ABI shapes;
- rejection of nil entries, non-asset entries, duplicate and empty `Skill_ID`;
- rejection when the snapshot cannot be persisted;
- rejection on subsystem, player, or world identity change mid-operation;
- the no-op report when no trait level increases;
- rejection when a `Skill_ID` disappears between snapshot and postcondition;
- reconstruct ordering by `Tier` then `level`, with the suppression flags asserted false;
- per-trait mismatch reporting rather than a collapsed boolean;
- an assertion that `onceBoughtLevel` is reported as unrestorable rather than silently ignored;
- zero calls to `TryBuyTrait`, `UnlockRandomTrait`, `ReceiveTraitPoints`, or `SpendTraitPoints`.

`TryBuyTrait` and `SpendTraitPoints` are explicitly forbidden in this path: they consume trait
points and would compound the damage rather than reproduce a baseline.

## Gate

| Evidence | State |
|---|---|
| Exact subsystem identity, already live-proven | Complete |
| Exact enumeration and stable identity key | Complete |
| Exact snapshot readback surface | Complete |
| Exact action signature | Complete |
| Reconstruct route with side-effect suppression | Complete |
| Exact inverse for `onceBoughtLevel` | **Does not exist** |
| `ResetAllTraits` live semantics | Not run |
| Live snapshot, action, and postcondition | Not run |
| Save-tree delta measured | Not run |
| Production capability | Not authorized |
