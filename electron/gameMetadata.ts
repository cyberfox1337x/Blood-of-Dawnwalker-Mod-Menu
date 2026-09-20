import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { itemLevelDefinition } from "./saveItemUpgrade.js";
import { tagId } from "./saveFacts.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_game_metadata");

// Local game metadata from the owner's DwSav asset importer export (the same folder
// the icons are served from, see gameAssets.ts). Nothing is bundled: a missing or
// invalid export disables the related feature with its reason, the way DwSav does.

export type ItemLevelCatalog = ReadonlyMap<string, Readonly<{ hasItemLevel: boolean; upgradeSpread: number }>>;

export type BookDefinition = Readonly<{ traitId: string; locked: readonly boolean[]; quest: boolean; pureBook: boolean }>;

export type TraitCatalogEntry = Readonly<{
  id: string;
  tree: string;
  tier: number;
  maximumRank: number;
  locked: readonly boolean[];
  parents: readonly string[];
  requiredAccess: number;
  spentPoints: number;
  mutation: number;
  ultimate: boolean;
  questSkill: boolean;
  /** Original local asset facts retained for target-rank validation. */
  properties?: Readonly<Record<string, unknown>>;
}>;

export type GameMetadata = Readonly<{
  itemLevels: ItemLevelCatalog;
  books: ReadonlyMap<string, BookDefinition>;
  traits: ReadonlyMap<string, TraitCatalogEntry>;
  gameConfig: string;
}>;

const MAX_ITEMS_JSON_BYTES = 16_777_216;
const MAX_TRAITS_JSON_BYTES = 4_194_304;
const MAX_CONFIG_BYTES = 4_194_304;

function parseJsonArray(text: string, limit: number, what: string): readonly unknown[] {
  if (typeof text !== "string" || text.trim().length === 0 || text.length > limit) throw new Error(`${what} is empty or exceeds the supported limit.`);
  const parsed: unknown = JSON.parse(text);
  if (!Array.isArray(parsed) || parsed.length === 0 || parsed.length > 4096) throw new Error(`Expected a bounded ${what} export.`);
  return parsed;
}

function requiredString(row: object, key: string, what: string): string {
  const value = (row as Record<string, unknown>)[key];
  if (typeof value !== "string" || value.trim().length === 0) throw new Error(`${what}: missing text metadata ${key}.`);
  return value;
}

function integerOr(row: Record<string, unknown>, key: string, missing: number): number {
  const value = row[key];
  if (value === undefined) return missing;
  if (typeof value !== "number" || !Number.isInteger(value)) throw new Error(`Invalid integer metadata: ${key}.`);
  return value;
}

/** Items.json reduced to the weapon/clothing upgrade facts; invalid rows are refused, not skipped. */
export function readItemLevelCatalogFromExport(rows: readonly unknown[]): ItemLevelCatalog {
  const catalog = new Map<string, { hasItemLevel: boolean; upgradeSpread: number }>();
  const seen = new Set<string>();
  for (const row of rows) {
    if (typeof row !== "object" || row === null) continue;
    const type = (row as { Type?: unknown }).Type;
    const properties = (row as { Properties?: unknown }).Properties;
    if (typeof properties !== "object" || properties === null) continue;
    const id = (properties as { ItemId?: unknown }).ItemId;
    if (typeof id !== "string" || id.length === 0 || id === "None") continue;
    if (seen.has(id)) throw new Error("Invalid, duplicate or ambiguous item identifier.");
    seen.add(id);
    if (type === "ItemWeaponDataAsset" || type === "ItemClothingDataAsset") {
      const definition = itemLevelDefinition(row as Readonly<{ Type?: unknown; Class?: unknown; Properties?: unknown }>);
      if (definition) catalog.set(id, definition);
    }
  }
  return catalog;
}

