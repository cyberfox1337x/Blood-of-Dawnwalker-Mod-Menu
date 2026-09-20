import { createHash } from "node:crypto";
import { decodeDsav, encodeDsav, encodeResizedDsav, parseDsavPayload, type DsavCodec, type DsavDocument } from "./dsavContainer.js";
import { describeItem } from "./itemCatalog.js";
import { planFactChanges, planInfamyChangeOnValues, readCourtState, readFactsDocument, serializeFactsValues, tagId } from "./saveFacts.js";
import { previewItemUpgrades, upgradeOnePlayerItem, type ItemLevelDefinition } from "./saveItemUpgrade.js";
import { handleName, readInventoryDocument, rebuildPayload, removePlayerStack, serializeInventoryDocument, setPlayerStack } from "./saveStructural.js";
import { acquireRankPreservingLoadout, readWritableTraitDocument, serializeTraitDocument, setBookAccess } from "./saveTraitDocument.js";
import { ATTR_BLOOD, ATTR_BLOOD_RESTORATION, ATTR_CORRUPTION_CHARGE, ATTR_HEALTH, ATTR_MUTATION_LEVEL, fieldLocations, readClockMs, readSaveFields, walkInventory } from "./saveFields.js";
import { validateUpgradeConfig, type TraitCatalogEntry, type BookDefinition } from "./gameMetadata.js";
import { acquisitionProfile, validatePerkAcquisition, validateBookAccess } from "./savePerkAcquisition.js";
import { planQuestTracking, readSaveJournal, validateQuestTrackingRequest, type QuestTrackingRequest, type QuestCatalog } from "./saveJournal.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_editing");

const MAX_CLOCK_MS = 0xffffffff;
const MS_PER_DAY = 86_400_000;
const DAY_START_MS = 28_800_000;
const SEGMENT_MS = 5_400_000;
const MAX_HEALTH = 100_000;
const MAX_MUTATION_LEVEL = 15;
const MAX_STACK = 9_999_999;
const MAX_LEVEL = 100;

export type SaveStackEdit = Readonly<{ itemIndex: number; value: number }>;
export type SaveAttributeEdit = Readonly<{ id: number; value: number }>;
export type SaveGiveItemEdit = Readonly<{ definitionIndex: number; value: number }>;
export type SaveReplaceItemEdit = Readonly<{ itemIndex: number; definitionIndex: number; value?: number }>;

export type SaveFieldEdit = Readonly<{
  clockMs?: number;
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
  stacks?: readonly SaveStackEdit[];
  /** Raise a stored perk rank in place (never above its access limit, never lowered). */
  traitRanks?: readonly SaveTraitRankEdit[];
  /** Structural inventory changes: rows added or removed, which rewrites the record length. */
  inventory?: SaveInventoryStructureEdit;
  attributeValues?: readonly SaveAttributeEdit[];
  giveItems?: readonly SaveGiveItemEdit[];
  replaceItems?: readonly SaveReplaceItemEdit[];
  /** DwSav item upgrades: one unit of the item moves to a new handle at the target level. */
  itemUpgrades?: readonly SaveItemUpgradeEdit[];
  /** DwSav first-rank acquisition: sets a rank row the save does not have yet (record grows). */
  perkAcquisitions?: readonly SavePerkAcquisitionEdit[];
  /** DwSav book access: raises a trait's stored access row so its book-locked rank opens. */
  bookAccess?: readonly SaveBookAccessEdit[];
  /** DwSav fact changes: replaces existing FactsDB entries (court facts refused). */
  factChanges?: readonly SaveFactChangeEdit[];
  /** DwSav infamy editor: sets the coupled Court fact trio to a consistent state. */
  infamyPoints?: number;
  /** Select an existing active Story/NanoPOI objective, preserving main tracking. */
  questTracking?: QuestTrackingRequest;
}> & SaveEditMetadata;

export type SaveItemUpgradeEdit = Readonly<{ itemId: string; targetLevel: number; handle?: number }>;
export type SavePerkAcquisitionEdit = Readonly<{ id: string; rank: number }>;
export type SaveBookAccessEdit = Readonly<{ id: string; accessLevel: number }>;
export type SaveFactChangeEdit = Readonly<{ tag: string; value: number; expectedValue?: number }>;
/** Catalog facts the editor needs for the DwSav-verified features; resolved from the asset export. */
export type SaveEditMetadata = Readonly<{
  itemLevels?: ReadonlyMap<string, ItemLevelDefinition>;
  traits?: ReadonlyMap<string, TraitCatalogEntry>;
  books?: ReadonlyMap<string, BookDefinition>;
  gameConfig?: string;
  questCatalog?: QuestCatalog;
}>;
/** The user-editable field set plus the editor-resolved metadata, as it flows into planning and encoding. */
export type SaveFieldEditResolved = SaveFieldEdit & SaveEditMetadata;

export type SaveTraitRankEdit = Readonly<{ id: string; rank: number }>;
/** Add gives the player `quantity` of an item id (creating its rows); remove drops a player stack by its position. */
export type SaveInventoryStructureEdit = Readonly<{ add?: readonly Readonly<{ itemId: string; quantity: number }>[]; remove?: readonly Readonly<{ itemIndex: number }>[] }>;
const ITEM_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$/;
const MAX_STACK_QUANTITY = 2_147_483_647;

export type SaveEditPlan = Readonly<{ field: string; previous: string; next: string }>;

export type SaveEditVerification = Readonly<{
  decodedBytes: number;
  changedBytes: number;
  allowedFields: readonly string[];
  changedFields: readonly string[];
  fieldsBefore: ReturnType<typeof readSaveFields>;
  fieldsAfter: ReturnType<typeof readSaveFields>;
}>;

export type SaveEditResult = Readonly<{
  encodedBytes: number;
  sha256After: string;
  verification: SaveEditVerification;
}>;

