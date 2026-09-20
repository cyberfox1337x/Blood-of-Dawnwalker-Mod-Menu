import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import importedCatalog from "../integration/imported-menu/catalog.json";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
import { CONTROL_CAPABILITIES, RENDERER_GAMEPLAY_CAPABILITIES } from "./gameplayControls";
import {
  GAMEPLAY_CAPABILITIES,
  type CommandValue,
  type GameplayCapability,
  type RuntimeCommand,
  type RuntimeInfo,
  type RuntimeResult,
} from "./runtimeContract";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_app_tests");

const disconnectedRuntime: RuntimeInfo = {
  platform: "test",
  mode: "disconnected",
  connected: false,
  gameRunning: false,
  buildVerified: false,
  interactionEligible: false,
  capabilities: [],
  activeCapabilities: [],
};

let gameplayHotkeyListener: ((action: "add-gold") => void) | undefined;

function verifiedRuntime(capabilities: readonly GameplayCapability[]): RuntimeInfo {
  return {
    platform: "test",
    mode: "live-offline",
    connected: true,
    gameRunning: true,
    buildVerified: true,
    interactionEligible: true,
    sessionId: "test-boot-1",
    capabilities,
    activeCapabilities: [],
  };
}

function appliedResult(command: RuntimeCommand, message: string, readback?: CommandValue): RuntimeResult {
  return {
    accepted: true,
    capability: command.capability,
    requestId: command.requestId,
    status: "applied",
    message,
    ...(readback === undefined ? {} : { readback }),
  };
}

function dispatchPointerEvent(
  target: Element,
  type: "pointerdown" | "pointermove" | "pointerup",
  properties: Readonly<{ button: number; buttons: number; pointerId: number; screenX: number; screenY: number }>,
): void {
  const pointerEvent = new Event(type, { bubbles: true, cancelable: true });
  for (const [propertyName, propertyValue] of Object.entries(properties)) {
    Object.defineProperty(pointerEvent, propertyName, { value: propertyValue });
  }
  fireEvent(target, pointerEvent);
}

function installBridge(
  runtimeInfo: RuntimeInfo,
  dispatch: (command: RuntimeCommand) => Promise<RuntimeResult> = async (command) => ({
    accepted: false,
    capability: command.capability,
    requestId: command.requestId,
    status: "rejected",
    message: "The verified Dawnwalker offline runtime bridge is not connected.",
  }),
) {
  const dispatchMock = vi.fn(dispatch);
  gameplayHotkeyListener = undefined;
  window.dawnwalkerDesktop = {
    beginWindowDrag: vi.fn(),
    updateWindowDrag: vi.fn(),
    endWindowDrag: vi.fn(),
    minimizeWindow: vi.fn(),
    toggleMaximizeWindow: vi.fn(),
    isWindowMaximized: vi.fn(async () => false),
    closeWindow: vi.fn(),
    onGameplayHotkey: vi.fn((listener) => {
      gameplayHotkeyListener = listener;
      return () => {
        if (gameplayHotkeyListener === listener) gameplayHotkeyListener = undefined;
      };
    }),
    getRuntimeInfo: vi.fn(async () => runtimeInfo),
    dispatch: dispatchMock,
  };
  return dispatchMock;
}

function installImportedMenu(sections: { id: string; title: string; items: never[] }[]): void {
  window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
    state: vi.fn(async () => ({ schema: 1 as const, sessionId: "test-imported", revision: 1, ready: false, sections })),
    dispatch: vi.fn(async () => ({ accepted: false, message: "Not connected." })),
  } };
}

const SUPPLIED_INVENTORY_SECTIONS = [{ id: "DWCurrency", title: "Coins", items: [] as never[] }];

function triggerGameplayHotkey(action: "add-gold"): void {
  if (!gameplayHotkeyListener) throw new Error("The gameplay hotkey listener was not registered.");
  gameplayHotkeyListener(action);
}

