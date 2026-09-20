import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { MovementSpeedControl } from "./MovementSpeedControl";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("movement_speed_control_tests");
afterEach(cleanup);
const snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "speed-session", revision: 1, ready: true, sections: [
  { id: "DWSpeed", title: "Movement speed", items: [
    { id: "multiplier", type: "number", value: 1 }, { id: "restore", type: "button" },
    { id: "status", type: "label", label: "Normal speed verified" },
  ] },
] };
function setup(next = snapshot) {
  const dispatch = vi.fn(async () => {});
  const props = { snapshot: next, dispatch, disabled: false, pending: false };
  return { ...render(<MovementSpeedControl {...props} />), props, dispatch };
}
it("commits a settled half-step once without claiming native confirmation", () => {
  const { dispatch } = setup();
  const slider = screen.getByRole("slider", { name: "Speed Multiplier" });
  expect(slider).toHaveAttribute("min", "1"); expect(slider).toHaveAttribute("max", "3");
  expect(slider).toHaveAttribute("step", "0.5");
  fireEvent.change(slider, { target: { value: "1.5" } });
  fireEvent.change(slider, { target: { value: "2" } });
  expect(dispatch).not.toHaveBeenCalled();
  fireEvent.pointerUp(slider); fireEvent.blur(slider);
  expect(dispatch).toHaveBeenCalledExactlyOnceWith({ action: "set", sectionId: "DWSpeed", itemId: "multiplier", value: 2 });
  expect(slider).toHaveValue("1");
});
it("supports keyboard commit and Escape cancellation", () => {
  const { dispatch } = setup(); const slider = screen.getByRole("slider");
  fireEvent.change(slider, { target: { value: "1.5" } }); fireEvent.keyUp(slider, { key: "ArrowRight" });
  expect(dispatch).toHaveBeenCalledTimes(1);
  fireEvent.change(slider, { target: { value: "3" } }); fireEvent.keyDown(slider, { key: "Escape" }); fireEvent.blur(slider);
  expect(dispatch).toHaveBeenCalledTimes(1); expect(slider).toHaveValue("1");
});
it("keeps native 1x restoration on the slider without a separate restore row", () => {
  const accelerated = { ...snapshot, sections: snapshot.sections.map(section => ({ ...section, items: section.items.map(item => item.id === "multiplier" ? { ...item, value: 2 } : item) })) };
  const { dispatch } = setup(accelerated);
  const slider = screen.getByRole("slider", { name: "Speed Multiplier" });
  fireEvent.change(slider, { target: { value: "1" } });
  fireEvent.pointerUp(slider);
  expect(dispatch).toHaveBeenCalledExactlyOnceWith({ action: "set", sectionId: "DWSpeed", itemId: "multiplier", value: 1 });
  expect(screen.queryByRole("button", { name: "Restore normal movement speed" })).not.toBeInTheDocument();
  expect(screen.queryByText("Normal speed verified")).not.toBeInTheDocument();
});
it("disables disconnected and in-flight controls", () => {
  const { rerender, props } = setup({ ...snapshot, ready: false });
  expect(screen.getByRole("slider")).toBeDisabled();
  expect(screen.queryByRole("button", { name: "Restore normal movement speed" })).not.toBeInTheDocument();
  expect(screen.queryByText("Connect to read movement speed.")).not.toBeInTheDocument();
  rerender(<MovementSpeedControl {...props} snapshot={snapshot} pending />);
  expect(screen.getByRole("slider")).toBeDisabled();
});
it("keeps feedback and confirmed readback without rendering native status copy", () => {
  const { rerender, props } = setup();
  const feedback = { sectionId: "DWSpeed", message: "Request queued. Check the control's game status." };
  const next = (label: string, value: number): ImportedMenuSnapshot => ({ ...snapshot, revision: snapshot.revision + 1,
    operation: { id: "receipt", status: "completed", message: "Command completed" },
    sections: snapshot.sections.map(section => ({ ...section, items: section.items.map(item => item.id === "status" ? { ...item, label }
      : item.id === "multiplier" ? { ...item, value } : item) })),
  });
  rerender(<MovementSpeedControl {...props} feedback={feedback} snapshot={next("Pending: resume gameplay to verify speed.", 1)} />);
  expect(screen.queryByText("Pending: resume gameplay to verify speed.")).not.toBeInTheDocument();
  expect(screen.getByRole("alert")).toHaveTextContent("Request queued. Check the control's game status.");
  expect(screen.getByRole("slider")).toHaveValue("1");
  rerender(<MovementSpeedControl {...props} feedback={feedback} snapshot={next("2x speed verified by active profile readback.", 2)} />);
  expect(screen.queryByText("2x speed verified by active profile readback.")).not.toBeInTheDocument();
  expect(screen.queryByText("Pending: resume gameplay to verify speed.")).not.toBeInTheDocument();
  expect(screen.getByRole("slider")).toHaveValue("2");
  rerender(<MovementSpeedControl {...props} snapshot={next("Recovery pending: restore the original profile.", 2)} feedback={{ sectionId: "DWSpeed", message: "Restore failed: foreign profile is active." }} />);
  expect(screen.getByRole("alert")).toHaveTextContent("Restore failed: foreign profile is active.");
  expect(screen.queryByText("Recovery pending: restore the original profile.")).not.toBeInTheDocument();
});
