import { expect, it } from "vitest";
import { buildShortcutScript, toastShortcutPath } from "./windowsToastIdentity.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("windows_toast_identity_tests");

const BACKSLASH = String.fromCharCode(92);
const windowsPath = (...segments: string[]) => ["C:", ...segments].join(BACKSLASH);

it("places the shortcut in the user's own Start Menu programs folder", () => {
  const path = toastShortcutPath(windowsPath("Users", "Someone", "AppData", "Roaming"), "Blood of Dawnwalker Mod Menu");
  expect(path).toContain(["Microsoft", "Windows", "Start Menu", "Programs"].join(BACKSLASH));
  expect(path.endsWith("Blood of Dawnwalker Mod Menu.lnk")).toBe(true);
});

it("carries the target, the model id and the property that makes Windows deliver the toast", () => {
  const script = buildShortcutScript({
    shortcutPath: windowsPath("menu", "Menu.lnk"),
    executablePath: windowsPath("menu", "Menu.exe"),
    appUserModelId: "com.example.menu",
    iconLocation: windowsPath("menu", "Menu.exe") + ",0",
  });
  expect(script).toContain("'com.example.menu'");
  expect(script).toContain("Menu.exe'");
  expect(script).toContain("WScript.Shell");
  // The System.AppUserModel.ID property key; without it Windows drops the toast.
  expect(script).toContain("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
  expect(script).toContain("Write-Output 'registered'");
});

it("quotes a path containing an apostrophe so it cannot become PowerShell syntax", () => {
  const script = buildShortcutScript({
    shortcutPath: windowsPath("Users", "O'Brien", "Menu.lnk"),
    executablePath: windowsPath("Users", "O'Brien", "Menu.exe"),
    appUserModelId: "com.example.menu",
    iconLocation: windowsPath("Users", "O'Brien", "Menu.exe") + ",0",
  });
  expect(script).toContain("O''Brien");
  // A single unescaped apostrophe would end the literal and let the rest run.
  expect(script).not.toMatch(/[^']'[^']*O'Brien/);
});

it("pins the shortcut's icon, since the taskbar draws the menu from it", () => {
  const script = buildShortcutScript({
    shortcutPath: windowsPath("menu", "Menu.lnk"),
    executablePath: windowsPath("menu", "Menu.exe"),
    appUserModelId: "com.example.menu",
    iconLocation: windowsPath("menu", "build-assets", "icon.ico"),
  });
  // Left unset, the shortcut shows whichever executable last wrote it - Electron's own
  // atom after an unpacked run - and every window with the model id inherits that.
  expect(script).toContain("$link.IconLocation=$icon;");
  expect(script).toContain("icon.ico'");
});
