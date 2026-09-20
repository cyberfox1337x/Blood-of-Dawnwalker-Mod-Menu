> Final outcome: exact installer passed native install/repair/uninstall and release verification. See [FINAL-RELEASE-READINESS.md](FINAL-RELEASE-READINESS.md) and [Nexus upload verification](NEXUS-UPLOAD-VERIFICATION.json). Earlier entries below are preserved chronological evidence, including superseded candidate status.

# Final-product validation in progress — 2026-09-19

This folder records actual game observations, not release certification. D8 startup stability and the packaged installer roundtrip remain open.

## Protected test baseline

- All 50 save files were copied to `saves-before/`; SHA256 and sizes are in `saves-before.json`.
- Disposable gameplay target: **Quicksave2**, metadata date `2026.09.03-00.54.36`, play time 5490 seconds. The game displays September 3, 12:54:36 AM, 1h31m. File modification dates do not identify the displayed save.
- `quicksave2-selection.png` records selection. `quicksave2-connected.json` and `quicksave2-loaded.png` record the loaded runtime and screen.
- No gameplay setters were invoked during the first loaded-save lifecycle trial. All 50 save hashes matched after quitting (`saves-after-loaded-quit.json`).

## Startup and shutdown trials

| Trial | Precondition | Observation | Evidence |
|---|---|---|---|
| 1 | Prior externally-ended session without positive quit marker | Started, selected Quicksave2, connected, dismissed tutorial, quit through game menu; shutdown marker and process exit verified | `loaded-lifecycle-result.json`, `before-loaded-quit.json`, `after-loaded-quit.json` |
| 2 | Normal loaded-save exit | Reached main menu, quit through game menu; marker `quit` emitted. Process lingered briefly after window disappeared before exiting | `boot2-title.jpg`, `boot2-before-quit.json`, `boot2-after-quit.json` |
| 3 | Normal title exit; launch requested while previous process was briefly finishing shutdown | Fresh session reached opening logos with heartbeat, intentionally force-closed before loading any save | `boot3-before-interruption.jpg`, `boot3-before-interruption.json`, `boot3-interruption.json` |
| 4 | Confirmed process absent after trial 3 | Fresh heartbeat; reached main menu, then intentionally force-closed without loading a save | `boot4-title.jpg`, `boot4-before-interruption.json`, `boot4-interruption.json` |
| 5 | Confirmed process absent after title-stage force-close | Black loading screen, no fresh session/heartbeat, CPU delta 0.078125 seconds over 3 seconds at approximately +37 seconds. Full dump captured before timeout; stalled process subsequently terminated | `boot5-hang-screen.jpg`, `boot5-hang/process.json`, `boot5-hang/Dawnwalker-full.dmp`, `boot5-hang/dump-hash.json` |

The early-logo interruption in trial 3 does not reproduce the earlier reported condition: force-close **after title screen**. Trial 5 reproduced that condition. **D8 remains open.** All 50 save files still match the original baseline after trial 5 (`saves-after-boot5-result.json`). Space is pressed during every launch; cinematic skipping is inconsistent through the supported computer-control input, although the same key works on title/tutorial/quit prompts.

## Diagnostics

`Capture-StartupHang.ps1` requires an explicit game PID, verifies the executable path, refuses to overwrite an existing dump, and captures full process memory plus handles and thread information for offline debugging. Syntax validated and actual capture exited 0. The dump is 7,090,112,146 bytes; SHA256 `08AF49A4282D9D414D498355516AB0C33A1B05E19460D05989382F1621ECC847`. It does not patch the executable, runtime, settings, or saves. Dumps remain local diagnostic artifacts and should not be included in a distributed installer.

Earlier sparse-dump unwind evidence lives in `../continuation-20260919/d8-evidence-audit/`. It confirms waiting threads, but does not prove the old FSR ownership claim. Preserve that distinction until direct evidence establishes the dependency.

## Installer roundtrip preparation

`installer-baseline/` preserves all 4,081 existing runtime/proxy files (506,240,084 bytes); identities are in `installer-baseline-hashes.json`. The game and desktop menu were closed, and the actual current helper's exact-build preflight passed. No existing managed imported runtime or desktop-menu uninstall registration was found (the Steam game's registration is unrelated and must remain untouched).

Native candidate: `../../release-current-installer-qa/Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe`, SHA256 `35CFC6E473B15075B2C1D7595FE5DEFE3348FFF637B94765E322C0D6B114AEAC`, unsigned. Requested `/S` without a force-run flag: the inspected electron-builder NSIS template suppresses application auto-launch in this mode. Windows secure-desktop administrator approval was canceled at 11:59:54; Start-Process reported the operation canceled by the user. **The installer did not start**, and no managed install state was created. No retry or alternate installation route was attempted. `native-installer-result.json` records this boundary. See `INSTALLER-INTEGRATION.md` for candidate build and fixture evidence.

## Title-ready deferred-loading diagnostic (in progress)

