# Blood of Dawnwalker — Mod Menu Feature List

**105 feature and panel ideas: 54 function-backed candidates, 16 additional gameplay/tool ideas, 5 live-data panels, and 30 menu workflow extensions.** Some extend the same underlying feature rather than representing independent game systems. This is a development list for the existing offline single-player menu. It uses the captured classes, functions, properties, and player readbacks in this folder. Creating this document did not implement or enable gameplay controls.

**Build scope:** Steam build **25129649 / CL257186**, Unreal Engine **5.5.4**. Function declarations come from the preserved build-matched capture. A function name establishes a development lead; its actual behavior, valid arguments, and restoration still need feature-specific testing.

## What the status labels mean

| Label | Meaning |
| --- | --- |
| **Existing · limited proof** | Existing code and bounded same-build runtime evidence are available. The remaining limitations are stated below; this is not a release guarantee. |
| **Candidate** | A captured function supports investigating the feature. No working implementation is claimed here. |
| **Historical pilot** | Earlier implementation/test evidence exists, but it must be checked again against this build. |
| **Research / blocked** | Required behavior, IDs, inverse, or runtime proof is missing, or a previous route failed. |
| **Readback available** | The recorded player snapshot contains this reading; a fresh session read is needed to show the current value. |

## Best order to build

1. **Finish the player essentials:** health, stamina, blood, speed, and No Clip. Reuse their existing controls and complete real gameplay and restoration checks.
2. **Add useful information panels:** resource percentages, position, game speed, connection/session freshness, then verified inventory and progression readers.
3. **Add everyday inventory tools:** currency, valid-item picker, equipment/loadout changes, quickslots, storage transfers, and crafting helpers.
4. **Expand player progression and abilities:** trait points, level actions, focus cooldowns, mutation controls, and form policy.
5. **Build world and camera tools:** difficulty, clock, weather, camera controls, and saved-location travel with destination checks.
6. **Keep NPC, encounter, quest, and advanced movement work as later investigations:** these need more state/side-effect discovery before dependable controls.

This order is a practical development priority, not an assertion that candidate features are easy or already safe to enable.

## Player — Health, stamina, and blood

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 1 | Refill health | Restore the player's health on demand. | `SetHealthPercent` | **Existing · limited proof:** bounded apply/readback/restore; combat and death paths need testing. |
| 2 | God Mode / lock health | Keep the health resource from decreasing. | `LockHealth` | **Existing · limited proof:** overlapping-control cycles; universal damage immunity is unproved. |
| 3 | Refill stamina | Restore stamina on demand. | `SetStaminaPercent` | **Existing · limited proof:** core control/readback infrastructure; test actual stamina-consuming actions. |
| 4 | No stamina drain | Lock the stamina resource during supported actions. | `LockStamina` | **Existing · limited proof:** combined ownership/cleanup cycles; sustained sprint/combat needs testing. |
| 5 | Refill blood | Restore blood energy on demand. | `SetBloodPercent` | **Existing · limited proof:** bounded resource changes and restoration. |
| 6 | Infinite blood energy | Lock the blood resource. | `LockBlood` | **Existing · limited proof:** overlapping-control cycles; ability/form transitions need testing. |
| 7 | Repair blood segments | Heal and replenish blood segments. | `HealAndReplenishAllSegments` | **Candidate:** inspect permanent damage and segment postconditions. |
| 8 | Heal wounds | Request wound recovery. | `HealWounds` | **Candidate:** authoritative wound-state readback is missing from the recipe. |

The first six share existing [CorePlayerControl.lua](../integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/CorePlayerControl.lua). Toggle ownership matters: turning off one overlapping control must not incorrectly clear another control's lock.

## Player — Forms, focus, and abilities

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 9 | Form policy selector | Select the game's supported human/vampire form policy. | `SetFormSelectionPolicy` | **Candidate:** validate policy enum, unlock requirements, and day/night transitions. |
| 10 | Refill focus charges | Override focus charge slots. | `SetSlotsChargedOverride` | **Candidate:** establish charge count, lifetime, and a reliable charge-state getter. |
| 11 | Reset focus cooldowns | Request a focus cooldown reset. | `ResetCooldowns` | **Candidate:** no recipe getter; measure real cooldown behavior. |
| 12 | Reduce focus cooldowns | Reduce cooldowns by a selected amount. | `ReduceCooldownsByValue` | **Candidate:** verify units, valid range, and affected cooldowns. |
| 13 | Extend active effects | Adjust duration of selected gameplay effects. | `ExtendGameplayEffectDuration` | **Candidate:** requires valid effect handles and duration semantics. |
| 14 | Ability cost-check control | Investigate disabling cost checks for a selected ability. | `SetCheckCost` | **Candidate:** does not establish unlimited ability use or bypass cooldowns. |

