import { describe, expect, it } from "vitest";
import { decodeDsav, encodeDsavContainer, parseDsavPayload, type DsavCodec, type DsavDocument } from "../electron/dsavContainer";
import { writePacked } from "../electron/recordCursor";
import { readFactsDocument, planFactChanges, planInfamyChangeOnValues, readCourtState, tagId, INFAMY_POINTS_TAG, INFAMY_LEVEL_TAG, INFAMY_PENDING_TAG, ACTIVE_EDICTS_TAG } from "../electron/saveFacts";
import { readInventoryDocument, rebuildPayload, serializeInventoryDocument } from "../electron/saveStructural";
import { readWritableTraitDocument, serializeTraitDocument, acquireRankPreservingLoadout, setBookAccess, spentSkillPointsOf } from "../electron/saveTraitDocument";
import { previewItemUpgrades, upgradeOnePlayerItem, itemLevelDefinition, readItemLevelCatalog } from "../electron/saveItemUpgrade";
import { readItemLevelCatalogFromExport, readTraitCatalog, validateUpgradeConfig, loadSaveEditorMetadata } from "../electron/gameMetadata";
import { encodeEditedSave, planFieldEdits, validateFieldEdit } from "../electron/saveEditing";
import { readSaveFields, walkInventory } from "../electron/saveFields";
import { acquisitionProfile, validatePerkAcquisition } from "../electron/savePerkAcquisition";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_save_ports_tests");

const u8 = (value: number) => Buffer.from([value]);
const u16 = (value: number) => { const b = Buffer.alloc(2); b.writeUInt16LE(value); return b; };
const u32 = (value: number) => { const b = Buffer.alloc(4); b.writeUInt32LE(value >>> 0); return b; };

function canonicalTrait(id = "Vampire_BloodRush", requirements: Record<string, unknown>[] = [{}]) {
  return { Type: "TraitAsset", Properties: {
    Skill_ID: id, SkillTree: `ECharacterDevelopmentMode::${id.split("_")[0]}`, MaxTraitLevel: requirements.length,
    Levels: requirements.map((requirement, index) => ({
      bLocked: false, SkillPointsCost: 1, TimeCost: 1, SPToAccess: 0, MutationToUnlock: 0,
      ReplacesLevel: [], AddedTags: [], CustomGEOrGAs: [],
      LevelEffect: { ObjectPath: `/Game/_Dawnwalker/Player/CharacterDevelopment/Traits/GameplayEffects/GE_Trait_${id}_Level_${index + 1}.0`, ObjectName: `BlueprintGeneratedClass'GE_Trait_${id}_Level_${index + 1}_C'` },
      ...requirement,
    })),
  } };
}

function pureBook(traitId: string) {
  return { Type: "ItemCharDevDataAsset", Properties: { ItemId: `Book_${traitId}`, LvlUnblockTraitID: traitId, ItemMaterial: "EItemMaterialType::Book", IsSingleUse: true, TraitPointsAmount: 0, FactIntFactValue: 0, ReadableAssets: [null] } };
}

function upgradeConfig(): string {
  return "[/Script/EngineSettings.GeneralProjectSettings]\nProjectID=95BA50734B3F6EE6FBA1129EFCD1EC41\nProjectName=Dawnwalker\nProjectVersion=1.0.16.0\n[/Script/DogwoodInventory.DogwoodInventorySettings]\nItemUpgradeLevelSpread=1\n[/Script/DogwoodCharacterDevelopment.DogwoodCharacterDevelopmentSettings]\nLevelCap=50";
}

// ---------------------------------------------------------------------------
// Synthetic save: Root containing TimeSystemImpl, AttributeSaveSystem,
// InventorySubsystem, CharacterDevelopmentSubsystem and FactsDB records.
// ---------------------------------------------------------------------------

const NAMES = ["Root", "TimeSystemImpl", "AttributeSaveSystem", "InventorySubsystem", "CharacterDevelopmentSubsystem", "FactsDB", "SwordLongCommon2", "Medicaments1", "VoraciousBite", "BloodRush"];

function traitRecord(): Buffer {
  const index = (name: string) => NAMES.indexOf(name) + 1;
  const dict = (rows: [string, number][]) => Buffer.concat([
    u32(rows.length),
    ...rows.map(([name, value]) => Buffer.concat([writePacked(index(name)), u32(value)])),
  ]);
  const names = (list: string[]) => Buffer.concat([u32(list.length), ...list.map(name => writePacked(index(name)))]);
  const prefix = Buffer.alloc(17);
  prefix.writeUInt32LE(8, 0);       // ledger: level 8 (readSaveFields reads +4 of the node)
  prefix.writeUInt32LE(0, 4);       // progress points
  prefix.writeUInt32LE(7, 8);       // skill points
  prefix.writeUInt32LE(5, 12);      // spent skill points
  prefix.writeUInt8(0, 16);         // state byte
  return Buffer.concat([
    prefix,
    dict([["VoraciousBite", 2]]),           // section 0: ranks
    dict([["VoraciousBite", 2]]),           // section 1: highest rank
    names(["VoraciousBite"]),               // section 2: progression names
    dict([["BloodRush", 1]]),               // section 3: book access
    dict([]),                               // section 4
    dict([]),                               // section 5
    names([]),                              // ability names
    u32(0),                                 // ability groups
    u32(0), u8(0),                          // trailing flag + byte
  ]);
}

