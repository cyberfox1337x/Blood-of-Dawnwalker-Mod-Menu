import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { createConfigurationOperation, decodeConfiguration, readConfigurationFile, replaceConfigurationFile as replaceFile } from "./configurationFiles.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_fog_settings");

const hash = (bytes: Buffer) => createHash("sha256").update(bytes).digest("hex");
const KEYS = ["r.Fog", "r.VolumetricFog"] as const;
type FogKey = typeof KEYS[number];
export type FogInspection = Readonly<{
  fullPath: string; sha256: string; exists: boolean;
  configured: Record<FogKey, string | null>; owned: boolean;
  backupPath?: string; restartRequired: true; verification: "Not verified in game";
}>;
export type FogChange = Readonly<{ expectedSha256: string; fog: boolean; volumetricFog: boolean }>;
type Ownership = { baselineFile: string; originalExisted: boolean; originalHash: string; appliedHash: string; priorHash?: string };

function inspectText(text: string): Record<FogKey, string | null> {
  const values: Record<FogKey, string | null> = { "r.Fog": null, "r.VolumetricFog": null };
  let section = "";
  for (const line of text.split(/\r?\n/)) {
    const heading = line.match(/^\s*\[([^\]]+)\]/);
    if (heading) section = heading[1].toLowerCase();
    const entry = line.match(/^\s*(r\.(?:Fog|VolumetricFog))\s*=\s*([^;\r\n]*)(?:;.*)?$/i);
    if (entry) {
      if (!["systemsettings", "consolevariables"].includes(section)) throw new Error("Fog settings exist in an unsupported section. Review Engine.ini manually before editing.");
      const key = KEYS.find(candidate => candidate.toLowerCase() === entry[1].toLowerCase())!;
      const value = entry[2].trim();
      if (values[key] !== null && values[key] !== value) throw new Error("Engine.ini contains conflicting fog values. Resolve them before editing.");
      values[key] = value;
    }
  }
  return values;
}

export function updateFogConfiguration(bytes: Buffer, fog: boolean, volumetricFog: boolean): Buffer {
  const { text, encode } = decodeConfiguration(bytes, "Engine.ini");
  inspectText(text);
  const newline = text.includes("\r\n") ? "\r\n" : "\n";
  const requested = { "r.Fog": fog ? "1" : "0", "r.VolumetricFog": volumetricFog ? "1" : "0" };
  const seen = new Set<string>();
  let updated = text.replace(/^(\s*)(r\.(?:Fog|VolumetricFog))(\s*=\s*)([^;\r\n]*)(;[^\r\n]*)?$/gim, (_match, space, rawKey, equals, _value, comment) => {
    const key = KEYS.find(candidate => candidate.toLowerCase() === rawKey.toLowerCase())!;
    seen.add(key);
    return `${space}${rawKey}${equals}${requested[key]}${comment ? ` ${comment}` : ""}`;
  });
  const additions = KEYS.filter(key => !seen.has(key)).map(key => `${key}=${requested[key]}`).join(newline);
  if (additions) {
    const heading = /^\s*\[SystemSettings\][^\r\n]*(?:\r?\n|$)/im;
    if (heading.test(updated)) updated = updated.replace(heading, match => `${match}${match.endsWith("\n") ? "" : newline}${additions}${newline}`);
    else updated += `${updated && !updated.endsWith("\n") ? newline : ""}[SystemSettings]${newline}${additions}${newline}`;
  }
  return encode(updated);
}