function requireCondition(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

// Clock edits preserve the saved clock's phase on the segment grid and stay inside
// the saved 12-hour half, mirroring the reference editor's time-bar contract.

export function segmentBounds(clockMs: number): readonly [number, number] {
  // The game day starts at 08:00 (confirmed in game: "Morning" at 28,800,000).
  // Segments are anchored there, so the night half spans midnight on the raw axis.
  let offset = (clockMs - DAY_START_MS) % MS_PER_DAY;
  if (offset < 0) offset += MS_PER_DAY;
  const gameDayStart = clockMs - offset;
  const half = offset >= 43_200_000 ? 1 : 0;
  const segmentIndex = Math.min(7, Math.floor((offset - half * 43_200_000) / SEGMENT_MS));
  const start = gameDayStart + half * 43_200_000 + segmentIndex * SEGMENT_MS;
  return [start, start + SEGMENT_MS];
}

export function validateFieldEdit(edit: unknown): SaveFieldEdit {
  requireCondition(edit !== null && typeof edit === "object" && !Array.isArray(edit), "Edit must be an object of field values.");
  const source = edit as Record<string, unknown>;
  const result: {
    clockMs?: number; health?: number; blood?: number; mutationLevel?: number;
    level?: number; progressPoints?: number; skillPoints?: number; spentSkillPoints?: number; bloodRestoration?: number; corruptionCharge?: number;
    coin?: number; stacks?: SaveStackEdit[]; traitRanks?: SaveTraitRankEdit[]; inventory?: SaveInventoryStructureEdit; attributeValues?: SaveAttributeEdit[];
    giveItems?: SaveGiveItemEdit[]; replaceItems?: SaveReplaceItemEdit[];
    itemUpgrades?: SaveItemUpgradeEdit[]; perkAcquisitions?: SavePerkAcquisitionEdit[]; bookAccess?: SaveBookAccessEdit[]; factChanges?: SaveFactChangeEdit[]; infamyPoints?: number; questTracking?: QuestTrackingRequest;
  } = {};
  const finiteNumber = (value: unknown): number => {
    requireCondition(typeof value === "number" && Number.isFinite(value), "Field values must be finite numbers.");
    return value;
  };
  if ("clockMs" in source) {
    const value = finiteNumber(source.clockMs);
    requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= MAX_CLOCK_MS, "Clock must be a whole number of milliseconds the save can store.");
    result.clockMs = value;
  }
  if ("health" in source) {
    const value = finiteNumber(source.health);
    requireCondition(value >= 0 && value <= MAX_HEALTH, "Health must be between 0 and 100000.");
    result.health = value;
  }
  if ("blood" in source) {
    const value = finiteNumber(source.blood);
    requireCondition(value >= 0 && value <= MAX_HEALTH, "Blood must be between 0 and 100000.");
    result.blood = value;
  }
  if ("mutationLevel" in source) {
    const value = finiteNumber(source.mutationLevel);
    requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= MAX_MUTATION_LEVEL, "Vampire mutation level must be a whole number from 0 to 15.");
    result.mutationLevel = value;
  }
  if ("coin" in source) {
    const value = finiteNumber(source.coin);
    requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= 4_294_967_295, "Coin must be a whole number the save can store.");
    result.coin = value;
  }
  if ("level" in source) {
    const value = finiteNumber(source.level);
    requireCondition(Number.isSafeInteger(value) && value >= 1 && value <= MAX_LEVEL, `Character level must be a whole number from 1 to ${MAX_LEVEL}.`);
    result.level = value;
  }
  if ("progressPoints" in source) {
    const value = finiteNumber(source.progressPoints);
    requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= 4_294_967_295, "Progress points must be a whole number the save can store.");
    result.progressPoints = value;
  }
  if ("skillPoints" in source) {
    const value = finiteNumber(source.skillPoints);
    requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= 4_294_967_295, "Skill points must be a whole number the save can store.");
    result.skillPoints = value;
  }
  if ("spentSkillPoints" in source) {
    const value = finiteNumber(source.spentSkillPoints);
    requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= 4_294_967_295, "Spent skill points must be a whole number the save can store.");
    result.spentSkillPoints = value;
  }
  // Blood restoration and corruption charge are attribute floats like Health and
  // Blood; the same bounds keep them inside what the game reads back.
  if ("bloodRestoration" in source) {
    const value = finiteNumber(source.bloodRestoration);
    requireCondition(value >= 0 && value <= 100_000, "Blood restoration must be between 0 and 100000.");
    result.bloodRestoration = value;
  }
  if ("corruptionCharge" in source) {
    const value = finiteNumber(source.corruptionCharge);
    requireCondition(value >= 0 && value <= 100_000, "Corruption charge must be between 0 and 100000.");
    result.corruptionCharge = value;
  }
  if ("stacks" in source) {
    requireCondition(Array.isArray(source.stacks), "Stack edits must be a list of item/value pairs.");
    const stacks: SaveStackEdit[] = [];
    const seen = new Set<number>();
    for (const raw of source.stacks as unknown[]) {
      requireCondition(raw !== null && typeof raw === "object", "Each stack edit must be an object.");
      const entry = raw as Record<string, unknown>;
      const itemIndex = entry.itemIndex;
      const value = entry.value;
      requireCondition(typeof itemIndex === "number" && Number.isSafeInteger(itemIndex) && itemIndex >= 0, "Stack edits need a valid item index.");
      requireCondition(!seen.has(itemIndex), `Two stack edits target item index ${itemIndex}.`);
      seen.add(itemIndex);
      requireCondition(typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= MAX_STACK, `Stack values must be whole numbers from 0 to ${MAX_STACK}.`);
      stacks.push({ itemIndex, value });
    }
    requireCondition(stacks.length > 0, "Stack edits are empty.");
    result.stacks = stacks;
  }
  if ("traitRanks" in source) {
    requireCondition(Array.isArray(source.traitRanks), "Perk rank edits must be a list of id/rank pairs.");
    const ranks: SaveTraitRankEdit[] = [];
    const seen = new Set<string>();
    for (const raw of source.traitRanks as unknown[]) {
      requireCondition(typeof raw === "object" && raw !== null, "Each perk rank edit must name a perk and a rank.");
      const { id, rank } = raw as { id?: unknown; rank?: unknown };
      requireCondition(typeof id === "string" && /^[A-Za-z0-9_.-]{1,120}$/.test(id), "Perk id must be the game's internal skill id.");
      const value = finiteNumber(rank);
      requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= 32, "Perk rank must be a whole number from 0 to 32.");
      requireCondition(!seen.has(id), `Perk ${id} is listed twice.`);
      seen.add(id);
      ranks.push({ id, rank: value });
    }
    requireCondition(ranks.length > 0, "Perk rank edits must include at least one perk.");
    result.traitRanks = ranks;
  }
  if ("inventory" in source) {
    requireCondition(typeof source.inventory === "object" && source.inventory !== null, "Inventory changes must list items to add or rows to remove.");
    const { add, remove } = source.inventory as { add?: unknown; remove?: unknown };
    const adds: { itemId: string; quantity: number }[] = [];
    const removes: { itemIndex: number }[] = [];
    if (add !== undefined) {
      requireCondition(Array.isArray(add), "Items to add must be a list.");
      const seen = new Set<string>();
      for (const raw of add as unknown[]) {
        requireCondition(typeof raw === "object" && raw !== null, "Each item to add must name an item id and a quantity.");
        const { itemId, quantity } = raw as { itemId?: unknown; quantity?: unknown };
        requireCondition(typeof itemId === "string" && ITEM_ID_PATTERN.test(itemId), "Item id must be the game's internal ItemId (letters, digits, _ . -).");
        const value = finiteNumber(quantity);
        requireCondition(Number.isSafeInteger(value) && value >= 1 && value <= MAX_STACK_QUANTITY, `Quantity for ${itemId} must be a whole number from 1 to ${MAX_STACK_QUANTITY}.`);
        requireCondition(!seen.has(itemId), `Item ${itemId} is listed twice.`);
        seen.add(itemId);
        adds.push({ itemId, quantity: value });
      }
    }
    if (remove !== undefined) {
      requireCondition(Array.isArray(remove), "Rows to remove must be a list.");
      const seen = new Set<number>();
      for (const raw of remove as unknown[]) {
        requireCondition(typeof raw === "object" && raw !== null, "Each row to remove must name its inventory position.");
        const index = finiteNumber((raw as { itemIndex?: unknown }).itemIndex);
        requireCondition(Number.isSafeInteger(index) && index >= 0 && index <= 65535, "Inventory row position must be a whole number.");
        requireCondition(!seen.has(index), `Inventory row ${index} is listed twice.`);
        seen.add(index);
        removes.push({ itemIndex: index });
      }
    }
    requireCondition(adds.length + removes.length > 0, "Inventory changes must include at least one item to add or row to remove.");
    result.inventory = { add: adds, remove: removes };
  }
  if ("attributeValues" in source) {
    requireCondition(Array.isArray(source.attributeValues), "Attribute edits must be a list of id/value pairs.");
    const attributes: SaveAttributeEdit[] = [];
    const seen = new Set<number>();
    for (const raw of source.attributeValues as unknown[]) {
      requireCondition(raw !== null && typeof raw === "object", "Each attribute edit must be an object.");
      const entry = raw as Record<string, unknown>;
      const id = entry.id;
      const value = entry.value;
      requireCondition(typeof id === "number" && Number.isSafeInteger(id) && id >= 0, "Attribute edits need a valid attribute id.");
      requireCondition(!seen.has(id), `Two attribute edits target attribute id ${id}.`);
      seen.add(id);
      requireCondition(typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= MAX_HEALTH, `Attribute values must be finite numbers within ±${MAX_HEALTH}.`);
      attributes.push({ id, value });
    }
    requireCondition(attributes.length > 0, "Attribute edits are empty.");
    result.attributeValues = attributes;
  }
  if ("giveItems" in source) {
    requireCondition(Array.isArray(source.giveItems), "Give-item edits must be a list of definition/count pairs.");
    const gives: SaveGiveItemEdit[] = [];
    const seenDefs = new Set<number>();
    for (const raw of source.giveItems as unknown[]) {
      requireCondition(raw !== null && typeof raw === "object", "Each give-item edit must be an object.");
      const entry = raw as Record<string, unknown>;
      const definitionIndex = entry.definitionIndex;
      const value = entry.value;
      requireCondition(typeof definitionIndex === "number" && Number.isSafeInteger(definitionIndex) && definitionIndex >= 0, "Give-item edits need a valid definition index.");
      requireCondition(!seenDefs.has(definitionIndex), `Two give edits target definition ${definitionIndex}.`);
      seenDefs.add(definitionIndex);
      requireCondition(typeof value === "number" && Number.isSafeInteger(value) && value >= 1 && value <= MAX_STACK, `Given counts must be whole numbers from 1 to ${MAX_STACK}.`);
      gives.push({ definitionIndex, value });
    }
    requireCondition(gives.length > 0, "Give-item edits are empty.");
    result.giveItems = gives;
  }
  if ("replaceItems" in source) {
    requireCondition(Array.isArray(source.replaceItems), "Replace-item edits must be a list of item/definition pairs.");
    const replaces: SaveReplaceItemEdit[] = [];
    const seenItems = new Set<number>();
    for (const raw of source.replaceItems as unknown[]) {
      requireCondition(raw !== null && typeof raw === "object", "Each replace-item edit must be an object.");
      const entry = raw as Record<string, unknown>;
      const itemIndex = entry.itemIndex;
      const definitionIndex = entry.definitionIndex;
      const value = entry.value;
      requireCondition(typeof itemIndex === "number" && Number.isSafeInteger(itemIndex) && itemIndex >= 0, "Replace-item edits need a valid item index.");
      requireCondition(!seenItems.has(itemIndex), `Two replace edits target item index ${itemIndex}.`);
      seenItems.add(itemIndex);
      requireCondition(typeof definitionIndex === "number" && Number.isSafeInteger(definitionIndex) && definitionIndex >= 0, "Replace-item edits need a valid definition index.");
      requireCondition(value === undefined || (typeof value === "number" && Number.isSafeInteger(value) && value >= 1 && value <= MAX_STACK), `Replacement counts must be whole numbers from 1 to ${MAX_STACK}.`);
      replaces.push({ itemIndex, definitionIndex, value });
    }
    requireCondition(replaces.length > 0, "Replace-item edits are empty.");
    result.replaceItems = replaces;
  }
  if ("itemUpgrades" in source) {
    requireCondition(Array.isArray(source.itemUpgrades), "Item upgrades must be a list of item/level pairs.");
    const upgrades: SaveItemUpgradeEdit[] = [];
    const seen = new Set<string>();
    for (const raw of source.itemUpgrades as unknown[]) {
      requireCondition(raw !== null && typeof raw === "object", "Each item upgrade must name an item id and a target level.");
      const entry = raw as Record<string, unknown>;
      const itemId = entry.itemId;
      const targetLevel = entry.targetLevel;
      const handle = entry.handle;
      requireCondition(handle === undefined || (typeof handle === "number" && Number.isSafeInteger(handle) && handle >= 0 && handle < 131072), "Item upgrade handle is invalid.");
      requireCondition(typeof itemId === "string" && ITEM_ID_PATTERN.test(itemId), "Item upgrades need the game's internal ItemId.");
      requireCondition(typeof targetLevel === "number" && Number.isSafeInteger(targetLevel) && targetLevel >= 1 && targetLevel <= 50, "Upgrade level must be a whole number from 1 to 50.");
      requireCondition(!seen.has(itemId), `Item ${itemId} is upgraded twice.`);
      seen.add(itemId);
      upgrades.push({ itemId, targetLevel, ...(handle === undefined ? {} : { handle }) });
    }
    requireCondition(upgrades.length > 0, "Item upgrades are empty.");
    result.itemUpgrades = upgrades;
  }
  if ("perkAcquisitions" in source) {
    requireCondition(Array.isArray(source.perkAcquisitions), "Perk acquisitions must be a list of id/rank pairs.");
    const acquisitions: SavePerkAcquisitionEdit[] = [];
    const seen = new Set<string>();
    for (const raw of source.perkAcquisitions as unknown[]) {
      requireCondition(typeof raw === "object" && raw !== null, "Each perk acquisition must name a perk and a rank.");
      const { id, rank } = raw as { id?: unknown; rank?: unknown };
      requireCondition(typeof id === "string" && /^[A-Za-z0-9_.-]{1,120}$/.test(id), "Perk id must be the game's internal skill id.");
      const value = finiteNumber(rank);
      requireCondition(Number.isSafeInteger(value) && value >= 1 && value <= 4, "Perk acquisition rank must be a whole number from 1 to 4.");
      requireCondition(!seen.has(id), `Perk ${id} is listed twice.`);
      seen.add(id);
      acquisitions.push({ id, rank: value });
    }
    requireCondition(acquisitions.length > 0, "Perk acquisitions are empty.");
    result.perkAcquisitions = acquisitions;
  }
  if ("bookAccess" in source) {
    requireCondition(Array.isArray(source.bookAccess), "Book access edits must be a list of id/access pairs.");
    const access: SaveBookAccessEdit[] = [];
    const seen = new Set<string>();
    for (const raw of source.bookAccess as unknown[]) {
      requireCondition(typeof raw === "object" && raw !== null, "Each book access edit must name a perk and an access level.");
      const { id, accessLevel } = raw as { id?: unknown; accessLevel?: unknown };
      requireCondition(typeof id === "string" && /^[A-Za-z0-9_.-]{1,120}$/.test(id), "Perk id must be the game's internal skill id.");
      const value = finiteNumber(accessLevel);
      requireCondition(Number.isSafeInteger(value) && value >= 1 && value <= 32, "Book access must be a whole number from 1 to 32.");
      requireCondition(!seen.has(id), `Perk ${id} is listed twice.`);
      seen.add(id);
      access.push({ id, accessLevel: value });
    }
    requireCondition(access.length > 0, "Book access edits are empty.");
    result.bookAccess = access;
  }
  if ("factChanges" in source) {
    requireCondition(Array.isArray(source.factChanges), "Fact changes must be a list of tag/value pairs.");
    const facts: SaveFactChangeEdit[] = [];
    const seen = new Set<string>();
    for (const raw of source.factChanges as unknown[]) {
      requireCondition(typeof raw === "object" && raw !== null, "Each fact change must name a gameplay tag and a value.");
      const entry = raw as Record<string, unknown>;
      const tag = entry.tag;
      const value = entry.value;
      requireCondition(typeof tag === "string" && /^[A-Za-z0-9._]{1,120}$/.test(tag), "Fact tags use ASCII letters, digits, dots and underscores.");
      requireCondition(typeof value === "number" && Number.isSafeInteger(value) && value >= -2_147_483_648 && value <= 2_147_483_647, "Fact values must be whole numbers the save can store.");
      requireCondition(!seen.has(tag), `Fact ${tag} is listed twice.`);
      seen.add(tag);
      requireCondition(entry.expectedValue === undefined || (typeof entry.expectedValue === "number" && Number.isSafeInteger(entry.expectedValue)), "Expected fact values must be whole numbers.");
      facts.push({ tag, value, ...(entry.expectedValue !== undefined ? { expectedValue: entry.expectedValue as number } : {}) });
    }
    requireCondition(facts.length > 0, "Fact changes are empty.");
    result.factChanges = facts;
  }
  if ("infamyPoints" in source) {
    const value = finiteNumber(source.infamyPoints);
    requireCondition(Number.isSafeInteger(value) && value >= 0 && value <= 900, "Infamy must be a whole number from 0 to 900.");
    result.infamyPoints = value;
  }
  if ("questTracking" in source) result.questTracking = validateQuestTrackingRequest(source.questTracking);
  requireCondition(Object.keys(result).length > 0, "No editable field was provided.");
  return result;
}

