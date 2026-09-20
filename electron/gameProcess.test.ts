import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_game_process_tests");

// The process check spawns tasklist; these tests replace child_process so the cache
// behaviour is pinned without touching the real process list.
const execFile = vi.fn();
vi.mock("node:child_process", () => { const shim = (...args: unknown[]) => execFile(...args); return { default: { execFile: shim }, execFile: shim }; });

function answer(stdout: string) {
  execFile.mockImplementation((_file: unknown, _args: unknown, _options: unknown, callback: (error: Error | null, result: { stdout: string; stderr: string }) => void) => {
    callback(null, { stdout, stderr: "" });
  });
}

describe("isDawnwalkerRunning cache", () => {
  const platform = process.platform;
  beforeEach(() => { Object.defineProperty(process, "platform", { value: "win32" }); execFile.mockReset(); });
  afterEach(() => { Object.defineProperty(process, "platform", { value: platform }); vi.useRealTimers(); });

  it("spawns tasklist once for concurrent callers and reuses the answer inside the window", async () => {
    vi.useFakeTimers({ now: 1_000_000 });
    const { isDawnwalkerRunning, resetDawnwalkerRunningCache } = await import("./gameProcess.js");
    resetDawnwalkerRunningCache();
    answer('"Dawnwalker.exe","1234","Console","1","4,000 K"\r\n');
    const [first, second] = await Promise.all([isDawnwalkerRunning(), isDawnwalkerRunning()]);
    expect(first).toBe(true); expect(second).toBe(true);
    expect(execFile).toHaveBeenCalledTimes(1);
    vi.setSystemTime(1_000_000 + 5000);
    expect(await isDawnwalkerRunning()).toBe(true);
    expect(execFile).toHaveBeenCalledTimes(1);
    // Past the window the process list is asked again and a stopped game is reported.
    vi.setSystemTime(1_000_000 + 6100);
    answer('"explorer.exe","99","Console","1","4,000 K"\r\n');
    expect(await isDawnwalkerRunning()).toBe(false);
    expect(execFile).toHaveBeenCalledTimes(2);
  });

  it("never caches a failed verification", async () => {
    const { isDawnwalkerRunning, resetDawnwalkerRunningCache } = await import("./gameProcess.js");
    resetDawnwalkerRunningCache();
    answer("garbage");
    await expect(isDawnwalkerRunning()).rejects.toThrow("Unable to verify game process status");
    await expect(isDawnwalkerRunning()).rejects.toThrow("Unable to verify game process status");
    expect(execFile).toHaveBeenCalledTimes(2);
  });

  it("rechecks a cached stopped result before permitting file changes", async () => {
    const { isDawnwalkerRunning, resetDawnwalkerRunningCache } = await import("./gameProcess.js");
    resetDawnwalkerRunningCache();
    answer('"explorer.exe","99","Console","1","4,000 K"\r\n');
    expect(await isDawnwalkerRunning()).toBe(false);
    answer('"Dawnwalker.exe","1234","Console","1","4,000 K"\r\n');
    expect(await isDawnwalkerRunning({ fresh: true })).toBe(true);
    expect(execFile).toHaveBeenCalledTimes(2);
  });

  it("refuses an unverifiable fresh probe even with a cached stopped result", async () => {
    const { isDawnwalkerRunning, resetDawnwalkerRunningCache } = await import("./gameProcess.js");
    resetDawnwalkerRunningCache();
    answer('"explorer.exe","99","Console","1","4,000 K"\r\n');
    expect(await isDawnwalkerRunning()).toBe(false);
    answer("garbage");
    await expect(isDawnwalkerRunning({ fresh: true })).rejects.toThrow("Unable to verify game process status");
  });
});
