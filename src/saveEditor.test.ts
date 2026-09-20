import { createHash } from "node:crypto";
import { link, mkdtemp, mkdir, open, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createSaveEditor } from "../electron/saveEditor";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_editor_tests");

const testDirectories: string[] = [];
const SAVE_NAME = "ManualSave2.sav";

function envelope(payload = "opaque gameplay bytes untouched"): Buffer {
  const bytes = Buffer.alloc(48 + Buffer.byteLength(payload));
  bytes.write("DSAV", 0);
  bytes.write("DSAVCHNK", 32);
  bytes.write(payload, 48);
  return bytes;
}

async function fixture(isGameRunning: () => Promise<boolean> = async () => false) {
  const directory = await mkdtemp(join(tmpdir(), "dawnwalker-save-editor-test-"));
  testDirectories.push(directory);
  const saveDirectory = join(directory, "saves");
  const backupDirectory = join(directory, "backups");
  await mkdir(saveDirectory);
  const original = envelope();
  await writeFile(join(saveDirectory, SAVE_NAME), original);
  await writeFile(join(saveDirectory, "ManualSave2.meta"), JSON.stringify({ Meta: { Day: 0, PlayTime: 5685, SaveName: "ManualSave2", BuildVersion: 256181, GameVersion: 5, SaveVersion: 134, TypeString: "Manual", Quest: "unrelated" } }));
  await writeFile(join(saveDirectory, "ManualSave2.png"), Buffer.from("opaque thumbnail fixture"));
  const editor = createSaveEditor({ saveDirectory, backupDirectory, isGameRunning, settleMilliseconds: 0 });
  return { directory, saveDirectory, backupDirectory, original, editor };
}

afterEach(async () => {
  for (const directory of testDirectories.splice(0)) {
    const absolute = resolve(directory);
    if (!absolute.startsWith(`${resolve(tmpdir())}${sep}dawnwalker-save-editor-test-`)) throw new Error("Refusing cleanup outside the test directory.");
    await rm(absolute, { recursive: true, force: true });
  }
});

