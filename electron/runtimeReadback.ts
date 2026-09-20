import type { BridgeResult } from "./bridgeTransport.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_runtime_readback");

export type RuntimePlayerReadback = Readonly<{
  alive?: boolean;
  level?: number;
  health?: number;
  maxHealth?: number;
  stamina?: number;
  maxStamina?: number;
  bloodEnergy?: number;
  maxBloodEnergy?: number;
  traitPoints?: number;
  gold?: number;
  x?: number;
  y?: number;
  z?: number;
}>;

export type RuntimeControlReadback = Readonly<{
  hudVisible?: boolean;
  gameSpeed?: number;
  rpgDifficulty?: number;
  actionDifficulty?: number;
}>;

export type RuntimeQuestState = "active" | "success" | "failure" | "unknown";

export type RuntimeQuestObjectiveReadback = Readonly<{
  text: string;
  state: RuntimeQuestState;
  currentCount: number;
  maxCount: number;
  optional: boolean;
}>;

export type RuntimeQuestReadback = Readonly<{
  title: string;
  state: RuntimeQuestState;
  tracked: boolean;
  objectiveCount: number;
  objectivesTruncated: boolean;
  objectives: readonly RuntimeQuestObjectiveReadback[];
}>;

export type RuntimeQuestJournalReadback = Readonly<{
  openQuestCount: number;
  returnedQuestCount: number;
  truncated: boolean;
  quests: readonly RuntimeQuestReadback[];
}>;

type ReadbackDispatcher = (command: Readonly<{
  capability: string;
}>) => Promise<BridgeResult>;

const MAX_QUEST_READBACK_BYTES = 8_192;
const MAX_QUESTS = 6;
const MAX_OBJECTIVES_PER_QUEST = 3;
const MAX_DECODED_QUEST_TEXT_LENGTH = 240;
const QUEST_STATES: ReadonlySet<string> = new Set(["active", "success", "failure", "unknown"]);

function parseReadbackFields(readback: string | undefined): Readonly<Record<string, string>> {
  if (!readback || readback.length > 16_384) return {};
  const fields: Record<string, string> = {};
  for (const entry of readback.split(";")) {
    const separator = entry.indexOf("=");
    if (separator <= 0) continue;
    const key = entry.slice(0, separator);
    if (!/^[a-z_]+$/.test(key)) continue;
    // Conflicting duplicate fields are not an authoritative snapshot.
    if (Object.hasOwn(fields, key)) return {};
    fields[key] = entry.slice(separator + 1);
  }
  return fields;
}

function finiteNumber(value: string | undefined): number | undefined {
  if (value === undefined || !/^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value)) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function percent(value: string | undefined): number | undefined {
  const parsed = finiteNumber(value);
  if (parsed === undefined || parsed < 0 || parsed > 100) return undefined;
  return parsed;
}

function parsePlayerStatus(readback: string | undefined): RuntimePlayerReadback {
  const fields = parseReadbackFields(readback);
  const health = percent(fields.health_percent);
  const stamina = percent(fields.stamina_percent);
  const bloodEnergy = finiteNumber(fields.blood);
  const maxBloodEnergy = finiteNumber(fields.blood_max);
  const level = boundedInteger(fields.level, 2_147_483_647);
  const traitPoints = boundedInteger(fields.trait_points, 2_147_483_647);
  return {
    ...(fields.alive === "1" ? { alive: true } : fields.alive === "0" ? { alive: false } : {}),
    ...(health === undefined ? {} : { health, maxHealth: 100 }),
    ...(stamina === undefined ? {} : { stamina, maxStamina: 100 }),
    ...(bloodEnergy === undefined || bloodEnergy < 0 ? {} : { bloodEnergy }),
    ...(maxBloodEnergy === undefined || maxBloodEnergy <= 0 ? {} : { maxBloodEnergy }),
    ...(level === undefined || level < 0 ? {} : { level }),
    ...(traitPoints === undefined || traitPoints < 0 ? {} : { traitPoints }),
  };
}

async function readOptionalSnapshot(
  dispatch: ReadbackDispatcher,
  capability: string,
): Promise<string | undefined> {
  try {
    const result = await dispatch({ capability });
    return result.accepted && result.status === "applied" && result.capability === capability
      ? result.readback
      : undefined;
  } catch {
    // A failed optional query has no current value. Preserve other accepted snapshots,
    // including when a transport throws before returning its promise.
    return undefined;
  }
}

