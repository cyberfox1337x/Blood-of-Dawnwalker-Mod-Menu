# Project status and verification history

> This is the previous top-level README, preserved verbatim for its evidence trail and commands. The current public overview is in the repository root [README.md](../README.md). The `Nexus-Upload-0.1.0/` folder it links to is a local packaging output and is not part of this repository.

# Blood of Dawnwalker Mod Menu

`cyberfox1337x.function("dawnwalker_mod_menu_readme")`

An offline, single-player-only Windows mod-menu project for the official Steam build of *The Blood of Dawnwalker*. The desktop shell is Electron + React + TypeScript; the runtime path uses a pinned experimental UE4SS build, a local session-bound bridge, and a transactional installer.

## Current status

Version **0.1.0 is prepared for Nexus upload with disclosed limitations**. [Upload files and instructions](Nexus-Upload-0.1.0/README-UPLOAD.md), [current menu quick start](CURRENT-MENU.md), and [final verification](qa/final-product-20260919/FINAL-RELEASE-READINESS.md).

The unsigned installer under `release-final` and `Nexus-Upload-0.1.0` is the exact native-tested executable, SHA256 `980F746F4A634D36B56A828DEC0C82E8729559F7821F40B357EC08F79196B146`. Real installation, rerunning setup and uninstall passed; all 4,081 original runtime files and 50 save files were restored or preserved exactly. No public upload has occurred.

Supported contract: Steam build **25232147**, game **1.0.5 / CL258504**, Windows x64, offline single-player. The menu verifies the installed executable and runtime payload before enabling controls. For local development/use, launch only `release-current/win-unpacked/Blood of Dawnwalker Mod Menu.exe`.

The package fixes missing-ACK recovery for automatic quest reads, dispatch into a busy callback queue, fresh process checks for file writes, shutdown reporting and exact configuration restoration. The desktop passed 635 Vitest and 11 Node checks; the corrected installer passed both Windows PowerShell 5 suites and the real native roundtrip. Independent final extraction verifies 82 runtime resources, 118 compiled desktop files and 74 imported payload files.

`npm run verify:release:current` now reports ready=true with no blockers. Features, lifecycle and installer checks passed. Performance and startup were explicitly accepted with documented limitations: 2.106% foreground idle CPU missed an agent-proposed 2% benchmark, and an intermittent startup stall also reproduced without the active mod. Neither condition is claimed fixed. Three previously accepted save-dependent effect limitations remain listed in the upload description. See [qualified release review](qa/final-product-20260919/QUALIFIED-RELEASE-REVIEW.md).

For future source changes, build with `npm run build` followed by `npx electron-builder --win dir --config.directories.output=release-current`. The current installer pipeline uses `npm run prepare:runtime:current`, `npm run test:runtime:current`, `npm run test:release:current`, and gated `npm run package:current`. Rebuilt bytes require new identity review; do not silently inherit this exact installer's native proof. Older pilot pipelines and candidate directories below remain historical.

Keep `HookEndPlay = 1` for verified normal shutdown markers. Save/configuration writes require a fresh game-closed check. The release-test uninstall left the original runtime intact and removed the managed test app; no save restoration is required.

## Historical pilot baseline (September 6)

The following baseline is preserved for its original evidence and commands; use the current status and linked validation records above for continuation.

This repository is in verified discovery and live-pilot development, not a finished gameplay release.

Current installation check (2026-09-06 UTC): Steam build **25129649 / CL-257186** differs from the reviewed **25107392 / CL-256914** contract below. The desktop verifies the actual executable before runtime readbacks or commands. Gameplay controls remain unavailable on this installation; an unchanged pilot version string cannot establish compatibility.

The footer displays the installed Steam build detected at runtime.

**Visuals** contains only Eye Appearance. **Save Editor** provides inspection, verified backups, restoration previews, and recovery. Save tools preserve complete selected-save bundles; time, money, health, and daytime stat-point editing remain unavailable until the compressed DSAV payload is understood and reload-tested. File writes require the game to be closed.

**Settings → Credits** identifies all seven feature references and the additional contributor in the console-loader README. No code or assets from the seven Nexus mods are bundled. The console loader explicitly conflicts with UE4SS and is not integrated.

See [current feature verification and recovery](analysis/dawnwalker-uue4ss/FEATURE-INTEGRATION-REPORT.md) and [reference compatibility](analysis/dawnwalker-uue4ss/NEXUS-FEATURE-REFERENCES.md). Historical evidence below remains limited to its recorded version and conditions.

