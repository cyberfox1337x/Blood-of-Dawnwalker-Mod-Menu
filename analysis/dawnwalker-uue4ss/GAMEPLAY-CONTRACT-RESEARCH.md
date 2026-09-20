<!-- cyberfox1337x.function("dawnwalker-gameplay-contract-research") -->

# Dawnwalker gameplay-contract research

Research date: 2026-09-02  
Pinned game contract: Steam app `3751260`, build `25014996`, Unreal Engine `5.5.4`

## Why normal sprint did not lower stamina

The pinned build's `DogwoodStatsSettings` class default object sets:

- `SprintBaseCostPerSecond = 0.0`
- `CombatSprintBaseCostPerSecond = 30.0`
- `AstralBoostBaseCostPerSecond = 20.0`

Evidence: the captured JMap at lines `1691333-1691339` and the captured UHT default constructor `DogwoodStats/Private/DogwoodStatsSettings.cpp:9-11`.

Normal out-of-combat sprint is therefore an invalid Unlimited Stamina test. The game has separate open-world, combat, fast-travel, human, vampire, and astral sprint paths. Its `GE_SprintCost` effect evaluates every `0.2` seconds and selects conditional stamina-consumption effects according to the current state and form. Passive regeneration can also hide a short drain if sampling is slow.

The official gameplay description independently says attacking armor and blocking swings consume significant stamina. Official feature material also describes distinct day and night gameplay loops and the adaptive omniattack/omniblock system:

