# Changelog

## v3.2 — September 7, 2026

### Progression controls

- Added **Set exact Corruption level** for levels 1–15. The action writes the
  game's saved Vampire corruption attributes, resets within-level charge to zero,
  and verifies the requested value immediately and again after a short delay.
- Documented the required native refresh after changing the level: press **+1 raw
  charge** (optionally **-1** afterward), or drink blood, before judging gameplay
  effects. Lowering the level does not reverse events already triggered.
- Added **Grant Specific Perk**, a searchable selector for every loaded trait and
  a target rank. It changes only the chosen perk, bypasses normal requirements and
  verifies that points, the spent ledger and unrelated perks remain unchanged.

### Three respec depths

- Renamed and expanded respec into **Light**, **Medium** and **Full** modes.
- Light removes ordinary purchased ranks while retaining Ultimates and broad
  earned protections.
- Medium also removes supported Ultimates while retaining broad earned, quest,
  boss-blood and manual-access protections.
- Full performs the deepest reset and restores ranks only for **Compel Soul,
  Astral Communion, Voracious Bite, Mercurial Fervour and Wolf Transform**.
- Corrected the fifth Full-respec anchor to Mercurial Fervour
  (`CombatFocus_ArcaneBoost`); it is not Run Hex.
- Full refuses to arm unless all five essential anchors resolve uniquely.
- All three modes retain exact refund accounting, separate legendary-consumable
  conversion authorization, preview/confirmation and post-change verification.

### Release cleanup

- Removed the temporary corruption reflection probe from the shipping scripts.
- Updated the menu warnings, README and Nexus page for the new controls and known
  refresh behavior.
- UE4SS binaries and the tested HookLoadMap workaround are unchanged from v3.1.

## v3.1 — September 7, 2026

### Kawaii interface

- Rebuilt the menu as a centered, wider gothic-kawaii layout with charcoal-plum
  cards, cream text, dusty-rose borders, lavender controls, mint success actions
  and gold warnings.
- Added decorative title, tab and section symbols, alternating card accents and
  a responsive two-column arrangement for descriptions and controls.
- Added live Health, Stamina and Activation Charge meters plus the current player
  level to Player Status.
- Limited searchable dropdowns to 48 live rows and disabled animated wheel
  scrolling to prevent overlapping text when scrolling quickly.
- Retained the engine-cursor optimization, avoiding the old custom 16 ms cursor
  polling loop. UE4SS overlay rendering may still reduce FPS while open.

### Inventory additions and stability

- Added **Give all Weapons + Clothing**, which grants one of every indexed item
  in those two categories and applies the selected Item Level where supported.
- Changed the bulk queue to wait for each native inventory operation to finish
  before starting its 20 ms pause, preventing game-thread requests from piling up.
- Added per-item preflight logging so a native crash identifies the exact asset
  being attempted rather than only the last successful grant.
- Restricted bulk granting to Weapons and Clothing after the wider All-category
  operation reproduced a native crash at `ITM_Recipe_Recipe4`. Consumables,
  materials, recipes and junk remain available through individual selection.
- Updated the confirmation dialog, Warnings tab, README and Nexus description to
  match the equipment-only bulk behavior.

### Packaging

- Promoted the kawaii build from preview to v3.1 release status.
- Kept the two-package upgrade layout: existing compatible UE4SS users need only
  the Mod Menu ZIP; the UE4SS Setup package is unchanged in binary content.

## v2 — September 6, 2026

### New features

- Added Auto Parry while blocking, with persistent ON/OFF ownership and safe cleanup.
- Added repeatable Infamy increases and decreases in 100-point steps while preserving partial progress.
- Added repeatable one-segment time controls. Forward movement supports day/night and day rollover; rewind remains within the current day/phase.
- Added a selector that grants any one of the nine Ultimate perks without prerequisites, exclusivity or skill-point cost.
- Added Unlock Everything / Max All Traits as a separate, clearly warned bulk action.
- Added a searchable Skill Manuals panel that grants one physical manual without
  directly changing its learned/read state.
- Added a separately warned Keys & Key Items browser for physical key grants.
- Bulk Unlock can now be used repeatedly and documents that recipe/manual-based
  skill access is marked as learned/read.
- Added Standard Respec, which preserves Ultimates, and Full Respec, which includes supported Ultimates.

### Respec improvements

- Preserves earned essential, always-equipped, quest and boss-blood abilities, plus manual unlock access.
- Explicitly preserves Blood Surge, Mesmerise, Scarlet Shield, Piercing Shriek and Shadowstorm.
- Handles legendary-consumable rank differences through a separate, explicit conversion confirmation.
- Fixed the confirmation crash caused by a missing menu reference.
- Successful respecs can be repeated in one session. An unverified mutation still blocks retries until restart.
- Known limitation: Font of Life and Mandrake Ward remain after Full Respec.

### Interface and release cleanup

- Switched from the custom overlay cursor to the engine cursor, removing the
  menu's 16 ms cursor-position polling loop while open.
- Renamed Settings to Warnings and replaced the shortcut editor with consolidated warnings and limitations.
- Removed the World Status panel, Ultimate asset-verification button and dormant research panels.
- Removed development-stage wording from the release interface.
- Increased menu readability and retained the F6 menu toggle plus fixed F11/F12 skill-point shortcuts.
- Documented that cheats trigger achievements and that the open UE4SS overlay can substantially reduce FPS.

### Stability and compatibility

- Retained the low-overhead cached implementations for stamina, activation charges, cooldown reset and Auto Parry.
- Infamy and time mutations verify their results and refuse unsafe retries after an uncertain failure.
- Validated with Steam build 25129649 and the supplied UE4SS configuration.
- HookLoadMap remains disabled because its UE4SS callback reproduced an access violation.

## v1 — preserved baseline

Skill points, XP, corruption, coins, materials, item/equipment grants, stamina refill, quick fill activation charge, quick cooldown reset, shrine unlocks and protected respec.
