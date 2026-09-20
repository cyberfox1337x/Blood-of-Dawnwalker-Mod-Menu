import type { DsavDocument } from "./dsavContainer.js";
import type { TraitCatalogEntry, BookDefinition } from "./gameMetadata.js";
import { readSaveFields } from "./saveFields.js";
import { readFactsDocument, tagId } from "./saveFacts.js";
import { readWritableTraitDocument, spentSkillPointsOf, type WritableTraitDocument } from "./saveTraitDocument.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_perk_acquisition");

type Metadata = Readonly<Record<string, unknown>>;
const EFFECT_DIRECTORY = "/Game/_Dawnwalker/Player/CharacterDevelopment/Traits/GameplayEffects/";

function requireCondition(condition: unknown, reason: string): asserts condition {
  if (!condition) throw new Error(reason);
}

function object(value: unknown, label: string): Metadata {
  requireCondition(typeof value === "object" && value !== null && !Array.isArray(value), `Incomplete ${label} metadata.`);
  return value as Metadata;
}

function integer(row: Metadata, key: string, minimum: number, maximum: number, fallback?: number): number {
  const value = row[key] === undefined ? fallback : row[key];
  requireCondition(typeof value === "number" && Number.isInteger(value) && value >= minimum && value <= maximum, `Unsupported ${key} metadata.`);
  return value;
}

function flag(row: Metadata, key: string): boolean {
  requireCondition(row[key] === undefined || typeof row[key] === "boolean", `Invalid skill flag: ${key}.`);
  return row[key] === true;
}

function list(value: unknown, label: string): readonly unknown[] {
  requireCondition(Array.isArray(value) && value.length <= 32, `Missing or oversized ${label} metadata.`);
  return value;
}

function tagsOf(value: unknown): string[] {
  const tags = list(value, "persistent-tag");
  const seen = new Set<string>();
  return tags.map(tag => {
    requireCondition(typeof tag === "string" && tag.length <= 200 && /^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*$/.test(tag), "Invalid persistent tag.");
    requireCondition(!seen.has(tag.toLowerCase()), "Duplicate persistent tag.");
    seen.add(tag.toLowerCase());
    return tag;
  });
}

function validateCustomEffects(value: unknown): void {
  const seen = new Set<string>();
  for (const entry of list(value, "custom perk effect")) {
    const effect = object(entry, "custom effect");
    requireCondition(list(effect.Parameters, "custom effect parameters").length === 0, "Custom perk grants require an effect with no parameter overrides.");
    const reference = object(effect.GEOrGA, "custom effect reference");
    const path = reference.ObjectPath;
    requireCondition(typeof path === "string" && path.startsWith(EFFECT_DIRECTORY), "Custom perk grants must use the canonical trait effect directory.");
    const match = /^(GE_[A-Za-z0-9_]{1,197})\.(\d+)$/.exec(path.slice(EFFECT_DIRECTORY.length));
    requireCondition(match && Number(match[2]) <= 65535 && reference.ObjectName === `BlueprintGeneratedClass'${match[1]}_C'` && !seen.has(match[1]), "Custom ability grants or ambiguous effect identities require a separate acquisition workflow.");
    seen.add(match[1]);
  }
}

export type AcquisitionProfile = Readonly<{ requiredAccess: number; spentPoints: number; mutation: number; tags: readonly string[]; parents: readonly string[]; ultimate: boolean; aliases: readonly string[] }>;

function abilityAliases(properties: Metadata, catalog: ReadonlyMap<string, TraitCatalogEntry>): string[] {
  const ability = object(properties.CombatFocusAbility, "combat ability class");
  const type = properties.SkillType;
  const kind = type === "ECharacterDevelopmentAbilityType::Combat" ? ["Sword", "Shared"] : type === "ECharacterDevelopmentAbilityType::Magic" ? ["Spells", "Daytime"] : type === "ECharacterDevelopmentAbilityType::Vampire" ? ["Vampire", "Nighttime"] : undefined;
  requireCondition(kind, "Unsupported combat ability type.");
  requireCondition(properties.DisplayedWorkingPhase === `ETraitWorkingPhase::${kind[1]}`, "The combat ability working phase is incomplete.");
  const path = ability.ObjectPath;
  const prefix = flag(properties, "AlwaysEquippedWithoutSlotCost") && kind[0] === "Spells" && typeof path === "string" && path.startsWith("/Game/_Dawnwalker/Player/Abilities/") ? "/Game/_Dawnwalker/Player/Abilities/" : `/Game/_Dawnwalker/Combat/Focus/${kind[0]}/`;
  requireCondition(typeof path === "string" && path.startsWith(prefix), "The combat ability must reference a canonical gameplay ability class.");
  const match = /^[A-Za-z0-9_]+\/(GA_[A-Za-z0-9_]+)\.0$/.exec(path.slice(prefix.length));
  requireCondition(match && ability.ObjectName === `BlueprintGeneratedClass'${match[1]}_C'`, "The combat ability must reference a matching canonical gameplay ability class.");
  const aliases: string[] = [];
  for (const candidate of catalog.values()) {
    if (candidate.id === properties.Skill_ID) continue;
    for (const key of ["CombatFocusAbility", "CombatFocusAbilityDEMO"]) {
      const reference = candidate.properties?.[key];
      if (typeof reference !== "object" || reference === null) continue;
      const record = reference as Metadata;
      if (record.ObjectPath !== path) continue;
      requireCondition(record.ObjectName === ability.ObjectName, "A shared gameplay ability has inconsistent class metadata.");
      aliases.push(candidate.id);
    }
  }
  return aliases;
}

