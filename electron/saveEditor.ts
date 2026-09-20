import { createHash, randomUUID } from "node:crypto";
import { lstat, mkdir, open, readdir, readFile, rename, unlink } from "node:fs/promises";
import { basename, dirname, join, resolve, sep } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { decodeDsav, type DsavCodec } from "./dsavContainer.js";
import { createInstalledOodleCodec } from "./installedOodle.js";
import { readSaveFields, type SaveFields } from "./saveFields.js";
import { encodeEditedSave, editedSaveSha256, validateFieldEdit, type SaveEditVerification, type SaveFieldEdit, type SaveFieldEditResolved } from "./saveEditing.js";
import { loadSaveEditorMetadata } from "./gameMetadata.js";
import { inspectAdvancedSave, type SaveAdvancedPreview, type SaveMetadataPaths } from "./saveEditorPreview.js";
import { parseQuestCatalog } from "./saveJournal.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_editor");

const MAX_FILE_BYTES = 64 * 1024 * 1024;
const MAX_METADATA_BYTES = 64 * 1024;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const BACKUP_PATTERN = /^\d{13}-[a-f0-9-]{36}$/;
const EDITABLE_FIELDS = Object.freeze(["clockMs", "health", "blood", "mutationLevel", "coin"] as const);

export type SaveMetadata = Readonly<{
  day?: number;
  playTimeSeconds?: number;
  saveName?: string;
  savedAt?: string;
  buildVersion?: number;
  gameVersion?: number;
  saveVersion?: number;
  type?: string;
}>;

export type SaveInspection = Readonly<{
  fileName: string;
  fullPath: string;
  sha256: string;
  sizeBytes: number;
  modifiedAt: string;
  format: "DSAV compressed envelope" | "Unknown or truncated";
  metadata?: SaveMetadata;
  metadataWarning?: string;
  /** The game's own screenshot for this save (data URI), when the .png companion exists. */
  thumbnail?: string;
  fields?: SaveFields;
  advanced?: SaveAdvancedPreview;
  editableFields: readonly ("clockMs" | "health" | "blood" | "mutationLevel" | "coin")[];
  unavailableReason?: string;
  payloadValidation?: Readonly<{
    status: "verified" | "unavailable";
    message: string;
    decodedBytes?: number;
    recordCount?: number;
  }>;
}>;

/** The handful of gameplay numbers the picker shows beside each save, without the
 *  inventory catalogue that a full field read carries. */
export type SaveSummary = Readonly<{
  clockDisplay: string;
  health?: number;
  blood?: number;
  mutationLevel?: number;
  level?: number;
  coin?: number;
}>;

export type SaveBackup = Readonly<{
  backupId: string;
  fileName: string;
  createdAt: string;
  backupPath: string;
  sha256: string;
  files: readonly Readonly<{ name: string; sha256: string; sizeBytes: number }>[];
}>;

export type SaveRestoreRequest = Readonly<{ fileName: string; backupId: string; expectedSha256: string }>;
export type SaveRestorePreview = Readonly<{
  previewToken: string;
  fileName: string;
  fullPath: string;
  currentSha256: string;
  restoredSha256: string;
  backupId: string;
  files: readonly string[];
  reloadRequired: true;
  message: string;
}>;export type SaveRestoreResult = Readonly<{ inspection: SaveInspection; recoveryBackup: SaveBackup; message: string }>;
export type SaveEditRequest = Readonly<{ fileName: string; expectedSha256: string; edit: SaveFieldEdit }>;
export type SaveEditOutcome = Readonly<{ inspection: SaveInspection; backup: SaveBackup; verification: SaveEditVerification; message: string }>;
export type SaveEditorOptions = Readonly<{
  saveDirectory: string;
  backupDirectory: string;
  isGameRunning?: () => Promise<boolean>;
  settleMilliseconds?: number;
  codec?: DsavCodec;
  /** Resolves the game metadata files the DwSav-verified editors need; null when absent. */
  metadataPaths?: () => SaveMetadataPaths;
}>;

