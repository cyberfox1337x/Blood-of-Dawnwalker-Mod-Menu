import { createHash } from "node:crypto";
import { copyFile, mkdir, mkdtemp, readFile, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createSaveEditor } from "../electron/saveEditor.ts";

const cyberfox1337x = Object.freeze({ function: (moduleName) => void moduleName });
cyberfox1337x.function("verify_dawnwalker_copied_save_recovery");

async function inventory(directory) {
  const records = [];
  for (const entry of (await readdir(directory, { withFileTypes: true })).filter((entry) => entry.isFile()).sort((left, right) => left.name.localeCompare(right.name))) {
    const bytes = await readFile(join(directory, entry.name));
    records.push({ name: entry.name, sizeBytes: bytes.length, sha256: createHash("sha256").update(bytes).digest("hex") });
  }
  return records;
}

async function main() {
  const [sourceArgument, outputArgument] = process.argv.slice(2);
  if (!sourceArgument || !outputArgument || process.argv.length !== 4) throw new Error("Usage: node scripts/Verify-DawnwalkerSaveRecovery.mjs <read-only-source-save-directory> <evidence-json-path>");
  const sourceDirectory = resolve(sourceArgument);
  const outputPath = resolve(outputArgument);
  const sourceBefore = await inventory(sourceDirectory);
  const fixtureDirectory = await mkdtemp(join(tmpdir(), "dawnwalker-copied-save-proof-"));
  const saveDirectory = join(fixtureDirectory, "saves");
  await mkdir(saveDirectory);
  for (const entry of sourceBefore) await copyFile(join(sourceDirectory, entry.name), join(saveDirectory, entry.name));
  // This callback only authorizes our isolated copied directory, never the live game saves.
  const editor = createSaveEditor({ saveDirectory, backupDirectory: join(fixtureDirectory, "backups"), isGameRunning: async () => false });
  const saves = await editor.listSaves();
  const eligible = saves.filter((save) => save.format === "DSAV compressed envelope");
  if (eligible.length < 2) throw new Error("At least two real save slots with the observed DSAV envelope are required.");
  const target = eligible.find((save) => save.fileName === "ManualSave2.sav") ?? eligible[0];
  const replacement = eligible.find((save) => save.fileName !== target.fileName && save.sha256 !== target.sha256);
  if (!replacement) throw new Error("Two distinct real save contents are required for the restoration proof.");
  const originalBackup = await editor.createBackup({ fileName: target.fileName, expectedSha256: target.sha256 });
  for (const entry of originalBackup.files) {
    const extension = entry.name.slice(entry.name.lastIndexOf("."));
    await copyFile(join(sourceDirectory, replacement.fileName.replace(/\.sav$/, extension)), join(saveDirectory, entry.name));
  }
  const changed = await editor.inspectSave(target.fileName);
  const request = { fileName: target.fileName, backupId: originalBackup.backupId, expectedSha256: changed.sha256 };
  const preview = await editor.previewRestore(request);
  const restored = await editor.restoreBackup({ ...request, previewToken: preview.previewToken });
  const targetInventory = await inventory(saveDirectory);
  const zeroCopiedDirectoryDifferences = JSON.stringify(targetInventory) === JSON.stringify(sourceBefore);
  const sourceUnchanged = JSON.stringify(await inventory(sourceDirectory)) === JSON.stringify(sourceBefore);
  const recoverySaveHash = createHash("sha256").update(await readFile(join(restored.recoveryBackup.backupPath, target.fileName))).digest("hex");
  const evidence = {
    schemaVersion: 1,
    checkedAt: new Date().toISOString(),
    scope: "Isolated copies of real saves; original directory was read only. No gameplay field edits or game reloads were performed.",
    fixtureDirectory,
    inspectedSaveCount: saves.length,
    recognizedEnvelopeCount: eligible.length,
    metadataSaveVersions: [...new Set(saves.map((save) => save.metadata?.saveVersion))],
    metadataBuildVersions: [...new Set(saves.map((save) => save.metadata?.buildVersion))],
    sourceFileCount: sourceBefore.length,
    sourceUnchanged,
    zeroCopiedDirectoryDifferences,
    targetFile: target.fileName,
    initialSha256: target.sha256,
    replacedWithFile: replacement.fileName,
    replacementSha256: changed.sha256,
    restoredSha256: restored.inspection.sha256,
    recoverySaveHash,
    recoveryMatchesReplacement: recoverySaveHash === changed.sha256,
    companionCount: originalBackup.files.length,
    originalBackupPath: originalBackup.backupPath,
    recoveryBackupPath: restored.recoveryBackup.backupPath,
    editableGameplayFields: [],
    gameplayVerification: "Not verified in game",
  };
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
  if (!sourceUnchanged || !zeroCopiedDirectoryDifferences || !evidence.recoveryMatchesReplacement || evidence.restoredSha256 !== evidence.initialSha256) throw new Error("Copied-save recovery proof failed; inspect the evidence JSON and preserved fixture directory.");
  process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
}

await main();
