import type { ImportedMenuSnapshot } from "./importedMenuContract";
import type { Dispatch } from "./importedMenuState";
import type { CharacterAppearanceChange } from "./characterAppearanceState";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_skin_tint_panel");

type Tint = readonly [red: number, green: number, blue: number];
const NEUTRAL_TINT: Tint = [50, 50, 50];

function parseTint(value: unknown): Tint | null {
  if (typeof value !== "string") return null;
  const parts = value.split(",").map(part => part.trim());
  if (parts.length !== 3) return null;
  const channels = parts.map(Number);
  if (channels.some(channel => !Number.isInteger(channel) || channel < 0 || channel > 100)) return null;
  return channels as unknown as Tint;
}

function channelToHex(channel: number): string {
  return Math.round(channel * 255 / 100).toString(16).padStart(2, "0");
}

function tintToHex(tint: Tint): string {
  return `#${tint.map(channelToHex).join("")}`;
}

function hexToTint(value: string): Tint | null {
  const match = /^#([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(value);
  if (!match) return null;
  return match.slice(1).map(pair => Math.round(Number.parseInt(pair, 16) * 100 / 255)) as unknown as Tint;
}

function serializeTint(tint: Tint): string {
  return tint.join(",");
}

export function SkinTintPanel({ snapshot, dispatch, pending = false, onPreviewChange }: Readonly<{
  snapshot?: ImportedMenuSnapshot;
  dispatch?: Dispatch;
  pending?: boolean;
  onPreviewChange?: (change: CharacterAppearanceChange) => void;
}>) {
  const live = snapshot?.ready ? snapshot.sections.find(section => section.id === "DWSkinTint") : undefined;
  const item = (id: string) => live?.items.find(entry => entry.id === id);
  const reportedTint = parseTint(item("tint")?.value);
  const tint = reportedTint ?? NEUTRAL_TINT;
  const owned = item("owned")?.value === true;
  const disabled = !live || !dispatch || pending || item("tint")?.disabled === true;
  const send = (next: Tint) => {
    if (disabled) return;
    onPreviewChange?.({ skinTint: next });
    void dispatch!({ action: "set", sectionId: "DWSkinTint", itemId: "tint", value: serializeTint(next) });
  };
  const setChannel = (index: number, raw: string) => {
    const value = Number(raw);
    if (!Number.isInteger(value) || value < 0 || value > 100) return;
    const next: [number, number, number] = [...tint];
    next[index] = value;
    send(next);
  };
  const restore = () => {
    if (disabled) return;
    onPreviewChange?.({ skinTint: NEUTRAL_TINT });
    void dispatch!({ action: "invoke", sectionId: "DWSkinTint", itemId: "restore" });
  };
  const note = !snapshot?.ready
    ? "Load your game to change Coen's skin colour; it applies live."
    : !live
      ? "The running game's mod does not expose skin colour yet — restart the game to load the updated scripts."
      : pending ? "Applying skin colour..."
      : /unavailable|failed|incomplete|recovery|needs attention/i.test(String(item("status")?.label ?? "")) ? "Skin colour needs attention. Restore the original skin before trying again."
      : owned && reportedTint ? "Skin colour applied."
      : owned ? "Restore the original skin before trying again."
      : /^Original .*restored/i.test(String(item("status")?.label ?? "")) ? "Original skin restored."
      : "Choose a skin colour.";
  const channelLabels = ["Red", "Green", "Blue"] as const;

  return <section className="eye-appearance skin-tint-panel" aria-label="Character Skin Colour">
    <header className="eye-heading">
      <div><span className="eye-kicker">Your character</span><h3>Skin Colour</h3></div>
      <span className="eye-application-status">{live ? "Game (live)" : "Load a save"}</span>
    </header>
    <div className="skin-tint-controls">
      <label className="skin-tint-picker">Skin tint colour
        <input type="color" aria-label="Skin tint colour" value={tintToHex(tint)} disabled={disabled}
          onChange={(event) => { const next = hexToTint(event.target.value); if (next) send(next); }} />
      </label>
      <div className="skin-tint-sliders">
        {channelLabels.map((label, index) => <label key={label}>{label} tint
          <span><input type="range" min="0" max="100" step="1" value={tint[index]} disabled={disabled}
            aria-label={`${label} tint`} onChange={(event) => setChannel(index, event.target.value)} />
          <output>{tint[index]}</output></span>
        </label>)}
      </div>
    </div>
    <p className="eye-mode-note">50 / 50 / 50 is the original skin tone. Adjust the sliders to change its colour.</p>
    <div className="eye-restore-block">
      <button disabled={disabled || !owned} onClick={restore}>Restore Original Skin</button>
      <p>Returns to your original skin colour.</p>
    </div>
    <p className="eye-mode-note skin-tint-status" aria-live="polite">{note}</p>
  </section>;
}
