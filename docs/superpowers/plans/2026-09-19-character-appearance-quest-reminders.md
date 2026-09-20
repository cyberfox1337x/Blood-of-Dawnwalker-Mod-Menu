<!-- cyberfox1337x.function("character-appearance-quest-reminders-plan") -->

# Character Appearance and Quest Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make eye, hair, eyebrow, and skin selections update the embedded character immediately; keep enabled quest reminders reliable across the running application's lifecycle; and perform the three approved Player-page cleanups.

**Architecture:** A pure renderer appearance-state adapter reconciles optimistic selections with confirmed runtime snapshots, while a Three.js material controller applies independent non-destructive preview layers. Quest selection stays bounded in Lua but prioritizes tracked/active records; a new Electron-main monitor owns scheduling, deduplication, notification delivery, and renderer toast events.

**Tech Stack:** React 19, TypeScript 5.8, Electron 44, Three.js 0.185, Vitest, Lua/UE4SS, PowerShell packaging and installer verification.

**Spec:** `docs/superpowers/specs/2026-09-19-character-appearance-quest-reminders-design.md`

## Global Constraints

- Keep Steam build `25232147 / 1.0.5 CL-258504` as the only supported build.
- Preserve existing game restoration, save protection, confirmation, and exact-build gates.
- Preview changes must never mutate the source GLB textures.
- Objective Reminders operate only while the mod-menu application process is running; do not add a tray process, startup entry, or service.
- Retain the six-quest, three-objective, and 8 KiB quest-readback bounds.
- Add the required `cyberfox1337x.function(...)` or language-valid signature to every created or materially modified code/test file.
- Use TDD: observe each focused test fail before adding its implementation.
- A newly built installer requires fresh exact-candidate native install/repair/uninstall evidence before Nexus promotion.

## Review Focus

- A failed native appearance command must roll the preview back to the last confirmed value; Task 2 tests rejection and session replacement.
- The appearance shader must compose the existing painted-eye `onBeforeCompile`; Task 3 asserts callback order and retained eye uniforms.
- A tracked quest after slot six and active non-optional objective after slot three must still be returned; Task 4 adds Lua fixtures for both.
- Busy runtime work must cause a bounded reminder retry without duplicate notifications; Task 5 tests retry and deduplication.
- Disabling reminders must cancel every pending timer and suppress later renderer/Windows output; Task 5 tests disposal and toggle-off races.

---

### Task 1: Requested Player-page cleanup

**Files:**
- Modify: `src/MovementSpeedControl.tsx`
- Modify: `src/MovementSpeedControl.test.tsx`
- Modify: `src/ReferenceDashboard.test.tsx`
- Modify: `src/App.tsx`
- Modify: `src/App.test.tsx`
- Modify: `src/ReferenceTheme.css`

**Interfaces:**
- Consumes: existing `DWSpeed.speed` dispatch and Player dashboard layout.
- Produces: no visible speed-restore row, no `DWRespec` footer, no locked-combat notice, and a contained unresolved-contract list.

- [ ] **Step 1: Write failing UI tests**

Add assertions that `Restore normal movement speed`, `1x: original movement profile restored`, `Other combat contracts remain locked`, and `Skill Respec` are absent, while changing the speed range to `1` still dispatches `{ action: "set", sectionId: "DWSpeed", itemId: "speed", value: 1 }`. Add a structural assertion that the unresolved list has the containment class.

- [ ] **Step 2: Run focused tests and observe failure**

Run: `npx vitest run src/MovementSpeedControl.test.tsx src/ReferenceDashboard.test.tsx src/App.test.tsx`

Expected: FAIL on the still-visible rows/sections and missing containment class.

- [ ] **Step 3: Implement the minimal cleanup**

Remove the restore button and status rendering from `MovementSpeedControl`; retain its slider and `1x` dispatch. Remove `DWRespec` from the `ReferenceDashboard` footer and remove the `Other combat contracts remain locked` `CapabilityNotice`. Keep `DWRespec` excluded from the other imported Player panels so it remains hidden. Add a scoped class/CSS rule using `padding-inline-start`, `list-style-position: outside`, and contained list-item spacing for the unresolved-contract list.

- [ ] **Step 4: Re-run focused tests**

Expected: PASS.

### Task 2: Appearance state and panel callbacks

**Files:**
- Create: `src/characterAppearanceState.ts`
- Create: `src/characterAppearanceState.test.ts`
- Modify: `src/EyeAppearancePanel.tsx`
- Modify: `src/HairColorPanel.tsx`
- Modify: `src/HairColorPanel.test.tsx`
- Modify: `src/SkinTintPanel.tsx`
- Modify: `src/SkinTintPanel.test.tsx`
- Modify: `src/App.tsx`

