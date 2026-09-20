import type { DsavDocument } from "./dsavContainer.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_traits");

// Perk ("trait") state lives in the CharacterDevelopmentSubsystem record after the
// 17-byte ledger prefix (level, XP, skill points, spent points, state byte). The layout
// mirrors the owner's DwSav TraitDocument.Read, checked here by walking the record to
// its exact end:
//   section 0  rank per trait            name -> u32   (edited here, in place)
//   section 1  highest rank ever held    name -> u32   (raised with the rank)
//   section 2  progression trait names   name list
//   section 3  book/access limit         name -> u32
//   section 4, 5  further dictionaries   name -> u32   (kept verbatim)
//   ability names, ability groups (u8 key + names), trailing u32 flag, one byte.
// Names are 1-based references into the save's name table, packed 7 bits per byte with
// the low bit as continuation. Only a trait that already has a rank row can be edited
// without growing the record, which is the same limit DwSav shows as "Not mapped in save".

const TRAIT_PREFIX_BYTES = 17;
const MAX_TRAIT_RANK = 32;
const MAX_DICTIONARY_ROWS = 4096;
const MAX_ABILITY_GROUPS = 256;

export type SaveTrait = Readonly<{
  /** Internal skill id, e.g. "VoraciousBite"; the game's Skill_ID. */
  id: string;
  /** Current rank, 0 when the save lists the trait only in the access dictionary. */
  rank: number;
  /** Highest rank the save has ever recorded for it. */
  highestRank: number;
  /** Book/access limit stored in the save; the rank cannot go above it. */
  accessLimit: number;
  /** True when a rank row exists, so the rank can be rewritten in place. */
  storedRank: boolean;
  /** True when the trait name is in the progression list (acquired perk). */
  acquired: boolean;
}>;

export type TraitRankLocation = Readonly<{ id: string; rankOffset: number; highestOffset?: number; highestRank: number; accessLimit: number; rank: number }>;

export type SaveTraitDocument = Readonly<{
  traits: readonly SaveTrait[];
  locations: ReadonlyMap<string, TraitRankLocation>;
}>;

class RecordCursor {
  position: number;
  constructor(private readonly bytes: Buffer, start: number, private readonly end: number, private readonly record: string) {
    this.position = start;
  }
  get remaining(): number { return this.end - this.position; }
  private take(count: number): number {
    if (count > this.remaining) throw new Error(`${this.record}: record ends inside a field at 0x${this.position.toString(16)}.`);
    const at = this.position;
    this.position += count;
    return at;
  }
  u8(): number { return this.bytes[this.take(1)]; }
  u32(): number { return this.bytes.readUInt32LE(this.take(4)); }
  requireArray(count: number, stride: number): void {
    if (count > Math.floor(this.remaining / stride)) throw new Error(`${this.record}: count ${count} exceeds the remaining record at 0x${this.position.toString(16)}.`);
  }
  packed(): number {
    let value = 0;
    for (let index = 0; index < 5; index++) {
      const byte = this.u8();
      const bits = byte >>> 1;
      if (index === 4 && bits > 15) throw new Error(`${this.record}: packed u32 overflow.`);
      value |= bits << (7 * index);
      if ((byte & 1) === 0) return value >>> 0;
    }
    throw new Error(`${this.record}: overlong packed u32.`);
  }
}

function developmentPrefix(document: DsavDocument): { start: number; end: number } | undefined {
  const index = document.nodes.findIndex(node => node.name === "CharacterDevelopmentSubsystem");
  if (index < 0) return undefined;
  const node = document.nodes[index];
  const prefixEnd = node.childIndex !== 65535 ? document.nodes[node.childIndex].offset : node.offset + node.size;
  return { start: node.offset + 4, end: prefixEnd };
}

