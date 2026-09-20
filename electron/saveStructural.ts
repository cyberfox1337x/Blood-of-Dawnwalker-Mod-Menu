import type { DsavDocument } from "./dsavContainer.js";
import { firstNameIndexes, readNameReference, RecordCursor, writePacked } from "./recordCursor.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_structural");

// Structural inventory edits: adding an item the save has never listed, or removing a
// stack outright, changes record lengths, so the InventorySubsystem record is parsed
// into a document, changed, serialised again and spliced back into the payload with
// every later record offset, the name table and the node directory rebuilt. The layout
// and every check mirror the owner's DwSav InventoryDocument / InventorySuffix /
// RecordRewriter; the record must parse to its exact end before anything is written.

const NULL_HANDLE = 0xffffffff;
const NPC_EQUIPMENT_SENTINEL = 0xfffffffe;
const MAX_TYPES = 65536;
const MAX_HANDLES = 131072;
const MAX_OWNERS = 131072;
const MAX_NAMES = 131072;
const MAX_LOGICAL_BYTES = 256 * 1024 * 1024;
const DATA_START = 36;

export type InventoryHandle = { type: number; variant: number };
export type InventoryStackRow = { handle: number; quantity: number };
export type EquipmentSlotRow = { key: number; handle: number };
export type InventoryOwnerRecord = { key: number; flag: number; activeSet: number; stacks: InventoryStackRow[]; equipment: EquipmentSlotRow[][]; references: number[] };
export type InventoryDocument = {
  prefixWord: number;
  types: string[];
  handles: InventoryHandle[];
  owners: InventoryOwnerRecord[];
  tail: Buffer;
};

function limit(value: number, maximum: number, what: string): void {
  if (value > maximum) throw new Error(`Inventory ${what} count ${value} exceeds the supported limit ${maximum}.`);
}

function prefixSpan(document: DsavDocument, name: string): { start: number; end: number } | undefined {
  const index = document.nodes.findIndex(node => node.name === name);
  if (index < 0) return undefined;
  const node = document.nodes[index];
  const prefixEnd = node.childIndex !== 65535 ? document.nodes[node.childIndex].offset : node.offset + node.size;
  return { start: node.offset + 4, end: prefixEnd };
}

/** Byte span of a named record's prefix (after its name word, before its children); undefined when absent. */
export function recordPrefixSpan(document: DsavDocument, name: string): { start: number; end: number } | undefined {
  return prefixSpan(document, name);
}

function readReference(cursor: RecordCursor, handleCount: number, unresolved: ReadonlySet<number>, flag: number, owner: number, section: string, index: number, options: { nullable?: boolean; npcEquipment?: boolean } = {}): number {
  const at = cursor.position;
  const value = cursor.u32();
  const outOfRange = value >= handleCount && !(options.nullable && value === NULL_HANDLE) && !(options.npcEquipment && value === NPC_EQUIPMENT_SENTINEL) && !(flag === 1 && (value | 0) < 0);
  if (outOfRange) throw new Error(`Inventory reference is outside the handle dictionary: owner=${owner}, section=${section}, index=${index}, offset=0x${at.toString(16)}, reference=${value}, handles=${handleCount}.`);
  if (unresolved.has(value)) throw new Error(`Inventory reference has no item type: owner=${owner}, section=${section}, index=${index}, handle=${value}.`);
  return value;
}

