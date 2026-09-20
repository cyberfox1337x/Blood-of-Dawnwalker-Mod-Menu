import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { readdir, readFile, stat } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { BrowserWindow, ipcMain, type IpcMainInvokeEvent } from "electron";
import { createEyeNativeChannel } from "./eyeNativeChannel.js";
import { createEyeSessionCoordinator } from "./eyeSessionCoordinator.js";
import { createEyeSessionPngStore } from "./eyeFrameTransport.js";
import { createEyeAppearanceService, type EyeServiceAcceptance, type EyeServiceRuntime } from "./eyeAppearanceService.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_eye_appearance_owner");

const BUILD_ID = "25129649";
const EXECUTABLE = "C:/Program Files (x86)/Steam/steamapps/common/The Blood of Dawnwalker/Dawnwalker/Binaries/Win64/Dawnwalker.exe";
const INSTALLED_SCRIPTS = "C:/Program Files (x86)/Steam/steamapps/common/The Blood of Dawnwalker/Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerRequestedReadOnly/Scripts";
const EYE_ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance";
const CHANNEL_ROOT = join(EYE_ROOT, "native-channel");
const ACCEPTANCE_PATH = join(EYE_ROOT, "eye-acceptance-record.json");
const CANDIDATE_MANIFEST = join(EYE_ROOT, "native-pilot-candidate-v10", "manifest.json");
const SCRIPT_PREFIX = "Mods/DawnwalkerRequestedReadOnly/Scripts/";
const BOOT_PATTERN = /^\d{1,16}-\d{1,16}$/u;
const OWNER_PATTERN = /^[a-f0-9]{32}$/u;
const CHANNEL = "dawnwalker:eye";
const SESSION_EVENT = "dawnwalker:eye-session";
const FRAME_EVENT = "dawnwalker:eye-frame";
const MAXIMUM_LEASES = 3;

const execute = promisify(execFile);

type NativeAddress = Readonly<{ bootId: string; ownerId: string; readyAtMs: number }>;
type GameProcess = Readonly<{ processId: number; processStartedAt: string }>;
type Service = ReturnType<typeof createEyeAppearanceService>;