- The frameless menu moves by dragging the title area. Its pointer-drag handler previously passed a native Windows test with an exact `+80,+20` window-position change; the visible drag label and pill have been removed.
- Global `F10` has passed native minimize and restore/focus checks. `F10` is not assigned to any renderer or UE4SS gameplay action.
- Player, Combat, World, Teleport, Visuals, NPC, Quests, Save Editor, and Settings are isolated category pages. Inventory is a distinct section inside the full-width Player page; Location belongs to World.
- The renderer, preload, Electron process, and Lua scaffold share an allowlisted local protocol with a fresh heartbeat, per-launch session ID, serialized dispatch, response matching, and bounded timeouts.
- All pictured game controls are inventoried in `analysis/dawnwalker-uue4ss/feature-contract-matrix.json`. None is advertised as working until the exact reflected target, setter/hook, readback, disable/rollback path, and isolated offline test are recorded.
- The packaged discovery bridge intentionally advertises zero gameplay capabilities. The live-verified `0.3.16-pilot` source advertised exactly 16 audited capabilities. Its read-only suite passed on boot `1788423559-989523`; the immutable artifact is `qa/pilot-evidence/dawnwalker-live-pilot-qa-20260903T082032Z.json` (SHA-256 `2B7408465B67854889BE190384662982D5F8EA4773E1EA17A4AE6E44EB475E3F`). Its safe-reversible suite then verified RPG Difficulty and Action Difficulty independently from `Story -> Normal -> Story`, plus HUD, Game Speed, and Add Gold restoration, ending with an empty active set; that artifact is `qa/pilot-evidence/dawnwalker-live-pilot-qa-20260903T082038Z.json` (SHA-256 `91739704BDDFED2DB94BC933828BCFF3BBD7D58B6780ED21809AB07D1139006D`). Computer-use also passed the rebuilt desktop controls, both difficulty selectors, the Infinite Blood Energy enable/disable cycle, exact window dragging, and global F10 from a focused game. Current `0.3.16` Trait Points evidence now proves the visible `0 -> 1` mutation, normal-save persistence, visible `1 -> 0` restoration, a second reload at baseline, and exact restoration of the protected 76-file pre-test save tree; the pinned artifact is `qa/pilot-evidence/dawnwalker-trait-points-live-persistence-20260903T084603Z.json` (SHA-256 `9332B897BBE1C60DBF2B2423EA8AE25C8C52F681E80F4AA0E499158CFE54F373`). Historical Add Gold persistence evidence remains pinned in `qa/pilot-evidence/dawnwalker-add-gold-live-persistence-20260903T064209Z.json`; the complete original 61-file save tree was restored with zero path, length, or SHA-256 differences. `player:unlimited-weight` remains explicitly withdrawn, and Extended Parry Window remains unavailable because its reflected effect requires an authoritative set-by-caller magnitude that the pinned evidence does not provide. All live evidence remains pilot-only, and the desktop UI stays release-locked unless a production bridge advertises proven capabilities.
- The repository's current source is `0.3.21-pilot` (19 advertised capabilities). `0.3.17-pilot` added Add Item and passed a bounded live `0 -> 1 -> 0` quantity cycle plus all seven guard rejections. `0.3.18-pilot` added Add Level and Unblock Trait; its live Add Level probes passed, but its Unblock Trait probe crashed the game with an access violation because the handler passed raw Lua strings into the `const FName&` parameters of `GetTrait`, `GetTraitUnblockedLevel`, and `UnblockTraitToLevel`, which the pinned UE4SS build does not marshal. `0.3.19-pilot` fixed that route (roster-resolved `Skill_ID` values only) and was promoted; its live probe verified Add Level end to end -- level 1 to 2 with exact readbacks, real level-up postconditions, and a zero-difference closed-game 89-file save restore (artifact `qa/pilot-evidence/dawnwalker-add-level-live-20260903T215316Z.json`) -- and proved Unblock Trait now rejects safely but cannot resolve any id, because the live `GetAllTraits()` container returns wrapped entries only the ForEach read shape unwrapped. `0.3.20-pilot` unwrapped every roster entry on all three container read shapes; its live probe then proved roster resolution works (112 traits enumerated, unknown ids rejected cleanly) and that `UnblockTraitToLevel` commits its level exactly one game beat late, so the same-dispatch readback reported failure on succeeded calls. `0.3.21-pilot` fixes that by deferring the verdict to a bounded later-tick verification (offline harness covers the deferred success, supersession, and exhaustion paths via `npm run test:add-level`); its fresh promotion and live probe then passed on boot `1788474671-718541` -- Add Level 1 -> 2 with exact readbacks, `Human_ToughSkin|1` committed to level 1 and confirmed by the repeat dispatch, and a zero-difference 91-file save restore (artifact `qa/pilot-evidence/dawnwalker-add-level-unblock-trait-live-20260903T223408Z.json`) -- so the matrix marks Unblock Trait pilot-live-verified.
- The installer supports read-only Status plus exact-build-gated Install, Repair, VerifyPayload, and Uninstall with payload hashes, traversal protection, semantic configuration ownership, transaction snapshots, and baseline restoration.

