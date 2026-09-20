# Current-runtime installer integration — September 19, 2026

## Outcome

A separate current NSIS installer candidate now targets the actual imported runtime on Steam build25232147 / CL258504. The old production pipeline remains intact for historical pilot evidence. This candidate is not a final release: the current acceptance gate still has open features/performance review, startup stability, and an actual NSIS install/uninstall roundtrip.

Candidate: `release-current-installer-qa/Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe`. Exact delivered hash and unsigned status are in `installer-package-verification.json` beside this report. The candidate was extracted and its embedded bytes checked, not installed on the live machine by this agent.

## Implementation

- `installer/DawnwalkerImportedRuntimeInstaller.ps1`: reuses the existing Steam discovery, exact executable/signature checks, compatible-loader detection, semantic configuration ownership, per-file backups, atomic copies, transaction rollback, repair, and uninstall engine. Adds the current build constants and imported-manifest validator. Uses separate `ProgramData/Cyberfox1337x/BloodOfDawnwalkerModMenu/ImportedRuntime` ownership, refusing overlap with an existing legacy managed runtime. Requires both EngineTick and EndPlay hooks. Explicitly imports the executing PowerShell's Security module, avoiding inherited PowerShell7 module-path interference with Windows PowerShell5.1.
- `scripts/Prepare-DawnwalkerImportedRuntime.ps1`: creates a deterministic staged installer payload from the pinned UE4SS archive and exact74-file imported manifest. Does not read or overwrite the installed game. The normalized installer payload has436 files. Existing exact loaders receive the overlays/dependency; unrelated mods and later unrelated configuration edits remain preserved by shared semantic ownership.
- `installer/current-build.mjs` and `installer/current-installer.nsh`: separate current NSIS configuration. Omits the old runtime archive/overrides/helper; retains only its old `official-build.json` because the existing desktop legacy inspector still reads that contract and must keep legacy controls gated. Current loader/imported resources are separate. Preflight checks game closed and exact signed executable before replacing the desktop application. Upgrade uninstalls preserve runtime ownership; the new helper updates it transactionally. A normal uninstall restores its recorded baseline.
- `scripts/Assert-DawnwalkerImportedReleaseReady.mjs`: fails closed on missing/open/duplicate acceptance, changed files, wrong game identity, missing evidence, or evidence paths outside the repository. Binds all current source and compiled desktop files plus payload/installer contracts. New files invalidate stale proof. Required scopes: features, performance, lifecycle, startup-stability, installer-roundtrip. Only the three previously user-accepted save-dependent exceptions can be recorded, each with a hashed approval artifact.
- `scripts/Assert-DawnwalkerImportedInstaller.mjs`: extracts the actual NSIS executable, handles current direct-file and historical nested7z layouts, checks x64, current runtime byte identity, all74 imported files, and all118 compiled desktop files against app.asar. Reports actual Authenticode status.
- `package.json`: adds explicit current preparation/testing/readiness/packaging commands without changing the legacy pipeline.
- `qa/dawnwalker-imported-release-proof.json`: incomplete evidence ledger with current hashes and only the positively observed loaded-save lifecycle marked passed. Open entries remain open; no acceptance fabricated.

## Verification

- `npm run build`: passed; existing large renderer bundle warning remains.
- `npm run lint`: passed.
- `npm test`:71 Vitest files /624 tests, then11 Node tests passed.
- `npm run test:package-contract`: existing legacy contract passed unchanged.
- `npm run test:runtime:current`: passed on Windows PowerShell5.1, plus earlier PowerShell7 execution. Exercises exact build rejection,74-file coverage, both hooks, full436-file staging, install/repair/uninstall, preservation of original Lua bytes and HookEndPlay setting, later unrelated user edits, injected second-copy failure rollback, and four malformed-metadata rejections.
- `npm run test:release:current`: two tests passed, covering acceptance scopes, tampered evidence, traversal, wrong build, changed installer, and newly added source/build files.
- Actual running-game preflight: refused with close-game message before mutation.
- Final NSIS compile including upgrade guard: passed.
- Actual candidate extraction: passed; see JSON evidence.
- `npm run verify:release:current`: exits1 as intended while open scopes remain.

## Transaction boundary

The game-runtime transaction restores the prior runtime on a write failure; this was fault-tested. NSIS desktop extraction/registration is a separate transaction boundary: a rare failure after app replacement can leave the newly copied menu requiring an installer retry. Preflight catches known running-game/wrong-build/legacy-ownership failures before app replacement. Upgrade teardown no longer removes the previous runtime first. Do not claim complete system-level atomic installation or successful real install/uninstall until the native roundtrip is observed.

## Commands

`npm run prepare:runtime:current`, `npm run test:runtime:current`, `npm run test:release:current`.

Final gated production build: `npm run package:current`. This checks acceptance before writing `release-final` and verifies the completed installer afterwards.

Candidate inspection: `node scripts/Assert-DawnwalkerImportedInstaller.mjs release-current-installer-qa`.

