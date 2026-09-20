import { readFile } from "node:fs/promises";
import type { DsavDocument } from "./dsavContainer.js";
import { readSaveFields } from "./saveFields.js";
import { tagId, readFactsDocument, readCourtState, validateCourtConfig, type CourtState } from "./saveFacts.js";
import { loadSaveEditorMetadata, validateUpgradeConfig } from "./gameMetadata.js";
import { planFieldEdits, type SaveFieldEditResolved } from "./saveEditing.js";
import { readInventoryDocument } from "./saveStructural.js";
import { previewItemUpgrades, type UpgradeOption } from "./saveItemUpgrade.js";
import { parseQuestCatalog, questTrackingOptions } from "./saveJournal.js";
import { acquisitionProfile } from "./savePerkAcquisition.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("save_editor_preview");

export type SaveMetadataPaths = Readonly<{
  itemsJson: string | null; traitsJson: string | null; defaultGameIni: string | null;
  factTagsIni?: string | null; questsJson?: string | null;
}>;
export type SavePerkOptions = Readonly<{ id: string; acquisitionRanks: readonly number[]; bookRanks: readonly number[]; acquisitionStructureMapped: boolean; definitionReason?: string; acquisitionReason?: string; bookReason?: string }>;
export type SaveAdvancedPreview = Readonly<{
  upgrades: readonly UpgradeOption[];
  perks: readonly SavePerkOptions[];
  facts: readonly { tag: string; value: number }[];
  court?: CourtState;
  infamyAvailable: boolean;
  infamyReason?: string;
  quests?: ReturnType<typeof questTrackingOptions>;
  issues: readonly string[];
}>;

// The same planner used to write the save supplies the allowed choices. A missing
// optional subsystem disables its own controls without hiding the proven editor.
export async function inspectAdvancedSave(document: DsavDocument, paths?: SaveMetadataPaths): Promise<SaveAdvancedPreview> {
  const issues: string[] = [];
  const reason = (error: unknown): string => error instanceof Error ? error.message : String(error);
  const metadata = paths ? await loadSaveEditorMetadata(paths) : {};
  if (metadata.unavailableReason) issues.push(metadata.unavailableReason);
  const fields = readSaveFields(document);
  let upgrades: readonly UpgradeOption[] = [];
  try {
    if (!metadata.itemLevels || !metadata.gameConfig) throw new Error("Item upgrades need the local item and game configuration exports.");
    validateUpgradeConfig(metadata.gameConfig);
    const inventory = readInventoryDocument(document);
    if (!inventory || fields.level === undefined) throw new Error("Item upgrades need a readable player inventory and level.");
    upgrades = previewItemUpgrades(inventory, metadata.itemLevels, fields.level);
  } catch (error) { issues.push(reason(error)); }
  const perks: SavePerkOptions[] = [];
  for (const [id, trait] of metadata.traits ?? []) {
    const acquisitionRanks: number[] = [];
    const bookRanks: number[] = [];
    let acquisitionReason: string | undefined;
    let bookReason: string | undefined;
    let acquisitionStructureMapped = false;
    let definitionReason: string | undefined;
    try { acquisitionProfile(id, 1, metadata.traits!); acquisitionStructureMapped = true; }
    catch (error) { definitionReason = reason(error); }
    for (let rank = 1; rank <= Math.min(4, trait.maximumRank); rank += 1) {
      try { planFieldEdits(document, { ...metadata, perkAcquisitions: [{ id, rank }] }); acquisitionRanks.push(rank); }
      catch (error) { acquisitionReason ??= reason(error); }
    }
    for (let accessLevel = 1; accessLevel <= Math.min(32, trait.maximumRank); accessLevel += 1) {
      try { planFieldEdits(document, { ...metadata, bookAccess: [{ id, accessLevel }] } as SaveFieldEditResolved); bookRanks.push(accessLevel); }
      catch (error) { bookReason ??= reason(error); }
    }
    perks.push({ id, acquisitionRanks, bookRanks, acquisitionStructureMapped, ...(definitionReason ? { definitionReason } : {}), ...(acquisitionRanks.length ? {} : { acquisitionReason }), ...(bookRanks.length ? {} : { bookReason }) });
  }
  if (!metadata.traits) issues.push("Perk acquisition and book unlocks need the local trait and item exports.");
  let court: CourtState | undefined;
  let facts: readonly { tag: string; value: number }[] = [];
  let infamyAvailable = false;
  let infamyReason: string | undefined;
  try {
    const documentFacts = readFactsDocument(document);
    if (!documentFacts) throw new Error("This save has no FactsDB record.");
    court = readCourtState(documentFacts.values);
    try {
      if (!paths?.factTagsIni) throw new Error("The local FactTags.ini export is missing; named fact editing is unavailable.");
      facts = mappedSaveFacts(documentFacts.values, parseFactTagNames(await readFile(paths.factTagsIni, "utf8")));
    } catch (error) { issues.push(`Named facts unavailable: ${reason(error)}`); }
    if (!metadata.gameConfig) throw new Error("Infamy requires the local game configuration export.");
    validateCourtConfig(metadata.gameConfig);
    if (court.level !== Math.floor(court.points / 100) || court.activeEdicts < 0 || court.activeEdicts > 9 || court.level - court.pending !== court.activeEdicts) throw new Error("The saved Court state is inconsistent; no repair is guessed.");
    infamyAvailable = true;
  } catch (error) { infamyReason = reason(error); }
  let quests: ReturnType<typeof questTrackingOptions> | undefined;
  try {
    if (!paths?.questsJson) throw new Error("Quest tracking needs the local quests.json export.");
    quests = questTrackingOptions(document, parseQuestCatalog(await readFile(paths.questsJson, "utf8")));
  } catch (error) { issues.push(reason(error)); }
  return { upgrades, perks, facts, court, infamyAvailable, infamyReason, quests, issues };
}

export function parseFactTagNames(text: string): readonly string[] {
  if (text.length > 4_194_304) throw new Error("Fact tag export exceeds the supported limit.");
  const tags = new Map<number, string>();
  for (const match of text.matchAll(/^\s*\+?GameplayTagList\s*=\s*\(Tag="([A-Za-z0-9_.]+)"/gm)) {
    const tag = match[1];
    const identifier = tagId(tag);
    const previous = tags.get(identifier);
    if (previous && previous.toLowerCase() !== tag.toLowerCase()) throw new Error("Fact tag export has an ambiguous tag hash.");
    if (!previous) tags.set(identifier, tag);
  }
  return [...tags.values()];
}

export function mappedSaveFacts(values: ReadonlyMap<number, number>, tags: readonly string[]): readonly { tag: string; value: number }[] {
  const protectedIds = new Set(["Court.StoredAlertLevel", "Court.AlertLevel", "Court.AlertLevelsToHandle", "Court.ActiveEdictsNum"].map(tagId));
  return tags.flatMap(tag => {
    const identifier = tagId(tag);
    const value = values.get(identifier);
    return value === undefined || protectedIds.has(identifier) ? [] : [{ tag, value }];
  }).sort((a, b) => a.tag.localeCompare(b.tag));
}
