import { cleanup, fireEvent, render, renderHook, screen, waitFor, act } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { IMPORTED_MENU_CATEGORIES, useImportedMenu, DEV_TESTING_SECTIONS } from "./importedMenuState";
import { ImportedMenuPanel, ImportedMenuConfirmation } from "./ImportedMenuPanel";
import { isDeveloperOption } from "./catalogOptions";
import type { ImportedMenuSnapshot } from "./importedMenuContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_panel_tests");
afterEach(cleanup);
it("routes read-only attack inspection only into Player combat and dispatches no mutation", () => {
  const dispatch = vi.fn(async () => undefined);
  const inspection: ImportedMenuSnapshot = { schema: 1, sessionId: "inspection-session", revision: 1, ready: true,
    sections: [{ id: "DWCombatDiscovery", title: "Attack settings inspection", items: [
      { id: "inspect", type: "button", label: "Inspect attack settings" },
      { id: "status", type: "label", label: "Inspection only" },
    ] }] };
  const { rerender } = render(<ImportedMenuPanel category="player" group="player" snapshot={inspection} disabled={false} dispatch={dispatch} />);
  expect(screen.queryByRole("button", { name: "Inspect attack settings" })).toBeNull();
  rerender(<ImportedMenuPanel category="player" group="combat" snapshot={inspection} disabled={false} dispatch={dispatch} />);
  fireEvent.click(screen.getByRole("button", { name: "Inspect attack settings" }));
  expect(dispatch).toHaveBeenCalledExactlyOnceWith({ action: "invoke", sectionId: "DWCombatDiscovery", itemId: "inspect" });
  expect(screen.queryByRole("switch")).toBeNull();
});
it("renders a native status checkbox as read-only without calling dispatch", () => {
  const dispatch = vi.fn(async () => undefined);
  const statusSnapshot = { schema: 1, sessionId: "status-session", revision: 1, ready: true, sections: [
    { id: "DWPhotoCamera", title: "Photo camera", items: [
      { id: "active", type: "checkbox", label: "Photo camera active", value: true, readOnly: true },
    ] },
  ] } as unknown as ImportedMenuSnapshot;
  render(<ImportedMenuPanel category="world" snapshot={statusSnapshot} disabled={false} dispatch={dispatch} />);
  const indicator = screen.getByRole("switch", { name: /Photo camera active/ });
  expect(indicator).toBeDisabled();
  expect(indicator).toBeChecked();
  expect(screen.queryByText(/^(ON|OFF)$/)).toBeNull();
  expect(screen.queryByText("Unavailable")).toBeNull();
  fireEvent.click(indicator);
  expect(dispatch).not.toHaveBeenCalled();
});
it("slows hidden polling and refreshes immediately on return without overlapping requests", async () => {
  vi.useFakeTimers();
  const hidden = vi.spyOn(document, "hidden", "get").mockReturnValue(false);
  const transport = { state: vi.fn(async () => snapshot), dispatch: vi.fn() };
  const hook = renderHook(() => useImportedMenu(true, transport));
  try {
    await act(async () => {});
    expect(transport.state).toHaveBeenCalledTimes(1);
    hidden.mockReturnValue(true);
    act(() => document.dispatchEvent(new Event("visibilitychange")));
    await act(async () => vi.advanceTimersByTimeAsync(9999));
    expect(transport.state).toHaveBeenCalledTimes(1);
    await act(async () => vi.advanceTimersByTimeAsync(1));
    expect(transport.state).toHaveBeenCalledTimes(2);
    hidden.mockReturnValue(false);
    await act(async () => document.dispatchEvent(new Event("visibilitychange")));
    expect(transport.state).toHaveBeenCalledTimes(3);
    await act(async () => vi.advanceTimersByTimeAsync(750));
    expect(transport.state).toHaveBeenCalledTimes(4);
  } finally {
    hook.unmount(); hidden.mockRestore(); vi.useRealTimers();
  }
});
const snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "world-1", revision: 1, ready: true, sections: [
  { id: "DWParryAssist", title: "Auto Parry", items: [{ id: "enabled", type: "checkbox", label: "Auto parry while blocking", value: false }] },
  { id: "DWSkills", title: "Skill Points", items: [{ type: "row", items: [{ id: "add", type: "button", label: "Add points" }] }] },
] };