## Inventory — Items, currency, and equipment

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 15 | Add gold / currency | Add a chosen amount of a valid currency. | `AddCurrency` | **Historical pilot:** revalidate current build, currency enum, quantity readback, and save restoration. |
| 16 | Item browser and grant | Add an item selected from a verified live roster. | `TryAddItem` | **Historical pilot:** requires a valid typed handle; an asset name is insufficient. |
| 17 | Add and equip | Grant a valid item and equip it. | `TryAddAndEquipItem` | **Candidate:** inspect equipment compatibility and both quantity/equipment results. |
| 18 | Upgrade selected item | Request an upgrade for a selected inventory item. | `UpgradeItem` | **Candidate:** discover legal upgrade levels, costs, and item handles. |
| 19 | Loadout switcher | Select an existing equipment loadout. | `SetActiveLoadout` | **Candidate:** validate loadout indices and actual equipped state. |
| 20 | Inventory/storage transfer | Move a selected item between valid inventories. | `TransferItem` | **Candidate:** verify both inventories and transferred quantity. |
| 21 | Currency transfer | Transfer currency between supported inventories. | `TransferCurrency` | **Candidate:** verify balances on both sides; not a currency-creation method. |
| 22 | Sell all junk | Sell items the game classifies as junk. | `SellAllJunk` | **Candidate:** confirm sale context, selection, proceeds, and persistence. |

Currency readback is `InventoryComponent:GetCurrencyQuantity`, not an `InventorySubsystem` method. Inventory transfers use the subsystem. Preserve these owner distinctions when implementing buttons.

## Inventory — Crafting and quickslots

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 23 | Unlock crafting recipes | Request all crafting recipes unlocked. | `UnlockAllCraftingRecipes` | **Candidate:** verify actual unlocked recipe roster and saved state. |
| 24 | Give crafting ingredients | Request ingredients for all crafting recipes. | `AddIngredientsForAllCraftingRecipes` | **Candidate:** inspect quantities, duplicates, and inventory consequences. |
| 25 | Refill daily crafting supplies | Restore the game's daily free crafting items. | `RefillDailyFreeItems` | **Candidate:** identify which supplies and daily limits change. |
| 26 | Craft selected item | Invoke crafting for a supported recipe. | `CraftItem` | **Candidate:** valid recipe, conditions, ingredient consumption, and result required. |
| 27 | Inventory quickslot editor | Assign an owned item to a valid quickslot. | `SetItemInSlot` | **Candidate:** validate item/slot types and original assignment restoration. |

## Player — Progression, traits, and mutations

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 28 | Trait-point editor | Set the available trait-point amount. | `SetTraitPointsAmount` | **Historical pilot:** previous persistence/restore evidence needs current-build revalidation. |
| 29 | Grant quest XP | Grant XP through the game's quest-XP category. | `AddQuestXP` | **Candidate:** takes a category enum; do not present it as arbitrary numeric XP or a multiplier. |
| 30 | Add a level | Request one level-up. | `ForceLevelUp` | **Historical pilot:** revalidate level-up side effects and saved progression. |
| 31 | Raise to selected level | Request level-ups toward a target level. | `ForceLevelUpTo` | **Candidate:** validate bounds; do not assume it can lower levels. |
| 32 | Unlock selected trait | Unlock a trait to a supported rank. | `UnblockTraitToLevel` | **Historical pilot:** roster-derived typed IDs and later-tick verification are required. |
| 33 | Equip / unequip trait | Change whether a selected trait is equipped. | `SetTraitEquipped` | **Candidate:** check prerequisites, slot limits, and active effects. |
| 34 | Reset traits | Request the game's trait reset behavior. | `ResetAllTraits` | **Candidate:** inspect refunds, retained unlocks, and other side effects. |
| 35 | Add mutation charges | Grant mutation charges. | `AddMutationCharges` | **Candidate:** establish amount limits, charge consumption, and persistence. |
| 36 | Mutation enable selector | Enable a supported vampire mutation. | `SetVampireMutationEnabled` | **Candidate:** needs valid mutation IDs and an enabled-state postcondition. |
| 37 | Ability quickslot editor | Assign an ability to a supported slot. | `SetAbilityInSlot` | **Candidate:** validate ability roster, unlocks, and prior assignment restoration. |