export function planFieldEdits(document: DsavDocument, edit: SaveFieldEditResolved): readonly SaveEditPlan[] {
  // Upgrades can move a stack to another handle before in-place edits resolve row
  // positions. Keep that transaction separate so quantity edits cannot multiply
  // the upgraded unit or invalidate the owner-level limit checked in preview.
  if (edit.itemUpgrades !== undefined) {
    requireCondition(edit.inventory === undefined && edit.stacks === undefined && edit.giveItems === undefined && edit.replaceItems === undefined && edit.level === undefined, "Apply inventory and character-level changes separately from item upgrades.");
  }
  // Acquisition requirements are checked against the selected save. A later
  // in-place write must not lower those prerequisites in the same transaction.
  if (edit.perkAcquisitions !== undefined) {
    requireCondition(edit.spentSkillPoints === undefined && edit.mutationLevel === undefined && !edit.attributeValues?.some(attribute => attribute.id === ATTR_MUTATION_LEVEL), "Apply perk prerequisite changes separately from perk acquisitions.");
  }
  const fields = readSaveFields(document);
  const plans: SaveEditPlan[] = [];
  if (edit.clockMs !== undefined) {
    const delta = edit.clockMs - fields.clockMs;
    requireCondition(delta !== 0, "The chosen segment is already the saved segment.");
    requireCondition(delta % SEGMENT_MS === 0, "Clock edits move by whole 90-minute segments while preserving the saved clock's phase.");
    requireCondition(Math.abs(delta) < 43_200_000, "Crossing into the other half of the day is not offered; pick a segment inside the saved half-day.");
    const [currentStart] = segmentBounds(fields.clockMs);
    const [nextStart] = segmentBounds(edit.clockMs);
    plans.push({ field: "clockMs", previous: `segment containing ${currentStart}`, next: `segment containing ${nextStart}` });
  }
  if (edit.health !== undefined) {
    requireCondition(fields.health !== undefined, "Health is not present in this save.");
    plans.push({ field: "health", previous: String(fields.health), next: String(edit.health) });
  }
  if (edit.blood !== undefined) {
    requireCondition(fields.blood !== undefined, "Blood is not present in this save.");
    plans.push({ field: "blood", previous: String(fields.blood), next: String(edit.blood) });
  }
  if (edit.mutationLevel !== undefined) {
    requireCondition(fields.mutationLevel !== undefined, "Vampire mutation level is not present in this save.");
    plans.push({ field: "mutationLevel", previous: String(fields.mutationLevel), next: String(edit.mutationLevel) });
  }
  if (edit.coin !== undefined) {
    requireCondition(fields.coin !== undefined, "This save has no Coin entry, so money cannot be edited.");
    plans.push({ field: "coin", previous: String(fields.coin), next: String(edit.coin) });
  }
  if (edit.level !== undefined) {
    requireCondition(fields.level !== undefined, "Character level is not present in this save.");
    requireCondition(fields.level !== edit.level, "The chosen level is already the saved level.");
    plans.push({ field: "level", previous: String(fields.level), next: String(edit.level) });
  }
  if (edit.progressPoints !== undefined) {
    requireCondition(fields.progressPoints !== undefined, "Progress points are not present in this save.");
    requireCondition(fields.progressPoints !== edit.progressPoints, "The chosen progress value is already the saved value.");
    plans.push({ field: "progressPoints", previous: String(fields.progressPoints), next: String(edit.progressPoints) });
  }
  if (edit.skillPoints !== undefined) {
    requireCondition(fields.skillPoints !== undefined, "Skill points are not present in this save.");
    requireCondition(fields.skillPoints !== edit.skillPoints, "The chosen skill point total is already the saved value.");
    plans.push({ field: "skillPoints", previous: String(fields.skillPoints), next: String(edit.skillPoints) });
  }
  if (edit.spentSkillPoints !== undefined) {
    requireCondition(fields.spentSkillPoints !== undefined, "Spent skill points are not present in this save.");
    requireCondition(fields.spentSkillPoints !== edit.spentSkillPoints, "The chosen spent-point total is already the saved value.");
    plans.push({ field: "spentSkillPoints", previous: String(fields.spentSkillPoints), next: String(edit.spentSkillPoints) });
  }
  if (edit.bloodRestoration !== undefined) {
    requireCondition(fields.bloodRestoration !== undefined, "Blood restoration is not present in this save.");
    requireCondition(fields.bloodRestoration !== edit.bloodRestoration, "The chosen blood restoration is already the saved value.");
    plans.push({ field: "bloodRestoration", previous: String(fields.bloodRestoration), next: String(edit.bloodRestoration) });
  }
  if (edit.corruptionCharge !== undefined) {
    requireCondition(fields.corruptionCharge !== undefined, "Corruption charge is not present in this save.");
    requireCondition(fields.corruptionCharge !== edit.corruptionCharge, "The chosen corruption charge is already the saved value.");
    plans.push({ field: "corruptionCharge", previous: String(fields.corruptionCharge), next: String(edit.corruptionCharge) });
  }
  if (edit.stacks !== undefined) {
    requireCondition(fields.stacks !== undefined && fields.stacks.length > 0, "No player inventory stacks were found in this save.");
    const byIndex = new Map(fields.stacks.map((stack) => [stack.itemIndex, stack]));
    for (const { itemIndex, value } of edit.stacks) {
      const current = byIndex.get(itemIndex);
      requireCondition(current !== undefined, `Item index ${itemIndex} is not part of this save's player inventory.`);
      requireCondition(current.value !== value, `Item ${current.name} already holds ${value}.`);
      plans.push({ field: `stack:${itemIndex}:${current.name}`, previous: String(current.value), next: String(value) });
    }
  }
  if (edit.traitRanks !== undefined) {
    for (const { id, rank } of edit.traitRanks) {
      const trait = fields.traits.find(entry => entry.id === id);
      requireCondition(trait !== undefined && trait.storedRank, `Perk ${id} has no stored rank row in this save, so it cannot be rewritten in place.`);
      requireCondition(rank !== trait.rank, `Perk ${id} already has rank ${rank}.`);
      requireCondition(rank > trait.rank, `Perk ${id}: lowering a rank needs an equipment-aware respec, which this editor does not do.`);
      requireCondition(rank <= trait.accessLimit, `Perk ${id}: rank ${rank} is above the stored access limit ${trait.accessLimit}.`);
      plans.push({ field: `perk:${id}`, previous: String(trait.rank), next: String(rank) });
    }
  }
  if (edit.attributeValues !== undefined) {
    requireCondition(fields.attributes !== undefined && fields.attributes.length > 0, "No saved attributes were found in this save.");
    const byId = new Map(fields.attributes.map((attribute) => [attribute.id, attribute]));
    for (const { id, value } of edit.attributeValues) {
      const current = byId.get(id);
      requireCondition(current !== undefined, `Attribute id ${id} is not present in this save.`);
      requireCondition(current.value !== value, `Attribute ${current.name} already holds ${value}.`);
      plans.push({ field: `attribute:${id}:${current.name}`, previous: String(current.value), next: String(value) });
    }
  }
  const walk = tryWalk(document);
  if (edit.inventory !== undefined) {
    const owned = new Map(fields.stacks.map((stack) => [stack.name, stack]));
    for (const { itemId, quantity } of edit.inventory.add ?? []) {
      const known = describeItem(itemId).catalogued || walk?.catalog.some((entry) => entry.name === itemId);
      requireCondition(known === true, `${itemId} is not a known item id; the catalog and this save both lack it.`);
      requireCondition(itemId !== "Coin", "Coins are edited through the Coin field, not as an inventory row.");
      const current = owned.get(itemId);
      requireCondition(current === undefined || current.value !== quantity, `You already carry ${quantity} of ${itemId}.`);
      requireCondition(!edit.stacks?.some((stack) => stack.itemIndex === current?.itemIndex), `${itemId} is edited twice: change its count in one place.`);
      plans.push({ field: `inventory:add:${itemId}`, previous: current ? String(current.value) : "absent", next: String(quantity) });
    }
    const byIndex = new Map(fields.stacks.map((stack) => [stack.itemIndex, stack]));
    for (const { itemIndex } of edit.inventory.remove ?? []) {
      const current = byIndex.get(itemIndex);
      requireCondition(current !== undefined, `Inventory row ${itemIndex} is not part of this save's player inventory.`);
      requireCondition(current.name !== "Coin", "Coins cannot be removed as a row; set the Coin field instead.");
      requireCondition(!edit.inventory.add?.some((entry) => entry.itemId === current.name), `${current.name} is both added and removed.`);
      requireCondition(!edit.stacks?.some((stack) => stack.itemIndex === itemIndex), `Inventory row ${itemIndex} is both removed and given a new count.`);
      plans.push({ field: `inventory:remove:${current.name}`, previous: String(current.value), next: "removed" });
    }
  }
  if (edit.giveItems !== undefined) {
    const resolved = resolveGives(walk, edit.giveItems);
    for (const give of resolved) {
      plans.push({ field: `give:${give.itemIndex}:${give.name}`, previous: "absent", next: String(give.value) });
    }
  }
  if (edit.replaceItems !== undefined) {
    const stackByIndex = new Map(fields.stacks.map((stack) => [stack.itemIndex, stack]));
    const resolved = resolveReplaces(walk, edit.replaceItems);
    for (const replace of resolved) {
      const current = stackByIndex.get(replace.itemIndex);
      requireCondition(current !== undefined, `Item index ${replace.itemIndex} is not part of this save's player inventory.`);
      requireCondition(current.name !== replace.name, `Item ${current.name} already is ${replace.name}; edit its stack count instead.`);
      if (replace.value !== undefined) {
        requireCondition(!edit.stacks?.some((stack) => stack.itemIndex === replace.itemIndex), `Item index ${replace.itemIndex} is edited twice: combine the replacement and count into one request.`);
      }
      plans.push({ field: `replace:${replace.itemIndex}:${current.name}`, previous: current.name, next: replace.value !== undefined ? `${replace.name} x${replace.value}` : replace.name });
    }
  }
  if (edit.itemUpgrades !== undefined) {
    requireCondition(edit.itemLevels !== undefined, "Item upgrades need the game's item metadata; refresh the game asset export.");
    requireCondition(edit.gameConfig !== undefined, "Item upgrades require the verified game configuration.");
    validateUpgradeConfig(edit.gameConfig);
    const inventory = readInventoryDocument(document);
    requireCondition(inventory !== undefined, "InventorySubsystem is missing from this save.");
    const level = fields.level;
    requireCondition(level !== undefined, "Character level is not present in this save, so the upgrade limit cannot be checked.");
    const catalog = edit.itemLevels;
    for (const { itemId, targetLevel, handle } of edit.itemUpgrades) {
      const candidates = previewItemUpgrades(inventory, catalog, level).filter(candidate => candidate.itemId === itemId && (handle === undefined || candidate.handle === handle));
      requireCondition(candidates.length <= 1, "Choose the exact inventory handle for an item with multiple stacks.");
      const option = candidates[0];
      requireCondition(option !== undefined, `${itemId} has no upgradeable player stack in this save.`);
      requireCondition(targetLevel > option!.currentLevel && targetLevel <= option!.maximumLevel, `Upgrade level must be above ${option!.currentLevel} and no higher than the mapped owner limit ${option!.maximumLevel}.`);
      upgradeOnePlayerItem(inventory, { itemId, targetLevel, handle, playerLevel: level }, catalog);
      plans.push({ field: `itemUpgrade:${itemId}`, previous: `level ${option!.currentLevel}`, next: `level ${targetLevel}` });
    }
  }
  if (edit.perkAcquisitions !== undefined) {
    requireCondition(edit.traits !== undefined, "Perk acquisitions need the game's trait metadata; refresh the game asset export.");
    const traitRows = readWritableTraitDocument(document);
    requireCondition(traitRows !== undefined, "CharacterDevelopmentSubsystem is missing from this save.");
    for (const { id, rank } of edit.perkAcquisitions) {
      const profile = validatePerkAcquisition(document, id, rank, edit.traits, traitRows);
      const existing = traitRows!.dictionaries[0].get(id) ?? 0;
      for (const tag of profile.tags) requireCondition(!edit.factChanges?.some(change => tagId(change.tag) === tagId(tag) && change.value !== 1), `Fact ${tag} conflicts with a persistent perk tag.`);
      requireCondition(!edit.traitRanks?.some(change => change.id === id), `Perk ${id} is edited twice.`);
      acquireRankPreservingLoadout(traitRows, id, rank);
      plans.push({ field: `perkAcquisition:${id}`, previous: existing === 0 ? "unacquired" : `rank ${existing}`, next: `rank ${rank}` });
    }
  }
  if (edit.bookAccess !== undefined) {
    requireCondition(edit.books !== undefined, "Book access requires the game's pure-book metadata; refresh the asset export.");
    const traitRows = readWritableTraitDocument(document);
    requireCondition(traitRows !== undefined, "CharacterDevelopmentSubsystem is missing from this save.");
    for (const { id, accessLevel } of edit.bookAccess) {
      validateBookAccess(document, id, accessLevel, edit.books);
      const current = traitRows!.dictionaries[2].get(id) ?? 0;
      requireCondition(accessLevel > current, `Book access for ${id} is already ${current}; it cannot be lowered.`);
      plans.push({ field: `bookAccess:${id}`, previous: current === 0 ? "none" : `rank ${current}`, next: `rank ${accessLevel}` });
    }
  }
  if (edit.factChanges !== undefined) {
    for (const change of edit.factChanges) {
      plans.push({ field: `fact:${change.tag}`, previous: "stored value", next: String(change.value) });
    }
  }
  if (edit.infamyPoints !== undefined) {
    const court = readCourtStateOf(document);
    requireCondition(court !== undefined, "Missing FactsDB in this save.");
    requireCondition(court!.points !== edit.infamyPoints, `Infamy is already ${edit.infamyPoints} points.`);
    plans.push({ field: "infamyPoints", previous: String(court!.points), next: String(edit.infamyPoints) });
  }
  if (edit.questTracking) {
    requireCondition(edit.questCatalog !== undefined, "Quest tracking needs the local quest catalog.");
    const plan = planQuestTracking(document, edit.questTracking, edit.questCatalog);
    requireCondition(plan.changed, "This objective is already tracked.");
    plans.push({ field: "questTracking", previous: edit.questTracking.expectedOther.instanceId || "none", next: plan.expectedOther.instanceId });
  }
  requireCondition(plans.length > 0, "No listed edit changes this save.");
  return plans;
}