The existing `release/` executable predates live Dawnwalker integration and must not be treated as the final mod. The production packaging command is release-gated and will fail until all concrete gameplay capabilities have live offline proof for the pinned build.

## Pinned game/runtime identity

- Steam App ID `3751260`, build ID `25107392`.
- `Dawnwalker.exe` size `176,998,264` and SHA-256 `45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E`.
- Valid Rebel Wolves Authenticode signature.
- Unreal Engine `5.5.4` build `dw1-pc-256914-shipping-patch2-all-CL-256914` (re-pinned 2026-09-03 after Steam updated the install from CL-256181; all live pilot evidence from 2026-09-03T21:30Z onward is on the CL-256914 build).
- Official experimental zDEV UE4SS `v3.0.1-1111-g97b7e501`, SHA-256 `8C2E28BB1479CBEA7BF5A3C16E027580D9E71D21606971B5BD103A20BA94C617`.

Any game update or identity mismatch stops installation and invalidates prior runtime proof until retested.

## Supplied character preview

Visuals → Eye Appearance loads the supplied full-body character locally, with orbital rotation, free movement, head/eye/full-body framing, iris presets, a color picker, and natural-eye-color restoration. Select **Move** to pan with a left drag, or right-drag in either mode. **Orbit** restores left-drag rotation; scroll or pinch zooms, and **Reset View** restores the selected framing. Keyboard controls are listed under the viewer. Camera movement keeps the character and repaired eyes together. The embedded PBR textures and meshopt decoder are bundled for offline use; the supplied model file remains unchanged.

The current preview asset is the matched derivative `public/models/coen-fullbody.glb`, exported from `character-from-glb/Character_FullBody_Matched.blend`. Reversible shape keys slightly narrow the cheeks, jaw, and shoulders and lengthen the chin to follow the added references. Eye-region positions and body textures are retained. The preview applies a warmer skin tone and clean reconstructed eyes. The runtime copy bakes the shape and uses meshopt compression without mesh simplification or position quantization; the original supplied GLB remains unchanged in Downloads.

Current preview GLB SHA-256: `2968557BAA335D21CA360D8E239D502203B0F8F91710FFBCB3CE0E43E2DC0261`.

These colors affect the model preview. Expand **Game eye controls** for the separate native workflow, which still requires a verified game session before any live eye change. Opening the local character preview does not open a native preview session or apply a game change.

## Development validation

```powershell
npm install
npm start # rebuilds current renderer and Electron sources before launch
npm run lint
npm test
npm run test:pilot
npm run test:carry-capacity
npm run test:unlock-all-skills
npm run test:lua:qa:source
npm run test:package-contract
npm run test:runtime-installer
npm run test:release-gate
npm run build
npm run capture:ui
```

`npm run test:pilot` validates the undeployed pilot source and its promotion contract. `npm run test:carry-capacity` validates the withdrawn carry-capacity feasibility phase and its standalone read-only probe harness; its Lua half needs a local `lua` interpreter on PATH. `npm run test:unlock-all-skills` validates the one-way Unlock All Skills planner, including its authorization gate and its refusal to claim an exact restore; it also needs `lua` on PATH. `npm run test:lua:qa:source` validates the separate inert discovery source; `package:qa` then prepares that exact source and uses `test:lua:qa` to require byte-for-byte payload and manifest parity. `npm run test:release-gate` proves that the discovery payload cannot be shipped accidentally. `npm run verify:release-ready` is expected to fail until the production bridge and `qa/dawnwalker-live-release-proof.json` pass every required feature.

## Read-only runtime status

```powershell
powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\installer\DawnwalkerRuntimeInstaller.ps1 -Action Status
```

## Reflection discovery

Follow `analysis/dawnwalker-uue4ss/DISCOVERY.md`. Dawnwalker must be saved and closed normally before any loader install, repair, promotion, or rollback. The discovery procedure uses an inert smoke profile first, then restricted metadata dump keys, then restores the pre-install baseline. It never patches the signed executable or rewrites locked game containers.

## Packaging

```powershell
# Disposable discovery-build QA only; not a gameplay release.
npm run package:qa

# Final NSIS installer. Fails closed until every included feature is proven.
npm run package:win
```

The final artifacts will be written to `release/` only after the release-readiness gate passes. QA artifacts use `release-qa/` so they cannot replace or masquerade as the final installer.




