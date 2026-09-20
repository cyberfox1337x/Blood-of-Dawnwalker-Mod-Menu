<!-- cyberfox1337x.function("character-appearance-quest-reminders-design") -->

# Character Appearance Preview and Quest Reminder Reliability

**Status:** Approved in conversation; pending review of this written specification before implementation.

## Purpose

Make every live appearance selection visible on the embedded 3D character and make enabled Objective Reminders continue following the player's tracked quest throughout a running game session. The work also removes the requested Player-page clutter and corrects the unresolved-combat list layout.

## Product boundaries

- Appearance controls continue applying to the game through the existing `DWEyeColor`, `DWHairColor`, and `DWSkinTint` runtime sections.
- The preview is a faithful visual approximation of the selected values on the supplied painted GLB. It does not claim pixel-identical parity with Unreal lighting or native game materials.
- Objective Reminders operate while the mod-menu application process is running, including when the window is hidden with F10, minimized, reloading its renderer, or reconnecting after a save or game-session change.
- Fully closing the mod-menu application stops monitoring and notifications. This change does not add a tray process, Windows-startup entry, or background service.
- Existing gameplay restoration, confirmation, save protection, and exact-build checks remain unchanged.

## Appearance architecture

### Confirmed and optimistic state

A focused appearance-state module will parse the latest confirmed values from the imported runtime snapshot:

- Eye colour and glow from `DWEyeColor`.
- Hair and eyebrow colours from `DWHairColor`.
- Skin RGB channels from `DWSkinTint`, where `50 / 50 / 50` is neutral.

The Visuals controls will publish an optimistic preview value before dispatching the existing native command, so the model changes in the same interaction. A successful runtime snapshot replaces the optimistic value with confirmed state. A failed operation, session change, disconnect, or native contradiction drops the optimistic value and restores the last confirmed appearance. Restore actions immediately show the original preview and then reconcile with native confirmation.

### Preview material controller

A dedicated Three.js controller will attach to the loaded `MeshStandardMaterial` instances without replacing their source textures. It will preserve and compose any existing `onBeforeCompile` callback used by painted-eye recolouring.

The controller will expose independent operations for eye, hair, eyebrow, and skin appearance. Eye rendering keeps the existing measured iris implementation. Hair and eyebrows use bounded masks measured against the supplied `medieval-warrior.glb`; eyebrows remain independent from scalp hair. Skin tint multiplies only measured skin regions and follows the game's channel-to-neutral relationship. Clothing, eye whites, iris textures, and unrelated model parts must retain their original colour.

Disposal removes shader hooks and references when the preview is released by the existing focus/minimize lifecycle. Recreating the preview reapplies the latest confirmed or optimistic appearance.

## Quest reminder architecture

### Complete bounded readback

`QuestReadback.lua` will keep the current six-quest, three-objective, and 8 KiB output bounds while changing selection order:

1. Scan the bounded opened-quest collection and include the tracked quest first even when it appears after the first six entries.
2. Fill remaining quest slots with other opened quests in stable order.
3. For every included quest, include its first active, non-optional objective first even when it appears after the first three entries.
4. Fill remaining objective slots in original order without duplicates.
5. Retain player, world, journal, class, count, UTF-8, and post-capture identity checks.

This ensures the reminder input contains the current tracked work without removing the existing safety and size limits.

### Main-process monitor

The Electron main process will own one reminder monitor alongside the authoritative persisted setting and imported-menu transport. This avoids renderer lifecycle gaps and duplicate polling.

When enabled, the monitor will:

- Refresh immediately when the setting turns on and whenever a new ready runtime session appears.
- Seed the current objective without announcing it, preventing a duplicate notification for the step already in progress.
- Refresh every 20 seconds while ready.
- Retry a busy or temporarily unavailable read after a bounded two-second delay instead of waiting another full interval.
- Deduplicate by quest title, objective text, and numeric progress.
- Reseed after a save load, player/world replacement, or new runtime session.
- Stop dispatching and clear timers immediately when disabled or disposed.
- Ask the existing main-process notification path to display Windows notifications only after confirming the persisted setting is still enabled.

The renderer's existing reminder interval and desktop-notify call will be removed. The main process will emit a narrow event containing an accepted reminder so the renderer can show the matching in-menu toast. Renderer reloads may miss an in-menu toast that occurred while no renderer existed, but the Windows notification remains authoritative and is never duplicated when the renderer returns.

Notification rejection or Windows identity failure will be reported through reminder status without disabling monitoring. Gameplay read failures remain retryable and never generate an empty or stale reminder.

## Requested Player-page cleanup

- Remove the visible `Restore normal movement speed` button and its `1x: original movement profile restored` status text. The speed slider's `1x` position remains the normal-speed restore route, and native restoration logic remains available for lifecycle cleanup.
- Correct the `Unresolved combat contracts` list so bullets and text stay inside the card at supported menu scales and do not overlap the left border.
- Remove the complete `Other Combat Contracts Remain Locked` notice and the visible `Skill Respec` block shown beneath it. The underlying `DWRespec` runtime source remains intact but is excluded from the desktop menu, preserving compatibility and avoiding unrelated gameplay changes.

## Testing

### Automated

- Appearance-state parsing and reconciliation: confirmed state, optimistic update, native failure, restore, disconnect, and session replacement.
- Material controller: neutral identity, independent hair/eyebrow/skin masks, eye-shader callback composition, restore, recreation, and disposal.
- Visual panels: immediate preview callback plus unchanged native dispatch.
- Quest Lua: tracked quest after position six, active objective after position three, optional-objective exclusion, stable fill order, output limits, world/player/journal replacement, malformed data, and empty journal.
- Main-process monitor: persisted enabled state, initial seed, one notification per change, progress updates, busy retry, disable cancellation, reconnect, save/session reseed, renderer reload, notification refusal, and disposal.
- Player UI: removed speed restore/status, hidden respec/locked notice, and combat-list containment.
- Full TypeScript, Vitest, Lua, lint, build, installer, and release-gate suites.

### Packaged acceptance

- Open the installed menu on Visuals and verify eye, hair, eyebrow, and skin changes visibly update the 3D model in eye, portrait, and full-body framing.
- Verify native game application and Restore remain correct for the supported build without changing unrelated model materials or saves.
- Enable Objective Reminders, verify the persisted switch after reopening the menu, and exercise F10 hide/show, minimization, renderer reload, game reconnect, and save reload with no duplicate notification.
- Confirm a current live quest seeds silently and a deterministic changed-objective fixture generates one Windows notification and one in-menu toast.
- Capture supported desktop scales showing the combat list contained and all three requested Player-page elements absent.
- Rebuild the installer, regenerate runtime and release hashes, and repeat the exact native install/repair/uninstall restoration round trip before promoting a new Nexus candidate.

## Release evidence

The final evidence must identify the exact installer SHA-256 and embedded `app.asar` SHA-256, signed status, supported game build, runtime/imported file counts, test totals, live appearance screenshots, reminder lifecycle results, save-tree comparison, and native installer restoration result. A rebuilt installer is not considered equivalent to the previous native-tested executable.
