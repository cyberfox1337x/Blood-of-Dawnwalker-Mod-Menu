import type { DsavDocument } from "./dsavContainer.js";
import { describeItem } from "./itemCatalog.js";
import { readSaveTraits, type SaveTrait, type TraitRankLocation } from "./saveTraits.js";
import { firstNameIndexes, readNameReference, RecordCursor } from "./recordCursor.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_fields");

// Layouts below mirror the reference editor's proven dwsave.py parser
// (recovered from its bytecode and confirmed against real saves):
// - TimeSystemImpl: cumulative clock u32 at record offset 4 (min size 8).
// - AttributeSaveSystem: u16 id count at 12, u32 ids at 14, u16 float count
//   after the ids, then parallel floats; ids[i] <-> floats[i] positionally.
// - CharacterDevelopmentSubsystem: a 16-byte u32 ledger after the 4-byte record
//   prefix: level at +4, experience (progress) at +8, unspent skill points at
//   +12 and spent skill points at +16 (the owner's DwSav editor, DsavFields.cs,
//   reads the same four slots as Development(name, 0 / 4 / 8 / 12)).
// - InventorySubsystem: definition count u32 at 8, then one packed name
//   reference per definition (the game's own encoding, so names appended by a
//   structural edit resolve too); owners are 7-byte headers (u32 tag, u8 flags,
//   u16 item count) and the player owner (tag 1) ends the walk.

// Attribute ids observed in the reference editor and confirmed on real saves.
export const ATTR_HEALTH = 1;
export const ATTR_BLOOD = 2;
export const ATTR_BLOOD_RESTORATION = 4;
export const ATTR_CORRUPTION_CHARGE = 7;
export const ATTR_MUTATION_LEVEL = 8;

export const ATTRIBUTE_NAMES: Readonly<Record<number, string>> = Object.freeze({
  [ATTR_HEALTH]: "Health",
  [ATTR_BLOOD]: "Blood",
  3: "Saved attribute 3",
  [ATTR_BLOOD_RESTORATION]: "Blood→Health restoration",
  5: "Saved attribute 5",
  [ATTR_CORRUPTION_CHARGE]: "Corruption charge",
  [ATTR_MUTATION_LEVEL]: "Vampire mutation level",
});

export type SaveFields = Readonly<{
  clockMs: number;
  clockDisplay: string;
  attributes: readonly { id: number; name: string; value: number }[];
  health?: number;
  blood?: number;
  mutationLevel?: number;
  level?: number;
  progressPoints?: number;
  skillPoints?: number;
  spentSkillPoints?: number;
  bloodRestoration?: number;
  corruptionCharge?: number;
  coin?: number;
  stacks: readonly InventoryStack[];
  /** Perk ranks stored in the save; empty when the development record has none. */
  traits: readonly SaveTrait[];
  /** Why the perk list is empty when the record could not be walked; absent when it was. */
  traitsUnavailable?: string;
  itemCatalog?: readonly ItemCatalogEntry[];
  freeItemSlots?: readonly number[];
  position?: PlayerPosition;
}>;

// Player transform read from the 110-byte WorldInfo record: three f64
// coordinates (UE centimetres) at +54/+62/+70 and yaw in degrees at +86,
// exactly as the reference editor's get_player_pos reads it.
export type PlayerPosition = Readonly<{ x: number; y: number; z: number; yaw: number }>;

const TRANSFORM_OFFSET_X = 54;
const TRANSFORM_OFFSET_YAW = 86;
const TRANSFORM_MIN_SIZE = 94;

export function readPlayerTransform(document: DsavDocument): PlayerPosition {
  const nodeIndex = document.nodes.findIndex((node) => node.name === "WorldInfo");
  requireCondition(nodeIndex >= 0, "WorldInfo is missing from this save.");
  const node = document.nodes[nodeIndex];
  requireCondition(node.size >= TRANSFORM_MIN_SIZE, `WorldInfo record is ${node.size} bytes; the known transform layout needs at least ${TRANSFORM_MIN_SIZE}. Refusing to guess.`);
  const x = document.payload.readDoubleLE(node.offset + TRANSFORM_OFFSET_X);
  const y = document.payload.readDoubleLE(node.offset + TRANSFORM_OFFSET_X + 8);
  const z = document.payload.readDoubleLE(node.offset + TRANSFORM_OFFSET_X + 16);
  const yaw = document.payload.readDoubleLE(node.offset + TRANSFORM_OFFSET_YAW);
  requireCondition([x, y, z, yaw].every(Number.isFinite), "WorldInfo transform fields are not finite numbers; the record layout does not match.");
  return { x, y, z, yaw };
}