function factsRecord(): Buffer {
  const rows: [number, number][] = [
    [tagId(INFAMY_POINTS_TAG), 350],
    [tagId(INFAMY_LEVEL_TAG), 3],
    [tagId(INFAMY_PENDING_TAG), 1],
    [tagId(ACTIVE_EDICTS_TAG), 2],
    [tagId("Day.Night"), 1],
    [tagId("Quest.Q713.Done"), 1],
  ];
  return Buffer.concat([u16(1), u32(rows.length), ...rows.map(([tag, value]) => Buffer.concat([u32(tag), u32(value)]))]);
}

function inventoryRecord(): Buffer {
  const index = (name: string) => NAMES.indexOf(name) + 1;
  const suffix = Buffer.concat([
    u16(0), u16(0),
    u32(0),
    u16(1), u32(0),
    u16(0),
    u16(0),
    u16(0), u16(0),
    Buffer.alloc(12),
  ]);
  return Buffer.concat([
    u32(531369477),
    u32(2), writePacked(index("SwordLongCommon2")), writePacked(index("Medicaments1")),
    u32(2), u32(0), u8(4), u32(1), u8(0),   // handle 0 = SwordLongCommon2 variant 4; handle 1 = Medicaments1
    u32(1),
    u32(1), u8(0),
    u16(2), u32(0), u32(1),
    u16(2), u32(1), u32(3),
    u8(0), u32(1), u16(1), u8(5), u16(1), u32(0),
    u16(1), u32(1),
    suffix,
  ]);
}

function buildSave(): { bytes: Buffer; codec: DsavCodec } {
  const root = Buffer.concat([Buffer.from("SN"), u16(0)]);
  const clock = Buffer.concat([Buffer.from("SN"), u16(1), u32(0), u32(28_800_000)]);
  const attributes = Buffer.concat([
    Buffer.from("SN"), u16(2),
    u32(1), u32(0), u32(0),               // 12-byte header
    u16(2), u32(1), u32(2), u16(2),       // count, ids (1=health, 2=blood), second count
    ((): Buffer => { const b = Buffer.alloc(4); b.writeFloatLE(100); return b; })(),
    ((): Buffer => { const b = Buffer.alloc(4); b.writeFloatLE(80); return b; })(),
  ]);
  const inventory = Buffer.concat([Buffer.from("SN"), u16(3), inventoryRecord()]);
  const development = Buffer.concat([Buffer.from("SN"), u16(4), traitRecord()]);
  const facts = Buffer.concat([Buffer.from("SN"), u16(5), factsRecord()]);
  const records = Buffer.concat([root, clock, attributes, inventory, development, facts]);
  const nameBody = Buffer.concat(NAMES.map(name => Buffer.concat([u8(name.length), Buffer.from(name)])));
  const nameTable = Buffer.concat([Buffer.from("NAME"), u32(nameBody.length), nameBody, Buffer.from("NAME")]);
  const clockOffset = 36 + root.length;
  const attributesOffset = clockOffset + clock.length;
  const inventoryOffset = attributesOffset + attributes.length;
  const developmentOffset = inventoryOffset + inventory.length;
  const factsOffset = developmentOffset + development.length;
  const entries: [number, number, number, number, number][] = [
    [1, 65535, 1, 36, records.length],
    [2, 2, 65535, clockOffset, clock.length],
    [3, 3, 65535, attributesOffset, attributes.length],
    [4, 4, 65535, inventoryOffset, inventory.length],
    [5, 5, 65535, developmentOffset, development.length],
    [6, 65535, 65535, factsOffset, facts.length],
  ];
  const directory = Buffer.alloc(6 + entries.length * 16 + 4);
  directory.write("DWNT"); directory.writeUInt16LE(entries.length, 4);
  entries.forEach(([name, next, child, offset, size], i) => {
    const start = 6 + i * 16;
    directory.writeUInt32LE(name, start); directory.writeUInt16LE(next, start + 4); directory.writeUInt16LE(child, start + 6);
    directory.writeUInt32LE(offset, start + 8); directory.writeUInt32LE(size, start + 12);
  });
  directory.write("DWNT", directory.length - 4);
  const payload = Buffer.concat([records, nameTable, directory]);
  const header = Buffer.alloc(32);
  header.write("DSAV"); header.writeUInt32LE(36, 4); header.writeUInt16LE(134, 8); header.writeUInt16LE(5, 10); header.writeUInt32LE(2, 12);
  header.writeUInt32LE(36 + records.length, 16); header.writeUInt32LE(36 + records.length + nameTable.length, 20); header.writeUInt32LE(36 + payload.length, 24);
  const chunks = [{ encoded: Buffer.from(payload), decodedBytes: payload.length }];
  const bytes = encodeDsavContainer({ header, namesOffset: header.readUInt32LE(16), nodesOffset: header.readUInt32LE(20), payloadBytes: payload.length, chunks });
  const codec: DsavCodec = {
    decompress: async (input) => input.map(chunk => Buffer.from(chunk.encoded)),
    compress: async (input) => input.map(encoded => ({ encoded: Buffer.from(encoded), decodedBytes: encoded.length })),
  };
  return { bytes, codec };
}

