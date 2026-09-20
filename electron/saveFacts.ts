import type { DsavDocument } from "./dsavContainer.js";
import { recordPrefixSpan } from "./saveStructural.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_facts");

function requireCondition(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

// Port of the owner's DwSav FactsDocument / ExperimentalFactChange /
// ExperimentalInfamyChange (DWSav.Core.Fields). The FactsDB record is a flat
// (u16 header, u32 count, count × (u32 tag id, i32 value)) table that must parse to
// its exact end. Edits rebuild the record and are only accepted when every mapped
// precondition still holds on the save being edited.

export type FactsValues = ReadonlyMap<number, number>;

export const INFAMY_POINTS_TAG = "Court.StoredAlertLevel";
export const INFAMY_LEVEL_TAG = "Court.AlertLevel";
export const INFAMY_PENDING_TAG = "Court.AlertLevelsToHandle";
export const ACTIVE_EDICTS_TAG = "Court.ActiveEdictsNum";

// Declared before COURT_IDENTIFIERS: the table must exist before the module-level
// tag hashing runs (a `let` referenced earlier would be a temporal-dead-zone error).
let cachedHashTable: Uint32Array | undefined;
function hashTable(): Uint32Array {
  if (cachedHashTable) return cachedHashTable;
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index << 24;
    for (let bit = 0; bit < 8; bit += 1) value = ((value << 1) ^ ((value & 0x80000000) !== 0 ? 79764919 : 0)) >>> 0;
    table[index] = value >>> 0;
  }
  cachedHashTable = table;
  return table;
}

/** Court facts are coupled; they may only change through the infamy editor. */
const COURT_IDENTIFIERS: readonly number[] = [INFAMY_POINTS_TAG, INFAMY_LEVEL_TAG, INFAMY_PENDING_TAG, ACTIVE_EDICTS_TAG].map(tagId);

export function tagId(tag: string): number {
  if (typeof tag !== "string" || tag.length === 0 || /[^\x21-\x7e]/.test(tag)) throw new Error("Use a nonempty ASCII gameplay tag without spaces.");
  const table = hashTable();
  let hash = 0;
  for (const character of tag) {
    const upper = character >= "a" && character <= "z" ? character.charCodeAt(0) - 32 : character.charCodeAt(0);
    hash = ((hash >>> 8) ^ table[(hash ^ upper) & 0xff]) >>> 0;
    hash = ((hash >>> 8) ^ table[hash & 0xff]) >>> 0;
  }
  return hash >>> 0;
}

export type FactsDocument = Readonly<{ values: FactsValues }>;

/** Parses the FactsDB record; undefined when the save has none. */
export function readFactsDocument(document: DsavDocument): FactsDocument | undefined {
  const span = recordPrefixSpan(document, "FactsDB");
  if (!span) return undefined;
  const bytes = document.payload;
  const cursor = { position: span.start };
  const readU16 = (): number => {
    requireCondition(cursor.position + 2 <= span.end, "FactsDB record overruns its boundary.");
    const value = bytes.readUInt16LE(cursor.position);
    cursor.position += 2;
    return value;
  };
  const readU32 = (): number => {
    requireCondition(cursor.position + 4 <= span.end, "FactsDB record overruns its boundary.");
    const value = bytes.readUInt32LE(cursor.position);
    cursor.position += 4;
    return value;
  };
  requireCondition(readU16() === 1, "Unsupported FactsDB header.");
  const count = readU32();
  requireCondition(count <= 1_000_000, "FactsDB count exceeds the supported limit.");
  requireCondition(count * 8 === span.end - cursor.position, "Unexpected FactsDB trailing bytes; ambiguous record boundary.");
  const values = new Map<number, number>();
  for (let index = 0; index < count; index += 1) {
    const key = readU32();
    const value = readU32() | 0;
    requireCondition(!values.has(key), "Duplicate FactsDB identifier.");
    values.set(key, value);
  }
  return { values };
}

export function serializeFactsValues(values: ReadonlyMap<number, number>): Buffer {
  requireCondition(values.size <= 1_000_000, "FactsDB count exceeds the supported limit.");
  const parts: Buffer[] = [];
  const header = Buffer.alloc(6);
  header.writeUInt16LE(1);
  header.writeUInt32LE(values.size, 2);
  parts.push(header);
  for (const [key, value] of values) {
    const row = Buffer.alloc(8);
    row.writeUInt32LE(key >>> 0);
    row.writeInt32LE(value | 0, 4);
    parts.push(row);
  }
  return Buffer.concat(parts);
}

export type CourtState = Readonly<{ points: number; level: number; pending: number; activeEdicts: number }>;

