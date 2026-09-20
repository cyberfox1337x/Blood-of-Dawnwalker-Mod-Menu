import { act, cleanup, renderHook } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { useImportedMenu } from "./importedMenuState";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
const cyberfox1337x = (name: string) => void name;
cyberfox1337x("quest_read_toggle_queue_tests");
afterEach(() => { cleanup(); vi.useRealTimers(); });

it("backs hidden menu polling off to ten seconds and refreshes immediately when shown", async () => {
  vi.useFakeTimers();
  Object.defineProperty(document, "hidden", { configurable: true, value: true });
  const snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "one", revision: 1, ready: true, sections: [] };
  const transport = { state: vi.fn(async () => snapshot), dispatch: vi.fn() };
  const hook = renderHook(() => useImportedMenu(true, transport));
  await act(async () => {});
  expect(transport.state).toHaveBeenCalledOnce();
  await act(async () => { await vi.advanceTimersByTimeAsync(9999); });
  expect(transport.state).toHaveBeenCalledOnce();
  await act(async () => { await vi.advanceTimersByTimeAsync(1); });
  expect(transport.state).toHaveBeenCalledTimes(2);

  Object.defineProperty(document, "hidden", { configurable: true, value: false });
  await act(async () => document.dispatchEvent(new Event("visibilitychange")));
  expect(transport.state).toHaveBeenCalledTimes(3);
  hook.unmount();
  Object.defineProperty(document, "hidden", { configurable: true, value: false });
});

async function setup(sectionId = "DWQuestReadback") {
  vi.useFakeTimers();
  let snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "one", revision: 1, ready: true,
    sections: [{ id: "DWPersonalFly", title: "Fly", items: [{ id: "enabled", type: "checkbox", label: "Fly", value: false }] }] };
  const dispatch = vi.fn(async (request) => {
    snapshot = { ...snapshot, revision: snapshot.revision + 1, operation: { id: request.action === "invoke" ? "read" : "toggle", status: "running" } };
    return { accepted: true, message: "Applying", operationId: snapshot.operation!.id };
  });
  const transport = { state: vi.fn(async () => snapshot), dispatch };
  const hook = renderHook(() => useImportedMenu(true, transport));
  await act(async () => {});
  await act(async () => { await hook.result.current.dispatch({ action: "invoke", sectionId, itemId: "refresh" }); });
  const toggle = () => hook.result.current.dispatch({ action: "set", sectionId: "DWPersonalFly", itemId: "enabled", value: true });
  const value = () => hook.result.current.snapshot.sections[0].items[0].value;
  const change = (patch: Partial<ImportedMenuSnapshot>) => { snapshot = { ...snapshot, ...patch, revision: snapshot.revision + 1 }; };
  return { ...hook, dispatch, toggle, value, change };
}

it("shows one switch intent immediately and dispatches it only after the quest read finishes", async () => {
  const h = await setup();
  await act(async () => { await h.toggle(); });
  expect(h.value()).toBe(true);
  expect(h.result.current.pendingControl).toEqual({ sectionId: "DWPersonalFly", itemId: "enabled" });
  expect(h.dispatch).toHaveBeenCalledTimes(1);
  await act(async () => { await h.toggle(); });
  expect(h.dispatch).toHaveBeenCalledTimes(1);
  h.change({ operation: { id: "read", status: "completed" } });
  await act(async () => { await vi.advanceTimersByTimeAsync(3000); });
  expect(h.dispatch).toHaveBeenCalledTimes(2);
  expect(h.dispatch.mock.calls[1][0]).toMatchObject({ action: "set", sessionId: "one", value: true });
});

it("never queues a switch behind a different game operation", async () => {
  const h = await setup("DWCorePlayer");
  await act(async () => { await h.toggle(); });
  expect(h.value()).toBe(false);
  h.change({ operation: { id: "read", status: "completed" } });
  await act(async () => { await vi.advanceTimersByTimeAsync(3000); });
  expect(h.dispatch).toHaveBeenCalledTimes(1);
});

it.each(["session", "timeout", "confirmation", "unmount"])("cancels queued intent on %s", async reason => {
  const h = await setup();
  await act(async () => { await h.toggle(); });
  if (reason === "session") h.change({ sessionId: "two" });
  if (reason === "confirmation") h.change({ confirmation: { token: "confirm", title: "Confirm", message: "Pending" } });
  if (reason === "unmount") h.unmount();
  await act(async () => { await vi.advanceTimersByTimeAsync(9000); });
  expect(h.dispatch).toHaveBeenCalledTimes(1);
  if (reason !== "unmount") expect(h.value()).toBe(false);
});

it("keeps requested state through interim native prewrite and phase snapshots", async () => {
  const h = await setup();
  h.change({ operation: { id: "read", status: "completed" } });
  await act(async () => { await vi.advanceTimersByTimeAsync(3000); });
  await act(async () => { await h.toggle(); });
  h.change({ sections: [{ id: "DWPersonalFly", title: "Fly", items: [{ id: "enabled", type: "checkbox", label: "Fly", value: true }] }] });
  await act(async () => { await vi.advanceTimersByTimeAsync(750); });
  h.change({ sections: [{ id: "DWPersonalFly", title: "Fly", items: [{ id: "enabled", type: "checkbox", label: "Fly", value: false }] }] });
  await act(async () => { await vi.advanceTimersByTimeAsync(750); });
  expect(h.value()).toBe(true);
  h.change({ operation: { id: "toggle", status: "failed", message: "Rejected" } });
  await act(async () => { await vi.advanceTimersByTimeAsync(3000); });
  expect(h.value()).toBe(false);
});
