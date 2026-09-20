import type { InventoryDocument } from "./saveStructural.js";
import { RecordCursor } from "./recordCursor.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_item_upgrade");

// Port of the owner's DwSav InventorySuffix / ExperimentalItemUpgrade byte rules for
// this repo's InventoryDocument model. Upgrading an item means: find or create a handle
// with the same type and the target variant (level), move exactly one unit of the source
// stack onto the upgraded stack (reusing an empty slot when the source had more than
// one), repoint player equipment that referenced the old handle, and append/refresh the
// old→new handle in the suffix's tracked-handle list. The suffix layout, the tracked
// region rules and every guard mirror InventorySuffix.UpgradeTrackedHandles; the rebuilt
// record is fully revalidated when it is serialised.

const NULL_HANDLE = 0xffffffff;
const MAX_HANDLES = 131072;
const TRACKED_LIST_LIMIT = 65535;
const MAX_SIGNED_QUANTITY = 0x7fffffff;

export type ItemLevelDefinition = Readonly<{ hasItemLevel: boolean; upgradeSpread: number }>;

/** One weapon/clothing row from the asset export's items.json, reduced to upgrade facts. */
export function itemLevelDefinition(row: Readonly<{ Type?: unknown; Class?: unknown; Properties?: unknown }>): ItemLevelDefinition | undefined {
  if (typeof row !== "object" || row === null) return undefined;
  const type = row.Type;
  const properties = row.Properties;
  if ((type !== "ItemWeaponDataAsset" && type !== "ItemClothingDataAsset") || typeof properties !== "object" || properties === null) return undefined;
  const id = (properties as { ItemId?: unknown }).ItemId;
  if (typeof id !== "string" || id.length === 0 || id.length > 200) return undefined;
  if (row.Class !== `UScriptClass'${type}'`) throw new Error("Item-level metadata does not name the verified native asset class.");
  let spread = 1;
  const override = (properties as { bOverrideUpgradeLevelSpread?: unknown }).bOverrideUpgradeLevelSpread;
  if (override !== undefined && typeof override !== "boolean") throw new Error("Malformed item upgrade spread override.");
  if (typeof override === "boolean" && override) {
    const spreadValue = (properties as { UpgradeLevelSpread?: unknown }).UpgradeLevelSpread;
    if (typeof spreadValue !== "number" || !Number.isInteger(spreadValue)) throw new Error("Missing or invalid item upgrade spread.");
    spread = spreadValue;
  }
  return { hasItemLevel: true, upgradeSpread: spread };
}

/** Indexes the asset export's items.json into ItemId → upgrade facts (only weapons and clothing carry levels). */
export function readItemLevelCatalog(rows: readonly unknown[]): ReadonlyMap<string, ItemLevelDefinition> {
  if (!Array.isArray(rows) || rows.length === 0 || rows.length > 4096) throw new Error("Expected a bounded local item asset export.");
  const catalog = new Map<string, ItemLevelDefinition>();
  for (const row of rows) {
    const definition = itemLevelDefinition(row as Readonly<{ Type?: unknown; Class?: unknown; Properties?: unknown }>);
    if (!definition) continue;
    const id = (row as { Properties?: { ItemId?: unknown } }).Properties?.ItemId;
    if (typeof id !== "string") continue;
    if (catalog.has(id)) throw new Error("Invalid, duplicate or ambiguous item identifier.");
    catalog.set(id, definition);
  }
  return catalog;
}

export type UpgradeOption = Readonly<{ itemId: string; handle: number; currentLevel: number; maximumLevel: number; quantity: number }>;

/** The player's upgradeable stacks, preserving the handle identity for repeated item types. */
export function previewItemUpgrades(document: InventoryDocument, catalog: ReadonlyMap<string, ItemLevelDefinition>, playerLevel: number): readonly UpgradeOption[] {
  requireProfile(playerLevel);
  const player = playerOwner(document);
  const options = new Map<number, UpgradeOption>();
  for (const stack of player.stacks) {
    if (stack.handle >= document.handles.length || stack.quantity === 0) continue;
    const handle = document.handles[stack.handle];
    if (handle.type >= document.types.length) continue;
    const itemId = document.types[handle.type];
    const definition = catalog.get(itemId);
    if (!definition || !definition.hasItemLevel) continue;
    requireCondition(document.types.filter(type => type.toLowerCase() === itemId.toLowerCase()).length === 1, "The selected item has an ambiguous inventory type identity.");
    if (options.has(stack.handle)) throw new Error(`An upgradeable item has duplicate player stacks: ${itemId}.`);
    const maximum = maximumLevel(playerLevel, definition.upgradeSpread);
    if (maximum > handle.variant) options.set(stack.handle, { itemId, handle: stack.handle, currentLevel: handle.variant, maximumLevel: maximum, quantity: stack.quantity });
  }
  return [...options.values()].sort((a, b) => a.itemId.localeCompare(b.itemId) || a.handle - b.handle);
}