/** DwSav ExperimentalPerkAcquisition metadata checks, evaluated only through the requested rank. */
export function acquisitionProfile(id: string, rank: number, catalog: ReadonlyMap<string, TraitCatalogEntry>): AcquisitionProfile {
  const metadata = catalog.get(id);
  requireCondition(metadata?.properties, `Incomplete first-acquisition metadata for ${id}. Refresh the trait export.`);
  const properties = metadata.properties;
  const tree = metadata.tree;
  requireCondition(["Shared", "Human", "Vampire", "CombatFocus"].includes(tree) && id.startsWith(`${tree}_`) && /^[A-Za-z0-9_]+$/.test(id), "First acquisition requires a supported Shared, Human, Vampire or Combat Focus trait.");
  const tier = integer(properties, "Tier", 0, 4, 1);
  const maximum = integer(properties, "MaxTraitLevel", 1, 4, 1);
  requireCondition(tier !== 4 || maximum === 1, "First acquisition requires a regular trait or a single-rank ultimate.");
  requireCondition(Number.isInteger(rank) && rank >= 1 && rank <= maximum, `Choose a rank between 1 and ${maximum}.`);
  const combat = tree === "CombatFocus";
  const quest = flag(properties, "UnlockWithQuest");
  const automatic = flag(properties, "AlwaysEquippedWithoutSlotCost");
  requireCondition(!(combat && flag(properties, "DescriptionHidden")), "Hidden ability acquisition requires a separately verified ability profile and is not supported here.");
  requireCondition(!(automatic && !combat) && !(quest && !combat && (tree === "Shared" || maximum !== 1 || tier === 4)), "Unsupported automatic or quest skill metadata.");
  for (const key of combat ? ["CombatFocusAbilityDEMO"] : ["CombatFocusAbility", "CombatFocusAbilityDEMO", "SkillType"]) {
    requireCondition(properties[key] === undefined || properties[key] === null, "This trait has an additional ability or skill-type dependency.");
  }
  requireCondition(!combat || (maximum === 4 && tier <= 3), "Unsupported Combat Focus definition for first acquisition.");
  const aliases = combat ? abilityAliases(properties, catalog) : [];
  const parents = list(properties.ParentSkills ?? [], "parent-skill").map(parent => {
    requireCondition(typeof parent === "string" && parent.trim().length > 0 && parent !== id, "Invalid parent-skill metadata.");
    return parent;
  });
  requireCondition(new Set(parents).size === parents.length, "Ambiguous parent-skill metadata.");
  const levels = list(properties.Levels, "trait level");
  requireCondition(levels.length === maximum, "Trait level metadata is incomplete.");
  const levelTags: string[][] = [];
  const active = new Set<number>();
  let requiredAccess = 0;
  let spentPoints = 0;
  let mutation = 0;
  for (let index = 0; index < rank; index++) {
    const level = object(levels[index], `rank ${index + 1}`);
    requireCondition(typeof level.bLocked === "boolean", "Incomplete rank book-lock metadata.");
    integer(level, "SkillPointsCost", 0, 20);
    integer(level, "TimeCost", 0, 20);
    spentPoints = Math.max(spentPoints, integer(level, "SPToAccess", 0, 1000));
    mutation = Math.max(mutation, integer(level, "MutationToUnlock", 0, 1000));
    const effectName = `GE_Trait_${id}_Level_${index + 1}`;
    const effect = object(level.LevelEffect, "rank effect");
    requireCondition(effect.ObjectPath === `${EFFECT_DIRECTORY}${effectName}.0` && effect.ObjectName === `BlueprintGeneratedClass'${effectName}_C'`, `Rank ${index + 1} does not have a matching canonical rank effect.`);
    const replacements = list(level.ReplacesLevel, "rank replacement");
    requireCondition(new Set(replacements).size === replacements.length, "Duplicate rank replacement dependency.");
    for (const previous of replacements) {
      requireCondition(typeof previous === "number" && Number.isInteger(previous) && previous >= 1 && previous <= index, "Rank replacement dependencies must reference earlier ranks of this trait.");
      requireCondition(levelTags[previous - 1].length === 0, "Replacing a rank with persistent tags requires a separate transition.");
      active.delete(previous - 1);
    }
    validateCustomEffects(level.CustomGEOrGAs);
    const tags = tagsOf(level.AddedTags);
    requireCondition(tags.every(tag => tag.startsWith("CharDev.")), "Regular acquisition only supports declared character-development tags.");
    levelTags.push(tags);
    active.add(index);
    if (level.bLocked && !quest) requiredAccess = index + 1;
  }
  const tags = [...new Set([...active].flatMap(index => levelTags[index]))];
  return { requiredAccess, spentPoints, mutation, tags, parents, ultimate: tier === 4, aliases };
}

