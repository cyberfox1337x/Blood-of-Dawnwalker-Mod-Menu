# Dawnwalker integration status

Reviewed 2026-09-06 UTC. This update delivers working desktop file tools and stabilization fixes. It does **not** complete the requested gameplay menu. No new gameplay effect was verified during this work.

## Existing work finished

The [Freebuff handoff review](FREEBUFF-HANDOFF-REVIEW.md) identifies the recovered task and distinguishes its historical observations from fresh checks. Cleanup was already complete: the temporary save driver was absent, and all 91 live save-tree files matched the pretest manifest. No repeat restoration was necessary. Exact slot identity and executable attribution were missing from its final rank-three test, so that result was not promoted to verified current-build evidence.

Fixed the desktop and CLI timeouts that could expire before Unblock Trait's deferred verdict. Both now wait up to eight seconds, and tests received authoritative verdicts at 6.1 seconds. Fixed stale build constants in payload preparation, installer, and release tests to match the existing reviewed contract. The actual installed game has since updated again; this update does not repin that game as compatible.

## Requested features

| Area | Delivered and current limitation |
| --- | --- |
| Eyes | Exact source/permissions reviewed and credited. Material ownership, parameters, human/vampire transitions and restoration remain unresolved. No live color controls or third-party presets shipped. |
| Attack speed | Player combat-mode attack-rate candidates and a read-only probe added. Ownership must exclude enemy/shared modes; no live multiplier enabled. Global game speed remains separate. |
| Fog | Integrated independent `r.Fog` and `r.VolumetricFog` configuration, revision checks, verified original backup, pending-commit recovery, and exact restoration. Game must be closed; restart required. **Not verified in game**; local/scripted fog can remain. |
| Stamina | Sprint/dodge/omniblock candidate attributes documented and probed read-only. A typed attribute setter and independent gameplay effect are unproved. Existing broad Unlimited Stamina is preserved, subject to build authorization. |
| Console, loading, god mode | Existing UE4SS bridge preserved; desktop verifies actual game identity before readbacks and dispatch. KZekai's SML explicitly conflicts with UE4SS, so no SML dependency is introduced. Existing god mode is not promoted as current-build or endurance proof. |
| Save editing | Integrated save selection, container/metadata inspection, verified backup history, explicit restore preview, recovery backup, restore and readback. Compressed gameplay fields remain unavailable; these are save-management tools, not completed gameplay-value editing. |
| Focus | Independent range/smell attributes and material observations documented in the read-only probe. Zoom/FOV, postprocessing, setters, restoration and gameplay behavior remain unproved. |

See [all seven source reviews](NEXUS-FEATURE-REFERENCES.md), [native-contract discovery](REQUESTED-RUNTIME-FEATURE-DISCOVERY.md), and [save-format investigation](SAVE-EDITOR-DISCOVERY.md). Download pages exposed listings but not archive bytes; no missing source code was inferred or incorporated.

## Attribution and dependencies

Settings credits Su4enka, Grimpil, DaraTeaGod, nectarines, KZekai, FullTimePatriot and Caites, with each original title, feature relationship and clickable Nexus link. It also names KeinZantezuken from SML's README and the game-asset credits in the stamina description. Each of the seven entries is labeled **Feature inspired by**. No author endorsement is implied.

Additional entries identify Narknon and UE4SS contributors as the existing runtime dependency, and Epic Games as the configuration documentation reference. The MIT license from pinned UE4SS revision `97b7e501` is preserved in `installer/UE4SS-LICENSE.txt` and included in desktop package resources. No application dependency was added. Playwright was installed only in an external temporary QA directory.

The user has explicitly confirmed permission to reuse the referenced creators' work with individual Settings credits, subject to the granted conditions. No Nexus payload had been acquired or incorporated at this checkpoint. Archive access and technical compatibility are separate unresolved requirements; SML still conflicts with the existing UE4SS integration.

## Verification evidence

- Baseline: 95 automated tests in 12 files and the existing lint/Lua/installer checks passed.
- Final: **139 automated tests in 17 files**, zero-warning lint, renderer/Electron build, Lua, installer, packaging-contract and release-gate suites passed. After the final credits and status changes, tests/lint/build and QA packaging were rerun. [Combined evidence](../../qa/dawnwalker-feature-validation-20260906.json) records the exact scope and hashes.
- Packaged QA payload verification passed: 363 inert discovery files, zero gameplay capabilities. All 72 compiled renderer/Electron files matched ASAR bytes; the included UE4SS MIT notice matched its source. Production readiness still refuses the missing live-release proof, as intended.
- [Desktop integration](../../qa/dawnwalker-desktop-integration-20260906.json): actual renderer/preload/IPC fog changes and save restoration on isolated files; real installed-build rejection even with the pilot flag; all seven mod links and both supporting source links reached the allowlisted shell opener (OS browser launch stubbed); no renderer errors. Desktop and 1100×650 screenshots are in `visual-qa/feature-*.png`.
- [Copied-save recovery](../../qa/dawnwalker-save-recovery-20260905.json): 12 real slots recognized; a copied save and companions replaced then restored; all 38 copied source-tree files returned to exact original bytes; recovery snapshot verified. Live source files were unchanged.
- New read-only runtime probe: eight offline test groups passed. It was not installed or run inside the updated game.
- No current-build gameplay endurance, visible fog change, character transformation, save-field editing, or combined-feature gameplay test was performed. The game was not launched and its files were not modified.
- [Final live-file audit](../../qa/dawnwalker-live-files-final-audit-20260906.json): all 91 tracked save/configuration/cache files still match the pretest tree by path, length and SHA-256, with zero differences.

