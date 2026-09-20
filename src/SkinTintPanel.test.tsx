import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
import { SkinTintPanel } from "./SkinTintPanel";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("skin_tint_panel_tests");

afterEach(cleanup);

function snapshotWith(tint = "50,50,50", owned = true): ImportedMenuSnapshot {
  return { schema: 1, sessionId: "skin-session", revision: 4, ready: true, sections: [{
    id: "DWSkinTint", title: "Skin color", items: [
      { id: "tint", type: "input", label: "Skin tint RGB", value: tint },
      { id: "owned", type: "checkbox", label: "Skin tint override active", value: owned, readOnly: true },
      { id: "restore", type: "button", label: "Restore original skin" },
      { id: "status", type: "label", label: owned ? `Applied in game: ${tint}.` : "Original skin is active." },
    ],
  }] };
}

it("maps the visual color picker and RGB sliders to one atomic native tint value", () => {
  const dispatch = vi.fn().mockResolvedValue({ accepted: true, operationId: "skin", message: "queued" });
  const onPreviewChange = vi.fn();
  render(<SkinTintPanel snapshot={snapshotWith()} dispatch={dispatch} onPreviewChange={onPreviewChange} />);

  const picker = screen.getByLabelText("Skin tint colour") as HTMLInputElement;
  expect(picker.value).toBe("#808080");
  expect(screen.getByLabelText("Red tint")).toHaveValue("50");
  expect(screen.getByLabelText("Green tint")).toHaveValue("50");
  expect(screen.getByLabelText("Blue tint")).toHaveValue("50");

  fireEvent.change(picker, { target: { value: "#ff8040" } });
  expect(onPreviewChange).toHaveBeenLastCalledWith({ skinTint: [100, 50, 25] });
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWSkinTint", itemId: "tint", value: "100,50,25" });

  fireEvent.change(screen.getByLabelText("Red tint"), { target: { value: "88" } });
  expect(onPreviewChange).toHaveBeenLastCalledWith({ skinTint: [88, 50, 50] });
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWSkinTint", itemId: "tint", value: "88,50,50" });

  fireEvent.click(screen.getByRole("button", { name: "Restore Original Skin" }));
  expect(onPreviewChange).toHaveBeenLastCalledWith({ skinTint: [50, 50, 50] });
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWSkinTint", itemId: "restore" });
  expect(screen.getByText("Skin colour applied.")).toBeVisible();
});

it("stays disabled until the connected runtime exposes the skin tint contract", () => {
  const dispatch = vi.fn();
  render(<SkinTintPanel snapshot={{ schema: 1, sessionId: "s", revision: 1, ready: true, sections: [] }} dispatch={dispatch} />);
  expect(screen.getByLabelText("Skin tint colour")).toBeDisabled();
  expect(screen.getByLabelText("Red tint")).toBeDisabled();
  expect(screen.getByRole("button", { name: "Restore Original Skin" })).toBeDisabled();
  expect(screen.getByText(/restart the game to load the updated scripts/i)).toBeVisible();
  expect(dispatch).not.toHaveBeenCalled();
});

it("rejects malformed native values and never dispatches while another operation is pending", () => {
  const dispatch = vi.fn();
  render(<SkinTintPanel snapshot={snapshotWith("500,-2,nope", false)} dispatch={dispatch} pending />);
  expect(screen.getByLabelText("Skin tint colour")).toHaveValue("#808080");
  expect(screen.getByLabelText("Skin tint colour")).toBeDisabled();
  fireEvent.change(screen.getByLabelText("Blue tint"), { target: { value: "90" } });
  expect(dispatch).not.toHaveBeenCalled();
});

it("summarizes native diagnostics without rendering material identifiers", () => {
  const state = snapshotWith("80,35,25", true);
  state.sections[0].items.find(item => item.id === "status")!.label = "Skin tint ownership verified. /Game/MI_Head\nPrivateMaterial_22 SkinTint=(1.6,0.7,0.5)";
  render(<SkinTintPanel snapshot={state} dispatch={vi.fn()} />);
  expect(document.querySelector(".skin-tint-status")).toHaveTextContent("Skin colour applied.");
  expect(screen.queryByText(/MI_Head|PrivateMaterial|SkinTint=/)).not.toBeInTheDocument();
  expect(screen.queryByText(/materials|readback|Rebinds/i)).not.toBeInTheDocument();
});