/** Items.json ItemCharDevDataAsset rows mapped to their trait; trait rows provide the bLocked ranks. */
export function readBookCatalog(traitRows: readonly unknown[], itemRows: readonly unknown[]): ReadonlyMap<string, BookDefinition> {
  const lockedByTrait = new Map<string, boolean[]>();
  const questByTrait = new Map<string, boolean>();
  for (const row of traitRows) {
    if (typeof row !== "object" || row === null) continue;
    const type = (row as { Type?: unknown }).Type;
    const properties = (row as { Properties?: unknown }).Properties;
    if (type !== "TraitAsset" || typeof properties !== "object" || properties === null) continue;
    const id = requiredString(properties, "Skill_ID", "Trait metadata");
    if ([...lockedByTrait.keys()].some(key => key.toLowerCase() === id.toLowerCase())) throw new Error("Duplicate trait metadata.");
    const levels = (properties as { Levels?: unknown }).Levels;
    if (!Array.isArray(levels) || levels.length < 1 || levels.length > 32) throw new Error("Trait rank bounds are missing or inconsistent.");
    if (integerOr(properties as Record<string, unknown>, "MaxTraitLevel", 1) !== levels.length) throw new Error("Trait rank bounds are missing or inconsistent.");
    const locked: boolean[] = [];
    for (const level of levels) {
      if (typeof level !== "object" || level === null || typeof (level as { bLocked?: unknown }).bLocked !== "boolean") throw new Error("Incomplete trait book-lock metadata.");
      locked.push((level as { bLocked: boolean }).bLocked);
    }
    lockedByTrait.set(id, locked);
    const unlockWithQuest = (properties as { UnlockWithQuest?: unknown }).UnlockWithQuest;
    if (unlockWithQuest !== undefined && typeof unlockWithQuest !== "boolean") throw new Error("Malformed quest-unlock metadata.");
    questByTrait.set(id, unlockWithQuest === true);
  }
  const books = new Map<string, BookDefinition>();
  const seenBooks = new Set<string>();
  const seenItems = new Set<string>();
  for (const row of itemRows) {
    if (typeof row !== "object" || row === null) continue;
    const properties = (row as { Properties?: unknown }).Properties;
    if (typeof properties !== "object" || properties === null) continue;
    const itemId = requiredString(properties, "ItemId", "Book item").toLowerCase();
    if (seenItems.has(itemId)) throw new Error("Duplicate item metadata.");
    seenItems.add(itemId);
    const traitId = (properties as { LvlUnblockTraitID?: unknown }).LvlUnblockTraitID;
    if (traitId === undefined) continue;
    if (typeof traitId !== "string" || traitId.length === 0 || (row as { Type?: unknown }).Type !== "ItemCharDevDataAsset") throw new Error("Invalid book-to-trait mapping.");
    if (!lockedByTrait.has(traitId)) throw new Error(`Unknown or ambiguous book-to-trait mapping: ${traitId}.`);
    if (seenBooks.has(traitId.toLowerCase())) throw new Error(`Unknown or ambiguous book-to-trait mapping: ${traitId}.`);
    seenBooks.add(traitId.toLowerCase());
    books.set(traitId, { traitId, locked: lockedByTrait.get(traitId)!, quest: questByTrait.get(traitId) ?? false, pureBook: isPureBook(properties as Record<string, unknown>) });
  }
  return books;
}

function isPureBook(book: Record<string, unknown>): boolean {
  const allowed = new Set(["TraitPointsAmount", "LvlUnblockTraitID", "ReadableAssets", "FactIntFactValue", "ItemId", "ItemName", "ItemDescription", "ItemRarity", "ItemMaterial", "SellCost", "BuyCost", "IsSingleUse", "ItemImage"]);
  if (Object.keys(book).some(key => !allowed.has(key))) throw new Error("The mapped book has unsupported properties or effects.");
  if (typeof book.IsSingleUse !== "boolean" || typeof book.ItemMaterial !== "string" || !Number.isInteger(book.TraitPointsAmount) || !Number.isInteger(book.FactIntFactValue)) throw new Error("The mapped book has incomplete effect metadata.");
  const readables = book.ReadableAssets;
  if (!Array.isArray(readables) || readables.length < 1 || readables.length > 32 || readables.some(row => row !== null && (typeof row !== "object" || typeof row.ObjectPath !== "string" || !row.ObjectPath.trim()))) throw new Error("Incomplete skill-book readable metadata.");
  return book.ItemMaterial === "EItemMaterialType::Book" && book.IsSingleUse && book.TraitPointsAmount === 0 && book.FactIntFactValue === 0;
}

