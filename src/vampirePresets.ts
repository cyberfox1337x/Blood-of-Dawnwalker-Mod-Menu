import type { SaveFieldEdit } from "../electron/saveEditing";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_vampire_presets");

// Preset bundles for the Save Editor's vampire section. Values are written
// through the ordinary verified edit pipeline (Health/Blood via
// AttributeSaveSystem ids 1 and 2, mutation level via id 8) and never touch
// any other attribute — the same narrow contract the reference editor's
// set_vitals follows ("leave every other attribute untouched").
//
// HONESTY NOTE: every preset is UNVERIFIED IN GAME. The bytes are proven by
// the pipeline's post-write decode; whether the game's vampire systems accept
// the resulting state can only be confirmed by loading the save in Dawnwalker.
export type VampirePresetId = "early-hunger" | "prime-vampire" | "apex-night" | "clear-vampirism";

export type VampirePreset = Readonly<{
  id: VampirePresetId;
  name: string;
  description: string;
  edit: Readonly<{ health?: number; blood?: number; mutationLevel?: number }>;
}>;

export const VAMPIRE_PRESETS: readonly VampirePreset[] = Object.freeze([
  {
    id: "early-hunger",
    name: "Freshly turned",
    description: "Mutation level 1, full Health, moderate Blood. The first restless nights.",
    edit: { mutationLevel: 1, health: 100, blood: 100 },
  },
  {
    id: "prime-vampire",
    name: "Prime vampire",
    description: "Mutation level 8, full Health, full Blood. A predator in its prime.",
    edit: { mutationLevel: 8, health: 200, blood: 300 },
  },
  {
    id: "apex-night",
    name: "Apex of the night",
    description: "Mutation level 15, high Health, deep Blood reserves. The apex of the curse.",
    edit: { mutationLevel: 15, health: 500, blood: 500 },
  },
  {
    id: "clear-vampirism",
    name: "Shed the curse",
    description: "Mutation level 0 with restored Health. Attempts to return the character to a human state.",
    edit: { mutationLevel: 0, health: 100 },
  },
]);

export type SaveVitalsSnapshot = Readonly<{
  health?: number;
  blood?: number;
  mutationLevel?: number;
}>;

// Drops every part of a preset whose target value already matches the save, so
// the pipeline's "no listed edit changes this save" guard never fires for a
// preset the save already satisfies. Empty result = already exactly this state.
export function presetEditsFor(
  preset: VampirePreset,
  vitals: SaveVitalsSnapshot,
): SaveFieldEdit {
  const edit: { health?: number; blood?: number; mutationLevel?: number } = {};
  if (preset.edit.mutationLevel !== undefined && vitals.mutationLevel !== preset.edit.mutationLevel) {
    edit.mutationLevel = preset.edit.mutationLevel;
  }
  if (preset.edit.health !== undefined && vitals.health !== preset.edit.health) {
    edit.health = preset.edit.health;
  }
  if (preset.edit.blood !== undefined && vitals.blood !== undefined && vitals.blood !== preset.edit.blood) {
    edit.blood = preset.edit.blood;
  }
  return edit;
}