export type ItemUpgradeRequest = Readonly<{ itemId: string; targetLevel: number; playerLevel: number; handle?: number }>;

/**
 * Applies one unit upgrade of `itemId` to `targetLevel` on the parsed document.
 * Throws with the DwSav wording whenever the mapped rules refuse the change; the
 * document is only mutated after every check has passed.
 */
export function upgradeOnePlayerItem(document: InventoryDocument, request: ItemUpgradeRequest, catalog: ReadonlyMap<string, ItemLevelDefinition>): number {
  requireProfile(request.playerLevel);
  requireCondition(Number.isInteger(request.targetLevel) && request.targetLevel >= 1 && request.targetLevel <= 50, "Upgrade level must be a whole number within the mapped owner limit (1 to 50).");
  const definition = catalog.get(request.itemId);
  requireCondition(definition !== undefined && definition.hasItemLevel, "The selected item does not have verified native item-level support.");
  requireCondition(document.types.filter(type => type.toLowerCase() === request.itemId.toLowerCase()).length === 1, "The selected item has an ambiguous inventory type identity.");
  const limit = maximumLevel(request.playerLevel, definition!.upgradeSpread);
  const player = playerOwner(document);
  requireCondition(player.stacks.length <= 65535 && player.equipment.length <= 64 && player.references.length <= 65535, "Player inventory exceeds the supported layout limits.");
  const sourceStacks = player.stacks
    .map((stack, index) => ({ stack, index }))
    .filter(({ stack }) => (request.handle === undefined || stack.handle === request.handle) && stack.quantity > 0 && stack.handle < document.handles.length && document.handles[stack.handle].type < document.types.length && document.types[document.handles[stack.handle].type] === request.itemId);
  requireCondition(sourceStacks.length === 1, "Upgrading requires one unambiguous positive source stack within the native quantity limit.");
  const { stack: source, index: sourceIndex } = sourceStacks[0];
  const sourceHandle = document.handles[source.handle];
  requireCondition(source.quantity > 0 && source.quantity <= MAX_SIGNED_QUANTITY, "Upgrading requires one unambiguous positive source stack within the native quantity limit.");
  requireCondition(request.targetLevel > sourceHandle.variant, `Upgrade level must be above ${sourceHandle.variant} and no higher than the mapped owner limit ${limit}.`);
  requireCondition(request.targetLevel <= limit, `Upgrade level must be above ${sourceHandle.variant} and no higher than the mapped owner limit ${limit}.`);

  let newHandle = document.handles.findIndex(handle => handle.type === sourceHandle.type && handle.variant === request.targetLevel);
  const appended = newHandle < 0;
  if (appended) {
    requireCondition(document.handles.length < MAX_HANDLES, "The inventory handle dictionary has no capacity for this upgrade.");
    newHandle = document.handles.length;
  }
  const destinations = player.stacks
    .map((stack, index) => ({ stack, index }))
    .filter(({ stack }) => stack.handle === newHandle);
  requireCondition(destinations.length <= 1 && (destinations.length === 0 || destinations[0].stack.quantity < MAX_SIGNED_QUANTITY), "The upgraded item has an ambiguous or full destination stack.");
  let destinationIndex = destinations.length === 1 ? destinations[0].index : -1;
  if (destinationIndex < 0 && destinations.length === 0) {
    for (let index = player.stacks.length - 1; index >= 0; index -= 1) {
      if (player.stacks[index].quantity === 0) { destinationIndex = index; break; }
    }
  }
  if (destinations.length === 0 && source.quantity === 1) destinationIndex = sourceIndex;
  if (destinationIndex < 0) requireCondition(player.stacks.length < 65535, "The player inventory has no stack capacity for this upgrade.");

  // Compute the new suffix first (it validates the tracked-list capacity), then mutate.
  const tail = upgradeTrackedHandles(document.tail, source.handle, newHandle, source.quantity === 1, document.handles.length, document.types.length);
  if (appended) document.handles.push({ type: sourceHandle.type, variant: request.targetLevel });
  player.stacks[sourceIndex] = { handle: source.quantity === 1 ? NULL_HANDLE : source.handle, quantity: source.quantity === 1 ? 0 : source.quantity - 1 };
  const upgraded = { handle: newHandle, quantity: (destinations.length === 1 ? destinations[0].stack.quantity : 0) + 1 };
  if (destinationIndex < 0) player.stacks.push(upgraded);
  else player.stacks[destinationIndex] = upgraded;
  for (const set of player.equipment) for (let slot = 0; slot < set.length; slot += 1) if (set[slot].handle === source.handle) set[slot] = { ...set[slot], handle: newHandle };
  document.tail = tail;
  return newHandle;
}

