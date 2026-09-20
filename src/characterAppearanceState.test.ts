import { describe, expect, it } from "vitest";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
import {
  NATURAL_CHARACTER_APPEARANCE,
  characterAppearanceReducer,
  createCharacterAppearanceState,
  parseConfirmedCharacterAppearance,
  selectDisplayedCharacterAppearance,
} from "./characterAppearanceState";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_appearance_state_tests");

function snapshot(sessionId = "appearance-session"): ImportedMenuSnapshot {
  return { schema: 1, sessionId, revision: 7, ready: true, sections: [
    { id: "DWEyeColor", title: "Eyes", items: [
      { id: "color", type: "input", value: "#20F6FF" },
      { id: "glow", type: "number", value: 2.2 },
      { id: "owned", type: "checkbox", value: true },
    ] },
    { id: "DWHairColor", title: "Hair", items: [
      { id: "color", type: "input", value: "#8A3B1E" },
      { id: "brows", type: "input", value: "#6B3FA0" },
      { id: "owned", type: "checkbox", value: true },
    ] },
    { id: "DWSkinTint", title: "Skin", items: [
      { id: "tint", type: "input", value: "65,45,35" },
      { id: "owned", type: "checkbox", value: true },
    ] },
  ] };
}

describe("character appearance state", () => {
  it("strictly parses confirmed eye, hair, eyebrow and skin values", () => {
    expect(parseConfirmedCharacterAppearance(snapshot())).toEqual({
      eyeColor: "#20f6ff", eyeGlow: 2.2, hairColor: "#8a3b1e", eyebrowColor: "#6b3fa0", skinTint: [65, 45, 35],
    });
    const malformed = snapshot();
    malformed.sections[0].items[0].value = "red";
    malformed.sections[0].items[1].value = 9;
    malformed.sections[1].items[0].value = "#12345";
    malformed.sections[2].items[0].value = "101,50,50";
    expect(parseConfirmedCharacterAppearance(malformed)).toEqual({
      ...NATURAL_CHARACTER_APPEARANCE,
      eyebrowColor: "#6b3fa0",
    });
  });

  it("keeps independently confirmed hair when eyebrows remain original", () => {
    const hairOnly = snapshot();
    hairOnly.sections[1].items.find(item => item.id === "brows")!.value = "";
    expect(parseConfirmedCharacterAppearance(hairOnly).hairColor).toBe("#8a3b1e");
    expect(parseConfirmedCharacterAppearance(hairOnly).eyebrowColor).toBeNull();
  });

  it("shows optimistic changes immediately, reconciles confirmations, and rolls failures back", () => {
    let state = createCharacterAppearanceState(snapshot());
    state = characterAppearanceReducer(state, { type: "preview", change: { hairColor: "#c9a35a" } });
    expect(selectDisplayedCharacterAppearance(state).hairColor).toBe("#c9a35a");
    const confirmed = snapshot();
    confirmed.sections[1].items[0].value = "#c9a35a";
    state = characterAppearanceReducer(state, { type: "snapshot", snapshot: confirmed });
    expect(state.optimistic.hairColor).toBeUndefined();
    state = characterAppearanceReducer(state, { type: "preview", change: { eyebrowColor: "#1f7a7a" } });
    state = characterAppearanceReducer(state, { type: "failure" });
    expect(selectDisplayedCharacterAppearance(state).eyebrowColor).toBe("#6b3fa0");
  });

  it("settles a completed native operation to its authoritative readback", () => {
    let state = createCharacterAppearanceState(snapshot());
    state = characterAppearanceReducer(state, { type: "preview", change: { skinTint: [99, 10, 10] } });
    state = characterAppearanceReducer(state, { type: "settled", snapshot: snapshot() });
    expect(state.optimistic).toEqual({});
    expect(selectDisplayedCharacterAppearance(state).skinTint).toEqual([65, 45, 35]);
  });

  it("clears stale optimistic values on disconnect or session replacement", () => {
    let state = createCharacterAppearanceState(snapshot());
    state = characterAppearanceReducer(state, { type: "preview", change: { skinTint: [90, 30, 20] } });
    state = characterAppearanceReducer(state, { type: "snapshot", snapshot: { ...snapshot("replacement"), ready: false } });
    expect(state.sessionId).toBe("replacement");
    expect(state.optimistic).toEqual({});
    expect(selectDisplayedCharacterAppearance(state)).toEqual(NATURAL_CHARACTER_APPEARANCE);
  });

  it("restores each native ownership group to its neutral preview", () => {
    let state = createCharacterAppearanceState(snapshot());
    state = characterAppearanceReducer(state, { type: "restore", target: "eyes" });
    state = characterAppearanceReducer(state, { type: "restore", target: "hair" });
    state = characterAppearanceReducer(state, { type: "restore", target: "skin" });
    expect(selectDisplayedCharacterAppearance(state)).toEqual(NATURAL_CHARACTER_APPEARANCE);
  });
});