// The bytes after the owner table: two handle lists, merchant tables, three tracked
// lists, a keyed map and a 12-byte trailer. They are kept verbatim, but every handle
// and type reference inside them is checked against the dictionaries so a rebuilt
// record can never point at a handle that no longer exists.
function validateSuffix(tail: Buffer, handleCount: number, typeCount: number, unresolved: ReadonlySet<number>): void {
  const cursor = new RecordCursor(tail, 0, tail.length, "Inventory suffix");
  const references = (count: number, dictionaryCount: number, dictionary: string, section: string, checkUnresolved: boolean) => {
    cursor.requireArray(count, 4);
    for (let index = 0; index < count; index++) {
      const value = cursor.u32();
      if (value >= dictionaryCount) throw new Error(`Inventory suffix reference is outside the ${dictionary} dictionary: section=${section}, entry=${index}, reference=${value}.`);
      if (checkUnresolved && unresolved.has(value)) throw new Error(`Inventory suffix reference has no item type: section=${section}, entry=${index}, handle=${value}.`);
    }
  };
  for (let list = 0; list < 2; list++) references(cursor.u16(), handleCount, "handle", `initial list ${list}`, true);
  const merchants = cursor.u32();
  if (merchants > 65536) throw new Error("Inventory suffix merchant count exceeds the supported limit.");
  cursor.requireArray(merchants, 19);
  for (let merchant = 0; merchant < merchants; merchant++) {
    cursor.packed();
    cursor.take(10);
    for (let map = 0; map < 2; map++) {
      const count = cursor.u16();
      references(count, map === 0 ? handleCount : typeCount, map === 0 ? "handle" : "type", `merchant ${merchant} map ${map}`, map === 0);
      if (cursor.u16() !== count) throw new Error(`Inventory suffix merchant ${merchant} stack counts differ.`);
      cursor.requireArray(count, 4);
      cursor.take(count * 4);
    }
  }
  for (let list = 0; list < 3; list++) {
    const count = cursor.u16();
    cursor.requireArray(count, 4);
    cursor.take(count * 4);
  }
  const mapCount = cursor.u16();
  if (mapCount > 256) throw new Error("Invalid inventory suffix map count.");
  cursor.requireArray(mapCount, 1);
  const keys = new Set<number>();
  for (let index = 0; index < mapCount; index++) {
    const key = cursor.u8();
    if (keys.has(key)) throw new Error("Duplicate inventory suffix map key.");
    keys.add(key);
  }
  if (cursor.u16() !== mapCount) throw new Error("Inventory suffix map counts differ.");
  cursor.requireArray(mapCount, 4);
  cursor.take(mapCount * 4);
  cursor.take(12);
  if (cursor.remaining !== 0) throw new Error("Unexpected inventory suffix bytes; ambiguous record boundary.");
}

/** Parses the InventorySubsystem record; undefined when the save has none. */
export function readInventoryDocument(document: DsavDocument): InventoryDocument | undefined {
  const span = prefixSpan(document, "InventorySubsystem");
  if (!span) return undefined;
  const cursor = new RecordCursor(document.payload, span.start, span.end, "Inventory");
  const firstIndexOf = firstNameIndexes(document.names);
  const prefixWord = cursor.u32();
  const typeCount = cursor.u32();
  limit(typeCount, MAX_TYPES, "type");
  cursor.requireArray(typeCount, 1);
  const types: string[] = [];
  for (let index = 0; index < typeCount; index++) types.push(readNameReference(cursor, document.names, firstIndexOf, "Inventory"));
  const handleCount = cursor.u32();
  limit(handleCount, MAX_HANDLES, "handle");
  cursor.requireArray(handleCount, 5);
  const handles: InventoryHandle[] = [];
  const unresolved = new Set<number>();
  for (let index = 0; index < handleCount; index++) {
    const type = cursor.u32();
    const variant = cursor.u8();
    if (type === NULL_HANDLE) unresolved.add(index);
    else if (type >= typeCount) throw new Error(`Invalid inventory handle type: handle ${index} refers to type ${type} of ${typeCount}.`);
    handles.push({ type, variant });
  }
  const ownerCount = cursor.u32();
  limit(ownerCount, MAX_OWNERS, "owner");
  cursor.requireArray(ownerCount, 16);
  const owners: InventoryOwnerRecord[] = [];
  const ownerKeys = new Set<number>();
  for (let ownerIndex = 0; ownerIndex < ownerCount; ownerIndex++) {
    const key = cursor.u32();
    const flag = cursor.u8();
    if (ownerKeys.has(key) || flag > 1) throw new Error("Unsupported inventory owner identity.");
    ownerKeys.add(key);
    const stackCount = cursor.u16();
    cursor.requireArray(stackCount, 4);
    const stackHandles: number[] = [];
    for (let index = 0; index < stackCount; index++) stackHandles.push(readReference(cursor, handleCount, unresolved, flag, key, "stacks", index, { nullable: true }));
    if (cursor.u16() !== stackCount) throw new Error("Inventory stack counts differ.");
    cursor.requireArray(stackCount, 4);
    const stacks: InventoryStackRow[] = [];
    for (let index = 0; index < stackCount; index++) {
      const quantity = cursor.u32();
      if (flag === 0 && stackHandles[index] === NULL_HANDLE && quantity !== 0) throw new Error(`Owner ${key}: empty inventory reference has a nonzero quantity.`);
      stacks.push({ handle: stackHandles[index], quantity });
    }
    const activeSet = cursor.u8();
    const setCount = cursor.u32();
    limit(setCount, 64, "equipment set");
    if (setCount === 0 ? activeSet !== 0 : activeSet >= setCount) throw new Error("Invalid active inventory equipment set.");
    cursor.requireArray(setCount, 4);
    const equipment: EquipmentSlotRow[][] = [];
    for (let set = 0; set < setCount; set++) {
      const slotCount = cursor.u16();
      cursor.requireArray(slotCount, 1);
      const keys: number[] = [];
      for (let index = 0; index < slotCount; index++) keys.push(cursor.u8());
      if (new Set(keys).size !== slotCount || cursor.u16() !== slotCount) throw new Error("Invalid equipment map.");
      cursor.requireArray(slotCount, 4);
      const slots: EquipmentSlotRow[] = [];
      for (let index = 0; index < slotCount; index++) slots.push({ key: keys[index], handle: readReference(cursor, handleCount, unresolved, flag, key, "equipment", index, { nullable: true, npcEquipment: key !== 1 }) });
      equipment.push(slots);
    }
    const referenceCount = cursor.u16();
    cursor.requireArray(referenceCount, 4);
    const references: number[] = [];
    for (let index = 0; index < referenceCount; index++) references.push(readReference(cursor, handleCount, unresolved, flag, key, "references", index));
    owners.push({ key, flag, activeSet, stacks, equipment, references });
  }
  const tail = cursor.slice(cursor.remaining);
  validateSuffix(tail, handleCount, typeCount, unresolved);
  return { prefixWord, types, handles, owners, tail };
}