type BundleEntry = Readonly<{ name: string; bytes: Buffer; sha256: string; modifiedAt: string }>;
type Bundle = readonly BundleEntry[];
type BackupManifest = Readonly<{
  schemaVersion: 1;
  saveDirectory: string;
  fileName: string;
  createdAt: string;
  files: SaveBackup["files"];
}>;
type RestoreAuthorization = Readonly<{
  request: SaveRestoreRequest;
  currentFingerprint: string;
  backupFingerprint: string;
  expiresAt: number;
}>;

function sha256(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function assertSaveName(fileName: string): void {
  if (typeof fileName !== "string" || !/^[A-Za-z0-9][A-Za-z0-9 _-]{0,99}\.sav$/.test(fileName) || fileName.toLowerCase() === "rebelsettings.sav") {
    throw new Error("Choose a gameplay .sav file from the save list.");
  }
}

function bundleNames(fileName: string): readonly string[] {
  assertSaveName(fileName);
  const stem = fileName.slice(0, -4);
  return [fileName, `${stem}.meta`, `${stem}.png`];
}

function hasCode(error: unknown, code: string): boolean {
  return error instanceof Error && "code" in error && error.code === code;
}

function fingerprint(bundle: Bundle): string {
  return sha256(Buffer.from(JSON.stringify(bundle.map(({ name, sha256: hash }) => [name, hash]))));
}

function isKnownEnvelope(bytes: Buffer): boolean {
  // This identifies the observed container only. It does not validate compressed gameplay data.
  return bytes.length >= 48 && bytes.subarray(0, 4).equals(Buffer.from("DSAV")) && bytes.subarray(32, 40).equals(Buffer.from("DSAVCHNK"));
}

async function verifiedDirectory(directory: string): Promise<string> {
  const absolute = resolve(directory);
  let ancestor = absolute;
  while (true) {
    const status = await lstat(ancestor);
    if (!status.isDirectory() || status.isSymbolicLink()) throw new Error("Save and backup directories must be ordinary local directories without symbolic links or junctions.");
    const parent = dirname(ancestor);
    if (parent === ancestor) break;
    ancestor = parent;
  }
  return absolute;
}

async function readBoundedFile(directory: string, name: string, limit = MAX_FILE_BYTES): Promise<BundleEntry> {
  const fullPath = join(directory, name);
  const before = await lstat(fullPath);
  if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1 || before.size > limit) throw new Error(`Unsafe or oversized file: ${name}.`);
  const handle = await open(fullPath, "r");
  try {
    const opened = await handle.stat();
    if (opened.ino !== before.ino || opened.size !== before.size) throw new Error(`File changed while opening: ${name}.`);
    const bytes = Buffer.alloc(opened.size);
    let offset = 0;
    while (offset < bytes.length) {
      const { bytesRead } = await handle.read(bytes, offset, bytes.length - offset, offset);
      if (bytesRead === 0) throw new Error(`File was truncated while reading: ${name}.`);
      offset += bytesRead;
    }
    const after = await handle.stat();
    const pathAfter = await lstat(fullPath);
    if (after.size !== opened.size || after.mtimeMs !== opened.mtimeMs || pathAfter.ino !== opened.ino) throw new Error(`File changed while reading: ${name}.`);
    return { name, bytes, sha256: sha256(bytes), modifiedAt: after.mtime.toISOString() };
  } finally {
    await handle.close();
  }
}

async function readBundle(directory: string, fileName: string): Promise<Bundle> {
  assertSaveName(fileName);
  await verifiedDirectory(directory);
  const entries: BundleEntry[] = [];
  for (const name of bundleNames(fileName)) {
    try {
      entries.push(await readBoundedFile(directory, name, name.endsWith(".meta") ? MAX_METADATA_BYTES : MAX_FILE_BYTES));
    } catch (error) {
      if (name !== fileName && hasCode(error, "ENOENT")) continue;
      throw error;
    }
  }
  return entries;
}

