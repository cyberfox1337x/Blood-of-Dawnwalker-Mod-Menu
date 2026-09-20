import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { createConfigurationOperation, decodeConfiguration, readConfigurationFile, replaceConfigurationFile as replaceFile } from "./configurationFiles.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_story_day_settings");

const hash = (bytes: Buffer) => createHash("sha256").update(bytes).digest("hex");
const SECTION = "/script/quest.questsettings";
export type StoryDayInspection = Readonly<{
  fullPath: string; sha256: string; exists: boolean; configuredDays: number | null;
  enabled: boolean; owned: boolean; conflict: boolean; backupPath?: string;
  gameRunning: boolean; buildVerified: boolean; restartRequired: true; verification: "Not verified in game";
}>;
export type StoryDayChange = Readonly<{ expectedSha256: string }>;
type Ownership = { targetPath: string; baselineFile: string; originalExisted: boolean; originalHash: string; appliedHash: string; priorHash?: string };

function inspectText(text: string): number | null {
  let section = "", found: number | null = null;
  for (const line of text.split(/\r?\n/)) {
    const heading = line.match(/^\s*\[([^\]]+)\]/);
    if (heading) section = heading[1].toLowerCase();
    if (section !== SECTION) continue;
    const entry = line.match(/^\s*DaysToPass\s*=\s*([^;\r\n]*)(?:;.*)?$/i);
    if (!entry) continue;
    const value = Number(entry[1].trim());
    if (!Number.isSafeInteger(value) || value < 1 || value > 2147483647) throw new Error("Game.ini contains an invalid DaysToPass value.");
    if (found !== null) throw new Error("Game.ini contains duplicate DaysToPass entries. Resolve them before editing.");
    found = value;
  }
  return found;
}

export function updateStoryDayConfiguration(bytes: Buffer): Buffer {
  const { text, encode } = decodeConfiguration(bytes, "Game.ini");
  inspectText(text);
  const newline = text.includes("\r\n") ? "\r\n" : "\n";
  let section = "", replaced = false;
  let updated = text.split(/(?<=\n)/).map(line => {
    const heading = line.match(/^\s*\[([^\]]+)\]/);
    if (heading) section = heading[1].toLowerCase();
    if (section !== SECTION) return line;
    return line.replace(/^(\s*DaysToPass\s*=\s*)([^;\r\n]*)(;[^\r\n]*)?/i, (_match, prefix, _value, comment) => {
      replaced = true; return `${prefix}91${comment ? ` ${comment}` : ""}`;
    });
  }).join("");
  if (!replaced) {
    const heading = /^\s*\[\/Script\/Quest\.QuestSettings\][^\r\n]*(?:\r?\n|$)/im;
    if (heading.test(updated)) updated = updated.replace(heading, match => `${match}${match.endsWith("\n") ? "" : newline}DaysToPass=91${newline}`);
    else updated += `${updated && !updated.endsWith("\n") ? newline : ""}[/Script/Quest.QuestSettings]${newline}DaysToPass=91${newline}`;
  }
  return encode(updated);
}