function tryWalk(document: DsavDocument): ReturnType<typeof walkInventory> | undefined {
  try { return walkInventory(document); } catch { return undefined; }
}

function readCourtStateOf(document: DsavDocument): Readonly<{ points: number; level: number; pending: number; activeEdicts: number }> | undefined {
  try {
    const facts = readFactsDocument(document);
    return facts ? readCourtState(facts.values) : undefined;
  } catch {
    return undefined;
  }
}

// Deterministic give plan: every requested definition must exist exactly once
// in the key table, not already be owned, and take a distinct free slot.
function resolveGives(walk: ReturnType<typeof walkInventory> | undefined, gives: readonly SaveGiveItemEdit[]): readonly { itemIndex: number; keyIndex: number; keySlotOffset: number; countOffset: number; value: number; name: string }[] {
  requireCondition(walk !== undefined, "The player inventory could not be parsed in this save.");
  const catalog = new Map(walk.catalog.map((entry) => [entry.definitionIndex, entry]));
  const keyByDefinition = new Map(walk.keyEntries.map((key) => [key.definitionIndex, key.keyIndex]));
  const freeSlots = [...walk.freeSlots].sort((a, b) => a.itemIndex - b.itemIndex);
  const usedSlots = new Set<number>();
  const resolved: { itemIndex: number; keyIndex: number; keySlotOffset: number; countOffset: number; value: number; name: string }[] = [];
  for (const { definitionIndex, value } of gives) {
    const entry = catalog.get(definitionIndex);
    requireCondition(entry !== undefined, `Definition ${definitionIndex} does not exist in this save's item table.`);
    requireCondition(!entry.owned, `${entry.name} is already in the player inventory; edit its stack count instead.`);
    const keyIndex = keyByDefinition.get(definitionIndex);
    requireCondition(keyIndex !== undefined, `${entry.name} has no key-table entry in this save, so it cannot be given without changing the save's structure. Refusing to guess.`);
    const slot = freeSlots.find((candidate) => !usedSlots.has(candidate.itemIndex));
    requireCondition(slot !== undefined, `No free inventory slot is available for ${entry.name}; the save's fixed layout cannot grow. Remove an item first or pick a save with a free slot.`);
    usedSlots.add(slot.itemIndex);
    resolved.push({ itemIndex: slot.itemIndex, keyIndex, keySlotOffset: slot.keySlotOffset, countOffset: slot.countOffset, value, name: entry.name });
  }
  return resolved;
}