function metadataFromBundle(bundle: Bundle): Pick<SaveInspection, "metadata" | "metadataWarning"> {
  const metadataFile = bundle.find(({ name }) => name.endsWith(".meta"));
  if (!metadataFile) return { metadataWarning: "No companion metadata file is present." };
  try {
    const parsed: unknown = JSON.parse(metadataFile.bytes.toString("utf8"));
    if (!parsed || typeof parsed !== "object" || !("Meta" in parsed) || !parsed.Meta || typeof parsed.Meta !== "object") throw new Error("Missing Meta object");
    const source = parsed.Meta as Record<string, unknown>;
    const metadata: Record<string, number | string> = {};
    const numbers = { Day: "day", PlayTime: "playTimeSeconds", BuildVersion: "buildVersion", GameVersion: "gameVersion", SaveVersion: "saveVersion" };
    for (const [key, label] of Object.entries(numbers)) {
      const candidate = source[key];
      if (typeof candidate === "number" && Number.isSafeInteger(candidate) && candidate >= 0) metadata[label] = candidate;
    }
    for (const [key, label] of Object.entries({ SaveName: "saveName", Date: "savedAt", TypeString: "type" })) {
      const candidate = source[key];
      if (typeof candidate === "string" && candidate.length <= 120 && ![...candidate].some((character) => character.charCodeAt(0) < 32)) metadata[label] = candidate;
    }
    return { metadata };
  } catch {
    return { metadataWarning: "Companion metadata is not recognized JSON. Its original bytes are preserved in backups." };
  }
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function inspectBundle(directory: string, fileName: string, bundle: Bundle): SaveInspection {
  const save = bundle[0];
  // The game writes a screenshot beside every save; the picker shows it so a save is
  // recognised the way the game's own load list presents it. Only a genuine PNG is
  // handed to the renderer, as a data URI (the page's CSP allows no file: images).
  const picture = bundle.find(entry => entry.name.toLowerCase().endsWith(".png"));
  const thumbnail = picture && picture.bytes.length > PNG_SIGNATURE.length && picture.bytes.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)
    ? `data:image/png;base64,${picture.bytes.toString("base64")}` : undefined;
  return {
    fileName, fullPath: join(directory, fileName), sha256: save.sha256, sizeBytes: save.bytes.length,
    modifiedAt: save.modifiedAt, format: isKnownEnvelope(save.bytes) ? "DSAV compressed envelope" : "Unknown or truncated",
    ...metadataFromBundle(bundle), ...(thumbnail ? { thumbnail } : {}), editableFields: EDITABLE_FIELDS,
  };
}

function assertExpectedHash(bundle: Bundle, expected: string): void {
  if (typeof expected !== "string" || !HASH_PATTERN.test(expected) || bundle[0].sha256 !== expected) {
    throw new Error("The save changed since it was selected. Inspect it again before continuing.");
  }
}

function validateManifest(raw: unknown, fileName: string, saveDirectory: string): BackupManifest {
  if (!raw || typeof raw !== "object") throw new Error("Invalid backup manifest.");
  const manifest = raw as BackupManifest;
  if (manifest.schemaVersion !== 1 || manifest.fileName !== fileName || manifest.saveDirectory !== saveDirectory || typeof manifest.createdAt !== "string" || !Number.isFinite(Date.parse(manifest.createdAt)) || !Array.isArray(manifest.files)) {
    throw new Error("The backup does not belong to this save directory and file.");
  }
  const allowed = bundleNames(fileName);
  const names = new Set<string>();
  for (const entry of manifest.files) {
    if (!entry || !allowed.includes(entry.name) || names.has(entry.name) || !HASH_PATTERN.test(entry.sha256) || !Number.isSafeInteger(entry.sizeBytes) || entry.sizeBytes < 0 || entry.sizeBytes > MAX_FILE_BYTES) throw new Error("Invalid backup file inventory.");
    names.add(entry.name);
  }
  if (!names.has(fileName) || manifest.files[0]?.name !== fileName || names.size > 3) throw new Error("Incomplete backup file inventory.");
  return manifest;
}

