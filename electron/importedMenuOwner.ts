import { app, BrowserWindow, ipcMain, type IpcMainInvokeEvent } from "electron";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { createImportedPayloadVerifier } from "./importedPayloadVerifier.js";
import { createImportedMenuTransport } from "./importedMenuTransport.js";
import { createGameBuildInspector } from "./gameBuildIdentity.js";
import { isDawnwalkerRunning } from "./gameProcess.js";
import type { ImportedMenuDispatchRequest } from "./importedMenuContract.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_owner");

export function createImportedMenuOwner(getWindow: () => BrowserWindow | undefined) {
  const resources = app.isPackaged ? join(process.resourcesPath, "imported-menu") : resolve(app.getAppPath(), "integration/imported-menu");
  const steamRoot = join(process.env["ProgramFiles(x86)"] ?? "C:\\Program Files (x86)", "Steam", "steamapps");
  const modRoot = join(steamRoot, "common", "The Blood of Dawnwalker", "Dawnwalker", "Binaries", "Win64", "ue4ss", "Mods", "DawnwalkerImportedMenu");
  const inspector = createGameBuildInspector({ contractPath: join(resources, "official-build.json"), manifestPath: join(steamRoot, "appmanifest_3751260.acf") });
  const verifyPayload = createImportedPayloadVerifier(modRoot, join(resources, "manifest.json"));
  let verifiedAt = 0;
  let verified = false;
  let verificationMessage = "The game runtime has not been verified yet.";
  let verification: Promise<boolean> | undefined;
  async function verifyRuntime(): Promise<boolean> {
    if (Date.now() - verifiedAt < 2000) return verified;
    if (verification) return verification;
    verification = (async () => {
      try {
        const build = await inspector.inspectInstalledBuild();
        if (!build.verified) { verificationMessage = build.reason; return false; }
        if (!await isDawnwalkerRunning()) { verificationMessage = "Start the game and load a save to connect."; return false; }
        const payload = await verifyPayload();
        verificationMessage = payload.reason;
        return payload.verified;
      } catch { verificationMessage = "Runtime verification failed. Restart the current menu and game, then check their installation."; return false; }
    })();
    try { verified = await verification; verifiedAt = Date.now(); return verified; }
    finally { verification = undefined; }
  }
  // The payload manifest already records the build the installed files were accepted
  // against, and the same file gates their hashes. Reading the build id from it keeps a
  // game patch a one-file change instead of a hardcoded constant that silently
  // disconnects the whole menu.
  let acceptedBuildId: string | undefined;
  async function expectedBuildId(): Promise<string | undefined> {
    if (acceptedBuildId) return acceptedBuildId;
    try {
      const manifest = JSON.parse(await readFile(join(resources, "manifest.json"), "utf8")) as { buildId?: unknown };
      if (typeof manifest.buildId === "string" && manifest.buildId) acceptedBuildId = manifest.buildId;
    } catch (error) {
      // Left undefined on purpose: the transport reports an unreadable manifest rather
      // than accepting a snapshot it cannot check.
      console.error("Could not read the imported payload manifest:", error);
    }
    return acceptedBuildId;
  }
  // The shared probe already caches polling results. A second cache here could hide
  // an exit and relaunch for almost twice its TTL. Failed probes remain unknown.
  async function gameRunning(): Promise<boolean | undefined> {
    try { return await isDawnwalkerRunning(); } catch { return undefined; }
  }
  // The eye-colour native path is accepted on exactly one executable. The Lua compares
  // its identity constant to itself, so the pin is enforced here against the executable
  // identity the inspector actually reads. Originally reviewed on 25129649; re-verified
  // on 25232147 (CL258504) on 2026-09-11 - read-only observation matched the reviewed
  // material chain, then an apply/readback/restore cycle passed in game. Evidence:
  // qa/eye-appearance/reverify-25232147-20260911.md. Move this only with new evidence.
  // The new combat section is read-only discovery, not a verified gameplay setter.
  const SECTION_BUILD_PINS: Readonly<Record<string, string>> = { DWEyeColor: "25232147", DWCombatDiscovery: "25232147" };
  let installedBuild: { at: number; id: string | undefined } | undefined;
  async function installedBuildId(): Promise<string | undefined> {
    if (installedBuild && Date.now() - installedBuild.at < 10000) return installedBuild.id;
    let id: string | undefined;
    try { id = (await inspector.inspectInstalledBuild()).actualBuildId; } catch { id = undefined; }
    installedBuild = { at: Date.now(), id };
    return id;
  }
  const transport = createImportedMenuTransport({ channelRoot: join(app.getPath("temp"), "DawnwalkerImportedMenu"), catalogPath: join(resources, "catalog.json"), expectedBuildId, verifyRuntime, verificationFailure: () => verificationMessage, gameRunning, sectionBuildPins: SECTION_BUILD_PINS, installedBuildId,
    // The read-only observation is how the eye pin gets re-verified, so it must run
    // on the build the pin is refusing.
    buildPinReadOnlyItems: { DWEyeColor: ["observe"] } });
  function authenticate(event: IpcMainInvokeEvent) {
    const window = getWindow();
    if (!window || window.isDestroyed() || BrowserWindow.fromWebContents(event.sender) !== window || event.senderFrame !== event.sender.mainFrame) throw new Error("Invalid menu request.");
  }
  return {
    // Main-process services use the same verified transport as the renderer. Keeping
    // this facade private to Electron avoids exposing any new native channel surface.
    monitorTransport: Object.freeze({
      state: () => transport.state(),
      dispatch: (request: ImportedMenuDispatchRequest) => transport.dispatch(request),
    }),
    async dispose() {
      const deadline = Date.now() + 35000;
      while (Date.now() < deadline) {
        const snapshot = await transport.state();
        if (!snapshot.ready) return;
        if (snapshot.operation && ["queued", "running"].includes(snapshot.operation.status)) {
          await new Promise(resolve => setTimeout(resolve, 250)); continue;
        }
        const result = await transport.dispatch({ action: "close", sessionId: snapshot.sessionId });
        if (!result.accepted) { console.warn(result.message); return; }
        while (Date.now() < deadline) {
          const state = await transport.state();
          if (!state.ready || state.sessionId !== snapshot.sessionId) return;
          if (state.operation?.status === "completed") return;
          if (state.operation?.status === "failed") { console.warn(state.operation.message); return; }
          await new Promise(resolve => setTimeout(resolve, 150));
        }
      }
      console.warn("Imported menu cleanup acknowledgement timed out; inspect game status before reusing controls.");
    },
    register() {
      ipcMain.handle("dawnwalker:imported-menu", async (event, action: unknown, request: unknown) => {
        authenticate(event);
        if (action === "state") return transport.state();
        if (action === "dispatch") return transport.dispatch(request as ImportedMenuDispatchRequest);
        throw new Error("Unknown menu request.");
      });
    },
  };
}
