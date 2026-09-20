import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { ImportedMenuConfirmation, ImportedMenuPanel } from "./ImportedMenuPanel";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_refinement_tests");
afterEach(cleanup);
const snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "test", revision: 1, ready: true, sections: [{ id: "DWXP", title: "Experience", items: [{ id: "amount", type: "number", label: "Amount", value: 4, min: 1, max: 10 }] }] };

it("cancels numeric edits with Escape and reports out-of-range edits without dispatch", () => {
  const dispatch = vi.fn(async () => undefined);
  render(<ImportedMenuPanel category="player" snapshot={snapshot} disabled={false} dispatch={dispatch} />);
  const input = screen.getByRole("spinbutton");
  act(() => input.focus());
  fireEvent.change(input, { target: { value: "8" } });
  fireEvent.keyDown(input, { key: "Escape" });
  expect(input).toHaveValue(4);
  expect(dispatch).not.toHaveBeenCalled();
  act(() => input.focus());
  fireEvent.change(input, { target: { value: "11" } });
  act(() => input.blur());
  expect(screen.getByRole("alert")).toHaveTextContent("Value not applied");
  expect(dispatch).not.toHaveBeenCalled();
});

it("does not commit a draft after the runtime disables the field", () => {
  const dispatch = vi.fn(async () => undefined);
  const { rerender } = render(<ImportedMenuPanel category="player" snapshot={snapshot} disabled={false} dispatch={dispatch} />);
  const input = screen.getByRole("spinbutton");
  act(() => input.focus());
  fireEvent.change(input, { target: { value: "8" } });
  rerender(<ImportedMenuPanel category="player" snapshot={snapshot} disabled dispatch={dispatch} />);
  fireEvent.blur(input);
  expect(dispatch).not.toHaveBeenCalled();
});

it("restores focus after confirmation and keeps pending dialog focus contained", () => {
  const dispatch = vi.fn(async () => undefined);
  const view = (confirmation: ImportedMenuSnapshot["confirmation"], pending = false) => <><button>Original action</button><ImportedMenuConfirmation snapshot={{ ...snapshot, confirmation }} pending={pending} dispatch={dispatch} /></>;
  const { rerender } = render(view(undefined));
  const original = screen.getByRole("button", { name: "Original action" });
  original.focus();
  const confirmation = { token: "one", title: "Confirm change", message: "Changes the save" };
  rerender(view(confirmation));
  expect(screen.getByRole("button", { name: "Cancel" })).toHaveFocus();
  original.focus();
  expect(screen.getByRole("dialog")).toHaveFocus();
  rerender(view(confirmation, true));
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Tab" });
  expect(screen.getByRole("dialog")).toHaveFocus();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  expect(dispatch).not.toHaveBeenCalled();
  rerender(view(undefined));
  expect(original).toHaveFocus();
});
