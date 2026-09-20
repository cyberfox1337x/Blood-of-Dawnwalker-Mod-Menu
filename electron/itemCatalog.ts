import { ITEM_CATALOG_RECORDS, type ItemCatalogRecord } from "./itemCatalogData.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_item_catalog");

/** What the editor shows for an item id: the game's display name and DwSav's category. */
export type ItemDescription = Readonly<{
  /** Localized name when the catalog knows one, else the id spelled out ("Chest Common 8b"). */
  name: string;
  category: string;
  rarity?: string;
  /** Quest, key, currency and story items the catalog advises against handing out. */
  sensitive: boolean;
  /** False when the id is not in the bundled catalog (name is then derived from the id). */
  catalogued: boolean;
}>;

// The category list DwSav's inventory filter offers, in its order.
export const ITEM_CATEGORIES = Object.freeze([
  "Currency", "Materials", "Consumables", "Weapons", "Clothing", "Recipes", "Manuals", "Documents", "Valuables", "Quest items", "Other",
] as const);

const byId: ReadonlyMap<string, ItemCatalogRecord> = new Map(ITEM_CATALOG_RECORDS.map(record => [record.id, record]));

// DwSav's ItemLabel.Format: split camel case and digit runs so an unknown id still reads.
function spellOutId(id: string): string {
  return id.replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2").replace(/([a-zA-Z])([0-9])/g, "$1 $2");
}

// DwSav's ItemLabel.Category: id-prefix heuristics for ids the catalog does not list.
function categoryFromId(id: string): string {
  if (id === "Coin") return "Currency";
  if (id.startsWith("Recipe")) return "Recipes";
  if (id.startsWith("SKB")) return "Manuals";
  if (/^(Sword|Axe|Mace|Dagger|Bow|Weapon)/.test(id)) return "Weapons";
  if (/^(Chest|Legs|Feet|Head|Gloves)/.test(id)) return "Clothing";
  if (/^(Medicaments|Food|Meal|Fruits)/.test(id)) return "Consumables";
  if (/^(Herbs|Bases|Spool|Leather|Ore|Wood|Iron)/.test(id)) return "Materials";
  if (/^(Q[0-9]|SQ[0-9]|NPOI|POI|OA[0-9]|OB[0-9]|OX[0-9])/.test(id)) return "Quest items";
  return "Other";
}

export function describeItem(id: string): ItemDescription {
  const record = byId.get(id);
  if (record) return { name: record.name, category: record.category, rarity: record.rarity, sensitive: record.sensitive === true, catalogued: true };
  return { name: spellOutId(id), category: categoryFromId(id), sensitive: false, catalogued: false };
}