Raw Lua strings passed to reflected `FName` parameters previously crashed the game. Reuse typed roster values and deferred verification patterns from the existing implementation. Do not promote old-build pilots to current-build working features automatically.

## Combat — Difficulty

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 38 | RPG difficulty | Change the RPG difficulty setting. | `SetRPGDifficulty` | **Historical pilot:** earlier reversible difficulty tests exist; verify this build's enum and restoration. |
| 39 | Action difficulty | Change the action difficulty setting. | `SetActionDifficulty` | **Historical pilot:** recheck setting readback and gameplay transition. |

## World — Time, weather, and visibility

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 40 | Set time of day | Set the game's clock through its time system. | `SetTime` | **Candidate:** discover time representation and story/quest effects. |
| 41 | Advance time | Add a chosen number of time segments. | `AddTimeSegments` | **Candidate:** check day, deadline, and event consequences; not necessarily reversible. |
| 42 | Weather selector | Request a supported weather preset. | `BP_ChangeWeather` | **Candidate:** interface needs a concrete implementation; preset roster/getter missing. |
| 43 | Fog distance | Adjust the supported fog-distance setting. | `SetFogDistance` | **Candidate:** verify units, getter, camera context, and restore behavior. |
| 44 | View distance | Adjust the supported view-distance setting. | `SetViewDistance` | **Candidate:** verify what this method actually affects and record a baseline. |

Changing the clock is not proof of pausing the story countdown. Treat story timer controls as a separate contract.

## NPC and quests — Court, encounters, and behavior

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 45 | Court alert editor | Change a supported court alert level. | `SetAlertLevel` | **Candidate:** discover court identifiers and associated quest consequences. |
| 46 | Activate encounter | Request activation of a selected encounter. | `BPActivateEncounter` | **Candidate:** valid encounter IDs and lifecycle required; not a generic NPC spawner. |
| 47 | NPC attitude selector | Change a selected NPC's combat attitude. | `SetAttitude` | **Candidate:** valid attitude enum and authoritative readback missing. |
| 48 | NPC aggression target | Set aggression toward a valid target. | `SetAggressiveTowards` | **Candidate:** object lifetime, target ownership, and restoration need investigation. |

## Visuals — Appearance and camera

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 49 | Appearance selector | Apply a supported appearance to the target component. | `ApplyAppearance` | **Candidate:** requires valid appearance records and original-look restoration. |
| 50 | Freeze cloth for posing | Pause cloth simulation on its supported actor. | `FreezeClothSimulation` | **Candidate:** declared on `DummyAppearanceNPC`; do not assume it controls the player. |
| 51 | Photo camera | Enter photo-camera mode; develop a verified exit control. | `EnterPhotoCamera` | **Candidate:** entry is captured; validate ownership, exit, input, and restoration separately. |
| 52 | Dialogue camera FOV | Set FOV for a supported dialogue camera. | `SetCameraFOV` | **Candidate:** interface needs a concrete camera; this is not established as global gameplay FOV. |

## Combat and movement — Targeting and traversal

| # | Menu feature | What it would do | Captured action | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| 53 | Combat target selection | Select a valid target for the existing lock-on system. | `SetLockTarget` | **Candidate:** validate target eligibility, release, and normal combat behavior. |
| 54 | Vault action | Request the player's supported vault traversal. | `RequestVaultingTraversal` | **Candidate:** needs valid traversal conditions; does not establish free flight or Super Jump. |

## Additional menu features worth developing

These extend beyond the 54 single-action recipes. They need multiple functions, state checks, or further discovery.