export function createStoryDaySettings(options: { configurationPath: string; backupDirectory: string; isGameRunning?: () => Promise<boolean>; isBuildVerified?: () => Promise<boolean> }) {
  const manifestPath = join(options.backupDirectory, "story-day-ownership.json");
  const readConfiguration = () => readConfigurationFile(options.configurationPath, "Game.ini");
  const exclusive = createConfigurationOperation(options.backupDirectory, "story-day", requireClosed);
  async function ownership(): Promise<Ownership | undefined> {
    try {
      const record = JSON.parse(await readFile(manifestPath, "utf8")) as Ownership;
      if (record.targetPath !== resolve(options.configurationPath) || !/^story-day-[a-f0-9-]+\.bak$/.test(record.baselineFile) || typeof record.originalExisted !== "boolean" || !/^[a-f0-9]{64}$/.test(record.originalHash) || !/^[a-f0-9]{64}$/.test(record.appliedHash)) throw new Error("Story-day backup record is invalid; retain backups and recover manually.");
      if (record.priorHash !== undefined && !/^[a-f0-9]{64}$/.test(record.priorHash)) throw new Error("Story-day transaction journal is invalid.");
      return record;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
      throw error;
    }
  }
  async function inspect(): Promise<StoryDayInspection> {
    const current = await readConfiguration();
    const record = await ownership();
    const configuredDays = inspectText(decodeConfiguration(current.bytes, "Game.ini").text);
    return { fullPath: options.configurationPath, sha256: hash(current.bytes), exists: current.exists,
      configuredDays, enabled: configuredDays === 91, owned: Boolean(record),
      conflict: Boolean(record && ![record.appliedHash, record.priorHash, record.originalHash].includes(hash(current.bytes))),
      ...(record ? { backupPath: join(options.backupDirectory, record.baselineFile) } : {}),
      gameRunning: options.isGameRunning ? await options.isGameRunning() : true, buildVerified: options.isBuildVerified ? await options.isBuildVerified() : false,
      restartRequired: true, verification: "Not verified in game" };
  }
  async function requireClosed() {
    if (!options.isGameRunning || await options.isGameRunning() !== false) throw new Error("Close Dawnwalker before changing story-day configuration. Process status must be verified.");
  }
  async function apply(change: StoryDayChange): Promise<StoryDayInspection> {
    return exclusive(async () => {
      if (!options.isBuildVerified || await options.isBuildVerified() !== true) throw new Error("The installed game build must be verified before enabling story configuration.");
      if (!change || typeof change.expectedSha256 !== "string") throw new Error("Invalid story-day settings.");
      const current = await readConfiguration();
      if (hash(current.bytes) !== change.expectedSha256) throw new Error("Game.ini changed. Refresh and review before applying.");
      const previous = await ownership();
      if (previous && ![previous.appliedHash, previous.priorHash].includes(hash(current.bytes))) throw new Error("Game.ini was changed outside this menu. Restore manually from the recorded backup or review the conflict.");
      const next = updateStoryDayConfiguration(current.bytes);
      if (hash(next) === hash(current.bytes)) return inspect();
      await mkdir(options.backupDirectory, { recursive: true });
      const record: Ownership = previous ?? { targetPath: resolve(options.configurationPath), baselineFile: `story-day-${randomUUID()}.bak`, originalExisted: current.exists, originalHash: hash(current.bytes), appliedHash: "" };
      if (!previous) {
        await writeFile(join(options.backupDirectory, record.baselineFile), current.bytes, { flag: "wx" });
        if (hash(await readFile(join(options.backupDirectory, record.baselineFile))) !== record.originalHash) throw new Error("Story-day backup verification failed; no configuration written.");
      }
      await requireClosed();
      const latest = await readConfiguration();
      if (latest.exists !== current.exists || hash(latest.bytes) !== change.expectedSha256) throw new Error("Game.ini changed during backup; no configuration written.");
      // Persist both possible commit states so a failed rename or interrupted process
      // remains recoverable without treating the untouched file as an external edit.
      record.priorHash = hash(current.bytes);
      record.appliedHash = hash(next);
      await replaceFile(manifestPath, Buffer.from(JSON.stringify(record, null, 2)));
      await mkdir(dirname(options.configurationPath), { recursive: true });
      await requireClosed();
      const beforeCommit = await readConfiguration();
      if (beforeCommit.exists !== current.exists || hash(beforeCommit.bytes) !== change.expectedSha256) throw new Error("Game.ini changed before commit; no configuration written. The original backup and recovery journal are retained.");
      if (await options.isBuildVerified() !== true) throw new Error("Game build verification changed before commit.");
      await replaceFile(options.configurationPath, next);
      if (hash((await readConfiguration()).bytes) !== record.appliedHash) throw new Error("Story-day write readback failed. Original backup retained.");
      return inspect();
    });
  }
  async function restore(expectedSha256: string): Promise<StoryDayInspection> {
    return exclusive(async () => {
      const record = await ownership();
      if (!record) throw new Error("No menu-owned story-day backup exists.");
      const current = await readConfiguration();
      if (hash(current.bytes) !== expectedSha256) throw new Error("Game.ini changed outside this menu. Automatic restoration would overwrite those changes.");
      const original = await readFile(join(options.backupDirectory, record.baselineFile));
      if (hash(original) !== record.originalHash) throw new Error("Story-day backup hash mismatch; restoration refused.");
      if (hash(current.bytes) === record.originalHash && current.exists === record.originalExisted) {
        await unlink(manifestPath);
        return inspect();
      }
      if (![record.appliedHash, record.priorHash].includes(hash(current.bytes))) throw new Error("Game.ini changed outside this menu. Automatic restoration would overwrite those changes.");
      await requireClosed();
      const beforeRestore = await readConfiguration();
      if (beforeRestore.exists !== current.exists || hash(beforeRestore.bytes) !== expectedSha256) throw new Error("Game.ini changed during restoration.");
      if (record.originalExisted) await replaceFile(options.configurationPath, original);
      else await unlink(options.configurationPath);
      const restored = await readConfiguration();
      if (restored.exists !== record.originalExisted || hash(restored.bytes) !== record.originalHash) throw new Error("Story-day restoration readback failed; retain backup.");
      await unlink(manifestPath);
      return inspect();
    });
  }
  return { inspect, apply, restore };
}

export async function handleStoryDayRequest(api: ReturnType<typeof createStoryDaySettings>, action: unknown, payload: unknown) {
  if (action === "inspect") return api.inspect();
  if (action === "apply" && payload && typeof payload === "object" && !Array.isArray(payload)) {
    const change = payload as Record<string, unknown>;
    if (Object.keys(change).length === 1 && typeof change.expectedSha256 === "string" && /^[a-f0-9]{64}$/.test(change.expectedSha256)) return api.apply({ expectedSha256: change.expectedSha256 });
  }
  if (action === "restore" && typeof payload === "string" && /^[a-f0-9]{64}$/.test(payload)) return api.restore(payload);
  throw new Error("Invalid story configuration operation.");
}
