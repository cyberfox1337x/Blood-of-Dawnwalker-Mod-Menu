# Current mod menu — quick start

This guide applies to the current imported menu for Steam build **25232147**, game **1.0.5 / CL258504**, in offline single-player play.

## Start the menu

1. Launch `release-current/win-unpacked/Blood of Dawnwalker Mod Menu.exe`.
2. Start the game and load your save. Press Space to skip startup cinematics when the game accepts it.
3. Wait for live player values and enabled controls. Controls remain unavailable at the title screen or without a verified loaded session.
4. Press **F10** to minimize or restore the menu. **F9 adds 10,000 gold** when the gameplay action is available; it is not a navigation key.

Choose Player, World, Inventory, Teleport, Visuals, Quests or Settings from the left side. Read each control's current status and any confirmation before applying it. A queued action is not yet a confirmed game change. Save UI Preset stores menu preferences; it is not a game-save backup.

Quit the game through its normal Quit Game command when finished. The desktop menu can remain open and reconnect to a later loaded session. A closed game correctly leaves gameplay controls unavailable.

## Tested installer

The tested unsigned installer is `release-final/Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe`. It contains the same app as the tested unpacked folder. The older `release-current-installer-qa` candidate predates the recovery fix.

Close the game before installation, repair or removal. The installer checks the exact supported game build. A real native install, repair and uninstall cycle passed. All 4,081 pre-existing runtime files and 50 protected save files matched their original hashes afterward. The release retains the disclosed limitations below. Do not use the historical pilot installer instructions elsewhere in this repository for this current menu.

## Current verification limits

The current package includes recovery from an unacknowledged automatic quest read. Normal gameplay dispatch, restoration, reconnection and loaded-save shutdown were verified; the full automated suite passed 635 Vitest and 11 Node checks.

Three previously accepted feature limitations remain: shrine world effects, repair of actual permanent blood damage, and photo camera behavior on a suitable map. Their request paths do not prove those unavailable effects.

An intermittent game startup hang also reproduced without the mod loaded; its cause remains unresolved. Foreground idle CPU measured 2.11% of this eight-core machine, slightly above the proposed 2% engineering benchmark, with accessibility servicing contributing substantially. Accessibility remains enabled.

See [current readiness evidence](qa/final-product-20260919/CURRENT-CANDIDATE-READINESS.md) for exact artifact identities, measured results and remaining checks.


