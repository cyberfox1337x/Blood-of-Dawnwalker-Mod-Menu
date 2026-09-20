import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { CharacterEyePreview } from "./CharacterEyePreview";
import { NATURAL_CHARACTER_APPEARANCE } from "./characterAppearanceState";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_eye_native_controls_without_webgl");
afterEach(cleanup);

describe("native eye controls without a rendered model", () => {
  it("renders controlled eye state and emits a new selection without losing the other appearance layers", () => {
    const select = vi.fn();
    const appearance = { ...NATURAL_CHARACTER_APPEARANCE, eyeColor: "#5c9bc8", eyeGlow: 1.4,
      hairColor: "#c9a35a", eyebrowColor: "#1f7a7a", skinTint: [65, 45, 35] as const };
    render(<CharacterEyePreview active={false} appearance={appearance} onColorSelect={select} />);
    expect(screen.getByRole("button", { name: "Blue" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByLabelText("Eye glow strength")).toHaveValue("1.4");
    fireEvent.click(screen.getByRole("button", { name: "Green" }));
    expect(select).toHaveBeenLastCalledWith("#589c60", 0);
  });
  it("treats a controlled null eye colour as the restored natural state", () => {
    const select = vi.fn();
    const colored = { ...NATURAL_CHARACTER_APPEARANCE, eyeColor: "#5c9bc8", eyeGlow: 1.4 };
    const view = render(<CharacterEyePreview active={false} appearance={colored} onColorSelect={select} />);
    expect(screen.getByRole("button", { name: "Blue" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(screen.getByRole("button", { name: "Green" }));
    view.rerender(<CharacterEyePreview active={false} appearance={NATURAL_CHARACTER_APPEARANCE} onColorSelect={select} />);
    expect(screen.getByRole("button", { name: "Blue" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByRole("button", { name: "Green" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByLabelText("Eye glow strength")).toHaveValue("0");
    expect(screen.getByLabelText("Eye glow strength")).toBeDisabled();
  });
  it("keeps color and original-eye restoration available while the preview is inactive", () => {
    const select = vi.fn();
    render(<CharacterEyePreview active={false} onColorSelect={select} />);
    fireEvent.click(screen.getByRole("button", { name: "Blue" }));
    expect(select).toHaveBeenLastCalledWith("#5c9bc8", 0);
    const wheel = screen.getByLabelText("Character iris color");
    expect(wheel).not.toBeDisabled();
    fireEvent.change(wheel, { target: { value: "#35b8cc" } });
    expect(select).toHaveBeenLastCalledWith("#35b8cc", 0);
    fireEvent.click(screen.getByRole("button", { name: "Restore Original Eyes" }));
    expect(select).toHaveBeenLastCalledWith(null, 0);
    expect(screen.getByRole("button", { name: "Orbit" })).toBeDisabled();
  });

  it("exposes neon presets and sends their color to the preview/game callback", () => {
    const select = vi.fn();
    render(<CharacterEyePreview active={false} onColorSelect={select} />);
    const neonButton = screen.getAllByRole("button", { name: "Neon Cyan" }).at(-1)!;
    fireEvent.click(neonButton);
    expect(select).toHaveBeenLastCalledWith("#20f6ff", 2.2);
    expect(neonButton).toHaveAttribute("data-neon", "true");
    // The preset's glow lands in the slider, and moving the slider re-sends the colour
    // with the new strength (this is what reaches the game's Emissivnes).
    const slider = screen.getAllByRole("slider", { name: "Eye glow strength" }).at(-1)!;
    expect(slider).toHaveValue("2.2");
    fireEvent.change(slider, { target: { value: "3" } });
    expect(select).toHaveBeenLastCalledWith("#20f6ff", 3);
    expect(screen.queryByText(/preview-only/)).toBeNull();
  });
});