function playerOf(document: InventoryDocument): InventoryOwnerRecord {
  const players = document.owners.filter(owner => owner.key === 1 && owner.flag === 0);
  if (players.length !== 1) throw new Error("Missing or ambiguous player inventory.");
  return players[0];
}

export function handleName(document: InventoryDocument, handle: number): string {
  const entry = document.handles[handle];
  if (!entry || entry.type >= document.types.length) throw new Error(`Inventory handle ${handle} has no item type.`);
  return document.types[entry.type];
}

function ensureStackHandle(document: InventoryDocument, itemId: string): number {
  let type = document.types.indexOf(itemId);
  const existing = type < 0 ? -1 : document.handles.findIndex(handle => handle.type === type && handle.variant === 0);
  if (existing >= 0) return existing;
  if (/^\s*["']?\/Game\//i.test(itemId) || /'\/Game\//i.test(itemId)) throw new Error("Use the item's ItemId, not its /Game/ asset path.");
  if (type < 0) {
    limit(document.types.length + 1, MAX_TYPES, "type");
    document.types.push(itemId);
    type = document.types.length - 1;
  }
  limit(document.handles.length + 1, MAX_HANDLES, "handle");
  document.handles.push({ type, variant: 0 });
  return document.handles.length - 1;
}

/** Sets the player's stack of `itemId` to `quantity`, creating the type/handle/stack rows when absent; 0 removes it. */
export function setPlayerStack(document: InventoryDocument, itemId: string, quantity: number): void {
  const player = playerOf(document);
  const matches = player.stacks.filter(stack => stack.handle < document.handles.length && document.handles[stack.handle].type < document.types.length
    && handleName(document, stack.handle) === itemId && document.handles[stack.handle].variant === 0);
  if (matches.length > 1) throw new Error(`Multiple stacks of ${itemId}; remove a specific row instead.`);
  if (matches.length === 1) {
    if (quantity === 0) { removePlayerStack(document, matches[0].handle); return; }
    matches[0].quantity = quantity;
    return;
  }
  if (quantity === 0) return;
  limit(player.stacks.length + 1, 65535, "player stack");
  player.stacks.push({ handle: ensureStackHandle(document, itemId), quantity });
}

/** Drops every player stack, equipment slot and reference that points at `handle`. */
export function removePlayerStack(document: InventoryDocument, handle: number): void {
  const player = playerOf(document);
  player.stacks = player.stacks.filter(stack => stack.handle !== handle);
  for (const set of player.equipment) for (const slot of set) if (slot.handle === handle) slot.handle = NULL_HANDLE;
  player.references = player.references.filter(reference => reference !== handle);
}

export function serializeInventoryDocument(document: InventoryDocument, nameIndex: (name: string) => number): Buffer {
  limit(document.types.length, MAX_TYPES, "type");
  limit(document.handles.length, MAX_HANDLES, "handle");
  limit(document.owners.length, MAX_OWNERS, "owner");
  const unresolved = new Set(document.handles.map((handle, index) => handle.type === NULL_HANDLE ? index : -1).filter(index => index >= 0));
  validateSuffix(document.tail, document.handles.length, document.types.length, unresolved);
  const parts: Buffer[] = [];
  const u8 = (value: number) => { const b = Buffer.alloc(1); b.writeUInt8(value); parts.push(b); };
  const u16 = (value: number) => { if (value > 65535) throw new Error("Inventory count exceeds a 16-bit field."); const b = Buffer.alloc(2); b.writeUInt16LE(value); parts.push(b); };
  const u32 = (value: number) => { const b = Buffer.alloc(4); b.writeUInt32LE(value >>> 0); parts.push(b); };
  u32(document.prefixWord);
  u32(document.types.length);
  for (const type of document.types) parts.push(writePacked(nameIndex(type)));
  u32(document.handles.length);
  for (const handle of document.handles) { u32(handle.type); u8(handle.variant); }
  u32(document.owners.length);
  for (const owner of document.owners) {
    u32(owner.key); u8(owner.flag);
    u16(owner.stacks.length); for (const stack of owner.stacks) u32(stack.handle);
    u16(owner.stacks.length); for (const stack of owner.stacks) u32(stack.quantity);
    u8(owner.activeSet);
    u32(owner.equipment.length);
    for (const set of owner.equipment) {
      u16(set.length); for (const slot of set) u8(slot.key);
      u16(set.length); for (const slot of set) u32(slot.handle);
    }
    u16(owner.references.length); for (const reference of owner.references) u32(reference);
  }
  parts.push(document.tail);
  return Buffer.concat(parts);
}

export type RebuiltPayload = Readonly<{ payload: Buffer; namesOffset: number; nodesOffset: number }>;

// Splices new prefix bytes into named records, appends any new names, and rewrites
// the node directory so every later offset and size follows the shift. Offsets in the
// directory are absolute file positions (payload position + 36), as the game writes them.
export function rebuildPayload(document: DsavDocument, replacements: ReadonlyMap<string, Buffer>, names: readonly string[]): RebuiltPayload {
  if (names.length > MAX_NAMES) throw new Error("NAME count exceeds the supported limit.");
  const spans = [...replacements].map(([name, bytes]) => {
    const span = prefixSpan(document, name);
    if (!span) throw new Error(`Missing record: ${name}.`);
    return { ...span, bytes };
  }).sort((a, b) => a.start - b.start);
  const recordsEnd = document.container.namesOffset - DATA_START;
  const shiftAt = (position: number) => spans.filter(span => span.end <= position).reduce((total, span) => total + span.bytes.length - (span.end - span.start), 0);
  const parts: Buffer[] = [];
  let cursor = 0;
  for (const span of spans) {
    if (span.start < cursor) throw new Error("Overlapping record replacements.");
    parts.push(document.payload.subarray(cursor, span.start), span.bytes);
    cursor = span.end;
  }
  parts.push(document.payload.subarray(cursor, recordsEnd));
  const records = Buffer.concat(parts);
  const encoder = new TextEncoder();
  const nameBodies = names.map(name => {
    const bytes = encoder.encode(name);
    if (bytes.length === 0 || bytes.length >= 255 || name.includes("\0")) throw new Error(`Invalid name for the save's name table: ${JSON.stringify(name)}.`);
    return Buffer.concat([Buffer.from([bytes.length]), Buffer.from(bytes)]);
  });
  const nameBody = Buffer.concat(nameBodies);
  const nameHeader = Buffer.alloc(8); nameHeader.write("NAME"); nameHeader.writeUInt32LE(nameBody.length, 4);
  const nameTable = Buffer.concat([nameHeader, nameBody, Buffer.from("NAME")]);
  const directory = Buffer.alloc(6 + document.nodes.length * 16 + 4);
  directory.write("DWNT");
  directory.writeUInt16LE(document.nodes.length, 4);
  document.nodes.forEach((node, index) => {
    const at = 6 + index * 16;
    const start = node.offset + shiftAt(node.offset);
    const end = node.offset + node.size + shiftAt(node.offset + node.size);
    directory.writeUInt32LE(nameIndexOfNode(document, node.index), at);
    directory.writeUInt16LE(node.nextIndex, at + 4);
    directory.writeUInt16LE(node.childIndex, at + 6);
    directory.writeUInt32LE(start + DATA_START, at + 8);
    directory.writeUInt32LE(end - start, at + 12);
  });
  directory.write("DWNT", directory.length - 4);
  const payload = Buffer.concat([records, nameTable, directory]);
  if (payload.length > MAX_LOGICAL_BYTES) throw new Error("Edited save exceeds the size limit.");
  return { payload, namesOffset: records.length + DATA_START, nodesOffset: records.length + nameTable.length + DATA_START };
}

// The directory stores each node's name as a 1-based name-table index; read it back
// from the original directory so a duplicated name keeps the same reference.
function nameIndexOfNode(document: DsavDocument, nodeIndex: number): number {
  const start = document.container.nodesOffset - DATA_START;
  return document.payload.readUInt32LE(start + 6 + nodeIndex * 16);
}