export function createSaveEditor(options: SaveEditorOptions) {
  const codec = options.codec ?? createInstalledOodleCodec();
  const saveDirectory = resolve(options.saveDirectory);
  const backupDirectory = resolve(options.backupDirectory);
  if (saveDirectory.toLowerCase() === backupDirectory.toLowerCase()) throw new Error("Backups must be stored separately from gameplay saves.");
  if (backupDirectory.toLowerCase().startsWith(`${saveDirectory.toLowerCase()}${sep}`)) throw new Error("Backups must be stored outside the gameplay save directory.");
  const settleMilliseconds = options.settleMilliseconds ?? 350;
  if (!Number.isFinite(settleMilliseconds) || settleMilliseconds < 0 || settleMilliseconds > 5_000) throw new Error("Invalid save-settle interval.");
  const previews = new Map<string, RestoreAuthorization>();
  let busy = false;

  async function requireStopped(): Promise<void> {
    if (!options.isGameRunning || await options.isGameRunning() !== false) throw new Error("Close Dawnwalker normally before backing up or restoring saves. Game process status must be verified.");
  }

  async function stableBundle(fileName: string): Promise<Bundle> {
    await requireStopped();
    const before = await readBundle(saveDirectory, fileName);
    await delay(settleMilliseconds);
    await requireStopped();
    const after = await readBundle(saveDirectory, fileName);
    if (fingerprint(before) !== fingerprint(after)) throw new Error("The save is changing or syncing. Wait until saving and cloud sync finish, then inspect it again.");
    return after;
  }

  async function withLock<T>(operation: () => Promise<T>): Promise<T> {
    if (busy) throw new Error("Another save operation is already in progress.");
    busy = true;
    let lock: Awaited<ReturnType<typeof open>> | undefined;
    const lockPath = join(saveDirectory, ".dawnwalker-save-editor.lock");
    try {
      await verifiedDirectory(saveDirectory);
      await requireStopped();
      lock = await open(lockPath, "wx");
      return await operation();
    } catch (error) {
      if (!lock && hasCode(error, "EEXIST")) throw new Error("Another menu owns the save lock. If every menu is closed after a crash, remove .dawnwalker-save-editor.lock before retrying.");
      throw error;
    } finally {
      try {
        if (lock) { await lock.close(); await unlink(lockPath); }
      } finally { busy = false; }
    }
  }

  async function persistBackup(fileName: string, bundle: Bundle): Promise<SaveBackup> {
    await mkdir(backupDirectory, { recursive: true });
    await verifiedDirectory(backupDirectory);
    const backupId = `${Date.now()}-${randomUUID()}`;
    const backupPath = join(backupDirectory, backupId);
    const pendingPath = join(backupDirectory, `.pending-${randomUUID()}`);
    await mkdir(pendingPath);
    const files = bundle.map(({ name, sha256: hash, bytes }) => ({ name, sha256: hash, sizeBytes: bytes.length }));
    const manifest: BackupManifest = { schemaVersion: 1, saveDirectory, fileName, createdAt: new Date().toISOString(), files };
    for (const entry of bundle) {
      const handle = await open(join(pendingPath, entry.name), "wx");
      try { await handle.writeFile(entry.bytes); await handle.sync(); } finally { await handle.close(); }
      if ((await readBoundedFile(pendingPath, entry.name)).sha256 !== entry.sha256) throw new Error("Backup verification failed. The original save was not changed.");
    }
    const manifestHandle = await open(join(pendingPath, "manifest.json"), "wx");
    try { await manifestHandle.writeFile(`${JSON.stringify(manifest, null, 2)}\n`); await manifestHandle.sync(); } finally { await manifestHandle.close(); }
    await rename(pendingPath, backupPath);
    return { backupId, fileName, createdAt: manifest.createdAt, backupPath, sha256: bundle[0].sha256, files };
  }

  async function readBackup(fileName: string, backupId: string): Promise<{ backup: SaveBackup; bundle: Bundle }> {
    assertSaveName(fileName);
    if (typeof backupId !== "string" || !BACKUP_PATTERN.test(backupId)) throw new Error("Choose a backup from the verified backup list.");
    await verifiedDirectory(backupDirectory);
    const backupPath = await verifiedDirectory(join(backupDirectory, backupId));
    const raw = await readBoundedFile(backupPath, "manifest.json", MAX_METADATA_BYTES);
    const manifest = validateManifest(JSON.parse(raw.bytes.toString("utf8")), fileName, saveDirectory);
    const bundle: BundleEntry[] = [];
    for (const entry of manifest.files) {
      const observed = await readBoundedFile(backupPath, entry.name);
      if (observed.sha256 !== entry.sha256 || observed.bytes.length !== entry.sizeBytes) throw new Error("The backup failed its SHA-256 integrity check. No save was changed.");
      bundle.push(observed);
    }
    return { backup: { backupId, fileName, backupPath, createdAt: manifest.createdAt, sha256: bundle[0].sha256, files: manifest.files }, bundle };
  }

  async function listSaves(): Promise<readonly SaveInspection[]> {
    try { await verifiedDirectory(saveDirectory); } catch (error) { if (hasCode(error, "ENOENT")) return []; throw error; }
    const names = await readdir(saveDirectory);
    const saves: SaveInspection[] = [];
    for (const name of names.sort()) {
      if (!/^[A-Za-z0-9][A-Za-z0-9 _-]{0,99}\.sav$/.test(name) || name.toLowerCase() === "rebelsettings.sav") continue;
      saves.push(inspectBundle(saveDirectory, name, await readBundle(saveDirectory, name)));
    }
    return saves;
  }

  async function inspectSave(fileName: string): Promise<SaveInspection> {
    const bundle = await readBundle(saveDirectory, fileName);
    const inspection = inspectBundle(saveDirectory, fileName, bundle);
    try {
      const decoded = await decodeDsav(bundle[0].bytes, codec);
      const after = await readBundle(saveDirectory, fileName);
      if (fingerprint(after) !== fingerprint(bundle)) throw new Error("The save changed during decoding. Refresh and inspect it again.");
      const advanced = await inspectAdvancedSave(decoded, options.metadataPaths?.());
      return { ...inspection, fields: readSaveFields(decoded), advanced, payloadValidation: { status: "verified", decodedBytes: decoded.payload.length, recordCount: decoded.nodes.length, message: "Compressed save structure decoded and verified; recognized gameplay values are read from it." } };
    } catch (error) {
      return { ...inspection, payloadValidation: { status: "unavailable", message: error instanceof Error ? error.message : "Save payload validation could not complete." } };
    }
  }

  async function readFields(fileName: string): Promise<SaveFields> {
    assertSaveName(fileName);
    const save = (await readBundle(saveDirectory, fileName))[0];
    const document = await decodeDsav(save.bytes, codec);
    return readSaveFields(document);
  }

  // Decoding a save takes a few hundred milliseconds, so the picker asks for these one
  // save at a time in the background instead of the list call decoding every file.
  async function readSummary(fileName: string): Promise<SaveSummary> {
    const fields = await readFields(fileName);
    return { clockDisplay: fields.clockDisplay, health: fields.health, blood: fields.blood, mutationLevel: fields.mutationLevel, level: fields.level, coin: fields.coin };
  }

  async function editFields(request: SaveEditRequest): Promise<SaveEditOutcome> {
    assertSaveName(request.fileName);
    if (!HASH_PATTERN.test(request.expectedSha256)) throw new Error("Inspect the save again before editing it.");
    const edit = validateFieldEdit(request.edit);
    // DwSav-verified features (item upgrades, first-rank perks) need the game's own
    // metadata; absent files leave those features off with a reason, not the editor.
    const metadata = options.metadataPaths
      ? await loadSaveEditorMetadata(options.metadataPaths())
      : {};
    const questsPath = options.metadataPaths?.().questsJson;
    const questCatalog = edit.questTracking && questsPath ? parseQuestCatalog(await readFile(questsPath, "utf8")) : undefined;
    const resolved: SaveFieldEditResolved = { ...edit, itemLevels: metadata.itemLevels, traits: metadata.traits, books: metadata.books, gameConfig: metadata.gameConfig, questCatalog };
    return withLock(async () => {
      const bundle = await stableBundle(request.fileName);
      assertExpectedHash(bundle, request.expectedSha256);
      const { encoded, verification } = await encodeEditedSave(bundle[0].bytes, resolved, codec);
      const editedBundle: Bundle = bundle.map((entry) => entry.name === request.fileName
        ? { ...entry, bytes: encoded, sha256: editedSaveSha256(encoded), modifiedAt: new Date().toISOString() }
        : entry);
      const backup = await persistBackup(request.fileName, bundle);
      const stagedPath = join(saveDirectory, `.dawnwalker-edit-${randomUUID()}.tmp`);
      const handle = await open(stagedPath, "wx");
      try { await handle.writeFile(encoded); await handle.sync(); } finally { await handle.close(); }
      try {
        await requireStopped();
        const observed = await readBundle(saveDirectory, request.fileName);
        if (fingerprint(observed) !== fingerprint(bundle)) throw new Error("The save changed while the edit was being applied; the original was left untouched.");
        await rename(stagedPath, join(saveDirectory, request.fileName));
      } catch (error) {
        try { await unlink(stagedPath); } catch { /* staged cleanup cannot hide the failure */ }
        throw error;
      }
      const finalBundle = await readBundle(saveDirectory, request.fileName);
      const written = finalBundle[0];
      if (written.sha256 !== editedBundle[0].sha256) throw new Error(`The written save failed its verification hash. Recover the original from ${backup.backupPath}`);
      let verifiedFields: SaveFields | undefined;
      let advanced: SaveAdvancedPreview | undefined;
      try {
        const document = await decodeDsav(written.bytes, codec);
        verifiedFields = readSaveFields(document);
        advanced = await inspectAdvancedSave(document, options.metadataPaths?.());
        if (edit.health !== undefined && verifiedFields.health !== edit.health) throw new Error("The written save does not read back the edited Health.");
        if (edit.blood !== undefined && verifiedFields.blood !== edit.blood) throw new Error("The written save does not read back the edited Blood.");
        if (edit.mutationLevel !== undefined && verifiedFields.mutationLevel !== edit.mutationLevel) throw new Error("The written save does not read back the edited mutation level.");
        if (edit.coin !== undefined && verifiedFields.coin !== edit.coin) throw new Error("The written save does not read back the edited coin.");
        if (edit.level !== undefined && verifiedFields.level !== edit.level) throw new Error("The written save does not read back the edited level.");
        if (edit.progressPoints !== undefined && verifiedFields.progressPoints !== edit.progressPoints) throw new Error("The written save does not read back the edited progress points.");
        if (edit.stacks !== undefined) {
          const writtenStacks = new Map((verifiedFields.stacks ?? []).map((stack) => [stack.itemIndex, stack.value]));
          for (const { itemIndex, value } of edit.stacks) {
            if (writtenStacks.get(itemIndex) !== value) throw new Error(`The written save does not read back the edited stack for item index ${itemIndex}.`);
          }
        }
        if (edit.attributeValues !== undefined) {
          const writtenAttributes = new Map((verifiedFields.attributes ?? []).map((attribute) => [attribute.id, attribute.value]));
          for (const { id, value } of edit.attributeValues) {
            if (writtenAttributes.get(id) !== value) throw new Error(`The written save does not read back the edited attribute ${id}.`);
          }
        }
        if (edit.giveItems !== undefined) {
          const catalog = new Map((verifiedFields.itemCatalog ?? []).map((entry) => [entry.definitionIndex, entry.name]));
          const writtenByName = new Map((verifiedFields.stacks ?? []).map((stack) => [stack.name, stack.value]));
          for (const { definitionIndex, value } of edit.giveItems) {
            const name = catalog.get(definitionIndex);
            if (name === undefined || writtenByName.get(name) !== value) throw new Error(`The written save does not read back the given item ${name ?? definitionIndex}.`);
          }
        }
        if (edit.replaceItems !== undefined) {
          const catalog = new Map((verifiedFields.itemCatalog ?? []).map((entry) => [entry.definitionIndex, entry.name]));
          const writtenByIndex = new Map((verifiedFields.stacks ?? []).map((stack) => [stack.itemIndex, stack]));
          for (const { itemIndex, definitionIndex, value } of edit.replaceItems) {
            const name = catalog.get(definitionIndex);
            const stack = writtenByIndex.get(itemIndex);
            if (name === undefined || stack?.name !== name) throw new Error(`The written save does not read back slot ${itemIndex} as ${name ?? definitionIndex}.`);
            if (value !== undefined && stack.value !== value) throw new Error(`The written save does not read back the replaced count for slot ${itemIndex}.`);
          }
        }
      } catch {
        throw new Error(`The written save failed final verification. Recover the original from ${backup.backupPath}`);
      }
      return {
        inspection: { ...inspectBundle(saveDirectory, request.fileName, finalBundle), fields: verifiedFields, advanced, payloadValidation: { status: "verified", message: "Edited save decoded and verified after writing." } },
        backup,
        verification,
        message: `Edit applied and verified: ${verification.changedFields.join(", ") || "no byte changes"}. Reload the save in game. The pre-edit files remain in the backup.`,
      };
    });
  }

  async function createBackup(request: Readonly<{ fileName: string; expectedSha256: string }>): Promise<SaveBackup> {
    return withLock(async () => {
      const bundle = await stableBundle(request.fileName);
      assertExpectedHash(bundle, request.expectedSha256);
      return persistBackup(request.fileName, bundle);
    });
  }

  async function listBackups(fileName: string): Promise<readonly SaveBackup[]> {
    assertSaveName(fileName);
    try { await verifiedDirectory(backupDirectory); } catch (error) { if (hasCode(error, "ENOENT")) return []; throw error; }
    const names = (await readdir(backupDirectory)).filter((name) => BACKUP_PATTERN.test(name)).sort().reverse();
    const backups: SaveBackup[] = [];
    for (const backupId of names) {
      const manifestPath = join(backupDirectory, backupId);
      await verifiedDirectory(manifestPath);
      const raw = await readBoundedFile(manifestPath, "manifest.json", MAX_METADATA_BYTES);
      const candidate: unknown = JSON.parse(raw.bytes.toString("utf8"));
      if (!candidate || typeof candidate !== "object" || !("fileName" in candidate) || candidate.fileName !== fileName) continue;
      backups.push((await readBackup(fileName, backupId)).backup);
    }
    return backups;
  }

  async function previewRestore(request: SaveRestoreRequest): Promise<SaveRestorePreview> {
    const current = await stableBundle(request.fileName);
    assertExpectedHash(current, request.expectedSha256);
    const { bundle: backup } = await readBackup(request.fileName, request.backupId);
    if (!isKnownEnvelope(current[0].bytes) || !isKnownEnvelope(backup[0].bytes)) throw new Error("Unknown or truncated save format. Restore is unavailable for this file.");
    if (current.map(({ name }) => name).join("|") !== backup.map(({ name }) => name).join("|")) throw new Error("Companion files differ. Automatic restore cannot safely add or delete save metadata or screenshots.");
    const previewToken = randomUUID();
    previews.clear();
    previews.set(previewToken, { request: { ...request }, currentFingerprint: fingerprint(current), backupFingerprint: fingerprint(backup), expiresAt: Date.now() + 300_000 });
    return {
      previewToken, fileName: request.fileName, fullPath: join(saveDirectory, request.fileName),
      currentSha256: current[0].sha256, restoredSha256: backup[0].sha256, backupId: request.backupId,
      files: backup.map(({ name }) => name), reloadRequired: true,
      message: "Restore replaces this save and its listed companions with the exact backup bytes. A recovery backup of the current files is created first. Keep Dawnwalker closed and wait for cloud sync to finish; launch and reload the save afterward.",
    };
  }

  async function restoreBackup(request: SaveRestoreRequest & Readonly<{ previewToken: string }>): Promise<SaveRestoreResult> {
    return withLock(async () => {
      const authorization = previews.get(request.previewToken);
      previews.delete(request.previewToken);
      if (!authorization || authorization.expiresAt < Date.now() || authorization.request.fileName !== request.fileName || authorization.request.backupId !== request.backupId || authorization.request.expectedSha256 !== request.expectedSha256) throw new Error("Preview this exact restore again before applying it.");
      const current = await stableBundle(request.fileName);
      assertExpectedHash(current, request.expectedSha256);
      const { bundle: backup } = await readBackup(request.fileName, request.backupId);
      if (fingerprint(current) !== authorization.currentFingerprint || fingerprint(backup) !== authorization.backupFingerprint) throw new Error("Save, companion, or backup files changed after preview. Preview the restore again.");
      const recoveryBackup = await persistBackup(request.fileName, current);
      const staged: { entry: BundleEntry; path: string }[] = [];
      const restored: BundleEntry[] = [];
      try {
        for (const entry of backup) {
          const stagedPath = join(saveDirectory, `.dawnwalker-${randomUUID()}.tmp`);
          staged.push({ entry, path: stagedPath });
          const handle = await open(stagedPath, "wx");
          try { await handle.writeFile(entry.bytes); await handle.sync(); } finally { await handle.close(); }
        }
        for (const { entry, path } of staged) {
          await requireStopped();
          const observed = await readBundle(saveDirectory, request.fileName);
          const expected = current.map((original) => restored.find(({ name }) => name === original.name) ?? original);
          if (fingerprint(observed) !== fingerprint(expected)) throw new Error("Save files changed during restore; further writes were stopped.");
          await rename(path, join(saveDirectory, entry.name));
          restored.push(entry);
        }
        const finalBundle = await readBundle(saveDirectory, request.fileName);
        if (fingerprint(finalBundle) !== fingerprint(backup)) throw new Error("Restored bytes failed verification.");
        return { inspection: inspectBundle(saveDirectory, request.fileName, finalBundle), recoveryBackup, message: "Exact backup bytes restored and verified. Launch Dawnwalker and reload this save. The pre-restore files remain in the recovery backup." };
      } catch (error) {
        // Never overwrite a racing game/cloud writer in an attempted automatic rollback.
        throw new Error(`Restore stopped. ${error instanceof Error ? error.message : "File operation failed."} ${restored.length ? "Some companion files were restored; keep the game closed and recover the complete set from" : "Original files are preserved in"} ${recoveryBackup.backupPath}`);
      } finally {
        for (const { path } of staged) {
          try { await unlink(path); } catch (error) {
            // Cleanup cannot replace the transaction result or hide its recovery path.
            if (!hasCode(error, "ENOENT")) process.emitWarning(`Could not remove staged save file ${basename(path)}. Save backups remain available.`);
          }
        }
      }
    });
  }

  return Object.freeze({ listSaves, inspectSave, readFields, readSummary, editFields, createBackup, listBackups, previewRestore, restoreBackup });
}