// Deterministic replace plan: the target slot must be owned, the new definition
// must exist exactly once in the key table, and replacing Coin is refused.
function resolveReplaces(walk: ReturnType<typeof walkInventory> | undefined, replaces: readonly SaveReplaceItemEdit[]): readonly { itemIndex: number; keyIndex: number; keySlotOffset: number; name: string; value?: number }[] {
  requireCondition(walk !== undefined, "The player inventory could not be parsed in this save.");
  const catalog = new Map(walk.catalog.map((entry) => [entry.definitionIndex, entry]));
  const keyByDefinition = new Map(walk.keyEntries.map((key) => [key.definitionIndex, key.keyIndex]));
  const stackByIndex = new Map(walk.stacks.map((stack) => [stack.itemIndex, stack]));
  const resolved: { itemIndex: number; keyIndex: number; keySlotOffset: number; name: string; value?: number }[] = [];
  for (const { itemIndex, definitionIndex, value } of replaces) {
    const current = stackByIndex.get(itemIndex);
    requireCondition(current !== undefined, `Item index ${itemIndex} is not part of this save's player inventory.`);
    requireCondition(current.name !== "Coin", "Replacing Coin is refused; edit the coin value instead.");
    const entry = catalog.get(definitionIndex);
    requireCondition(entry !== undefined, `Definition ${definitionIndex} does not exist in this save's item table.`);
    const keyIndex = keyByDefinition.get(definitionIndex);
    requireCondition(keyIndex !== undefined, `${entry.name} has no key-table entry in this save, so it cannot be substituted without changing the save's structure. Refusing to guess.`);
    resolved.push({ itemIndex, keyIndex, keySlotOffset: current.keySlotOffset, name: entry.name, value });
  }
  return resolved;
}