/** Traits.json reduced to the facts first-rank acquisition validates: tree, tier, ranks, costs, parents. */
export function readTraitCatalog(rows: readonly unknown[]): ReadonlyMap<string, TraitCatalogEntry> {
  const traits = new Map<string, TraitCatalogEntry>();
  const tagNames = new Map<number, string>();
  for (const row of rows) {
    if (typeof row !== "object" || row === null) continue;
    const properties = (row as { Properties?: unknown }).Properties;
    if (typeof properties !== "object" || properties === null) continue;
    const id = (properties as { Skill_ID?: unknown }).Skill_ID;
    if (typeof id !== "string" || id.length === 0) continue;
    if (traits.has(id)) throw new Error("Incomplete or duplicate trait metadata.");
    const treePath = (properties as { SkillTree?: unknown }).SkillTree;
    if (typeof treePath !== "string" || !treePath.startsWith("ECharacterDevelopmentMode::")) throw new Error(`First acquisition requires a supported Shared, Human, Vampire or Combat Focus trait: ${id}.`);
    const tree = treePath.slice("ECharacterDevelopmentMode::".length);
    const levels = (properties as { Levels?: unknown }).Levels;
    if (!Array.isArray(levels)) throw new Error(`Trait level metadata is incomplete: ${id}.`);
    const locked: boolean[] = [];
    let requiredAccess = 0;
    let spentPoints = 0;
    let mutation = 0;
    for (const level of levels) {
      if (typeof level !== "object" || level === null || typeof (level as { bLocked?: unknown }).bLocked !== "boolean") throw new Error(`Rank requirements are incomplete or unsupported: ${id}.`);
      const record = level as { bLocked: boolean; SPToAccess?: unknown; MutationToUnlock?: unknown; SkillPointsCost?: unknown };
      for (const key of ["SkillPointsCost", "SPToAccess", "MutationToUnlock"] as const) {
        const value = (level as Record<string, unknown>)[key];
        if (value !== undefined && (typeof value !== "number" || !Number.isInteger(value))) throw new Error(`Rank requirements are incomplete or unsupported: ${id}.`);
      }
      locked.push(record.bLocked);
      spentPoints = Math.max(spentPoints, typeof record.SPToAccess === "number" ? record.SPToAccess : 0);
      requiredAccess = record.bLocked ? Math.max(requiredAccess, locked.length) : requiredAccess;
      mutation = Math.max(mutation, typeof record.MutationToUnlock === "number" ? record.MutationToUnlock : 0);
      const addedTags = (level as Record<string, unknown>).AddedTags;
      if (Array.isArray(addedTags)) for (const tag of addedTags) {
        if (typeof tag !== "string") throw new Error("Invalid persistent tag metadata.");
        const identifier = tagId(tag);
        const previous = tagNames.get(identifier);
        if (previous !== undefined && previous.toLowerCase() !== tag.toLowerCase()) throw new Error("Ambiguous gameplay-tag hash in trait metadata.");
        tagNames.set(identifier, tag);
      }
    }
    const maximumRank = levels.length;
    const parents = (properties as { ParentSkills?: unknown }).ParentSkills;
    traits.set(id, {
      id,
      tree,
      tier: integerOr(properties as Record<string, unknown>, "Tier", 1),
      maximumRank,
      locked,
      parents: Array.isArray(parents) ? parents.filter((parent): parent is string => typeof parent === "string") : [],
      requiredAccess,
      spentPoints,
      mutation,
      ultimate: integerOr(properties as Record<string, unknown>, "Tier", 1) === 4,
      questSkill: (properties as { UnlockWithQuest?: unknown }).UnlockWithQuest === true,
      properties: properties as Readonly<Record<string, unknown>>,
    });
  }
  return traits;
}

/** DefaultGame.ini must still match the mapped upgrade profile (ProjectVersion, spread, level cap). */
export function validateUpgradeConfig(gameConfig: string): void {
  if (typeof gameConfig !== "string" || gameConfig.trim().length === 0 || gameConfig.length > MAX_CONFIG_BYTES) throw new Error("Missing or unsupported local game configuration.");
  const sections = new Map<string, Map<string, string>>();
  let current: Map<string, string> | undefined;
  let protectedSection = false;
  for (const rawLine of gameConfig.split("\n")) {
    const line = rawLine.trim();
    if (line.length === 0 || line.startsWith(";") || line.startsWith("#")) continue;
    if (line.startsWith("[")) {
      if (!line.endsWith("]")) throw new Error("Malformed local game configuration section.");
      const name = line.slice(1, -1);
      protectedSection = ["/Script/EngineSettings.GeneralProjectSettings", "/Script/DogwoodInventory.DogwoodInventorySettings", "/Script/DogwoodCharacterDevelopment.DogwoodCharacterDevelopmentSettings"].includes(name);
      if (protectedSection && sections.has(name)) throw new Error("Duplicate mapped upgrade configuration section.");
      current = sections.has(name) ? undefined : new Map();
      if (current) sections.set(name, current);
      continue;
    }
    if (!current) continue;
    const equals = line.indexOf("=");
    if (equals <= 0) throw new Error("Malformed local game configuration value.");
    const key = line.slice(0, equals).trim();
    if (protectedSection && current.has(key) && ["ProjectID", "ProjectName", "ProjectVersion", "ItemUpgradeLevelSpread", "LevelCap"].includes(key.replace(/^[+\-.!]/, ""))) throw new Error(`Duplicate mapped upgrade configuration value: ${key}.`);
    current.set(key, line.slice(equals + 1).trim());
  }
  const general = sections.get("/Script/EngineSettings.GeneralProjectSettings");
  const inventory = sections.get("/Script/DogwoodInventory.DogwoodInventorySettings");
  const development = sections.get("/Script/DogwoodCharacterDevelopment.DogwoodCharacterDevelopmentSettings");
  if (!general || !inventory || !development) throw new Error("Missing mapped upgrade configuration section.");
  const single = (section: Map<string, string>, key: string): string => {
    const matches = [...section.keys()].filter(name => name.replace(/^[+\-.!]/, "") === key);
    if (matches.length !== 1) throw new Error(`Local upgrade configuration differs from the verified profile: ${key}.`);
    return section.get(matches[0])!;
  };
  const supportedVersions = new Set(["1.0.15.0", "1.0.16.0"]);
  if (single(general, "ProjectID") !== "95BA50734B3F6EE6FBA1129EFCD1EC41" || single(general, "ProjectName") !== "Dawnwalker") throw new Error("Local game configuration does not match Dawnwalker.");
  const version = single(general, "ProjectVersion");
  if (!supportedVersions.has(version)) throw new Error(`Item upgrades are not verified for ProjectVersion ${version}. Use Copy report in Logs to report this game build.`);
  if (single(inventory, "ItemUpgradeLevelSpread") !== "1") throw new Error("Local upgrade configuration differs from the verified profile: ItemUpgradeLevelSpread.");
  if (single(development, "LevelCap") !== "50") throw new Error("Local upgrade configuration differs from the verified profile: LevelCap.");
}

