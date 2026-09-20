import type { DsavDocument } from "./dsavContainer.js";
import { RecordCursor } from "./recordCursor.js";
import { recordPrefixSpan } from "./saveStructural.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_save_journal");

// DwSav JournalDocument / JournalGuid / ExperimentalQuestTracking: preserve the
// entire journal prefix except the final secondary tracked-objective pair.
export type JournalTrackedObjective = Readonly<{ instanceId: string; objectiveGuid: string }>;
export type JournalObjective = Readonly<{ key: number; state: number; counter: number; revealedAt: string }>;
export type JournalQuest = Readonly<{ finished: boolean; state: number; ending: number; assetPath: string; objectives: readonly JournalObjective[] }>;
export type SaveJournal = Readonly<{ quests: readonly JournalQuest[]; trackedMain: JournalTrackedObjective; trackedOther: JournalTrackedObjective; prefix: Buffer; otherOffset: number }>;
export type QuestMetadata = Readonly<{ assetPath: string; guid: string; title: string | null; newType: number | null; objectives: readonly Readonly<{ guid: string; name: string | null }>[] }>;
export type QuestCatalog = ReadonlyMap<string, QuestMetadata>;
export type QuestTrackingRequest = Readonly<{ assetPath: string; objectiveGuid: string; expectedMain: JournalTrackedObjective; expectedOther: JournalTrackedObjective }>;
export type QuestTrackingOption = Readonly<{ assetPath: string; title: string; objectiveGuid: string; objectiveName: string }>;

/** IPC-facing contract: only the asset identity and two serializable tracked pairs. */
export function validateQuestTrackingRequest(input: unknown): QuestTrackingRequest {
  const row = object(input);
  requireCondition(typeof row.assetPath === "string" && row.assetPath.startsWith("/Game/") && row.assetPath.length <= 2048 && !controls.test(row.assetPath), "Invalid quest asset path.");
  const tracked = (input: unknown): JournalTrackedObjective => {
    const pair = object(input);
    requireCondition(typeof pair.instanceId === "string" && !controls.test(pair.instanceId) && Buffer.byteLength(pair.instanceId, "utf8") <= 254 && Buffer.from(pair.instanceId, "utf8").toString("utf8") === pair.instanceId, "Invalid tracked quest instance.");
    return { instanceId: pair.instanceId, objectiveGuid: canonicalGuid(pair.objectiveGuid) };
  };
  return { assetPath: row.assetPath, objectiveGuid: canonicalGuid(row.objectiveGuid), expectedMain: tracked(row.expectedMain), expectedOther: tracked(row.expectedOther) };
}

