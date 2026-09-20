import { useEffect, useRef, useState } from "react";
import { CharacterEyePreview } from "./CharacterEyePreview";
import { createEyeColorSelection, type EyeColorSelectionState } from "./eyeColorSelection";
import { applyGameEyeColor } from "./gameEyeColor";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
import type { CharacterAppearance, CharacterAppearanceChange } from "./characterAppearanceState";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_appearance_panel");

export function EyeAppearancePanel({ active, snapshot, appearance, onPreviewChange, onPreviewFailure }: Readonly<{
  active: boolean;
  snapshot?: ImportedMenuSnapshot;
  appearance?: CharacterAppearance;
  onPreviewChange?: (change: CharacterAppearanceChange) => void;
  onPreviewFailure?: () => void;
}>) {
  const controller = useRef<ReturnType<typeof createEyeColorSelection> | undefined>(undefined);
  const failureHandler = useRef(onPreviewFailure);
  failureHandler.current = onPreviewFailure;
  const [selection, setSelection] = useState<EyeColorSelectionState>({ phase: "idle", value: null });
  useEffect(() => {
    const current = createEyeColorSelection({
      apply: async (color, glow) => {
        const transport = window.dawnwalkerDesktop?.importedMenu;
        if (!transport) throw new Error("Open the desktop menu and load your game to apply eye color.");
        await applyGameEyeColor(transport, color, glow);
      },
      notify: next => {
        setSelection(next);
        if (next.phase === "error") failureHandler.current?.();
      },
    });
    controller.current = current;
    return () => { current.dispose(); controller.current = undefined; };
  }, []);
  useEffect(() => { controller.current?.invalidate(); }, [active, snapshot?.sessionId, snapshot?.ready]);
  const native = snapshot?.sections.find(section => section.id === "DWEyeColor");
  const owned = native?.items.find(item => item.id === "owned")?.value === true;
  const actualColor = native?.items.find(item => item.id === "color")?.value;
  // The transport disables every control of a section whose native path is pinned to
  // a different game build and puts the reason in its status. Showing "Select a color"
  // over disabled controls invited a click that could only fail.
  const gated = Boolean(native) && native!.items.some(item => item.id === "color" && item.disabled === true);
  const confirmed = snapshot?.ready && owned && typeof actualColor === "string" && /^#[\da-f]{6}$/i.test(actualColor);
  const message = selection.phase === "pending" ? "Applying eye color in game..."
    : selection.phase === "error" ? "Eye colour could not be applied. Restore original game eyes before trying again."
    : confirmed ? "Eye colour applied."
    : !snapshot?.ready ? "Preview available. Load your game to apply a color."
    : !native ? "Game eye controls are unavailable. Check the game connection."
    : gated ? "Eye colour is unavailable on this game build."
    : owned ? "Eye colour needs attention. Restore original game eyes before trying again."
    : selection.phase === "applied" && selection.value === null ? "Original game eyes restored."
    : "Select a color to apply it in game.";
  return <div className="character-eye-workflow"><CharacterEyePreview active={active} appearance={appearance}
    onColorSelect={(color, glow) => {
      if (gated) return;
      onPreviewChange?.({ eyeColor: color, eyeGlow: color === null ? 0 : glow });
      controller.current?.request(color, glow);
    }}
    liveStatus="Vampire-style eyes. Game lighting affects appearance; the preview is an approximation. Glow strength applies in game too." />
    <small role="status" aria-live="polite">{message}</small>
  </div>;
}
