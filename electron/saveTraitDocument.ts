import type { DsavDocument } from "./dsavContainer.js";
import { writePacked } from "./recordCursor.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_trait_document");

// Port of the owner's DwSav TraitDocument as a writable model: the
// CharacterDevelopmentSubsystem record is parsed into its ledger prefix, the five
// name -> u32 dictionaries, the progression names, the ability loadout and the
// trailing flag, edited, and serialised again so rebuildPayload can splice it back.
// AcquireRankPreservingLoadout and SetBookAccess are the mutations; the parse walks
// the record to its exact end before anything is written.

const TRAIT_PREFIX_BYTES = 17;
const MAX_TRAIT_RANK = 32;
const MAX_DICTIONARY_ROWS = 4096;
const MAX_ABILITY_GROUPS = 256;
const LEDGER_SPENT_OFFSET = 12;

export type TraitValueRow = { id: string; value: number };

export type TraitAbilityGroupRecord = { key: number; names: string[] };

export type WritableTraitDocument = {
  prefix: Buffer;
  /** section 0: rank per trait; section 1: highest rank ever held; section 2 missing (progression names); section 3: book access; sections 4/5: verbatim extras */
  dictionaries: Map<string, number>[];
  progressionNames: string[];
  abilityNames: string[];
  abilityGroups: TraitAbilityGroupRecord[];
  trailingFlag: boolean;
  tailByte: number;
};

class TraitCursor {
  position: number;
  constructor(private readonly bytes: Buffer, start: number, private readonly end: number) {
    this.position = start;
  }
  get remaining(): number { return this.end - this.position; }
  private take(count: number): number {
    if (count > this.remaining) throw new Error("Character traits: record ends inside a field.");
    const at = this.position;
    this.position += count;
    return at;
  }
  u8(): number { return this.bytes[this.take(1)]; }
  u32(): number { return this.bytes.readUInt32LE(this.take(4)); }
  requireArray(count: number, stride: number): void {
    if (stride <= 0 || count > Math.floor(this.remaining / stride)) throw new Error("Character traits: count exceeds the remaining record.");
  }
  packed(): number {
    let value = 0;
    for (let index = 0; index < 5; index++) {
      const byte = this.u8();
      const bits = byte >>> 1;
      if (index === 4 && bits > 15) throw new Error("Character traits: packed u32 overflow.");
      value |= bits << (7 * index);
      if ((byte & 1) === 0) return value >>> 0;
    }
    throw new Error("Character traits: overlong packed u32.");
  }
}

export function developmentPrefixSpan(document: DsavDocument): { start: number; end: number } | undefined {
  const index = document.nodes.findIndex(node => node.name === "CharacterDevelopmentSubsystem");
  if (index < 0) return undefined;
  const node = document.nodes[index];
  const prefixEnd = node.childIndex !== 65535 ? document.nodes[node.childIndex].offset : node.offset + node.size;
  return { start: node.offset + 4, end: prefixEnd };
}

function firstNameIndexes(names: readonly string[]): Map<string, number> {
  const firstIndexOf = new Map<string, number>();
  names.forEach((name, index) => { if (!firstIndexOf.has(name)) firstIndexOf.set(name, index + 1); });
  return firstIndexOf;
}

function readName(cursor: TraitCursor, document: DsavDocument, firstIndexOf: ReadonlyMap<string, number>): string {
  const reference = cursor.packed();
  if (reference === 0 || reference > document.names.length) throw new Error("Character traits: invalid name reference.");
  const name = document.names[reference - 1];
  if (!name || name.includes("\0") || firstIndexOf.get(name) !== reference) throw new Error("Character traits: name reference is noncanonical or ambiguous for rewriting.");
  return name;
}

function readCount(cursor: TraitCursor, limit: number, stride: number): number {
  const count = cursor.u32();
  if (count > limit) throw new Error("Character traits: unexpected section count.");
  cursor.requireArray(count, stride);
  return count;
}

function readNames(cursor: TraitCursor, document: DsavDocument, firstIndexOf: ReadonlyMap<string, number>): string[] {
  const count = readCount(cursor, MAX_DICTIONARY_ROWS, 1);
  const names: string[] = [];
  for (let index = 0; index < count; index++) names.push(readName(cursor, document, firstIndexOf));
  return names;
}

