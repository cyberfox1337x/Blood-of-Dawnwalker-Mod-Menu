import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
import { HairColorPanel } from "./HairColorPanel";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("hair_color_panel_tests");

afterEach(cleanup);

const liveSection = (hair: string, brows: string) => ({ id: "DWHairColor", title: "Hair color", items: [
  { id: "color", type: "input" as const, label: "Hair color (natural range)", value: hair },
  { id: "brows", type: "input" as const, label: "Eyebrow color", value: brows },
  { id: "browStatus", type: "label" as const, label: brows ? `Eyebrows in game: ${brows.toUpperCase()}. Face Mesh: RootColor=(0.46,0.03,0.04)` : "Select an eyebrow colour to apply it in game." },
  { id: "owned", type: "checkbox" as const, label: "Hair color override active", value: Boolean(hair || brows) },
  { id: "status", type: "label" as const, label: hair ? `Applied in game: hair ${hair.toUpperCase()} as natural melanin 0.74, redness 0.75, grey 0.00.` : "Select a hair colour to apply it in game." },
  { id: "restore", type: "button" as const, label: "Restore original hair and eyebrows" },
] });
const snapshotWith = (hair: string, brows: string): ImportedMenuSnapshot => ({ schema: 1, sessionId: "s", revision: 3, ready: true, sections: [liveSection(hair, brows)] });

it("offers natural hair colours without unverified eyebrow options or native diagnostics", () => {
  const dispatch = vi.fn().mockResolvedValue({ accepted: true, operationId: "hair", message: "queued" });
  const onPreviewChange = vi.fn();
  render(<HairColorPanel snapshot={snapshotWith("#8a3b1e", "#b52c35")} dispatch={dispatch} onPreviewChange={onPreviewChange} />);
  const hair = within(screen.getByRole("group", { name: "Hair colour (natural shades)" }));
  // Selection reflects what the game reports for each part independently.
  expect(hair.getByRole("button", { name: "Auburn" })).toHaveAttribute("aria-pressed", "true");
  expect(screen.queryByRole("group", { name: "Eyebrow colour" })).not.toBeInTheDocument();
  expect(hair.queryByRole("button", { name: /^Red$/ })).not.toBeInTheDocument();
  fireEvent.click(hair.getByRole("button", { name: "Blonde" }));
  expect(onPreviewChange).toHaveBeenLastCalledWith({ hairColor: "#c9a35a" });
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWHairColor", itemId: "color", value: "#c9a35a" });
  // No free colour pickers: only shades the shader was seen to honour are offered.
  expect(screen.queryByLabelText("Custom hair color")).toBeNull();
  expect(screen.queryByLabelText("Custom eyebrow color")).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Restore Original Hair" }));
  expect(onPreviewChange).toHaveBeenLastCalledWith({ hairColor: null, eyebrowColor: null });
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWHairColor", itemId: "restore" });
  expect(document.querySelector(".hair-color-status")).toHaveTextContent("Hair colour applied.");
  expect(screen.queryByText(/melanin|RootColor|Face Mesh/)).not.toBeInTheDocument();
});

it("stays disabled without a save, and says so when the running mod predates hair colour", () => {
  const dispatch = vi.fn();
  render(<HairColorPanel snapshot={{ schema: 1, sessionId: "s", revision: 1, ready: true, sections: [] }} dispatch={dispatch} />);
  expect(within(screen.getByRole("group", { name: "Hair colour (natural shades)" })).getByRole("button", { name: "Blonde" })).toBeDisabled();
  expect(screen.queryByRole("group", { name: "Eyebrow colour" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Restore Original Hair" })).toBeDisabled();
  expect(document.querySelector(".hair-color-status")).toHaveTextContent("restart the game to load the updated scripts");
  cleanup();
  render(<HairColorPanel snapshot={{ schema: 1, sessionId: "", revision: 0, ready: false, sections: [] }} dispatch={dispatch} />);
  expect(document.querySelector(".hair-color-status")).toHaveTextContent("Load your game");
  expect(dispatch).not.toHaveBeenCalled();
});

it("keeps the eyebrow controls off when the game's section predates them, and never dispatches while pending", () => {
  const dispatch = vi.fn();
  const older = { ...liveSection("", ""), items: liveSection("", "").items.filter(entry => entry.id !== "brows" && entry.id !== "browStatus") };
  render(<HairColorPanel snapshot={{ schema: 1, sessionId: "s", revision: 2, ready: true, sections: [older] }} dispatch={dispatch} />);
  expect(within(screen.getByRole("group", { name: "Hair colour (natural shades)" })).getByRole("button", { name: "Blonde" })).toBeEnabled();
  expect(screen.queryByRole("group", { name: "Eyebrow colour" })).not.toBeInTheDocument();
  cleanup();
  render(<HairColorPanel snapshot={snapshotWith("", "")} dispatch={dispatch} pending />);
  fireEvent.click(within(screen.getByRole("group", { name: "Hair colour (natural shades)" })).getByRole("button", { name: "Blonde" }));
  expect(dispatch).not.toHaveBeenCalled();
});

it("retains a concise recovery result when diagnostics accompany an owned colour", () => {
  const state = snapshotWith("#ffffff", "");
  state.sections[0].items.find(item => item.id === "status")!.label = "Restore incomplete: /Game/MI_Hair\nRootColor=(1,0,0)";
  render(<HairColorPanel snapshot={state} dispatch={vi.fn()} />);
  expect(document.querySelector(".hair-color-status")).toHaveTextContent("Hair colour needs attention.");
  expect(document.querySelector(".hair-color-status")).not.toHaveTextContent("applied");
  expect(screen.queryByText(/MI_Hair|RootColor/)).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Restore Original Hair" })).toBeEnabled();
});