async function document(): Promise<DsavDocument> {
  const { bytes, codec } = buildSave();
  return decodeDsav(bytes, codec);
}

// The save-editing entry points read the whole field model; use the editing pipeline
// directly for structural rewrites that planFieldEdits covers, and raw parses for the rest.
function nameIndexOf(document_: DsavDocument): (name: string) => number {
  const names = [...document_.names];
  return (name: string) => {
    const at = names.indexOf(name);
    if (at >= 0) return at + 1;
    names.push(name);
    return names.length;
  };
}

function rebuildWith(replaceName: string, record: Buffer, original: DsavDocument): DsavDocument {
  const names = [...original.names];
  const rebuilt = rebuildPayload(original, new Map([[replaceName, record]]), names);
  const container = { ...original.container, namesOffset: rebuilt.namesOffset, nodesOffset: rebuilt.nodesOffset, payloadBytes: rebuilt.payload.length };
  return parseDsavPayload(container, rebuilt.payload);
}

// ---------------------------------------------------------------------------

describe("facts document and infamy port", () => {
  it("parses the FactsDB record and reports the coupled court state", async () => {
    const doc = await document();
    const facts = readFactsDocument(doc)!;
    expect(readCourtState(facts.values)).toEqual({ points: 350, level: 3, pending: 1, activeEdicts: 2 });
  });

  it("changes an existing fact and refuses absent facts and court-owned tags", async () => {
    const doc = await document();
    const { next } = planFactChanges(doc, [{ tag: "Day.Night", value: 2, expectedValue: 1 }]);
    expect(next.get(tagId("Day.Night"))).toBe(2);
    expect(() => planFactChanges(doc, [{ tag: "Never.Seen", value: 1 }])).toThrow(/absent/);
    expect(() => planFactChanges(doc, [{ tag: INFAMY_POINTS_TAG, value: 0 }])).toThrow(/Infamy editor/);
  });

  it("raises infamy consistently across the court trio and honours the edict floor", async () => {
    const doc = await document();
    const config = courtConfig();
    const { next, changed } = planInfamyChangeOnValues(readFactsDocument(doc)!.values, 650, config);
    expect(changed).toBe(true);
    expect(readCourtState(next)).toEqual({ points: 650, level: 6, pending: 1 + 6 - 3, activeEdicts: 2 });
    const refused = planInfamyChangeOnValues(readFactsDocument(doc)!.values, 350, config);
    expect(refused.changed).toBe(false);
    expect(() => planInfamyChangeOnValues(readFactsDocument(doc)!.values, 50, config)).toThrow(/edicts are enacted/);
    expect(() => planInfamyChangeOnValues(readFactsDocument(doc)!.values, 650, "broken config")).toThrow(/CourtSettings/);
  });
});

describe("writable trait document: first-rank acquisition and book access", () => {
  it("round-trips the record byte for byte through parse and serialise", async () => {
    const doc = await document();
    const traits = readWritableTraitDocument(doc)!;
    const serialized = serializeTraitDocument(traits, nameIndexOf(doc));
    expect(serialized).toEqual(traitRecord());
  });

  it("acquires a first rank, preserving the loadout and raising the history row", async () => {
    const doc = await document();
    const traits = readWritableTraitDocument(doc)!;
    acquireRankPreservingLoadout(traits, "BloodRush", 1);
    expect(traits.dictionaries[0].get("BloodRush")).toBe(1);
    expect(traits.dictionaries[1].get("BloodRush")).toBe(1);
    expect(traits.dictionaries[0].get("VoraciousBite")).toBe(2);
    const after = readWritableTraitDocument(rebuildWith("CharacterDevelopmentSubsystem", serializeTraitDocument(traits, nameIndexOf(doc)), doc))!;
    expect(after.dictionaries[0].get("BloodRush")).toBe(1);
    expect(after.dictionaries[1].get("BloodRush")).toBe(1);
  });

  it("refuses ranks the save already holds or that exceed the supported band", async () => {
    const doc = await document();
    const traits = readWritableTraitDocument(doc)!;
    expect(() => acquireRankPreservingLoadout(traits, "VoraciousBite", 1)).toThrow(/above the current rank/);
    expect(() => acquireRankPreservingLoadout(traits, "BloodRush", 5)).toThrow(/supported rank/);
    expect(() => acquireRankPreservingLoadout(traits, "", 1)).toThrow(/supported rank/);
  });

  it("raises book access and never lowers it", async () => {
    const doc = await document();
    const traits = readWritableTraitDocument(doc)!;
    setBookAccess(traits, "VoraciousBite", 3);
    expect(traits.dictionaries[2].get("VoraciousBite")).toBe(3);
    expect(() => setBookAccess(traits, "VoraciousBite", 1)).toThrow(/cannot be lowered/);
    const after = readWritableTraitDocument(rebuildWith("CharacterDevelopmentSubsystem", serializeTraitDocument(traits, nameIndexOf(doc)), doc))!;
    expect(after.dictionaries[2].get("VoraciousBite")).toBe(3);
  });

  it("exposes the spent-point ledger", async () => {
    const doc = await document();
    const traits = readWritableTraitDocument(doc)!;
    expect(spentSkillPointsOf(traits)).toBe(5);
  });
});