function applyEdits(document: DsavDocument, edit: SaveFieldEdit): { payload: Buffer; touched: Map<number, string> } {
  const locations = fieldLocations(document);
  const payload = Buffer.from(document.payload);
  const touched = new Map<number, string>();
  const claim = (offset: number, length: number, field: string): void => {
    for (let index = offset; index < offset + length; index += 1) {
      requireCondition(!touched.has(index), `Two edits overlap at byte ${index}.`);
      touched.set(index, field);
    }
  };
  if (edit.clockMs !== undefined) {
    requireCondition(locations.clock !== undefined, "TimeSystemImpl clock location is unavailable.");
    const clock = locations.clock;
    claim(clock.offset, 4, "clockMs");
    payload.writeUInt32LE(edit.clockMs, clock.offset);
  }
  const attributeEdits: readonly (readonly [number, number | undefined, string])[] = [
    [ATTR_HEALTH, edit.health, "health"],
    [ATTR_BLOOD, edit.blood, "blood"],
    [ATTR_MUTATION_LEVEL, edit.mutationLevel, "mutationLevel"],
    [ATTR_BLOOD_RESTORATION, edit.bloodRestoration, "bloodRestoration"],
    [ATTR_CORRUPTION_CHARGE, edit.corruptionCharge, "corruptionCharge"],
  ];
  for (const [id, value, field] of attributeEdits) {
    if (value === undefined) continue;
    const location = locations.attributes[id];
    requireCondition(location !== undefined, `Attribute ${id} location is unavailable.`);
    requireCondition(Number.isFinite(payload.readFloatLE(location.offset)), `Attribute ${id} does not hold a finite float.`);
    claim(location.offset, 4, field);
    payload.writeFloatLE(value, location.offset);
  }
  if (edit.coin !== undefined) {
    requireCondition(locations.coin !== undefined, "Coin stack location is unavailable.");
    const coin = locations.coin;
    claim(coin.offset, 4, "coin");
    payload.writeUInt32LE(edit.coin, coin.offset);
  }
  if (edit.level !== undefined) {
    requireCondition(locations.level !== undefined, "Character level location is unavailable.");
    const level = locations.level;
    claim(level.offset, 4, "level");
    payload.writeUInt32LE(edit.level, level.offset);
  }
  if (edit.progressPoints !== undefined) {
    requireCondition(locations.progressPoints !== undefined, "Progress points location is unavailable.");
    const progress = locations.progressPoints;
    claim(progress.offset, 4, "progressPoints");
    payload.writeUInt32LE(edit.progressPoints, progress.offset);
  }
  if (edit.skillPoints !== undefined) {
    requireCondition(locations.skillPoints !== undefined, "Skill points location is unavailable.");
    claim(locations.skillPoints.offset, 4, "skillPoints");
    payload.writeUInt32LE(edit.skillPoints, locations.skillPoints.offset);
  }
  if (edit.spentSkillPoints !== undefined) {
    requireCondition(locations.spentSkillPoints !== undefined, "Spent skill points location is unavailable.");
    claim(locations.spentSkillPoints.offset, 4, "spentSkillPoints");
    payload.writeUInt32LE(edit.spentSkillPoints, locations.spentSkillPoints.offset);
  }
  if (edit.stacks !== undefined) {
    const byIndex = new Map(locations.stacks.map((stack) => [stack.itemIndex, stack]));
    for (const { itemIndex, value } of edit.stacks) {
      const stack = byIndex.get(itemIndex);
      requireCondition(stack !== undefined, `Item index ${itemIndex} location is unavailable.`);
      claim(stack.offset, 4, `stack:${itemIndex}:${stack.name}`);
      payload.writeUInt32LE(value, stack.offset);
    }
  }
  if (edit.traitRanks !== undefined) {
    for (const { id, rank } of edit.traitRanks) {
      const location = locations.traitRanks.get(id);
      requireCondition(location !== undefined, `Perk ${id} rank location is unavailable.`);
      claim(location.rankOffset, 4, `perk:${id}`);
      payload.writeUInt32LE(rank, location.rankOffset);
      // The "highest rank ever" row follows the rank up, as the game would record it.
      if (rank > location.highestRank) {
        requireCondition(location.highestOffset !== undefined, `Perk ${id}: the save has no highest-rank row to raise, so the rank cannot exceed ${location.highestRank}.`);
        claim(location.highestOffset, 4, `perk-highest:${id}`);
        payload.writeUInt32LE(rank, location.highestOffset);
      }
    }
  }
  if (edit.attributeValues !== undefined) {
    for (const { id, value } of edit.attributeValues) {
      const location = locations.attributes[id];
      requireCondition(location !== undefined, `Attribute ${id} location is unavailable.`);
      requireCondition(Number.isFinite(payload.readFloatLE(location.offset)), `Attribute ${id} does not hold a finite float.`);
      claim(location.offset, 4, `attribute:${id}`);
      payload.writeFloatLE(value, location.offset);
    }
  }
  const walk = tryWalk(document);
  if (edit.giveItems !== undefined) {
    const resolved = resolveGives(walk, edit.giveItems);
    for (const give of resolved) {
      claim(give.keySlotOffset, 4, `give:${give.itemIndex}:${give.name}`);
      claim(give.countOffset, 4, `give:${give.itemIndex}:${give.name}`);
      requireCondition(payload.readUInt32LE(give.keySlotOffset) === 0xffffffff, `Slot ${give.itemIndex} was not free at write time.`);
      requireCondition(payload.readUInt32LE(give.countOffset) === 0, `Slot ${give.itemIndex}'s count was not empty at write time.`);
      payload.writeUInt32LE(give.keyIndex, give.keySlotOffset);
      payload.writeUInt32LE(give.value, give.countOffset);
    }
  }
  if (edit.replaceItems !== undefined) {
    const resolved = resolveReplaces(walk, edit.replaceItems);
    for (const replace of resolved) {
      claim(replace.keySlotOffset, 4, `replace:${replace.itemIndex}:${replace.name}`);
      requireCondition(payload.readUInt32LE(replace.keySlotOffset) !== 0xffffffff, `Slot ${replace.itemIndex} was expected to hold an item.`);
      payload.writeUInt32LE(replace.keyIndex, replace.keySlotOffset);
      if (replace.value !== undefined) {
        const stack = walk?.stacks.find((candidate) => candidate.itemIndex === replace.itemIndex);
        requireCondition(stack !== undefined, `Item index ${replace.itemIndex} has no count cell.`);
        claim(stack.offset, 4, `replace:${replace.itemIndex}:${replace.name}`);
        payload.writeUInt32LE(replace.value, stack.offset);
      }
    }
  }
  return { payload, touched };
}