describe("supplied menu controls", () => {
  it("disables controls on a current connection failure and recovers when a new session responds", async () => {
    vi.useFakeTimers();
    const replacement = { ...snapshot, sessionId: "world-2" };
    const transport = {
      state: vi.fn().mockResolvedValueOnce(snapshot).mockRejectedValueOnce(new Error("Runtime unavailable"))
        .mockResolvedValue(replacement),
      dispatch: vi.fn(async () => ({ accepted: true, message: "Queued" })),
    };
    const hook = renderHook(() => useImportedMenu(true, transport));
    try {
      await act(async () => {});
      await act(async () => vi.advanceTimersByTimeAsync(750));
      expect(hook.result.current.disabled).toBe(true);
      expect(hook.result.current.snapshot.message).toBe("Runtime unavailable");
      await act(async () => hook.result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
      expect(transport.dispatch).not.toHaveBeenCalled();
      await act(async () => vi.advanceTimersByTimeAsync(750));
      expect(hook.result.current.disabled).toBe(false);
      expect(hook.result.current.snapshot.message).toBeUndefined();
      await act(async () => hook.result.current.dispatch({ action: "invoke", sectionId: "DWPlayer", itemId: "refresh" }));
      expect(transport.dispatch).toHaveBeenCalledWith({ sessionId: "world-2", action: "invoke", sectionId: "DWPlayer", itemId: "refresh" });
    } finally { hook.unmount(); vi.useRealTimers(); }
  });
  it("ignores a superseded poll failure after a successful feature readback", async () => {
    vi.useFakeTimers();
    let rejectPoll!: (error: Error) => void;
    const updated = { ...snapshot, revision: 2 };
    const transport = {
      state: vi.fn().mockResolvedValueOnce(snapshot)
        .mockImplementationOnce(() => new Promise<ImportedMenuSnapshot>((_resolve, reject) => { rejectPoll = reject; }))
        .mockResolvedValue(updated),
      dispatch: vi.fn(async () => ({ accepted: true, message: "Queued", operationId: "latest-command" })),
    };
    const hook = renderHook(() => useImportedMenu(true, transport));
    try {
      await act(async () => {});
      await act(async () => vi.advanceTimersByTimeAsync(750));
      await act(async () => hook.result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
      expect(hook.result.current.snapshot.revision).toBe(2);
      await act(async () => rejectPoll(new Error("Old poll failed")));
      expect(hook.result.current.snapshot.ready).toBe(true);
      expect(hook.result.current.snapshot.message).toBeUndefined();
      expect(hook.result.current.disabled).toBe(false);
    } finally { hook.unmount(); vi.useRealTimers(); }
  });
  it("keeps unrelated controls available while only the requested switch shows applying", () => {
    const dispatch = vi.fn(async () => undefined);
    render(<ImportedMenuPanel category="player" snapshot={snapshot} disabled={false} pending
      pendingControl={{ sectionId: "DWParryAssist", itemId: "enabled" }} dispatch={dispatch} />);
    expect(screen.getByRole("switch")).toBeDisabled();
    expect(screen.getByText("Applying…")).toBeVisible();
    expect(screen.getByRole("button", { name: "Add points" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Refresh game lists & status" })).toBeEnabled();
    expect(screen.queryByText("Unavailable")).not.toBeInTheDocument();
  });
  it("rejects overlapping game writes with local feedback without marking the connection unavailable", async () => {
    const running: ImportedMenuSnapshot = { ...snapshot, operation: { id: "in-flight", status: "running" } };
    const transport = { state: vi.fn(async () => running), dispatch: vi.fn() };
    const { result } = renderHook(() => useImportedMenu(true, transport));
    await waitFor(() => expect(result.current.snapshot.ready).toBe(true));
    expect(result.current.disabled).toBe(false);
    await act(async () => result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
    expect(transport.dispatch).not.toHaveBeenCalled();
    expect(result.current.feedback).toEqual({ sectionId: "DWSkills", message: "Another game change is still applying. Try this control when it finishes." });
    expect(result.current.disabled).toBe(false);
  });
  it("withdraws the still-applying notice once nothing is applying", async () => {
    // The notice describes a moment. Left on screen after the work finishes it reports
    // a block that is not there, which is what made the item panel look stuck.
    let current: ImportedMenuSnapshot = { ...snapshot, operation: { id: "in-flight", status: "running" } };
    const transport = { state: vi.fn(async () => current), dispatch: vi.fn() };
    const { result } = renderHook(() => useImportedMenu(true, transport));
    await waitFor(() => expect(result.current.snapshot.ready).toBe(true));
    await act(async () => result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
    expect(result.current.feedback?.message).toBe("Another game change is still applying. Try this control when it finishes.");
    current = { ...snapshot, operation: { id: "in-flight", status: "completed" }, heartbeat: 2 };
    await waitFor(() => expect(result.current.feedback).toBeUndefined());
  });
  it("validates heartbeat polls without rerendering unchanged controls and retains state changes", async () => {
    vi.useFakeTimers();
    try {
      let next = { ...snapshot, heartbeat: 1 };
      let renders = 0;
      const transport = { state: vi.fn(async () => structuredClone(next)), dispatch: vi.fn(async () => ({ accepted: true, message: "Accepted" })) };
      const { result } = renderHook(() => { renders += 1; return useImportedMenu(true, transport); });
      await act(async () => { await Promise.resolve(); });
      const initialRenders = renders;
      next = { ...next, heartbeat: 2 };
      await act(async () => { await vi.advanceTimersByTimeAsync(750); });
      expect(transport.state).toHaveBeenCalledTimes(2);
      expect(renders).toBe(initialRenders);
      next = { ...next, ready: false, heartbeat: 3 };
      await act(async () => { await vi.advanceTimersByTimeAsync(750); });
      expect(result.current.snapshot.ready).toBe(false);
      next = { ...next, ready: true, revision: next.revision + 1, sections: [{ ...next.sections[0], title: "Changed title" }] };
      await act(async () => { await vi.advanceTimersByTimeAsync(750); });
      expect(result.current.snapshot.sections[0].title).toBe("Changed title");
      expect(result.current.snapshot.ready).toBe(true);
    } finally { vi.useRealTimers(); }
  });
  it("keeps a pending switch neutral and blocks duplicate requests until confirmed", () => {
    const dispatch = vi.fn(async () => undefined);
    const { rerender } = render(<ImportedMenuPanel category="player" group="combat" snapshot={snapshot} disabled pending dispatch={dispatch} />);
    const toggle = screen.getByRole("switch");
    expect(toggle).toBeDisabled();
    expect(toggle).toHaveAttribute("aria-busy", "true");
    expect(screen.getByText("Applying…")).toBeVisible();
    fireEvent.click(toggle);
    expect(dispatch).not.toHaveBeenCalled();
    rerender(<ImportedMenuPanel category="player" group="combat" snapshot={snapshot} disabled={false} dispatch={dispatch} />);
    expect(toggle).not.toBeChecked();
    expect(screen.queryByText(/^(ON|OFF)$/)).toBeNull();
    rerender(<ImportedMenuPanel category="player" group="combat" snapshot={{ ...snapshot, ready: false }} disabled dispatch={dispatch} />);
    expect(screen.getByText("Unavailable")).toBeVisible();
  });
  it("omits generic queued and completion notices without technical disclosures", () => {
    const completed: ImportedMenuSnapshot = { ...snapshot, operation: { id: "refresh-1", status: "completed", message: "Scheduled callback work completed..." }, messages: ["TRAIT_GRANT indexed=112"] };
    render(<ImportedMenuPanel category="player" snapshot={completed} disabled={false} dispatch={vi.fn()} />);
    expect(screen.queryByText("Finished — check the control status.")).toBeNull();
    expect(screen.queryByText("TRAIT_GRANT indexed=112")).toBeNull();
    expect(screen.queryByText("Scheduled callback work completed...")).toBeNull();
    expect(document.querySelector(".imported-menu details")).toBeNull();
  });
  it("places a genuine rejection inside its affected card", () => {
    render(<ImportedMenuPanel category="player" snapshot={snapshot} disabled={false} dispatch={vi.fn()}
      feedback={{ sectionId: "DWSkills", message: "Load a player before adding points." }} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Load a player before adding points.");
    expect(screen.getByRole("alert").closest("[data-imported-section]")).toHaveAttribute("data-imported-section", "DWSkills");
  });
  it("keeps transport rejection feedback but suppresses queued acknowledgement feedback", async () => {
    const transport = { state: vi.fn(async () => snapshot), dispatch: vi.fn(async () => ({ accepted: false, message: "Player changed; refresh before trying again." })) };
    const { result } = renderHook(() => useImportedMenu(true, transport));
    await waitFor(() => expect(result.current.snapshot.ready).toBe(true));
    await act(async () => result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
    expect(result.current.feedback).toEqual({ sectionId: "DWSkills", message: "Player changed; refresh before trying again." });
    transport.dispatch.mockResolvedValue({ accepted: true, message: "Request queued. Check the control's game status." });
    await act(async () => result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
    expect(result.current.feedback).toBeUndefined();
  });
  it("tracks the emitted command ID even when the following snapshot belongs to another session", async () => {
    let current = snapshot;
    const transport = {
      state: vi.fn(async () => current),
      dispatch: vi.fn(async () => {
        current = { ...snapshot, sessionId: "replacement-session", operation: { id: "unrelated", status: "completed" } };
        return { accepted: true, message: "Queued", operationId: "emitted-command" };
      }),
    };
    const { result } = renderHook(() => useImportedMenu(true, transport));
    await waitFor(() => expect(result.current.snapshot.ready).toBe(true));
    await act(async () => {
      expect(await result.current.dispatchTracked({ action: "invoke", sectionId: "DWSkills", itemId: "add" }))
        .toEqual({ accepted: true, operationId: "emitted-command", sessionId: snapshot.sessionId });
    });
  });
  it("preserves an asynchronous native failure in the original action's scope", async () => {
    let state: ImportedMenuSnapshot = snapshot;
    const transport = { state: vi.fn(async () => state), dispatch: vi.fn(async () => {
      state = { ...snapshot, operation: { id: "native-action", status: "queued" } };
      return { accepted: true, message: "Queued" };
    }) };
    const { result } = renderHook(() => useImportedMenu(true, transport));
    await waitFor(() => expect(result.current.snapshot.ready).toBe(true));
    await act(async () => result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
    state = { ...snapshot, operation: { id: "native-action", status: "failed", message: "Character development is unavailable; load a save." } };
    await waitFor(() => expect(result.current.feedback?.message).toBe("Character development is unavailable; load a save."), { timeout: 1800 });
    expect(result.current.feedback?.sectionId).toBe("DWSkills");
  });
  it("maps original groups and the supplied story settings and never adds Visuals, hidden God Mode or the removed warnings wall", () => {
    // Original sections plus controls published by the game bridge but rendered here:
    // reachable only through the command channel, several of them verified working.
    expect(Object.keys(IMPORTED_MENU_CATEGORIES)).toHaveLength(37);
    expect(IMPORTED_MENU_CATEGORIES.DWCombatDiscovery).toBe("player");
    for (const section of ["DWQuickslots", "DWCrafting", "DWLoadout"]) expect(IMPORTED_MENU_CATEGORIES[section]).toBe("inventory");
    for (const section of ["DWCourtAlert", "DWClock", "DWPhotoCamera"]) expect(IMPORTED_MENU_CATEGORIES[section]).toBe("world");
    // The hub tab tools and the stuck-popup tools are diagnostics, so they moved out of
    // World and into Settings > Dev testing. The sub-tab renders exactly this list and
    // the Settings body excludes exactly this list, so the two must not drift.
    expect([...DEV_TESTING_SECTIONS].sort()).toEqual(["DWHubTabs", "DWHubTags", "DWTutorialDismiss"]);
    for (const section of DEV_TESTING_SECTIONS) expect(IMPORTED_MENU_CATEGORIES[section]).toBe("settings");
    for (const section of ["DWTraitPoints", "DWXPMultiplier", "DWBloodSegments", "DWEyeColor"]) expect(IMPORTED_MENU_CATEGORIES[section]).toBe("player");
    // Developer probes stay unreachable on purpose.
    for (const probe of ["DWXPReadback", "DWFallDropTest", "DWXPAwardObservation"]) expect(IMPORTED_MENU_CATEGORIES[probe]).toBeUndefined();
    expect(IMPORTED_MENU_CATEGORIES.DWFormToggle).toBe("player");
    for (const section of ["DWCurrency", "DWItems", "DWMaterials", "DWManuals", "DWKeys"]) expect(IMPORTED_MENU_CATEGORIES[section]).toBe("inventory");
    for (const section of ["DWInfamyControl", "DWTimeControl", "DWStoryTimer", "DWStorySettings", "DWTimelessCourt"]) expect(IMPORTED_MENU_CATEGORIES[section]).toBe("world");
    expect(IMPORTED_MENU_CATEGORIES.DWShrines).toBe("teleport");
    expect(IMPORTED_MENU_CATEGORIES.DWFastTravel).toBeUndefined();
    expect(IMPORTED_MENU_CATEGORIES.DWMenuWarnings).toBeUndefined();
    expect(Object.values(IMPORTED_MENU_CATEGORIES)).not.toContain("visuals");
    expect(IMPORTED_MENU_CATEGORIES.DWGodMode).toBeUndefined();
  });
  it("hides the old day probe and exposes recovery only when it is needed", () => {
    const native: ImportedMenuSnapshot = { ...snapshot, sections: [{ id: "DWStorySettings", title: "Story settings", items: [
      { id: "days", type: "button", label: "Old day probe" }, { id: "dayOwned", type: "checkbox", label: "Recovery pending", value: false },
      { id: "daysEnabled", type: "checkbox", label: "90-day live", value: false },
    ] }] };
    const dispatch = vi.fn(async () => undefined);
    const { rerender } = render(<ImportedMenuPanel category="world" snapshot={native} disabled={false} dispatch={dispatch} />);
    expect(screen.queryByRole("button", { name: "Old day probe" })).toBeNull();
    expect(screen.queryByRole("switch", { name: /Recovery/ })).toBeNull();
    native.sections[0].items[1].value = true;
    rerender(<ImportedMenuPanel category="world" snapshot={{ ...native }} disabled={false} dispatch={dispatch} />);
    fireEvent.click(screen.getByRole("switch", { name: /Recovery/ }));
    expect(dispatch).toHaveBeenCalledWith({ action: "set", sectionId: "DWStorySettings", itemId: "dayOwned", value: false });
  });
  it("renders only the assigned category and sends explicit requested checkbox state", () => {
    const dispatch = vi.fn(async () => undefined);
    render(<ImportedMenuPanel category="player" group="combat" snapshot={snapshot} disabled={false} dispatch={dispatch} />);
    expect(screen.getByRole("switch")).toBeVisible();
    expect(screen.getByRole("switch").closest("details")).toBeNull();
    expect(screen.queryByText("Add points")).toBeNull();
    fireEvent.click(screen.getByRole("switch"));
    expect(dispatch).toHaveBeenCalledWith({ action: "set", sectionId: "DWParryAssist", itemId: "enabled", value: true });
    expect(screen.getByRole("switch")).not.toBeChecked();
  });
  it("keeps disconnected controls disabled including nested rows", () => {
    render(<ImportedMenuPanel category="player" snapshot={{ ...snapshot, ready: false }} disabled dispatch={vi.fn()} />);
    expect(screen.getByRole("heading", { name: "Skill Points" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Add points" })).toBeDisabled();
  });
  it("never dispatches a false-valued dropdown placeholder", () => {
    const dispatch = vi.fn(async () => undefined);
    const pickerSnapshot: ImportedMenuSnapshot = { ...snapshot, sections: [{ id: "DWMaterials", title: "Materials", items: [{ id: "material", type: "dropdown", label: "Material", value: false, options: [{ label: "Load a save first", value: false }, { label: "Iron", value: "iron" }] }] }] };
    render(<ImportedMenuPanel category="inventory" snapshot={pickerSnapshot} disabled={false} dispatch={dispatch} />);
    expect(screen.getByRole("heading", { name: "Materials" })).toBeVisible();
    expect(screen.getByRole("option", { name: "Load a save first" })).toBeDisabled();
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "0" } });
    expect(dispatch).not.toHaveBeenCalled();
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "1" } });
    expect(dispatch).toHaveBeenCalledWith({ action: "set", sectionId: "DWMaterials", itemId: "material", value: "iron" });
  });
  it("separates inventory groups from player progression without losing either", () => {
    const grouped = { ...snapshot, sections: [...snapshot.sections, { id: "DWItems", title: "Equipment", items: [] }] };
    const { rerender } = render(<ImportedMenuPanel category="player" group="player" snapshot={grouped} disabled dispatch={vi.fn()} />);
    expect(screen.getByText("Skill Points")).toBeInTheDocument();
    expect(screen.queryByText("Equipment")).toBeNull();
    rerender(<ImportedMenuPanel category="inventory" group="inventory" snapshot={grouped} disabled dispatch={vi.fn()} />);
    expect(screen.getByText("Equipment")).toBeInTheDocument();
    expect(screen.queryByText("Skill Points")).toBeNull();
  });
  it("honors native disabled rows and refreshes only on deliberate click", () => {
    const dispatch = vi.fn(async () => undefined);
    const nativeDisabled = { ...snapshot, sections: [{ id: "DWSkills", title: "Points", items: [{ type: "row", enabled: false, items: [{ id: "add", type: "button", label: "Add points" }] }] }] };
    render(<ImportedMenuPanel category="player" snapshot={nativeDisabled} disabled={false} dispatch={dispatch} />);
    expect(screen.getByRole("heading", { name: "Points" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Add points" })).toBeDisabled();
    expect(dispatch).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Refresh game lists & status" }));
    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith({ action: "refresh" });
  });
  it("returns exact confirmation token and explicit cancel without invoking an action", () => {
    const dispatch = vi.fn(async () => undefined);
    render(<ImportedMenuConfirmation snapshot={{ ...snapshot, confirmation: { token: "unique-token", title: "Convert upgrades?", message: "Consumed items are not restored.", confirmLabel: "Convert and respec" } }} pending={false} dispatch={dispatch} />);
    expect(screen.getByRole("button", { name: "Cancel" })).toHaveFocus();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(dispatch).toHaveBeenCalledWith({ action: "confirm", confirmationToken: "unique-token", confirmed: false });
  });
  it("uses the displayed session and readback instead of optimistic applied state", async () => {
    const transport = { state: vi.fn(async () => snapshot), dispatch: vi.fn(async () => ({ accepted: true, message: "Queued" })) };
    const { result } = renderHook(() => useImportedMenu(true, transport));
    await waitFor(() => expect(result.current.snapshot.ready).toBe(true));
    await act(async () => result.current.dispatch({ action: "invoke", sectionId: "DWSkills", itemId: "add" }));
    expect(transport.dispatch).toHaveBeenCalledWith({ action: "invoke", sectionId: "DWSkills", itemId: "add", sessionId: "world-1" });
    expect(result.current.message).toBe("Queued");
    expect(result.current.snapshot).toEqual(snapshot);
  });
  it("does not poll while an unrelated tab is active", () => {
    const transport = { state: vi.fn(async () => snapshot), dispatch: vi.fn() };
    renderHook(() => useImportedMenu(false, transport));
    expect(transport.state).not.toHaveBeenCalled();
  });
});

describe("developer catalog rows", () => {
  it("hides obsolete, debug and class-default items from pickers but keeps real items", () => {
    expect(isDeveloperOption("[OBSOLETE - TECHNICAL ITEM] Leonica Knife  [Weapons]")).toBe(true);
    expect(isDeveloperOption("[DB] Anca Knife  [Weapons]")).toBe(true);
    expect(isDeveloperOption("Default  Item Weapon Data Asset  [Weapons]")).toBe(true);
    expect(isDeveloperOption("Anca Knife  [Weapons]")).toBe(false);
    expect(isDeveloperOption("Default Sword of the Order  [Weapons]")).toBe(false);
  });
});
