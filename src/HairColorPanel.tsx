import type { ImportedMenuSnapshot } from "./importedMenuContract";
import type { Dispatch } from "./importedMenuState";
import type { CharacterAppearanceChange } from "./characterAppearanceState";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_hair_color_panel");

// The native haircut shader maps these natural shades to melanin and warmth.
// It cannot honour arbitrary dye colours. Eyebrow presets are withheld until the
// complete independent palette has visual acceptance; restore still cleans both.
const HAIR_PRESETS = [
  ["Black", "#17120f"], ["Dark brown", "#3a2418"], ["Chestnut", "#6b3a1f"], ["Auburn", "#8a3b1e"],
  ["Blonde", "#c9a35a"], ["Platinum", "#e6dcc3"], ["White", "#ffffff"],
] as const;

export function HairColorPanel({ snapshot, dispatch, pending = false, onPreviewChange }: Readonly<{
  snapshot?: ImportedMenuSnapshot; dispatch?: Dispatch; pending?: boolean;
  onPreviewChange?: (change: CharacterAppearanceChange) => void;
}>) {
  const live = snapshot?.ready ? snapshot.sections.find(section => section.id === "DWHairColor") : undefined;
  const item = (id: string) => live?.items.find(entry => entry.id === id);
  const hex = (value: unknown) => typeof value === "string" && /^#[\da-f]{6}$/i.test(value) ? value.toLowerCase() : null;
  const hair = hex(item("color")?.value);
  const owned = item("owned")?.value === true;
  const disabled = !live || !dispatch || pending || item("color")?.disabled === true;
  const set = (value: string) => {
    if (disabled) return;
    const normalized = value.toLowerCase();
    onPreviewChange?.({ hairColor: normalized });
    void dispatch!({ action: "set", sectionId: "DWHairColor", itemId: "color", value: normalized });
  };
  const restore = () => {
    if (disabled) return;
    onPreviewChange?.({ hairColor: null, eyebrowColor: null });
    void dispatch!({ action: "invoke", sectionId: "DWHairColor", itemId: "restore" });
  };
  const note = !snapshot?.ready ? "Load your game to colour the hair; it applies live, no restart."
    : !live ? "The running game's mod does not expose hair colour yet — restart the game to load the updated scripts."
    : pending ? "Applying hair colour..."
    : /unavailable|failed|incomplete|recovery|required|needs attention/i.test(String(item("status")?.label ?? "")) ? "Hair colour needs attention. Restore the original hair before trying again."
    : owned && hair ? "Hair colour applied."
    : owned ? "Restore the original hair before trying again."
    : /^Original .*restored/i.test(String(item("status")?.label ?? "")) ? "Original hair restored."
    : "Select a hair colour.";

  return <section className="eye-appearance hair-color-panel" aria-label="Character Hair Colour">
    <header className="eye-heading"><div><span className="eye-kicker">Your character</span><h3>Hair Colour</h3></div><span className="eye-application-status">{live ? "Game (live)" : "Load a save"}</span></header>
    <fieldset className="eye-presets hair-color-live" disabled={disabled}><legend>Hair colour (natural shades)</legend><div>
      {HAIR_PRESETS.map(([label, value]) => <button key={label} aria-pressed={hair === value} onClick={() => set(value)}>
        <span className="eye-color-swatch" style={{ backgroundColor: value }} />{label}
      </button>)}
    </div></fieldset>
    <p className="eye-mode-note hair-color-hair-note">Natural shades vary with the game's lighting.</p>
    <div className="eye-restore-block"><button disabled={disabled || !owned} onClick={restore}>Restore Original Hair</button><p>Returns to your original appearance.</p></div>
    <p className="eye-mode-note hair-color-status" aria-live="polite">{note}</p>
  </section>;
}
