import { EventEmitter } from "node:events";
import { describe, expect, it, vi } from "vitest";
import { createWindowLifecycle, showAndFocus } from "./windowLifecycle.js";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("window_lifecycle_tests");
function windowFixture() {
  const events = new EventEmitter();
  let destroyed = false;
  return {
    once: events.once.bind(events),
    isDestroyed: () => destroyed,
    isMinimized: vi.fn(() => false),
    restore: vi.fn(), show: vi.fn(), focus: vi.fn(),
    close: () => { destroyed = true; events.emit("closed"); },
  };
}
describe("main window shutdown and second instance", () => {
  it("rejects focus while native cleanup is pending after Alt+F4", async () => {
    const lifecycle = createWindowLifecycle<ReturnType<typeof windowFixture>>();
    const window = windowFixture(); lifecycle.track(window); window.close();
    lifecycle.beginQuit();
    let finish!: () => void;
    const cleanup = new Promise<void>(resolve => { finish = resolve; });
    lifecycle.focusExisting();
    expect(window.isMinimized).not.toHaveBeenCalled();
    expect(window.show).not.toHaveBeenCalled();
    expect(lifecycle.getWindow()).toBeNull();
    finish(); await cleanup;
    expect(lifecycle.isQuitting()).toBe(true);
    expect(() => lifecycle.track(windowFixture())).toThrow(/shutdown/);
  });
  it("does not focus a still-live window once quit has started", () => {
    const lifecycle = createWindowLifecycle<ReturnType<typeof windowFixture>>();
    const window = windowFixture(); lifecycle.track(window); lifecycle.beginQuit(); lifecycle.focusExisting();
    expect(window.show).not.toHaveBeenCalled();
  });
  it("restores a normal minimized instance but tolerates destruction during restore", () => {
    const window = windowFixture(); window.isMinimized.mockReturnValue(true);
    showAndFocus(window); expect(window.restore).toHaveBeenCalledOnce(); expect(window.focus).toHaveBeenCalledOnce();
    const closing = windowFixture(); closing.isMinimized.mockReturnValue(true); closing.restore.mockImplementation(closing.close);
    showAndFocus(closing); expect(closing.show).not.toHaveBeenCalled(); expect(closing.focus).not.toHaveBeenCalled();
  });
  it("an older closed callback cannot clear a newer tracked window", () => {
    const lifecycle = createWindowLifecycle<ReturnType<typeof windowFixture>>();
    const old = windowFixture(), current = windowFixture(); lifecycle.track(old); lifecycle.track(current); old.close();
    lifecycle.focusExisting(); expect(current.focus).toHaveBeenCalledOnce();
  });
});