export type FieldLocation = Readonly<{ nodeIndex: number; offset: number }>;

function requireCondition(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

export function attributeSlots(document: DsavDocument): ReadonlyMap<number, { value: number; offset: number }> {
  const slots = new Map<number, { value: number; offset: number }>();
  const nodeIndex = document.nodes.findIndex((node) => node.name === "AttributeSaveSystem");
  if (nodeIndex < 0) return slots;
  const node = document.nodes[nodeIndex];
  const bytes = document.payload.subarray(node.offset, node.offset + node.size);
  requireCondition(node.size >= 16, "AttributeSaveSystem record is too small to parse.");
  const count = bytes.readUInt16LE(12);
  const idsEnd = 14 + count * 4;
  requireCondition(idsEnd + 2 <= node.size, `AttributeSaveSystem id count ${count} overruns its ${node.size}-byte record.`);
  const ids: number[] = [];
  for (let index = 0; index < count; index++) ids.push(bytes.readUInt32LE(14 + index * 4));
  requireCondition(new Set(ids).size === ids.length, "AttributeSaveSystem contains duplicate attribute ids; refusing an ambiguous edit.");
  const secondCount = bytes.readUInt16LE(idsEnd);
  requireCondition(secondCount === count, `AttributeSaveSystem counts disagree (${count} and ${secondCount}).`);
  const floatsAt = idsEnd + 2;
  requireCondition(floatsAt + count * 4 <= node.size, `AttributeSaveSystem layout not understood: count=${count} implies floats at ${floatsAt}..${floatsAt + count * 4} but the record is ${node.size} bytes. Refusing to guess.`);
  for (let index = 0; index < count; index++) {
    slots.set(ids[index], { value: bytes.readFloatLE(floatsAt + index * 4), offset: node.offset + floatsAt + index * 4 });
  }
  return slots;
}

export function readClockMs(document: DsavDocument): number {
  const nodeIndex = document.nodes.findIndex((node) => node.name === "TimeSystemImpl");
  requireCondition(nodeIndex >= 0, "TimeSystemImpl is missing from this save.");
  const node = document.nodes[nodeIndex];
  requireCondition(node.size >= 8, "TimeSystemImpl record is too small for a clock field.");
  return document.payload.readUInt32LE(node.offset + 4);
}

export function readCharacterLevel(document: DsavDocument): number | undefined {
  const nodeIndex = document.nodes.findIndex((node) => node.name === "CharacterDevelopmentSubsystem");
  if (nodeIndex < 0) return undefined;
  const node = document.nodes[nodeIndex];
  if (node.size < 8) return undefined;
  return document.payload.readUInt32LE(node.offset + 4);
}

export function readProgressPoints(document: DsavDocument): number | undefined {
  return readDevelopmentSlot(document, 8);
}

export function readSkillPoints(document: DsavDocument): number | undefined {
  return readDevelopmentSlot(document, 12);
}

export function readSpentSkillPoints(document: DsavDocument): number | undefined {
  return readDevelopmentSlot(document, 16);
}

// One u32 of the CharacterDevelopmentSubsystem ledger; undefined when the record is
// too short to hold it (older saves), never a guess.
function readDevelopmentSlot(document: DsavDocument, relativeOffset: number): number | undefined {
  const nodeIndex = document.nodes.findIndex((node) => node.name === "CharacterDevelopmentSubsystem");
  if (nodeIndex < 0) return undefined;
  const node = document.nodes[nodeIndex];
  if (node.size < relativeOffset + 4) return undefined;
  return document.payload.readUInt32LE(node.offset + relativeOffset);
}

// `name` is the game's internal item id (the save stores nothing else); `displayName`
// and `category` come from the bundled item catalog so the editor can show items the
// way the game's inventory does.
export type InventoryStack = Readonly<{ itemIndex: number; name: string; displayName: string; category: string; value: number; offset: number; keyIndex: number; keySlotOffset: number }>;
export type ItemCatalogEntry = Readonly<{ definitionIndex: number; name: string; displayName: string; category: string; rarity?: string; sensitive: boolean; owned: boolean }>;
export type FreeItemSlot = Readonly<{ itemIndex: number; keySlotOffset: number; countOffset: number }>;
export type InventoryWalk = Readonly<{
  nodeIndex: number;
  definitionCount: number;
  stacks: readonly InventoryStack[];
  coin?: InventoryStack;
  keyEntries: readonly { keyIndex: number; definitionIndex: number; offset: number }[];
  freeSlots: readonly FreeItemSlot[];
  catalog: readonly ItemCatalogEntry[];
}>;

// Full player-owner inventory walk. Each stack's offset is absolute into document.payload.
export function walkInventory(document: DsavDocument): InventoryWalk {
  const inventoryIndex = document.nodes.findIndex((node) => node.name === "InventorySubsystem");
  requireCondition(inventoryIndex >= 0, "InventorySubsystem is missing from this save.");
  const node = document.nodes[inventoryIndex];
  const bytes = document.payload.subarray(node.offset, node.offset + node.size);
  const need = (offset: number, length: number, what: string): void => {
    requireCondition(offset + length <= bytes.length, `InventorySubsystem ${what} overruns its record.`);
  };
  need(8, 4, "item-definition count");
  const definitionCount = bytes.readUInt32LE(8);
  requireCondition(definitionCount <= 65536, "InventorySubsystem lists more item definitions than the game supports.");
  // Definition names are packed references into the save's name table.
  const nameCursor = new RecordCursor(bytes, 12, bytes.length, "InventorySubsystem definitions");
  const firstIndexOf = firstNameIndexes(document.names);
  const definitionNames: string[] = [];
  for (let index = 0; index < definitionCount; index++) definitionNames.push(readNameReference(nameCursor, document.names, firstIndexOf, "InventorySubsystem"));
  const keysOffset = nameCursor.position;
  need(keysOffset, 4, "item-key count");
  const keyCount = bytes.readUInt32LE(keysOffset);
  const keys: (readonly [number, number])[] = [];
  let cursor = keysOffset + 4;
  need(cursor, keyCount * 5, "item-key table");
  const keyEntries: { keyIndex: number; definitionIndex: number; offset: number }[] = [];
  for (let index = 0; index < keyCount; index++) {
    keyEntries.push({ keyIndex: index, definitionIndex: bytes.readUInt32LE(cursor), offset: node.offset + cursor });
    keys.push([bytes.readUInt32LE(cursor), bytes[cursor + 4]]);
    cursor += 5;
  }
  need(cursor, 4, "owner count");
  const ownerCount = bytes.readUInt32LE(cursor);
  cursor += 4;
  let coin: InventoryStack | undefined;
  const stacks: InventoryStack[] = [];
  const freeSlots: FreeItemSlot[] = [];
  for (let ownerIndex = 0; ownerIndex < ownerCount; ownerIndex++) {
    need(cursor, 7, "owner header");
    const ownerTag = bytes.readUInt32LE(cursor);
    const itemCount = bytes.readUInt16LE(cursor + 5);
    const keysAt = cursor + 7;
    need(keysAt, itemCount * 4, "owner item keys");
    const countsOffset = keysAt + itemCount * 4;
    need(countsOffset, 2, "owner stack count");
    const stackCount = bytes.readUInt16LE(countsOffset);
    const countsAt = countsOffset + 2;
    need(countsAt, stackCount * 4, "owner stack-count table");
    if (ownerTag === 1) {
      const ownedDefIndexes = new Set<number>();
      for (let itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        const keyIndex = bytes.readUInt32LE(keysAt + itemIndex * 4);
        if (keyIndex === 0xffffffff) {
          // An empty slot is only usable when its count cell exists and is zero.
          requireCondition(itemIndex < stackCount, `InventorySubsystem free slot ${itemIndex} has no count cell.`);
          freeSlots.push({ itemIndex, keySlotOffset: node.offset + keysAt + itemIndex * 4, countOffset: node.offset + countsAt + itemIndex * 4 });
          continue;
        }
        requireCondition(keyIndex < keys.length, `InventorySubsystem player item ${itemIndex} refers to a missing key.`);
        const definitionIndex = keys[keyIndex][0];
        requireCondition(definitionIndex < definitionCount, `InventorySubsystem key ${keyIndex} refers to a missing definition.`);
        const itemName = definitionNames[definitionIndex] ?? `definition ${definitionIndex}`;
        requireCondition(itemIndex < stackCount, `InventorySubsystem has no stack count for player item ${itemIndex} (${itemName}).`);
        const described = describeItem(itemName);
        const stack: InventoryStack = { itemIndex, name: itemName, displayName: described.name, category: described.category, value: bytes.readUInt32LE(countsAt + itemIndex * 4), offset: node.offset + countsAt + itemIndex * 4, keyIndex, keySlotOffset: node.offset + keysAt + itemIndex * 4 };
        stacks.push(stack);
        ownedDefIndexes.add(definitionIndex);
        if (itemName === "Coin") coin = stack;
      }
      const catalog: ItemCatalogEntry[] = [];
      for (let definitionIndex = 0; definitionIndex < definitionCount; definitionIndex++) {
        catalog.push(catalogEntry(definitionIndex, definitionNames[definitionIndex], ownedDefIndexes.has(definitionIndex)));
      }
      // The player owner block ends the walk (mirrors the reference): group
      // tables are parsed only for non-player owners. Returning here is what
      // keeps the walk honest on real saves.
      return { nodeIndex: inventoryIndex, definitionCount, stacks, coin, keyEntries, freeSlots, catalog };
    }
    cursor = countsAt + stackCount * 4 + 1;
    need(cursor, 4, "owner group count");
    const groupCount = bytes.readUInt32LE(cursor);
    cursor += 4;
    for (let groupIndex = 0; groupIndex < groupCount; groupIndex++) {
      need(cursor, 2, "group name size");
      const nameSize = bytes.readUInt16LE(cursor);
      cursor += 2 + nameSize;
      need(cursor, 2, "group entry count");
      const entryCount = bytes.readUInt16LE(cursor);
      cursor += 2;
      need(cursor, entryCount * 4, "group entry table");
      cursor += entryCount * 4;
    }
  }
  // Reaching this point means the save lists owners but none is the player.
  const catalog: ItemCatalogEntry[] = [];
  for (let definitionIndex = 0; definitionIndex < definitionCount; definitionIndex++) {
    catalog.push(catalogEntry(definitionIndex, definitionNames[definitionIndex], false));
  }
  return { nodeIndex: inventoryIndex, definitionCount, stacks, coin, keyEntries, freeSlots: [], catalog };
}

function catalogEntry(definitionIndex: number, itemId: string | undefined, owned: boolean): ItemCatalogEntry {
  const name = itemId ?? `definition ${definitionIndex}`;
  const described = describeItem(name);
  return { definitionIndex, name, displayName: described.name, category: described.category, rarity: described.rarity, sensitive: described.sensitive, owned };
}

export function readCoin(document: DsavDocument): number | undefined {
  try { return walkInventory(document).coin?.value; } catch { return undefined; }
}

// Read-only definition catalog with ownership flags, sorted by name for the
// searchable give-item list. Never throws: a save without a walkable inventory
// simply has no catalog.
export function itemCatalog(document: DsavDocument): readonly ItemCatalogEntry[] {
  try { return [...walkInventory(document).catalog].sort((a, b) => a.name.localeCompare(b.name)); } catch { return []; }
}

export function clockDisplay(clockMs: number): string {
  const day = Math.floor(clockMs / MS_PER_DAY);
  const inDay = clockMs % MS_PER_DAY;
  const hours = Math.floor(inDay / 3_600_000);
  const minutes = Math.floor((inDay % 3_600_000) / 60_000);
  return `Day ${day + 1}, ${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

const MS_PER_DAY = 86_400_000;

export function readSaveFields(document: DsavDocument): SaveFields {
  const clockMs = readClockMs(document);
  const slots = attributeSlots(document);
  const attributes = [...slots.entries()].sort(([a], [b]) => a - b).map(([id, slot]) => ({
    id,
    name: ATTRIBUTE_NAMES[id] ?? `Attribute ${id}`,
    value: slot.value,
  }));
  const level = readCharacterLevel(document);
  const progressPoints = readProgressPoints(document);
  const skillPoints = readSkillPoints(document);
  const spentSkillPoints = readSpentSkillPoints(document);
  const coin = readCoin(document);
  let stacks: readonly InventoryStack[] = [];
  let itemCatalog: readonly ItemCatalogEntry[] = [];
  let freeItemSlots: readonly number[] = [];
  try {
    const walk = walkInventory(document);
    stacks = walk.stacks;
    itemCatalog = walk.catalog;
    freeItemSlots = walk.freeSlots.map((slot) => slot.itemIndex);
  } catch { stacks = []; }
  let position: PlayerPosition | undefined;
  try { position = readPlayerTransform(document); } catch { position = undefined; }
  let traits: readonly SaveTrait[] = [];
  let traitsUnavailable: string | undefined;
  try { traits = readSaveTraits(document)?.traits ?? []; }
  catch (error) { traitsUnavailable = error instanceof Error ? error.message : String(error); }
  return {
    clockMs,
    clockDisplay: clockDisplay(clockMs),
    attributes,
    health: slots.get(ATTR_HEALTH)?.value,
    blood: slots.get(ATTR_BLOOD)?.value,
    mutationLevel: slots.get(ATTR_MUTATION_LEVEL)?.value,
    bloodRestoration: slots.get(ATTR_BLOOD_RESTORATION)?.value,
    corruptionCharge: slots.get(ATTR_CORRUPTION_CHARGE)?.value,
    level,
    progressPoints,
    skillPoints,
    spentSkillPoints,
    coin,
    stacks,
    traits,
    ...(traitsUnavailable ? { traitsUnavailable } : {}),
    itemCatalog,
    freeItemSlots,
    position,
  };
}

export type FieldLocations = Readonly<{
  clock: FieldLocation;
  attributes: Readonly<Record<number, FieldLocation>>;
  coin?: FieldLocation & { name: string };
  level?: FieldLocation;
  progressPoints?: FieldLocation;
  skillPoints?: FieldLocation;
  spentSkillPoints?: FieldLocation;
  stacks: readonly InventoryStack[];
  traitRanks: ReadonlyMap<string, TraitRankLocation>;
  position?: { nodeIndex: number; x: number; y: number; z: number; yaw: number };
}>;

// Every offset returned here is absolute into document.payload, matching what
// applyEdits writes.
export function fieldLocations(document: DsavDocument): FieldLocations {
  const attributeNode = nodeOffsetOf(document, "AttributeSaveSystem");
  const slots = attributeSlots(document);
  const attributes: Record<number, FieldLocation> = {};
  for (const [id, slot] of slots) attributes[id] = { nodeIndex: attributeNode.nodeIndex, offset: slot.offset };
  let coin: (FieldLocation & { name: string }) | undefined;
  let stacks: readonly InventoryStack[] = [];
  try {
    const walk = walkInventory(document);
    stacks = walk.stacks;
    if (walk.coin) coin = { nodeIndex: walk.nodeIndex, offset: walk.coin.offset, name: walk.coin.name };
  } catch {
    stacks = [];
  }
  const progressIndex = document.nodes.findIndex((node) => node.name === "CharacterDevelopmentSubsystem");
  const level = progressIndex >= 0 && document.nodes[progressIndex].size >= 8 ? { nodeIndex: progressIndex, offset: document.nodes[progressIndex].offset + 4 } : undefined;
  const progressPoints = progressIndex >= 0 && document.nodes[progressIndex].size >= 12 ? { nodeIndex: progressIndex, offset: document.nodes[progressIndex].offset + 8 } : undefined;
  const skillPoints = progressIndex >= 0 && document.nodes[progressIndex].size >= 16 ? { nodeIndex: progressIndex, offset: document.nodes[progressIndex].offset + 12 } : undefined;
  const spentSkillPoints = progressIndex >= 0 && document.nodes[progressIndex].size >= 20 ? { nodeIndex: progressIndex, offset: document.nodes[progressIndex].offset + 16 } : undefined;
  const clockNode = nodeOffsetOf(document, "TimeSystemImpl");
  let traitRanks: ReadonlyMap<string, TraitRankLocation> = new Map();
  try { traitRanks = readSaveTraits(document)?.locations ?? new Map(); } catch { traitRanks = new Map(); }
  let position: FieldLocations["position"];
  try {
    const worldNode = nodeOffsetOf(document, "WorldInfo");
    position = { nodeIndex: worldNode.nodeIndex, x: worldNode.offset + TRANSFORM_OFFSET_X, y: worldNode.offset + TRANSFORM_OFFSET_X + 8, z: worldNode.offset + TRANSFORM_OFFSET_X + 16, yaw: worldNode.offset + TRANSFORM_OFFSET_YAW };
  } catch { position = undefined; }
  return { clock: { nodeIndex: clockNode.nodeIndex, offset: clockNode.offset + 4 }, attributes, coin, level, progressPoints, skillPoints, spentSkillPoints, stacks, traitRanks, position };
}

function nodeOffsetOf(document: DsavDocument, name: string): { nodeIndex: number; offset: number } {
  const index = document.nodes.findIndex((node) => node.name === name);
  requireCondition(index >= 0, `${name} is missing from this save.`);
  return { nodeIndex: index, offset: document.nodes[index].offset };
}

export const SAVE_FIELD_NAMES = Object.freeze(["clockMs", "health", "blood", "mutationLevel", "bloodRestoration", "corruptionCharge", "level", "progressPoints", "skillPoints", "spentSkillPoints", "coin"] as const);
export type SaveFieldName = (typeof SAVE_FIELD_NAMES)[number];