**Interfaces:**
- Produces: `CharacterAppearance`, `ConfirmedCharacterAppearance`, `parseConfirmedCharacterAppearance(snapshot)`, and optimistic reducer actions for eye, hair, brows, skin, restore, failure, and session replacement.
- Consumes: Task 3 accepts `CharacterAppearance` as controlled preview input.

- [ ] **Step 1: Write failing state and callback tests**

Test confirmed parsing for `DWEyeColor`, `DWHairColor`, and `DWSkinTint`; optimistic same-click updates; confirmed reconciliation; failure rollback; disconnected/session replacement; and neutral restore. Extend Hair/Skin panel tests with `onPreviewChange` spies that receive the selected value before the existing dispatch assertion.

- [ ] **Step 2: Run focused tests and observe failure**

Run: `npx vitest run src/characterAppearanceState.test.ts src/HairColorPanel.test.tsx src/SkinTintPanel.test.tsx`

Expected: FAIL because the module and callbacks do not exist.

- [ ] **Step 3: Implement pure state and wire controls**

Use strict parsers: eye/hair/brow `#RRGGBB | null`, glow `0..3`, and integer skin tuple `[0..100, 0..100, 0..100]`. Store `{ confirmed, optimistic, sessionId }`; display `optimistic ?? confirmed`. Hair/Skin selections call the preview callback synchronously, then dispatch. App owns the reducer, reconciles on snapshot revision/session/operation state, and passes the controlled appearance to `EyeAppearancePanel`.

- [ ] **Step 4: Re-run focused tests**

Expected: PASS.

### Task 3: Non-destructive Three.js appearance layers

**Files:**
- Create: `src/characterAppearanceMaterial.ts`
- Create: `src/characterAppearanceMaterial.test.ts`
- Modify: `src/CharacterEyePreview.tsx`
- Modify: `src/CharacterEyePreview.test.tsx`
- Modify: `src/EyeAppearancePanel.tsx`
- Modify: `src/EyeAppearancePanel.test.tsx`

**Interfaces:**
- Consumes: `CharacterAppearance` from Task 2.
- Produces: `createCharacterAppearanceMaterialController(root): { apply(appearance): void; dispose(): void }` and controlled `appearance` prop on `CharacterEyePreview`.

- [ ] **Step 1: Write failing controller and preview tests**

Construct representative `MeshStandardMaterial` meshes named with the measured GLB part IDs. Assert neutral appearance leaves shader uniforms disabled; skin, hair, and brow layers are independent; the prior eye callback still runs; apply updates uniforms without replacing maps; restore disables all overrides; and dispose restores callbacks. Mock the controller in the preview test and assert load/reload receives the controlled appearance.

- [ ] **Step 2: Run focused tests and observe failure**

Run: `npx vitest run src/characterAppearanceMaterial.test.ts src/CharacterEyePreview.test.tsx src/EyeAppearancePanel.test.tsx`

Expected: FAIL because the controller and controlled prop do not exist.

- [ ] **Step 3: Implement the material controller**

Measure and encode bounded model-part/position masks for the shipped `medieval-warrior.glb`. Chain each material's prior `onBeforeCompile`, inject uniforms and colour transforms after `map_fragment`, and set `customProgramCacheKey` to a stable appearance-layer version. Never replace `material.map`. Mark materials `needsUpdate` only when shader structure changes; ordinary selections update uniforms and render. Reapply controlled state after model load and after focus-driven preview recreation.

- [ ] **Step 4: Re-run focused tests and capture preview diagnostic**

Expected: PASS; diagnostic capture shows clothing unchanged across high-contrast hair/skin tests.

### Task 4: Prioritized bounded quest readback

**Files:**
- Modify: `integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/QuestReadback.lua`
- Modify: `integration/imported-menu/tests/QuestReadback.Tests.lua`

**Interfaces:**
- Produces: unchanged schema-1 serialized readback with tracked quest first and active non-optional objective first.
- Consumes: Task 5 parses the same schema with existing `parseQuestJournal`.

- [ ] **Step 1: Add failing Lua cases**

Create nine opened quests with the tracked quest at index nine and five objectives with the first active non-optional objective at index five. Assert that tracked/current records appear, no duplicate appears, returned counts remain `6`/`3`, optional active objectives are not prioritized, and output remains at most 8192 bytes. Preserve player/world/journal replacement cases.

- [ ] **Step 2: Run the focused Lua test and observe failure**

Run the same Lua executable and argument convention used by `scripts/Test-DawnwalkerLua.ps1` for `QuestReadback.Tests.lua`.

