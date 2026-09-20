import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { EyeAppearancePanel } from "./EyeAppearancePanel";
import { applyGameEyeColor } from "./gameEyeColor";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
import { NATURAL_CHARACTER_APPEARANCE } from "./characterAppearanceState";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("eye_panel_native_status_tests");
vi.mock("./gameEyeColor", () => ({ applyGameEyeColor: vi.fn() }));
vi.mock("./CharacterEyePreview", () => ({ CharacterEyePreview: ({ onColorSelect, appearance }: { onColorSelect: (color: string | null, glow: number) => void; appearance?: { hairColor: string | null } }) => <div>
  Editable character preview
  <span data-testid="preview-hair">{appearance?.hairColor ?? "natural"}</span>
  <button onClick={() => onColorSelect("#ff0000", 0)}>Red</button>
  <button onClick={() => onColorSelect("#35b8cc", 0)}>Custom teal</button>
  <button onClick={() => onColorSelect("#20f6ff", 2.2)}>Neon cyan</button>
  <button onClick={() => onColorSelect(null, 0)}>Restore</button>
</div> }));
function snapshot(color = "", owned = false, sessionId = "session"): ImportedMenuSnapshot {
  return { schema: 1, sessionId, revision: 1, ready: true, sections: [{ id: "DWEyeColor", title: "Eyes", items: [
    { id: "color", type: "input", value: color }, { id: "owned", type: "checkbox", value: owned },
  ] }] };
}
beforeEach(() => { vi.useFakeTimers(); vi.mocked(applyGameEyeColor).mockReset().mockResolvedValue();
  window.dawnwalkerDesktop = { importedMenu: {} } as NonNullable<typeof window.dawnwalkerDesktop>; });
afterEach(() => { cleanup(); vi.useRealTimers(); delete window.dawnwalkerDesktop; });
it("coalesces preview selections and shows success only from native state", async () => {
  const view = render(<EyeAppearancePanel active snapshot={snapshot()} />);
  fireEvent.click(screen.getByText("Red")); fireEvent.click(screen.getByText("Custom teal"));
  expect(screen.getByRole("status")).toHaveTextContent("Applying");
  await act(() => vi.advanceTimersByTimeAsync(250));
  expect(applyGameEyeColor).toHaveBeenCalledTimes(1);
  expect(applyGameEyeColor).toHaveBeenCalledWith(window.dawnwalkerDesktop!.importedMenu, "#35b8cc", 0);
  expect(screen.getByRole("status")).not.toHaveTextContent("applied");
  view.rerender(<EyeAppearancePanel active snapshot={snapshot("#35b8cc", true)} />);
  expect(screen.getByRole("status")).toHaveTextContent("Eye colour applied.");
  expect(screen.getByRole("status")).not.toHaveTextContent(/#[\da-f]{6}|material|readback/i);
  view.rerender(<EyeAppearancePanel active snapshot={snapshot()} />);
  expect(screen.getByRole("status")).not.toHaveTextContent("Applied");
});
it("retains the actual native color across tab changes without sending another write", () => {
  const view = render(<EyeAppearancePanel active snapshot={snapshot("#ff0000", true)} />);
  view.rerender(<EyeAppearancePanel active={false} snapshot={snapshot("#ff0000", true)} />);
  view.rerender(<EyeAppearancePanel active snapshot={snapshot("#ff0000", true)} />);
  expect(screen.getByRole("status")).toHaveTextContent("Eye colour applied.");
  expect(applyGameEyeColor).not.toHaveBeenCalled();
});
it("cancels unsent selection when the session changes", async () => {
  const view = render(<EyeAppearancePanel active snapshot={snapshot()} />);
  fireEvent.click(screen.getByText("Red"));
  view.rerender(<EyeAppearancePanel active snapshot={snapshot("", false, "replacement")} />);
  await act(() => vi.advanceTimersByTimeAsync(500));
  expect(applyGameEyeColor).not.toHaveBeenCalled();
  expect(screen.getByRole("status")).not.toHaveTextContent("Applying");
});
it("reports native failure while keeping the preview usable and allows explicit restore", async () => {
  vi.mocked(applyGameEyeColor).mockRejectedValueOnce(new Error("Failed: /Game/MI_Coen_Head: RootColor=0.5\nPrivateMaterial_123"));
  const onPreviewFailure = vi.fn();
  render(<EyeAppearancePanel active snapshot={snapshot()} onPreviewFailure={onPreviewFailure} />);
  fireEvent.click(screen.getByText("Red"));
  await act(() => vi.advanceTimersByTimeAsync(250));
  expect(screen.getByRole("status")).toHaveTextContent("Eye colour could not be applied");
  expect(onPreviewFailure).toHaveBeenCalledTimes(1);
  expect(screen.queryByText(/MI_Coen|RootColor|PrivateMaterial/)).not.toBeInTheDocument();
  expect(screen.getByText("Editable character preview")).toBeVisible();
  fireEvent.click(screen.getByText("Restore"));
  await act(async () => undefined);
  expect(applyGameEyeColor).toHaveBeenLastCalledWith(window.dawnwalkerDesktop!.importedMenu, null, 0);
  expect(screen.getByRole("status")).toHaveTextContent("Original game eyes restored");
});
it("does not report applied from a disconnected or missing native section", () => {
  const view = render(<EyeAppearancePanel active snapshot={{ ...snapshot("#ff0000", true), ready: false }} />);
  expect(screen.getByRole("status")).toHaveTextContent("Load your game");
  view.rerender(<EyeAppearancePanel active snapshot={{ ...snapshot(), sections: [] }} />);
  expect(screen.getByRole("status")).toHaveTextContent("Check the game connection");
});
it("shows cleanup failures while native ownership remains without a confirmed color", () => {
  const state = snapshot("", true);
  state.sections[0].items.push({ id: "status", type: "label", label: "Eye color needs attention: restore incomplete." });
  render(<EyeAppearancePanel active snapshot={state} />);
  expect(screen.getByRole("status")).toHaveTextContent("Restore original game eyes before trying again");
  expect(screen.getByRole("status")).not.toHaveTextContent("Applied in game");
});
it("forwards a neon preset's glow strength to the game apply", async () => {
  const onPreviewChange = vi.fn();
  const appearance = { ...NATURAL_CHARACTER_APPEARANCE, hairColor: "#c9a35a" };
  render(<EyeAppearancePanel active snapshot={snapshot()} appearance={appearance} onPreviewChange={onPreviewChange} />);
  expect(screen.getByTestId("preview-hair")).toHaveTextContent("#c9a35a");
  fireEvent.click(screen.getByText("Neon cyan"));
  expect(onPreviewChange).toHaveBeenCalledWith({ eyeColor: "#20f6ff", eyeGlow: 2.2 });
  await act(() => vi.advanceTimersByTimeAsync(250));
  expect(applyGameEyeColor).toHaveBeenCalledWith(window.dawnwalkerDesktop!.importedMenu, "#20f6ff", 2.2);
});