describe("item level upgrade port", () => {
  it("maps the export rows into upgrade facts and refuses a wrong asset class", () => {
    expect(itemLevelDefinition({ Type: "ItemWeaponDataAsset", Class: "UScriptClass'ItemWeaponDataAsset'", Properties: { ItemId: "X" } })).toEqual({ hasItemLevel: true, upgradeSpread: 1 });
    expect(() => itemLevelDefinition({ Type: "ItemWeaponDataAsset", Class: "UScriptClass'Other'", Properties: { ItemId: "X" } })).toThrow(/asset class/);
    expect(() => readItemLevelCatalog("no" as unknown as readonly unknown[])).toThrow(/bounded/);
  });

  it("previews upgradeable stacks bounded by the mapped owner limit", async () => {
    const doc = await document();
    const inventory = readInventoryDocument(doc)!;
    const options = previewItemUpgrades(inventory, ITEM_LEVEL_CATALOG, 8);
    expect(options).toEqual([{ itemId: "SwordLongCommon2", handle: 0, currentLevel: 4, maximumLevel: 9, quantity: 1 }]);
    expect(previewItemUpgrades(inventory, ITEM_LEVEL_CATALOG, 49)).toEqual([{ itemId: "SwordLongCommon2", handle: 0, currentLevel: 4, maximumLevel: 50, quantity: 1 }]);
  });

  it("moves one unit to a new handle, repoints equipment and tracks the pair in the suffix", async () => {
    const doc = await document();
    const inventory = readInventoryDocument(doc)!;
    const newHandle = upgradeOnePlayerItem(inventory, { itemId: "SwordLongCommon2", targetLevel: 5, playerLevel: 8 }, ITEM_LEVEL_CATALOG);
    expect(newHandle).toBe(2);
    expect(inventory.handles).toEqual([{ type: 0, variant: 4 }, { type: 1, variant: 0 }, { type: 0, variant: 5 }]);
    expect(inventory.owners[0].stacks).toEqual([{ handle: 2, quantity: 1 }, { handle: 1, quantity: 3 }]);
    expect(inventory.owners[0].equipment[0][0]).toEqual({ key: 5, handle: 2 });
    const trackedCount = inventory.tail.readUInt16LE(8); // after the two initial lists and merchant count
    expect(trackedCount).toBe(1);
    expect(inventory.tail.readUInt32LE(10)).toBe(2); // tracked entry: the upgraded handle
    const serialized = serializeInventoryDocument(inventory, nameIndexOf(doc));
    const after = readInventoryDocument(rebuildWith("InventorySubsystem", serialized, doc))!;
    expect(after.handles).toEqual(inventory.handles);
    expect(after.owners[0].stacks).toEqual(inventory.owners[0].stacks);
    expect(after.owners[0].equipment[0][0].handle).toBe(2);
  });

  it("refuses upgrades DwSav refuses", async () => {
    const doc = await document();
    const inventory = readInventoryDocument(doc)!;
    expect(() => upgradeOnePlayerItem(inventory, { itemId: "Medicaments1", targetLevel: 1, playerLevel: 8 }, ITEM_LEVEL_CATALOG)).toThrow(/item-level support/);
    expect(() => upgradeOnePlayerItem(readInventoryDocument(doc)!, { itemId: "SwordLongCommon2", targetLevel: 4, playerLevel: 8 }, ITEM_LEVEL_CATALOG)).toThrow(/above 4/);
    expect(() => upgradeOnePlayerItem(readInventoryDocument(doc)!, { itemId: "SwordLongCommon2", targetLevel: 51, playerLevel: 8 }, ITEM_LEVEL_CATALOG)).toThrow(/mapped owner limit/);
    expect(() => upgradeOnePlayerItem(readInventoryDocument(doc)!, { itemId: "SwordLongCommon2", targetLevel: 5, playerLevel: 0 }, ITEM_LEVEL_CATALOG)).toThrow(/1-50 profile/);
  });
});

