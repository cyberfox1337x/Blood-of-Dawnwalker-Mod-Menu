import { describe, expect, it, vi } from "vitest";
import { applyGameEyeColor, MAX_GAME_EYE_GLOW } from "./gameEyeColor";
import type { ImportedMenuSnapshot, ImportedMenuTransport } from "./importedMenuContract";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("game_eye_color_acknowledgement_tests");
const snapshot: ImportedMenuSnapshot = { schema: 1, sessionId: "session", revision: 1, ready: true, sections: [] };
function fixture(states: ImportedMenuSnapshot[] = []) {
  const state = vi.fn().mockResolvedValue(states.at(-1) ?? snapshot).mockResolvedValueOnce(snapshot);
  for (const entry of states) state.mockResolvedValueOnce(entry);
  return { state, dispatch: vi.fn().mockResolvedValue({ accepted: true, operationId: "eye-id", message: "queued" }) } satisfies ImportedMenuTransport;
}
const wait = async () => undefined;
describe("native eye color acknowledgement", () => {
  it("waits for the exact operation rather than unrelated completion", async () => {
    const transport = fixture([{ ...snapshot, operation: { id: "other", status: "completed" } },
      { ...snapshot, operation: { id: "eye-id", status: "completed" } }]);
    await applyGameEyeColor(transport, "#AA44CC", 0, wait);
    expect(transport.state).toHaveBeenCalledTimes(3);
    expect(transport.dispatch).toHaveBeenCalledWith({ sessionId: "session", sectionId: "DWEyeColor", action: "set", itemId: "color", value: "#aa44cc" });
  });
  it("restores through the explicit native restore action", async () => {
    const transport = fixture([{ ...snapshot, operation: { id: "eye-id", status: "completed" } }]);
    await applyGameEyeColor(transport, null, 0, wait);
    expect(transport.dispatch).toHaveBeenCalledWith({ sessionId: "session", sectionId: "DWEyeColor", action: "invoke", itemId: "restore" });
  });
  it("rejects missing operation IDs and native failures", async () => {
    const missing = fixture(); missing.dispatch.mockResolvedValue({ accepted: true, message: "queued" });
    await expect(applyGameEyeColor(missing, "#ff0000", 0, wait)).rejects.toThrow("did not identify");
    const failed = fixture([{ ...snapshot, operation: { id: "eye-id", status: "failed", message: "Original eyes restored" } }]);
    await expect(applyGameEyeColor(failed, "#ff0000", 0, wait)).rejects.toThrow("Original eyes restored");
  });
  it("rejects session replacement and bounded timeout", async () => {
    await expect(applyGameEyeColor(fixture([{ ...snapshot, sessionId: "new" }]), "#ff0000", 0, wait)).rejects.toThrow("session changed");
    const transport = fixture();
    await expect(applyGameEyeColor(transport, "#ff0000", 0, wait)).rejects.toThrow("timed out");
    expect(transport.state).toHaveBeenCalledTimes(41);
  });
  it("sends the glow first, and only when the live section exposes it", async () => {
    const glowSection = { id: "DWEyeColor", title: "Eye", items: [{ id: "color", type: "input" as const, label: "Eye color" }, { id: "glow", type: "number" as const, label: "Eye glow strength" }] };
    const withGlow: ImportedMenuSnapshot = { ...snapshot, sections: [glowSection] };
    const transport = { state: vi.fn().mockResolvedValue({ ...withGlow, operation: { id: "eye-id", status: "completed" } }).mockResolvedValueOnce(withGlow),
      dispatch: vi.fn().mockResolvedValue({ accepted: true, operationId: "eye-id", message: "queued" }) } satisfies ImportedMenuTransport;
    await applyGameEyeColor(transport, "#20F6FF", 2.24, wait);
    expect(transport.dispatch.mock.calls.map(([request]) => request)).toEqual([
      { sessionId: "session", sectionId: "DWEyeColor", action: "set", itemId: "glow", value: 2.2 },
      { sessionId: "session", sectionId: "DWEyeColor", action: "set", itemId: "color", value: "#20f6ff" },
    ]);
    // A mod without the glow item (pre-update install) still gets the colour, nothing else.
    const legacy = fixture([{ ...snapshot, operation: { id: "eye-id", status: "completed" } }]);
    await applyGameEyeColor(legacy, "#20F6FF", 2.2, wait);
    expect(legacy.dispatch).toHaveBeenCalledTimes(1);
    expect(legacy.dispatch).toHaveBeenCalledWith({ sessionId: "session", sectionId: "DWEyeColor", action: "set", itemId: "color", value: "#20f6ff" });
    // Restore never sends a glow.
    const restoring = { ...transport, dispatch: vi.fn().mockResolvedValue({ accepted: true, operationId: "eye-id", message: "queued" }) };
    await applyGameEyeColor(restoring, null, 2.2, wait);
    expect(restoring.dispatch).toHaveBeenCalledTimes(1);
    await expect(applyGameEyeColor(transport, "#20f6ff", MAX_GAME_EYE_GLOW + 1, wait)).rejects.toThrow("glow strength");
  });
  it("does not dispatch invalid input or unavailable sessions", async () => {
    const transport = fixture();
    await expect(applyGameEyeColor(transport, "red", 0, wait)).rejects.toThrow("valid eye color");
    transport.state.mockReset().mockResolvedValue({ ...snapshot, ready: false });
    await expect(applyGameEyeColor(transport, "#ff0000", 0, wait)).rejects.toThrow("Load your game");
    expect(transport.dispatch).not.toHaveBeenCalled();
  });
});
