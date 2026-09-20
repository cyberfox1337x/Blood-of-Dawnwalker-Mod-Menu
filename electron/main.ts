import { createWindowLifecycle, showAndFocus } from "./windowLifecycle.js";
import { createInterfaceScaleStore } from "./interfaceScale.js";
import { createQuestReminderStore } from "./questReminderSetting.js";
import { buildReminderToastXml } from "./reminderToast.js";
import { ensureToastShortcut, toastShortcutPath } from "./windowsToastIdentity.js";
import { app, BrowserWindow, globalShortcut, ipcMain, Menu, net, Notification, protocol, screen, session, shell } from "electron";
import { mkdirSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { ASSET_SCHEME, createGameAssetStore } from "./gameAssets.js";
import { createBridgeTransport } from "./bridgeTransport.js";
import { createStoryDaySettings, handleStoryDayRequest } from "./storyDaySettings.js";
import { createFogSettings, type FogChange } from "./fogSettings.js";
import { isDawnwalkerRunning } from "./gameProcess.js";
import { resolveFeatureReference } from "./featureReferences.js";
import { createSaveEditor, type SaveEditRequest, type SaveRestoreRequest } from "./saveEditor.js";
import { createGameBuildInspector } from "./gameBuildIdentity.js";
import { createEyeAppearanceOwner } from "./eyeAppearanceOwner.js";
import { createImportedMenuOwner } from "./importedMenuOwner.js";
import { createQuestReminderMonitor, type QuestReminderEvent } from "./questReminderMonitor.js";
import {
  evaluateRuntimeControlAuthorization,
  isRuntimeDispatchAuthorized,
  PILOT_CONTROLS_ENVIRONMENT_VARIABLE,
} from "./runtimeAuthorization.js";
import { RUNTIME_CAPABILITY_SET } from "./runtimeCapabilities.js";
import {
  collectRuntimeControlReadback,
  collectRuntimePlayerReadback,
  collectRuntimeQuestJournalReadback,
} from "./runtimeReadback.js";
import {
  calculateWindowDragPosition,
  normalizeWindowDragPoint,
  type DragPoint,
  type DragRectangle,
} from "./windowDrag.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("electron_main");

const DESIGN_WIDTH = 1672;
const DESIGN_HEIGHT = 941;
const WINDOW_TOGGLE_HOTKEY = "F10";
const ADD_GOLD_HOTKEY = "F9";
const ADD_GOLD_HOTKEY_ACTION = "add-gold";
const currentDirectory = dirname(fileURLToPath(import.meta.url));
const developmentUrl = process.env.DAWNWALKER_DEV_URL;
const capturePath = process.env.DAWNWALKER_CAPTURE_PATH;
const gameBuildInspector = createGameBuildInspector({
  contractPath: app.isPackaged
    ? join(process.resourcesPath, "dawnwalker-runtime", "official-build.json")
    : resolve(currentDirectory, "..", "analysis", "dawnwalker-uue4ss", "official-build.json"),
  manifestPath: join(process.env["ProgramFiles(x86)"] ?? "C:\\Program Files (x86)", "Steam", "steamapps", "appmanifest_3751260.acf"),
});
const bridgeTransport = createBridgeTransport(
  join(app.getPath("temp"), "DawnwalkerModMenuBridge"),
  RUNTIME_CAPABILITY_SET,
);

type ActiveWindowDrag = Readonly<{
  senderId: number;
  windowId: number;
  initialBounds: DragRectangle;
  initialCursor: DragPoint;
}>;

if (capturePath) {
  const qaUserDataPath = join(app.getPath("temp"), `dawnwalker-menu-qa-${process.pid}`);
  mkdirSync(qaUserDataPath, { recursive: true });
  app.setPath("userData", qaUserDataPath);
}

function isSafeDevelopmentUrl(candidate: string): boolean {
  try {
    const parsedUrl = new URL(candidate);
    return parsedUrl.protocol === "http:" && parsedUrl.hostname === "127.0.0.1";
  } catch {
    return false;
  }
}

const interfaceScaleStore = createInterfaceScaleStore(join(app.getPath("userData"), "interface-scale.json"));
// Game icons exported by the owner's DwSav asset importer, served to the renderer as
// dw-asset://icon/<id>. The scheme must be registered before the app is ready.
const gameAssets = createGameAssetStore({ userDataPath: app.getPath("userData"), localAppDataPath: process.env.LOCALAPPDATA });
protocol.registerSchemesAsPrivileged([{ scheme: ASSET_SCHEME, privileges: { standard: true, secure: true, supportFetchAPI: true } }]);
const questReminderStore = createQuestReminderStore(join(app.getPath("userData"), "quest-reminder.json"));
// Windows shows a desktop notification under the identity of the app that raised it.
// Without an explicit model id a packaged Electron app can be attributed to the
// launcher instead, which drops the icon and the app name from the toast.
const APP_USER_MODEL_ID = "com.cyberfox1337x.dawnwalker.modmenu";
const notificationIcon = app.isPackaged
  ? join(process.resourcesPath, "notification-icon.png")
  : resolve(currentDirectory, "..", "build-assets", "icon.png");

// Windows drops a toast from a desktop app with no Start Menu shortcut carrying the
// same AppUserModelID - silently, with nothing in the notification centre. An installed
// build gets that shortcut from its installer; a portable or unpacked build does not,
// so the menu writes it once when reminders are switched on.
let toastShortcutReady: Promise<boolean> | undefined;
function ensureToastIdentity(): Promise<boolean> {
  toastShortcutReady ??= ensureToastShortcut({
    shortcutPath: toastShortcutPath(app.getPath("appData"), "Blood of Dawnwalker Mod Menu"),
    executablePath: process.execPath,
    appUserModelId: APP_USER_MODEL_ID,
    // A packaged executable carries the crest itself; an unpacked run is Electron's
    // binary, whose own icon is not the menu's, so the repository's .ico is used.
    iconLocation: app.isPackaged ? `${process.execPath},0` : resolve(currentDirectory, "..", "build-assets", "icon.ico"),
    keepExisting: !app.isPackaged,
  });
  return toastShortcutReady;
}

async function sendQuestReminderNotification(titleInput: unknown, bodyInput: unknown): Promise<boolean> {
  // The persisted setting is authoritative for both manual tests and background
  // journal changes. A stale renderer can never bypass a switch that was turned off.
  if (!questReminderStore.get() || !Notification.isSupported()) return false;
  await ensureToastIdentity();
  if (!questReminderStore.get()) return false;
  const title = typeof titleInput === "string" ? titleInput.slice(0, 120) : "";
  const body = typeof bodyInput === "string" ? bodyInput.slice(0, 240) : "";
  if (!title || !body) throw new Error("A quest reminder needs a title and a body.");
  if (process.platform === "win32") {
    const toastXml = buildReminderToastXml({ questTitle: title, objective: body, logoPath: notificationIcon });
    new Notification({ title, body, icon: notificationIcon, toastXml, silent: false }).show();
  } else {
    new Notification({ title, body, icon: notificationIcon, silent: false }).show();
  }
  return true;
}

let questReminderMonitor: ReturnType<typeof createQuestReminderMonitor> | undefined;

async function applyInterfaceScale(targetWindow: BrowserWindow, scale: unknown): Promise<number> {
  const savedScale = await interfaceScaleStore.set(scale);
  if (!targetWindow.isDestroyed() && !targetWindow.webContents.isDestroyed()) {
    targetWindow.webContents.setZoomFactor(savedScale / 100);
    targetWindow.webContents.send("dawnwalker:interface-scale-changed", savedScale);
  }
  return savedScale;
}

// dw-asset://icon/<id> -> <export>/icons/<id>.png; anything else is a 404 so the
// renderer's <img onError> can hide the picture instead of showing a broken image.
function registerGameAssetProtocol(): void {
  protocol.handle(ASSET_SCHEME, (request) => {
    const url = new URL(request.url);
    const id = decodeURIComponent(url.pathname.replace(/^\/+/, ""));
    const path = url.hostname === "icon" ? gameAssets.iconPath(id) : null;
    if (!path) return new Response("Not found", { status: 404 });
    return net.fetch(pathToFileURL(path).toString());
  });
}

function enforceLocalOnlyPolicy(): void {
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  session.defaultSession.setPermissionCheckHandler(() => false);

  session.defaultSession.webRequest.onBeforeRequest((details, callback) => {
    const isLocalFile = details.url.startsWith("file:") || details.url.startsWith(`${ASSET_SCHEME}://`);
    // glTF embedded images are decoded through renderer-owned object URLs.
    const isEmbeddedImage = ["image", "xhr"].includes(details.resourceType) && (details.url.startsWith("blob:null/")
      || details.url.startsWith("blob:file:///") || Boolean(developmentUrl && details.url.startsWith("blob:http://127.0.0.1:5173/")));
    const isDevelopmentRequest = developmentUrl
      ? details.url.startsWith("http://127.0.0.1:5173") || details.url.startsWith("ws://127.0.0.1:5173")
      : false;
    callback({ cancel: !isLocalFile && !isDevelopmentRequest && !isEmbeddedImage });
  });
}

async function captureWindow(targetWindow: BrowserWindow, targetPath: string): Promise<void> {
  const absoluteTarget = resolve(process.cwd(), targetPath);
  await mkdir(dirname(absoluteTarget), { recursive: true });
  await targetWindow.webContents.insertCSS("*, *::before, *::after { animation: none !important; transition: none !important; } .panel { opacity: 1 !important; transform: none !important; } .left-rail button:not(.active):hover { color: #aba7a0 !important; background: rgba(3, 4, 4, 0.74) !important; padding-left: 27px !important; }");
  await targetWindow.webContents.executeJavaScript(`document.fonts.ready.then(() => new Promise((resolveFrame) => requestAnimationFrame(() => requestAnimationFrame(resolveFrame))))`);
  await new Promise((resolveCaptureStyle) => setTimeout(resolveCaptureStyle, 250));
  const image = await targetWindow.webContents.capturePage();
  await writeFile(absoluteTarget, image.toPNG());
}

function createMainWindow(): BrowserWindow {
  const mainWindow = new BrowserWindow({
    width: DESIGN_WIDTH,
    height: DESIGN_HEIGHT,
    minWidth: 1100,
    minHeight: 620,
    frame: false,
    show: Boolean(capturePath),
    backgroundColor: "#040505",
    title: "Blood of Dawnwalker Mod Menu",
    icon: notificationIcon,
    autoHideMenuBar: true,
    webPreferences: {
      preload: join(currentDirectory, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      spellcheck: false,
      // Always off, not just for captures. With throttling on, Chromium stops drawing
      // and swapping frames while it considers the window background, and on Windows
      // its occlusion tracker can leave a restored frameless window in that state:
      // the window came back black after minimize/F10 and after the hidden-then-shown
      // startup, until a 1px resize forced a frame. The capture path already ran with
      // this off and never showed the symptom, which is what pointed at the cause.
      backgroundThrottling: false,
    },
  });

  // Belt and braces for the same fault: any transition back to visible schedules a
  // full repaint through the API meant for it, so a paint the compositor skipped
  // while the window was hidden or minimized is never left on screen.
  const repaintWhenShown = (): void => {
    if (!mainWindow.isDestroyed() && !mainWindow.webContents.isDestroyed()) mainWindow.webContents.invalidate();
  };
  mainWindow.on("show", repaintWhenShown);
  mainWindow.on("restore", repaintWhenShown);
  mainWindow.on("focus", repaintWhenShown);

  mainWindow.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  mainWindow.webContents.on("did-finish-load", () => mainWindow.webContents.setZoomFactor(interfaceScaleStore.get() / 100));
  mainWindow.webContents.on("before-input-event", (event, input) => {
    if (input.type !== "keyDown" || !input.control || input.alt || input.meta || input.isAutoRepeat) return;
    const change = ["+", "="].includes(input.key) ? 25 : input.key === "-" ? -25 : 0;
    if (!change && input.key !== "0") return;
    event.preventDefault();
    const scale = change ? Math.max(75, Math.min(200, interfaceScaleStore.get() + change)) : 100;
    void applyInterfaceScale(mainWindow, scale).catch((error: unknown) => {
      console.error("Unable to save interface scale:", error);
      if (!mainWindow.isDestroyed()) mainWindow.webContents.send("dawnwalker:interface-scale-error", "Could not save menu scale. Check that the menu's settings folder is writable.");
    });
  });
  mainWindow.webContents.on("will-navigate", (event) => event.preventDefault());
  // A renderer that dies leaves a black window with no way back for the user; reload it
  // once the crash is reported. A killed page is the user's own doing and is left alone.
  mainWindow.webContents.on("render-process-gone", (_event, details) => {
    console.error("Menu renderer process gone:", details.reason, details.exitCode);
    if (details.reason === "killed" || details.reason === "clean-exit" || mainWindow.isDestroyed()) return;
    setTimeout(() => { if (!mainWindow.isDestroyed()) mainWindow.webContents.reload(); }, 500);
  });
  mainWindow.on("unresponsive", () => console.error("Menu window unresponsive."));
  const publishMaximizedState = (): void => {
    if (!mainWindow.isDestroyed() && !mainWindow.webContents.isDestroyed()) {
      mainWindow.webContents.send("dawnwalker:window-maximized", mainWindow.isMaximized());
    }
  };
  mainWindow.on("maximize", publishMaximizedState);
  mainWindow.on("unmaximize", publishMaximizedState);
  if (!capturePath) {
    // ready-to-show alone was not enough: it only fires after a first paint while
    // hidden, and for this renderer (React plus a three.js character preview) it did
    // not fire at all - the window sat with no handle until F10 forced a show. The
    // page had loaded fine, so did-finish-load is the fallback. Whichever fires first
    // shows the window once; backgroundColor above means an early show is a dark
    // frame, not a white flash.
    const showOnce = (): void => {
      if (!mainWindow.isDestroyed() && !mainWindow.isVisible()) mainWindow.show();
    };
    mainWindow.once("ready-to-show", showOnce);
    mainWindow.webContents.once("did-finish-load", showOnce);
  }

  if (capturePath) {
    mainWindow.webContents.once("did-finish-load", () => {
      setTimeout(() => {
        void captureWindow(mainWindow, capturePath)
          .catch((error: unknown) => {
            console.error("Unable to capture Dawnwalker UI:", error);
            process.exitCode = 1;
          })
          .finally(() => app.quit());
      }, 900);
    });
  }

  if (developmentUrl && isSafeDevelopmentUrl(developmentUrl)) {
    void mainWindow.loadURL(developmentUrl);
  } else {
    void mainWindow.loadFile(join(currentDirectory, "..", "dist", "index.html"));
  }

  return mainWindow;
}

function registerWindowHandlers(): void {
  let activeWindowDrag: ActiveWindowDrag | null = null;
  const storyBuildInspector = createGameBuildInspector({
    contractPath: app.isPackaged ? join(process.resourcesPath, "imported-menu", "official-build.json")
      : resolve(currentDirectory, "..", "integration", "imported-menu", "official-build.json"),
    manifestPath: join(process.env["ProgramFiles(x86)"] ?? "C:\\Program Files (x86)", "Steam", "steamapps", "appmanifest_3751260.acf"),
  });
  const storyDaySettings = createStoryDaySettings({
    configurationPath: join(process.env.LOCALAPPDATA ?? join(app.getPath("home"), "AppData", "Local"), "Dawnwalker", "Saved", "Config", "Windows", "Game.ini"),
    backupDirectory: join(app.getPath("userData"), "configuration-backups"),
    isGameRunning: () => isDawnwalkerRunning({ fresh: true }),
    isBuildVerified: async () => (await storyBuildInspector.inspectInstalledBuild()).verified,
  });
  const fogSettings = createFogSettings({
    configurationPath: join(process.env.LOCALAPPDATA ?? join(app.getPath("home"), "AppData", "Local"), "Dawnwalker", "Saved", "Config", "Windows", "Engine.ini"),
    backupDirectory: join(app.getPath("userData"), "configuration-backups"),
    isGameRunning: () => isDawnwalkerRunning({ fresh: true }),
  });
  const saveEditor = createSaveEditor({
    saveDirectory: join(process.env.LOCALAPPDATA ?? join(app.getPath("home"), "AppData", "Local"), "Dawnwalker", "Saved", "SaveGames"),
    backupDirectory: join(app.getPath("userData"), "save-backups"),
    isGameRunning: () => isDawnwalkerRunning({ fresh: true }),
    // The DwSav-verified save editors read the game's own metadata from the asset export.
    metadataPaths: () => ({
      itemsJson: gameAssets.metadataPath("items.json"),
      traitsJson: gameAssets.metadataPath("traits.json"),
      defaultGameIni: gameAssets.metadataPath("DefaultGame.ini"),
      factTagsIni: gameAssets.metadataPath("FactTags.ini"),
      questsJson: gameAssets.metadataPath("quests.json"),
    }),
  });
  ipcMain.handle("dawnwalker:saves", async (event, action: unknown, payload: unknown) => {
    if (!BrowserWindow.fromWebContents(event.sender) || event.senderFrame !== event.sender.mainFrame) throw new Error("Invalid save request.");
    if (action === "list") return saveEditor.listSaves();
    if (action === "inspect" && typeof payload === "string") return saveEditor.inspectSave(payload);
    if (action === "backups" && typeof payload === "string") return saveEditor.listBackups(payload);
    if (action === "fields" && typeof payload === "string") return saveEditor.readFields(payload);
    if (action === "summary" && typeof payload === "string") return saveEditor.readSummary(payload);
    if (!payload || typeof payload !== "object") throw new Error("Invalid save operation.");
    if (action === "backup") return saveEditor.createBackup(payload as SaveRestoreRequest);
    if (action === "preview") return saveEditor.previewRestore(payload as SaveRestoreRequest);
    if (action === "restore") return saveEditor.restoreBackup(payload as SaveRestoreRequest & { previewToken: string });
    if (action === "edit") return saveEditor.editFields(payload as SaveEditRequest);
    throw new Error("Unknown save operation.");
  });

  ipcMain.handle("dawnwalker:game-assets", async (event, action: unknown) => {
    if (!BrowserWindow.fromWebContents(event.sender) || event.senderFrame !== event.sender.mainFrame) throw new Error("Invalid asset request.");
    if (action === "status") return gameAssets.status();
    if (action === "perks") return gameAssets.perks();
    throw new Error("Unknown asset operation.");
  });

  ipcMain.handle("dawnwalker:feature-reference", async (event, id: unknown) => {
    if (!BrowserWindow.fromWebContents(event.sender) || event.senderFrame !== event.sender.mainFrame) throw new Error("Invalid source-link request.");
    const url = resolveFeatureReference(id);
    if (!url) throw new Error("Unknown feature reference.");
    await shell.openExternal(url);
  });
  ipcMain.handle("dawnwalker:story-days", async (event, action: unknown, payload: unknown) => {
    if (!BrowserWindow.fromWebContents(event.sender) || event.senderFrame !== event.sender.mainFrame) throw new Error("Invalid configuration request.");
    return handleStoryDayRequest(storyDaySettings, action, payload);
  });
  ipcMain.handle("dawnwalker:fog", async (event, action: unknown, payload: unknown) => {
    if (!BrowserWindow.fromWebContents(event.sender) || event.senderFrame !== event.sender.mainFrame) throw new Error("Invalid configuration request.");
    if (action === "inspect") return fogSettings.inspect();
    if (action === "apply") return fogSettings.apply(payload as FogChange);
    if (action === "restore" && typeof payload === "string") return fogSettings.restore(payload);
    throw new Error("Unknown fog operation.");
  });

  ipcMain.on("dawnwalker:window-drag", (event, message: unknown) => {
    if (!message || typeof message !== "object") return;
    const candidate = message as Readonly<Record<string, unknown>>;
    if (candidate.action !== "start" && candidate.action !== "move" && candidate.action !== "end") return;

    const targetWindow = BrowserWindow.fromWebContents(event.sender);
    if (!targetWindow) return;

    if (candidate.action === "start") {
      const initialCursor = normalizeWindowDragPoint(candidate.screenX, candidate.screenY);
      if (!initialCursor) return;
      activeWindowDrag = {
        senderId: event.sender.id,
        windowId: targetWindow.id,
        initialBounds: targetWindow.getBounds(),
        initialCursor,
      };
      return;
    }

    if (!activeWindowDrag || activeWindowDrag.senderId !== event.sender.id || activeWindowDrag.windowId !== targetWindow.id) {
      return;
    }

    if (candidate.action === "end") {
      activeWindowDrag = null;
      return;
    }

    const currentCursor = normalizeWindowDragPoint(candidate.screenX, candidate.screenY);
    if (!currentCursor) return;
    const workArea = screen.getDisplayNearestPoint(currentCursor).workArea;
    const nextPosition = calculateWindowDragPosition(
      activeWindowDrag.initialBounds,
      activeWindowDrag.initialCursor,
      currentCursor,
      workArea,
    );
    const [currentX, currentY] = targetWindow.getPosition();
    if (nextPosition.x !== currentX || nextPosition.y !== currentY) {
      targetWindow.setPosition(nextPosition.x, nextPosition.y, false);
    }
  });

  ipcMain.on("dawnwalker:window-control", (event, action: unknown) => {
    if (action !== "minimize" && action !== "toggle-maximize" && action !== "close") return;
    const targetWindow = BrowserWindow.fromWebContents(event.sender);
    if (!targetWindow || targetWindow.isDestroyed() || event.senderFrame !== event.sender.mainFrame) return;
    if (activeWindowDrag?.senderId === event.sender.id) activeWindowDrag = null;
    if (action === "minimize") targetWindow.minimize();
    if (action === "toggle-maximize") {
      if (targetWindow.isMaximized()) targetWindow.unmaximize();
      else targetWindow.maximize();
    }
    if (action === "close") targetWindow.close();
  });

  ipcMain.handle("dawnwalker:window-maximized", (event) => {
    const targetWindow = BrowserWindow.fromWebContents(event.sender);
    if (!targetWindow || targetWindow.isDestroyed() || event.senderFrame !== event.sender.mainFrame) {
      throw new Error("Invalid window state request.");
    }
    return targetWindow.isMaximized();
  });

  ipcMain.handle("dawnwalker:interface-scale", (event, scale: unknown) => {
    const targetWindow = BrowserWindow.fromWebContents(event.sender);
    if (!targetWindow || targetWindow.isDestroyed() || event.senderFrame !== event.sender.mainFrame) {
      throw new Error("Invalid interface scale request.");
    }
    return scale === undefined ? interfaceScaleStore.get() : applyInterfaceScale(targetWindow, scale);
  });

  ipcMain.handle("dawnwalker:quest-reminder", async (event, action: unknown, payload: unknown) => {
    const targetWindow = BrowserWindow.fromWebContents(event.sender);
    if (!targetWindow || targetWindow.isDestroyed() || event.senderFrame !== event.sender.mainFrame) {
      throw new Error("Invalid quest reminder request.");
    }
    if (action === "get") return questReminderStore.get();
    if (action === "set") {
      const saved = await questReminderStore.set(payload);
      // Register on the way in, so the first reminder after switching on can arrive.
      if (saved) void ensureToastIdentity();
      questReminderMonitor?.settingChanged(saved);
      return saved;
    }
    if (action === "notify") {
      const request = payload as { title?: unknown; body?: unknown } | undefined;
      return sendQuestReminderNotification(request?.title, request?.body);
    }
    throw new Error("Unknown quest reminder request.");
  });

  ipcMain.handle("dawnwalker:runtime-info", async () => {
    const [identity, displayIdentity] = await Promise.all([
      gameBuildInspector.inspectInstalledBuild(),
      storyBuildInspector.inspectInstalledBuild(),
    ]);
    const status = await bridgeTransport.status();
    const authorization = evaluateRuntimeControlAuthorization(status, {
      isPackaged: app.isPackaged,
      pilotControlsEnvironmentValue: process.env[PILOT_CONTROLS_ENVIRONMENT_VARIABLE],
    });
    const readbackDispatch = (command: Readonly<{ capability: string }>) => bridgeTransport.dispatch({
      ...command,
      expectedBootId: status.bootId,
    });
    const [player, controls, questJournal] = identity.verified && status.connected && status.bootId
      ? await Promise.all([
        collectRuntimePlayerReadback(status.capabilities, readbackDispatch),
        collectRuntimeControlReadback(status.capabilities, readbackDispatch),
        collectRuntimeQuestJournalReadback(status.capabilities, readbackDispatch),
      ])
      : [undefined, undefined, undefined];
    return {
      platform: process.platform,
      mode: status.connected ? "live-offline" : "disconnected",
      connected: status.connected,
      gameRunning: await isDawnwalkerRunning().catch(() => status.connected),
      buildVerified: identity.verified && authorization.buildVerified,
      installedBuildId: identity.actualBuildId,
      installedGameVersion: displayIdentity.gameVersion,
      installedGameChangelist: displayIdentity.gameChangelist,
      verifiedBuildId: identity.expectedBuildId,
      interactionEligible: identity.verified && authorization.interactionEligible,
      compatibilityIssue: identity.verified ? undefined : identity.reason,
      bridgeVersion: status.bridgeVersion,
      sessionId: status.bootId,
      capabilities: status.capabilities,
      activeCapabilities: status.active,
      ...(player ? { player } : {}),
      ...(controls ? { controls } : {}),
      ...(questJournal ? { questJournal } : {}),
    };
  });

  ipcMain.handle("dawnwalker:runtime-dispatch", async (_event, command: unknown) => {
    if (!isRuntimeCommandEnvelope(command)) {
      throw new TypeError("Rejected an invalid Dawnwalker runtime command envelope.");
    }
    const identity = await gameBuildInspector.inspectInstalledBuild();
    if (!identity.verified) return { accepted: false, capability: command.capability, requestId: command.requestId, status: "rejected", message: identity.reason };
    const status = await bridgeTransport.status();
    const authorization = evaluateRuntimeControlAuthorization(status, {
      isPackaged: app.isPackaged,
      pilotControlsEnvironmentValue: process.env[PILOT_CONTROLS_ENVIRONMENT_VARIABLE],
    });
    if (!isRuntimeDispatchAuthorized(status, authorization, command)) {
      return {
        accepted: false,
        capability: command.capability,
        requestId: command.requestId,
        status: "rejected",
        message: "The current Dawnwalker session is not authorized for interactive controls.",
      };
    }
    const result = await bridgeTransport.dispatch({
      capability: command.capability,
      value: command.value,
      expectedBootId: command.sessionId,
    });
    return { ...result, requestId: command.requestId };
  });
}

function isRuntimeCommandEnvelope(command: unknown): command is Readonly<{
  capability: string;
  requestId: string;
  sessionId: string;
  value?: boolean | number | string;
}> {
  if (!command || typeof command !== "object") return false;
  const candidate = command as Readonly<Record<string, unknown>>;
  if (typeof candidate.capability !== "string" || !RUNTIME_CAPABILITY_SET.has(candidate.capability)) return false;
  if (typeof candidate.requestId !== "string" || !/^[a-zA-Z0-9-]{3,100}$/.test(candidate.requestId)) return false;
  if (typeof candidate.sessionId !== "string" || !/^[a-zA-Z0-9-]{3,80}$/.test(candidate.sessionId)) return false;
  if (candidate.value === undefined) return true;
  if (typeof candidate.value === "boolean") return true;
  if (typeof candidate.value === "number") return Number.isFinite(candidate.value);
  return typeof candidate.value === "string" && candidate.value.length <= 4096 && !/[\r\n]/.test(candidate.value);
}

function registerGlobalHotkeys(getMainWindow: () => BrowserWindow | null): void {
  const windowToggleRegistered = globalShortcut.register(WINDOW_TOGGLE_HOTKEY, () => {
    const mainWindow = getMainWindow();
    if (!mainWindow || mainWindow.isDestroyed()) return;
    if (mainWindow.isVisible() && !mainWindow.isMinimized()) {
      mainWindow.minimize();
      return;
    }
    showAndFocus(mainWindow);
  });

  const addGoldRegistered = globalShortcut.register(ADD_GOLD_HOTKEY, () => {
    const mainWindow = getMainWindow();
    if (!mainWindow || mainWindow.isDestroyed()) return;
    mainWindow.webContents.send("dawnwalker:gameplay-hotkey", ADD_GOLD_HOTKEY_ACTION);
  });

  if (!windowToggleRegistered && !capturePath) {
    console.warn(`Unable to register the ${WINDOW_TOGGLE_HOTKEY} menu hotkey.`);
  }
  if (!addGoldRegistered && !capturePath) {
    console.warn(`Unable to register the ${ADD_GOLD_HOTKEY} Add Gold hotkey.`);
  }
}

const hasSingleInstanceLock = app.requestSingleInstanceLock();

if (!hasSingleInstanceLock) {
  app.quit();
} else {
  const lifecycle = createWindowLifecycle<BrowserWindow>();
  // One eye owner for the authorized main window. It keeps the native channel, coordinator and
  // material baseline alive across preview leases and stops scheduling whenever the window leaves view.
  const eyeAppearanceOwner = createEyeAppearanceOwner(() => lifecycle.getWindow() ?? undefined);
  const importedMenuOwner = createImportedMenuOwner(() => lifecycle.getWindow() ?? undefined);
  const publishQuestReminder = (event: QuestReminderEvent): void => {
    const window = lifecycle.getWindow();
    if (!window || window.isDestroyed() || window.webContents.isDestroyed()) return;
    window.webContents.send("dawnwalker:quest-reminder-changed", event);
  };
  questReminderMonitor = createQuestReminderMonitor({
    getEnabled: questReminderStore.get,
    state: importedMenuOwner.monitorTransport.state,
    dispatch: importedMenuOwner.monitorTransport.dispatch,
    notify: sendQuestReminderNotification,
    publish: publishQuestReminder,
  });
  let importedMenuClosed = false;
  let importedMenuClosing = false;
  app.on("before-quit", event => {
    lifecycle.beginQuit();
    if (importedMenuClosed) return;
    event.preventDefault();
    if (importedMenuClosing) return;
    importedMenuClosing = true;
    questReminderMonitor?.dispose();
    void importedMenuOwner.dispose().finally(() => { importedMenuClosed = true; app.quit(); });
  });

  app.on("second-instance", () => {
    lifecycle.focusExisting();
  });

  // Chromium restarts a crashed GPU process on its own, but the window it was painting can
  // stay black (seen 2026-09-17 when a game hang took the GPU with it). Repainting the
  // page after the GPU process comes back costs nothing and brings the menu back.
  app.on("child-process-gone", (_event, details) => {
    console.error("Menu child process gone:", details.type, details.reason, details.exitCode);
    if (details.type !== "GPU" || details.reason === "clean-exit") return;
    setTimeout(() => {
      for (const window of BrowserWindow.getAllWindows()) {
        if (!window.isDestroyed() && !window.webContents.isDestroyed()) window.webContents.invalidate();
      }
    }, 1000);
  });

  app.whenReady().then(async () => {
    if (process.platform === "win32") app.setAppUserModelId(APP_USER_MODEL_ID);
    await Promise.all([interfaceScaleStore.load(), questReminderStore.load()]);
    // Already-on reminders should work from the first objective of the session.
    if (questReminderStore.get()) void ensureToastIdentity();
    Menu.setApplicationMenu(null);
    enforceLocalOnlyPolicy();
    registerGameAssetProtocol();
    registerWindowHandlers();
    eyeAppearanceOwner.register();
    importedMenuOwner.register();
    questReminderMonitor?.settingChanged(questReminderStore.get());
    if (lifecycle.isQuitting()) return;
    const mainWindow = createMainWindow();
    lifecycle.track(mainWindow);
    eyeAppearanceOwner.attach(mainWindow);
    if (!capturePath) registerGlobalHotkeys(lifecycle.getWindow);

    app.on("activate", () => {
      if (!lifecycle.isQuitting() && BrowserWindow.getAllWindows().length === 0) {
        const mainWindow = createMainWindow();
        lifecycle.track(mainWindow);
        eyeAppearanceOwner.attach(mainWindow);
      }
    });
  });

  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });

  app.on("will-quit", () => {
    globalShortcut.unregisterAll();
    questReminderMonitor?.dispose();
    void eyeAppearanceOwner.dispose();
  });
}