// Eight full category switches driven through userEvent, each with a sweep of
// cross-category assertions: ~5.5 s of real work, which does not fit vitest's 5 s
// default. The budget states what the test does rather than masking a slow render.
const NAVIGATION_SWEEP_TIMEOUT_MS = 30000;
describe("Blood of Dawnwalker menu", () => {
  it("keeps the Player Fly option reachable through search", () => {
    installBridge(disconnectedRuntime);
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.change(screen.getByRole("textbox", { name: "Search menu options" }), { target: { value: "Fly" } });
    expect(screen.getByRole("switch", { name: "Fly" })).toBeVisible();
    expect(screen.queryByText("No matching Player controls")).toBeNull();
  });
  it("keeps removed combat, unresolved contracts and respec out of Player", async () => {
    installBridge(disconnectedRuntime);
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ ...importedCatalog, ready: false } as ImportedMenuSnapshot)),
      dispatch: vi.fn(),
    } };
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await waitFor(() => expect(screen.getByRole("slider", { name: "Speed Multiplier" })).toBeInTheDocument());
    expect(screen.queryByRole("region", { name: "Unresolved combat contracts" })).not.toBeInTheDocument();
    expect(screen.queryByText(/Other combat contracts remain locked/i)).not.toBeInTheDocument();
    expect(screen.queryByText("Skill Respec", { exact: true })).not.toBeInTheDocument();
    expect(document.querySelector('[data-imported-section="DWRespec"]')).not.toBeInTheDocument();
  });
  it("preserves the supplied Player controls inside the current design after navigating away and back", async () => {
    installBridge(disconnectedRuntime);
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ ...importedCatalog, ready: false } as ImportedMenuSnapshot)),
      dispatch: vi.fn(),
    } };
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Read player level" })).toBeVisible());
    fireEvent.click(screen.getByRole("button", { name: /^World$/ }));
    fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const player = within(document.querySelector("#panel-player") as HTMLElement);
    expect(document.querySelector(".reference-dashboard")).toBeInTheDocument();
    expect(player.getByText("God Mode", { exact: true })).toBeVisible();
    expect(player.getByText("Sprint No Drain", { exact: true })).toBeVisible();
    for (const label of ["Read player level", "Apply level", "Add XP", "Set exact Corruption level", "Refresh corruption status"]) {
      expect(player.getByRole("button", { name: label })).toBeVisible();
      expect(player.getByRole("button", { name: label })).toBeDisabled();
    }
    for (const label of [/Rapid stamina refill/, /Vampire form override/]) {
      expect(player.getByRole("switch", { name: label })).toBeVisible();
      expect(player.getByRole("switch", { name: label })).toBeDisabled();
    }
    for (const label of ["Skill point amount", "Corruption level", "Corruption amount (raw units)"]) {
      expect(player.getByRole("spinbutton", { name: label })).toBeVisible();
    }
    expect(player.getByRole("combobox", { name: "Reward size" })).toBeVisible();
    expect(document.querySelectorAll('[data-imported-section="DWPlayer"] meter')).toHaveLength(3);
    for (const section of ["DWSkills", "DWXP", "DWMutation"]) {
      expect(document.querySelector(`#panel-player [data-imported-section="${section}"]`)).toHaveClass("dashboard-card");
    }
    expect(player.getAllByRole("button", { name: /^God Mode:/ })).toHaveLength(1);
    expect(document.querySelector("#panel-player [data-imported-section=DWPlayer]")).not.toBeInTheDocument();
    const sidebar = within(document.querySelector(".dashboard-sidebar") as HTMLElement);
    expect(sidebar.getByRole("button", { name: "Refill stamina now" })).toBeDisabled();
    expect(sidebar.getByRole("button", { name: "Refresh status" })).toBeDisabled();
  });
  it("reflows the frame so native zoom enlarges controls instead of cancelling itself", async () => {
    installBridge(disconnectedRuntime);
    let publish: (scale: number) => void = () => undefined;
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, interfaceScale: {
      get: async () => 100,
      set: async percent => percent,
      onChanged: listener => { publish = listener; return () => undefined; },
      onError: () => () => undefined,
    } };
    const originalWidth = window.innerWidth;
    const originalHeight = window.innerHeight;
    try {
      Object.defineProperty(window, "innerWidth", { configurable: true, value: 3344 });
      Object.defineProperty(window, "innerHeight", { configurable: true, value: 1882 });
      const view = render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
      const viewport = view.container.querySelector(".viewport") as HTMLElement;
      await waitFor(() => expect(viewport.style.getPropertyValue("--stage-scale")).toBe("2"));
      act(() => {
        // Chromium reports the viewport in CSS pixels after native 200% zoom.
        Object.defineProperty(window, "innerWidth", { configurable: true, value: 1672 });
        Object.defineProperty(window, "innerHeight", { configurable: true, value: 941 });
        publish(200);
        window.dispatchEvent(new Event("resize"));
      });
      expect(viewport.style.getPropertyValue("--stage-scale")).toBe("2");
      expect(viewport.style.getPropertyValue("--stage-width")).toBe("836px");
      expect(viewport.style.getPropertyValue("--stage-height")).toBe("470.5px");
      expect(viewport.style.getPropertyValue("--stage-left")).toBe("0px");
      expect(viewport).toHaveAttribute("data-compact", "true");
    } finally {
      Object.defineProperty(window, "innerWidth", { configurable: true, value: originalWidth });
      Object.defineProperty(window, "innerHeight", { configurable: true, value: originalHeight });
    }
  });
  it("routes Sprint No Drain to the stamina lock and clearly describes its broader scope", async () => {
    const legacy = installBridge(disconnectedRuntime);
    let enabled = false;
    const dispatch = vi.fn(async (request) => { enabled = request.value; return { accepted: true, message: "Applied" }; });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "stamina-lock-session", revision: 1, ready: true,
        sections: [{ id: "DWCorePlayer", title: "Player controls", items: [
          { type: "checkbox", id: "god", value: false },
          { type: "checkbox", id: "sprintEnabled", value: enabled },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "Player" }));
    expect(await screen.findByText("Locks stamina while enabled, including sprinting and other stamina-consuming actions.")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Sprint No Drain: off" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Sprint No Drain: on" })).toHaveAttribute("aria-pressed", "true"));
    expect(dispatch).toHaveBeenCalledWith({ sessionId: "stamina-lock-session", action: "set", sectionId: "DWCorePlayer", itemId: "sprintEnabled", value: true });
    expect(screen.getByRole("button", { name: "God Mode: off" })).toHaveAttribute("aria-pressed", "false");
    expect(legacy).not.toHaveBeenCalled();
  });
  it("gives the requested ability and item controls one home in Player controls", async () => {
    const legacy = installBridge(disconnectedRuntime);
    const dispatch = vi.fn(async () => ({ accepted: true, message: "Applied" }));
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "reference-session", revision: 1, ready: true,
        sections: [
          { id: "DWActivationControl", title: "✦ Activation Charges", items: [
            { type: "checkbox" as const, id: "enabled", value: false },
            { type: "label" as const, id: "status", label: "Activation charge refill: OFF" },
          ] },
          { id: "DWCooldownControl", title: "☆ Ability Cooldowns", items: [
            { type: "checkbox" as const, id: "enabled", value: true },
            { type: "label" as const, id: "status", label: "Cooldown reset: ON" },
          ] },
          { id: "DWCrafting", title: "Crafting", items: [
            { type: "label" as const, id: "status", label: "available recipes: 44." },
            { type: "button" as const, id: "unlock", label: "Unlock all crafting recipes" },
          ] },
          { id: "DWWeight", title: "Carry weight", items: [
            { type: "label" as const, id: "status", label: "Run the read-only check to see the live capacity state." },
            { type: "button" as const, id: "probe", label: "Run read-only carry-weight check" },
          ] },
        ] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "Player" }));
    // The placeholder renders the same label before the first poll lands, so wait for the
    // control the game actually published rather than clicking the offline stand-in.
    await waitFor(() => expect(screen.getByRole("switch", { name: "Unlimited Activation Charge" })).toBeEnabled());
    await waitFor(() => expect(screen.getByRole("button", { name: "Unlock" })).toBeEnabled());
    const activation = screen.getByRole("switch", { name: "Unlimited Activation Charge" });
    const panel = document.querySelector("#panel-player") as HTMLElement;
    // Each control keeps exactly one home. Activation Charges and Ability Cooldowns used
    // to be drawn by the Combat block, and the crafting unlock had no reachable panel at
    // all, so nothing here is a second copy of a control drawn elsewhere.
    for (const section of ["DWActivationControl", "DWCooldownControl"]) {
      expect(panel.querySelectorAll(`[data-imported-section="${section}"]`)).toHaveLength(0);
    }
    for (const label of ["Unlimited Activation Charge", "Instant Ability Cooldown", "Super Damage / One-Hit Kills", "Unlimited Consumables", "Edit Item Amount", "Zero Weight", "Ignore Crafting Requirement", "Unlock All Crafting Recipes"]) {
      expect(within(panel).getAllByText(label)).toHaveLength(1);
    }
    // The three with a native route dispatch to their own section, exactly as the
    // sections they moved out of did. One command is in flight at a time, so each row is
    // waited for rather than clicked while the menu is still answering for the last one.
    const clickAndExpect = async (control: HTMLElement, request: Record<string, unknown>) => {
      await waitFor(() => expect(control).toBeEnabled());
      fireEvent.click(control);
      await waitFor(() => expect(dispatch).toHaveBeenCalledWith({ sessionId: "reference-session", ...request }));
    };
    await clickAndExpect(activation, { action: "set", sectionId: "DWActivationControl", itemId: "enabled", value: true });
    await clickAndExpect(within(panel).getByRole("switch", { name: "Instant Ability Cooldown" }), { action: "set", sectionId: "DWCooldownControl", itemId: "enabled", value: false });
    await clickAndExpect(within(panel).getByRole("button", { name: "Unlock" }), { action: "invoke", sectionId: "DWCrafting", itemId: "unlock" });
    // The four with no verified native route are disabled and send nothing, and each one
    // says on the row why it is not wired. Carry weight is the fifth: it has a documented
    // route but no authorized setter, so its row runs the read-only check and it is the
    // only one that may dispatch.
    dispatch.mockClear();
    for (const label of ["Super Damage / One-Hit Kills", "Unlimited Consumables", "Ignore Crafting Requirement"]) {
      const control = within(panel).getByRole("switch", { name: label });
      expect(control).toBeDisabled();
      fireEvent.click(control);
    }
    expect(within(panel).queryByRole("switch", { name: "Zero Weight" })).not.toBeInTheDocument();
    const check = within(panel).getByRole("button", { name: "Run check" });
    await clickAndExpect(check, { action: "invoke", sectionId: "DWWeight", itemId: "probe" });
    expect(within(panel).getByRole("button", { name: "Increase Edit Item Amount" })).toBeDisabled();
    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(legacy).not.toHaveBeenCalled();
  });
  it("F9 grants once after native amount ACK and restores the prior amount", async () => {
    const legacy = installBridge(disconnectedRuntime);
    let amount = 250, operation = 0;
    const dispatch = vi.fn(async (request) => {
      operation += 1;
      if (request.action === "set") amount = request.value;
      return { accepted: true, message: "Completed" };
    });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "gold-session", revision: operation, ready: true,
        operation: { id: String(operation), status: "completed" as const },
        sections: [{ id: "DWCurrency", title: "Coins", items: [
          { type: "number", id: "amount", label: "Coin amount", value: amount },
          { type: "row", items: [{ type: "button", id: "add", label: "Add coins" }] },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await waitFor(() => expect(screen.getByText("Add 10,000 Gold")).toHaveAttribute("data-control-state", "available"));
    act(() => { triggerGameplayHotkey("add-gold"); triggerGameplayHotkey("add-gold"); });
    await waitFor(() => expect(dispatch).toHaveBeenCalledTimes(3));
    expect(dispatch.mock.calls.map(([request]) => [request.action, request.itemId, request.value])).toEqual([
      ["set", "amount", 10000], ["invoke", "add", undefined], ["set", "amount", 250],
    ]);
    expect(amount).toBe(250);
    expect(legacy).not.toHaveBeenCalled();
  });
  it("F9 never grants after the amount ACK changes player session", async () => {
    installBridge(disconnectedRuntime);
    let session = "gold-before", amount = 10;
    const dispatch = vi.fn(async (request: { action: string }) => { void request; session = "gold-after"; amount = 10000; return { accepted: true, message: "Changed session" }; });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: session, revision: 1, ready: true,
        operation: { id: session, status: "completed" as const },
        sections: [{ id: "DWCurrency", title: "Coins", items: [
          { type: "number", id: "amount", value: amount }, { type: "button", id: "add" },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await waitFor(() => expect(screen.getByText("Add 10,000 Gold")).toHaveAttribute("data-control-state", "available"));
    act(() => triggerGameplayHotkey("add-gold"));
    await waitFor(() => expect(dispatch).toHaveBeenCalledTimes(1));
    expect(dispatch.mock.calls[0][0].action).toBe("set");
  });
  it("saves native session locations after the name update completes and uses returned destinations", async () => {
    const legacy = installBridge(disconnectedRuntime);
    let name = "", saved = false, sequence = 0;
    const dispatch = vi.fn(async (request) => {
      sequence += 1;
      if (request.itemId === "name") name = request.value;
      if (request.itemId === "save") saved = true;
      return { accepted: true, message: "Completed" };
    });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "location-session", revision: 1, ready: true,
        operation: { id: `operation-${sequence}`, status: "completed" as const },
        sections: [{ id: "DWCoreTeleport", title: "Saved locations", items: [
          { type: "input", id: "name", value: name },
          { type: "dropdown", id: "destination", value: saved ? "opaque-location-1" : false, options: saved ? [{label: name, value: "opaque-location-1"}] : [] },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "Teleport" }));
    await waitFor(() => expect(screen.getByRole("textbox", { name: "Saved location name" })).toBeEnabled());
    fireEvent.change(screen.getByRole("textbox", { name: "Saved location name" }), { target: { value: "Gate" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(screen.getByRole("combobox", { name: "Saved location" })).toHaveValue("opaque-location-1"));
    expect(dispatch.mock.calls[0][0]).toEqual({ sessionId: "location-session", action: "set", sectionId: "DWCoreTeleport", itemId: "name", value: "Gate" });
    expect(dispatch.mock.calls[1][0]).toEqual({ sessionId: "location-session", action: "invoke", sectionId: "DWCoreTeleport", itemId: "save" });
    expect(legacy).not.toHaveBeenCalled();
  });
  it("uses only numeric live level targets and does not apply on selection", async () => {
    let revision = 0; // the runtime bumps this on every content change; the stub below mutates content between polls
    installBridge(disconnectedRuntime);
    let target: number | undefined;
    const dispatch = vi.fn(async (request) => { if (request.itemId === "target") target = request.value; return {accepted: true, message: "Accepted"}; });
    window.dawnwalkerDesktop = {...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({schema: 1 as const, sessionId: "levels", revision: ++revision, ready: true,
        sections: [{id: "DWCoreLevel", title: "Player level", items: [
          {id: "current", type: "label", value: 4},
          {id: "target", type: "dropdown", value: target, options: [{label: "5", value: 5}, {label: "6", value: 6}]},
          {id: "status", type: "label", label: "Live cap 6"},
        ]}]})), dispatch,
    }};
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const picker = await screen.findByRole("combobox", {name: "Target level"});
    expect(screen.getByRole("button", {name: "Apply level"})).toBeDisabled();
    expect(within(picker).getAllByRole("option").map((option) => option.textContent)).toEqual(["Select a level", "5", "6"]);
    fireEvent.change(picker, {target: {value: "6"}});
    await waitFor(() => expect(screen.getByRole("button", {name: "Apply level"})).toBeEnabled());
    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(dispatch.mock.calls[0][0]).toMatchObject({action: "set", itemId: "target", value: 6});
    fireEvent.click(screen.getByRole("button", {name: "Apply level"}));
    await waitFor(() => expect(dispatch).toHaveBeenCalledTimes(2));
    expect(dispatch.mock.calls[1][0]).toMatchObject({action: "invoke", itemId: "apply"});
    expect(screen.getByText("4", {selector: "strong"})).toBeInTheDocument();
  });
  it("never saves after a reused unrelated name ACK", async () => {
    installBridge(disconnectedRuntime);
    let name = "";
    const dispatch = vi.fn(async (request) => { name = request.value; return {accepted: true, message: "Accepted"}; });
    window.dawnwalkerDesktop = {...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({schema: 1 as const, sessionId: "locations", revision: 1, ready: true,
        operation: {id: "old-unrelated", status: "completed" as const}, sections: [{id: "DWCoreTeleport", title: "Saved locations", items: [
          {id: "name", type: "input", value: name}, {id: "destination", type: "dropdown", options: []},
        ]}]})), dispatch,
    }};
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));fireEvent.click(screen.getByRole("button", {name: "Teleport"}));
    const input = await screen.findByRole("textbox", {name: "Saved location name"});
    await waitFor(() => expect(input).toBeEnabled());
    fireEvent.change(input, {target: {value: "Gate"}});fireEvent.click(screen.getByRole("button", {name: "Save"}));
    await screen.findByText("The name could not be confirmed. Check the connection and try saving again.");
    expect(dispatch).toHaveBeenCalledTimes(1);
  });
  it("enables independent difficulty selectors only after native refresh validation", async () => {
    let revision = 0; // the runtime bumps this on every content change; the stub below mutates content between polls
    const legacy = installBridge(disconnectedRuntime);
    let verified = false;
    const dispatch = vi.fn(async (request) => { if (request.itemId === "refresh") verified = true; return { accepted: true, message: "Read" }; });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "difficulty-session", revision: ++revision, ready: true,
        sections: [{ id: "DWCoreDifficulty", title: "Difficulty", items: [
          { type: "dropdown", id: "rpg", value: 1, enabled: verified },
          { type: "dropdown", id: "action", value: 2, enabled: verified },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "Player" }));
    await screen.findByRole("button", { name: "Read difficulty" });
    expect(screen.getByRole("combobox", { name: "RPG Difficulty" })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Read difficulty" }));
    await waitFor(() => expect(screen.getByRole("combobox", { name: "RPG Difficulty" })).toBeEnabled());
    fireEvent.change(screen.getByRole("combobox", { name: "RPG Difficulty" }), { target: { value: "3" } });
    await waitFor(() => expect(dispatch).toHaveBeenCalledWith({ sessionId: "difficulty-session", action: "set", sectionId: "DWCoreDifficulty", itemId: "rpg", value: 3 }));
    expect(screen.getByRole("combobox", { name: "Action Difficulty" })).toHaveValue("2");
    expect(legacy).not.toHaveBeenCalled();
  });
  it("routes independent blood energy through its owned adapter without enabling God", async () => {
    const legacy = installBridge(disconnectedRuntime);
    let enabled = false;
    const dispatch = vi.fn(async (request) => { enabled = request.value; return { accepted: true, message: "Applied" }; });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "blood-session", revision: 1, ready: true,
        sections: [{ id: "DWCorePlayer", title: "Player controls", items: [
          { type: "checkbox", id: "god", value: false },
          { type: "checkbox", id: "bloodEnabled", value: enabled },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "Player" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Infinite Blood Energy: off" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Infinite Blood Energy: off" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Infinite Blood Energy: on" })).toHaveAttribute("aria-pressed", "true"));
    expect(dispatch).toHaveBeenCalledWith({ sessionId: "blood-session", action: "set", sectionId: "DWCorePlayer", itemId: "bloodEnabled", value: true });
    expect(screen.getByRole("button", { name: "God Mode: off" })).toHaveAttribute("aria-pressed", "false");
    expect(legacy).not.toHaveBeenCalled();
  });
  it("shows the objective event from the main-process monitor without sending a duplicate desktop notification", async () => {
    installBridge(disconnectedRuntime);
    let enabled = false;
    const notify = vi.fn(async () => true);
    let publishReminder: ((event: { title: string; objective: string; desktopAccepted: boolean }) => void) | undefined;
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!,
      questReminder: {
        get: async () => enabled,
        set: async (next: boolean) => { enabled = next; return next; },
        notify,
        onReminder: (listener) => { publishReminder = listener; return () => { publishReminder = undefined; }; },
      },
      importedMenu: {
        state: vi.fn(async () => ({ schema: 1 as const, sessionId: "reminder-session", revision: 1, ready: true,
          sections: [{ id: "DWQuestReadback", title: "Quest Journal", items: [] }] })),
        dispatch: vi.fn(async () => ({ accepted: true, message: "Read" })),
      } };

    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: "Settings" }));
    fireEvent.click(screen.getByRole("tab", { name: "General" }));
    fireEvent.click(await screen.findByRole("switch", { name: "Objective reminders" }));
    await waitFor(() => expect(screen.getByRole("switch", { name: "Objective reminders" })).toHaveAttribute("aria-checked", "true"));
    expect(publishReminder).toBeTypeOf("function");
    act(() => publishReminder?.({ title: "Withering Away", objective: "Find your family", desktopAccepted: true }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Find your family");
    expect(notify).not.toHaveBeenCalled();
  });

  it("offers the reminder switch in Settings and saves what the store confirms", async () => {
    const user = userEvent.setup();
    installBridge(disconnectedRuntime);
    let enabled = false;
    const set = vi.fn(async (next: boolean) => { enabled = next; return next; });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!,
      questReminder: { get: async () => enabled, set, notify: async () => true } };
    render(<App />);
    await user.click(screen.getByRole("button", { name: "Settings" }));
    await user.click(screen.getByRole("tab", { name: "General" }));
    const control = await screen.findByRole("switch", { name: "Objective reminders" });
    expect(control).toHaveAttribute("aria-checked", "false");
    await user.click(control);
    expect(set).toHaveBeenCalledWith(true);
    await waitFor(() => expect(screen.getByRole("switch", { name: "Objective reminders" })).toHaveAttribute("aria-checked", "true"));
  });

  it("sends a test notification only once reminders are on and reports what Windows said", async () => {
    const user = userEvent.setup();
    installBridge(disconnectedRuntime);
    let enabled = false;
    let accepted = true;
    const notify = vi.fn(async () => accepted);
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!,
      questReminder: { get: async () => enabled, set: async (next: boolean) => { enabled = next; return next; }, notify } };
    render(<App />);
    await user.click(screen.getByRole("button", { name: "Settings" }));
    await user.click(screen.getByRole("tab", { name: "General" }));

    // Nothing to test while reminders are off.
    expect(await screen.findByRole("button", { name: "Send test" })).toBeDisabled();

    await user.click(screen.getByRole("switch", { name: "Objective reminders" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Send test" })).toBeEnabled());
    await user.click(screen.getByRole("button", { name: "Send test" }));
    expect(notify).toHaveBeenCalledWith("Objective reminders", "This is a test reminder from the mod menu.");
    expect(await screen.findByText(/Sent\./)).toBeVisible();

    // A refusal is reported as a refusal, not as success.
    accepted = false;
    await user.click(screen.getByRole("button", { name: "Send test" }));
    expect(await screen.findByText(/did not accept the notification/)).toBeVisible();
  });

  it("leaves scheduled quest refreshes to the main process", async () => {
    vi.useFakeTimers();
    try {
      installBridge(disconnectedRuntime);
      const snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "quest-startup", revision: 1, ready: true,
        sections: [{ id: "DWQuestReadback", title: "Quest Journal", items: [{ id: "refresh", type: "button" }] }] };
      const dispatch = vi.fn(async () => ({ accepted: true, message: "Read", operationId: "read-2" }));
      window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!,
        questReminder: { get: async () => true, set: async (value: boolean) => value, notify: vi.fn(async () => true) },
        importedMenu: { state: vi.fn(async () => snapshot), dispatch } };
      render(<App />);
      await act(async () => {});
      await act(async () => { await vi.advanceTimersByTimeAsync(60_000); });
      expect(dispatch).not.toHaveBeenCalled();
    } finally { cleanup(); vi.useRealTimers(); }
  });
  it("refreshes the imported read-only journal into the existing valid-empty view", async () => {
    let revision = 0; // the runtime bumps this on every content change; the stub below mutates content between polls
    const legacy = installBridge(disconnectedRuntime);
    let payload = "";
    const dispatch = vi.fn(async () => { payload = "schema=1;open_total=0;returned=0;truncated=0"; return { accepted: true, message: "Read" }; });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "quest-session", revision: ++revision, ready: true,
        sections: [{ id: "DWQuestReadback", title: "Quest Journal", items: [
          { type: "label", id: "snapshot", label: payload },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "Quests" }));
    fireEvent.click(await screen.findByRole("button", { name: "Refresh Quest Journal" }));
    expect(await screen.findByText("No open quests")).toBeVisible();
    expect(dispatch).toHaveBeenCalledWith({ sessionId: "quest-session", action: "invoke", sectionId: "DWQuestReadback", itemId: "refresh" });
    expect(legacy).not.toHaveBeenCalled();
  });
  it("uses imported world readback and speed actions without enabling legacy teleport", async () => {
    const legacy = installBridge(disconnectedRuntime);
    const dispatch = vi.fn(async () => ({ accepted: true, message: "Queued" }));
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "world-session", revision: 1, ready: true,
        sections: [{ id: "DWCoreWorld", title: "World controls", items: [
          { type: "number", id: "speed", value: .8 },
          { type: "label", id: "status", label: "Game speed: 0.80x" },
          { type: "label", id: "location", label: "X: 1.00  Y: 2.00  Z: 3.00" },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "World" }));
    await waitFor(() => expect(screen.getByRole("slider", { name: "Game Speed" })).toBeEnabled());
    // The location readback lives in the Player tab's sidebar, not beside World.
    expect(screen.queryByText("X: 1.00 Y: 2.00 Z: 3.00")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    expect(screen.getByText("X: 1.00 Y: 2.00 Z: 3.00")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "World" }));
    fireEvent.change(screen.getByRole("slider", { name: "Game Speed" }), { target: { value: "1.5" } });
    fireEvent.pointerUp(screen.getByRole("slider", { name: "Game Speed" }));
    await waitFor(() => expect(dispatch).toHaveBeenCalledWith({ sessionId: "world-session", action: "set", sectionId: "DWCoreWorld", itemId: "speed", value: 1.5 }));
    fireEvent.click(screen.getByRole("button", { name: "Restore game speed" }));
    await waitFor(() => expect(dispatch).toHaveBeenCalledWith({ sessionId: "world-session", action: "invoke", sectionId: "DWCoreWorld", itemId: "restore" }));
    expect(legacy).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Teleport" }));
    expect(screen.getByRole("combobox", { name: "Saved location" })).toBeDisabled();
  });
  it("routes the top God Mode control through its registered native adapter without opening Sprint", async () => {
    const legacy = installBridge(disconnectedRuntime);
    let god = false;
    const dispatch = vi.fn(async (request) => { god = request.value; return { accepted: true, message: "Applied" }; });
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "core-session", revision: 1, ready: true,
        sections: [{ id: "DWCorePlayer", title: "Player controls", items: [
          { type: "checkbox", id: "god", label: "God Mode", value: god },
        ] }] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "Player" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "God Mode: off" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "God Mode: off" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "God Mode: on" })).toHaveAttribute("aria-pressed", "true"));
    expect(dispatch).toHaveBeenCalledWith({ sessionId: "core-session", action: "set", sectionId: "DWCorePlayer", itemId: "god", value: true });
    expect(legacy).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: /Sprint No Drain:/ })).toBeDisabled();
  });
  it("attributes pending speed work only to speed and preserves serialized core toggles", async () => {
    installBridge(disconnectedRuntime);
    let finish: (() => void) | undefined;
    const dispatch = vi.fn(() => new Promise<{ accepted: boolean; message: string }>(resolve => {
      finish = () => resolve({ accepted: true, message: "Queued" });
    }));
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "pending-scope", revision: 1, ready: true, sections: [
        { id: "DWCorePlayer", title: "Player", items: ["god", "sprintEnabled", "bloodEnabled"].map(id => ({ id, type: "checkbox" as const, value: false })) },
        { id: "DWSpeed", title: "Movement speed", items: [{ id: "multiplier", type: "number" as const, value: 1 }, { id: "restore", type: "button" as const }] },
      ] })), dispatch,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await waitFor(() => expect(screen.getByRole("slider", { name: "Speed Multiplier" })).toBeEnabled());
    const speed = screen.getByRole("slider", { name: "Speed Multiplier" });
    fireEvent.change(speed, { target: { value: "1.5" } }); fireEvent.pointerUp(speed);
    expect(speed).toBeDisabled();
    for (const label of ["God Mode: off", "Sprint No Drain: off", "Infinite Blood Energy: off"]) {
      expect(screen.getByRole("button", { name: label })).toBeEnabled();
    }
    fireEvent.click(screen.getByRole("button", { name: "God Mode: off" }));
    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(screen.getAllByText("Another game change is still applying. Try this control when it finishes.").some(element => element.closest('[hidden]') === null)).toBe(true);
    await act(async () => { finish?.(); });
    fireEvent.click(screen.getByRole("button", { name: "God Mode: off" }));
    expect(dispatch).toHaveBeenCalledTimes(2);
    // The switch flips the moment it is pressed; the game's confirmation only has to agree later.
    expect(screen.getByRole("button", { name: "God Mode: on" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Sprint No Drain: off" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Infinite Blood Energy: off" })).toBeEnabled();
    fireEvent.click(screen.getByRole("button", { name: "God Mode: on" }));
    expect(dispatch).toHaveBeenCalledTimes(2);
    await act(async () => { finish?.(); });
  });
  afterEach(() => cleanup());

  beforeEach(() => {
    window.localStorage.clear();
    installBridge(disconnectedRuntime);
  });
  it("distinguishes connected supplied controls from gated core time and cooldown routes", async () => {
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "supplied-world", revision: 1, ready: true, sections: [] })),
      dispatch: vi.fn(async () => ({ accepted: true, message: "Queued" })),
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    fireEvent.click(screen.getByRole("button", { name: "World" }));
    expect(await screen.findByText("Time segment safeguards")).toBeVisible();
    expect(screen.getByText(/Weather controls remain unavailable/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Player" }));
    expect(await screen.findByText("Ability cooldown control")).toBeVisible();
    expect(screen.getByText(/separate Focus debug control remains unavailable/)).toBeVisible();
    expect(await screen.findByText("Core player controls unavailable")).toBeVisible();
    expect(screen.getByText(/supplied player controls below are connected/)).toBeVisible();
    expect(screen.getByRole("button", { name: /God Mode:/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: /God Mode:/ }).closest("details")).toBeNull();
  });

  it.each([
    { runtime: disconnectedRuntime, message: "Start Dawnwalker and load an offline single-player save." },
    { runtime: { ...disconnectedRuntime, gameRunning: true }, message: "The game is running, but the gameplay connection is not ready." },
    { runtime: { ...disconnectedRuntime, compatibilityIssue: "Build mismatch" }, message: "The installed game build needs verification before Player controls can be used." },
  ])("explains the unavailable Player state without issuing a command: $message", async ({ runtime, message }) => {
    const dispatch = installBridge(runtime);
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    expect(await screen.findByText(message)).toBeVisible();
    const toggle = screen.getByRole("button", { name: /God Mode:/ });
    expect(toggle).toBeDisabled();
    expect(within(toggle.closest(".toggle-row") as HTMLElement).getByText("Unavailable")).toBeVisible();
    fireEvent.click(toggle);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("keeps the eight requested options in Player Controls without pretending they have native support", () => {
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    expect(screen.getByText("Keeps health, stamina and blood energy full.")).toBeVisible();
    expect(screen.getByRole("heading", { name: "Survival" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "Resources" })).toBeVisible();
    expect(screen.getByRole("region", { name: "Movement controls" })).toBeVisible();
    expect(document.querySelectorAll("#panel-player details")).toHaveLength(0);
    expect(screen.getByRole("button", { name: /God Mode:/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: /Sprint No Drain:/ })).toBeDisabled();
    const core = within(document.querySelector(".player-core-controls") as HTMLElement);
    for (const label of ["Infinite Health", "Super Jump", "No Clip"]) {
      expect(core.getByRole("switch", { name: label })).toBeDisabled();
      expect(screen.getAllByRole("switch", { name: label })).toHaveLength(1);
    }
    // Fall Damage had no runtime behind it and is no longer offered.
    expect(screen.queryByRole("switch", { name: "Fall Damage" })).not.toBeInTheDocument();
    for (const label of ["Blood Energy", "Speed Multiplier"]) {
      expect(core.getByRole("slider", { name: label })).toBeDisabled();
      expect(screen.getAllByRole("slider", { name: label })).toHaveLength(1);
    }
    // XP and Corruption are levelling controls, so they sit in the Player level card.
    const levelCard = within(document.querySelector(".player-level-controls") as HTMLElement);
    expect(levelCard.getByRole("slider", { name: "Experience Multiplier" })).toBeDisabled();
    expect(screen.getAllByRole("slider", { name: "Experience Multiplier" })).toHaveLength(1);
    expect(core.queryByRole("slider", { name: "Experience Multiplier" })).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Player options" })).not.toBeInTheDocument();
    expect(screen.queryByText(/The read-only probe documents/)).not.toBeInTheDocument();
    expect(screen.queryByText(/prevents sprint drain/)).not.toBeInTheDocument();
  });

  it("renders the Player category without the removed status and player-info panels", async () => {
    installImportedMenu(SUPPLIED_INVENTORY_SECTIONS);
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    expect(await screen.findByRole("heading", { name: "Player" })).toBeVisible();

    expect(screen.getByRole("heading", { name: "Blood of Dawnwalker Mod Menu" })).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Menu status" })).not.toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Player" })).toBeVisible();
    expect(screen.queryByRole("heading", { name: "Inventory" })).not.toBeInTheDocument();
    expect(screen.queryByRole("complementary", { name: "Player contextual tools" })).not.toBeInTheDocument();
    expect(document.querySelector(".app-stage")).not.toHaveClass("has-context-rail");
    expect(screen.getByRole("heading", { name: "Combat" })).toBeVisible();
    expect(screen.queryByRole("heading", { name: "World" })).not.toBeInTheDocument();
  });

  it("finds the moved combat controls through their exact search terms inside Player", () => {
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const search = screen.getByRole("textbox", { name: "Search menu options" });
    for (const [query, label] of [["infinite blood energy", "Infinite Blood Energy"], ["rpg difficulty", "RPG Difficulty"], ["action difficulty", "Action Difficulty"], ["sprint no drain", "Sprint No Drain"]]) {
      fireEvent.change(search, { target: { value: query } });
      expect(screen.getByRole("heading", { name: "Player" })).toBeVisible();
      expect(screen.getByText(label)).toBeVisible();
      expect(screen.queryByText("No matching Player controls")).not.toBeInTheDocument();
    }
  });

  it.each([disconnectedRuntime, { ...disconnectedRuntime, compatibilityIssue: "Installed build differs." }])("marks unavailable readouts without hiding requested action amounts", async (runtime) => {
    installBridge(runtime);
    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    expect(screen.getByRole("combobox", { name: "RPG Difficulty" })).toBeDisabled();
    expect(screen.getByRole("combobox", { name: "Action Difficulty" })).toBeDisabled();
    await user.click(screen.getByRole("button", { name: "World" }));
    expect(screen.getByRole("slider", { name: "Game Speed" })).toHaveAttribute("aria-valuetext", "Unavailable");
  });

  it.each([undefined, "invalid"])("does not invent toggle or numeric state for accepted readback %s", async (readback) => {
    const user = userEvent.setup();
    const dispatch = installBridge(verifiedRuntime([CONTROL_CAPABILITIES.godMode, CONTROL_CAPABILITIES.gameSpeed]),
      async command => appliedResult(command, "Runtime accepted the request.", readback));
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const toggle = screen.getByRole("button", { name: "God Mode: off" });
    await waitFor(() => expect(toggle).toBeEnabled());
    await user.click(toggle);
    expect(screen.getByRole("button", { name: "God Mode: off" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByText(/toggle returned no valid readback/)).toBeVisible();
    await user.click(screen.getAllByRole("button", { name: "World" })[0]);
    const slider = screen.getByRole("slider", { name: "Game Speed" });
    fireEvent.change(slider, { target: { value: "2" } });
    fireEvent.pointerUp(slider);
    await waitFor(() => expect(slider).toHaveValue("1"));
    expect(screen.getByText(/slider returned no valid readback/)).toBeVisible();
    expect(dispatch).toHaveBeenCalledTimes(2);
  });

  it("rejects a finite but out-of-range slider readback", async () => {
    const user = userEvent.setup();
    installBridge(verifiedRuntime([CONTROL_CAPABILITIES.gameSpeed]),
      async command => appliedResult(command, "Accepted.", "500"));
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await user.click(screen.getByRole("button", { name: "World" }));
    const slider = screen.getByRole("slider", { name: "Game Speed" });
    fireEvent.change(slider, { target: { value: "2" } });
    fireEvent.pointerUp(slider);
    await waitFor(() => expect(slider).toHaveValue("1"));
    expect(screen.getByText(/slider returned no valid readback/)).toBeVisible();
  });

  it("locks controls after a status refresh failure and recovers the same session", async () => {
    const runtime = verifiedRuntime([CONTROL_CAPABILITIES.godMode]);
    const dispatch = installBridge(runtime);
    const getRuntimeInfo = vi.mocked(window.dawnwalkerDesktop!.getRuntimeInfo);
    const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    try {
      render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
      const toggle = screen.getByRole("button", { name: "God Mode: off" });
      await waitFor(() => expect(toggle).toBeEnabled());
      getRuntimeInfo.mockRejectedValueOnce(new Error("Status IPC failed."));
      await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
      expect(toggle).toBeDisabled();
      expect(screen.queryByText("Game bridge disconnected")).not.toBeInTheDocument();
      fireEvent.click(toggle);
      expect(dispatch).not.toHaveBeenCalled();
      await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
      await waitFor(() => expect(toggle).toBeEnabled());
    } finally { warning.mockRestore(); }
  });

  it("discards a late command readback from a previous bridge session", async () => {
    let finish: (() => void) | undefined;
    installBridge(verifiedRuntime([CONTROL_CAPABILITIES.godMode]), command => new Promise(resolve => {
      finish = () => resolve(appliedResult(command, "Old session enabled God Mode.", "1"));
    }));
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const toggle = screen.getByRole("button", { name: "God Mode: off" });
    await waitFor(() => expect(toggle).toBeEnabled());
    fireEvent.click(toggle);
    vi.mocked(window.dawnwalkerDesktop!.getRuntimeInfo).mockResolvedValue({ ...verifiedRuntime([CONTROL_CAPABILITIES.godMode]), sessionId: "test-boot-2" });
    await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
    await act(async () => { finish!(); });
    expect(screen.getByRole("button", { name: "God Mode: off" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByText(/session changed before its response arrived/)).toBeVisible();
    expect(screen.queryByText("Old session enabled God Mode.")).not.toBeInTheDocument();
  });

  it("does not claim a preset was saved when local storage rejects the write", async () => {
    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const write = vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => { throw new Error("Storage unavailable."); });
    try {
      await user.click(screen.getByRole("button", { name: "Save UI Preset" }));
      expect(screen.getByText(/UI preset could not be saved locally/)).toBeVisible();
      expect(screen.getByRole("combobox", { name: "Local UI preset" })).toHaveValue("Default Preset");
      expect(window.localStorage.getItem("blood-of-dawnwalker-menu-local-presets-v2")).toBeNull();
    } finally { write.mockRestore(); }
  });

  it("requires an actual saved-name readback and clears locations across bridge sessions", async () => {
    const user = userEvent.setup();
    const capabilities = [CONTROL_CAPABILITIES.saveLocation, CONTROL_CAPABILITIES.teleportSavedLocation];
    const dispatch = installBridge(verifiedRuntime(capabilities), async command => appliedResult(command, "Accepted."));
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await user.click(screen.getByRole("button", { name: "Teleport" }));
    const name = screen.getByRole("textbox", { name: "Saved location name" });
    await waitFor(() => expect(name).toBeEnabled());
    await user.type(name, "Castle Gate");
    await user.click(screen.getByRole("button", { name: "Save" }));
    const locations = screen.getByRole("combobox", { name: "Saved location" });
    expect(locations).toHaveValue("");
    expect(locations).toBeDisabled();
    expect(screen.getByText(/no valid name readback/)).toBeVisible();
    dispatch.mockImplementation(async command => appliedResult(command, "Saved.", "Castle Gate"));
    await user.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(locations).toHaveValue("Castle Gate"));
    vi.mocked(window.dawnwalkerDesktop!.getRuntimeInfo).mockResolvedValue({ ...verifiedRuntime(capabilities), sessionId: "test-boot-2" });
    await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
    expect(locations).toHaveValue("");
    expect(locations).toBeDisabled();
    expect(within(locations).queryByRole("option", { name: "Castle Gate" })).not.toBeInTheDocument();
  });

  it("fails closed when the build is unverified or a capability is absent", async () => {
    const user = userEvent.setup();
    installBridge({
      ...verifiedRuntime([CONTROL_CAPABILITIES.godMode]),
      mode: "disconnected",
      buildVerified: false,
      interactionEligible: false,
    });
    const dispatch = vi.mocked(window.dawnwalkerDesktop!.dispatch);
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const godModeToggle = await screen.findByRole("button", { name: "God Mode: off" });
    const bloodToggle = screen.getByRole("button", { name: "Infinite Blood Energy: off" });
    expect(godModeToggle).toBeDisabled();
    expect(bloodToggle).toBeDisabled();

    await user.click(godModeToggle);
    await user.click(bloodToggle);
    expect(dispatch).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "God Mode: off" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByRole("button", { name: "Infinite Blood Energy: off" })).toHaveAttribute("aria-pressed", "false");
  });

  it("dispatches an advertised toggle and commits only its accepted readback", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(
      verifiedRuntime([CONTROL_CAPABILITIES.godMode]),
      async (command) => appliedResult(command, "God Mode applied by the verified bridge.", "1"),
    );
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    const toggle = screen.getByRole("button", { name: "God Mode: off" });
    await waitFor(() => expect(toggle).toBeEnabled());
    await user.click(toggle);

    await waitFor(() => expect(screen.getByRole("button", { name: "God Mode: on" })).toHaveAttribute("aria-pressed", "true"));
    expect(dispatch).toHaveBeenCalledOnce();
    expect(dispatch.mock.calls[0][0]).toMatchObject({ capability: "player:god-mode", value: true });
    expect(dispatch.mock.calls[0][0]).toMatchObject({ sessionId: "test-boot-1" });
    expect(dispatch.mock.calls[0][0].requestId).toMatch(/^renderer-[a-z0-9]+-1$/);
    expect(screen.getByText("God Mode applied by the verified bridge.")).toBeVisible();
  });

  it("allows an explicitly authorized development pilot without claiming a production build", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(
      {
        ...verifiedRuntime([CONTROL_CAPABILITIES.sprintNoDrain]),
        buildVerified: false,
        interactionEligible: true,
        bridgeVersion: "0.3.18-pilot",
      },
      async (command) => appliedResult(command, "Sprint No Drain enabled for pilot QA.", "1"),
    );
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    const toggle = screen.getByRole("button", { name: "Sprint No Drain: off" });
    await waitFor(() => expect(toggle).toBeEnabled());
    await user.click(toggle);

    await waitFor(() => expect(screen.getByRole("button", { name: "Sprint No Drain: on" })).toBeEnabled());
    expect(dispatch).toHaveBeenCalledOnce();
    expect(dispatch.mock.calls[0][0]).toMatchObject({
      capability: "player:sprint-no-drain",
      value: true,
      sessionId: "test-boot-1",
    });
    expect(screen.queryByRole("region", { name: "Menu status" })).not.toBeInTheDocument();
  });

  it("reconciles resource toggles to the bridge active set", async () => {
    const dispatch = installBridge({
      ...verifiedRuntime([CONTROL_CAPABILITIES.godMode]),
      activeCapabilities: [CONTROL_CAPABILITIES.godMode],
    });

    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    // The reconciliation waits on the bridge's runtime-info round trip after a cold App
    // render (~2.5 s on this machine), longer than waitFor's 1 s default under load.
    await waitFor(() => expect(screen.getByRole("button", { name: "God Mode: on" })).toBeEnabled(), { timeout: 8000 });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("reconciles the displayed game-speed value to live readback", async () => {
    installBridge({
      ...verifiedRuntime([CONTROL_CAPABILITIES.gameSpeed]),
      controls: { gameSpeed: 1.5 },
    });

    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await userEvent.setup().click(screen.getAllByRole("button", { name: "World" })[0]);
    await waitFor(() => expect(screen.getByRole("slider", { name: "Game Speed" })).toHaveValue("1.5"));
  });

  it("leaves a slider unchanged and shows the exact bridge rejection", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(verifiedRuntime([CONTROL_CAPABILITIES.gameSpeed]), async (command) => ({
      accepted: false,
      capability: command.capability,
      requestId: command.requestId,
      status: "rejected",
      message: "Game Speed rejected: runtime readback did not match.",
      readback: 0,
    }));
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await user.click(screen.getAllByRole("button", { name: "World" })[0]);

    const slider = screen.getByRole("slider", { name: "Game Speed" });
    await waitFor(() => expect(slider).toBeEnabled());
    fireEvent.change(slider, { target: { value: "2" } });
    fireEvent.pointerUp(slider);

    await waitFor(() => expect(screen.getByText("Game Speed rejected: runtime readback did not match.")).toBeVisible());
    expect(dispatch.mock.calls[0][0]).toMatchObject({ capability: "world:game-speed", value: 2 });
    await waitFor(() => expect(slider).toHaveValue("1"));
  });

  it("does not flood slider commands and commits on pointer release", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(
      verifiedRuntime([CONTROL_CAPABILITIES.gameSpeed]),
      async (command) => appliedResult(command, "Game Speed set to 2.", 2),
    );
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await user.click(screen.getAllByRole("button", { name: "World" })[0]);

    const slider = screen.getByRole("slider", { name: "Game Speed" });
    await waitFor(() => expect(slider).toBeEnabled());
    fireEvent.change(slider, { target: { value: "1.8" } });
    fireEvent.change(slider, { target: { value: "2" } });
    expect(dispatch).not.toHaveBeenCalled();
    fireEvent.pointerUp(slider);

    await waitFor(() => expect(dispatch).toHaveBeenCalledOnce());
    expect(dispatch.mock.calls[0][0]).toMatchObject({ capability: "world:game-speed", value: 2 });
    await waitFor(() => expect(slider).toHaveValue("2"));
  });

  it("saves category and search presets without imitating gameplay changes", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(
      verifiedRuntime([CONTROL_CAPABILITIES.gameSpeed]),
      async (command) => appliedResult(command, `Game Speed set to ${command.value}.`, command.value),
    );
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getAllByRole("button", { name: "World" })[0]);
    const slider = screen.getByRole("slider", { name: "Game Speed" });
    await waitFor(() => expect(slider).toBeEnabled());
    fireEvent.change(slider, { target: { value: "2" } });
    fireEvent.pointerUp(slider);
    await waitFor(() => expect(slider).toHaveValue("2"));

    await user.type(screen.getByRole("textbox", { name: "Search menu options" }), "speed");
    await user.click(screen.getByRole("button", { name: "Save UI Preset" }));
    const presetSelector = screen.getByRole("combobox", { name: "Local UI preset" });
    expect(presetSelector).toHaveValue("Custom Preset");
    await waitFor(() => {
      const storedPresets = JSON.parse(window.localStorage.getItem("blood-of-dawnwalker-menu-local-presets-v2") ?? "{}") as {
        "Custom Preset"?: { activeNav?: string; searchQuery?: string };
      };
      expect(storedPresets["Custom Preset"]).toEqual({ activeNav: "world", searchQuery: "speed" });
    });

    const restoredSlider = screen.getByRole("slider", { name: "Game Speed" });
    fireEvent.change(restoredSlider, { target: { value: "2.5" } });
    fireEvent.pointerUp(restoredSlider);
    await waitFor(() => expect(restoredSlider).toHaveValue("2.5"));
    expect(dispatch).toHaveBeenCalledTimes(2);

    await user.selectOptions(presetSelector, "Default Preset");
    expect(screen.getByRole("heading", { name: "Player" })).toBeVisible();
    await user.selectOptions(presetSelector, "Custom Preset");
    expect(screen.getByRole("heading", { name: "World" })).toBeVisible();
    expect(screen.getByRole("textbox", { name: "Search menu options" })).toHaveValue("speed");
    expect(screen.getByText(/No game commands were sent/i)).toBeVisible();
    expect(screen.getByRole("slider", { name: "Game Speed" })).toHaveValue("2.5");
    expect(dispatch).toHaveBeenCalledTimes(2);
  });

  it("prevents duplicate in-flight commands for the same capability", async () => {
    let completeDispatch: (() => void) | undefined;
    const dispatch = installBridge(verifiedRuntime([CONTROL_CAPABILITIES.godMode]), (command) => new Promise((resolve) => {
      completeDispatch = () => resolve(appliedResult(command, "God Mode applied once.", true));
    }));
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    const toggle = screen.getByRole("button", { name: "God Mode: off" });
    await waitFor(() => expect(toggle).toBeEnabled());
    const row = within(toggle.closest(".toggle-row") as HTMLElement);
    expect(row.queryByText(/^(ON|OFF)$/)).toBeNull();
    fireEvent.click(toggle);
    fireEvent.click(toggle);
    expect(dispatch).toHaveBeenCalledOnce();
    expect(toggle).toBeDisabled();
    // Pending state stays on the accessible control without a redundant state word.
    expect(toggle).toHaveAttribute("aria-busy", "true");
    expect(row.queryByText("Applying…")).toBeNull();

    await act(async () => completeDispatch?.());
    await waitFor(() => expect(screen.getByRole("button", { name: "God Mode: on" })).toBeEnabled());
    expect(row.queryByText(/^(ON|OFF)$/)).toBeNull();
    expect(toggle).toHaveAttribute("aria-busy", "false");
  });
  it("names the requested Player switch state at once instead of Applying…", async () => {
    installBridge(disconnectedRuntime);
    let god = false;
    let complete: (() => void) | undefined;
    const dispatch = vi.fn((request: { itemId?: string; value?: unknown }) => new Promise((resolve) => {
      complete = () => { if (request.itemId === "god") god = request.value === true; resolve({ accepted: true, message: "Applied" }); };
    }));
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "instant-toggle-session", revision: 1, ready: true,
        sections: [{ id: "DWCorePlayer", title: "Player controls", items: [
          { type: "checkbox" as const, id: "god", value: god },
        ] }] })), dispatch: dispatch as never,
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const toggle = await screen.findByRole("button", { name: "God Mode: off" });
    const row = within(toggle.closest(".toggle-row") as HTMLElement);
    expect(row.queryByText(/^(ON|OFF)$/)).toBeNull();

    fireEvent.click(toggle);
    // The switch retains its requested state without a duplicate visible word.
    expect(row.queryByText(/^(ON|OFF)$/)).toBeNull();
    expect(toggle).toHaveAttribute("aria-busy", "true");
    expect(screen.getByRole("button", { name: "God Mode: on" })).toHaveAttribute("aria-busy", "true");
    expect(row.queryByText("Applying…")).toBeNull();

    await act(async () => complete?.());
    await waitFor(() => expect(toggle).toHaveAttribute("aria-busy", "false"));
    expect(screen.getByRole("button", { name: "God Mode: on" })).toBeEnabled();
  });

  it("saves and reuses only locations accepted by the bridge", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(
      verifiedRuntime([CONTROL_CAPABILITIES.saveLocation, CONTROL_CAPABILITIES.teleportSavedLocation]),
      async (command) => appliedResult(command, `${command.capability} applied.`, command.value),
    );
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getByRole("button", { name: "Teleport" }));
    const name = screen.getByRole("textbox", { name: "Saved location name" });
    await waitFor(() => expect(name).toBeEnabled());
    await user.type(name, "Castle Gate");
    await user.click(screen.getByRole("button", { name: "Save" }));
    const savedLocation = screen.getByRole("combobox", { name: "Saved location" });
    await waitFor(() => expect(savedLocation).toHaveValue("Castle Gate"));
    const teleportAction = screen.getAllByRole("button", { name: "Teleport" }).find(
      (button) => button.getAttribute("data-capability") === CONTROL_CAPABILITIES.teleportSavedLocation,
    );
    expect(teleportAction).toBeDefined();
    await user.click(teleportAction!);

    await waitFor(() => expect(dispatch).toHaveBeenCalledTimes(2));
    expect(dispatch.mock.calls[0][0]).toMatchObject({ capability: "teleport:save-location", value: "Castle Gate" });
    expect(dispatch.mock.calls[1][0]).toMatchObject({ capability: "teleport:teleport-saved-location", value: "Castle Gate" });
  });

  it("opens all Player controls by default and retains the explicit reference Overview", () => {
    const { container } = render(<App />);
    expect(container.querySelector(".reference-dashboard")).toHaveAttribute("data-reference-category", "player");
    expect(container.querySelector(".player-core-controls")).toHaveClass("dashboard-card");
    expect(screen.getAllByRole("button", { name: /^God Mode:/ })).toHaveLength(1);
    fireEvent.click(screen.getByRole("button", { name: "Overview" }));
    expect(screen.getByRole("button", { name: "Overview" })).toHaveAttribute("aria-current", "page");
    // Player, Combat, World, Inventory, Teleport - the NPC card was only ever
    // unimplemented controls. Sidebar: Player Info and Location, without Quick Spawn.
    expect(container.querySelectorAll(".dashboard-main > .dashboard-card")).toHaveLength(5);
    expect(container.querySelectorAll(".dashboard-sidebar > .dashboard-card")).toHaveLength(2);
    fireEvent.click(screen.getByRole("button", { name: "Player" }));
    expect(container.querySelector(".reference-dashboard")).toHaveAttribute("data-reference-category", "player");
    expect(screen.getByRole("heading", { name: "Player" })).toBeVisible();
  });

  it("switches every navigation category into its own isolated view", async () => {
    const user = userEvent.setup();
    installImportedMenu(SUPPLIED_INVENTORY_SECTIONS);
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await screen.findByRole("heading", { name: "Player" });

    const categories = ["Player", "World", "Inventory", "Teleport", "Visuals", "Quests", "Settings"];
    const dashboard = document.querySelector(".reference-dashboard");
    const sidebar = document.querySelector(".dashboard-sidebar");
    const categoryRail = screen.getByRole("complementary", { name: "Menu categories" });
    expect(within(categoryRail).getAllByRole("button").map(button => button.textContent)).toEqual(categories);
    expect(screen.queryByRole("tablist", { name: "Quick categories" })).not.toBeInTheDocument();
    for (const category of categories) {
      await user.click(screen.getByRole("button", { name: category }));
      expect(screen.getByRole("heading", { name: category })).toBeVisible();
      expect(document.querySelector(".reference-dashboard")).toBe(dashboard);
      expect(dashboard).toHaveAttribute("data-reference-category", category.toLowerCase());
      // Player Info and Location stay with the Player tab only (Quick Spawn held only
      // unimplemented buttons); every other category takes the full width.
      if (category === "Player") {
        expect(document.querySelector(".dashboard-sidebar")).toBe(sidebar);
        expect(sidebar?.querySelectorAll(".dashboard-card")).toHaveLength(2);
        expect(document.querySelector(".dashboard-layout")).toHaveAttribute("data-sidebar", "true");
      } else {
        expect(document.querySelector(".dashboard-sidebar")).toBeNull();
        expect(document.querySelector(".dashboard-layout")).toHaveAttribute("data-sidebar", "false");
      }
      expect(document.querySelectorAll(".dashboard-main > .dashboard-card")).toHaveLength(0);
      for (const otherCategory of categories.filter((label) => label !== category)) {
        expect(screen.queryByRole("heading", { name: otherCategory })).not.toBeInTheDocument();
      }
      if (category === "Player") {
        expect(screen.queryByRole("heading", { name: "Inventory" })).not.toBeInTheDocument();
        // Combat is a section inside Player now, so its content travels with this category.
        expect(screen.getByRole("heading", { name: "Combat" })).toBeVisible();
        expect(screen.getByText("Extended Parry Window unavailable")).toBeVisible();
        expect(screen.getByText("Extended parry timing is unavailable. Its required player settings are not yet verified.")).toBeVisible();
        expect(screen.queryByText(/requires a Stats.CustomModifier set-by-caller magnitude/i)).not.toBeInTheDocument();
        expect(document.querySelectorAll("#panel-player details")).toHaveLength(0);
      } else if (category !== "Inventory") {
        expect(screen.queryByRole("heading", { name: "Inventory" })).not.toBeInTheDocument();
        expect(screen.queryByRole("heading", { name: "Combat" })).not.toBeInTheDocument();
      }
    }

    expect(screen.getByText("Quest Journal unavailable")).not.toBeVisible();
    await user.click(screen.getByRole("tab", { name: "General" }));
    expect(screen.getByRole("button", { name: "Reset UI View" })).toBeVisible();
    expect(screen.queryByText("Global menu hotkeys")).not.toBeInTheDocument();
    expect(screen.queryByText("Local settings only")).not.toBeInTheDocument();
  }, NAVIGATION_SWEEP_TIMEOUT_MS);

  it("hides the complete attack-speed panel while preserving combat controls", async () => {
    installBridge(disconnectedRuntime);
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: {
      state: vi.fn(async () => ({ schema: 1 as const, sessionId: "combat-session", revision: 1, ready: true,
        sections: [{ id: "DWCombatDiscovery", title: "Attack speed", items: [
          { type: "checkbox" as const, id: "attackEnabled", label: "Attack speed bonus +0.10", value: false },
          { type: "label" as const, id: "attackStatus", label: "Normal human fist playback verified at +10%; other attacks unverified." },
        ] }],
      })), dispatch: vi.fn(),
    } };
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await waitFor(() => expect(screen.getByRole("slider", { name: "Speed Multiplier" })).toBeInTheDocument());
    expect(screen.queryByText("Attack speed bonus +0.10")).not.toBeInTheDocument();
    expect(document.querySelector('[data-imported-section="DWCombatDiscovery"]')).not.toBeInTheDocument();
    expect(screen.queryByText(/These controls remain unavailable until player-only targets/)).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Unresolved combat contracts" })).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Unresolved combat contracts" })).not.toBeInTheDocument();
  });

  it("excludes removed diagnostic tools from Settings search results", async () => {
    installBridge(disconnectedRuntime);
    const dispatch = vi.fn();
    const state = vi.fn(async () => ({ schema: 1 as const, sessionId: "diagnostic-search", revision: 1, ready: true,
      sections: [{ id: "DWHubTabs", title: "Hub tab recovery", items: [
        { type: "button" as const, id: "restore", label: "Restore hub locks" },
      ] }],
    }));
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: { state, dispatch } };
    render(<App />);
    await waitFor(() => expect(state).toHaveBeenCalled());
    fireEvent.click(screen.getByRole("button", { name: "Settings" }));
    const search = screen.getByRole("textbox", { name: "Search menu options" });
    fireEvent.change(search, { target: { value: "hub" } });
    expect(screen.getByText("No matching Settings controls")).toBeVisible();
    expect(document.querySelector(".search-count")).toHaveTextContent("0");
    expect(screen.queryByRole("tab", { name: /Dev testing/i })).not.toBeInTheDocument();
    expect(screen.queryByText("Restore hub locks")).not.toBeInTheDocument();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("opens the Save Editor and Credits as Settings tabs, each keeping its tools to itself", async () => {
    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getByRole("button", { name: "Settings" }));
    // Empty diagnostics do not add a Settings tab.
    expect(screen.getAllByRole("tab").map(tab => tab.textContent)).toEqual(["General", "Save Editor", "Credits"]);
    await user.click(screen.getByRole("tab", { name: "Save Editor" }));
    expect(screen.getByRole("button", { name: "Settings" })).toHaveAttribute("aria-current", "page");
    const editor = screen.getByRole("tabpanel", { name: "Save Editor" });
    expect(editor).toHaveAttribute("id", "settings-pane-save-editor");
    expect(within(editor).getByRole("region", { name: "Save tools" })).toBeVisible();
    expect(within(editor).getByText(/Pick a save, type the new values, press Apply\./)).toBeVisible();
    expect(within(editor).getByText("Open the desktop app to access local saves.")).toBeVisible();
    expect(screen.queryByRole("region", { name: "Credits" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("tab", { name: "Credits" }));
    const settings = screen.getByRole("region", { name: "Settings" });
    expect(within(settings).getByRole("region", { name: "Credits" })).toBeVisible();
    expect(screen.queryByRole("region", { name: "Save tools" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("tab", { name: "General" }));
    expect(within(settings).getByRole("switch", { name: "Styled tooltips" })).toHaveAttribute("aria-checked", "true");
    expect(screen.queryByRole("region", { name: "Credits" })).not.toBeInTheDocument();
  });

  it("searches save operations inside the Save Editor tab and restores Settings from a saved UI preset", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(disconnectedRuntime);
    const view = render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await user.click(screen.getByRole("button", { name: "Settings" }));
    await user.click(screen.getByRole("tab", { name: "Save Editor" }));
    const search = screen.getByRole("textbox", { name: "Search menu options" });
    for (const query of ["save editor", "inspect", "backup", "restore", "recovery", "daytime stat points"]) {
      fireEvent.change(search, { target: { value: query } });
      expect(screen.getByRole("region", { name: "Save tools" })).toBeVisible();
    }
    fireEvent.change(search, { target: { value: "backup" } });
    await user.click(screen.getByRole("button", { name: "Save UI Preset" }));
    view.unmount();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await user.selectOptions(screen.getByRole("combobox", { name: "Local UI preset" }), "Custom Preset");
    expect(screen.getByRole("heading", { name: "Settings" })).toBeVisible();
    expect(screen.getByRole("textbox", { name: "Search menu options" })).toHaveValue("backup");
    // The preset restores the category; the Save Editor tab is one click away and its tools stay out of General.
    expect(screen.getByRole("tab", { name: "Save Editor" })).toBeVisible();
    expect(screen.queryByRole("region", { name: "Save tools" })).not.toBeInTheDocument();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("renders a bounded read-only Quest Journal with tracked, optional, and progress states", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge({
      ...verifiedRuntime([CONTROL_CAPABILITIES.questJournal]),
      questJournal: {
        openQuestCount: 2,
        returnedQuestCount: 2,
        truncated: false,
        quests: [
          {
            title: "Blood, Stone;= Dawn",
            state: "active",
            tracked: true,
            objectiveCount: 2,
            objectivesTruncated: false,
            objectives: [
              { text: "Find the key", state: "active", currentCount: 1.5, maxCount: 3, optional: false },
              { text: "Visit Łuków", state: "success", currentCount: 1, maxCount: 1, optional: true },
            ],
          },
          {
            title: "A Quiet Night",
            state: "unknown",
            tracked: false,
            objectiveCount: 0,
            objectivesTruncated: false,
            objectives: [],
          },
        ],
      },
    });
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getByRole("button", { name: "Quests" }));
    await waitFor(() => expect(screen.getByText("Open Quest Journal")).toBeVisible());
    const journal = screen.getByRole("region", { name: "Quest Journal readback" });
    expect(journal).toHaveAttribute("data-capability", "quests:journal-readback");
    expect(journal).toHaveAttribute("data-control-state", "available");
    expect(within(journal).getByRole("heading", { name: "Blood, Stone;= Dawn" })).toBeVisible();
    expect(within(journal).getByText("Tracked")).toBeVisible();
    expect(within(journal).getByText("Completed · Optional")).toBeVisible();
    expect(within(journal).getByLabelText("Find the key progress")).toHaveTextContent("1.5 / 3");
    expect(within(journal).getByText("No objectives are present in this quest snapshot.")).toBeVisible();
    expect(within(journal).queryAllByRole("button")).toEqual([]);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("distinguishes a valid empty Quest Journal from unavailable readback", async () => {
    const user = userEvent.setup();
    installBridge({
      ...verifiedRuntime([CONTROL_CAPABILITIES.questJournal]),
      questJournal: {
        openQuestCount: 0,
        returnedQuestCount: 0,
        truncated: false,
        quests: [],
      },
    });
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getByRole("button", { name: "Quests" }));
    await waitFor(() => expect(screen.getByText("No open quests")).toBeVisible());
    expect(screen.getByText("The loaded Journal returned a valid empty snapshot.")).toBeVisible();
    expect(screen.queryByText("Quest Journal unavailable")).not.toBeInTheDocument();
  });

  it("keeps coins and equipment exclusively in Inventory and blood energy in Player Controls", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge(verifiedRuntime([]));
    // installBridge replaces the whole desktop bridge, so the supplied menu goes on after it.
    installImportedMenu(SUPPLIED_INVENTORY_SECTIONS);
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    expect(screen.getByRole("button", { name: "Inventory" })).toBeVisible();
    expect(screen.queryByRole("tab", { name: "Inventory" })).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Inventory" })).not.toBeInTheDocument();
    expect(document.querySelector("#panel-player [data-imported-section=DWCurrency]")).not.toBeInTheDocument();
    expect(document.querySelector("#panel-player [data-imported-section=DWItems]")).not.toBeInTheDocument();
    const core = within(document.querySelector(".player-core-controls") as HTMLElement);
    expect(core.getByRole("button", { name: /^Infinite Blood Energy:/ })).toBeVisible();
    expect(within(document.querySelector(".player-combat-section") as HTMLElement).queryByRole("button", { name: /^Infinite Blood Energy:/ })).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Inventory" }));
    expect(screen.getByRole("button", { name: "Inventory" })).toHaveAttribute("aria-current", "page");
    const inventoryRegion = screen.getByRole("region", { name: "Inventory" });
    const inventoryCapabilities = new Set(
      [...inventoryRegion.querySelectorAll<HTMLElement>("[data-capability]")].map((element) => element.dataset.capability),
    );
    // The core Add Gold / Add Item rows and their locked notices were removed, so the
    // Inventory section is now only the connected supplied-menu cards.
    expect(inventoryCapabilities).toEqual(new Set());
    expect(screen.queryByText("Other inventory contracts remain locked")).not.toBeInTheDocument();
    expect(screen.queryByText("Unlimited Weight target under correction")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Add Gold" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Add Item" })).not.toBeInTheDocument();
    expect(document.querySelectorAll("#panel-player details")).toHaveLength(0);
    expect(screen.queryByText("Red Essence")).not.toBeInTheDocument();
    expect(screen.queryByRole("switch", { name: "No Durability Loss" })).not.toBeInTheDocument();
    expect(screen.queryByRole("switch", { name: "Unlimited Weight" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Unlimited Weight:/ })).not.toBeInTheDocument();
    expect(dispatch).not.toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: "World" }));
    expect(screen.queryByRole("heading", { name: "Inventory" })).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Inventory" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Player" }));
    // The Inventory section is matched through the supplied cards it now contains.
    await user.type(screen.getByRole("textbox", { name: "Search menu options" }), "coins");
    expect(screen.getByText("No matching Player controls")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Inventory" }));
    expect(screen.getByRole("heading", { name: "Inventory" })).toBeVisible();
  });

  // The bounded Add Gold row was removed with the rest of "Additional inventory controls".
  // The F9 hotkey below still exercises the same guarded addGold path.
  it("routes global F9 to the same authorized Add Gold action with a fixed 10,000 delta", async () => {
    const dispatch = installBridge(
      {
        ...verifiedRuntime([CONTROL_CAPABILITIES.addGold]),
        player: { gold: 0 },
      },
      async (command) => appliedResult(command, "Added 10000 Gold; balance is 10000.", "10000"),
    );
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await waitFor(() => expect(gameplayHotkeyListener).toBeTypeOf("function"));
    await waitFor(() => expect(screen.getByText("Add 10,000 Gold")).toHaveAttribute("data-control-state", "available"));

    act(() => {
      triggerGameplayHotkey("add-gold");
      triggerGameplayHotkey("add-gold");
    });

    await waitFor(() => expect(dispatch).toHaveBeenCalledOnce());
    expect(dispatch.mock.calls[0][0]).toMatchObject({
      capability: CONTROL_CAPABILITIES.addGold,
      value: 10000,
      sessionId: "test-boot-1",
    });
    expect(screen.getByText("F9")).toBeVisible();
    expect(screen.getByText("Add 10,000 Gold")).toHaveAttribute("data-control-state", "available");
  });

  it("keeps global F9 fail closed when Add Gold is not authorized", async () => {
    const dispatch = installBridge(disconnectedRuntime);
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    await waitFor(() => expect(gameplayHotkeyListener).toBeTypeOf("function"));

    act(() => triggerGameplayHotkey("add-gold"));

    expect(dispatch).not.toHaveBeenCalled();
    expect(screen.getByText("Add 10,000 Gold")).toHaveAttribute("data-control-state", "locked");
    expect(await screen.findByText(/verified offline bridge has not advertised player:add-gold/i)).toBeVisible();
  });

  it("keeps Eye Appearance isolated inside the shared reference sidebar", async () => {
    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getByRole("button", { name: "Visuals" }));
    expect(screen.queryByText("Show NPC Info")).not.toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Character Eye Appearance" })).toBeVisible();
    expect(screen.queryByText("HUD Visible")).not.toBeInTheDocument();
    expect(screen.queryByText("Native HUD control")).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Fog configuration" })).not.toBeInTheDocument();
    const search = screen.getByRole("textbox", { name: "Search menu options" });
    for (const query of ["fog", "hud"]) {
      fireEvent.change(search, { target: { value: query } });
      expect(screen.getByText("No matching Visuals controls")).toBeVisible();
    }
    fireEvent.change(search, { target: { value: "eye" } });
    expect(screen.getByRole("region", { name: "Character Eye Appearance" })).toBeVisible();

    await user.click(screen.getByRole("button", { name: "Quests" }));
    expect(screen.getByRole("region", { name: "Character Eye Appearance", hidden: true })).not.toBeVisible();

    await user.click(screen.getByRole("button", { name: "World" }));
    // Player Info and Location stay with the Player tab; World gets the full width.
    expect(screen.queryByRole("heading", { name: "Location" })).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /^Player$/ }));
    expect(screen.getByRole("heading", { name: "Location" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "World" }));
    expect(screen.queryByRole("complementary", { name: "World contextual tools" })).not.toBeInTheDocument();
    expect(document.querySelector(".app-stage")).not.toHaveClass("has-context-rail");
  });

  it("rolls the controlled character preview back when the game rejects an eye change", async () => {
    installBridge(disconnectedRuntime);
    const snapshot: ImportedMenuSnapshot = {
      schema: 1, sessionId: "appearance-session", revision: 1, ready: true,
      sections: [{ id: "DWEyeColor", title: "Eye color", items: [
        { id: "color", type: "input", value: "" },
        { id: "glow", type: "number", value: 0 },
        { id: "owned", type: "checkbox", value: false },
        { id: "status", type: "label", label: "Select a color" },
      ] }],
    };
    let rejectEye!: () => void;
    const dispatch = vi.fn(() => new Promise<{ accepted: boolean; message: string }>(resolve => {
      rejectEye = () => resolve({ accepted: false, message: "Rejected by the game." });
    }));
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, importedMenu: { state: vi.fn(async () => snapshot), dispatch } };
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: "Visuals" }));
    const green = await screen.findByRole("button", { name: "Green" });
    fireEvent.click(green);
    await waitFor(() => expect(green).toHaveAttribute("aria-pressed", "true"));
    await waitFor(() => expect(dispatch).toHaveBeenCalled());
    rejectEye();
    await waitFor(() => expect(green).toHaveAttribute("aria-pressed", "false"));
    expect(await screen.findByText("Eye colour could not be applied. Restore original game eyes before trying again.")).toBeVisible();
  });

  it("filters only the active category and restores it when cleared", async () => {
    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getByRole("button", { name: "World" }));
    await user.type(screen.getByRole("textbox", { name: "Search menu options" }), "speed");
    expect(screen.getByRole("heading", { name: "World" })).toBeVisible();
    expect(screen.queryByRole("heading", { name: "Player" })).not.toBeInTheDocument();
    expect(screen.getByText("Game Speed")).toBeVisible();
    expect(screen.queryByText("World state safety")).not.toBeInTheDocument();

    await user.clear(screen.getByRole("textbox", { name: "Search menu options" }));
    await user.type(screen.getByRole("textbox", { name: "Search menu options" }), "cooldowns");
    expect(screen.getByText("No matching World controls")).toBeVisible();

    await user.clear(screen.getByRole("textbox", { name: "Search menu options" }));
    expect(screen.getByRole("heading", { name: "World" })).toBeVisible();

    await user.click(screen.getByRole("button", { name: "Player" }));
    await user.type(screen.getByRole("textbox", { name: "Search menu options" }), "cooldowns");
    expect(screen.getByText("Cooldown replacement under live validation")).toBeVisible();
    expect(screen.queryByText("God Mode")).not.toBeInTheDocument();
    await user.clear(screen.getByRole("textbox", { name: "Search menu options" }));

    await user.type(screen.getByRole("textbox", { name: "Search menu options" }), "sprint");
    expect(screen.getByText("Sprint No Drain")).toBeVisible();
    expect(screen.queryByText("God Mode")).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Inventory" })).not.toBeInTheDocument();

    await user.clear(screen.getByRole("textbox", { name: "Search menu options" }));
    expect(screen.getByText("God Mode")).toBeVisible();
  });

  it("wires the frameless titlebar controls to the preload boundary", async () => {
    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    expect(document.querySelector(".masthead")).toHaveClass("drag-region");
    const dragHandle = document.querySelector<HTMLElement>(".window-drag-handle");
    expect(dragHandle).toHaveClass("no-drag");
    expect(dragHandle).toBeEmptyDOMElement();

    dispatchPointerEvent(dragHandle!, "pointerdown", { button: 0, buttons: 1, pointerId: 7, screenX: 700, screenY: 80 });
    dispatchPointerEvent(dragHandle!, "pointermove", { button: 0, buttons: 1, pointerId: 7, screenX: 860, screenY: 210 });
    dispatchPointerEvent(dragHandle!, "pointerup", { button: 0, buttons: 0, pointerId: 7, screenX: 860, screenY: 210 });

    await user.click(screen.getByRole("button", { name: "Minimize application" }));
    await user.click(screen.getByRole("button", { name: "Maximize application" }));
    await user.click(screen.getByRole("button", { name: "Close application" }));

    expect(window.dawnwalkerDesktop?.beginWindowDrag).toHaveBeenCalledOnce();
    expect(window.dawnwalkerDesktop?.beginWindowDrag).toHaveBeenCalledWith(700, 80);
    expect(window.dawnwalkerDesktop?.updateWindowDrag).toHaveBeenCalledTimes(2);
    expect(window.dawnwalkerDesktop?.updateWindowDrag).toHaveBeenNthCalledWith(1, 860, 210);
    expect(window.dawnwalkerDesktop?.updateWindowDrag).toHaveBeenNthCalledWith(2, 860, 210);
    expect(window.dawnwalkerDesktop?.endWindowDrag).toHaveBeenCalledOnce();
    expect(window.dawnwalkerDesktop?.minimizeWindow).toHaveBeenCalledOnce();
    expect(window.dawnwalkerDesktop?.toggleMaximizeWindow).toHaveBeenCalledOnce();
    expect(window.dawnwalkerDesktop?.closeWindow).toHaveBeenCalledOnce();
  });

  it("reserves F10 exclusively for the Electron global window toggle", () => {
    const dispatch = vi.mocked(window.dawnwalkerDesktop!.dispatch);
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    fireEvent.keyDown(window, { key: "F10" });
    expect(dispatch).not.toHaveBeenCalled();
    expect(screen.getByText("F10")).toBeVisible();
    fireEvent.keyDown(window, { key: "F9" });
    expect(dispatch).not.toHaveBeenCalled();
    expect(screen.queryByRole("button", { name: "Kill All Enemies" })).not.toBeInTheDocument();
  });

  it("renders and dispatches independent RPG and Action difficulty controls only in the Player Combat section", async () => {
    const runtime = {
      ...verifiedRuntime([CONTROL_CAPABILITIES.rpgDifficulty, CONTROL_CAPABILITIES.actionDifficulty]),
      controls: { rpgDifficulty: 1, actionDifficulty: 2 },
    };
    const dispatch = installBridge(runtime, async (command) => appliedResult(
      command,
      "Difficulty applied with exact readback.",
      command.value,
    ));
    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));

    await user.click(screen.getAllByRole("button", { name: "World" })[0]);
    expect(screen.queryByRole("combobox", { name: "RPG Difficulty" })).not.toBeInTheDocument();
    await user.click(screen.getAllByRole("button", { name: "Player" })[0]);
    const rpg = await screen.findByRole("combobox", { name: "RPG Difficulty" });
    const action = screen.getByRole("combobox", { name: "Action Difficulty" });
    await waitFor(() => expect(rpg).toHaveValue("1"));
    expect(action).toHaveValue("2");
    expect(screen.queryByLabelText("Game Difficulty")).not.toBeInTheDocument();
    expect(screen.getByText("Two-axis development pilot")).toBeVisible();

    await user.selectOptions(rpg, "Nightmare");
    await user.selectOptions(action, "Story");
    await waitFor(() => expect(dispatch).toHaveBeenCalledTimes(2));
    expect(dispatch.mock.calls.map(([command]) => ({ capability: command.capability, value: command.value }))).toEqual([
      { capability: CONTROL_CAPABILITIES.rpgDifficulty, value: 3 },
      { capability: CONTROL_CAPABILITIES.actionDifficulty, value: 0 },
    ]);
  });

  // The Blood Energy owner-lock test was removed with the Blood Energy slider itself. The
  // direct setter is no longer offered anywhere, so there is no owner conflict left to gate.

  it("names the verified build when no marketing version has been confirmed for it", async () => {
    // What happens after a game patch: the executable and Steam build verify, but the
    // in-game version screen has not been re-checked, so no semver is claimed.
    installBridge({ ...verifiedRuntime([]), installedBuildId: "25191761", installedGameChangelist: "258042" });
    render(<App />);
    expect(await screen.findByText(/Game build 25191761 \(CL 258042\)/)).toBeVisible();
    expect(screen.queryByText(/Game version unavailable/)).not.toBeInTheDocument();
  });

  it("falls back to the build id alone when even the changelist is unknown", async () => {
    installBridge({ ...verifiedRuntime([]), installedBuildId: "25191761" });
    render(<App />);
    expect(await screen.findByText(/Game build 25191761/)).toBeVisible();
  });

  it("shows the installed build without enabling unverified active bridge claims", async () => {
    const user = userEvent.setup();
    const dispatch = installBridge({ ...verifiedRuntime([CONTROL_CAPABILITIES.godMode]), interactionEligible: false, buildVerified: false,
      installedBuildId: "25129649", verifiedBuildId: "25107392",
      installedGameVersion: { version: "1.0.3", changelist: "257186" },
      compatibilityIssue: "Installed game build differs from the reviewed build.", activeCapabilities: [CONTROL_CAPABILITIES.godMode] });
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const toggle = await screen.findByRole("button", { name: "God Mode: unverified" });
    expect(toggle).toBeDisabled();
    expect(toggle).not.toHaveAttribute("aria-pressed");
    expect(toggle).not.toHaveClass("toggle-on");
    expect(screen.queryByRole("region", { name: "Menu status" })).not.toBeInTheDocument();
    expect(screen.getByText(/Game 1.0.3 \(257186\)/)).toBeVisible();
    await user.click(toggle);
    expect(dispatch).not.toHaveBeenCalled();
    await user.click(screen.getByRole("button", { name: "Settings" }));
    expect(screen.queryByText("Installed game build")).not.toBeInTheDocument();
    expect(screen.queryByText("Runtime-tested build")).not.toBeInTheDocument();
    expect(screen.queryByText("Runtime bridge")).not.toBeInTheDocument();
    expect(screen.queryByText("Available gameplay controls")).not.toBeInTheDocument();
    expect(screen.queryByText(/Gameplay readbacks and commands are blocked/)).not.toBeInTheDocument();
    const search = screen.getByRole("textbox", { name: "Search menu options" });
    for (const query of ["local settings", "runtime", "hotkeys", "installed build"]) {
      fireEvent.change(search, { target: { value: query } });
      expect(screen.getByText("No matching Settings controls")).toBeVisible();
    }
  });

  it("keeps protocol capability parity while rendering only the remaining controls", async () => {
    expect(RENDERER_GAMEPLAY_CAPABILITIES).toHaveLength(GAMEPLAY_CAPABILITIES.length);
    expect(new Set(RENDERER_GAMEPLAY_CAPABILITIES)).toEqual(new Set(GAMEPLAY_CAPABILITIES));

    const user = userEvent.setup();
    render(<App />); fireEvent.click(screen.getByRole("button", { name: /^Player$/ }));
    const renderedCapabilities = new Set(
      [...document.querySelectorAll<HTMLElement>("[data-capability]")].map((element) => element.dataset.capability),
    );
    for (const category of ["World", "Teleport", "Visuals", "Quests"]) {
      await user.click(screen.getByRole("button", { name: category }));
      document.querySelectorAll<HTMLElement>("[data-capability]").forEach((element) => renderedCapabilities.add(element.dataset.capability));
    }

    // The protocol still carries every capability, but the menu only renders the ones it
    // actually offers. These stay in the contract for the bridge and for later promotion.
    const unrendered: readonly string[] = [
      CONTROL_CAPABILITIES.locationReadback,
      CONTROL_CAPABILITIES.playerInfo,
      CONTROL_CAPABILITIES.hudVisible,
      CONTROL_CAPABILITIES.infiniteHealth,
      CONTROL_CAPABILITIES.unlimitedStamina,
      CONTROL_CAPABILITIES.bloodEnergy,
      CONTROL_CAPABILITIES.traitPoints,
      CONTROL_CAPABILITIES.addLevel,
      CONTROL_CAPABILITIES.unblockTrait,
      CONTROL_CAPABILITIES.addItem,
    ];
    expect(renderedCapabilities).toEqual(new Set(GAMEPLAY_CAPABILITIES.filter(capability => !unrendered.includes(capability))));
  });
});