export function readCourtState(values: FactsValues): CourtState {
  const value = (tag: string): number => values.get(tagId(tag)) ?? 0;
  return { points: value(INFAMY_POINTS_TAG), level: value(INFAMY_LEVEL_TAG), pending: value(INFAMY_PENDING_TAG), activeEdicts: value(ACTIVE_EDICTS_TAG) };
}

/** Port of DwSav's CourtSettings check: the local DefaultGame.ini must still match the mapped nine-stage profile. */
export function validateCourtConfig(gameConfig: string): void {
  if (typeof gameConfig !== "string" || gameConfig.length > 4_194_304) throw new Error("Game configuration exceeds the research limit.");
  const sections = gameConfig.split("[/Script/DogwoodQuest.CourtSettings]");
  if (sections.length !== 2) throw new Error("Expected one local CourtSettings section.");
  const body = sections[1].split(/^\s*\[/m, 2)[0];
  const lines = body.split("\n").map((line) => line.trim()).filter((line) => line.length !== 0 && !line.startsWith(";"));
  const one = (key: string, expected: string): boolean => {
    const matches = lines.filter((line) => line.startsWith(`${key}=`));
    return matches.length === 1 && lines.includes(`${key}=${expected}`);
  };
  const edicts = lines.filter((line) => line.startsWith("+Edicts="));
  const overridden = lines.some((line) => line.startsWith("!Edicts") || line.startsWith("-Edicts") || line.startsWith("Edicts="));
  const ok = one("MaxAlertLevel", "900")
    && one("AlertLevelTag", '(TagName="Court.AlertLevel")')
    && one("AlertLevelsToHandleTag", '(TagName="Court.AlertLevelsToHandle")')
    && one("AlertStagesThresholds", "((High, 9),(Medium, 6),(Low, 3))")
    && edicts.length === 9
    && edicts.every((line) => line.endsWith(",EdictFacts=)"))
    && !overridden;
  if (!ok) throw new Error("Court configuration differs from the mapped nine-stage profile; refresh or investigate before editing.");
}

export type FactChange = Readonly<{ tag: string; value: number; expectedValue?: number }>;

/** Replaces existing FactsDB entries (never adds or removes); court facts are refused. */
export function planFactChanges(document: DsavDocument, changes: readonly FactChange[]): Readonly<{ facts: FactsDocument; next: Map<number, number> }> {
  const facts = readFactsDocument(document);
  requireCondition(facts !== undefined, "Missing FactsDB in this save.");
  const next = new Map(facts!.values);
  for (const change of changes) {
    const identifier = tagId(change.tag);
    requireCondition(!COURT_IDENTIFIERS.includes(identifier), `Court facts have coupled progression rules; use the Infamy editor for ${change.tag}.`);
    const current = facts!.values.get(identifier);
    requireCondition(current !== undefined, `The selected fact ${change.tag} is absent. Advanced fact changes only replace existing entries.`);
    if (change.expectedValue !== undefined) requireCondition(current === change.expectedValue, `The selected fact ${change.tag} no longer matches its original value. Reload the save.`);
    next.set(identifier, change.value | 0);
  }
  return { facts: facts!, next };
}

export const MAX_INFAMY_POINTS = 900;

/** Port of ExperimentalInfamyChange.Apply over a fact table; returns the next table. */
export function planInfamyChangeOnValues(values: FactsValues, targetPoints: number, gameConfig: string): Readonly<{ next: Map<number, number>; changed: boolean }> {
  validateCourtConfig(gameConfig);
  requireCondition(Number.isInteger(targetPoints) && targetPoints >= 0 && targetPoints <= MAX_INFAMY_POINTS, "Infamy research requires DSAV134/game5 and 0-900 points.");
  const court = readCourtState(values);
  const consistent = court.level === Math.floor(court.points / 100)
    && court.activeEdicts >= 0
    && court.activeEdicts <= 9
    && court.level - court.pending === court.activeEdicts;
  requireCondition(consistent, "Court state is inconsistent with the mapped profile; no repair was guessed.");
  if (targetPoints === court.points) return { next: new Map(values), changed: false };
  const targetLevel = Math.floor(targetPoints / 100);
  requireCondition(targetLevel >= court.activeEdicts, `Infamy cannot be reduced below ${court.activeEdicts * 100} points while ${court.activeEdicts} edicts are enacted. A negative pending balance can trigger additional edicts at dawn.`);
  const next = new Map(values);
  next.set(tagId(INFAMY_POINTS_TAG), targetPoints);
  if (targetLevel !== court.level) {
    next.set(tagId(INFAMY_LEVEL_TAG), targetLevel);
    next.set(tagId(INFAMY_PENDING_TAG), court.pending + targetLevel - court.level);
  }
  return { next, changed: true };
}