Before a real install/uninstall test, coordinate with the live operator, confirm the game is closed, preserve the exact current app/runtime/config/save baseline, and validate restoration. The loaded-save lifecycle evidence lives alongside this report.

## Signature audit

Every authored code file is signed: `DawnwalkerImportedRuntimeInstaller.ps1`, `DawnwalkerImportedRuntimeInstaller.Tests.ps1`, `Prepare-DawnwalkerImportedRuntime.ps1`, `current-build.mjs`, `current-installer.nsh`, `Assert-DawnwalkerImportedReleaseReady.mjs`, `Assert-DawnwalkerImportedReleaseReady.Tests.mjs`, `Assert-DawnwalkerImportedInstaller.mjs`. `package.json` retains its signature property. Generated INI and mods.txt configuration use comment-only function-style markers because their parsers do not allow executable declarations. Original copied Lua files preserve their signatures.

After the September19 quest-read recovery source change, the earlier NSIS QA candidate remains preserved but is superseded as an application build candidate. Its recorded hash still identifies its original contents; it does not include the newer transport fix. Do not present it as the final current release or retry native installation after the canceled UAC without renewed user authorization. The unpacked release-current update and its new hash are recorded separately in read-timeout-package-consistency.json after repackaging. Production gate source/build hashes must be refreshed only with reviewed acceptance evidence for that exact build.

## Read-recovery QA candidate

A separate current candidate now includes the read-only timeout recovery and finite-callback pre-dispatch guard:

`release-current-installer-qa-read-recovery/Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe`

SHA-256: `526BD2038E80C2CD20B3C97965D5B3C0C5900601047E933CDEECE469DC58E16B`. Authenticode: NotSigned. The earlier candidate is preserved.

NSIS compilation passed. Independent extraction verified82current-runtime resource files,118compiled desktop files and74imported runtime files. Its app.asar SHA-256 `92CC51C3FD148966E0160AA2B3C6728A677D4A7737C4854B438CAD4B42B08F71` exactly matches the currently tested release-current package. Evidence: `read-recovery-nsis-build.log`, `read-recovery-installer-verification.json`, `read-recovery-installer-hashes.json`, `read-recovery-installer-signature.json`.

This is still a QA candidate. No installation/UAC was attempted, no actual native roundtrip is claimed, and the production evidence gate is not bypassed. Visible foreground CPU remains above2% in the measured UIAutomation environment; background and accessibility-disabled diagnostic results are not substituted for that criterion. D-8 has now reproduced with an immediately preceding unmodded process and is documented separately by the live operator; it cannot be labeled a proved mod-loader regression or a solved startup problem.

## Authorized native retry and discovered formatting defect

The user authorized retry on September 19. The read-recovery NSIS candidate installed successfully (exit 0), reported installed-healthy, and installed the exact tested app.asar. Rerunning it also exited 0, remained healthy, and preserved original ownership/backup metadata across all 77 managed files. Native uninstall completed; the actual temporary uninstaller processes exited, app and registration were removed, and managed installation state was removed.

The resulting 4,081-file comparison found two byte differences: UE4SS-settings.ini and Mods/mods.txt. Their lines were unchanged, but Windows PowerShell 5.1 semantic restoration added a UTF-8 BOM and normalized line endings. All 50 save files were unchanged. Evidence: retry-installer-*-result.json, retry-upgrade-ownership.json, retry-installer-restoration.json and uninstall-config-byte-difference.json. This is not an exact-restoration pass.

The two uninstall outputs were preserved in QA. Both original files were then restored from independently verified baseline backups; manual-baseline-restored-after-first-roundtrip.json confirms all 4,081 runtime files and 50 saves match, and no managed app remains. The engineering lead is implementing exact baseline restoration when an owned semantic file has no subsequent edits, retaining per-key restoration when unrelated user edits must be preserved. A rebuilt candidate must repeat the native roundtrip.

Corrected candidate: release-current-installer-qa-byte-restore/Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe, SHA256 980F746F4A634D36B56A828DEC0C82E8729559F7821F40B357EC08F79196B146, unsigned. Both Windows PowerShell 5 installer suites pass the new exact-byte regression and repair-with-unrelated-edits cases. Independent extraction verifies 82 runtime resources, 118 compiled desktop files and 74 imported files. The desktop archive/executable are unchanged; only installer restoration behavior changed. Native validation is underway and must be recorded separately from these offline passes.

The corrected-candidate UAC prompt was canceled before setup started (byte-restore-native-install.json). No actual corrected-build roundtrip is claimed. Complete-NativeInstallerRoundtrip.ps1 -InstallFirst is prepared for one administrator-approved cycle, with exact candidate pin, existing-baseline preflight, healthy install/repair checks, preserved ownership, bounded waits and actual temporary-uninstaller-worker exit observation. Verify-NativeInstallerRestoration.ps1 compares all 4,081 protected runtime files and 50 saves plus desktop registration/state removal. Both are signed QA helpers; the combined helper passed syntax review but has not yet been executed.
