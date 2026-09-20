import { afterEach, describe, expect, it, vi } from "vitest";
import { createEyeColorSelection } from "./eyeColorSelection";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("eye_color_selection_tests");

function deferred() {
  let resolve!: () => void;
  let reject!: (reason: Error) => void;
  const promise = new Promise<void>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
afterEach(() => vi.useRealTimers());

describe("eye color selection scheduling", () => {
  it("coalesces drag events and waits for native completion before reporting applied", async () => {
    vi.useFakeTimers();
    const native = deferred();
    const apply = vi.fn(() => native.promise), notify = vi.fn();
    const selection = createEyeColorSelection({ apply, notify });
    selection.request("#AA1122");
    await vi.advanceTimersByTimeAsync(200);
    selection.request("#223344");
    await vi.advanceTimersByTimeAsync(249);
    expect(apply).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(apply).toHaveBeenCalledExactlyOnceWith("#223344", 0);
    expect(notify).toHaveBeenLastCalledWith({ phase: "pending", value: "#223344" });
    native.resolve();
    await vi.advanceTimersByTimeAsync(0);
    expect(notify).toHaveBeenLastCalledWith({ phase: "applied", value: "#223344" });
  });

  it("serializes writes and keeps only the latest queued choice", async () => {
    vi.useFakeTimers();
    const first = deferred(), second = deferred();
    const apply = vi.fn().mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise), notify = vi.fn();
    const selection = createEyeColorSelection({ apply, notify });
    selection.request("#111111");
    await vi.advanceTimersByTimeAsync(250);
    selection.request("#222222");
    selection.request("#333333");
    await vi.advanceTimersByTimeAsync(250);
    expect(apply).toHaveBeenCalledTimes(1);
    first.resolve();
    await vi.advanceTimersByTimeAsync(0);
    expect(apply).toHaveBeenLastCalledWith("#333333", 0);
    expect(notify.mock.calls.some(([state]) => state.phase === "applied")).toBe(false);
    second.resolve();
    await vi.advanceTimersByTimeAsync(0);
    expect(notify).toHaveBeenLastCalledWith({ phase: "applied", value: "#333333" });
  });

  it("restores immediately when idle and after the current write when busy", async () => {
    vi.useFakeTimers();
    const first = deferred();
    const apply = vi.fn().mockReturnValueOnce(first.promise).mockResolvedValue(undefined);
    const selection = createEyeColorSelection({ apply, notify: vi.fn() });
    selection.request("#112233");
    await vi.advanceTimersByTimeAsync(250);
    selection.request(null);
    expect(apply).toHaveBeenCalledTimes(1);
    first.resolve();
    await vi.advanceTimersByTimeAsync(0);
    expect(apply).toHaveBeenLastCalledWith(null, 0);
    selection.request("#ffffff");
    selection.request(null);
    expect(apply).toHaveBeenCalledTimes(3);
    await vi.advanceTimersByTimeAsync(300);
    expect(apply).toHaveBeenCalledTimes(3);
  });

  it("drops stale completion and pending colors after a session change", async () => {
    vi.useFakeTimers();
    const first = deferred();
    const apply = vi.fn(() => first.promise), notify = vi.fn();
    const selection = createEyeColorSelection({ apply, notify });
    selection.request("#112233");
    await vi.advanceTimersByTimeAsync(250);
    selection.request("#abcdef");
    selection.invalidate();
    first.reject(new Error("old session"));
    await vi.advanceTimersByTimeAsync(500);
    expect(apply).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenLastCalledWith({ phase: "idle", value: null });
  });

  it("reports failures and permits retry, without accepting invalid colors", async () => {
    vi.useFakeTimers();
    const apply = vi.fn().mockRejectedValueOnce(new Error("Game changed form")).mockResolvedValue(undefined), notify = vi.fn();
    const selection = createEyeColorSelection({ apply, notify });
    expect(() => selection.request("red")).toThrow("six-digit");
    selection.request("#112233");
    await vi.advanceTimersByTimeAsync(250);
    expect(notify).toHaveBeenLastCalledWith({ phase: "error", value: "#112233", message: "Game changed form" });
    selection.request("#112233");
    await vi.advanceTimersByTimeAsync(250);
    expect(notify).toHaveBeenLastCalledWith({ phase: "applied", value: "#112233" });
  });

  it("cancels unsent work and suppresses callbacks after disposal", async () => {
    vi.useFakeTimers();
    const apply = vi.fn(), notify = vi.fn();
    const selection = createEyeColorSelection({ apply, notify });
    selection.request("#112233");
    selection.dispose();
    selection.request(null);
    await vi.advanceTimersByTimeAsync(500);
    expect(apply).not.toHaveBeenCalled();
    expect(notify).toHaveBeenCalledTimes(1);
  });

  it("does not report an already-sent operation after disposal", async () => {
    vi.useFakeTimers();
    const native = deferred();
    const apply = vi.fn(() => native.promise), notify = vi.fn();
    const selection = createEyeColorSelection({ apply, notify });
    selection.request("#112233");
    await vi.advanceTimersByTimeAsync(250);
    selection.request("#ffffff");
    selection.dispose();
    native.resolve();
    await vi.advanceTimersByTimeAsync(500);
    expect(apply).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledTimes(2);
    expect(notify.mock.calls.every(([state]) => state.phase === "pending")).toBe(true);
  });
});

describe("eye color selection glow", () => {
  it("carries the glow with the colour and drops it on restore", async () => {
    vi.useFakeTimers();
    const apply = vi.fn().mockResolvedValue(undefined);
    const selection = createEyeColorSelection({ apply, notify: vi.fn(), delayMs: 10 });
    selection.request("#20F6FF", 2.2);
    await vi.advanceTimersByTimeAsync(10);
    expect(apply).toHaveBeenLastCalledWith("#20f6ff", 2.2);
    selection.request(null, 2.2);
    await vi.advanceTimersByTimeAsync(0);
    expect(apply).toHaveBeenLastCalledWith(null, 0);
    expect(() => selection.request("#20f6ff", -1)).toThrow("glow strength");
    selection.dispose();
    vi.useRealTimers();
  });
});