const ITEM_LEVEL_CATALOG = readItemLevelCatalog([
  { Type: "ItemWeaponDataAsset", Class: "UScriptClass'ItemWeaponDataAsset'", Properties: { ItemId: "SwordLongCommon2" } },
  { Type: "ItemWeaponDataAsset", Class: "UScriptClass'ItemWeaponDataAsset'", Properties: { ItemId: "SwordRare5", bOverrideUpgradeLevelSpread: true, UpgradeLevelSpread: 3 } },
]);
function courtConfig(): string {
  const edicts = Array.from({ length: 9 }, (_, index) => `+Edicts=(EdictFactTag=(TagName="Court.Edict${index}"),EdictFacts=)`);
  return [
    "[/Script/DogwoodQuest.CourtSettings]",
    "MaxAlertLevel=900",
    'AlertLevelTag=(TagName="Court.AlertLevel")',
    'AlertLevelsToHandleTag=(TagName="Court.AlertLevelsToHandle")',
    "AlertStagesThresholds=((High, 9),(Medium, 6),(Low, 3))",
    ...edicts,
  ].join("\n");
}

describe("game metadata loading", () => {
  const itemsRows = [
    { Type: "ItemWeaponDataAsset", Class: "UScriptClass'ItemWeaponDataAsset'", Properties: { ItemId: "SwordLongCommon2" } },
    pureBook("BloodRush"),
  ];
  const traitRows = [
    { Type: "TraitAsset", Class: "UScriptClass'TraitAsset'", Properties: { Skill_ID: "BloodRush", SkillTree: "ECharacterDevelopmentMode::Vampire", Levels: [{ bLocked: false, SkillPointsCost: 1 }] } },
    { Type: "TraitAsset", Class: "UScriptClass'TraitAsset'", Properties: { Skill_ID: "VoraciousBite", MaxTraitLevel: 2, SkillTree: "ECharacterDevelopmentMode::Vampire", Levels: [{ bLocked: true, SkillPointsCost: 1 }, { bLocked: false, SkillPointsCost: 2 }] } },
  ];

  it("reads item levels, book definitions and trait ITEM_LEVEL_CATALOG facts", () => {
    const itemLevels = readItemLevelCatalogFromExport(itemsRows);
    expect(itemLevels.get("SwordLongCommon2")).toEqual({ hasItemLevel: true, upgradeSpread: 1 });
    const books = loadBooks(traitRows, itemsRows);
    expect(books.get("BloodRush")).toEqual({ traitId: "BloodRush", locked: [false], quest: false, pureBook: true });
    const traits = readTraitCatalog(traitRows);
    expect(traits.get("BloodRush")!.tree).toBe("Vampire");
    expect(traits.get("VoraciousBite")!.requiredAccess).toBe(1);
  });

  it("accepts the verified config profile and rejects a different game", () => {
    const config = [
      "[/Script/EngineSettings.GeneralProjectSettings]",
      "ProjectID=95BA50734B3F6EE6FBA1129EFCD1EC41",
      "ProjectName=Dawnwalker",
      "ProjectVersion=1.0.16.0",
      "[/Script/DogwoodInventory.DogwoodInventorySettings]",
      "ItemUpgradeLevelSpread=1",
      "[/Script/DogwoodCharacterDevelopment.DogwoodCharacterDevelopmentSettings]",
      "LevelCap=50",
    ].join("\n");
    expect(() => validateUpgradeConfig(config)).not.toThrow();
    expect(() => validateUpgradeConfig(config.replace("Dawnwalker", "Other"))).toThrow(/does not match Dawnwalker/);
    expect(() => validateUpgradeConfig(config.replace("1.0.16.0", "9.9.9.9"))).toThrow(/ProjectVersion/);
  });

  it("loads metadata from resolved export paths and reports problems instead of throwing", async () => {
    const ok = await loadSaveEditorMetadata({ itemsJson: null, traitsJson: null, defaultGameIni: null });
    expect(ok.itemLevels).toBeUndefined();
    expect(ok.unavailableReason).toBeUndefined();
  });
});

// Imported separately to keep the direct gameMetadata import list honest.
import { readBookCatalog } from "../electron/gameMetadata";
function loadBooks(traitRows: readonly unknown[], itemRows: readonly unknown[]) {
  return readBookCatalog(traitRows, itemRows);
}