/** Loads the export the way gameAssets.ts resolves it; throws with the feature's reason when absent. */
export async function loadGameMetadata(assetDirectory: string): Promise<GameMetadata> {
  const itemsText = await readFile(join(assetDirectory, "items.json"), "utf-8");
  const traitsText = await readFile(join(assetDirectory, "traits.json"), "utf-8");
  const configText = await readFile(join(assetDirectory, "DefaultGame.ini"), "utf-8");
  const itemRows = parseJsonArray(itemsText, MAX_ITEMS_JSON_BYTES, "items.json");
  const traitRows = parseJsonArray(traitsText, MAX_TRAITS_JSON_BYTES, "traits.json");
  return {
    itemLevels: readItemLevelCatalogFromExport(itemRows),
    books: readBookCatalog(traitRows, itemRows),
    traits: readTraitCatalog(traitRows),
    gameConfig: configText,
  };
}

/** The slice of the metadata that flows into save edits (already validated). */
export type SaveEditorMetadata = Readonly<{
  itemLevels?: ReadonlyMap<string, Readonly<{ hasItemLevel: boolean; upgradeSpread: number }>>;
  traits?: ReadonlyMap<string, TraitCatalogEntry>;
  books?: ReadonlyMap<string, BookDefinition>;
  gameConfig?: string;
  /** Set when the export could not be used, so features can be disabled with a reason. */
  unavailableReason?: string;
}>;

/** Loads the save-edit metadata from the resolved export paths; absent files disable features, not the editor. */
export async function loadSaveEditorMetadata(paths: Readonly<{ itemsJson: string | null; traitsJson: string | null; defaultGameIni: string | null }>): Promise<SaveEditorMetadata> {
  const metadata: { itemLevels?: ReturnType<typeof readItemLevelCatalogFromExport>; traits?: ReturnType<typeof readTraitCatalog>; books?: ReadonlyMap<string, BookDefinition>; gameConfig?: string; unavailableReason?: string } = {};
  const problems: string[] = [];
  let itemRows: readonly unknown[] | undefined;
  let traitRows: readonly unknown[] | undefined;
  if (paths.itemsJson) {
    try {
      const text = await readFile(paths.itemsJson, "utf-8");
      itemRows = parseJsonArray(text, MAX_ITEMS_JSON_BYTES, "items.json");
      metadata.itemLevels = readItemLevelCatalogFromExport(itemRows);
    } catch (error) { problems.push(`items.json: ${error instanceof Error ? error.message : String(error)}`); }
  }
  if (paths.traitsJson) {
    try {
      const text = await readFile(paths.traitsJson, "utf-8");
      traitRows = parseJsonArray(text, MAX_TRAITS_JSON_BYTES, "traits.json");
      metadata.traits = readTraitCatalog(traitRows);
    } catch (error) { problems.push(`traits.json: ${error instanceof Error ? error.message : String(error)}`); }
  }
  if (itemRows && traitRows) {
    try { metadata.books = readBookCatalog(traitRows, itemRows); }
    catch (error) { problems.push(`Book metadata: ${error instanceof Error ? error.message : String(error)}`); }
  }
  if (paths.defaultGameIni) {
    try {
      const text = await readFile(paths.defaultGameIni, "utf-8");
      metadata.gameConfig = text;
      validateUpgradeConfig(text);
    } catch (error) { problems.push(`DefaultGame.ini: ${error instanceof Error ? error.message : String(error)}`); }
  }
  if (problems.length > 0) metadata.unavailableReason = problems.join(" ");
  return metadata;
}

export function validateConfigSize(gameConfig: string): void {
  if (typeof gameConfig !== "string" || gameConfig.length > MAX_CONFIG_BYTES) throw new Error("Game configuration exceeds the research limit.");
}