Expected: FAIL because current loops only inspect the initial slots.

- [ ] **Step 3: Implement priority selection**

Scan only validated opened/objective arrays, select the tracked quest/current objective first by address/state/optional fields, fill remaining slots in source order using address/index deduplication, then keep the existing sorting/serialization and post-capture identity checks.

- [ ] **Step 4: Re-run focused and complete Lua suites**

Run: `npm run test:lua`

Expected: all Lua suites PASS.

### Task 5: Electron-main quest reminder monitor

**Files:**
- Create: `electron/questReminderMonitor.ts`
- Create: `electron/questReminderMonitor.test.ts`
- Modify: `electron/importedMenuOwner.ts`
- Modify: `electron/main.ts`
- Modify: `electron/preload.cts`
- Modify: `src/desktop.d.ts`
- Modify: `src/App.tsx`
- Modify: `src/App.test.tsx`
- Modify: `src/questReminder.ts`

**Interfaces:**
- Produces: `createQuestReminderMonitor({ getEnabled, state, dispatch, notify, publish, setTimeout, clearTimeout, intervalMs, retryMs })` with `start()`, `settingChanged(enabled)`, and `dispose()`.
- `importedMenuOwner` exposes its authenticated internal `transport` only through a returned main-process `monitorTransport` facade; it is not added to preload.
- Preload exposes `questReminder.onReminder(listener)` for validated `{ title, objective }` renderer events.

- [ ] **Step 1: Write failing monitor lifecycle tests**

Use fake timers and transport fixtures to assert: persisted enabled start; silent first seed; one notification/event on objective or progress change; 2-second busy retry; no duplicate on unchanged state; toggle-off cancellation; ready-session replacement reseed; disconnect/reconnect; renderer absence; notification rejection; and disposal.

- [ ] **Step 2: Run focused tests and observe failure**

Run: `npx vitest run electron/questReminderMonitor.test.ts src/App.test.tsx src/questReminder.test.ts`

Expected: FAIL because the monitor and event API do not exist.

- [ ] **Step 3: Implement monitor and remove renderer scheduling**

Move shared reminder selection to an Electron-importable pure module or duplicate no logic: both main and renderer import one function. Main starts the monitor after stores load and owner registration, calls `settingChanged` after persisted writes, delivers Windows notifications through the existing sanitized notification function, and sends accepted reminders to a live window. Remove App's 20-second dispatch interval and direct changed-objective desktop notify; subscribe only to `onReminder` for in-menu toast/status. Keep the manual test-notification action.

- [ ] **Step 4: Re-run monitor and renderer tests**

Expected: PASS.

### Task 6: Full regression, packaged acceptance, and release promotion

**Files:**
- Update generated runtime manifest/catalog/build output through existing scripts.
- Create: `qa/appearance-reminders-20260919/` evidence files.
- Update: `Nexus-Upload-0.1.0` release notes, manifest, checksums, and screenshots only after exact-candidate verification.

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: exact packaged installer and evidence bound to its SHA-256.

- [ ] **Step 1: Run source regression gates**

Run lint, full `npm test`, `npm run test:lua`, current runtime preparation/tests, current release tests, build, and `npm run verify:release:current`. Save complete logs.

- [ ] **Step 2: Build and structurally verify a new isolated candidate**

Run the current-build Electron Builder command with a new output directory, then `Assert-DawnwalkerImportedInstaller.mjs` against that directory. Record installer/app.asar hashes and unsigned status.

- [ ] **Step 3: Perform packaged UI and live-game acceptance**

Verify the three removed Player elements are absent and the combat list is contained at supported scales. With a loaded supported save, exercise eye, hair, eyebrow, and skin preview changes plus Restore; confirm runtime remains fresh, pending tasks return to zero, and save hashes remain unchanged. Exercise reminders across F10, minimize, renderer reload, reconnect, and save reload; use deterministic changed-objective injection only at the monitor boundary and record one Windows plus one in-menu event.

- [ ] **Step 4: Perform exact native installer round trip**

Back up and hash the current 4,081-file runtime and 50-save baseline, then run the existing elevated exact-candidate install/repair/uninstall helper. Require exit zero, exact restoration, and no remaining managed app/state/registration before promotion.

- [ ] **Step 5: Promote exact bytes and update Nexus metadata**

Copy without rebuilding into `release-final` and `Nexus-Upload-0.1.0`, preserve the prior release in a timestamped archive, update hashes/performance/limitations truthfully, re-run both installer verifiers, reinstall the exact final candidate, launch through Steam, press Space through startup, and leave the connected menu open on Visuals.
