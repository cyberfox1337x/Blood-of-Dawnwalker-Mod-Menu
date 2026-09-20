import { contextBridge, ipcRenderer, type IpcRendererEvent } from "electron";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("electron_preload");

type RuntimeCommandPayload = Readonly<{
  capability: string;
  value?: boolean | number | string;
  requestId: string;
  sessionId: string;
}>;

type GameplayHotkeyAction = "add-gold";
type QuestReminderEvent = Readonly<{ title: string; objective: string; desktopAccepted: boolean }>;

function isQuestReminderEvent(value: unknown): value is QuestReminderEvent {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<QuestReminderEvent>;
  return typeof candidate.title === "string" && candidate.title.length > 0 && candidate.title.length <= 120
    && typeof candidate.objective === "string" && candidate.objective.length > 0 && candidate.objective.length <= 240
    && typeof candidate.desktopAccepted === "boolean";
}

const desktopControls = Object.freeze({
  importedMenu: Object.freeze({
    state: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:imported-menu", "state"),
    dispatch: (request: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:imported-menu", "dispatch", request),
  }),
  beginWindowDrag: (screenX: number, screenY: number): void => ipcRenderer.send("dawnwalker:window-drag", { action: "start", screenX, screenY }),
  updateWindowDrag: (screenX: number, screenY: number): void => ipcRenderer.send("dawnwalker:window-drag", { action: "move", screenX, screenY }),
  endWindowDrag: (): void => ipcRenderer.send("dawnwalker:window-drag", { action: "end" }),
  minimizeWindow: (): void => ipcRenderer.send("dawnwalker:window-control", "minimize"),
  toggleMaximizeWindow: (): void => ipcRenderer.send("dawnwalker:window-control", "toggle-maximize"),
  isWindowMaximized: (): Promise<boolean> => ipcRenderer.invoke("dawnwalker:window-maximized"),
  onWindowMaximizedChanged: (listener: (maximized: boolean) => void): (() => void) => {
    const handleMaximizedChanged = (_event: IpcRendererEvent, maximized: unknown): void => {
      if (typeof maximized === "boolean") listener(maximized);
    };
    ipcRenderer.on("dawnwalker:window-maximized", handleMaximizedChanged);
    return () => ipcRenderer.removeListener("dawnwalker:window-maximized", handleMaximizedChanged);
  },
  closeWindow: (): void => ipcRenderer.send("dawnwalker:window-control", "close"),
  interfaceScale: Object.freeze({
    get: (): Promise<number> => ipcRenderer.invoke("dawnwalker:interface-scale"),
    set: (scale: number): Promise<number> => ipcRenderer.invoke("dawnwalker:interface-scale", scale),
    onChanged: (listener: (scale: number) => void): (() => void) => {
      const handler = (_event: IpcRendererEvent, scale: unknown): void => {
        if (typeof scale === "number") listener(scale);
      };
      ipcRenderer.on("dawnwalker:interface-scale-changed", handler);
      return () => ipcRenderer.removeListener("dawnwalker:interface-scale-changed", handler);
    },
    onError: (listener: (message: string) => void): (() => void) => {
      const handler = (_event: IpcRendererEvent, message: unknown): void => {
        if (typeof message === "string") listener(message);
      };
      ipcRenderer.on("dawnwalker:interface-scale-error", handler);
      return () => ipcRenderer.removeListener("dawnwalker:interface-scale-error", handler);
    },
  }),
  questReminder: Object.freeze({
    // Narrow wrappers only: the renderer can read and set the setting and ask for a
    // notification, but never reaches ipcRenderer, the channel name or the icon path.
    get: (): Promise<boolean> => ipcRenderer.invoke("dawnwalker:quest-reminder", "get"),
    set: (enabled: boolean): Promise<boolean> => ipcRenderer.invoke("dawnwalker:quest-reminder", "set", enabled),
    notify: (title: string, body: string): Promise<boolean> => ipcRenderer.invoke("dawnwalker:quest-reminder", "notify", { title, body }),
    onReminder: (listener: (event: QuestReminderEvent) => void): (() => void) => {
      const handler = (_event: IpcRendererEvent, reminder: unknown): void => {
        if (isQuestReminderEvent(reminder)) listener(reminder);
      };
      ipcRenderer.on("dawnwalker:quest-reminder-changed", handler);
      return () => ipcRenderer.removeListener("dawnwalker:quest-reminder-changed", handler);
    },
  }),
  onGameplayHotkey: (listener: (action: GameplayHotkeyAction) => void): (() => void) => {
    const handleGameplayHotkey = (_event: IpcRendererEvent, action: unknown): void => {
      if (action === "add-gold") listener(action);
    };
    ipcRenderer.on("dawnwalker:gameplay-hotkey", handleGameplayHotkey);
    return () => ipcRenderer.removeListener("dawnwalker:gameplay-hotkey", handleGameplayHotkey);
  },
  getRuntimeInfo: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:runtime-info"),
  dispatch: (command: RuntimeCommandPayload): Promise<unknown> => ipcRenderer.invoke("dawnwalker:runtime-dispatch", command),
  openFeatureReference: (id: number): Promise<void> => ipcRenderer.invoke("dawnwalker:feature-reference", id),
  storyDaySettings: Object.freeze({
    inspect: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:story-days", "inspect"),
    apply: (change: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:story-days", "apply", change),
    restore: (sha256: string): Promise<unknown> => ipcRenderer.invoke("dawnwalker:story-days", "restore", sha256),
  }),
  fogSettings: Object.freeze({
    inspect: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:fog", "inspect"),
    apply: (change: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:fog", "apply", change),
    restore: (sha256: string): Promise<unknown> => ipcRenderer.invoke("dawnwalker:fog", "restore", sha256),
  }),
  eyeAppearance: Object.freeze({
    // Narrow allowlisted wrappers only. No ipcRenderer, channel name, native path or report is exposed.
    open: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "open"),
    state: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "state"),
    updatePreview: (request: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "update", request),
    apply: (request: unknown, address: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "apply", request, address),
    restore: (request: unknown, address: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "restore", request, address),
    inspect: (identity: unknown, baselineId: string): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "inspect", identity, baselineId),
    cancelQueued: (address: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "cancel", address),
    close: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:eye", "close"),
    onSession: (listener: (session: unknown) => void): (() => void) => {
      const handleSession = (_event: IpcRendererEvent, session: unknown): void => listener(session);
      ipcRenderer.on("dawnwalker:eye-session", handleSession);
      return () => ipcRenderer.removeListener("dawnwalker:eye-session", handleSession);
    },
    onFrame: (listener: (frame: unknown) => void): (() => void) => {
      const handleFrame = (_event: IpcRendererEvent, frame: unknown): void => listener(frame);
      ipcRenderer.on("dawnwalker:eye-frame", handleFrame);
      return () => ipcRenderer.removeListener("dawnwalker:eye-frame", handleFrame);
    },
  }),
  gameAssets: Object.freeze({
    status: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:game-assets", "status"),
    perks: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:game-assets", "perks"),
  }),
  saveEditor: Object.freeze({
    listSaves: (): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "list"),
    inspectSave: (fileName: string): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "inspect", fileName),
    listBackups: (fileName: string): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "backups", fileName),
    readFields: (fileName: string): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "fields", fileName),
    readSummary: (fileName: string): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "summary", fileName),
    editFields: (request: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "edit", request),
    createBackup: (request: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "backup", request),
    previewRestore: (request: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "preview", request),
    restoreBackup: (request: unknown): Promise<unknown> => ipcRenderer.invoke("dawnwalker:saves", "restore", request),
  }),
});

contextBridge.exposeInMainWorld("dawnwalkerDesktop", desktopControls);
