# System study: Court / Infamy / Edict / Notifications

Built from the CL257186 capture (`feature_catalog.sqlite`) on 2026-09-09, after the
Infamy popup soft-lock. Written because guessing at individual functions produced a
soft-lock twice; this maps the whole system first.

Everything here is a **captured declaration**. Where a behaviour was confirmed against
the running game it is marked **[live]**.

---

## 1. The Infamy value itself

`/Script/DogwoodQuest.CourtSubsystem`

| Function | Notes |
|---|---|
| `GetAlertLevel() -> int` | Returns **raw points**, not a level. **[live]** 0, 50, 100, 200 all observed. |
| `GetAlertLevelPercentage() -> float` | Fraction of the bar. |
| `GetAlertStage() -> EAlertStage` | Low / Medium / High. |
| `GetCurrentAlertThresholdLevel() -> int` | The level index. |
| `GetSingleAlertThresholdBarValue() -> float` | **Points per level = 100.** **[live]** |
| `SetAlertLevel(int)` | **MILESTONE setter. Do not call.** Takes a *level*; jumps the Infamy Level without proclaiming the Edict. **[live]** `SetAlertLevel(2)` → reads back 200, and soft-locks. |
| `SetAlertLevelByInt(int)` | Untested. Name suggests a raw-points setter. |
| `ChangeAlertLevelByInt(int)` | Raw current + delta. The pipeline `DropAlertLevelByInt` routes into. |
| `DropAlertLevelByInt(int)` | **The safe path.** Negates its input, so a negative drop *adds*. **[live]** verified 0→50, 0→100, 100→0. |
| `ChangeAlertLevel(EAlertChange)` | Enum-stepped change; see enum below. |

`/Script/DogwoodQuest.CourtSettings` → `MaxAlertLevel` = **900** **[live]**.

So: **9 levels of 100 points.** The shipped Infamy panel moves ±100 via
`DropAlertLevelByInt`; `Scripts/Source/InfamyControl.lua:41` states plainly
*"Never call milestone SetAlertLevel."*

### Enums

- `EAlertChange`: `ToMinimum=0, BigMinus=1, MediumMinus=2, SmallMinus=3, Plus1=4 … Plus12=15, ToMaximum=16`
  — note `Plus1` starts at **4**, so the numeric value is not the step count.
- `EAlertStage`: `Low=0, Medium=1, High=2`
- `ECourtEntryPowerState`: `Full=0, Mid=1, Low=2, Depleted=3`
- `ECourtEntryType`: `None=0, Compound=1, MultipleActivity=2, SubEntry=3`
- `ECourtEntryStatus`: `Hidden=0, Revealed=1, Resolved=2`

---

## 2. Why the popup blocks — the real chain

The Edict popup is **not** a tutorial. Hooking
`/Script/DogwoodSystem.TutorialSchema:ShowTutorial` recorded **zero** events across a
full Infamy level-up **[live]**. It is a **notification**.

The live widget is **[live]**:

```
WBP_NotificationPanel_Infamy_C
  …BP_GameInstance_C.WBP_UIFrontend_C.WidgetTree.WBP_GameHUD_C
    .WidgetTree.WBP_NotificationPanel.WidgetTree.WBP_NotificationPanel_Infamy
```

so it lives in the HUD's notification panel, driven by `NotificationSubsystem`.

### The notification system

`/Script/DogwoodUI.NotificationSubsystem`

| Member | Notes |
|---|---|
| `CurrentNotification` (property) | The `NotificationInfo` on screen. |
| `NotificationQueue`, `NonBlockingNotificationQueue` | Two queues. |
| `GetCurrentNotificationInfo() -> NotificationInfo` | **The getter that says what is showing.** |
| `CanShowNotificationsNow() -> bool` | |
| `TryShowNotificationFromNonBlockingQueue()` | Advances the non-blocking queue. |
| `SetNotificationsHidden(bool)` | Global hide. |
| `PushNotificationBlocker(Name)` / `PopNotificationBlocker(Name)` | Named blockers gate display. |
| `PushNotification(NotificationInfo)` | |