## Build and use

From the project directory in PowerShell:

```powershell
npm ci
npm start
```

The current workspace already has dependencies. `npm start` rebuilds the renderer and Electron code before launch. **Visuals → Fog**, **Save Editor**, and **Settings → Credits** are available independently of the gameplay bridge. The dedicated Save Editor currently provides the file tools described above; it must not be represented as completed gameplay-value editing. See `qa/TEAM-BOARD-20260906.md` for the continuing team work and newer validation.

```powershell
npm run lint
npm test
npm run build
npm run package:qa
```

The QA package contains the inert discovery runtime and is not a gameplay release. Its standalone desktop is `release-qa/win-unpacked/Blood of Dawnwalker Mod Menu.exe`. The QA setup must not be installed into the currently incompatible game. Production `npm run package:win` remains gated; the old `release/` executable is not updated or represented as complete.

Optional desktop verification uses an external Playwright installation:

```powershell
node scripts/Verify-DawnwalkerDesktop.mjs "<Playwright installation>/index.mjs"
```

It copies the local ManualSave2 bundle into a temporary profile, verifies file operations there, and closes its test app. It does not write the original save.

## Recovery and manual gameplay checks

**Fog:** close Dawnwalker, refresh configuration, review the two saved values, then apply. The full original file is backed up before writing. Restore Original Configuration returns its exact bytes (or original absence). The backup path is shown in the menu. If another tool edits Engine.ini, automatic restoration refuses to overwrite it; preserve that newer file and merge the desired settings manually from the retained backup. Restart after applying or restoring. At the same location, weather and time, compare screenshots before/after each fog option; test loading, interiors/exteriors and restoration. Until then its visual effect remains unverified.

**Saves:** close Dawnwalker and wait for cloud synchronization. Select the exact `.sav`, create a backup, choose that backup, and review the destination, hashes and companion filenames before confirming. Restoration creates another recovery backup first. The menu displays its path even if history refresh fails. Reload that save after launching the game. For interruption or companion-file mismatch, keep the game closed and use the recovery procedure in [save discovery](SAVE-EDITOR-DISCOVERY.md); preserve every involved bundle and do not mix `.sav`, `.meta`, and `.png` from different backups.

**Gameplay:** first establish a fresh isolated loader/reflection baseline for installed Steam build 25129649 / CL-257186. Do not weaken or simply change the compatibility pins. Then verify player ownership, typed setter, independent readback and exact rollback for each feature. Test attack timing in each player combat mode without changing enemies/movement; sprint, directional block, omniblock and dodge independently in both forms; focus range/smell/zoom/visibility separately; eyes across both forms/loading; god mode under damage and after disable. Repeat toggles and interactions on backed-up disposable saves. Only promote a control once the recorded gameplay observations support it.

## Changed files

Desktop integration: `src/App.tsx`, `src/styles.css`, `src/runtimeContract.ts`, `src/desktop.d.ts`, `electron/main.ts`, `electron/preload.cts`.

New components/services: `src/FeatureCredits.tsx`, `src/FogSettings.tsx`, `src/SaveTools.tsx`, `electron/featureReferences.ts`, `electron/fogSettings.ts`, `electron/saveEditor.ts`, `electron/gameProcess.ts`, `electron/gameBuildIdentity.ts`.

Stabilization/package: `electron/bridgeTransport.ts`, `scripts/Dispatch-DawnwalkerPilotCommand.mjs`, `scripts/Prepare-DawnwalkerRuntimePayload.ps1`, `installer/DawnwalkerRuntimeInstaller.ps1`, `scripts/Assert-DawnwalkerReleaseReady.ps1`, their regression fixtures, `package.json`, `installer/UE4SS-LICENSE.txt`, and regenerated inert `installer/runtime` payload.

Validation: `src/App.test.tsx`, `src/FeatureTools.test.tsx`, `src/fogSettings.test.ts`, `src/saveEditor.test.ts`, `src/gameBuildIdentity.test.ts`, transport/CLI regressions, `scripts/Verify-DawnwalkerSaveRecovery.mjs`, `scripts/Verify-DawnwalkerDesktop.mjs`, the requested-feature Lua probe/test, reports and QA artifacts. All authored/materially changed code retains the existing language-valid signature convention; declaration/CSS files use comments because they cannot execute a signature.

Original source snapshot: `%TEMP%/dawnwalker-feature-expansion-baseline-20260906`. Earlier generated runtime payload: `%TEMP%/dawnwalker-runtime-payload-before-handoff-20260906`. No existing commits or user changes were discarded.

The [changed-source inventory](../../qa/dawnwalker-feature-changed-source-20260906.json) lists 30 desktop/installer/script files added or changed against the initial snapshot; every entry retains its signature. The Lua probe, reports, package/license files and generated QA artifacts are listed separately above.