describe("integrated edit pipeline over the synthetic save", () => {
  it("rejects upgrading a stack and rewriting its quantity in one transaction", async () => {
    const { bytes, codec } = buildSave();
    await expect(encodeEditedSave(bytes, {
      itemUpgrades: [{ itemId: "SwordLongCommon2", handle: 0, targetLevel: 5 }],
      stacks: [{ itemIndex: 0, value: 3 }], itemLevels: ITEM_LEVEL_CATALOG, gameConfig: upgradeConfig(),
    }, codec)).rejects.toThrow(/Apply inventory and character-level changes separately/);
  });

  it("rejects upgrading alongside inventory mutations or an owner-level change", async () => {
    const save = await document();
    const upgrade = { itemUpgrades: [{ itemId: "SwordLongCommon2", handle: 0, targetLevel: 5 }], itemLevels: ITEM_LEVEL_CATALOG, gameConfig: upgradeConfig() };
    for (const mixed of [
      { inventory: { remove: [{ itemIndex: 0 }] } },
      { inventory: { add: [{ itemId: "SwordLongCommon2", quantity: 3 }] } },
      { replaceItems: [{ itemIndex: 0, definitionIndex: 1 }] },
      { giveItems: [{ definitionIndex: 1, value: 1 }] },
      { level: 1 },
    ]) expect(() => planFieldEdits(save, { ...upgrade, ...mixed })).toThrow(/Apply inventory and character-level changes separately/);
  });

  it("rejects acquisition alongside prerequisite changes while preserving unrelated fact edits", async () => {
    const { bytes, codec } = buildSave();
    const acquisition = { perkAcquisitions: [{ id: "Vampire_BloodRush", rank: 1 }], traits: readTraitCatalog([canonicalTrait("Vampire_BloodRush", [{ SPToAccess: 5 }])]) };
    for (const mixed of [{ spentSkillPoints: 0 }, { mutationLevel: 0 }, { attributeValues: [{ id: 8, value: 0 }] }]) {
      await expect(encodeEditedSave(bytes, { ...acquisition, ...mixed }, codec)).rejects.toThrow(/Apply perk prerequisite changes separately/);
    }
    const result = await encodeEditedSave(bytes, { ...acquisition, factChanges: [{ tag: "Day.Night", value: 0 }] }, codec);
    const after = await decodeDsav(result.encoded, codec);
    expect(readFactsDocument(after)!.values.get(tagId("Day.Night"))).toBe(0);
    expect(readSaveFields(after).traits.find(trait => trait.id === "Vampire_BloodRush")?.rank).toBe(1);
  });

  it("uses only the target prefix and SPToAccess instead of the skill-point purchase cost", async () => {
    const save = await document();
    const traits = readTraitCatalog([canonicalTrait("Vampire_BloodRush", [{ SkillPointsCost: 20, SPToAccess: 0 }, { SPToAccess: 6, MutationToUnlock: 15, bLocked: true }])]);
    expect(() => planFieldEdits(save, { traits, perkAcquisitions: [{ id: "Vampire_BloodRush", rank: 1 }] })).not.toThrow();
    expect(() => planFieldEdits(save, { traits, perkAcquisitions: [{ id: "Vampire_BloodRush", rank: 2 }] })).toThrow(/6 spent skill points/);
  });

  it("persists acquired perk tags and preserves other facts through DSAV encode/decode", async () => {
    const { bytes, codec } = buildSave();
    const traits = readTraitCatalog([canonicalTrait("Vampire_BloodRush", [{ AddedTags: ["CharDev.Test.BloodRush"] }])]);
    const before = await decodeDsav(bytes, codec);
    const { encoded } = await encodeEditedSave(bytes, { traits, perkAcquisitions: [{ id: "Vampire_BloodRush", rank: 1 }] }, codec);
    const after = await decodeDsav(encoded, codec);
    const expected = new Map(readFactsDocument(before)!.values);
    expected.set(tagId("CharDev.Test.BloodRush"), 1);
    expect(readFactsDocument(after)!.values).toEqual(expected);
    expect(readSaveFields(after).skillPoints).toBe(readSaveFields(before).skillPoints);
    expect(readSaveFields(after).spentSkillPoints).toBe(readSaveFields(before).spentSkillPoints);
    expect(readSaveFields(after).clockMs).toBe(readSaveFields(before).clockMs);
  });

  it("refuses tag conflicts and replacement transitions that would remove persistent tags", async () => {
    const save = await document();
    const traits = readTraitCatalog([canonicalTrait("Vampire_BloodRush", [{ AddedTags: ["CharDev.Test.BloodRush"] }, { ReplacesLevel: [1] }])]);
    expect(() => planFieldEdits(save, { traits, perkAcquisitions: [{ id: "Vampire_BloodRush", rank: 1 }], factChanges: [{ tag: "CharDev.Test.BloodRush", value: 0 }] })).toThrow(/conflicts/);
    expect(() => acquisitionProfile("Vampire_BloodRush", 2, traits)).toThrow(/separate transition/);
  });

  it("refuses unsupported history, secondary state, loadout and malformed effects", async () => {
    const save = await document();
    const id = "Vampire_BloodRush";
    const traits = readTraitCatalog([canonicalTrait(id)]);
    for (const section of [1, 3, 4]) {
      const stored = readWritableTraitDocument(save)!;
      stored.dictionaries[section].set(id, 1);
      expect(() => validatePerkAcquisition(save, id, 1, traits, stored)).toThrow(/history, secondary/);
    }
    const equipped = readWritableTraitDocument(save)!;
    equipped.abilityNames.push(id);
    expect(() => validatePerkAcquisition(save, id, 1, traits, equipped)).toThrow(/history, secondary/);
    const malformed = readTraitCatalog([canonicalTrait(id, [{ LevelEffect: {} }])]);
    expect(() => validatePerkAcquisition(save, id, 1, malformed)).toThrow(/canonical rank effect/);
  });

  it("rejects arbitrary, nonlocked and quest book ranks at the encode boundary", async () => {
    const { bytes, codec } = buildSave();
    const row = canonicalTrait("VoraciousBite", [{ bLocked: false }, { bLocked: true }]);
    const books = readBookCatalog([row], [pureBook("VoraciousBite")]);
    for (const request of [{ id: "Unknown", accessLevel: 1 }, { id: "VoraciousBite", accessLevel: 1 }, { id: "VoraciousBite", accessLevel: 3 }]) {
      await expect(encodeEditedSave(bytes, { books, bookAccess: [request] }, codec)).rejects.toThrow(/pure-book-locked/);
    }
    const questBooks = readBookCatalog([{ ...row, Properties: { ...row.Properties, UnlockWithQuest: true } }], [pureBook("VoraciousBite")]);
    await expect(encodeEditedSave(bytes, { books: questBooks, bookAccess: [{ id: "VoraciousBite", accessLevel: 2 }] }, codec)).rejects.toThrow(/pure-book-locked/);
  });

  it("rejects duplicate and impure book mappings", () => {
    const rows = [canonicalTrait()];
    const book = pureBook("Vampire_BloodRush");
    expect(() => readBookCatalog(rows, [book, { ...book, Properties: { ...book.Properties, ItemId: "AnotherBook" } }])).toThrow(/ambiguous/);
    const impure = { ...book, Properties: { ...book.Properties, TraitPointsAmount: 1 } };
    expect(readBookCatalog(rows, [impure]).get("Vampire_BloodRush")?.pureBook).toBe(false);
  });

  it("enforces ultimate exclusivity and gameplay-ability aliases", async () => {
    const save = await document();
    const ultimate = canonicalTrait("Human_FinalSkill");
    const otherUltimate = canonicalTrait("Human_OtherFinalSkill");
    const catalog = readTraitCatalog([ultimate, otherUltimate].map(row => ({ ...row, Properties: { ...row.Properties, Tier: 4 } })));
    const stored = readWritableTraitDocument(save)!;
    stored.dictionaries[0].clear();
    expect(() => validatePerkAcquisition(save, "Human_FinalSkill", 1, catalog, stored)).not.toThrow();
    stored.dictionaries[0].set("Human_OtherFinalSkill", 1);
    expect(() => validatePerkAcquisition(save, "Human_FinalSkill", 1, catalog, stored)).toThrow(/already has an acquired ultimate/);
    const abilityRows = ["CombatFocus_Test", "CombatFocus_Alias"].map(id => {
      const row = canonicalTrait(id, [{}, {}, {}, {}]);
      return { ...row, Properties: { ...row.Properties, SkillType: "ECharacterDevelopmentAbilityType::Combat", DisplayedWorkingPhase: "ETraitWorkingPhase::Shared", CombatFocusAbility: { ObjectPath: "/Game/_Dawnwalker/Combat/Focus/Sword/Test/GA_Test.0", ObjectName: "BlueprintGeneratedClass'GA_Test_C'" } } };
    });
    const abilities = readTraitCatalog(abilityRows);
    stored.dictionaries[0].clear();
    stored.dictionaries[0].set("CombatFocus_Alias", 1);
    expect(() => validatePerkAcquisition(save, "CombatFocus_Test", 1, abilities, stored)).toThrow(/same gameplay ability/);
  });

  it("rejects malformed override flags and duplicate upgrade configuration values", () => {
    expect(() => itemLevelDefinition({ Type: "ItemWeaponDataAsset", Class: "UScriptClass'ItemWeaponDataAsset'", Properties: { ItemId: "Sword", bOverrideUpgradeLevelSpread: "false" } })).toThrow(/Malformed/);
    expect(() => validateUpgradeConfig(upgradeConfig().replace("LevelCap=50", "LevelCap=90\nLevelCap=50"))).toThrow(/Duplicate/);
  });

  it("selects one explicit handle when an item has multiple level variants", async () => {
    const inventory = readInventoryDocument(await document())!;
    inventory.handles.push({ type: 0, variant: 3 });
    inventory.owners[0].stacks.push({ handle: 2, quantity: 2 });
    expect(previewItemUpgrades(inventory, ITEM_LEVEL_CATALOG, 8)).toHaveLength(2);
    expect(() => upgradeOnePlayerItem(inventory, { itemId: "SwordLongCommon2", targetLevel: 5, playerLevel: 8 }, ITEM_LEVEL_CATALOG)).toThrow(/unambiguous/);
    const result = upgradeOnePlayerItem(inventory, { itemId: "SwordLongCommon2", handle: 2, targetLevel: 5, playerLevel: 8 }, ITEM_LEVEL_CATALOG);
    expect(inventory.handles[result].variant).toBe(5);
    expect(inventory.owners[0].stacks.find(stack => stack.handle === 0)?.quantity).toBe(1);
    expect(inventory.owners[0].stacks.find(stack => stack.handle === 2)?.quantity).toBe(1);
  });

  it("verifies the upgraded variant while a lower-level stack remains owned", async () => {
    const { codec } = buildSave();
    const original = await document();
    const inventory = readInventoryDocument(original)!;
    inventory.owners[0].stacks[0].quantity = 2;
    const stacked = rebuildWith("InventorySubsystem", serializeInventoryDocument(inventory, nameIndexOf(original)), original);
    const bytes = encodeDsavContainer({ ...stacked.container, chunks: [{ encoded: stacked.payload, decodedBytes: stacked.payload.length }] });
    const edit = validateFieldEdit({ itemUpgrades: [{ itemId: "SwordLongCommon2", handle: 0, targetLevel: 5 }] });
    expect(edit.itemUpgrades?.[0].handle).toBe(0);
    const { encoded } = await encodeEditedSave(bytes, { ...edit, itemLevels: ITEM_LEVEL_CATALOG, gameConfig: upgradeConfig() }, codec);
    const after = readInventoryDocument(await decodeDsav(encoded, codec))!;
    const variants = after.owners[0].stacks.filter(stack => stack.quantity > 0 && after.handles[stack.handle].type === 0).map(stack => [after.handles[stack.handle].variant, stack.quantity]);
    expect(variants).toEqual([[4, 1], [5, 1]]);
  });
  it("refuses book access without a mapped pure book", async () => {
    const save = await document();
    expect(() => planFieldEdits(save, { bookAccess: [{ id: "VoraciousBite", accessLevel: 2 }] })).toThrow(/book metadata/);
  });

  it("refuses item upgrades when the game configuration is absent", async () => {
    const save = await document();
    expect(() => planFieldEdits(save, { itemUpgrades: [{ itemId: "SwordLongCommon2", targetLevel: 5 }], itemLevels: ITEM_LEVEL_CATALOG })).toThrow(/configuration/);
  });
  it("plans and encodes a first-rank acquisition end to end", async () => {
    const { bytes, codec } = buildSave();
    const edit = validateFieldEdit({ perkAcquisitions: [{ id: "Vampire_BloodRush", rank: 1 }] });
    const resolved = { ...edit, traits: readTraitCatalog([canonicalTrait()]) };
    const { encoded, verification } = await encodeEditedSave(bytes, resolved, codec);
    expect(verification.changedFields).toContain("perkAcquisition:Vampire_BloodRush");
    const after = await decodeDsav(encoded, codec);
    const trait = readSaveFields(after).traits.find(entry => entry.id === "Vampire_BloodRush");
    expect(trait?.rank).toBe(1);
    expect(trait?.highestRank).toBe(1);
  });

  it("plans and encodes a book access raise end to end", async () => {
    const { bytes, codec } = buildSave();
    const edit = validateFieldEdit({ bookAccess: [{ id: "VoraciousBite", accessLevel: 2 }] });
    const books = readBookCatalog([canonicalTrait("VoraciousBite", [{ bLocked: true }, { bLocked: true }])], [pureBook("VoraciousBite")]);
    const { encoded, verification } = await encodeEditedSave(bytes, { ...edit, books }, codec);
    expect(verification.changedFields).toContain("bookAccess:VoraciousBite");
    const after = await decodeDsav(encoded, codec);
    const trait = readSaveFields(after).traits.find(entry => entry.id === "VoraciousBite");
    expect(trait?.accessLimit).toBe(2);
  });

  it("plans and encodes a fact change and the infamy editor end to end", async () => {
    const { bytes, codec } = buildSave();
    const edit = validateFieldEdit({ factChanges: [{ tag: "Day.Night", value: 0, expectedValue: 1 }], infamyPoints: 700 });
    const { encoded, verification } = await encodeEditedSave(bytes, { ...edit, gameConfig: courtConfig() }, codec);
    expect(verification.changedFields).toContain("fact:Day.Night");
    expect(verification.changedFields).toContain("infamyPoints");
    const after = await decodeDsav(encoded, codec);
    const facts = readFactsDocument(after)!;
    expect(facts.values.get(tagId("Day.Night"))).toBe(0);
    expect(readCourtState(facts.values).points).toBe(700);
    expect(readCourtState(facts.values).level).toBe(7);
  });

  it("plans and encodes an item upgrade end to end", async () => {
    const { bytes, codec } = buildSave();
    const edit = validateFieldEdit({ itemUpgrades: [{ itemId: "SwordLongCommon2", targetLevel: 5 }] });
    const resolved = { ...edit, itemLevels: ITEM_LEVEL_CATALOG, gameConfig: upgradeConfig() };
    const { encoded, verification } = await encodeEditedSave(bytes, resolved, codec);
    expect(verification.changedFields.some(field => field.startsWith("itemUpgrade:SwordLongCommon2"))).toBe(true);
    const after = await decodeDsav(encoded, codec);
    const walk = walkInventory(after);
    expect(walk.stacks.filter(stack => stack.name === "SwordLongCommon2").length).toBe(1);
    const inventory = readInventoryDocument(after)!;
    const type = inventory.types.indexOf("SwordLongCommon2");
    const upgraded = inventory.owners[0].stacks.find(stack => stack.quantity > 0 && inventory.handles[stack.handle]?.type === type);
    expect(upgraded && inventory.handles[upgraded.handle].variant).toBe(5);
  });
});
