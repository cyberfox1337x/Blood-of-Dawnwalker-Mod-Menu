import { existsSync, readdirSync, statSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_game_assets");

// Item and perk icons are the game's own textures, exported locally by the owner's
// DwSav asset importer (dwsav-assets.exe <game> <mapping.usmap> <output>) into
// <output>/icons/<ItemId or Skill_ID>.png next to perks.json / quests.json. Nothing is
// bundled with the menu: this module only finds such an export and serves from it.
export const ASSET_SCHEME = "dw-asset";
export const ICON_FILE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.\- ]{0,120}$/;

export type GameAssetStatus = Readonly<{
  /** Folder the icons are served from, or null when no export has been found. */
  directory: string | null;
  iconCount: number;
  hasPerkMetadata: boolean;
  /** Where the menu looks first; shown to the user so they know where to export. */
  preferredDirectory: string;
}>;

/** One perk as the asset importer describes it in perks.json (English text). */
export type PerkMetadata = Readonly<{
  id: string; name: string; description: string; tree: string; quest: boolean; parents: readonly string[];
  rankDescriptions: readonly string[]; iconStatus: string;
}>;

export type GameAssetStore = Readonly<{
  /** Absolute path of an icon, or null when the id is unsafe or the file is absent. */
  iconPath(id: string): string | null;
  status(): Promise<GameAssetStatus>;
  metadataPath(name: "perks.json" | "quests.json" | "items.json" | "traits.json" | "DefaultGame.ini" | "FactTags.ini"): string | null;
  /** Perk names, trees and descriptions from the export; empty when there is none. */
  perks(): Promise<readonly PerkMetadata[]>;
}>;

const MAX_METADATA_BYTES = 16 * 1024 * 1024;

function asString(value: unknown): string { return typeof value === "string" ? value : ""; }
function asStrings(value: unknown): readonly string[] { return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : []; }

// perks.json is written by the importer as an array of { Id, Name, Description, Tree,
// Quest, Parents, RankDescriptions, ... }; anything malformed is skipped, not guessed.
export function parsePerkMetadata(text: string): readonly PerkMetadata[] {
  const parsed: unknown = JSON.parse(text);
  if (!Array.isArray(parsed)) throw new Error("perks.json does not hold a list of perks.");
  const perks: PerkMetadata[] = [];
  for (const entry of parsed) {
    if (typeof entry !== "object" || entry === null) continue;
    const record = entry as Record<string, unknown>;
    const id = asString(record.Id);
    if (!id) continue;
    const rankDescriptions = Array.isArray(record.RankDescriptions)
      ? record.RankDescriptions.map(rank => typeof rank === "string" ? rank : typeof rank === "object" && rank !== null ? asString((rank as Record<string, unknown>).Description ?? (rank as Record<string, unknown>).Text) : "")
      : [];
    perks.push({ id, name: asString(record.Name) || id, description: asString(record.Description), tree: asString(record.Tree) || "Unknown", quest: record.Quest === true, parents: asStrings(record.Parents), rankDescriptions, iconStatus: asString(record.IconStatus) });
  }
  return perks;
}

function newestDwSavCache(localAppData: string | undefined): string | null {
  if (!localAppData) return null;
  const root = join(localAppData, "dwsav", "game-assets");
  if (!existsSync(root)) return null;
  let newest: { path: string; modified: number } | undefined;
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith("cache-")) continue;
    const candidate = join(root, entry.name);
    if (!existsSync(join(candidate, "icons"))) continue;
    const modified = statSync(candidate).mtimeMs;
    if (!newest || modified > newest.modified) newest = { path: candidate, modified };
  }
  return newest?.path ?? null;
}

export function createGameAssetStore(options: Readonly<{ userDataPath: string; localAppDataPath?: string }>): GameAssetStore {
  const preferredDirectory = join(options.userDataPath, "game-assets");
  // Resolved on every call so an export finished while the menu is open is picked up.
  const exportRoot = (): string | null => {
    if (existsSync(join(preferredDirectory, "icons"))) return preferredDirectory;
    return newestDwSavCache(options.localAppDataPath);
  };
  const metadataPath = (name: "perks.json" | "quests.json" | "items.json" | "traits.json" | "DefaultGame.ini" | "FactTags.ini"): string | null => {
    const root = exportRoot();
    if (!root) return null;
    const path = join(root, name);
    return existsSync(path) ? path : null;
  };
  return Object.freeze({
    metadataPath,
    iconPath(id: string) {
      if (!ICON_FILE_PATTERN.test(id) || id.includes("..")) return null;
      const root = exportRoot();
      if (!root) return null;
      const path = join(root, "icons", `${id}.png`);
      return existsSync(path) ? path : null;
    },
    async perks() {
      const path = metadataPath("perks.json");
      if (!path) return [];
      if (statSync(path).size > MAX_METADATA_BYTES) throw new Error("perks.json exceeds 16 MB.");
      return parsePerkMetadata(await readFile(path, "utf-8"));
    },
    async status() {
      const root = exportRoot();
      if (!root) return { directory: null, iconCount: 0, hasPerkMetadata: false, preferredDirectory };
      const icons = await readdir(join(root, "icons"));
      return {
        directory: root,
        iconCount: icons.filter(name => name.toLowerCase().endsWith(".png")).length,
        hasPerkMetadata: existsSync(join(root, "perks.json")),
        preferredDirectory,
      };
    },
  });
}