| Feature | Why it is useful | Current basis and next requirement |
| --- | --- | --- |
| Movement speed multiplier | Adjustable player movement speed. | **Existing · limited proof:** 1.5× paused apply/resume/restore/cancel verdict; actual distance measurement and endurance remain unproved. See [SpeedControl.lua](../integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/SpeedControl.lua). |
| No Clip / flight controls | Controlled movement through geometry and free positioning. | **Existing · limited proof:** mode/collision/position restoration checks; broad traversal, input focus, and long sessions remain unproved. See [NoClipPilot.lua](../integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/NoClipPilot.lua). |
| Super Jump | Higher player jumps. | **Research / blocked:** trajectory/effect behavior unverified; a reflected traversal method alone does not solve it. |
| Fall-damage protection | Prevent injury when returning from large jumps or flight. | **Research / blocked:** nondamaging trials and zero callbacks do not demonstrate damage suppression. |
| Saved-location teleport | Save named positions, return to them, and restore the starting position. | Existing [SavedLocationControl.lua](../integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/SavedLocationControl.lua) is an implementation starting point; destination validity, streaming, collision, and current-build travel proof must be checked. |
| Position bookmark panel | Name, display, and copy observed locations. | **Readback available:** coordinates were captured. Saving menu bookmarks is separate from actually teleporting. |
| Slow motion / global game speed | Adjust overall simulation speed for exploration or camera work. | Historical controls plus a current recorded 1× reading; verify time behavior and restoration. Distinct from player movement speed. |
| XP reward multiplier | Scale later quest/combat rewards. | **Research / blocked:** previous table-scaling route failed cached-getter verification and was restored. Direct `AddQuestXP` does not fix this. |
| Corruption panel | Inspect corruption and investigate bounded edits. | Existing research associates corruption with persistent world/quest state. Lowering a displayed value does not undo triggered consequences. |
| Story timer controls | Inspect or adjust story deadlines separately from the clock. | Existing story-timer/settings modules are research starting points; verify deadline and quest behavior before enabling changes. |
| Quest inspector | Display discovered quest state and useful identifiers. | Existing [QuestReadback.lua](../integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/QuestReadback.lua); require authoritative per-quest readbacks. Completion/reset buttons are separate unverified work. |
| NPC / creature spawn browser | Choose from actual spawnable classes with valid initialization. | **Research / blocked:** captured asset names are not a validated spawn roster. Horse, boat, and companion buttons remain unsupported until classes and lifecycle are proved. |
| Eye appearance controls | Choose supported in-game eye looks with restoration. | Existing eye modules and preview workflow; preview colors alone do not prove an in-game change. Reuse only separately verified native contracts. |
| Item and ability information browser | Search IDs, descriptions, icons, requirements, and related classes. | Captured metadata provides discovery leads. Actual descriptions/icon pixels/valid runtime IDs may need further authorized data discovery. |
| Save backup and comparison | Preserve progress before persistent feature tests and inspect changes. | Existing save research and backup tooling; decoded save nodes do not prove editable/reload-safe fields. |
| Menu presets and hotkeys | Save preferred UI settings and assign convenient controls. | Menu-side feature work; activating a preset must still check every gameplay capability and current session. |

Unlimited carry weight, extended parry windows, unrestricted quest completion, arbitrary spawns, and full texture/model replacement are **not established as supported features by this list**. They need their own evidence; the catalog should not turn their names into enabled switches.

## Useful live-data panels

| Panel | Available evidence | What to display |
| --- | --- | --- |
| Health, stamina, blood | **Readback available:** 100%, 100%, 75% in the recorded observation. | Values plus last refresh time; support a fresh read. |
| Player location | **Readback available:** X 253627.52, Y 368119.35, Z 23326.41. | Coordinates, copy button, and bookmark option. |
| Global game speed | **Readback available:** 1.00×. | Current observed multiplier and timestamp. |
| Level, XP, traits, inventory | Getter candidates appear in the recipes. | Add only after actual live reads; do not substitute captured defaults. |
| Build / connection status | Existing session-bound bridge and build checks. | Matching build, connection freshness, and actionable unavailable reasons. |

The resource/location snapshot was captured **2026-09-08 at 23:23:07 UTC**. It refreshed only `DWCorePlayer` and `DWCoreWorld`. It is not a continuous feed, and other raw snapshot fields may be defaults or unread. No new live requests were made to produce this document. See [live readback notes](live_player_data/README.md) and [raw observation](live_player_data/latest-observation.json).

## Thirty more useful menu extensions

These are **composite menu/UI ideas**, not additional verified game APIs. They build on the readers, actions, metadata, or settings above; any gameplay step still requires its own verified contract. They can make the menu more useful without filling it with unsupported toggles.