export async function encodeEditedSave(
  originalBytes: Buffer,
  edit: SaveFieldEditResolved,
  codec: DsavCodec,
): Promise<Readonly<{ encoded: Buffer; verification: SaveEditVerification }>> {
  const original = await decodeDsav(originalBytes, codec);
  const plans = planFieldEdits(original, edit);
  requireCondition(plans.length > 0, "No listed edit changes this save.");
  const changedFields = new Set<string>();
  let changedBytes = 0;
  // Structural record changes rebuild their region first; every in-place edit is then
  // applied to the rebuilt document, whose field locations are recomputed.
  const rebuilt = rebuildStructural(original, edit);
  const document = rebuilt?.document ?? original;
  if (rebuilt) {
    for (const field of rebuilt.changedFields) changedFields.add(field);
    changedBytes += Math.abs(document.payload.length - original.payload.length);
  }
  const { inventory: _structural, itemUpgrades: _upgrades, perkAcquisitions: _acquisitions, bookAccess: _books, factChanges: _facts, infamyPoints: _infamy, questTracking: _tracking,
    itemLevels: _itemLevels, traits: _traits, books: _bookCatalog, gameConfig: _gameConfig, questCatalog: _questCatalog, ...inPlace } = edit;
  void _structural; void _upgrades; void _acquisitions; void _books; void _facts; void _infamy; void _tracking;
  void _itemLevels; void _traits; void _bookCatalog; void _gameConfig; void _questCatalog;
  const hasInPlace = Object.values(inPlace).some((value) => value !== undefined);
  const { payload, touched } = hasInPlace ? applyEdits(document, inPlace) : { payload: Buffer.from(document.payload), touched: new Map<number, string>() };
  requireCondition(payload.length === document.payload.length, "Edit changed the payload length.");
  for (let index = 0; index < payload.length; index += 1) {
    if (payload[index] === document.payload[index]) continue;
    const field = touched.get(index);
    requireCondition(field !== undefined, `Edit changed byte ${index} outside the permitted fields.`);
    changedFields.add(field);
    changedBytes += 1;
  }
  const encoded = rebuilt
    ? await encodeResizedDsav(original, payload, rebuilt.namesOffset, rebuilt.nodesOffset, codec)
    : await encodeDsav(document, payload, codec);
  const readback = await decodeDsav(encoded, codec);
  requireCondition(readback.payload.equals(payload), "Re-encoded save did not decode back to the edited bytes.");
  const fieldsAfter = readSaveFields(readback);
  if (edit.questTracking) {
    requireCondition(edit.questCatalog !== undefined, "Quest tracking catalog is missing during verification.");
    const expected = planQuestTracking(original, edit.questTracking, edit.questCatalog);
    const actual = readSaveJournal(readback);
    requireCondition(actual !== undefined && actual.prefix.equals(expected.prefix), "Edited quest tracking did not read back exactly.");
  }
  if (edit.health !== undefined) requireCondition(fieldsAfter.health === edit.health, "Edited Health did not read back.");
  if (edit.blood !== undefined) requireCondition(fieldsAfter.blood === edit.blood, "Edited Blood did not read back.");
  if (edit.mutationLevel !== undefined) requireCondition(fieldsAfter.mutationLevel === edit.mutationLevel, "Edited mutation level did not read back.");
  if (edit.coin !== undefined) requireCondition(fieldsAfter.coin === edit.coin, "Edited coin did not read back.");
  if (edit.clockMs !== undefined) requireCondition(readClockMs(readback) === edit.clockMs, "Edited clock did not read back.");
  if (edit.level !== undefined) requireCondition(fieldsAfter.level === edit.level, "Edited level did not read back.");
  if (edit.progressPoints !== undefined) requireCondition(fieldsAfter.progressPoints === edit.progressPoints, "Edited progress points did not read back.");
  if (edit.skillPoints !== undefined) requireCondition(fieldsAfter.skillPoints === edit.skillPoints, "Edited skill points did not read back.");
  if (edit.spentSkillPoints !== undefined) requireCondition(fieldsAfter.spentSkillPoints === edit.spentSkillPoints, "Edited spent skill points did not read back.");
  if (edit.bloodRestoration !== undefined) requireCondition(fieldsAfter.bloodRestoration === edit.bloodRestoration, "Edited blood restoration did not read back.");
  if (edit.corruptionCharge !== undefined) requireCondition(fieldsAfter.corruptionCharge === edit.corruptionCharge, "Edited corruption charge did not read back.");
  if (edit.traitRanks !== undefined) {
    for (const { id, rank } of edit.traitRanks) {
      const trait = fieldsAfter.traits.find(entry => entry.id === id);
      requireCondition(trait !== undefined && trait.rank === rank && trait.highestRank >= rank, `Edited perk ${id} did not read back at rank ${rank}.`);
    }
  }
  if (edit.inventory !== undefined) verifyInventoryStructure(readSaveFields(original), fieldsAfter, edit.inventory);
  if (edit.stacks !== undefined) {
    const afterStacks = new Map((fieldsAfter.stacks ?? []).map((stack) => [stack.itemIndex, stack.value]));
    for (const { itemIndex, value } of edit.stacks) {
      requireCondition(afterStacks.get(itemIndex) === value, `Edited stack for item index ${itemIndex} did not read back.`);
    }
  }
  if (edit.attributeValues !== undefined) {
    const afterAttributes = new Map((fieldsAfter.attributes ?? []).map((attribute) => [attribute.id, attribute.value]));
    for (const { id, value } of edit.attributeValues) {
      requireCondition(afterAttributes.get(id) === value, `Edited attribute ${id} did not read back.`);
    }
  }
  if (edit.giveItems !== undefined) {
    const walkAfter = tryWalk(readback);
    requireCondition(walkAfter !== undefined, "The written save no longer parses its player inventory.");
    const afterByName = new Map(walkAfter.stacks.map((stack) => [stack.name, stack.value]));
    const catalog = new Map(walkAfter.catalog.map((entry) => [entry.definitionIndex, entry.name]));
    for (const { definitionIndex, value } of edit.giveItems) {
      const name = catalog.get(definitionIndex);
      requireCondition(name !== undefined && afterByName.get(name) === value, `Given item ${name ?? definitionIndex} did not read back with count ${value}.`);
    }
  }
  if (edit.replaceItems !== undefined) {
    const walkAfter = tryWalk(readback);
    requireCondition(walkAfter !== undefined, "The written save no longer parses its player inventory.");
    const afterByIndex = new Map(walkAfter.stacks.map((stack) => [stack.itemIndex, stack]));
    const catalog = new Map(walkAfter.catalog.map((entry) => [entry.definitionIndex, entry.name]));
    for (const { itemIndex, definitionIndex, value } of edit.replaceItems) {
      const name = catalog.get(definitionIndex);
      const stack = afterByIndex.get(itemIndex);
      requireCondition(name !== undefined && stack?.name === name, `Replaced slot ${itemIndex} did not read back as ${name ?? definitionIndex}.`);
      if (value !== undefined) requireCondition(stack.value === value, `Replaced slot ${itemIndex} did not read back with count ${value}.`);
    }
  }
  if (edit.itemUpgrades !== undefined) {
    const walkAfter = tryWalk(readback);
    requireCondition(walkAfter !== undefined, "The written save no longer parses its player inventory.");
    for (const { itemId, targetLevel } of edit.itemUpgrades) {
      const upgraded = walkAfter.stacks.filter(stack => stack.name === itemId).length;
      requireCondition(upgraded >= 1, `Upgraded ${itemId} did not read back as an owned stack.`);
      const inventory = readInventoryDocument(readback);
      const player = inventory?.owners.find(owner => owner.key === 1 && owner.flag === 0);
      const upgradedStacks = player?.stacks.filter(stack => {
        const handle = inventory?.handles[stack.handle];
        return stack.quantity > 0 && handle && inventory?.types[handle.type] === itemId && handle.variant === targetLevel;
      });
      requireCondition(upgradedStacks?.length === 1, `Upgraded ${itemId} did not read back at level ${targetLevel}.`);
    }
  }
  if (edit.perkAcquisitions !== undefined) {
    const afterTraits = fieldsAfter.traits;
    for (const { id, rank } of edit.perkAcquisitions) {
      const trait = afterTraits.find(entry => entry.id === id);
      requireCondition(trait !== undefined && trait.rank === rank && trait.highestRank >= rank, `First-acquired perk ${id} did not read back at rank ${rank}.`);
      const profile = acquisitionProfile(id, rank, edit.traits!);
      if (profile.tags.length > 0) {
        const facts = readFactsDocument(readback);
        requireCondition(facts !== undefined && profile.tags.every(tag => facts.values.get(tagId(tag)) === 1), `Persistent tags for ${id} did not read back.`);
      }
    }
  }
  if (edit.bookAccess !== undefined) {
    const afterTraits = fieldsAfter.traits;
    for (const { id, accessLevel } of edit.bookAccess) {
      const trait = afterTraits.find(entry => entry.id === id);
      requireCondition(trait !== undefined && trait.accessLimit >= accessLevel, `Book access for ${id} did not read back as rank ${accessLevel}.`);
    }
  }
  if (edit.factChanges !== undefined || edit.infamyPoints !== undefined) {
    const facts = readFactsDocument(readback);
    requireCondition(facts !== undefined, "The written save no longer parses its FactsDB.");
    if (edit.factChanges !== undefined) {
      for (const change of edit.factChanges) {
        const value = facts!.values.get(tagId(change.tag));
        requireCondition(value !== undefined && value === (change.value | 0), `Fact ${change.tag} did not read back as ${change.value}.`);
      }
    }
    if (edit.infamyPoints !== undefined) {
      const court = readCourtState(facts!.values);
      requireCondition(court.points === edit.infamyPoints, `Infamy did not read back as ${edit.infamyPoints} points.`);
      requireCondition(court.level === Math.floor(court.points / 100), `Infamy level did not read back consistently with ${court.points} points.`);
    }
  }
  return {
    encoded,
    verification: {
      decodedBytes: payload.length,
      changedBytes,
      allowedFields: plans.map(({ field }) => field),
      changedFields: [...changedFields],
      fieldsBefore: readSaveFields(original),
      fieldsAfter,
    },
  };
}