function parseLocation(readback: string | undefined): RuntimePlayerReadback {
  const fields = parseReadbackFields(readback);
  const x = finiteNumber(fields.x);
  const y = finiteNumber(fields.y);
  const z = finiteNumber(fields.z);
  return {
    ...(x === undefined ? {} : { x }),
    ...(y === undefined ? {} : { y }),
    ...(z === undefined ? {} : { z }),
  };
}

function parseBoolean(readback: string | undefined): boolean | undefined {
  if (readback === "1") return true;
  if (readback === "0") return false;
  return undefined;
}

function parseGameSpeed(readback: string | undefined): number | undefined {
  const parsed = finiteNumber(readback);
  return parsed !== undefined && parsed >= 0.1 && parsed <= 3 ? parsed : undefined;
}

function parseDifficulty(readback: string | undefined): number | undefined {
  const parsed = finiteNumber(readback);
  return parsed !== undefined && Number.isInteger(parsed) && parsed >= 0 && parsed <= 3
    ? parsed
    : undefined;
}

function parseGoldQuantity(readback: string | undefined): number | undefined {
  const parsed = finiteNumber(readback);
  return parsed !== undefined && Number.isInteger(parsed) && parsed >= 0 && parsed <= 2_147_483_647
    ? parsed
    : undefined;
}

function boundedInteger(value: string | undefined, maximum = 1_000_000): number | undefined {
  const parsed = finiteNumber(value);
  if (parsed === undefined || !Number.isInteger(parsed) || parsed < 0 || parsed > maximum) return undefined;
  return parsed;
}

function parseBinaryFlag(value: string | undefined): boolean | undefined {
  if (value === "1") return true;
  if (value === "0") return false;
  return undefined;
}

function parseQuestState(value: string | undefined): RuntimeQuestState | undefined {
  return value && QUEST_STATES.has(value) ? value as RuntimeQuestState : undefined;
}

function hasControlCharacter(value: string): boolean {
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
}

function decodeQuestText(value: string | undefined): string | undefined {
  if (!value || value.length > MAX_DECODED_QUEST_TEXT_LENGTH * 3) return undefined;
  try {
    const decoded = decodeURIComponent(value);
    if (!decoded || decoded.length > MAX_DECODED_QUEST_TEXT_LENGTH || hasControlCharacter(decoded)) return undefined;
    return decoded;
  } catch {
    return undefined;
  }
}

export function parseQuestJournal(readback: string | undefined): RuntimeQuestJournalReadback | undefined {
  if (!readback || readback.length > MAX_QUEST_READBACK_BYTES) return undefined;

  type MutableQuest = Omit<RuntimeQuestReadback, "objectives"> & { objectives: RuntimeQuestObjectiveReadback[] };
  const quests: MutableQuest[] = [];
  const header: Record<string, string> = {};

  for (const record of readback.split(";")) {
    if (!record) continue;
    const separator = record.indexOf("=");
    if (separator <= 0) return undefined;
    const key = record.slice(0, separator);
    const value = record.slice(separator + 1);

    if (["schema", "open_total", "returned", "truncated"].includes(key)) {
      if (Object.hasOwn(header, key)) return undefined;
      header[key] = value;
      continue;
    }

    const fields = value.split(",");
    if (key === "q") {
      if (fields.length !== 6) return undefined;
      const index = boundedInteger(fields[0], MAX_QUESTS - 1);
      const state = parseQuestState(fields[1]);
      const tracked = parseBinaryFlag(fields[2]);
      const title = decodeQuestText(fields[3]);
      const objectiveCount = boundedInteger(fields[4]);
      const objectivesTruncated = parseBinaryFlag(fields[5]);
      if (index === undefined || index !== quests.length || !state || tracked === undefined || !title
        || objectiveCount === undefined || objectivesTruncated === undefined || quests.length >= MAX_QUESTS) return undefined;
      quests.push({ title, state, tracked, objectiveCount, objectivesTruncated, objectives: [] });
      continue;
    }

    if (key === "o") {
      if (fields.length !== 6) return undefined;
      const questIndex = boundedInteger(fields[0], MAX_QUESTS - 1);
      const state = parseQuestState(fields[1]);
      const text = decodeQuestText(fields[2]);
      const currentCount = finiteNumber(fields[3]);
      const maxCount = boundedInteger(fields[4], 1_000_000_000);
      const optional = parseBinaryFlag(fields[5]);
      const quest = questIndex === undefined ? undefined : quests[questIndex];
      if (!quest || !state || !text || currentCount === undefined || currentCount < 0 || currentCount > 1_000_000_000
        || maxCount === undefined || optional === undefined || quest.objectives.length >= MAX_OBJECTIVES_PER_QUEST) return undefined;
      quest.objectives.push({ text, state, currentCount, maxCount, optional });
      continue;
    }

    return undefined;
  }

  const openQuestCount = boundedInteger(header.open_total);
  const returnedQuestCount = boundedInteger(header.returned, MAX_QUESTS);
  const truncated = parseBinaryFlag(header.truncated);
  if (header.schema !== "1" || openQuestCount === undefined || returnedQuestCount === undefined || truncated === undefined
    || returnedQuestCount !== quests.length || returnedQuestCount > openQuestCount
    || truncated !== (returnedQuestCount < openQuestCount)) return undefined;

  for (const quest of quests) {
    if (quest.objectives.length > quest.objectiveCount
      || quest.objectivesTruncated !== (quest.objectives.length < quest.objectiveCount)) return undefined;
  }

  return {
    openQuestCount,
    returnedQuestCount,
    truncated,
    quests: quests.map((quest) => ({ ...quest, objectives: [...quest.objectives] })),
  };
}