function sha256(bytes: Uint8Array | string): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Product-facing text only. Native paths, raw reports and stack traces never reach the renderer. */
function safeReason(error: unknown): string {
  const message = error instanceof Error && error.message ? error.message : "The native eye session is unavailable.";
  return message.replace(/[A-Za-z]:[\\/][^\s"']*/gu, "a local path").slice(0, 240);
}

/**
 * Finds the most recently published native channel. A `channel.ready` marker only proves that a
 * host published its transport; it is never treated as capability approval, and the service still
 * refuses to open without a reviewed acceptance record.
 */
async function discoverNativeAddress(): Promise<NativeAddress> {
  let newest: NativeAddress | undefined;
  const bootDirectories = await readdir(CHANNEL_ROOT, { withFileTypes: true }).catch(() => []);
  for (const bootEntry of bootDirectories) {
    if (!bootEntry.isDirectory() || !BOOT_PATTERN.test(bootEntry.name)) continue;
    const ownerDirectories = await readdir(join(CHANNEL_ROOT, bootEntry.name), { withFileTypes: true }).catch(() => []);
    for (const ownerEntry of ownerDirectories) {
      if (!ownerEntry.isDirectory() || !OWNER_PATTERN.test(ownerEntry.name)) continue;
      const marker = join(CHANNEL_ROOT, bootEntry.name, ownerEntry.name, "channel.ready");
      const details = await stat(marker).catch(() => undefined);
      if (!details?.isFile()) continue;
      const readyAtMs = details.mtimeMs;
      if (!newest || readyAtMs > newest.readyAtMs) newest = { bootId: bootEntry.name, ownerId: ownerEntry.name, readyAtMs };
    }
  }
  if (!newest) throw new Error("No native eye host has published a channel. Start one in the running game first.");
  return newest;
}

async function readGameProcess(): Promise<GameProcess> {
  if (process.platform !== "win32") throw new Error("The native eye session requires the Windows game process.");
  const powershell = join(process.env.SystemRoot ?? "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const { stdout } = await execute(powershell, ["-NoProfile", "-NonInteractive", "-Command",
    "$p = Get-Process Dawnwalker -ErrorAction SilentlyContinue | Select-Object -First 1;" +
    " if ($p) { @{ id = $p.Id; started = $p.StartTime.ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress }"],
    { windowsHide: true, timeout: 10000, maxBuffer: 1024 * 1024 });
  const trimmed = stdout.trim();
  if (!trimmed) throw new Error("The game is not running, so no native eye session can be observed.");
  const parsed = JSON.parse(trimmed) as { id?: unknown; started?: unknown };
  if (!Number.isSafeInteger(parsed.id) || (parsed.id as number) <= 0 || typeof parsed.started !== "string" || !parsed.started) {
    throw new Error("The running game process could not be identified.");
  }
  return { processId: parsed.id as number, processStartedAt: parsed.started };
}

/**
 * Confirms that the payload actually installed in the game directory is byte-for-byte the reviewed
 * candidate. The channel's own checksum is deliberately not used as payload identity.
 */
async function verifyInstalledPayload(): Promise<string> {
  const manifestBytes = await readFile(CANDIDATE_MANIFEST);
  const manifest = JSON.parse(manifestBytes.toString("utf8")) as { payload?: readonly { path: string; sha256: string }[] };
  const payload = manifest.payload ?? [];
  if (payload.length === 0) throw new Error("The reviewed native candidate manifest records no payload.");
  let verified = 0;
  for (const record of payload) {
    if (!record.path.startsWith(SCRIPT_PREFIX)) continue;
    const installed = await readFile(join(INSTALLED_SCRIPTS, record.path.slice(SCRIPT_PREFIX.length))).catch(() => undefined);
    if (!installed || sha256(installed).toUpperCase() !== record.sha256.toUpperCase()) {
      throw new Error("The installed native payload differs from the reviewed candidate.");
    }
    verified++;
  }
  if (verified === 0) throw new Error("The reviewed native candidate manifest records no installed scripts.");
  return sha256(manifestBytes).toUpperCase();
}

let cachedExecutableHash: string | undefined;
async function executableSha256(): Promise<string> {
  if (!cachedExecutableHash) cachedExecutableHash = sha256(await readFile(EXECUTABLE)).toUpperCase();
  return cachedExecutableHash;
}

/**
 * The acceptance record is supplied by a reviewed file on disk, never invented by application code.
 * Its absence keeps the feature honestly unavailable rather than mounting an unproven viewer.
 */
async function readAcceptance(): Promise<EyeServiceAcceptance | undefined> {
  const bytes = await readFile(ACCEPTANCE_PATH).catch(() => undefined);
  if (!bytes) return undefined;
  return JSON.parse(bytes.toString("utf8")) as EyeServiceAcceptance;
}

export function createEyeAppearanceOwner(getWindow: () => BrowserWindow | undefined) {
  let service: Service | undefined, address: NativeAddress | undefined, disposing = false;
  let channelHandle: Awaited<ReturnType<typeof createEyeNativeChannel>> | undefined;

  function send(event: string, payload: unknown): void {
    const targetWindow = getWindow();
    if (!targetWindow || targetWindow.isDestroyed() || targetWindow.webContents.isDestroyed()) return;
    targetWindow.webContents.send(event, payload);
  }

  function authenticate(event: IpcMainInvokeEvent): void {
    const targetWindow = getWindow();
    if (!targetWindow || BrowserWindow.fromWebContents(event.sender) !== targetWindow
      || event.senderFrame !== event.sender.mainFrame) throw new Error("Invalid eye appearance request.");
  }

  async function inspectRuntime(): Promise<EyeServiceRuntime> {
    if (!address) throw new Error("No native eye channel has been discovered.");
    const [executable, payloadManifestSha256, gameProcess] = await Promise.all([
      executableSha256(), verifyInstalledPayload(), readGameProcess(),
    ]);
    return { buildId: BUILD_ID, executableSha256: executable, payloadManifestSha256,
      bootId: address.bootId, ownerId: address.ownerId, ...gameProcess };
  }

  async function build(): Promise<Service> {
    const acceptance = await readAcceptance();
    if (!acceptance) throw new Error("No reviewed native acceptance record is installed, so the eye viewer stays unavailable.");
    address = await discoverNativeAddress();
    const native = await createEyeNativeChannel({ bootId: address.bootId, ownerId: address.ownerId });
    channelHandle = native;
    const stores = new Map<string, ReturnType<typeof createEyeSessionPngStore>>();
    function store(frameAddress: { bootId: string; previewNonce: string }) {
      if (frameAddress.bootId !== address!.bootId) throw new Error("Native frame boot mismatch.");
      let existing = stores.get(frameAddress.previewNonce);
      if (!existing) {
        if (stores.size >= MAXIMUM_LEASES) throw new Error("Native frame lease budget exhausted.");
        existing = createEyeSessionPngStore({ bootId: address!.bootId, previewNonce: frameAddress.previewNonce });
        stores.set(frameAddress.previewNonce, existing);
      }
      return existing;
    }
    const coordinator = createEyeSessionCoordinator({
      channel: { waitForTransport: timeout => native.waitForTransport(timeout), send: (command, timeout) => native.send(command, timeout) },
      timeoutMs: 10000,
      frames: { read: frameAddress => store(frameAddress).read(frameAddress), discardKnown: frameAddress => store(frameAddress).discardKnown(frameAddress) },
    });
    return createEyeAppearanceService({
      coordinator, acceptance, inspectRuntime, now: () => Date.now(),
      schedule(callback, delayMs) { const timer = setTimeout(callback, delayMs); return () => clearTimeout(timer); },
      onSession: session => send(SESSION_EVENT, session),
      onFrame: frame => send(FRAME_EVENT, frame),
      onFault: error => send(SESSION_EVENT, { availability: "unavailable", reason: safeReason(error), diagnostics: [] }),
    });
  }

  async function open(): Promise<unknown> {
    if (disposing) throw new Error("The eye viewer is shutting down.");
    if (!service) service = await build();
    return service.open();
  }

  /**
   * Every path that removes the viewer from view stops native scheduling. F10 minimises the window
   * rather than hiding it, so minimize is handled alongside hide, close, crash and navigation.
   * Suspending never restores committed live eye changes.
   */
  async function suspend(): Promise<void> {
    if (!service) return;
    try { await service.close(); } catch (error) { send(SESSION_EVENT, { availability: "unavailable", reason: safeReason(error), diagnostics: [] }); }
  }

  async function dispose(): Promise<void> {
    disposing = true;
    try { await service?.dispose(); } catch { /* Disposal failures must not block application shutdown; the record is retained natively. */ }
    service = undefined;
    channelHandle?.dispose();
    channelHandle = undefined;
  }

  function register(): void {
    ipcMain.handle(CHANNEL, async (event, action: unknown, first: unknown, second: unknown) => {
      authenticate(event);
      switch (action) {
        case "open": return open();
        case "state": return service ? service.getState().session : { availability: "unavailable", reason: "The eye viewer has not been opened.", diagnostics: [] };
        case "update": return requireService().updatePreview(first);
        case "apply": return requireService().apply(first, second);
        case "restore": return requireService().restore(first, second);
        case "inspect": return requireService().inspect(first, String(second ?? ""));
        case "cancel": return requireService().cancelQueued(first);
        case "close": return suspend();
        default: throw new Error("Unsupported eye appearance request.");
      }
    });
  }

  function requireService(): Service {
    if (!service) throw new Error("The eye viewer has no open native session.");
    return service;
  }

  function attach(targetWindow: BrowserWindow): void {
    targetWindow.on("minimize", () => { void suspend(); });
    targetWindow.on("hide", () => { void suspend(); });
    targetWindow.on("close", () => { void suspend(); });
    targetWindow.webContents.on("render-process-gone", () => { void dispose(); });
    targetWindow.webContents.on("did-start-navigation", () => { void suspend(); });
    targetWindow.on("closed", () => { void dispose(); });
  }

  return Object.freeze({ register, attach, dispose, suspend });
}
