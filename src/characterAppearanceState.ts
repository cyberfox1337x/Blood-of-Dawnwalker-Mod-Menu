import type { ImportedMenuSnapshot } from "./importedMenuContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_appearance_state");

export type SkinTint = readonly [red: number, green: number, blue: number];
export type CharacterAppearance = Readonly<{
  eyeColor: string | null;
  eyeGlow: number;
  hairColor: string | null;
  eyebrowColor: string | null;
  skinTint: SkinTint;
}>;
export type ConfirmedCharacterAppearance = CharacterAppearance;
export type CharacterAppearanceChange = Partial<CharacterAppearance>;
export type CharacterAppearanceState = Readonly<{
  sessionId: string;
  confirmed: ConfirmedCharacterAppearance;
  optimistic: CharacterAppearanceChange;
}>;

export const NATURAL_CHARACTER_APPEARANCE: ConfirmedCharacterAppearance = Object.freeze({
  eyeColor: null,
  eyeGlow: 0,
  hairColor: null,
  eyebrowColor: null,
  skinTint: Object.freeze([50, 50, 50] as const),
});

function sectionItem(snapshot: ImportedMenuSnapshot, sectionId: string, itemId: string): unknown {
  return snapshot.sections.find(section => section.id === sectionId)?.items.find(item => item.id === itemId)?.value;
}

function owned(snapshot: ImportedMenuSnapshot, sectionId: string): boolean {
  return snapshot.ready && sectionItem(snapshot, sectionId, "owned") === true;
}

function parseHex(value: unknown): string | null {
  return typeof value === "string" && /^#[\da-f]{6}$/i.test(value) ? value.toLowerCase() : null;
}

function parseGlow(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 3 ? value : null;
}

function parseSkinTint(value: unknown): SkinTint | null {
  if (typeof value !== "string") return null;
  const channels = value.split(",").map(channel => Number(channel.trim()));
  if (channels.length !== 3 || channels.some(channel => !Number.isInteger(channel) || channel < 0 || channel > 100)) return null;
  return channels as unknown as SkinTint;
}

export function parseConfirmedCharacterAppearance(snapshot: ImportedMenuSnapshot | undefined): ConfirmedCharacterAppearance {
  if (!snapshot?.ready) return NATURAL_CHARACTER_APPEARANCE;
  const eyeOwned = owned(snapshot, "DWEyeColor");
  const hairOwned = owned(snapshot, "DWHairColor");
  const skinOwned = owned(snapshot, "DWSkinTint");
  const eyeColor = eyeOwned ? parseHex(sectionItem(snapshot, "DWEyeColor", "color")) : null;
  const eyeGlow = eyeColor ? parseGlow(sectionItem(snapshot, "DWEyeColor", "glow")) : 0;
  const hairColor = hairOwned ? parseHex(sectionItem(snapshot, "DWHairColor", "color")) : null;
  const eyebrowColor = hairOwned ? parseHex(sectionItem(snapshot, "DWHairColor", "brows")) : null;
  const skinTint = skinOwned ? parseSkinTint(sectionItem(snapshot, "DWSkinTint", "tint")) : null;
  // Hair and eyebrows are applied independently in game, so one valid native value
  // remains useful while the other is still original or malformed.
  return {
    eyeColor,
    eyeGlow: eyeColor ? eyeGlow ?? 0 : 0,
    hairColor,
    eyebrowColor,
    skinTint: skinTint ?? NATURAL_CHARACTER_APPEARANCE.skinTint,
  };
}

export function createCharacterAppearanceState(snapshot?: ImportedMenuSnapshot): CharacterAppearanceState {
  return { sessionId: snapshot?.sessionId ?? "", confirmed: parseConfirmedCharacterAppearance(snapshot), optimistic: {} };
}

function sameValue(left: unknown, right: unknown): boolean {
  if (Array.isArray(left) && Array.isArray(right)) return left.length === right.length && left.every((value, index) => value === right[index]);
  return left === right;
}

function reconcileOptimistic(optimistic: CharacterAppearanceChange, confirmed: ConfirmedCharacterAppearance): CharacterAppearanceChange {
  return Object.fromEntries(Object.entries(optimistic).filter(([key, value]) => !sameValue(value, confirmed[key as keyof CharacterAppearance]))) as CharacterAppearanceChange;
}

export type CharacterAppearanceAction =
  | Readonly<{ type: "preview"; change: CharacterAppearanceChange }>
  | Readonly<{ type: "snapshot"; snapshot: ImportedMenuSnapshot }>
  | Readonly<{ type: "settled"; snapshot: ImportedMenuSnapshot }>
  | Readonly<{ type: "failure" }>
  | Readonly<{ type: "restore"; target: "eyes" | "hair" | "skin" }>;

export function characterAppearanceReducer(state: CharacterAppearanceState, action: CharacterAppearanceAction): CharacterAppearanceState {
  if (action.type === "preview") return { ...state, optimistic: { ...state.optimistic, ...action.change } };
  if (action.type === "failure") return { ...state, optimistic: {} };
  if (action.type === "restore") {
    const change = action.target === "eyes" ? { eyeColor: null, eyeGlow: 0 }
      : action.target === "hair" ? { hairColor: null, eyebrowColor: null }
      : { skinTint: NATURAL_CHARACTER_APPEARANCE.skinTint };
    return { ...state, optimistic: { ...state.optimistic, ...change } };
  }
  if (action.type === "settled") {
    return { sessionId: action.snapshot.sessionId, confirmed: parseConfirmedCharacterAppearance(action.snapshot), optimistic: {} };
  }
  const confirmed = parseConfirmedCharacterAppearance(action.snapshot);
  if (!action.snapshot.ready || action.snapshot.sessionId !== state.sessionId) {
    return { sessionId: action.snapshot.sessionId, confirmed, optimistic: {} };
  }
  return { ...state, confirmed, optimistic: reconcileOptimistic(state.optimistic, confirmed) };
}

export function selectDisplayedCharacterAppearance(state: CharacterAppearanceState): CharacterAppearance {
  return { ...state.confirmed, ...state.optimistic };
}
