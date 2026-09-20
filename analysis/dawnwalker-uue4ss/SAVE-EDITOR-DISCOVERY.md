# Dawnwalker save editor discovery and recovery

`cyberfox1337x.function("dawnwalker_save_editor_discovery")`

Inspected 2026-09-05 America/New_York. This is an independent save inspection and recovery implementation. Gameplay value editing is incomplete and unavailable.

## Reference and permissions

[Blood of Dawnwalker Save Editor](https://www.nexusmods.com/thebloodofdawnwalker/mods/43), created and uploaded by **FullTimePatriot**, advertises time, money, health, and daytime stat points. The page identifies version 6, updated September 5, 2026, and mentions a repair for lighting problems from older editor versions. The [files page](https://www.nexusmods.com/thebloodofdawnwalker/mods/43?tab=files) lists one 9.9 MB DawnwalkerSaveEditor archive. No format specification or public source link was provided on those pages.

Modification and asset use require the creator's permission; redistribution is prohibited. No reference code, executable, codec, or asset was copied, reused, or redistributed. Settings attribution should say **Feature inspired by**. This author has no additional named contributors on the inspected page. Credit does not grant reuse permission.

## Local evidence

- Steam save directory: `%LOCALAPPDATA%\Dawnwalker\Saved\SaveGames`.
- Twelve gameplay `.sav` files were inspected through isolated copies, plus corresponding `.meta` and `.png` companions. `RebelSettings.sav` is settings data and is excluded from the gameplay save list.
- All twelve gameplay files start with `DSAV`; an observed `DSAVCHNK` marker begins at byte 32. They are not standard Unreal `GVAS` tagged-property saves. Recognizing these markers identifies only an envelope; it does not establish payload validity, chunk layout, checksums, field offsets, or field meanings.
- All twelve companion metadata files identify save version 134, game version 5, and build 256181. These are older saves; the currently pinned executable build is separately documented in the project README. Save metadata alone does not prove compatibility with the current executable.
- Captured `Persistency/Public/ESaveVersion.h` includes `OodleCompressionByDefault` and `SavingTimeAsSignedInt`. This supports the compression/time-serialization investigation but does not specify an editable field layout.
- No standalone Oodle/`oo2` codec file was found in the installed game tree. The reference describes no codec interface. No speculative decompression or byte-offset mutation was attempted.
- `.meta` contains display fields such as `Day`, `PlayTime`, and `SaveName`; those are presented as read-only metadata. They are not treated as authoritative gameplay time, currency, health, or stat points.

## Implemented behavior

`electron/saveEditor.ts` lists and inspects gameplay saves, computes SHA-256, displays bounded metadata, creates verified backups of the selected `.sav` and its existing `.meta`/`.png`, lists backup history, previews exact restoration, and restores the previewed files with a pre-restore recovery backup.

The main process supplies a process-detection callback. Without it, or if its result is unavailable, mutations fail closed. Backup and restore require the game stopped, a stable observation interval, and a current selected-save hash. Restore also uses a five-minute one-use preview bound to every companion and backup hash. A lock serializes cooperating menu instances; symbolic links, junctions, hardlinks, path traversal, oversized files, tampered backup inventories, and mismatched companion sets are rejected. Backups remain outside Steam's save directory and include a flushed manifest and per-file hashes. Unfinished backup directories never appear in normal backup history.

Each companion is staged and atomically replaced separately, with process and file-state checks before each replacement. A game launch, cloud sync, or filesystem failure during the transaction can interrupt the set. Detected racing writes are never overwritten by an attempted automatic rollback. The operation reports the retained complete recovery directory. This is not a cross-file atomic transaction and does not claim to lock out an external process that starts between the final process check and filesystem replacement.

## Recovery procedure

1. Close Dawnwalker normally and wait for Steam cloud synchronization to finish. Keep the game closed through the operation.
2. In the integrated save section, inspect the selected slot, create a backup, and record its displayed location.
3. Select the desired backup and review the exact filenames and original/restored hashes before applying restoration. The current slot is backed up automatically first.
4. If restoration stops after a partial replacement, keep the game closed, refresh the slot, select the newly created pre-restore recovery backup, preview it, and restore the complete set. Unit coverage proves this recovery path. For a missing or corrupted companion set that the integrated restore refuses, manually copy the complete `.sav`/`.meta`/`.png` set from the displayed recovery directory with the game closed; preserve the interrupted files first.
5. Launch Dawnwalker and load that save. The active gameplay session is never changed by the save tool. Save reload and gameplay effects remain **Not verified in game** for this implementation.
6. After an application crash, a stale `.dawnwalker-save-editor.lock` can remain. Remove it only after closing every menu instance and the game; the tool never deletes another process's lock automatically.

## Validation

- `npx vitest run src/saveEditor.test.ts`: sixteen tests cover format refusal, byte preservation, metadata bounds, backup integrity/history, stopped-process gates, path and link rejection, stale/save-sync observations, preview enforcement, companion races, repeated exact restoration, cross-instance locking, a process start between companion replacements, and recovery of that partial set.
- `npx tsc -p electron/tsconfig.json --noEmit` and targeted ESLint passed.
- `node scripts/Verify-DawnwalkerSaveRecovery.mjs "$env:LOCALAPPDATA\Dawnwalker\Saved\SaveGames" qa/dawnwalker-save-recovery-20260905.json` ran with Node 24. It copies its read-only source to a fresh temporary directory before any mutation.
- `qa/dawnwalker-save-recovery-20260905.json`: all twelve envelope observations; ManualSave2 plus companions backed up, replaced with copies of another real slot, previewed and restored; all 38 copied files match the source again; the complete source inventory is unchanged; pre-restore recovery bytes match the replaced slot.
- No new package dependency, live save mutation, gameplay field editing, or game reload validation occurred.

## September 6 format advancement

The local compression blocker is now resolved for research. An expanded inspection found the officially installed Unreal Engine 5.6 Oodle 2.9.10 runtime at `C:\Program Files\Epic Games\UE_5.6\Engine\Source\Programs\Shared\EpicGames.Oodle\Sdk\2.9.10\win\redist\oo2core_9_win64.dll`, SHA-256 `111A505E64A3BF1B89C05AAB2DD16306BC2267A5EA3F0C9722A3B6152091CE1C`. The probe calls this existing DLL in place, using API declarations from the adjacent official `EpicGames.Oodle/Oodle.cs` and the installed Oodle headers. No DLL or licensed SDK code is bundled or redistributed. The [Epic Oodle announcement](https://www.unrealengine.com/blog/oodle-now-free-to-use-in-unreal-engine-via-github?lang=en-US) documents its Unreal integration; a desktop release must resolve its own codec installation/distribution arrangement separately.

`probes/dawnwalker_save_format.py` independently validates the observed save-version-134/game-version-5/container-mode-2 format:

| Region | Verified structure |
|---|---|
| Bytes 0–31 | `DSAV`, decoded-data start 36, uint16 save/game versions, observed mode word 2, absolute decoded NAME offset, DWNT offset, decoded end, encoded chunk-region length |
| Bytes 32–35 | Opening `DSAV` |
| Chunk region | Repeated `CHNK`, uint32 encoded length, uint32 decoded length, exactly that many compressed bytes; observed decoded chunks are at most 131072 bytes |
| Container tail | `VASD`, uint32 chunk count, repeated encoded/decoded length pairs matching every chunk, final `VASD`; no unexplained trailing bytes |
| Decoded NAME table | Opening `NAME`, uint32 byte length, repeated uint8-length UTF-8 names, closing `NAME` |
| Decoded DWNT table | Opening `DWNT`, uint16 record count, 16-byte records, closing `DWNT` |
| DWNT record | uint32 one-based name index, two uint16 forward links, uint32 absolute decoded offset, uint32 byte size; each location begins `SN` plus its uint16 directory index |

All table references, decoded lengths, record bounds, forward-link validity, child containment, and marker/index matches are checked. The two forward links are consistent with next-sibling and first-child relationships across the inspected corpus. This is observed-format support; unknown versions or container modes are refused.

The installed codec with `OodleLZ_Compressor_Kraken = 8` and `Fast = 3` reproduced every original compressed chunk exactly. Thirteen real save copies passed both full container parse/encode and decompress/recompress roundtrips with **identical complete save bytes and SHA-256**. The original saves were unchanged. Other compression settings produced different compressed bytes, so the probe retains the empirically reproduced setting. Evidence: `qa/dawnwalker-save-format-20260906.json`; all records have `unchangedContainerByteExact`, `recompressedByteExact`, and `recompressedPayloadByteExact` true.

The decoded corpus contains 506–812 names and 330–465 named records. `ManualSave2.sav` resolves `CharacterDevelopmentSubsystem` to a bounded 89-byte record, `AttributeSaveSystem` to 64 bytes, `TimeSystemImpl` to 42 bytes, and `InventorySubsystem` to 7492 bytes. This provides reliable record targeting without absolute-offset guesses. Captured `ESavedAttributeType.h` identifies the game's saved attribute enumeration, but its presence alone does not establish the record's serialization layout.

Historical progression quarantines also show candidate int32 values inside `CharacterDevelopmentSubsystem` corresponding to recorded levels 1/2 and Trait Points 0/22/23. Those correlations are research clues, not an authorized editing schema: a controlled same-slot one-variable save pair, inverse pair, and game reload remain required before exposing these fields.

Validation commands:

```powershell
python -m unittest discover -s analysis/dawnwalker-uue4ss/tests -p test_dawnwalker_save_format.py -v
python analysis/dawnwalker-uue4ss/probes/dawnwalker_save_format.py `
  --source-directory "$env:LOCALAPPDATA\Dawnwalker\Saved\SaveGames" `
  --codec 'C:\Program Files\Epic Games\UE_5.6\Engine\Source\Programs\Shared\EpicGames.Oodle\Sdk\2.9.10\win\redist\oo2core_9_win64.dll' `
  --codec-sha256 111a505e64a3bf1b89c05aab2dd16306bc2267a5ea3f0c9722a3b6152091ce1c `
  --output qa/dawnwalker-save-format-20260906.json
```

Thirteen standard-library tests pass, including every truncated synthetic prefix, oversized lengths, unsupported versions, mismatched chunk inventories, malformed names, invalid record/name references, cycles, and wrong node markers. Python syntax compilation passes. This research introduces no application dependency or gameplay write API. Decompressed binaries and unchanged recompressed research files stay in isolated temporary directories.

Next safe work: capture a known same-slot Trait Points baseline, a small verified runtime mutation, and its inverse as separate protected save copies; resolve each named record and identify all changed bytes. Then stage a bounded independent edit on a copy and verify exact unrelated decoded-byte preservation, valid re-encoding, game reload/readback, and restoration. Time additionally requires validating coupled phase/lighting state; metadata `Day` remains read-only. The codec and complete unchanged-roundtrip requirements are now proved locally; **verified semantic edits and game-load validation remain incomplete**.

## September 6 coordinated implementation checkpoint

The current user request explicitly authorizes reuse of the seven referenced creators' work with Settings credits and applicable conditions. The v6 FullTimePatriot archive remains unavailable after the coordinator's supported Computer Use navigation stopped on current-URL verification. No code or assets from that archive have been incorporated; the existing independent-inspiration attribution remains accurate. The reference was rechecked at [mod 43](https://www.nexusmods.com/thebloodofdawnwalker/mods/43): FullTimePatriot, version 6, time/money/health/daytime points, and its lighting-repair notice.

Implemented this checkpoint:

- Selected-save inspection now calls the actual desktop DSAV/native-codec pipeline and reports whether payload structure verified. The save list remains a lightweight metadata read. Inspection verifies the complete save/companion fingerprint again after decoding and reports a changed-source condition without authorizing any write.
- The TypeScript decoder now validates the complete root/child/sibling tree, rejects unreachable records and multiple-parent references, and checks every sibling stays inside its parent. All thirteen existing protected save copies pass this stricter graph validation.
- The desktop codec corpus runner at `probes/Verify-DawnwalkerDsavCodec.mjs` copies its sources into a fresh temporary directory, validates all records, performs unchanged serialization and complete native recompression, independently decodes the result, and verifies source hashes again. `qa/dawnwalker-desktop-codec-corpus-20260906.json` records thirteen successful complete byte-exact roundtrips. No codec implementation is bundled.
- `probes/compare_dawnwalker_save_records.py` prepares structural baseline/change/inverse evidence from three separately captured saves. It only compares protected copies, records subsystem-relative changes, detects incomplete inverses or varying record sizes, and never treats correlation as an editable schema.

Validation: 26 focused Vitest tests pass (`saveEditor`, `dsavContainer`, `installedOodle`), including every truncated synthetic save prefix, malformed lengths/versions/name and node tables, unsupported codec output, unchanged-chunk preservation, and existing backup/recovery races. Three new comparison tests pass; the existing thirteen Python format tests remain passing. Scoped ESLint and Electron TypeScript compilation pass. `qa/dawnwalker-selected-save-inspection-20260906.json` records actual compiled-backend inspection of protected `ManualSave2.sav`: decoded structure verified, gameplay editable fields still empty. This is backend evidence, not computer-use or game-load evidence.

Specific semantic blocker: the preserved Trait Points persistence quarantine retains the final `0` inverse save, but not the separately saved intermediate `1` bytes. Later progression quarantines correlate record values with `22`/`23` points while also changing other progression state. Those files cannot independently establish a one-variable field meaning or safe write schema. The reference archive's schema or a freshly captured known baseline/small mutation/inverse triplet is required before editable controls can be exposed. The current implementation still has **no actual gameplay value editing** and remains **Not verified in game**; this checkpoint does not satisfy the complete Save Editor request.

Reusable verification commands (from the workspace):

```powershell
npx tsc -p electron/tsconfig.json
npx vitest run src/saveEditor.test.ts src/dsavContainer.test.ts src/installedOodle.test.ts
python -m unittest discover -s analysis/dawnwalker-uue4ss/tests -p 'test_dawnwalker_save_*.py' -v
node analysis/dawnwalker-uue4ss/probes/Verify-DawnwalkerDsavCodec.mjs '<protected-save-copy-directory>' '<new-evidence-file.json>'
```

When supported interactive access is restored, acquire and inspect mod43/file394, then compare its field handling against decoded protected saves before implementation. If using runtime-generated pairs, capture a separate baseline, changed and inverse save after each ordinary save operation, including exact slot, executable identity and live field readback. Keep the game closed before staging an edited copy. Do not infer current gameplay compatibility from the successful byte-exact codec roundtrip.
