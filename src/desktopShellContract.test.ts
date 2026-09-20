import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_desktop_shell_contract_tests");

const electronSource = readFileSync(resolve(process.cwd(), "electron/main.ts"), "utf8");
const preloadSource = readFileSync(resolve(process.cwd(), "electron/preload.cts"), "utf8");
const rendererSource = readFileSync(resolve(process.cwd(), "src/App.tsx"), "utf8");
const dragHandleSource = readFileSync(resolve(process.cwd(), "src/WindowDragHandle.tsx"), "utf8");
const packageManifest = JSON.parse(readFileSync(resolve(process.cwd(), "package.json"), "utf8")) as {
  scripts?: Record<string, string>;
};

describe("Dawnwalker desktop shell contract", () => {
  it("builds current renderer and Electron sources before a local start", () => {
    expect(packageManifest.scripts?.start).toBe("npm run build && electron .");
  });

  it("uses F10 to minimize and restore the native window", () => {
    expect(electronSource).toContain('const WINDOW_TOGGLE_HOTKEY = "F10"');
    expect(electronSource).toContain("globalShortcut.register(WINDOW_TOGGLE_HOTKEY");
    expect(electronSource).toContain("mainWindow.minimize()");
    expect(electronSource).toContain("showAndFocus(mainWindow)");
    expect(electronSource).toContain("globalShortcut.unregisterAll()");
    expect(electronSource).not.toContain('WINDOW_TOGGLE_HOTKEY = "Insert"');
  });

  it("routes global F9 through the isolated renderer action and authorized runtime dispatch", () => {
    expect(electronSource).toContain('const ADD_GOLD_HOTKEY = "F9"');
    expect(electronSource).toContain("globalShortcut.register(ADD_GOLD_HOTKEY");
    expect(electronSource).toContain('mainWindow.webContents.send("dawnwalker:gameplay-hotkey", ADD_GOLD_HOTKEY_ACTION)');
    expect(preloadSource).toContain('ipcRenderer.on("dawnwalker:gameplay-hotkey"');
    expect(preloadSource).toContain('if (action === "add-gold") listener(action)');
    expect(rendererSource).toContain('void addGold(ADD_GOLD_HOTKEY_AMOUNT)');
    expect(rendererSource).toContain('dispatchGameplay(CONTROL_CAPABILITIES.addGold, requestedDelta)');
  });

  it("never consumes F10 as a renderer gameplay action", () => {
    expect(rendererSource).not.toMatch(/key\s*===\s*["']f10["']/i);
    expect(rendererSource).not.toMatch(/if\s*\([^)]*f10[^)]*\)\s*performAction/i);
  });

  it("routes human pointer dragging through a sender-bound main-process handler", () => {
    expect(preloadSource).toContain('{ action: "start", screenX, screenY }');
    expect(preloadSource).toContain('{ action: "move", screenX, screenY }');
    expect(preloadSource).toContain('{ action: "end" }');
    expect(electronSource).toContain('ipcMain.on("dawnwalker:window-drag"');
    expect(electronSource).toContain("BrowserWindow.fromWebContents(event.sender)");
    expect(electronSource).toContain("activeWindowDrag.senderId !== event.sender.id");
    expect(electronSource).toContain("normalizeWindowDragPoint(candidate.screenX, candidate.screenY)");
    expect(electronSource).toContain("targetWindow.setPosition(nextPosition.x, nextPosition.y, false)");
    expect(dragHandleSource).toContain("onPointerDown={beginDrag}");
    expect(dragHandleSource).toContain("onPointerMove={updateDrag}");
    expect(dragHandleSource).toContain("onPointerUp={endDrag}");
  });

  it("enforces runtime authorization in the main process before dispatch", () => {
    expect(electronSource).toContain("evaluateRuntimeControlAuthorization(status");
    expect(electronSource).toContain("isRuntimeDispatchAuthorized(status, authorization, command)");
    expect(electronSource).toContain("expectedBootId: command.sessionId");
  });
});