export function editedSaveSha256(encoded: Buffer): string {
  return createHash("sha256").update(encoded).digest("hex");
}

export const SAVE_EDIT_BOUNDS = Object.freeze({ MAX_HEALTH, MAX_MUTATION_LEVEL, MAX_CLOCK_MS, MS_PER_DAY, DAY_START_MS, SEGMENT_MS });

type RebuiltInventory = Readonly<{ document: DsavDocument; namesOffset: number; nodesOffset: number; changedFields: readonly string[] }>;

// Applies the structural record changes (inventory rows, perk acquisition, book access,
// facts) to their records and rebuilds the payload around them. Removals are resolved
// to handles on the original stacks, so a position always means the row the user saw.
function rebuildStructural(original: DsavDocument, edit: SaveFieldEditResolved): RebuiltInventory | undefined {
  const replacements = new Map<string, Buffer>();
  const names = [...original.names];
  const changedFields: string[] = [];
  const nameIndex = (name: string): number => {
    const existing = names.indexOf(name);
    if (existing >= 0) return existing + 1;
    names.push(name);
    return names.length;
  };
  if (edit.inventory) {
    const inventory = readInventoryDocument(original);
    requireCondition(inventory !== undefined, "InventorySubsystem is missing from this save.");
    const player = inventory.owners.find((owner) => owner.key === 1 && owner.flag === 0);
    requireCondition(player !== undefined, "This save has no player inventory to change.");
    for (const { itemIndex } of edit.inventory.remove ?? []) {
      const row = player.stacks[itemIndex];
      requireCondition(row !== undefined && row.handle !== 0xffffffff, `Inventory row ${itemIndex} is empty or missing.`);
      const name = handleName(inventory, row.handle);
      removePlayerStack(inventory, row.handle);
      changedFields.push(`inventory:remove:${name}`);
    }
    for (const { itemId, quantity } of edit.inventory.add ?? []) {
      setPlayerStack(inventory, itemId, quantity);
      changedFields.push(`inventory:add:${itemId}`);
    }
    replacements.set("InventorySubsystem", serializeInventoryDocument(inventory, nameIndex));
  }
  if (edit.itemUpgrades !== undefined) {
    requireCondition(edit.itemLevels !== undefined, "Item upgrades need the game's item metadata; refresh the game asset export.");
    const inventory = replacements.has("InventorySubsystem")
      ? readInventoryDocument(parseReplaced(original, replacements, names))
      : readInventoryDocument(original);
    requireCondition(inventory !== undefined, "InventorySubsystem is missing from this save.");
    const level = readSaveFields(original).level;
    requireCondition(level !== undefined, "Character level is not present in this save.");
    for (const { itemId, targetLevel, handle } of edit.itemUpgrades) {
      const newHandle = upgradeOnePlayerItem(inventory, { itemId, targetLevel, handle, playerLevel: level }, edit.itemLevels);
      changedFields.push(`itemUpgrade:${itemId}@handle${newHandle}`);
    }
    replacements.set("InventorySubsystem", serializeInventoryDocument(inventory, nameIndex));
  }
  if (edit.perkAcquisitions !== undefined || edit.bookAccess !== undefined) {
    const traits = readWritableTraitDocument(original);
    requireCondition(traits !== undefined, "CharacterDevelopmentSubsystem is missing from this save.");
    for (const { id, rank } of edit.perkAcquisitions ?? []) {
      requireCondition(edit.traits !== undefined, "Perk acquisitions require trait metadata.");
      const profile = validatePerkAcquisition(original, id, rank, edit.traits, traits);
      if (profile.tags.length > 0) {
        const base = replacements.has("FactsDB") ? parseReplaced(original, replacements, names) : original;
        const facts = readFactsDocument(base);
        requireCondition(facts !== undefined, "Persistent perk tags require a readable FactsDB.");
        const next = new Map(facts.values);
        for (const tag of profile.tags) { next.set(tagId(tag), 1); changedFields.push(`perkTag:${tag}`); }
        replacements.set("FactsDB", serializeFactsValues(next));
      }
      acquireRankPreservingLoadout(traits!, id, rank);
      changedFields.push(`perkAcquisition:${id}`);
    }
    for (const { id, accessLevel } of edit.bookAccess ?? []) {
      setBookAccess(traits!, id, accessLevel);
      changedFields.push(`bookAccess:${id}`);
    }
    replacements.set("CharacterDevelopmentSubsystem", serializeTraitDocument(traits!, nameIndex));
  }
  if (edit.factChanges !== undefined || edit.infamyPoints !== undefined) {
    // Both kinds rewrite the same FactsDB record, so they chain onto one table.
    const base = replacements.has("FactsDB") ? parseReplaced(original, replacements, names) : original;
    let next: Map<number, number>;
    if (edit.factChanges !== undefined) {
      next = new Map(planFactChanges(base, edit.factChanges).next);
      for (const change of edit.factChanges) changedFields.push(`fact:${change.tag}`);
    } else {
      const facts = readFactsDocument(base);
      requireCondition(facts !== undefined, "Missing FactsDB in this save.");
      next = new Map(facts!.values);
    }
    if (edit.infamyPoints !== undefined) {
      requireCondition(edit.gameConfig !== undefined, "The infamy editor needs the game's DefaultGame.ini from the asset export.");
      const { next: afterInfamy, changed } = planInfamyChangeOnValues(next, edit.infamyPoints, edit.gameConfig!);
      if (changed) {
        changedFields.push("infamyPoints");
        next = afterInfamy;
      }
    }
    replacements.set("FactsDB", serializeFactsValues(next));
  }
  if (edit.questTracking) {
    requireCondition(edit.questCatalog !== undefined, "Quest tracking needs the local quest catalog.");
    const tracking = planQuestTracking(original, edit.questTracking, edit.questCatalog);
    replacements.set("Journal", tracking.prefix);
    changedFields.push("questTracking");
  }
  if (replacements.size === 0) return undefined;
  const { payload, namesOffset, nodesOffset } = rebuildPayload(original, replacements, names);
  const container = { ...original.container, namesOffset, nodesOffset, payloadBytes: payload.length };
  const document = parseDsavPayload(container, payload);
  requireCondition(readInventoryDocument(document) !== undefined || !replacements.has("InventorySubsystem"), "Rebuilt inventory record does not parse.");
  return { document, namesOffset, nodesOffset, changedFields };
}

function parseReplaced(original: DsavDocument, replacements: ReadonlyMap<string, Buffer>, names: readonly string[]): DsavDocument {
  const { payload, namesOffset, nodesOffset } = rebuildPayload(original, replacements, names);
  const container = { ...original.container, namesOffset, nodesOffset, payloadBytes: payload.length };
  return parseDsavPayload(container, payload);
}

function verifyInventoryStructure(before: ReturnType<typeof readSaveFields>, after: ReturnType<typeof readSaveFields>, edit: SaveInventoryStructureEdit): void {
  const afterByName = new Map(after.stacks.map((stack) => [stack.name, stack.value]));
  for (const { itemId, quantity } of edit.add ?? []) {
    requireCondition(afterByName.get(itemId) === quantity, `Added item ${itemId} did not read back with quantity ${quantity}.`);
  }
  for (const { itemIndex } of edit.remove ?? []) {
    const removed = before.stacks[itemIndex];
    requireCondition(removed !== undefined, `Removed row ${itemIndex} was not in the original inventory.`);
    const stillAdded = edit.add?.some((entry) => entry.itemId === removed.name);
    requireCondition(stillAdded || !afterByName.has(removed.name), `Removed item ${removed.name} is still in the inventory.`);
  }
  const untouched = new Set([...(edit.add ?? []).map((entry) => entry.itemId), ...(edit.remove ?? []).map(({ itemIndex }) => before.stacks[itemIndex]?.name)]);
  for (const stack of before.stacks) {
    if (untouched.has(stack.name)) continue;
    requireCondition(afterByName.get(stack.name) === stack.value, `Untouched item ${stack.name} changed during the rebuild.`);
  }
}