/** Parses the CharacterDevelopmentSubsystem record into an editable model; undefined when the save has none. */
export function readWritableTraitDocument(document: DsavDocument): WritableTraitDocument | undefined {
  const span = developmentPrefixSpan(document);
  if (!span) return undefined;
  const cursor = new TraitCursor(document.payload, span.start, span.end);
  if (cursor.remaining < TRAIT_PREFIX_BYTES) return undefined;
  const prefix = document.payload.subarray(cursor.position, cursor.position + TRAIT_PREFIX_BYTES);
  cursor.position += TRAIT_PREFIX_BYTES;
  const firstIndexOf = firstNameIndexes(document.names);
  const dictionaries: Map<string, number>[] = [];
  let progressionNames: string[] = [];
  for (let section = 0; section < 6; section++) {
    if (section === 2) { progressionNames = readNames(cursor, document, firstIndexOf); continue; }
    const count = readCount(cursor, MAX_DICTIONARY_ROWS, 5);
    const rows = new Map<string, number>();
    for (let index = 0; index < count; index++) {
      const name = readName(cursor, document, firstIndexOf);
      const value = cursor.u32();
      if (value > MAX_TRAIT_RANK || rows.has(name)) throw new Error("Character traits: unsupported trait dictionary.");
      rows.set(name, value);
    }
    dictionaries.push(rows);
  }
  const abilityNamesPosition = cursor.position;
  const abilityNames = readNames(cursor, document, firstIndexOf);
  const groupCount = readCount(cursor, MAX_ABILITY_GROUPS, 5);
  const abilityGroups: TraitAbilityGroupRecord[] = [];
  const groupKeys = new Set<number>();
  for (let index = 0; index < groupCount; index++) {
    const key = cursor.u8();
    if (groupKeys.has(key)) throw new Error("Character traits: duplicate ability-group key.");
    groupKeys.add(key);
    abilityGroups.push({ key, names: readNames(cursor, document, firstIndexOf) });
  }
  const flag = cursor.u32();
  if (flag > 1) throw new Error("Character traits: invalid trailing flag.");
  const tailByte = cursor.u8();
  if (cursor.remaining !== 0) throw new Error("Character traits: unexpected trailing bytes.");
  return { prefix: Buffer.from(prefix), dictionaries, progressionNames, abilityNames, abilityGroups, trailingFlag: flag === 1, tailByte };
  // (abilityNamesPosition kept for symmetry with the record layout; the loadout region
  // is rebuilt from the parsed lists on serialise, so no raw slice is retained.)
  void abilityNamesPosition;
}

function writeNameReference(parts: Buffer[], nameIndexValue: number): void {
  parts.push(writePacked(nameIndexValue));
}

/** Serialises the model back into record bytes; nameIndex resolves each name to its 1-based table slot. */
export function serializeTraitDocument(document: WritableTraitDocument, nameIndex: (name: string) => number): Buffer {
  const parts: Buffer[] = [document.prefix];
  const names = (list: readonly string[]): void => {
    const count = Buffer.alloc(4);
    count.writeUInt32LE(list.length);
    parts.push(count);
    for (const name of list) writeNameReference(parts, nameIndex(name));
  };
  const dictionaries = [...document.dictionaries];
  let mapIndex = 0;
  for (let section = 0; section < 6; section++) {
    if (section === 2) { names(document.progressionNames); continue; }
    const rows = dictionaries[mapIndex++];
    const count = Buffer.alloc(4);
    count.writeUInt32LE(rows.size);
    parts.push(count);
    for (const [name, value] of rows) {
      writeNameReference(parts, nameIndex(name));
      const cell = Buffer.alloc(4);
      cell.writeUInt32LE(value >>> 0);
      parts.push(cell);
    }
  }
  names(document.abilityNames);
  const groupCount = Buffer.alloc(4);
  groupCount.writeUInt32LE(document.abilityGroups.length);
  parts.push(groupCount);
  for (const group of document.abilityGroups) {
    parts.push(Buffer.from([group.key & 0xff]));
    names(group.names);
  }
  const trailing = Buffer.alloc(5);
  trailing.writeUInt32LE(document.trailingFlag ? 1 : 0);
  trailing.writeUInt8(document.tailByte, 4);
  parts.push(trailing);
  return Buffer.concat(parts);
}

export function spentSkillPointsOf(document: WritableTraitDocument): number {
  return document.prefix.readUInt32LE(LEDGER_SPENT_OFFSET);
}

/** Port of TraitDocument.AcquireRankPreservingLoadout: sets the rank and highest-rank rows. */
export function acquireRankPreservingLoadout(document: WritableTraitDocument, id: string, rank: number): void {
  if (typeof id !== "string" || id.length === 0) throw new Error("Rank acquisition requires a supported rank above the current rank.");
  if (!Number.isInteger(rank) || rank < 1 || rank > 4 || rank <= (document.dictionaries[0].get(id) ?? 0)) throw new Error("Rank acquisition requires a supported rank above the current rank.");
  for (const index of [0, 1]) {
    if (!document.dictionaries[index].has(id) && document.dictionaries[index].size >= MAX_DICTIONARY_ROWS) throw new Error("Trait rank or history dictionary exceeds the supported limit.");
  }
  document.dictionaries[0].set(id, rank);
  document.dictionaries[1].set(id, Math.max(rank, document.dictionaries[1].get(id) ?? 0));
}

/** Port of TraitDocument.SetBookAccess: raises the section-3 access row, never lowers it. */
export function setBookAccess(document: WritableTraitDocument, id: string, accessLevel: number): void {
  if (typeof id !== "string" || id.length === 0 || !Number.isInteger(accessLevel) || accessLevel > 32 || accessLevel === 0) throw new Error("Invalid book access request.");
  const current = document.dictionaries[2].get(id) ?? 0;
  if (accessLevel < current) throw new Error("Book access cannot be lowered.");
  if (!document.dictionaries[2].has(id) && document.dictionaries[2].size >= MAX_DICTIONARY_ROWS) throw new Error("Trait access dictionary exceeds the supported limit.");
  document.dictionaries[2].set(id, accessLevel);
}