`/Script/DogwoodUI.NotificationInfo`

| Member | Notes |
|---|---|
| `NotifyEnded()` | **Ends this notification.** The correct dismissal call. |
| `ShouldBlockQueue() -> bool` | A blocking notification holds the whole queue until it ends. |
| `ShouldCloseAutomatically() -> bool` | If false it waits for input that may never come. |
| `GetType() -> ENotificationType` | |

`/Script/DogwoodUI.NotificationWidget`

| Member | Notes |
|---|---|
| `ForceMenuInputConfig()` | **Takes input into menu mode.** |
| `RestoreInputConfig()` | **Gives input back.** |
| `OnHideAnimationFinished()`, `OnShowAnimationFinished()` | Animation completion. |
| `OnNotificationShown()`, `OnNotificationHidden()` | |
| `State` (property) | Widget state enum. |
| `NotificationCloseTime`, `CurrentNotificationDuration` | Auto-close timing. |
| `HideAnim`, `ShowAnim` | The animations. |

`/Script/DogwoodUI.NotificationReceiver` → `IsDisplayingNotification() -> bool`
— **a real getter for "is a popup on screen"**, which makes a verified dismissal possible.

`/Script/DogwoodUI.CourtWidgetBase` → `DisableInputDuringEdictAnimation(WidgetAnimation)`
— the Court widget disables input for the Edict animation's duration.

`/Script/DogwoodUI.InfamyNotificationWidget` → `OnAnimationsDone()`,
`TriggerEdictAnimation(int)`, `SwitchToInfamyBar()`, `TriggerUpdateAnimations()`.

### Reading of the failure

An Infamy level-up pushes a **blocking** Infamy notification and plays the Edict
animation, during which input is deliberately disabled. Dismissal normally happens when
the notification ends (`NotifyEnded`) and the widget restores input
(`RestoreInputConfig`). When Infamy is set in a way the Court UI cannot resolve into a
displayable Edict, that sequence never completes: the notification stays current, it
blocks the queue, and input is never restored — which is exactly the observed
"popup won't close and Tab does nothing" **[live]**.

`OnAnimationsDone()` alone was tried **[live]** and was **not** sufficient.

---

## 3. The correct dismissal, in order

1. `NotificationSubsystem:GetCurrentNotificationInfo()` — is anything showing?
2. `info:NotifyEnded()` — end it properly.
3. Verify with `GetCurrentNotificationInfo()` again (should change or clear), and/or
   `NotificationReceiver:IsDisplayingNotification()`.
4. If input is still held, `NotificationWidget:RestoreInputConfig()` on the live widget.
5. `TryShowNotificationFromNonBlockingQueue()` if the queue needs a nudge.

This is verifiable, unlike the earlier `OnAnimationsDone` guess.

---

## 3b. The notification widgets are a POOL - and touching idle ones crashes the game

`FindAllOf("NotificationWidget")` returned **36 widgets** live **[live]**, and the list
is byte-identical whether or not a popup is on screen: pooled toasts
(`WBP_NotificationPanel_Toast_Entry_C_*`) plus one prepared widget per notification kind
(`WBP_NotificationPanel_Infamy`, `_LevelUp`, `_QuestComplete`, `_RecipeUnlocked`, ...).
`NotificationToastPanel` confirms this design: `GetToastWidgetFromPool`, `ToastWidgetPool`.

**So enumeration cannot identify the displayed widget, and name matching is not enough.**

Calling `OnHideAnimationFinished` / `OnNotificationHidden` / `RestoreInputConfig` across
those pooled widgets **crashed the game** **[live]**:

```
EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000038
UE4SS!RC::LuaType::call_ufunction_from_lua()
```

A widget that has never been shown holds no `CurrentNotification`, and the hide path
dereferences it. **`pcall` does not protect against this** - an access violation is not
a Lua error, so the process dies regardless.

The only safe discriminator is a property read before any call:

```lua
local ok, current = pcall(function() return widget.CurrentNotification end)
local displaying = ok and current ~= nil and current:IsValid()
```

Act only on widgets that pass it. Never iterate the pool calling functions "to see what
sticks".

## 4. Court entries (not yet needed, recorded for later)

`CourtSubsystem` also exposes a GameplayTag-keyed entry graph:
`GetEntryStatus(Tag)`, `GetEntryStatusDirectlyFromFact(Tag)`, `GetEntryType(Tag)`,
`GetRootEntry() -> CompoundCourtEntry`, `GetSubEntryParentTag(Tag)`,
`SetEntryStatus(Tag, …)`, `SetEntryStatusComplete(Tag)`.

Edicts appear as trait gameplay effects, e.g.
`GE_Trait_Edict_StrongSoldiers_Level_1`, `GE_Trait_Edict_TradeLaw_Level_1/2` — so an
Edict grants a trait effect. That is the likely reason a directly-set Infamy level has
no Edict to show: the effect was never granted.

UI-side: `WBP_Hub_Court_InfamyBar_C:"Unlock Edict"(int)`,
`WBP_Hub_Court_C:"Trigger Edict Animation"(int)`,
`/Script/DogwoodQuest.EdictTriggerReceiver:OnEdictTriggered(int)`.

---

## 4b. The real cause of the "stuck" Edict prompt: the Court hub tab is LOCKED

The hub wheel (Tab) shows eight entries: Journal, Character, Map, Inventory, Crafting,
Glossary, Active Abilities and one more. **[live]** they were all padlocked, then seven
opened, leaving one locked in the Court position.

That explains the whole symptom. The Edict prompt says "Open the Court panel [Tab]".
Tab works and the hub opens - but the Court tab is locked, so the prompt can never be
satisfied. It was never an input soft-lock.

`/Script/DogwoodUI.HUBManagerSubystem` (the game's own misspelling) owns this:

| Member | Notes |
|---|---|
| `GetAllTabTags(out TArray<FGameplayTag>)` | **UNSAFE - see below** |
| `GetRegisteredHubTabs(out TArray<HubTabRow>)` | **UNSAFE - same reason** |
| `BP_IsTabLocked(tag) -> bool` | Safe: plain struct argument in, bool out. |
| `BP_IsTabBlocked(tag)`, `BP_IsTabDisabled(tag)` | Safe. |
| `BP_SetTabLocked(tag, bEnabled)` | The write. `bEnabled` polarity is undocumented. |
| `RegisteredTabs`, `SpawnedTabs` (TMap properties) | Not readable as a count from Lua. |

### The blocker: struct arrays cannot cross the Lua bridge **[live]**

```
EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000014e00
FName::ToString() <- push_structproperty() <- call_ufunction_from_lua()
```

Calling `GetAllTabTags()` with no argument raises "UFunction expected 1 parameters,
received 0". Calling it with a table makes UE4SS marshal the `TArray<FGameplayTag>` into
Lua and the process dies. `pcall` does not help - an access violation is not a Lua error.

So the lock/unlock calls are safe, but there is **no safe way yet to obtain a tab's
GameplayTag**. The panel therefore ships disabled.

The likely route, unproven: reuse the `GetItemHandle` technique - hook a function that
returns a single tag and consume the native userdata inside the hook's lifetime, exactly
as `Scripts/Source/GameplayMenu.lua` already does for `ItemHandle`.

## 5. Lessons

- The catalog's 54 curated recipes name **one** function per feature. Real systems have
  a pipeline around that function, and the shipped source often already documents which
  entry point is safe. Read the neighbouring class API and the existing Lua first.
- A verified readback proves a value moved, not that the game is still playable.
- Where two setters exist for one system, the one the shipped code avoids is avoided
  for a reason.
- Never marshal a struct or struct array across the Lua bridge here. It has crashed the
  game twice, and `pcall` cannot catch it. Plain scalars, enums and bools are fine.
- A symptom described as "input is dead" was actually "the panel it points at is
  locked". Confirm what a prompt is asking for before building recovery machinery.
