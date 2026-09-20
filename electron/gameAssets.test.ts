import { describe, expect, it } from "vitest";
import { parsePerkMetadata } from "./gameAssets.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_game_assets_tests");

describe("perk asset metadata", () => {
  it("preserves the importer's explicit icon provenance and internal classification", () => {
    const perks = parsePerkMetadata(JSON.stringify([
      { Id: "Shared_Vitality", Name: "Vigour", Tree: "Shared", IconStatus: "Original game icon", RankDescriptions: [] },
      { Id: "CombatFocus_Internal", Name: "", Tree: "CombatFocus", IconStatus: "Internal definition: no localized name or verified icon association", RankDescriptions: [] },
    ]));
    expect(perks).toEqual([
      expect.objectContaining({ id: "Shared_Vitality", name: "Vigour", iconStatus: "Original game icon" }),
      expect.objectContaining({ id: "CombatFocus_Internal", name: "CombatFocus_Internal", iconStatus: "Internal definition: no localized name or verified icon association" }),
    ]);
  });
});