function readName(cursor: RecordCursor, document: DsavDocument, firstIndexOf: ReadonlyMap<string, number>): string {
  const reference = cursor.packed();
  if (reference === 0 || reference > document.names.length) throw new Error("Character traits: invalid name reference.");
  const name = document.names[reference - 1];
  if (!name || name.includes("\0") || firstIndexOf.get(name) !== reference) throw new Error("Character traits: name reference is ambiguous for rewriting.");
  return name;
}

function readCount(cursor: RecordCursor, limit: number, stride: number): number {
  const count = cursor.u32();
  if (count > limit) throw new Error("Character traits: unexpected section count.");
  cursor.requireArray(count, stride);
  return count;
}

function readNames(cursor: RecordCursor, document: DsavDocument, firstIndexOf: ReadonlyMap<string, number>): string[] {
  const count = readCount(cursor, MAX_DICTIONARY_ROWS, 1);
  const names: string[] = [];
  for (let index = 0; index < count; index++) names.push(readName(cursor, document, firstIndexOf));
  return names;
}

/** Reads the trait dictionaries; undefined when the save has no development record. */
export function readSaveTraits(document: DsavDocument): SaveTraitDocument | undefined {
  const span = developmentPrefix(document);
  if (!span) return undefined;
  const cursor = new RecordCursor(document.payload, span.start, span.end, "Character traits");
  if (cursor.remaining < TRAIT_PREFIX_BYTES) return undefined;
  cursor.position += TRAIT_PREFIX_BYTES;
  const firstIndexOf = new Map<string, number>();
  document.names.forEach((name, index) => { if (!firstIndexOf.has(name)) firstIndexOf.set(name, index + 1); });

  type Row = { value: number; offset: number };
  const dictionaries: Map<string, Row>[] = [];
  let progressionNames: string[] = [];
  for (let section = 0; section < 6; section++) {
    if (section === 2) { progressionNames = readNames(cursor, document, firstIndexOf); continue; }
    const count = readCount(cursor, MAX_DICTIONARY_ROWS, 5);
    const rows = new Map<string, Row>();
    for (let index = 0; index < count; index++) {
      const name = readName(cursor, document, firstIndexOf);
      const offset = cursor.position;
      const value = cursor.u32();
      if (value > MAX_TRAIT_RANK || rows.has(name)) throw new Error("Character traits: unsupported trait dictionary.");
      rows.set(name, { value, offset });
    }
    dictionaries.push(rows);
  }
  readNames(cursor, document, firstIndexOf); // ability names
  const groupCount = readCount(cursor, MAX_ABILITY_GROUPS, 5);
  const groupKeys = new Set<number>();
  for (let index = 0; index < groupCount; index++) {
    const key = cursor.u8();
    if (groupKeys.has(key)) throw new Error("Character traits: duplicate ability-group key.");
    groupKeys.add(key);
    readNames(cursor, document, firstIndexOf);
  }
  if (cursor.u32() > 1) throw new Error("Character traits: invalid trailing flag.");
  cursor.u8();
  if (cursor.remaining !== 0) throw new Error("Character traits: unexpected trailing bytes.");

  const [ranks, highest, access] = dictionaries;
  const acquired = new Set(progressionNames);
  const ids = [...new Set([...ranks.keys(), ...access.keys()])].sort((a, b) => a.localeCompare(b));
  const locations = new Map<string, TraitRankLocation>();
  const traits = ids.map((id): SaveTrait => {
    const rankRow = ranks.get(id);
    const highestRow = highest.get(id);
    const accessRow = access.get(id);
    const rank = rankRow?.value ?? 0;
    const highestRank = highestRow?.value ?? 0;
    const accessLimit = Math.max(rank, accessRow?.value ?? 0);
    if (rankRow) locations.set(id, { id, rankOffset: rankRow.offset, highestOffset: highestRow?.offset, highestRank, accessLimit, rank });
    return { id, rank, highestRank, accessLimit, storedRank: Boolean(rankRow), acquired: acquired.has(id) };
  });
  return { traits, locations };
}