function requireTraitSpelling(document: DsavDocument, id: string): void {
  requireCondition(!document.names.some(name => name.toLowerCase() === id.toLowerCase() && name !== id), "The save contains an ambiguous spelling of the requested trait identifier.");
}

/** Validates the same saved-state boundaries as DwSav without mutating the document. */
export function validatePerkAcquisition(document: DsavDocument, id: string, rank: number, catalog: ReadonlyMap<string, TraitCatalogEntry>, traits?: WritableTraitDocument): AcquisitionProfile {
  requireTraitSpelling(document, id);
  const profile = acquisitionProfile(id, rank, catalog);
  const stored = traits ?? readWritableTraitDocument(document);
  requireCondition(stored, "CharacterDevelopmentSubsystem is missing from this save.");
  const current = stored.dictionaries[0].get(id) ?? 0;
  const history = stored.dictionaries[1].get(id) ?? 0;
  const maximum = catalog.get(id)!.maximumRank;
  const occurs = stored.progressionNames.includes(id) || stored.abilityNames.includes(id) || stored.abilityGroups.some(group => group.names.includes(id));
  requireCondition(rank > current, "Choose a rank above the current rank. Use Reset skills to lower learned ranks.");
  requireCondition(!(stored.dictionaries[3].get(id) || stored.dictionaries[4].get(id)) && current <= maximum && history <= maximum && !(current === 0 && (history !== 0 || occurs)), "Rank acquisition cannot change unsupported history, secondary progression or an unlearned equipped trait.");
  if (profile.ultimate) for (const [learned, value] of stored.dictionaries[0]) {
    if (value === 0) continue;
    const other = catalog.get(learned);
    requireCondition(other, "An acquired trait lacks metadata; ultimate exclusivity cannot be verified.");
    requireCondition(!(other.tree === catalog.get(id)!.tree && other.tier === 4), "This tree already has an acquired ultimate. Use Replace ultimate instead.");
  }
  for (const alias of profile.aliases) requireCondition(!(stored.dictionaries[0].get(alias)), `The same gameplay ability is already acquired as ${alias}.`);
  for (const parent of profile.parents) requireCondition((stored.dictionaries[0].get(parent) ?? 0) > 0, `Learn the prerequisite ${parent} first.`);
  requireCondition(spentSkillPointsOf(stored) >= profile.spentPoints, `The selected rank requires ${profile.spentPoints} spent skill points.`);
  if (profile.mutation > 0) {
    const mutation = readSaveFields(document).mutationLevel;
    requireCondition(mutation !== undefined && Number.isInteger(mutation) && mutation >= profile.mutation && mutation <= 15, `The selected rank requires mutation level ${profile.mutation}.`);
  }
  requireCondition((stored.dictionaries[2].get(id) ?? 0) >= profile.requiredAccess, `The selected rank requires stored book access through rank ${profile.requiredAccess}. Use Unlock book requirements first.`);
  for (const group of stored.abilityGroups) requireCondition(new Set(group.names).size === group.names.length && group.names.every(name => stored.abilityNames.includes(name)), "The saved combat ability selection is inconsistent.");
  requireCondition(id !== "Shared_SwordfightFocus" || !stored.abilityGroups.some(group => group.key === 1 && group.names.length > 2), "The current Sword Focus loadout exceeds the verified two-slot profile.");
  if (profile.tags.length > 0) {
    const facts = readFactsDocument(document);
    requireCondition(facts, "Persistent perk tags require a readable FactsDB.");
    for (const tag of profile.tags) requireCondition(!facts.values.has(tagId(tag)) || facts.values.get(tagId(tag)) === 1, `A persistent perk tag has an unexpected stored value: ${tag}.`);
  }
  return profile;
}

export function validateBookAccess(document: DsavDocument, id: string, accessLevel: number, books: ReadonlyMap<string, BookDefinition>): void {
  requireTraitSpelling(document, id);
  const book = books.get(id);
  requireCondition(Number.isInteger(accessLevel) && accessLevel > 0 && accessLevel <= 32 && book && !book.quest && book.pureBook && book.locked[accessLevel - 1] === true, "The requested rank is not a mapped pure-book-locked rank.");
}
