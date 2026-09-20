# Dawnwalker read-only reflection discovery

`cyberfox1337x.function("dawnwalker_reflection_discovery_document")`

This kit identifies the user's official Steam installation and stages a reversible, offline-only way to collect Unreal reflection metadata. It does not patch `Dawnwalker.exe`, decrypt or rewrite `.pak/.ucas/.utoc` containers, bypass Steam/DRM, disable protections, or claim that the menu's proposed game features work.

## Pinned evidence

- Steam app `3751260`, build `25014996`, depot manifest `116071877880222957`.
- Install: `C:\Program Files (x86)\Steam\steamapps\common\The Blood of Dawnwalker`.
- Executable: `Dawnwalker\Binaries\Win64\Dawnwalker.exe`, 176,484,216 bytes, SHA-256 `31D6271093358CA859C5D98CD5BF226113285FED41532F3B76881DDA7BE8278A`.
- Authenticode is valid and published by Rebel Wolves; file/engine version is Unreal Engine 5.5.4 (`dw1-pc-256181-shipping-patch2-all-CL-256181`).
- The completed Steam manifest totals 58,350,822,521 bytes. Content uses locked IoStore containers; they remain read-only.
- Official experimental zDEV UE4SS `v3.0.1-1111-g97b7e501`: 44,605,660 bytes, SHA-256 `8C2E28BB1479CBEA7BF5A3C16E027580D9E71D21606971B5BD103A20BA94C617`.
- No Dawnwalker custom profile exists in the inspected official config pack. No known anti-cheat filename/module was observed, but absence is not proof; all gates remain fail-closed.
- At capture time Dawnwalker PID 25544 was running. Nothing was installed.

The complete machine-readable pin is in `official-build.json`. Proposed UI controls are inventoried in `feature-contract-matrix.json`; every game-changing control remains `pending-reflection` until it has an exact reflected target, setter/hook, readback, disable/rollback path, and an offline test.

## Safe procedure

Run these commands from this directory in PowerShell. Stop immediately on any mismatch, protection marker, crash, or new game update. The wrapper handles its internal confirmation call; do not append a shell-specific `-Confirm:$false` argument.

1. Close Dawnwalker normally. Do not kill it through this kit.
2. Verify the exact build and the stopped-process gate:

   ```powershell
   .\Verify-DawnwalkerOfficialBuild.ps1 -RequireStopped -AsJson
   .\Install-DawnwalkerReflectionTools.ps1 -Action VerifyPayload
   ```

3. Preview the transaction, then explicitly install the inert smoke profile:

   ```powershell
   .\Install-DawnwalkerReflectionTools.ps1 -Action Install -WhatIf
   .\Install-DawnwalkerReflectionTools.ps1 -Action Install
   ```

   Install first backs up `%LOCALAPPDATA%\Dawnwalker\Saved` plus any existing `dwmapi.dll` and `ue4ss` targets into `state\backups\<transaction>`. Existing targets require `-ReplaceExisting`. Only the verified zDEV archive is extracted; optional/action mod directories and `mods.json` are stripped. First-run settings have every `Hook* = 0`, every mod including Keybinds off, cache off, load-all-assets off, and engine override 5.5.

4. Launch the game offline to the main menu only, confirm it remains stable long enough to create `ue4ss\UE4SS.log`, then exit normally. Review the fresh log. Do not promote if it contains startup failures, access violations, or a crash.
5. With the game stopped, promote the separately backed-up restricted dump profile:

   ```powershell
   .\Install-DawnwalkerReflectionTools.ps1 -Action PromoteDumpProfile -ApproveCleanSmokeLog
   ```

   Promotion enables only the restricted asynchronous Keybinds dispatcher; all bundled action mods remain off. The dump profile uses cache off, guarded slow UObject iteration, module-relative offsets, engine 5.5, GUI off, every Unreal hook off, and load-all-assets off.

   Compatibility evidence from 2026-09-02: an earlier all-hooks-on dump profile caused an access violation in `Dawnwalker.exe+0x11E8C6E` before any dump key was sent. That transaction was rolled back completely. Do not restore or retry the all-hooks-on profile; the restricted profile now preserves the stable all-hooks-off smoke settings.

6. Launch offline and request only the needed metadata, one operation per run if stability is uncertain:

   - `Ctrl+J`: object dump
   - `Ctrl+H`: C++ headers
   - `Ctrl+NumPad9`: UHT-compatible headers
   - `Ctrl+NumPad6`: USMAP
   - `Ctrl+NumPad5`: JMAP

   Static mesh and actor dumping are deliberately unbound. Do not turn on load-all-assets. Exit normally after the dump and preserve `UE4SS.log` with the generated output.
   After copying the generated text/headers into a workspace folder, build a bounded anchor index without scanning binary maps:

   ```powershell
   .\Analyze-DawnwalkerReflectionDump.ps1 -DumpRoot '.\captured-dump' -OutputPath '.\captured-dump\reflection-index.json'
   ```

   The index is triage evidence only. Each candidate still needs an exact live object/function, readback, rollback, and isolated offline test before its capability is advertised.
7. Roll back after capture:

   ```powershell
   .\Install-DawnwalkerReflectionTools.ps1 -Action Rollback -WhatIf
   .\Install-DawnwalkerReflectionTools.ps1 -Action Rollback
   ```

   Rollback refuses while the game runs, captures the current loader tree (including generated output), restores the exact preinstall `dwmapi.dll`/`ue4ss` snapshots, verifies their SHA-256 inventories, and retains the save backup without overwriting newer saves.

## Isolated bridge pilot

After completing reflection capture and rolling it back, use [BRIDGE-PILOT.md](BRIDGE-PILOT.md) for the separately gated one-hook bridge pilot. It requires a new exact inert-smoke transaction and a newly reviewed clean log; a prior dump promotion or capture transaction cannot be reused. The pilot remains analysis-only and is not production/release evidence by itself.

## Runtime boundary

The signed executable contains useful search anchors such as `ADawnwalkerPlayerCharacter`, Dogwood ability/combat/inventory/map/quest modules, health/stamina accessors, currency methods, time/weather names, travel markers, NPC/horse types, and quest events. Strings alone do not establish object paths, writable properties, valid calls, offsets, or reversibility. They are recorded only as unverified search anchors in the feature matrix. No God Mode, inventory, teleport, world, combat, NPC, quest, or visual effect is implemented or represented as live until the reflection evidence gate passes.

Official references: [UE4SS experimental release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest), [installation guide](https://docs.ue4ss.com/dev/installation-guide.html), [dumpers](https://docs.ue4ss.com/dev/feature-overview/dumpers.html), and [UHT header generation](https://docs.ue4ss.com/dev/guides/generating-uht-compatible-headers.html).