describe("integrated Dawnwalker save inspection and recovery", () => {
  it("identifies the observed container, exposes display metadata, and lists the verified editable fields", async () => {
    const { editor, saveDirectory, original } = await fixture();
    await writeFile(join(saveDirectory, "RebelSettings.sav"), envelope());
    const saves = await editor.listSaves();
    expect(saves).toHaveLength(1);
    expect(saves[0]).toMatchObject({ fileName: SAVE_NAME, fullPath: join(saveDirectory, SAVE_NAME), format: "DSAV compressed envelope", editableFields: ["clockMs", "health", "blood", "mutationLevel", "coin"], metadata: { day: 0, playTimeSeconds: 5685, buildVersion: 256181, saveVersion: 134 } });
    expect(saves[0].sha256).toBe(createHash("sha256").update(original).digest("hex"));
  });

  it("treats unknown and truncated saves as unsupported and refuses recovery writes", async () => {
    const { editor, saveDirectory } = await fixture();
    await writeFile(join(saveDirectory, SAVE_NAME), Buffer.from("DSAV"));
    const inspection = await editor.inspectSave(SAVE_NAME);
    expect(inspection.format).toBe("Unknown or truncated");
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspection.sha256 });
    await expect(editor.previewRestore({ fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: inspection.sha256 })).rejects.toThrow("Unknown or truncated");
  });

  it("preserves malformed companion metadata as opaque bytes instead of losing it", async () => {
    const { editor, saveDirectory } = await fixture();
    await writeFile(join(saveDirectory, "ManualSave2.meta"), "{broken metadata");
    const inspected = await editor.inspectSave(SAVE_NAME);
    expect(inspected.metadataWarning).toContain("original bytes");
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 });
    expect(await readFile(join(backup.backupPath, "ManualSave2.meta"), "utf8")).toBe("{broken metadata");
  });

  it("backs up every companion byte, verifies SHA-256, and lists persistent backup history", async () => {
    const { editor, saveDirectory, backupDirectory } = await fixture();
    const inspected = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 });
    expect(backup.files.map(({ name }) => name)).toEqual([SAVE_NAME, "ManualSave2.meta", "ManualSave2.png"]);
    for (const entry of backup.files) expect(await readFile(join(backup.backupPath, entry.name))).toEqual(await readFile(join(saveDirectory, entry.name)));
    const reopened = createSaveEditor({ saveDirectory, backupDirectory });
    expect((await reopened.listBackups(SAVE_NAME))[0].backupId).toBe(backup.backupId);
    expect(await readdir(saveDirectory)).not.toContain(".dawnwalker-save-editor.lock");
  });

  it("requires verified stopped process status, failing closed without a callback or on callback errors", async () => {
    const { saveDirectory, backupDirectory, editor } = await fixture(async () => true);
    const inspected = await editor.inspectSave(SAVE_NAME);
    const request = { fileName: SAVE_NAME, expectedSha256: inspected.sha256 };
    await expect(editor.createBackup(request)).rejects.toThrow("Close Dawnwalker");
    await expect(createSaveEditor({ saveDirectory, backupDirectory }).createBackup(request)).rejects.toThrow("Close Dawnwalker");
    await expect(createSaveEditor({ saveDirectory, backupDirectory, isGameRunning: async () => { throw new Error("process query failed"); } }).createBackup(request)).rejects.toThrow("process query failed");
  });

  it("rejects unsafe file names, backup ids, and backup roots inside the save directory", async () => {
    const { editor, saveDirectory } = await fixture();
    for (const name of ["../ManualSave2.sav", "C:\\outside.sav", "ManualSave2.sav:stream", "RebelSettings.sav"]) await expect(editor.inspectSave(name)).rejects.toThrow("gameplay .sav");
    expect(() => createSaveEditor({ saveDirectory, backupDirectory: join(saveDirectory, "backups") })).toThrow("outside");
    const inspected = await editor.inspectSave(SAVE_NAME);
    await expect(editor.previewRestore({ fileName: SAVE_NAME, backupId: "../../outside", expectedSha256: inspected.sha256 })).rejects.toThrow("verified backup list");
  });

  it("rejects stale inspected hashes and saves changing during the settle window", async () => {
    const { editor, saveDirectory, backupDirectory } = await fixture();
    const inspected = await editor.inspectSave(SAVE_NAME);
    await writeFile(join(saveDirectory, SAVE_NAME), envelope("new player state"));
    await expect(editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 })).rejects.toThrow("changed since");
    let queries = 0;
    const racingEditor = createSaveEditor({ saveDirectory, backupDirectory, settleMilliseconds: 0, isGameRunning: async () => {
      queries++;
      if (queries === 3) await writeFile(join(saveDirectory, "ManualSave2.meta"), "changed while settling");
      return false;
    } });
    const latest = await racingEditor.inspectSave(SAVE_NAME);
    await expect(racingEditor.createBackup({ fileName: SAVE_NAME, expectedSha256: latest.sha256 })).rejects.toThrow("changing or syncing");
  });

  it("restores the exact save and companion set only after preview and retains pre-restore recovery bytes", async () => {
    const { editor, saveDirectory, original } = await fixture();
    const initial = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: initial.sha256 });
    const changed = envelope("newer gameplay state");
    await writeFile(join(saveDirectory, SAVE_NAME), changed);
    await writeFile(join(saveDirectory, "ManualSave2.meta"), "newer opaque metadata");
    const current = await editor.inspectSave(SAVE_NAME);
    const request = { fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: current.sha256 };
    await expect(editor.restoreBackup({ ...request, previewToken: "fabricated" })).rejects.toThrow("Preview this exact restore");
    const preview = await editor.previewRestore(request);
    expect(preview).toMatchObject({ currentSha256: current.sha256, restoredSha256: initial.sha256, reloadRequired: true, files: [SAVE_NAME, "ManualSave2.meta", "ManualSave2.png"] });
    const result = await editor.restoreBackup({ ...request, previewToken: preview.previewToken });
    expect(result.inspection.sha256).toBe(initial.sha256);
    expect(await readFile(join(saveDirectory, SAVE_NAME))).toEqual(original);
    expect(await readFile(join(result.recoveryBackup.backupPath, SAVE_NAME))).toEqual(changed);
    expect(await readFile(join(result.recoveryBackup.backupPath, "ManualSave2.meta"), "utf8")).toBe("newer opaque metadata");
    await expect(editor.restoreBackup({ ...request, previewToken: preview.previewToken })).rejects.toThrow("Preview this exact restore");
    expect((await readdir(saveDirectory)).filter((name) => name.startsWith(".dawnwalker"))).toEqual([]);
  });

  it("detects companion races after preview even when the gameplay save hash is unchanged", async () => {
    const { editor, saveDirectory } = await fixture();
    const initial = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: initial.sha256 });
    const request = { fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: initial.sha256 };
    const preview = await editor.previewRestore(request);
    await writeFile(join(saveDirectory, "ManualSave2.meta"), "changed after preview");
    await expect(editor.restoreBackup({ ...request, previewToken: preview.previewToken })).rejects.toThrow("changed after preview");
    expect(await readFile(join(saveDirectory, "ManualSave2.meta"), "utf8")).toBe("changed after preview");
  });

  it("refuses tampered backups without modifying the original save", async () => {
    const { editor, saveDirectory, original } = await fixture();
    const inspected = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 });
    await writeFile(join(backup.backupPath, SAVE_NAME), envelope("tampered backup"));
    await expect(editor.previewRestore({ fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: inspected.sha256 })).rejects.toThrow("integrity check");
    expect(await readFile(join(saveDirectory, SAVE_NAME))).toEqual(original);
  });

  it("rejects companion additions or deletion instead of silently creating an inconsistent slot", async () => {
    const { editor, saveDirectory } = await fixture();
    const inspected = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 });
    await rm(join(saveDirectory, "ManualSave2.png"));
    await expect(editor.previewRestore({ fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: inspected.sha256 })).rejects.toThrow("Companion files differ");
  });

  it("honors a lock held by another menu and never deletes that owner's lock", async () => {
    const { editor, saveDirectory } = await fixture();
    const inspected = await editor.inspectSave(SAVE_NAME);
    const lockPath = join(saveDirectory, ".dawnwalker-save-editor.lock");
    await writeFile(lockPath, "another owner");
    await expect(editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 })).rejects.toThrow("Another menu owns");
    expect(await readFile(lockPath, "utf8")).toBe("another owner");
  });

  it("refuses a running game at apply time even after a valid preview", async () => {
    let gameRunning = false;
    const guard = vi.fn(async () => gameRunning);
    const { editor, saveDirectory, original } = await fixture(guard);
    const inspected = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 });
    const request = { fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: inspected.sha256 };
    const preview = await editor.previewRestore(request);
    gameRunning = true;
    await expect(editor.restoreBackup({ ...request, previewToken: preview.previewToken })).rejects.toThrow("Close Dawnwalker");
    expect(await readFile(join(saveDirectory, SAVE_NAME))).toEqual(original);
  });

  it("bounds oversized files and refuses hardlinked saves or junction save directories", async () => {
    const { editor, saveDirectory, backupDirectory, directory } = await fixture();
    const handle = await open(join(saveDirectory, "Oversized.sav"), "w");
    try { await handle.truncate(64 * 1024 * 1024 + 1); } finally { await handle.close(); }
    await expect(editor.inspectSave("Oversized.sav")).rejects.toThrow("oversized");
    await link(join(saveDirectory, SAVE_NAME), join(directory, "linked-original.sav"));
    await expect(editor.inspectSave(SAVE_NAME)).rejects.toThrow("Unsafe");
    const junction = join(directory, "save-junction");
    await symlink(saveDirectory, junction, "junction");
    await expect(createSaveEditor({ saveDirectory: junction, backupDirectory }).listSaves()).rejects.toThrow("junctions");
  });

  it("rejects a malicious manifest path and ignores unfinished backup directories", async () => {
    const { editor, backupDirectory } = await fixture();
    const inspected = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: inspected.sha256 });
    await mkdir(join(backupDirectory, ".pending-interrupted-backup"));
    expect(await editor.listBackups(SAVE_NAME)).toHaveLength(1);
    const manifestPath = join(backup.backupPath, "manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest.files[0].name = "../outside.sav";
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expect(editor.previewRestore({ fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: inspected.sha256 })).rejects.toThrow("Invalid backup file inventory");
  });

  it("stops on a game launch between companion replacements and retains a complete recovery snapshot", async () => {
    let refuseAfterFirstReplacement = false;
    let observedPath = "";
    const original = envelope();
    const { editor, saveDirectory } = await fixture(async () => refuseAfterFirstReplacement && (await readFile(observedPath)).equals(original));
    observedPath = join(saveDirectory, SAVE_NAME);
    const initial = await editor.inspectSave(SAVE_NAME);
    const backup = await editor.createBackup({ fileName: SAVE_NAME, expectedSha256: initial.sha256 });
    const newer = envelope("newer state before recovery");
    await writeFile(observedPath, newer);
    await writeFile(join(saveDirectory, "ManualSave2.meta"), "newer metadata before recovery");
    const current = await editor.inspectSave(SAVE_NAME);
    const request = { fileName: SAVE_NAME, backupId: backup.backupId, expectedSha256: current.sha256 };
    const preview = await editor.previewRestore(request);
    refuseAfterFirstReplacement = true;
    await expect(editor.restoreBackup({ ...request, previewToken: preview.previewToken })).rejects.toThrow("Some companion files were restored");
    const backups = await editor.listBackups(SAVE_NAME);
    expect(backups).toHaveLength(2);
    expect(await readFile(join(backups[0].backupPath, SAVE_NAME))).toEqual(newer);
    expect(await readFile(join(backups[0].backupPath, "ManualSave2.meta"), "utf8")).toBe("newer metadata before recovery");
    expect(await readFile(join(saveDirectory, "ManualSave2.meta"), "utf8")).toBe("newer metadata before recovery");
    expect((await readdir(saveDirectory)).filter((name) => name.startsWith(".dawnwalker"))).toEqual([]);
    refuseAfterFirstReplacement = false;
    const partial = await editor.inspectSave(SAVE_NAME);
    const recoveryRequest = { fileName: SAVE_NAME, backupId: backups[0].backupId, expectedSha256: partial.sha256 };
    const recoveryPreview = await editor.previewRestore(recoveryRequest);
    await editor.restoreBackup({ ...recoveryRequest, previewToken: recoveryPreview.previewToken });
    expect(await readFile(join(saveDirectory, SAVE_NAME))).toEqual(newer);
    expect(await readFile(join(saveDirectory, "ManualSave2.meta"), "utf8")).toBe("newer metadata before recovery");
  });
});