- [Official gameplay reveal recap](https://en.bandainamcoent.eu/dawnwalker/news/the-blood-of-dawnwalker-gameplay-reveal-recap)
- [Official features overview](https://en.bandainamcoent.eu/dawnwalker/news/explore-the-blood-of-dawnwalkers-features-ahead-of-release-new-gameplay-trailer)
- [Official skills and power overview](https://en.bandainamcoent.eu/dawnwalker/news/community-bulletin-board-11-skills-power)

## Intended stamina control contract

`UCombatComponentBase` exposes the strongest reflected native path:

- `SetStaminaPercent(float)`
- `LockStamina()`
- `UnlockStamina()`
- `GetStaminaPercentage()`
- `HasFullStamina()`
- `HasLostAllStamina()`
- `IsFatigued()`

These are native, public, Blueprint-callable functions in the JMap. The game also ships `UQuestNodeControlCharacterStamina` with explicit `bModifyStaminaLock` and `bSetStaminaLocked` fields, confirming that stamina locking is a first-class game operation.

The current bridge follows the intended route: capture the exact percentage, set it to `1.0`, lock it, verify the readback, then unlock and restore the captured percentage on final owner release. Direct attribute writes or manual gameplay-effect injection would be less safe.

The `GE_StaminaOverride` asset is an infinite override of `CharacterBaseAttributeSet.Stamina` using the set-by-caller tag `Effect.OverrideStamina`. Static reflection does not prove that `LockStamina()` uses this asset internally, so gameplay endurance remains a live test requirement.

## Combat resource model

The reflected player attribute set includes Stamina, MaxStamina, PermanentStaminaDamage, Exhaustion, StaminaBase, StaminaRegen, cost multipliers, and ExhaustionConversionRate. The game's internal term is `Exhaustion`, not `Exertion`.

Attack, parry, and omniblock effects modify Exhaustion; combat restoration modifies Stamina. Combat dodge has a reflected default cost of `20.0` and is the safest repeatable stimulus found so far.

## Unlimited Stamina endurance protocol

Use a disposable offline save with a verified backup. Keep every other bridge capability disabled.

1. Require a responsive process, unchanged bridge boot ID, fresh heartbeat, and an empty active set.
2. Query Player Info and record the exact baseline.
3. With Unlimited Stamina off, perform three identical combat dodges while polling sequentially every `150-250 ms`. Accept the stimulus only if stamina drops measurably, preferably by at least five percentage points. If dodge is unavailable, use exactly five seconds of sprint while definitely in combat.
4. Let stamina return to the pre-enable baseline.
5. Enable only `player:unlimited-stamina`; require an accepted response and a later heartbeat whose active set contains exactly that capability.
6. Repeat the identical action count or duration. Require every readback to remain at least `99.9%`, the action to remain usable, no fatigue behavior, fresh heartbeats, and a responsive process.
7. Disable in cleanup. Require a later heartbeat with an empty active set and exact baseline restoration within `0.25%`.
8. Repeat one calibrated action with the feature off and require stamina to drain again. This final step proves that `UnlockStamina()` released the native lock.

Stop immediately on a rejected response, stale heartbeat, changed boot ID, identity change, invalid readback, or process failure. Issue only the matching `false` cleanup command until the active set is empty.

## Implications for the menu

- Player and Combat controls must be state-aware. A normal traversal observation cannot stand in for combat proof.
- Day/night is a gameplay-mode boundary: human Witchcraft and vampire abilities are distinct, although official material confirms that XP and skill points are shared across the skill trees.
- The screenshot's Humanity, Red Essence, and durability concepts still lack an exact writable pinned-build contract. They must remain unavailable or be replaced with proven Dawnwalker concepts rather than simulated.
- Horse framework and quest strings exist in the build, but no exact loaded concrete spawnable class and safe destroy pair has been captured. Boat and companion controls likewise remain blocked until both spawn and rollback assets are proven.

## Read-only Quest Journal contract

The pinned UHT dump provides a complete display-only route without guessing quest identifiers or writing save-backed state:

- `ADawnwalkerGameStateBase.QuestJournal` resolves the live `UJournal`.
- `UJournal.GetOpenedQuests(TArray<UQuest*>& OutQuests)` provides open quests through an exact UE4SS out table. In pinned UE4SS, an `FArrayProperty` out parameter fills the passed table itself at one-based numeric keys rather than assigning a named `OutQuests` field. `GetTrackedQuest()` identifies the currently tracked quest without changing it.
- `UQuest.Title`, `Objectives`, and `State` provide the quest display record.
- `FObjective.Text`, `State`, `CurrentCount`, `MaxCount`, and `bIsOptional` provide bounded objective display data.

The `0.3.7-pilot` source exposes this as `quests:journal-readback` only. It rejects any non-empty command value, calls no `TrackQuest`, `TrackQuestObjective`, completion, objective-update, delegate, or save function, and serializes percent-encoded free text. Output is capped at six open quests, three objectives per quest, 240 encoded bytes per text field, and 8192 bytes total. A zero-open-quest Journal is a valid snapshot, distinct from a missing or invalid Journal. Reversible `0.3.4-pilot`, `0.3.5-pilot`, and `0.3.6-pilot` attempts rejected safely without mutation while exposing three wrapper assumptions. The exact pinned route is `UJournal:GetOpenedQuests(out)` with `out[1..#out]` populated directly. The bridge reads only `out[1]` through `out[min(#out, 6)]` and only `Objectives[1]` through `Objectives[min(#Objectives, 3)]`. Every invalid length, missing entry, invalid UObject, or invalid display field rejects the complete Quest snapshot.

`DawnwalkerQuestJournalPilot.Tests.lua` proves the exact object path, direct TArray out-table ABI, tracked state, UTF-8/delimiter encoding, all bounds, mutation rejection, and the empty-Journal case with a live-shaped `UJournal` that has `GetOpenedQuests(out)` but no `OpenedQuests` property. The fixture writes only one-based numeric entries into `out`; it has no named `OutQuests` field, and neither quest nor objective array has `ForEach`. TypeScript scaffold, parser, failure-isolation, and renderer tests cover the exact reflected call, strict schema validation, preservation of unrelated readbacks when Quest rejects, and the isolated Quests page. Corrected `0.3.7-pilot` passed a live pinned-build read on boot `1788414524-513788`: two quests were returned, `Withering Away` was tracked, six unrelated queries remained valid, and the active set remained empty. The immutable automated artifact is SHA-256 `B4123167CA1CE198A92377C08648F795F5D2398AD8C902E8D835E875AF3D4FF4`; the visible UI/F10 evidence artifact is SHA-256 `E679C347A0F1D6F59EAB37A5613D66D85983720E1D34FE0E60E6F5D7A1FCBC25`. Both are pilot-only evidence, not production proof.

## Add Gold contract

The pinned build exposes one exact currency route for the pictured Gold control. `/Script/DogwoodInventory.ECurrencyType::Coin` is enum value `0`. The live player's `GetInventoryComponent()` and the game-instance `UInventorySubsystem.GetPlayerInventoryComponent()` must resolve the same `UInventoryComponent` address before any query or mutation. `GetCurrencyQuantity(Coin)` is the authoritative signed-int32 readback. `AddCurrency(Coin, signed delta)` performs the mutation, but pinned native inspection shows its reflected `EInventoryResult` return is unreliable and therefore must be ignored.

The Add Gold contract introduced in `0.3.8-pilot` and retained unchanged by current `0.3.16-pilot` accepts an empty value as a read-only query and a nonzero signed integer whose absolute magnitude is at most `10,000`. It rejects a negative result, positive signed-int32 overflow, unstable player/world/component identity, fractional values, and non-finite values. Success requires readback exactly equal to baseline plus the requested delta. After a mismatched readback, it may issue an inverse only for the exact observed bounded delta, in the requested direction and segment, while every identity remains unchanged; exact baseline restoration is mandatory. Otherwise it fails closed and directs the operator to the save fallback. The renderer exposes only positive amounts from 1 through 10,000. Historical `0.3.8` passed an automated in-memory `0 -> 1 -> 0` exact-readback cycle on boot `1788416226-130670`; `qa/pilot-evidence/dawnwalker-live-pilot-qa-20260903T062333Z.json` is pinned at SHA-256 `71DF3D8B64C2C34E2EE82AE74557E904F3854B0EEDD2614E55AD98CBD36B919A`. The persistence/UI artifact `qa/pilot-evidence/dawnwalker-add-gold-live-persistence-20260903T064209Z.json` is pinned at SHA-256 `21AE16140B8B05C29DE252169B724844C857351777BB67BA6DCE3FB626056F49`: Computer-use exercised `0 -> 10000` through the visible UI and exact `10000 -> 0` restoration through the bridge; a separate `+1` survived a normal save/reload, the `-1` inverse restored baseline `0`, and baseline survived a second save/reload across three boot identities.

`DawnwalkerAddGoldPilot.Tests.lua` covers query, signed restoration, component agreement, command/int32 boundaries, the unreliable-return rule, partial-delta inverse, and fail-closed identity and range cases. The completed live persistence control used the closed-game backup `qa/save-backups/gold-pretest-20260903T055722Z`, ended with an empty active set, and never called the private `TryQuicksave` function. After the third-boot baseline readback, the post-test tree was retained at `qa/save-posttests/gold-persistence-posttest-20260903T064209Z`; the original tree was restored while the game was closed and all 61 files matched relative path, length, and SHA-256 with zero differences. Global F9 is bound to the same renderer action with a fixed positive delta of `10,000`; the existing interaction-eligibility, exact bridge identity, capability-advertisement, in-flight, main-process authorization, and exact-readback gates all still apply. Promoted `0.3.10-pilot` supplied that binding's own live run: `qa/pilot-evidence/dawnwalker-0.3.10-hotkeys-live-20260903T070604Z.json` is pinned at SHA-256 `38616500F68E74E5DC9689BF516435152654A90D5EE450FB347B28E3E2E4D9E2` and records an exact `0 -> 10000` menu readback triggered while Dawnwalker held focus, a helper inverse back to `0`, a normal exit, and 61/61 original save files restored at zero path, length, or SHA-256 differences. Current `0.3.16-pilot` retains the binding unchanged. The evidence remains pilot-only.

## Combat difficulty two-axis contract

The pinned build exposes two independent difficulty axes on one subsystem. The
live `/Script/DogwoodCombat.CombatSubsystem` must be resolved from the playable
player's current `UWorld`, never from a CDO or a global search, together with its
assigned `/Script/DogwoodStats.DifficultyConfig` and the non-CDO
`URebelGameUserSettings` singleton. `SetRPGDifficulty(ERebelGameDifficulty)` and
`SetActionDifficulty(ERebelGameDifficulty)` are the exact setters. Each accepts
only `Story=0`, `Normal=1`, `Immersive=2`, or `Nightmare=3`, and only after the
matching `DifficultyConfig.RPGDifficulties` or
`DifficultyConfig.ActionDifficulties` map reports that it contains the requested
value; `MAX=4` and every other value are rejected before any setter runs.

Readback is deliberately redundant. The reflected `RPGDifficultyLevel` and
`ActionDifficultyLevel` properties must equal the requested enum,
`GetActionDifficultyLevel()` must agree with its property, and
`GetRPGDifficultySettings()` and `GetActionDifficultySettings()` must match every
semantic field of the assigned config-map entry. Setting one axis must leave the
other axis, both `URebelGameUserSettings` owner values (settings `69` and `70`),
every object identity, and all four config fingerprints unchanged.

Fingerprinting the Action difficulty entry is what made this contract hard. The
entry contains a `ParryWindowMultipliers` map, and versions `0.3.11-pilot`
through `0.3.15-pilot` each failed their live read-only suite because that
nested container could not be walked through the live UE4SS ABI: four of the five
reported `attempt to call a nil value` and `0.3.14` reported `a function
requiring userdata as param #1`. Every one of those runs rejected the
`combat:rpg-difficulty` query and mutated nothing. `0.3.16-pilot` resolves it by
supporting the nil-return TMap shape alongside `pairs` and `ForEach`, bounding
the walk at 32 entries, and treating an incomplete or unsupported iteration as a
hard rejection rather than a partial fingerprint. This repeats the lesson already
recorded for the Quest Journal `TArray` out-parameter: a reflected container's
iteration ABI cannot be assumed, and only a bounded walk that fails closed is
safe.

Rollback uses one shared two-axis snapshot holding the player, world, subsystem,
config, and settings objects and addresses, both baseline enum levels, both owner
values, and stable fingerprints for all four config entries. The bridge refuses
to capture at all when the live axes are already owned by another runtime
override. Restoration re-reads live state first and calls no setter when the
binding left its original world or when a config fingerprint changed. If the
settings owner changed, the bridge never overwrites it and relinquishes ownership
only when the live subsystem already matches the new owner values. The two axes
are then restored independently, each clearing its own active entry only after
its exact level and fingerprint postcondition holds; an unresolved partial
restore is retained and blocks further difficulty mutation until an exact
same-world retry succeeds.

`DawnwalkerDifficultyPilot.Tests.lua` covers query, enum bounds, axis
independence, same-world identity, config and owner noninterference, exact
restoration, owner reclaim, fingerprint-mismatch rollback, world-drift
rejection, and retained partial-rollback retry. The live proof is
`qa/pilot-evidence/dawnwalker-live-pilot-qa-20260903T082038Z.json`, pinned at
SHA-256 `91739704BDDFED2DB94BC933828BCFF3BBD7D58B6780ED21809AB07D1139006D`: both
axes independently completed `Story -> Normal -> Story` with mutation
verification, exact config and owner readback, and an empty final active set.
That is pilot evidence only; both controls stay release-locked.

## Extended Parry Window feasibility

The pictured Perfect Parry concept has been narrowed to the more accurate label **Extended Parry Window**, but it is not a capability. The pinned build contains the exact infinite gameplay effect class `/Game/_Dawnwalker/Stats/CustomItemModifiers/GE_ParryWindowMultiplier.GE_ParryWindowMultiplier_C` and its class default object. The effect has one `AddBase` modifier for `/Script/DogwoodStats.CharDevAttributeSet.ParryWindowMultiplier`; its magnitude is `SetByCaller` under the exact gameplay tag `Stats.CustomModifier`, and it has no stacking policy. The class/CDO are present in the captured object dump at lines `181061-181062` and the full effect definition is in the captured JMAP at lines `771654-772211`.

If an authoritative magnitude is later recovered, the rest of the reflected, player-scoped chain is exact. Resolve the player's inherited `AbilitySystemComponent` and independently call `/Script/DogwoodUtil.DogwoodBlueprintFunctionLibrary:GetPlayerAbilitySystemComponent(player)`, requiring the same UObject address. Resolve the player's `CharDevAttributeSet` and its `ParryWindowMultiplier` attribute. Create the effect context with `UAbilitySystemComponent:MakeEffectContext`, create a level-1 spec with `MakeOutgoingSpec`, resolve `Stats.CustomModifier` through `GetGameplayTagFromString`, assign the magnitude through `AbilitySystemBlueprintLibrary:AssignTagSetByCallerMagnitude`, and apply it with `BP_ApplyGameplayEffectSpecToSelf`. Retain the returned `FActiveGameplayEffectHandle`; rollback must use only `RemoveActiveGameplayEffect(handle, -1)`, never source-effect removal. Before and after apply/remove, require stable player/world/ASC/attribute-set identity, exact `GetGameplayEffectCount(effectClass, nil, false)` deltas, `GetGameplayAttributeValue` success, and agreement with `CharDevAttributeSet.ParryWindowMultiplier.CurrentValue`. The reflected callable evidence is in the JMAP at `1761739-1761812`, `2376876-2376931`, `2381709-2381745`, `2382673-2382782`, `2383188-2383272`, and `2384152-2384200`; the attribute is declared in `DogwoodStats/Public/CharDevAttributeSet.h:102`.

The missing piece is decisive: the gameplay effect intentionally contains no literal magnitude, and the pinned JMAP has no external asset reference that proves what value a caller supplies for this effect. `ParryWindowMultiplier` has a baseline of `1.0`, while `CombatConfig.VampireParryWindowMultiplier` is separately initialized to `1.2`; neither value establishes the `Stats.CustomModifier` payload for `GE_ParryWindowMultiplier_C`. A guessed `+0.2`, `+1.0`, or other magnitude could produce a different mechanic than advertised and would lack a trustworthy rollback postcondition. Until an exact caller or other authoritative asset pins that value, Extended Parry Window stays unavailable, absent from bridge capabilities, and hidden from the interactive release UI. No version bump or live pilot is warranted for Parry from this evidence alone.

## Evidence locations

- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/DogwoodCombat.hpp:1187-1249`
- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/DogwoodStats.hpp:349-451`
- Captured JMap: stamina native functions at `1585909-1585934`, `1586457-1586472`, `1587755-1587780`, and `1587922-1587937`
- Captured JMap: sprint settings at `1691333-1691339`
- Captured JMap: `GE_SprintCost` at `675615`, `675726-675770`
- Captured JMap: `GE_StaminaOverride` at `782563-782808`
- Captured JMap: combat dodge cost at `1599176-1599223`
- `integration/uue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua:273-284,332-425,603-617`
- Combat difficulty handlers, fingerprinting, and shared rollback: `integration/uue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua:446-627,628-838,1104-1310`
- Captured JMap: difficulty subsystem, enum, config, and user settings at `1593892-1594650`, `1696923-1697219`, and `3239600-3243808`
- `captured-dump/2026-09-02-uht-incomplete/UHTHeaderDump/Dawnwalker/Public/DawnwalkerGameStateBase.h`
- `captured-dump/2026-09-02-uht-incomplete/UHTHeaderDump/Quest/Public/Journal.h`
- `captured-dump/2026-09-02-uht-incomplete/UHTHeaderDump/Quest/Public/Quest.h`
- `captured-dump/2026-09-02-uht-incomplete/UHTHeaderDump/Quest/Public/Objective.h`
- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/GE_ParryWindowMultiplier.hpp`
- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/DogwoodStats.hpp:267`
- `captured-dump/2026-09-02-uht-incomplete/UHTHeaderDump/DogwoodUtil/Public/DogwoodBlueprintFunctionLibrary.h:80,83`
- `captured-dump/2026-09-02-uht-incomplete/UHTHeaderDump/DogwoodStats/Public/CharDevAttributeSet.h:102`
- Captured JMap: `GE_ParryWindowMultiplier_C` at `771654-772211`; ASC/tag resolution and effect apply/readback/remove functions at `1761739-1761812`, `2376876-2376931`, `2381709-2381745`, `2382673-2382782`, `2383188-2383272`, and `2384152-2384200`
- Captured object dump: `GE_ParryWindowMultiplier_C` class/CDO at `181061-181062`
