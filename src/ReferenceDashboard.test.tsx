import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { PlayerMovementControls, PlayerOptions, PlayerReferenceControls, ReferenceDashboard, PlayerParryWindow } from "./ReferenceDashboard";
import { useImportedMenu } from "./importedMenuState";
import { ImportedMenuPanel } from "./ImportedMenuPanel";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("reference_dashboard_tests");
afterEach(cleanup);
it("shows Fly immediately before transport resolves and rolls back a rejected request", async () => {
  const current: ImportedMenuSnapshot = { schema: 1, sessionId: "instant-flight", revision: 1, ready: true,
    sections: [{ id: "DWPersonalFly", title: "Fly", items: [{ id: "enabled", type: "checkbox", value: false, enabled: true }] }] };
  let resolveDispatch: ((result: { accepted: boolean; message: string }) => void) | undefined;
  const transport = { state: vi.fn(async () => current), dispatch: vi.fn(() => new Promise<{ accepted: boolean; message: string }>(resolve => { resolveDispatch = resolve; })) };
  function Harness() { const menu = useImportedMenu(true, transport); return <PlayerOptions {...menu} query="Fly" />; }
  render(<Harness />);
  await waitFor(() => expect(screen.getByRole("switch", { name: "Fly" })).toBeEnabled());
  const toggle = screen.getByRole("switch", { name: "Fly" });
  fireEvent.click(toggle);
  expect(toggle).toHaveAttribute("aria-checked", "true");
  expect(toggle).toHaveAttribute("aria-busy", "true");
  expect(toggle).toBeDisabled();
  expect(transport.dispatch).toHaveBeenCalledTimes(1);
  await act(async () => { resolveDispatch?.({ accepted: false, message: "Entry refused; movement unchanged." }); });
  await waitFor(() => expect(toggle).toHaveAttribute("aria-checked", "false"));
  expect(screen.getByRole("alert")).toHaveTextContent("Entry refused; movement unchanged.");
});
it("routes the personal Fly switch and preserves its confirmed state and pending feedback", () => {
  const fly: ImportedMenuSnapshot = { schema: 1, sessionId: "flight-test", revision: 1, ready: true, sections: [
    { id: "DWPersonalFly", title: "Fly", items: [
      { id: "enabled", type: "checkbox", value: false, enabled: true },
      { id: "status", type: "label", label: "OFF. Shift rises; Ctrl descends." },
    ] },
  ] };
  const { dispatch, props, rerender } = setup(fly);
  const toggle = screen.getByRole("switch", { name: "Fly" });
  fireEvent.click(toggle);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWPersonalFly", itemId: "enabled", value: true });
  expect(toggle).toHaveAttribute("aria-checked", "false");
  const active = { ...fly, sections: fly.sections.map(section => ({ ...section, items: section.items.map(item => item.id === "enabled" ? { ...item, value: true } : item) })) };
  rerender(<ReferenceDashboard {...props} snapshot={active} pending pendingControl={{ sectionId: "DWPersonalFly", itemId: "enabled" }} />);
  expect(toggle).toHaveAttribute("aria-busy", "true");
  expect(toggle).toBeDisabled();
  rerender(<ReferenceDashboard {...props} snapshot={active} />);
  fireEvent.click(toggle);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWPersonalFly", itemId: "enabled", value: false });
});
const snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "test-game", revision: 1, ready: true, sections: [
  { id: "DWCorePlayer", title: "Player", items: [{ id: "god", type: "checkbox", value: false }, { id: "health", type: "meter", value: { percent: .5, text: "50 / 100" } }] },
  { id: "DWCooldownControl", title: "Cooldown", items: [{ id: "enabled", type: "checkbox", value: true }] },
  { id: "DWCurrency", title: "Coins", items: [{ id: "amount", type: "number", value: 100, min: 1, max: 1000 }, { type: "row", items: [{ id: "add", type: "button" }] }] },
  { id: "DWCoreTeleport", title: "Locations", items: [{ id: "name", type: "input", value: "" }, { id: "save", type: "button" }, { id: "destination", type: "dropdown", options: [{ label: "Camp", value: "camp" }], value: "camp" }, { id: "teleport", type: "button" }] },
] };
function setup(next = snapshot) { const dispatch = vi.fn(async () => {}); const open = vi.fn(); const props = { snapshot: next, dispatch, open, disabled: false, pending: false, query: "" }; return { ...render(<ReferenceDashboard {...props} />), dispatch, open, props }; }
it("maps speed to native half-step selection and clears an unsent draft on session change", () => {
  const native: ImportedMenuSnapshot = { ...snapshot, sections: [...snapshot.sections, { id: "DWSpeed", title: "Movement speed", items: [
    { id: "multiplier", type: "number", value: 1 }, { id: "restore", type: "button" },
  ] }] };
  const { props, rerender, dispatch } = setup(native);
  const slider = screen.getByRole("slider", { name: "Speed Multiplier" });
  expect(slider).toBeEnabled();
  fireEvent.change(slider, { target: { value: "1.5" } }); fireEvent.pointerUp(slider);
  expect(dispatch).toHaveBeenCalledExactlyOnceWith({ action: "set", sectionId: "DWSpeed", itemId: "multiplier", value: 1.5 });
  fireEvent.change(slider, { target: { value: "3" } });
  rerender(<ReferenceDashboard {...props} snapshot={{ ...native, sessionId: "next-session" }} />);
  expect(screen.getByRole("slider", { name: "Speed Multiplier" })).toHaveValue("1");
  expect(dispatch).toHaveBeenCalledTimes(1);
});
const MOVEMENT_SECTIONS: ImportedMenuSnapshot["sections"] = [
  { id: "DWSuperJump", title: "Super Jump", items: [{ id: "enabled", type: "checkbox", value: false, enabled: true }] },
  { id: "DWNoClip", title: "No Clip", items: [{ id: "enabled", type: "checkbox", value: false, enabled: true }] },
  { id: "DWPersonalFly", title: "Fly", items: [
    { id: "enabled", type: "checkbox", value: false, enabled: true },
    { id: "status", type: "label", label: "OFF. WASD moves." },
  ] },
  { id: "DWSpeed", title: "Movement speed", items: [
    { id: "multiplier", type: "number", value: 1 }, { id: "restore", type: "button" },
    { id: "status", type: "label", label: "Normal speed verified" },
  ] },
];
it("keeps the movement controls in one labeled block with Fly beside the speed slider", () => {
  setup({ ...snapshot, sections: [...snapshot.sections, ...MOVEMENT_SECTIONS] });
  const block = screen.getByRole("region", { name: "Movement controls" });
  const fly = screen.getByRole("switch", { name: "Fly" });
  const speed = screen.getByRole("slider", { name: "Speed Multiplier" });
  const flyGroup = fly.closest(".dashboard-option-group");
  const speedGroup = speed.closest(".dashboard-option-group");
  expect(flyGroup).not.toBeNull();
  // Fly and the speed slider are the two cells of one flight row, so no window width
  // and no column count can put the slider on a row of its own away from Fly.
  expect(flyGroup).toHaveClass("dashboard-option-group");
  expect(flyGroup?.parentElement).toHaveClass("player-flight-row");
  expect(speedGroup?.parentElement).toBe(flyGroup?.parentElement);
  expect(speedGroup?.previousElementSibling).toBe(flyGroup);
  expect(fly.compareDocumentPosition(speed) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  // The whole movement set, with its switches and slider, is
  // inside that one block rather than loose rows elsewhere in the card.
  expect(block).toContainElement(flyGroup as HTMLElement | null);
  expect(block).toContainElement(speedGroup as HTMLElement | null);
  expect(block).toContainElement(screen.getByRole("switch", { name: "Super Jump" }));
  expect(block).toContainElement(screen.getByRole("switch", { name: "No Clip" }));
  expect(within(block).queryByRole("button", { name: "Restore normal movement speed" })).not.toBeInTheDocument();
  expect(within(block).queryByText("Normal speed verified")).not.toBeInTheDocument();
  expect(block.querySelector(".player-movement-heading")).toHaveTextContent("Movement");
});
it("keeps the movement block searchable and hides it when nothing matches", () => {
  const dispatch = vi.fn(async () => {});
  const props = { snapshot: { ...snapshot, sections: [...snapshot.sections, ...MOVEMENT_SECTIONS] }, dispatch, disabled: false, pending: false };
  const { container, rerender } = render(<PlayerMovementControls {...props} query="" />);
  const block = screen.getByRole("region", { name: "Movement controls" });
  for (const label of ["Super Jump", "No Clip", "Fly"]) expect(within(block).getByRole("switch", { name: label })).toBeVisible();
  expect(within(block).getByRole("slider", { name: "Speed Multiplier" })).toBeVisible();
  expect(container.querySelectorAll(".player-movement-controls")).toHaveLength(1);
  rerender(<PlayerMovementControls {...props} query="speed" />);
  expect(screen.queryByRole("switch", { name: "No Clip" })).not.toBeInTheDocument();
  expect(screen.queryByRole("switch", { name: "Super Jump" })).not.toBeInTheDocument();
  expect(screen.getByRole("slider", { name: "Speed Multiplier" })).toBeVisible();
  rerender(<PlayerMovementControls {...props} query="fly" />);
  expect(screen.getByRole("switch", { name: "Fly" })).toBeVisible();
  expect(screen.queryByRole("slider", { name: "Speed Multiplier" })).not.toBeInTheDocument();
  rerender(<PlayerMovementControls {...props} query="__nothing_matches__" />);
  expect(container.querySelector(".player-movement-controls")).toBeNull();
});
it("maps native XP multiplier and recovery without duplicate cards or fake fallback", () => {
  const native: ImportedMenuSnapshot = { ...snapshot, sections: [...snapshot.sections, { id: "DWXPRewards", title: "XP rewards", items: [
    { id: "multiplier", type: "number", label: "Quest & combat XP rewards", min: 1, max: 5, step: 1, value: 1, enabled: false },
    { id: "refresh", type: "button", label: "Read XP rewards" },
    { id: "restore", type: "button", label: "Restore XP rewards" },
    { id: "owned", type: "checkbox", label: "Recovery pending", value: true },
    { id: "status", type: "label", label: "Restore is required" },
  ] }] };
  const { props, dispatch, rerender } = setup(native);
  expect(screen.getByRole("spinbutton", { name: "Quest & combat XP rewards" })).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Restore XP rewards" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWXPRewards", itemId: "restore" });
  fireEvent.click(screen.getByRole("button", { name: "Read XP rewards" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWXPRewards", itemId: "refresh" });
  const ready = { ...native, sections: native.sections.map(section => ({ ...section, items: section.items.map(item => item.id === "multiplier" ? { ...item, enabled: true } : item) })) };
  rerender(<><ReferenceDashboard {...props} snapshot={ready} /><ImportedMenuPanel {...props} snapshot={ready} category="player" /></>);
  const target = screen.getByRole("spinbutton", { name: "Quest & combat XP rewards" });
  fireEvent.focus(target); fireEvent.change(target, { target: { value: "2" } }); fireEvent.blur(target);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWXPRewards", itemId: "multiplier", value: 2 });
  expect(screen.getAllByRole("button", { name: "Restore XP rewards" })).toHaveLength(1);
  rerender(<ReferenceDashboard {...props} snapshot={snapshot} />);
  expect(screen.getByRole("slider", { name: "Experience Multiplier" })).toBeDisabled();
});
it("uses real Corruption controls once and retains raw charge controls separately", () => {
  const native: ImportedMenuSnapshot = { ...snapshot, sections: [...snapshot.sections, { id: "DWMutation", title: "Corruption", items: [
    { id: "status", type: "label", label: "Corruption level: 0    Raw charge value: 0.00" },
    { id: "level", type: "number", label: "Corruption level", value: 1, min: 1, max: 15 },
    { id: "setLevel", type: "button", label: "Set exact Corruption level" },
    { id: "refresh", type: "button", label: "Refresh corruption status" },
    { id: "amount", type: "number", label: "Raw charges", value: 1 },
  ] }] };
  const { props, dispatch, rerender } = setup(native);
  expect(screen.queryByText("Humanity")).not.toBeInTheDocument();
  const target = screen.getByRole("spinbutton", { name: "Corruption level" });
  fireEvent.focus(target); fireEvent.change(target, { target: { value: "2" } }); fireEvent.blur(target);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWMutation", itemId: "level", value: 2 });
  fireEvent.click(screen.getByRole("button", { name: "Set exact Corruption level" }));
  // Only invokes the native control; the existing native confirmation owns apply.
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWMutation", itemId: "setLevel" });
  rerender(<><ReferenceDashboard {...props} /><ImportedMenuPanel {...props} category="player" corruptionAdvancedOnly /></>);
  expect(screen.getAllByRole("spinbutton", { name: "Corruption level" })).toHaveLength(1);
  expect(screen.getAllByRole("button", { name: "Set exact Corruption level" })).toHaveLength(1);
  expect(screen.getByRole("spinbutton", { name: "Raw charges" })).toBeVisible();
  expect(within(screen.getByLabelText("Corruption status")).getByText(/Corruption level: 0/)).toBeVisible();
});
it("verifies published movement controls before enabling and preserves scoped errors", () => {
  const sections = ["DWNoClip", "DWSuperJump"].map(id => ({ id, title: id, items: [
    { id: "enabled", type: "checkbox" as const, value: false, enabled: false },
    { id: "refresh", type: "button" as const, label: `Verify ${id}` },
    { id: "status", type: "label" as const, label: "Verify first" },
  ] }));
  const native = { ...snapshot, sections: [...snapshot.sections, ...sections] };
  const { props, rerender, dispatch } = setup(native);
  expect(screen.getByText("WASD moves · Space rises · Q descends. OFF returns to the starting position.")).toBeVisible();
  for (const [id, label] of [["DWNoClip", "No Clip"], ["DWSuperJump", "Super Jump"]]) {
    expect(screen.getByRole("switch", { name: label })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: `Verify ${id}` }));
    expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: id, itemId: "refresh" });
  }
  const verified = { ...native, sections: native.sections.map(section => ({ ...section, items: section.items.map(item => item.id === "enabled" ? { ...item, enabled: true } : item) })) };
  rerender(<ReferenceDashboard {...props} snapshot={verified} />);
  for (const [id, label] of [["DWNoClip", "No Clip"], ["DWSuperJump", "Super Jump"]]) {
    fireEvent.click(screen.getByRole("switch", { name: label }));
    expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: id, itemId: "enabled", value: true });
    expect(screen.getByRole("switch", { name: label })).toHaveAttribute("aria-checked", "false");
  }
  rerender(<ReferenceDashboard {...props} feedback={{ sectionId: "DWNoClip", message: "Return position could not be restored" }} />);
  expect(screen.getAllByText("Return position could not be restored").length).toBeGreaterThan(0);
  rerender(<ReferenceDashboard {...props} snapshot={snapshot} />);
  expect(screen.getByRole("switch", { name: "No Clip" })).toBeDisabled();
  expect(screen.getByRole("switch", { name: "Super Jump" })).toBeDisabled();
});
it("does not display catalog zero as a blood reading while disconnected or unread", () => {
  const unread = { ...snapshot, sections: [{ id: "DWCorePlayer", title: "Player", items: [
    { id: "bloodPercent", type: "number" as const, value: 0, enabled: false },
    { id: "blood", type: "meter" as const, value: { percent: 0, text: "Unread" } },
  ] }] };
  const { props, rerender } = setup({ ...unread, ready: false });
  expect(screen.queryByText("0%")).not.toBeInTheDocument();
  rerender(<ReferenceDashboard {...props} snapshot={unread} />);
  expect(screen.queryByText("0%")).not.toBeInTheDocument();
  const lockedReadback = { ...unread, sections: [{ ...unread.sections[0], items: [
    { id: "bloodPercent", type: "number" as const, value: 40, enabled: false },
    { id: "blood", type: "meter" as const, value: { percent: .4, text: "0.4" } },
  ] }] };
  rerender(<ReferenceDashboard {...props} snapshot={lockedReadback} />);
  expect(screen.getAllByText("40%")).toHaveLength(2);
  expect(document.querySelector(".dashboard-resource-blood output")).toHaveTextContent("40%");
  expect(screen.getByRole("slider", { name: "Blood Energy" })).toBeDisabled();
});
it("commits native blood percentage once per gesture and respects native lock availability", () => {
  const native = { ...snapshot, sections: snapshot.sections.map(section => section.id === "DWCorePlayer" ? { ...section, items: [...section.items, { id: "bloodPercent", type: "number" as const, value: 87.719298245614, enabled: true }] } : section) };
  const { props, rerender, dispatch } = setup(native);
  const slider = screen.getByRole("slider", { name: "Blood Energy" });
  fireEvent.change(slider, { target: { value: "25" } });
  expect(dispatch).not.toHaveBeenCalled();
  fireEvent.pointerUp(slider);
  fireEvent.blur(slider);
  expect(dispatch).toHaveBeenCalledTimes(1);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCorePlayer", itemId: "bloodPercent", value: 25 });
  expect(slider).toHaveValue("87.719298245614");
  expect(slider.closest("label")?.querySelector("output")).toHaveTextContent("88%");
  fireEvent.change(slider, { target: { value: "45" } });
  fireEvent.keyUp(slider, { key: "ArrowRight" });
  expect(dispatch).toHaveBeenCalledTimes(2);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCorePlayer", itemId: "bloodPercent", value: 45 });
  const locked = { ...native, sections: native.sections.map(section => ({ ...section, items: section.items.map(item => item.id === "bloodPercent" ? { ...item, enabled: false } : item) })) };
  rerender(<ReferenceDashboard {...props} snapshot={locked} />);
  expect(screen.getByRole("slider", { name: "Blood Energy" })).toBeDisabled();
  rerender(<ReferenceDashboard {...props} snapshot={snapshot} />);
  expect(screen.getByRole("slider", { name: "Blood Energy" })).toBeDisabled();
});
it("exposes native resource readback and owned blood recovery without guessing support", () => {
  const native = { ...snapshot, sections: [...snapshot.sections.filter(section => section.id !== "DWCorePlayer"), { id: "DWCorePlayer", title: "Player", items: [
    { id: "bloodPercent", type: "number" as const, value: 0, enabled: false },
    { id: "refresh", type: "button" as const, enabled: true },
    { id: "bloodRecovery", type: "checkbox" as const, value: true, enabled: true },
  ] }] };
  const { dispatch } = setup(native);
  fireEvent.click(screen.getByRole("button", { name: "Read blood amount" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWCorePlayer", itemId: "refresh" });
  fireEvent.click(screen.getByRole("button", { name: "Restore Blood Energy" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCorePlayer", itemId: "bloodRecovery", value: false });
});
it("uses independent native health only when published and waits for acknowledged state", () => {
  const native = { ...snapshot, sections: snapshot.sections.map(section => section.id === "DWCorePlayer" ? { ...section, items: [...section.items, { id: "healthEnabled", type: "checkbox" as const, value: false }] } : section) };
  const { props, rerender, dispatch } = setup(native);
  fireEvent.click(screen.getByRole("switch", { name: "Infinite Health" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCorePlayer", itemId: "healthEnabled", value: true });
  expect(screen.getByRole("switch", { name: "Infinite Health" })).toHaveAttribute("aria-checked", "false");
  rerender(<ReferenceDashboard {...props} pending pendingControl={{ sectionId: "DWCorePlayer", itemId: "healthEnabled" }} />);
  expect(screen.getByRole("switch", { name: "Infinite Health" })).toBeDisabled();
  rerender(<ReferenceDashboard {...props} snapshot={snapshot} />);
  expect(screen.getByRole("switch", { name: "Infinite Health" })).toBeDisabled();
  fireEvent.click(screen.getByRole("switch", { name: "Infinite Health" }));
  expect(dispatch).toHaveBeenCalledTimes(1);
});
it("keeps native player status and its actions in the Player sidebar and off the other categories", () => {
  const next: ImportedMenuSnapshot = { ...snapshot, sections: [...snapshot.sections, { id: "DWPlayer", title: "Player Status", items: [
    { id: "health", type: "meter", label: "Health", value: { percent: .5, text: "50 / 100" } },
    { id: "stamina", type: "button", label: "Refill stamina now" },
    { id: "refresh", type: "button", label: "Refresh status" },
  ] }] };
  const { container, props, rerender, dispatch } = setup(next);
  for (const category of ["world", "inventory", "teleport", "visuals", "quests", "settings"]) {
    rerender(<ReferenceDashboard {...props} category={category} />);
    // Player Info belongs to the Player tab; other categories take the full width.
    expect(container.querySelector(".dashboard-sidebar")).not.toBeInTheDocument();
    expect(container.querySelector("[data-imported-section=DWPlayer]")).not.toBeInTheDocument();
    expect(screen.queryByText("50 / 100")).not.toBeInTheDocument();
  }
  rerender(<ReferenceDashboard {...props} category="player" />);
  expect(container.querySelectorAll(".dashboard-sidebar [data-imported-section=DWPlayer]")).toHaveLength(1);
  expect(container.querySelector(".dashboard-main [data-imported-section=DWPlayer]")).not.toBeInTheDocument();
  expect(screen.getAllByText("50 / 100")).toHaveLength(1);
  const sidebar = within(container.querySelector(".dashboard-sidebar") as HTMLElement);
  fireEvent.click(sidebar.getByRole("button", { name: "Refill stamina now" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWPlayer", itemId: "stamina" });
  fireEvent.click(sidebar.getByRole("button", { name: "Refresh status" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWPlayer", itemId: "refresh" });
  rerender(<ReferenceDashboard {...props} feedback={{ sectionId: "DWPlayer", message: "Refresh failed" }} />);
  expect(sidebar.getByRole("alert")).toHaveTextContent("Refresh failed");
});
it("renders only runtime-backed groups and never dispatches from a disconnected control", () => {
  const { container, dispatch } = setup();
  // Player, Combat, World, Inventory, Teleport. The NPC card held nothing but
  // unimplemented controls, so it is gone; the NPC tab still explains why.
  expect(container.querySelectorAll(".dashboard-main > .dashboard-card")).toHaveLength(5);
  // Player Info and Location. Quick Spawn was four unimplemented buttons.
  expect(container.querySelectorAll(".dashboard-sidebar > .dashboard-card")).toHaveLength(2);
  // Nothing advertises itself as a placeholder any more.
  expect(container.querySelectorAll("[title*='placeholder']")).toHaveLength(0);
  expect(container.querySelectorAll(".dashboard-placeholder-mark")).toHaveLength(0);
  for (const control of container.querySelectorAll<HTMLElement>(".dashboard-main button:disabled, .dashboard-main input:disabled, .dashboard-main select:disabled")) {
    fireEvent.click(control);
  }
  expect(dispatch).not.toHaveBeenCalled();
  expect(screen.getByText("50 / 100")).toBeInTheDocument();
  expect(screen.queryByText("10000 / 10000")).not.toBeInTheDocument();
});
it("dispatches exact real actions and follows acknowledged switch state", () => {
  const { dispatch } = setup();
  fireEvent.click(screen.getByRole("switch", { name: "God Mode" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCorePlayer", itemId: "god", value: true });
  expect(screen.getByRole("switch", { name: "God Mode" })).toHaveAttribute("aria-checked", "false");
  fireEvent.click(screen.getByRole("switch", { name: "No Cooldowns" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCooldownControl", itemId: "enabled", value: false });
  fireEvent.click(screen.getByRole("button", { name: "Increase Gold amount" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCurrency", itemId: "amount", value: 101 });
});
it("requires native saved-name acknowledgment before enabling Save", () => {
  const { dispatch, props, rerender } = setup();
  const input = screen.getByRole("textbox", { name: "New saved location name" });
  fireEvent.change(input, { target: { value: "Camp" } });
  expect(screen.getByRole("button", { name: /^Save$/ })).toBeDisabled();
  fireEvent.blur(input);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCoreTeleport", itemId: "name", value: "Camp" });
  const acknowledged = structuredClone(snapshot);
  acknowledged.sections[3].items[0].value = "Camp";
  rerender(<ReferenceDashboard {...props} snapshot={acknowledged} />);
  fireEvent.click(screen.getByRole("button", { name: /^Save$/ }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWCoreTeleport", itemId: "save" });
});
it("keeps all category workflows accessible and blocks disconnected mutation", () => {
  const { open, dispatch } = setup({ ...snapshot, ready: false });
  fireEvent.click(screen.getByRole("button", { name: "All Player controls" }));
  expect(open).toHaveBeenCalledWith("player");
  fireEvent.click(screen.getByRole("button", { name: "All World controls" }));
  expect(open).toHaveBeenCalledWith("world");
  expect(screen.getByRole("switch", { name: "God Mode" })).toBeDisabled();
  fireEvent.click(screen.getByRole("switch", { name: "God Mode" }));
  expect(dispatch).not.toHaveBeenCalled();
  expect(screen.queryByText("50 / 100")).not.toBeInTheDocument();
});

it("commits gold typing once on blur and waits for the native amount before Add", () => {
  const { dispatch, container } = setup();
  const input = screen.getByRole("spinbutton", { name: "Gold amount" });
  fireEvent.focus(input);
  fireEvent.change(input, { target: { value: "250" } });
  expect(dispatch).not.toHaveBeenCalled();
  expect(container.querySelector(".dashboard-gold .dashboard-action")).toBeDisabled();
  fireEvent.blur(input);
  expect(dispatch).toHaveBeenCalledExactlyOnceWith({ action: "set", sectionId: "DWCurrency", itemId: "amount", value: 250 });
  expect(container.querySelector(".dashboard-gold .dashboard-action")).toBeDisabled();
});

it("preserves category content without duplicate overview actions or invented controls", () => {
  const { props, rerender, dispatch, container } = setup();
  expect(container.querySelector(".dashboard-sidebar")).toBeInTheDocument();
  rerender(<ReferenceDashboard {...props} category="inventory"><button onClick={() => void dispatch()}>Actual inventory action</button></ReferenceDashboard>);
  // Inventory has no Player Info sidebar; it gets the full width for its own controls.
  expect(container.querySelector(".dashboard-sidebar")).not.toBeInTheDocument();
  expect(screen.queryByRole("switch", { name: "God Mode" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /^Add$/ })).not.toBeInTheDocument();
  // Unlimited Weight, No Durability Loss and the rest of the invented inventory
  // controls are no longer rendered at all.
  for (const label of ["Unlimited Weight", "No Durability Loss", "Add Red Essence", "Add All Crafting Materials"]) {
    expect(screen.queryByRole("switch", { name: label })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: label })).not.toBeInTheDocument();
  }
  expect(dispatch).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "Actual inventory action" }));
  expect(dispatch).toHaveBeenCalledTimes(1);
  rerender(<ReferenceDashboard {...props} />);
  expect(container.querySelector(".dashboard-sidebar")).toBeInTheDocument();
  expect(container.querySelectorAll(".dashboard-main > .dashboard-card")).toHaveLength(5);
});

const REFERENCE_SECTIONS: ImportedMenuSnapshot["sections"] = [
  { id: "DWActivationControl", title: "✦ Activation Charges", items: [
    { id: "enabled", type: "checkbox", value: false, enabled: true },
    { id: "status", type: "label", label: "Activation charge refill: OFF" },
  ] },
  { id: "DWCooldownControl", title: "☆ Ability Cooldowns", items: [
    { id: "enabled", type: "checkbox", value: true, enabled: true },
    { id: "status", type: "label", label: "Cooldown reset: ON" },
  ] },
  { id: "DWCrafting", title: "Crafting", items: [
    { id: "status", type: "label", label: "available recipes: 44." },
    { id: "unlock", type: "button", label: "Unlock all crafting recipes" },
  ] },
  // Carry weight has a documented route but no authorized setter yet, so the section
  // publishes the read-only check the Player controls row runs.
  { id: "DWWeight", title: "Carry weight", items: [
    { id: "status", type: "label", label: "Run the read-only check to see the live capacity state." },
    { id: "probe", type: "button", label: "Run read-only carry-weight check" },
  ] },
];
const REFERENCE_SNAPSHOT: ImportedMenuSnapshot = { schema: 1, sessionId: "reference", revision: 1, ready: true, sections: REFERENCE_SECTIONS };
function referenceProps(query = "") {
  const dispatch = vi.fn(async () => {});
  return { dispatch, props: { query, snapshot: REFERENCE_SNAPSHOT, disabled: false, pending: false, dispatch } };
}
it("draws the requested ability and item rows and wires only the controls with a native route", () => {
  const { dispatch, props } = referenceProps();
  render(<PlayerReferenceControls {...props} />);
  expect(screen.getByRole("heading", { name: "Abilities" })).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Items & crafting" })).toBeInTheDocument();
  const activation = screen.getByRole("switch", { name: "Unlimited Activation Charge" });
  expect(activation).toHaveAttribute("aria-checked", "false");
  expect(activation.closest(".dashboard-row")?.querySelector(".player-toggle-state")).toBeNull();
  fireEvent.click(activation);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWActivationControl", itemId: "enabled", value: true });
  const cooldown = screen.getByRole("switch", { name: "Instant Ability Cooldown" });
  expect(cooldown).toHaveAttribute("aria-checked", "true");
  fireEvent.click(cooldown);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWCooldownControl", itemId: "enabled", value: false });
  // The crafting unlock keeps its section and its confirmation contract; only the label
  // and the home changed.
  fireEvent.click(screen.getByRole("button", { name: "Unlock" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWCrafting", itemId: "unlock" });
  expect(dispatch).toHaveBeenCalledTimes(3);
});
it("keeps every control with no verified route disabled and says why on the row", () => {
  const { dispatch, props } = referenceProps();
  render(<PlayerReferenceControls {...props} />);
  for (const label of ["Super Damage / One-Hit Kills", "Unlimited Consumables", "Ignore Crafting Requirement"]) {
    const control = screen.getByRole("switch", { name: label });
    expect(control).toBeDisabled();
    expect(control.closest(".dashboard-row")).toHaveAttribute("title", expect.stringContaining(label));
    fireEvent.click(control);
  }
  expect(screen.getByRole("button", { name: "Increase Edit Item Amount" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Decrease Edit Item Amount" })).toBeDisabled();
  expect(dispatch).not.toHaveBeenCalled();
});
it("runs the read-only carry-weight check instead of offering a weight switch", () => {
  const { dispatch, props } = referenceProps();
  render(<PlayerReferenceControls {...props} />);
  // No switch: the capacity setter is not authorized until the check passes in the game.
  expect(screen.queryByRole("switch", { name: "Zero Weight" })).not.toBeInTheDocument();
  const check = screen.getByRole("button", { name: "Run check" });
  expect(check).toBeEnabled();
  expect(check.closest(".dashboard-option-group")).toHaveTextContent("Run the read-only check to see the live capacity state.");
  fireEvent.click(check);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWWeight", itemId: "probe" });
});
it("offers the Zero Weight switch once the running mod publishes it, next to the check", () => {
  const dispatch = vi.fn(async () => {});
  const sections = REFERENCE_SNAPSHOT.sections.map(section => section.id !== "DWWeight" ? section : { ...section, items: [
    ...section.items, { id: "zeroWeight", type: "checkbox" as const, label: "Zero weight (no carry limit)", value: false },
  ] });
  render(<PlayerReferenceControls query="" snapshot={{ ...REFERENCE_SNAPSHOT, sections }} disabled={false} pending={false} dispatch={dispatch} />);
  const zero = screen.getByRole("switch", { name: "Zero Weight" });
  expect(zero).toBeEnabled();
  expect(zero).toHaveAttribute("aria-checked", "false");
  fireEvent.click(zero);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWWeight", itemId: "zeroWeight", value: true });
  // The read-only check stays available beside the switch.
  fireEvent.click(screen.getByRole("button", { name: "Run check" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "invoke", sectionId: "DWWeight", itemId: "probe" });
});
it("offers the Super Damage switch and its multiplier once the running mod publishes them", () => {
  const dispatch = vi.fn(async () => {});
  const sections = [...REFERENCE_SNAPSHOT.sections, { id: "DWSuperDamage", title: "Super damage", items: [
    { id: "status", type: "label" as const, label: "Off." },
    { id: "enabled", type: "checkbox" as const, label: "Super damage / one-hit kills", value: false },
    { id: "multiplier", type: "number" as const, label: "Damage multiplier", value: 100, min: 2, max: 1000, step: 1 },
  ] }];
  render(<PlayerReferenceControls query="" snapshot={{ ...REFERENCE_SNAPSHOT, sections }} disabled={false} pending={false} dispatch={dispatch} />);
  const damage = screen.getByRole("switch", { name: "Super Damage / One-Hit Kills" });
  expect(damage).toBeEnabled();
  fireEvent.click(damage);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWSuperDamage", itemId: "enabled", value: true });
  const multiplier = screen.getByRole("spinbutton", { name: "Damage multiplier" });
  expect(multiplier).toHaveValue(100);
  fireEvent.focus(multiplier);
  fireEvent.change(multiplier, { target: { value: "1000" } });
  fireEvent.blur(multiplier);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWSuperDamage", itemId: "multiplier", value: 1000 });
});
it("keeps Super Damage and Ignore Crafting Requirement as explained placeholders on an older payload", () => {
  render(<PlayerReferenceControls query="" snapshot={REFERENCE_SNAPSHOT} disabled={false} pending={false} dispatch={vi.fn(async () => {})} />);
  expect(screen.getByRole("switch", { name: "Super Damage / One-Hit Kills" })).toBeDisabled();
  expect(screen.getByRole("switch", { name: "Ignore Crafting Requirement" })).toBeDisabled();
  expect(screen.getByText(/has not published its super-damage switch/)).toBeInTheDocument();
  expect(screen.getByText(/has not published its free-crafting switch/)).toBeInTheDocument();
});
it("offers the Ignore Crafting Requirement switch once the running mod publishes it", () => {
  const dispatch = vi.fn(async () => {});
  const sections = [...REFERENCE_SNAPSHOT.sections, { id: "DWFreeCrafting", title: "Free crafting", items: [
    { id: "status", type: "label" as const, label: "Ignore crafting requirement OFF." },
    { id: "enabled", type: "checkbox" as const, label: "Ignore crafting requirement", value: false },
  ] }];
  render(<PlayerReferenceControls query="" snapshot={{ ...REFERENCE_SNAPSHOT, sections }} disabled={false} pending={false} dispatch={dispatch} />);
  const crafting = screen.getByRole("switch", { name: "Ignore Crafting Requirement" });
  expect(crafting).toBeEnabled();
  fireEvent.click(crafting);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWFreeCrafting", itemId: "enabled", value: true });
  expect(screen.getByText("Ignore crafting requirement OFF.")).toBeInTheDocument();
});
it("renders the Extended Parry Window switch and multiplier only when the mod publishes it", () => {
  const dispatch = vi.fn(async () => {});
  const { unmount } = render(<PlayerParryWindow snapshot={REFERENCE_SNAPSHOT} disabled={false} pending={false} dispatch={dispatch} />);
  expect(screen.queryByRole("switch", { name: "Extended Parry Window" })).toBeNull();
  unmount();
  const sections = [...REFERENCE_SNAPSHOT.sections, { id: "DWParryWindow", title: "Extended parry window", items: [
    { id: "status", type: "label" as const, label: "Off." },
    { id: "enabled", type: "checkbox" as const, label: "Extended parry window", value: false },
    { id: "multiplier", type: "number" as const, label: "Multiplier", value: 2, min: 2, max: 5, step: 1 },
  ] }];
  render(<PlayerParryWindow snapshot={{ ...REFERENCE_SNAPSHOT, sections }} disabled={false} pending={false} dispatch={dispatch} />);
  fireEvent.click(screen.getByRole("switch", { name: "Extended Parry Window" }));
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWParryWindow", itemId: "enabled", value: true });
  const multiplier = screen.getByRole("spinbutton", { name: "Parry window multiplier" });
  fireEvent.focus(multiplier);
  fireEvent.change(multiplier, { target: { value: "3" } });
  fireEvent.blur(multiplier);
  expect(dispatch).toHaveBeenLastCalledWith({ action: "set", sectionId: "DWParryWindow", itemId: "multiplier", value: 3 });
});
it("shows the carry-weight check busy while the game is answering it", () => {
  const dispatch = vi.fn(async () => {});
  render(<PlayerReferenceControls query="" snapshot={{ ...REFERENCE_SNAPSHOT, operation: { id: "operation-1", status: "running" } }} disabled={false} pending pendingControl={{ sectionId: "DWWeight", itemId: "probe" }} dispatch={dispatch} />);
  const check = screen.getByRole("button", { name: "Running…" });
  expect(check).toBeDisabled();
  expect(check).toHaveAttribute("aria-busy", "true");
});
it("names the requested state at once on a pending switch row and never says Applying", () => {
  const dispatch = vi.fn(async () => {});
  render(<PlayerReferenceControls query="" snapshot={REFERENCE_SNAPSHOT} disabled={false} pending pendingControl={{ sectionId: "DWActivationControl", itemId: "enabled" }} dispatch={dispatch} />);
  const row = screen.getByRole("switch", { name: "Unlimited Activation Charge" }).closest(".dashboard-row") as HTMLElement;
  expect(screen.getByRole("switch", { name: "Unlimited Activation Charge" })).toHaveAttribute("aria-busy", "true");
  expect(row.querySelector(".player-toggle-state")).toBeNull();
  expect(screen.getByRole("switch", { name: "Unlimited Activation Charge" })).toHaveAttribute("aria-checked", "false");
  expect(row).not.toHaveTextContent("Applying");
});
it("shows only the reference control a search names", () => {
  const { props } = referenceProps("Zero Weight");
  render(<PlayerReferenceControls {...props} />);
  expect(screen.getByText("Zero Weight")).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Items & crafting" })).toBeInTheDocument();
  expect(screen.queryByText("Unlimited Consumables")).not.toBeInTheDocument();
  expect(screen.queryByRole("switch", { name: "Unlimited Activation Charge" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Abilities" })).not.toBeInTheDocument();
});
it("renders nothing when the search names none of the reference controls", () => {
  const { props } = referenceProps("god mode");
  const { container } = render(<PlayerReferenceControls {...props} />);
  expect(container).toBeEmptyDOMElement();
});