export function createFogSettings(options: { configurationPath: string; backupDirectory: string; isGameRunning?: () => Promise<boolean> }) {
  const manifestPath = join(options.backupDirectory, "fog-ownership.json");
  const readConfiguration = () => readConfigurationFile(options.configurationPath, "Engine.ini");
  const exclusive = createConfigurationOperation(options.backupDirectory, "fog", requireClosed);
  async function ownership(): Promise<Ownership | undefined> {
    try {
      const record = JSON.parse(await readFile(manifestPath, "utf8")) as Ownership;
      if (!/^fog-[a-f0-9-]+\.bak$/.test(record.baselineFile) || typeof record.originalExisted !== "boolean" || !/^[a-f0-9]{64}$/.test(record.originalHash) || !/^[a-f0-9]{64}$/.test(record.appliedHash)) throw new Error("Fog backup record is invalid; retain backups and recover manually.");
      if (record.priorHash !== undefined && !/^[a-f0-9]{64}$/.test(record.priorHash)) throw new Error("Fog transaction journal is invalid.");
      return record;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
      throw error;
    }
  }
  async function inspect(): Promise<FogInspection> {
    const current = await readConfiguration();
    const record = await ownership();
    return { fullPath: options.configurationPath, sha256: hash(current.bytes), exists: current.exists,
      configured: inspectText(decodeConfiguration(current.bytes, "Engine.ini").text), owned: Boolean(record),
      ...(record ? { backupPath: join(options.backupDirectory, record.baselineFile) } : {}),
      restartRequired: true, verification: "Not verified in game" };
  }
  async function requireClosed() {
    if (!options.isGameRunning || await options.isGameRunning() !== false) throw new Error("Close Dawnwalker before changing fog configuration. Process status must be verified.");
  }
  async function apply(change: FogChange): Promise<FogInspection> {
    return exclusive(async () => {
      if (!change || typeof change.expectedSha256 !== "string" || typeof change.fog !== "boolean" || typeof change.volumetricFog !== "boolean") throw new Error("Invalid fog settings.");
      const current = await readConfiguration();
      if (hash(current.bytes) !== change.expectedSha256) throw new Error("Engine.ini changed. Refresh and review before applying.");
      const previous = await ownership();
      if (previous && ![previous.appliedHash, previous.priorHash].includes(hash(current.bytes))) throw new Error("Engine.ini was changed outside this menu. Restore manually from the recorded backup or review the conflict.");
      const next = updateFogConfiguration(current.bytes, change.fog, change.volumetricFog);
      if (hash(next) === hash(current.bytes)) return inspect();
      await mkdir(options.backupDirectory, { recursive: true });
      const record: Ownership = previous ?? { baselineFile: `fog-${randomUUID()}.bak`, originalExisted: current.exists, originalHash: hash(current.bytes), appliedHash: "" };
      if (!previous) {
        await writeFile(join(options.backupDirectory, record.baselineFile), current.bytes, { flag: "wx" });
        if (hash(await readFile(join(options.backupDirectory, record.baselineFile))) !== record.originalHash) throw new Error("Fog backup verification failed; no configuration written.");
      }
      await requireClosed();
      const latest = await readConfiguration();
      if (latest.exists !== current.exists || hash(latest.bytes) !== change.expectedSha256) throw new Error("Engine.ini changed during backup; no configuration written.");
      // Persist both possible commit states so a failed rename or interrupted process
      // remains recoverable without treating the untouched file as an external edit.
      record.priorHash = hash(current.bytes);
      record.appliedHash = hash(next);
      await replaceFile(manifestPath, Buffer.from(JSON.stringify(record, null, 2)));
      await mkdir(dirname(options.configurationPath), { recursive: true });
      await requireClosed();
      const beforeCommit = await readConfiguration();
      if (beforeCommit.exists !== current.exists || hash(beforeCommit.bytes) !== change.expectedSha256) throw new Error("Engine.ini changed before commit; no configuration written. The original backup and recovery journal are retained.");
      await replaceFile(options.configurationPath, next);
      if (hash((await readConfiguration()).bytes) !== record.appliedHash) throw new Error("Fog write readback failed. Original backup retained.");
      return inspect();
    });
  }
  async function restore(expectedSha256: string): Promise<FogInspection> {
    return exclusive(async () => {
      const record = await ownership();
      if (!record) throw new Error("No menu-owned fog backup exists.");
      const current = await readConfiguration();
      if (hash(current.bytes) !== expectedSha256) throw new Error("Engine.ini changed outside this menu. Automatic restoration would overwrite those changes.");
      const original = await readFile(join(options.backupDirectory, record.baselineFile));
      if (hash(original) !== record.originalHash) throw new Error("Fog backup hash mismatch; restoration refused.");
      if (hash(current.bytes) === record.originalHash && current.exists === record.originalExisted) {
        await unlink(manifestPath);
        return inspect();
      }
      if (![record.appliedHash, record.priorHash].includes(hash(current.bytes))) throw new Error("Engine.ini changed outside this menu. Automatic restoration would overwrite those changes.");
      await requireClosed();
      const beforeRestore = await readConfiguration();
      if (beforeRestore.exists !== current.exists || hash(beforeRestore.bytes) !== expectedSha256) throw new Error("Engine.ini changed during restoration.");
      if (record.originalExisted) await replaceFile(options.configurationPath, original);
      else await unlink(options.configurationPath);
      const restored = await readConfiguration();
      if (restored.exists !== record.originalExisted || hash(restored.bytes) !== record.originalHash) throw new Error("Fog restoration readback failed; retain backup.");
      await unlink(manifestPath);
      return inspect();
    });
  }
  return { inspect, apply, restore };
}