The original proxy is held intact at `dwmapi.dll.d8-title-load-20260919`; `deferred-load-proxy-state.json` records its hash and mandatory restoration. This is a controlled diagnostic, not an adopted product loader.

Trial 1: PID 29724 launched without the proxy, actual main menu positively observed (`deferred1-title-before-load.jpg`), then the build/hash-gated `late_load_ue4ss.py --pid 29724 --execute --title-ready` loaded the pinned UE4SS module. Quicksave2 selected and loaded, fresh ready session `1789833928-529673-1`. Desktop God Mode ON produced native `ON: health, stamina and blood resource locks active.`, OFF produced `OFF: owned resources released and restoration verified.` Screenshots and native JSON are `deferred1-god-on/off.*`. One successful trial does not resolve D8; repeated forced-close/restart tests are pending.

Trial 2: after forced close of the loaded first deferred session, process 6972 launched with proxy absent and **zero UE4SS modules**, but stalled at the black spinner before late loading was attempted. `deferred2-unmodded-hang/loader-absence.json` and `loaded-modules.json` establish that boundary. A second full dump completed successfully; screenshot `deferred2-unmodded-hang-screen.jpg`. The generic capture script copied the previous session's UE4SS log and runtime JSON: those two files are stale and do not describe process 6972. This disproves deferred loading alone as an adequate fix. It does not establish whether the previous modded session contributes persistent state.

After capturing evidence, process 6972 was terminated. The original proxy was restored at 12:13:54 with its SHA256 unchanged; `deferred-load-proxy-state.json` now records restoreRequired=false. No diagnostic loader change was adopted. Fresh performance sampling separately found idle CPU above the declared target; see `performance-current-idle.json` and `performance-current-read.json`. Performance acceptance remains open.

## New connected-menu recovery defect

After restored proxy startup16756, positively selected and loaded Quicksave2, native session1789834462-167381-1 stayed ready with advancing heartbeat. The shipped menu remained unavailable after more than20seconds. Preserved `restored-ready-ui-unavailable.jpg/.json` and `restored-pending-command.txt`: automatic DWQuestReadback.refresh request63001156-b7e4-4760-8c5c-1a6e710c54d1 belongs to the new session, was written12:19:57, expired12:20:02, but native operation remained null. This is not stale accessibility text or the old diagnostic difficulty requests. Transport inspection found expired pending requests remain held indefinitely. A narrowly allowlisted read-only timeout recovery regression/fix is being implemented; gameplay mutations must not be blindly retried.

Read recovery and callback-queue guard are now implemented in the desktop transport/contract with regressions. Final checks:635Vitest tests across71files and11Node restoration checks passed; lint/build and mandated release-current packaging passed. The packaged118compiled files match and222runtime identity checks passed. No Lua payload changed. Current app.asar92CC51C3FD148966E0160AA2B3C6728A677D4A7737C4854B438CAD4B42B08F71; EXEF128B57976E0391D05F728424FCE47DE2A55CBF023AA383BB9AD9E16A73A3F9C, unsigned. Old installer candidate is superseded and must be rebuilt before any final installation test.

Normal packaged launch connected to the same loaded Quicksave2 session. Actual UI God Mode ON/OFF commands returned native locks-active and restoration-verified labels (`read-recovery-normal-god-on/off.jpg/.json`). These prove normal dispatch/restoration after the desktop change; the precise missing-ACK recovery is separately covered by the recorded regression, not claimed as a reproduced live timeout after the fix.

CPU attribution: main process dominates; renderer/graphics processes contribute little. A bounded loopback-only Inspector session recorded JavaScript predominantly idle, while native CrBrowserMain consumes most measuredCPU. Inspector process was closed and port9229 confirmed closed before normal relaunch. No speculative JavaScript cache/renderer change was made. Observer/accessibility effects are being investigated before performance acceptance.

## Clean predecessor startup comparison

After a normal modded loaded-session exit, two consecutive unmodded sessions reached the main menu. Both were deliberately interrupted there. The second restart (PID30108) reproduced the black-spinner hang with proxy absent and zero UE4SS modules, after an immediately preceding unmodded session. Its full dump shows the same game/render/RHI wait RVAs and generic hang bucket as earlier cases. Details: clean-unmodded3-hang/ANALYSIS.md. This narrows the attribution boundary; D8 is not fixed and no speculative game patch was adopted. The original proxy has been restored unchanged. All50 saves matched immediately before this no-save-loaded comparison.

### Current candidate shutdown checkpoint

The read-recovery QA installer was rebuilt and independently extracted; see INSTALLER-INTEGRATION.md for hash and exact parity counts. Final loaded Quicksave2 session PID19344 quit normally, with shutdown=quit and actual process exit. At 13:19 all 50 save files and actual file count matched saves-before.json; see read-recovery-final-shutdown-save-check.json. Normal menu remains open without diagnostic launch flags. Foreground CPU remains 2.106% and is not accepted by the 2% criterion. Renewed native installer authorization is pending after the earlier canceled UAC; no retry was attempted.