function requireCondition(condition: unknown, message: string): asserts condition { if (!condition) throw new Error(message); }
const controls = { test: (text: string) => [...text].some(character => { const code = character.charCodeAt(0); return code < 32 || (code >= 127 && code <= 159); }) };
const zeroGuid = "00000000-00000000-00000000-00000000";
function canonicalGuid(value: unknown): string {
  requireCondition(typeof value === "string" && /^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{8}){3}$/.test(value), "Invalid Journal GUID.");
  return value.toUpperCase();
}
export function journalObjectiveKey(guid: string): number {
  const [a, b, c, d] = canonicalGuid(guid).split("-").map(value => BigInt(`0x${value}`));
  const wrap = (value: bigint) => BigInt.asUintN(64, value);
  const rotate = (value: bigint, count: bigint) => wrap((value >> count) | (value << (64n - count)));
  const lo = a | b << 32n; const hi = c | d << 32n;
  const multiplier = 11160318154034397295n;
  const base = wrap(lo + 11160318154034397263n);
  const first = wrap(rotate(hi, 37n) * multiplier + base);
  const second = wrap(wrap(rotate(base, 25n) + hi) * multiplier);
  const third = wrap((second ^ first) * multiplier);
  const fourth = wrap((third ^ third >> 47n ^ second) * multiplier);
  return Number(BigInt.asUintN(32, (fourth ^ fourth >> 47n) * multiplier));
}
function readState(cursor: RecordCursor): number { const value = cursor.u8(); requireCondition(value <= 3, "Invalid Journal state."); return value; }
function readTracked(cursor: RecordCursor): JournalTrackedObjective {
  const length = cursor.u8(); requireCondition(length !== 255, "Unsupported extended Journal instance string.");
  const bytes = cursor.slice(length);
  let instanceId: string;
  try { instanceId = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); }
  catch (error) { throw new Error("Invalid Journal instance UTF-8.", { cause: error }); }
  requireCondition(!controls.test(instanceId), "Invalid Journal instance text.");
  const words = Array.from({ length: 4 }, () => cursor.u32().toString(16).padStart(8, "0").toUpperCase());
  return { instanceId, objectiveGuid: words.join("-") };
}
export function parseJournalPrefix(prefix: Buffer, names: readonly string[]): SaveJournal {
  const cursor = new RecordCursor(prefix, 0, prefix.length, "Journal");
  const quests: JournalQuest[] = []; let total = 0;
  const matchedCount = (count: number, stride: number) => { requireCondition(cursor.u16() === count, "Mismatched Journal objective array lengths."); cursor.requireArray(count, stride); };
  for (let group = 0; group < 2; group++) {
    const count = cursor.u32(); requireCondition(count <= 4096, "Journal quest count exceeds 4096."); cursor.requireArray(count, 11);
    for (let index = 0; index < count; index++) {
      const state = readState(cursor); const objectiveCount = cursor.u16(); total += objectiveCount;
      requireCondition(objectiveCount <= 4096 && total <= 65536, "Journal objective count exceeds the supported limit.");
      cursor.requireArray(objectiveCount, 4);
      const keys = Array.from({ length: objectiveCount }, () => cursor.u32());
      requireCondition(new Set(keys).size === keys.length, "Duplicate Journal objective key.");
      matchedCount(objectiveCount, 8);
      const timestamps = keys.map(() => { const value = cursor.slice(8).readBigInt64LE(); requireCondition(value >= 0n, "Negative Journal reveal timestamp."); return value.toString(); });
      matchedCount(objectiveCount, 4);
      const counters = keys.map(() => { const value = cursor.u32(); requireCondition(value <= 0x7fffffff, "Negative Journal objective counter."); return value; });
      matchedCount(objectiveCount, 1);
      const objectives = keys.map((key, i) => ({ key, state: readState(cursor), counter: counters[i], revealedAt: timestamps[i] }));
      const reference = cursor.packed(); const nameIndex = reference & 0xffff; const suffix = reference >>> 16;
      requireCondition(nameIndex > 0 && nameIndex <= names.length, "Invalid Journal asset name reference.");
      let assetPath = names[nameIndex - 1]; requireCondition(assetPath.startsWith("/Game/") && !controls.test(assetPath), "Invalid Journal asset path.");
      if (suffix !== 0) assetPath += `_${suffix - 1}`;
      quests.push({ finished: group === 1, state, ending: cursor.u8(), assetPath, objectives });
    }
  }
  const trackedMain = readTracked(cursor); const otherOffset = cursor.position; const trackedOther = readTracked(cursor);
  requireCondition(cursor.remaining === 0, "Unexpected Journal trailing bytes.");
  return { quests, trackedMain, trackedOther, prefix: Buffer.from(prefix), otherOffset };
}
export function readSaveJournal(document: DsavDocument): SaveJournal | undefined {
  requireCondition(document.nodes.filter(node => node.name === "Journal").length <= 1, "Ambiguous Journal record.");
  const span = recordPrefixSpan(document, "Journal");
  if (!span) return undefined;
  requireCondition(span.start >= 0 && span.end >= span.start && span.end <= document.payload.length, "Invalid Journal record bounds.");
  return parseJournalPrefix(document.payload.subarray(span.start, span.end), document.names);
}
function object(value: unknown): Record<string, unknown> { requireCondition(typeof value === "object" && value !== null && !Array.isArray(value), "Invalid Quest catalog identity."); return value as Record<string, unknown>; }
function optionalText(value: unknown): string | null { requireCondition(value === undefined || value === null || (typeof value === "string" && value.length <= 32768 && !value.includes("\0")), "Invalid Quest catalog text."); return typeof value === "string" ? value : null; }
export function parseQuestCatalog(text: string): QuestCatalog {
  requireCondition(typeof text === "string" && Buffer.byteLength(text, "utf8") <= 8388608, "Quest catalog exceeds 8 MiB.");
  const rows: unknown = JSON.parse(text); requireCondition(Array.isArray(rows) && rows.length <= 4096, "Quest catalog exceeds 4096 entries.");
  const entries = new Map<string, QuestMetadata>(); const identities = new Set<string>(); let total = 0;
  for (const value of rows) {
    const row = object(value); const assetPath = row.AssetPath; const guid = canonicalGuid(row.Guid);
    requireCondition(typeof assetPath === "string" && assetPath.length <= 2048 && assetPath.startsWith("/Game/") && !controls.test(assetPath) && !identities.has(guid), "Invalid or duplicate Quest catalog identity.");
    requireCondition(Array.isArray(row.Objectives) && row.Objectives.length <= 4096 && Array.isArray(row.Endings) && row.Endings.length <= 256, "Invalid Quest catalog objective or ending count.");
    requireCondition(row.NewType === undefined || row.NewType === null || (typeof row.NewType === "number" && Number.isInteger(row.NewType) && row.NewType >= 0 && row.NewType <= 2), "Invalid Quest catalog type.");
    total += row.Objectives.length; requireCondition(total <= 65536, "Quest catalog objective count exceeds 65536.");
    const objectiveKeys = new Set<number>();
    const objectives = row.Objectives.map(value => { const entry = object(value); const guid = canonicalGuid(entry.Guid); const key = journalObjectiveKey(guid); requireCondition(!objectiveKeys.has(key), "Invalid or ambiguous Quest objective identity."); objectiveKeys.add(key); return { guid, name: optionalText(entry.Name) }; });
    const endings = new Set<number>();
    for (const value of row.Endings) { const ending = object(value); requireCondition(typeof ending.Id === "number" && Number.isInteger(ending.Id) && ending.Id >= 0 && ending.Id <= 255 && !endings.has(ending.Id), "Invalid or duplicate Quest ending identity."); endings.add(ending.Id); optionalText(ending.Description); }
    const key = assetPath.toLowerCase(); requireCondition(!entries.has(key), "Duplicate Quest asset path identity.");
    optionalText(row.Description); identities.add(guid);
    entries.set(key, { assetPath, guid, title: optionalText(row.Title), newType: typeof row.NewType === "number" ? row.NewType : null, objectives });
  }
  return entries;
}
function sameTracked(first: JournalTrackedObjective, second: JournalTrackedObjective): boolean { return first.instanceId === second.instanceId && canonicalGuid(first.objectiveGuid) === canonicalGuid(second.objectiveGuid); }
function replacementFor(quest: JournalQuest, metadata: QuestMetadata, guid: string): JournalTrackedObjective {
  const dot = quest.assetPath.lastIndexOf("."); const name = quest.assetPath.slice(dot + 1);
  requireCondition(dot >= 0 && name.length > 0 && !name.includes("/"), "Unsupported quest asset object name.");
  return { instanceId: name + metadata.guid.replaceAll("-", ""), objectiveGuid: guid };
}
export function questTrackingOptions(document: DsavDocument, catalog: QuestCatalog): Readonly<{ options: readonly QuestTrackingOption[]; trackedMain: JournalTrackedObjective; trackedOther: JournalTrackedObjective }> {
  const journal = readSaveJournal(document); requireCondition(journal, "Missing Journal.");
  const options: QuestTrackingOption[] = [];
  for (const quest of journal.quests) {
    const metadata = catalog.get(quest.assetPath.toLowerCase());
    if (quest.finished || quest.state !== 1 || !metadata || (metadata.newType !== 1 && metadata.newType !== 2) || metadata.guid === zeroGuid || journal.quests.filter(row => row.assetPath.toLowerCase() === quest.assetPath.toLowerCase()).length !== 1) continue;
    for (const objective of metadata.objectives) {
      if (objective.guid === zeroGuid || !quest.objectives.some(row => row.key === journalObjectiveKey(objective.guid) && row.state === 1)) continue;
      const replacement = replacementFor(quest, metadata, objective.guid);
      if (Buffer.byteLength(replacement.instanceId, "utf8") > 254) continue;
      options.push({ assetPath: quest.assetPath, title: metadata.title ?? quest.assetPath, objectiveGuid: objective.guid, objectiveName: objective.name ?? objective.guid });
    }
  }
  return { options, trackedMain: journal.trackedMain, trackedOther: journal.trackedOther };
}
export function planQuestTracking(document: DsavDocument, request: QuestTrackingRequest, catalog: QuestCatalog): Readonly<{ prefix: Buffer; expectedMain: JournalTrackedObjective; expectedOther: JournalTrackedObjective; changed: boolean }> {
  requireCondition(document.container.header.length >= 12 && document.container.header.readUInt16LE(8) === 134 && document.container.header.readUInt16LE(10) === 5, "Quest tracking requires DSAV 134 / game 5.");
  const journal = readSaveJournal(document); requireCondition(journal, "Missing Journal.");
  requireCondition(sameTracked(journal.trackedMain, request.expectedMain) && sameTracked(journal.trackedOther, request.expectedOther), "Tracked quests no longer match the preview. Reload the save.");
  requireCondition(typeof request.assetPath === "string", "Invalid quest asset path.");
  const matches = journal.quests.filter(row => row.assetPath.toLowerCase() === request.assetPath.toLowerCase());
  requireCondition(matches.length === 1 && !matches[0].finished && matches[0].state === 1, "Tracking requires one existing opened active quest.");
  const quest = matches[0]; const metadata = catalog.get(quest.assetPath.toLowerCase());
  requireCondition(metadata && (metadata.newType === 1 || metadata.newType === 2), "Tracking requires verified Story or NanoPOI quest metadata. MainGoal and unknown types remain unchanged.");
  const guid = canonicalGuid(request.objectiveGuid); requireCondition(metadata.guid !== zeroGuid && guid !== zeroGuid, "Missing quest or objective GUID identity.");
  const key = journalObjectiveKey(guid); const objectives = metadata.objectives.filter(row => journalObjectiveKey(row.guid) === key);
  requireCondition(objectives.length === 1 && objectives[0].guid === guid, "The selected objective has no unambiguous catalog GUID.");
  const saved = quest.objectives.filter(row => row.key === key); requireCondition(saved.length === 1 && saved[0].state === 1, "The selected objective is not active in this saved quest.");
  const replacement = replacementFor(quest, metadata, guid); const bytes = Buffer.from(replacement.instanceId, "utf8");
  requireCondition(bytes.length > 0 && bytes.length <= 254 && !controls.test(replacement.instanceId) && bytes.toString("utf8") === replacement.instanceId, "Invalid tracked quest instance UTF-8 or length.");
  const words = Buffer.alloc(16); guid.split("-").forEach((word, index) => words.writeUInt32LE(parseInt(word, 16), index * 4));
  const prefix = Buffer.concat([journal.prefix.subarray(0, journal.otherOffset), Buffer.from([bytes.length]), bytes, words]);
  const rebuilt = parseJournalPrefix(prefix, document.names);
  requireCondition(sameTracked(rebuilt.trackedMain, journal.trackedMain) && sameTracked(rebuilt.trackedOther, replacement), "Rebuilt tracked quests do not match the requested pair.");
  return { prefix, expectedMain: journal.trackedMain, expectedOther: replacement, changed: !sameTracked(journal.trackedOther, replacement) };
}