function playerOwner(document: InventoryDocument) {
  const players = document.owners.filter(owner => owner.key === 1 && owner.flag === 0);
  if (players.length !== 1) throw new Error("Missing or ambiguous player inventory.");
  return players[0];
}

function requireProfile(playerLevel: number): void {
  if (!Number.isInteger(playerLevel) || playerLevel < 1 || playerLevel > 50) throw new Error("Character level is outside the mapped 1-50 profile.");
}

function maximumLevel(playerLevel: number, spread: number): number {
  const level = playerLevel + spread;
  if (!Number.isSafeInteger(level)) throw new Error("Item upgrade spread overflows the native level calculation.");
  return Math.min(50, level);
}

// --- Suffix tracked-handle region -------------------------------------------------

type TrackedRegion = Readonly<{ countOffset: number; count: number; end: number }>;

/** Walks the suffix layout to the first of its three u32-lists (the tracked handles), bounds only.
 *  The walk must stay identical to saveStructural's validateSuffix: it is the proven layout,
 *  and serializeInventoryDocument re-runs the full reference validation afterwards. */
export function trackedHandleRegion(tail: Buffer, handleCount: number, typeCount: number): TrackedRegion {
  const cursor = new RecordCursor(tail, 0, tail.length, "Inventory suffix");
  for (let list = 0; list < 2; list += 1) {
    const count = cursor.u16();
    cursor.requireArray(count, 4);
    cursor.take(count * 4);
  }
  const merchants = cursor.u32();
  if (merchants > 65536) throw new Error("Inventory suffix merchant count exceeds the supported limit.");
  cursor.requireArray(merchants, 19);
  for (let merchant = 0; merchant < merchants; merchant += 1) {
    cursor.packed(); // packed name reference; validated against the name table on serialise
    cursor.take(10);
    for (let map = 0; map < 2; map += 1) {
      const count = cursor.u16();
      cursor.requireArray(count, 4);
      cursor.take(count * 4);
      if (cursor.u16() !== count) throw new Error(`Inventory suffix merchant ${merchant} stack counts differ.`);
      cursor.requireArray(count, 4);
      cursor.take(count * 4);
    }
  }
  let region: TrackedRegion | undefined;
  for (let list = 0; list < 3; list += 1) {
    const start = cursor.position;
    const count = cursor.u16();
    cursor.requireArray(count, 4);
    cursor.take(count * 4);
    if (list === 0) region = { countOffset: start, count, end: cursor.position };
  }
  const mapCount = cursor.u16();
  if (mapCount > 256) throw new Error("Invalid inventory suffix map count.");
  cursor.requireArray(mapCount, 1);
  cursor.take(mapCount);
  if (cursor.u16() !== mapCount) throw new Error("Inventory suffix map counts differ.");
  cursor.requireArray(mapCount, 4);
  cursor.take(mapCount * 4);
  cursor.take(12);
  if (cursor.remaining !== 0) throw new Error("Unexpected inventory suffix bytes; ambiguous record boundary.");
  if (!region) throw new Error("Inventory suffix tracked-handle list is missing.");
  void handleCount;
  void typeCount;
  return region;
}

/** Port of InventorySuffix.UpgradeTrackedHandles: drop the old handle when its last unit leaves, append the new one. */
export function upgradeTrackedHandles(tail: Buffer, oldHandle: number, newHandle: number, removeOld: boolean, handleCount: number, typeCount: number): Buffer {
  if (handleCount > MAX_HANDLES || oldHandle >= handleCount || newHandle > handleCount || newHandle >= MAX_HANDLES) throw new Error("Invalid tracked inventory handle upgrade.");
  const region = trackedHandleRegion(tail, handleCount, typeCount);
  const entries: number[] = [];
  for (let index = 0; index < region.count; index += 1) {
    const value = tail.readUInt32LE(region.countOffset + 2 + index * 4);
    if (!removeOld || value !== oldHandle) entries.push(value);
  }
  entries.push(newHandle);
  requireCondition(entries.length <= TRACKED_LIST_LIMIT, "The tracked inventory handle list has no capacity for this upgrade.");
  const delta = (entries.length - region.count) * 4;
  const next = Buffer.alloc(tail.length + delta);
  tail.copy(next, 0, 0, region.countOffset);
  next.writeUInt16LE(entries.length, region.countOffset);
  let at = region.countOffset + 2;
  for (const entry of entries) {
    next.writeUInt32LE(entry, at);
    at += 4;
  }
  tail.copy(next, at, region.end);
  return next;
}

function requireCondition(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}
