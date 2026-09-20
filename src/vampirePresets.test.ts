import { describe, expect, it } from "vitest";
import { VAMPIRE_PRESETS, presetEditsFor } from "./vampirePresets";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("vampire_presets_tests");

describe("vampire presets", () => {
  it("exposes the four documented presets with bounded mutation levels", () => {
    expect(VAMPIRE_PRESETS.map(preset => preset.id)).toEqual(["early-hunger", "prime-vampire", "apex-night", "clear-vampirism"]);
    for (const preset of VAMPIRE_PRESETS) {
      expect(preset.name.length).toBeGreaterThan(0);
      expect(preset.description.length).toBeGreaterThan(0);
      if (preset.edit.mutationLevel !== undefined) {
        expect(preset.edit.mutationLevel).toBeGreaterThanOrEqual(0);
        expect(preset.edit.mutationLevel).toBeLessThanOrEqual(15);
        expect(Number.isInteger(preset.edit.mutationLevel)).toBe(true);
      }
      if (preset.edit.health !== undefined) expect(preset.edit.health).toBeGreaterThan(0);
      if (preset.edit.blood !== undefined) expect(preset.edit.blood).toBeGreaterThan(0);
    }
  });

  it("keeps every preset inside the backend's validation bounds", () => {
    for (const preset of VAMPIRE_PRESETS) {
      if (preset.edit.health !== undefined) expect(preset.edit.health).toBeLessThanOrEqual(100_000);
      if (preset.edit.blood !== undefined) expect(preset.edit.blood).toBeLessThanOrEqual(100_000);
    }
  });

  it("prunes values the save already matches", () => {
    const preset = VAMPIRE_PRESETS.find(candidate => candidate.id === "prime-vampire")!;
    const edit = presetEditsFor(preset, { health: 200, blood: 300, mutationLevel: 8 });
    expect(edit).toEqual({});
  });

  it("keeps only the differing parts of a partially matching save", () => {
    const preset = VAMPIRE_PRESETS.find(candidate => candidate.id === "prime-vampire")!;
    const edit = presetEditsFor(preset, { health: 220, blood: 300, mutationLevel: 8 });
    expect(edit).toEqual({ health: 200 });
  });

  it("omits Blood when the save has no Blood stack", () => {
    const preset = VAMPIRE_PRESETS.find(candidate => candidate.id === "prime-vampire")!;
    const edit = presetEditsFor(preset, { health: 100, mutationLevel: 0 });
    expect(edit.blood).toBeUndefined();
    expect(edit.health).toBe(200);
    expect(edit.mutationLevel).toBe(8);
  });

  it("produces an empty edit for a save already in the clear-vampirism state", () => {
    const preset = VAMPIRE_PRESETS.find(candidate => candidate.id === "clear-vampirism")!;
    const edit = presetEditsFor(preset, { health: 100, mutationLevel: 0, blood: 0 });
    expect(edit).toEqual({});
  });

  it("never emits fields outside mutationLevel/health/blood", () => {
    for (const preset of VAMPIRE_PRESETS) {
      const edit = presetEditsFor(preset, {});
      for (const key of Object.keys(edit)) expect(["mutationLevel", "health", "blood"]).toContain(key);
    }
  });
});