export async function collectRuntimePlayerReadback(
  capabilities: readonly string[],
  dispatch: ReadbackDispatcher,
): Promise<RuntimePlayerReadback | undefined> {
  const capabilitySet = new Set(capabilities);
  const requests: Promise<RuntimePlayerReadback>[] = [];

  if (capabilitySet.has("player:player-info")) {
    requests.push(readOptionalSnapshot(dispatch, "player:player-info").then(parsePlayerStatus));
  }
  if (capabilitySet.has("world:location-readback")) {
    requests.push(readOptionalSnapshot(dispatch, "world:location-readback").then(parseLocation));
  }
  if (capabilitySet.has("player:add-gold")) {
    requests.push(readOptionalSnapshot(dispatch, "player:add-gold").then((readback) => {
      const gold = parseGoldQuantity(readback);
      return gold === undefined ? {} : { gold };
    }));
  }
  if (requests.length === 0) return undefined;

  const snapshots = await Promise.all(requests);
  const merged = Object.assign({}, ...snapshots) as RuntimePlayerReadback;
  return Object.keys(merged).length > 0 ? merged : undefined;
}

export async function collectRuntimeControlReadback(
  capabilities: readonly string[],
  dispatch: ReadbackDispatcher,
): Promise<RuntimeControlReadback | undefined> {
  const capabilitySet = new Set(capabilities);
  const requests: Promise<RuntimeControlReadback>[] = [];

  if (capabilitySet.has("visuals:hud-visible")) {
    requests.push(readOptionalSnapshot(dispatch, "visuals:hud-visible").then((readback) => {
      const hudVisible = parseBoolean(readback);
      return hudVisible === undefined ? {} : { hudVisible };
    }));
  }
  if (capabilitySet.has("world:game-speed")) {
    requests.push(readOptionalSnapshot(dispatch, "world:game-speed").then((readback) => {
      const gameSpeed = parseGameSpeed(readback);
      return gameSpeed === undefined ? {} : { gameSpeed };
    }));
  }
  if (capabilitySet.has("combat:rpg-difficulty")) {
    requests.push(readOptionalSnapshot(dispatch, "combat:rpg-difficulty").then((readback) => {
      const rpgDifficulty = parseDifficulty(readback);
      return rpgDifficulty === undefined ? {} : { rpgDifficulty };
    }));
  }
  if (capabilitySet.has("combat:action-difficulty")) {
    requests.push(readOptionalSnapshot(dispatch, "combat:action-difficulty").then((readback) => {
      const actionDifficulty = parseDifficulty(readback);
      return actionDifficulty === undefined ? {} : { actionDifficulty };
    }));
  }
  if (requests.length === 0) return undefined;

  const snapshots = await Promise.all(requests);
  const merged = Object.assign({}, ...snapshots) as RuntimeControlReadback;
  return Object.keys(merged).length > 0 ? merged : undefined;
}

export async function collectRuntimeQuestJournalReadback(
  capabilities: readonly string[],
  dispatch: ReadbackDispatcher,
): Promise<RuntimeQuestJournalReadback | undefined> {
  if (!capabilities.includes("quests:journal-readback")) return undefined;
  return parseQuestJournal(await readOptionalSnapshot(dispatch, "quests:journal-readback"));
}

export const runtimeReadbackTestApi = Object.freeze({
  parseBoolean,
  parseDifficulty,
  parseGameSpeed,
  parseGoldQuantity,
  parseLocation,
  parsePlayerStatus,
  parseQuestJournal,
  parseReadbackFields,
});
