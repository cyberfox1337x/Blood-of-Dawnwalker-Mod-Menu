import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { ImportedMenuPanel } from "./ImportedMenuPanel";
import type { ImportedMenuSnapshot } from "./importedMenuContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("form_toggle_renderer_tests");
afterEach(cleanup);

const state = (enabled: boolean): ImportedMenuSnapshot => ({
  schema: 1, sessionId: "form-session", revision: 1, ready: true,
  sections: [{ id: "DWFormToggle", title: "Vampire Form", tab: "Player", items: [
    { id: "enabled", type: "checkbox", label: "Vampire form override", value: enabled },
    { id: "status", type: "label", label: enabled ? "Forced vampire" : "Automatic day/night; current form: Vampire" },
  ] }],
});

it("waits for native acknowledgement and sends explicit on/off requests in Player", () => {
  const dispatch = vi.fn(async () => {});
  const view = render(<ImportedMenuPanel category="player" group="player" snapshot={state(false)} disabled={false} dispatch={dispatch} />);
  const toggle = screen.getByRole("switch", { name: /Vampire form override/ });
  expect(toggle).not.toBeChecked();
  fireEvent.click(toggle);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWFormToggle", itemId: "enabled", value: true });
  expect(toggle).not.toBeChecked();
  view.rerender(<ImportedMenuPanel category="player" group="player" snapshot={state(true)} disabled={false} dispatch={dispatch} />);
  expect(toggle).toBeChecked();
  fireEvent.click(toggle);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWFormToggle", itemId: "enabled", value: false });
});

it("keeps automatic nighttime OFF and blocks pending or disconnected requests", () => {
  const dispatch = vi.fn(async () => {});
  const view = render(<ImportedMenuPanel category="player" snapshot={state(false)} disabled={false} pending dispatch={dispatch} />);
  const toggle = screen.getByRole("switch", { name: /Vampire form override/ });
  expect(toggle).not.toBeChecked();
  expect(toggle).toBeDisabled();
  fireEvent.click(toggle);
  expect(dispatch).not.toHaveBeenCalled();
  view.rerender(<ImportedMenuPanel category="player" snapshot={state(false)} disabled dispatch={dispatch} />);
  expect(toggle).toBeDisabled();
  expect(screen.getByText("Automatic day/night; current form: Vampire")).toBeVisible();
});