| # | Extension | Player benefit and dependency |
| --- | --- | --- |
| 1 | Favorite controls | Pin frequently used, supported actions to a compact page. Menu-side storage. |
| 2 | Search all menu features | Find controls by name and category. Menu-side search. |
| 3 | Recent actions | Show which action finished, failed, or restored, with a timestamp. Existing response records needed. |
| 4 | Undo last reversible action | Restore the recorded baseline only for actions with proved inverses. Never promise generic undo for progression. |
| 5 | Restore owned toggles | Release all locks owned by this menu and verify each restoration. Requires ownership-aware cleanup. |
| 6 | Exploration preset | Combine verified movement/resource preferences. Each control must pass individual capability checks. |
| 7 | Photo-session preset | Combine supported camera, weather, and visibility settings with recorded restoration. |
| 8 | Resource thresholds | Highlight health, stamina, or blood below a chosen percentage. Fresh readers required. |
| 9 | Refill-all button | Sequence verified health, stamina, and blood refill actions and report each result separately. |
| 10 | Resource history graphs | Plot sampled resource values during play. Bounded polling and fresh readings required. |
| 11 | Compact player overlay | Display verified resource values and coordinates in a small menu view. |
| 12 | Disconnect/stale-data indicator | Clearly mark when displayed player values are outdated. Session timestamps required. |
| 13 | Per-control availability details | Explain missing player, wrong build, or unresolved target directly beside the feature. |
| 14 | Hotkey conflict checker | Prevent accidental duplicate bindings or conflicts with reserved menu keys. Menu-side validation. |
| 15 | Hold-to-activate hotkeys | Support temporary verified reversible effects with reliable release/focus-loss cleanup. |
| 16 | Separate form preferences | Remember human/vampire UI preferences; only apply gameplay settings after validating form transitions. |
| 17 | Searchable item categories | Filter verified roster entries into weapons, clothing, consumables, or ingredients when metadata supports it. |
| 18 | Favorite item grants | Save valid roster selections and preferred quantities, then re-resolve IDs each session. |
| 19 | Grant quantity preview | Show requested amount and resulting observed quantity before/after a verified item action. |
| 20 | Equipment comparison panel | Compare captured/readable stats for current and selected equipment, labeling unavailable fields. |
| 21 | Missing crafting ingredients | Compare valid recipe requirements with actual owned quantities. Requires both authoritative readers. |
| 22 | Crafting shopping list | Build a local list of required ingredients for selected recipes. No grant action implied. |
| 23 | Loadout labels | Name supported loadout indices locally and provide a clear switcher. |
| 24 | Trait search and filters | Browse verified trait roster, unlock ranks, and equipped status. Typed IDs required. |
| 25 | Trait-point budget preview | Calculate planned selections without applying them; requires actual cost/requirement metadata. |
| 26 | Bookmark folders | Organize saved positions by user-defined region or purpose. Menu-side storage. |
| 27 | Distance to bookmark | Calculate distance from a fresh position to a saved coordinate in game units; do not assume meters. |
| 28 | Return-to-start bookmark | Preserve the pre-travel position for a verified return action, subject to destination validity. |
| 29 | Named backup browser | Label complete save backups and display their timestamps/build context. Restoration remains a separate procedure. |
| 30 | Export feature profile | Export menu preferences and valid selections; omit stale pointers/session tokens and revalidate imported settings. |

## What the captured files give us

| Source | How it helps build features |
| --- | --- |
| [All classes](data_exports/all_classes.csv) | Find the component, actor, or subsystem that owns a capability. |
| [All functions](full_dump/CL257186/functions.csv) | Discover getters, actions, callbacks, and related operations. |
| [Properties and parameters](full_dump/CL257186/properties.csv) | Check argument types, structs, enums, and captured property declarations. |
| [Exact recipes](feature_catalog/feature_recipes.json) | All 54 complete action owners, argument definitions, getter candidates, and missing contracts. |
| [Technical catalog](feature_catalog/README.md) | Complete database, 16 system guides, relationships, enums, defaults, and search tools. |
| [Asset metadata](full_dump/assets_extracted/README.md) | Discover package and asset references for item definitions, effects, icons, and other feature data. |
| [Runtime evidence](feature_catalog/runtime_evidence.md) | Distinguish existing bounded proof, historical pilots, and failed/unverified routes. |
| [Evidence records](feature_catalog/existing_control_evidence.json) | Exact source/evidence paths and recorded hashes for reviewed existing controls. |
| [Save research](saves/README.md) | Understand backed-up save bundles and decoded persistence data before save-affecting tests. |

The catalog contains **9,328 classes**, **21,669 functions**, and **112,652 property/parameter records**. Asset references are useful identifiers, but raw encrypted textures/models and full DataTable rows remain unavailable in these exports. Captured object addresses and class defaults must not be reused as current live player objects or pointers.

## When a candidate becomes a usable menu feature

For each selected feature, identify the live owner, typed inputs, authoritative baseline getter, actual action result, later-tick readback, visible gameplay effect, and disable/restoration behavior. Test interacting toggles and relevant form/respawn transitions. For inventory, progression, crafting, quests, time, and encounters, preserve the complete save bundle and verify persistence consequences before describing the feature as dependable.

Keep this menu's current layout and visual direction. Place new controls in the existing appropriate category, and show unavailable/research status until the feature has its own verified contract.
