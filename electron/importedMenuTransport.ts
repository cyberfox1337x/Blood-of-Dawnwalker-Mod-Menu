import { randomUUID } from "node:crypto";
import { readFile, stat, writeFile, rename, unlink, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import type { ImportedMenuDispatchRequest, ImportedMenuSnapshot, ImportedMenuItem } from "./importedMenuContract.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_transport");
const MAX_STATE_BYTES = 1024 * 1024;
const MAX_SECTIONS = 96;
// A cold boot to the main menu takes ~90 s on the reference machine (cinematics included).
const STARTUP_HANG_AFTER_SECONDS = 150;

// The runtime rewrites state.json once a second with only the heartbeat digits changed
// (measured 2026-09-18: 200 KB/s idle). Parsing 200 KB twice a second was most of the
// menu's idle CPU, so the last payload is kept and re-parsed only when anything other
// than the heartbeat differs; a heartbeat-only rewrite just refreshes that one field.
const HEARTBEAT_FIELD = /"heartbeat":-?\d+/;
let cachedStripped: string | undefined;
let cachedParsed: Record<string, unknown> | undefined;
function parseState(raw: string): unknown {
  const match = HEARTBEAT_FIELD.exec(raw);
  const stripped = match ? raw.slice(0, match.index) + raw.slice(match.index + match[0].length) : raw;
  if (cachedParsed && stripped === cachedStripped) {
    const heartbeat = match ? Number(match[0].slice('"heartbeat":'.length)) : undefined;
    return { ...cachedParsed, heartbeat };
  }
  const parsed = JSON.parse(raw) as unknown;
  if (parsed && typeof parsed === "object") { cachedStripped = stripped; cachedParsed = parsed as Record<string, unknown>; }
  return parsed;
}

async function boundedJson(path: string): Promise<unknown> {
  for (let attempt = 0; ; attempt++) {
    try {
      const info = await stat(path);
      if (!info.isFile() || info.size > MAX_STATE_BYTES) throw new Error("Invalid menu state file.");
      return parseState(await readFile(path, "utf8"));
    } catch (error) {
      // Native Lua replaces the mailbox using remove + rename on Windows.
      // Retry only the brief filesystem gap; never reuse an old snapshot.
      const code = (error as NodeJS.ErrnoException).code;
      if (attempt >= 3 || !["ENOENT", "EACCES", "EPERM", "EBUSY"].includes(code ?? "")) throw error;
      await delay(20);
    }
  }
}
function validPendingFiniteTasks(value: unknown): value is number | undefined {
  return value === undefined || (typeof value === "number" && Number.isSafeInteger(value) && value >= 0);
}
function validSnapshot(value: unknown): value is ImportedMenuSnapshot {
  if (!value || typeof value !== "object") return false;
  const state = value as ImportedMenuSnapshot;
  return state.schema === 1 && typeof state.sessionId === "string" && state.sessionId.length < 256
    && Number.isSafeInteger(state.revision) && typeof state.ready === "boolean" && validPendingFiniteTasks(state.pendingFiniteTasks)
    && Array.isArray(state.sections) && state.sections.length <= MAX_SECTIONS
    && state.sections.every(section => typeof section.id === "string" && typeof section.title === "string" && Array.isArray(section.items));
}
function findItem(items: ImportedMenuItem[], id: string): ImportedMenuItem | undefined {
  for (const item of items) {
    if (item.id === id) return item;
    if (item.items) { const found = findItem(item.items, id); if (found) return found; }
  }
  return undefined;
}
export function validateImportedRequest(request: ImportedMenuDispatchRequest, state: ImportedMenuSnapshot): void {
  if (!request || typeof request !== "object" || request.sessionId !== state.sessionId) throw new Error("The game session changed. Refresh the controls.");
  if (!["invoke", "set", "confirm", "refresh", "close"].includes(request.action)) throw new Error("Unknown menu action.");
  if (!validPendingFiniteTasks(state.pendingFiniteTasks)) throw new Error("Invalid runtime callback count. Refresh the controls.");
  if ((state.pendingFiniteTasks ?? 0) > 0) throw new Error("The game is finishing earlier work. Wait before sending another command.");
  if (request.action === "close") {
    if (state.operation && ["queued", "running"].includes(state.operation.status)) throw new Error("Wait for the current action to finish.");
    return;
  }
  if (request.action === "confirm") {
    if (!state.confirmation || request.confirmationToken !== state.confirmation.token || typeof request.confirmed !== "boolean") throw new Error("This confirmation has expired.");
    return;
  }
  if (state.operation && ["queued", "running", "awaiting-confirmation"].includes(state.operation.status)) throw new Error("Wait for the current action or cancel its confirmation.");
  if (request.action === "refresh") return;
  const section = state.sections.find(section => section.id === request.sectionId);
  const item = section && typeof request.itemId === "string" ? findItem(section.items, request.itemId) : undefined;
  if (!item || item.disabled || item.enabled === false) throw new Error("This control is unavailable.");
  if (item.readOnly === true) throw new Error("This status control is read-only.");
  if (request.action === "invoke") {
    if (item.type !== "button") throw new Error("This control is not an action button.");
    return;
  }
  const value = request.value;
  if (item.type === "checkbox") {
    if (typeof value !== "boolean") throw new Error("A toggle requires On or Off.");
  } else if (["number", "slider"].includes(item.type)) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < (item.min ?? -1e9) || value > (item.max ?? 1e9)) throw new Error("Value is outside this control's range.");
  } else if (["dropdown", "select"].includes(item.type)) {
    if (value === false || !item.options?.some(option => (typeof option === "string" ? option : option.value) === value)) throw new Error("Choose an available option.");
  } else if (["input", "text"].includes(item.type)) {
    if (typeof value !== "string" || value.length > 512 || /[\0\r\n]/.test(value)) throw new Error("Invalid input text.");
  } else throw new Error("This control cannot be changed.");
}
export function createImportedMenuTransport(options: {
  channelRoot: string;
  catalogPath: string;
  // The Steam build the installed payload was accepted against. Supplied by the caller
  // from the payload manifest so a game patch is handled in one place: hardcoding it
  // here made every snapshot incompatible the moment the game updated.
  expectedBuildId: () => Promise<string | undefined>;
  verifyRuntime: () => Promise<boolean>;
  verificationFailure?: () => string;
  now?: () => number;
  // Whether the game process is alive, when the caller can tell. A stale heartbeat
  // on its own says nothing about the process - the file is left behind by a normal
  // exit exactly as it is by a hang - so the two are only told apart by asking. Only
  // consulted when the heartbeat is stale; undefined means "could not determine".
  gameRunning?: () => Promise<boolean | undefined>;
  // Called once per unclean game exit (process gone, last snapshot without a `shutdown`
  // marker). Returns the sentence to show for what was done about it. Nothing is wired by
  // default: an automatic Steam restart was tried on 2026-09-18 and rejected (it can leave
  // Steam at its login prompt and did not reliably prevent the freeze).
  onUncleanExit?: (info: { lastHeartbeat: number; sessionId: string }) => Promise<string | undefined>;
  // Sections whose native path was reviewed on exactly one game build. Until they are
  // re-verified on the installed build they are shown disabled with the reason, and a
  // request to them is refused here - the Lua side compares a constant to itself, so
  // this layer, which reads the real executable identity, is where the gate has to be.
  sectionBuildPins?: Readonly<Record<string, string>>;
  installedBuildId?: () => Promise<string | undefined>;
  // Items in a pinned section that stay usable on any build because they only read:
  // the observation that re-verifies the section has to run on the very build the
  // pin is refusing, or the pin could never be lifted with evidence.
  buildPinReadOnlyItems?: Readonly<Record<string, readonly string[]>>;
}) {
  const now = options.now ?? Date.now;
  let writing = false;
  let pending: { id: string; session: string; at: number; readOnly: boolean } | undefined;
  async function unavailable(message: string): Promise<ImportedMenuSnapshot> {
    let sections: ImportedMenuSnapshot["sections"] = [];
    try {
      const catalog = await boundedJson(options.catalogPath) as { sections?: ImportedMenuSnapshot["sections"] };
      if (Array.isArray(catalog.sections)) sections = catalog.sections;
    } catch { /* The fallback remains explicitly unavailable until a reviewed catalog exists. */ }
    return { schema: 1, sessionId: "", revision: 0, ready: false, sections, message };
  }
  // Why a pinned section is unavailable on this build, or undefined when it is fine.
  async function buildPinReason(sectionId: string): Promise<string | undefined> {
    const pinned = options.sectionBuildPins?.[sectionId];
    if (!pinned || !options.installedBuildId) return undefined;
    const installed = await options.installedBuildId();
    if (installed === pinned) return undefined;
    return `Reviewed only on game build ${pinned}; the installed build is ${installed ?? "unknown"}. Disabled until it is re-verified on this build.`;
  }
  async function applyBuildPins(snapshot: ImportedMenuSnapshot): Promise<ImportedMenuSnapshot> {
    if (!options.sectionBuildPins) return snapshot;
    const sections = await Promise.all(snapshot.sections.map(async section => {
      const reason = await buildPinReason(section.id);
      if (!reason) return section;
      const readOnly = new Set(options.buildPinReadOnlyItems?.[section.id] ?? []);
      return { ...section, items: section.items.map(item =>
        item.type === "label" ? (item.id === "status" ? { ...item, label: reason } : item)
          : (item.id !== undefined && readOnly.has(item.id)) ? item
          : { ...item, disabled: true, enabled: false }) };
    }));
    return { ...snapshot, sections };
  }
  // First moment the game was seen running with a stale heartbeat; cleared by a fresh one.
  let quietSince: number | undefined;
  let gameplayObserved = false;
  async function stoppedRuntime(running: boolean | undefined, lastSeen?: string): Promise<ImportedMenuSnapshot> {
    if (running === false) {
      quietSince = undefined;
      gameplayObserved = false;
      return unavailable("Start the game, then load a save to connect its mod runtime.");
    }
    if (running !== true) return unavailable("The game controls are not connected. The game process could not be checked.");
    quietSince ??= now();
    const quietSeconds = Math.round((now() - quietSince) / 1000);
    if (quietSeconds >= STARTUP_HANG_AFTER_SECONDS) {
      if (gameplayObserved) return unavailable("The game's mod runtime stopped responding during this session. Check UE4SS.log; close and restart the game if it remains unresponsive.");
      return unavailable(`The game has been running for ${quietSeconds}s without its mod runtime responding${lastSeen ? ` (last seen ${lastSeen})` : ""}. It may have encountered the known startup freeze. Close the game (Task Manager if needed) and start it again. Quitting through the game's own menu reduces this risk.`);
    }
    return unavailable(`The game is running, but its mod runtime has not responded${lastSeen ? ` (last seen ${lastSeen})` : " yet"}. If it is still starting, wait for the menu screen; if this persists, check UE4SS.log or restart the game.`);
  }
  // The heartbeat of the last snapshot already handled as an unclean exit, so the
  // recovery runs once per exit and not on every poll of the same stale file.
  let uncleanHandled: number | undefined;
  let uncleanOutcome: string | undefined;
  async function state(): Promise<ImportedMenuSnapshot> {
    try {
      const value = await boundedJson(join(options.channelRoot, "state.json"));
      if (!validSnapshot(value) || !Number.isFinite(value.heartbeat)) return unavailable("The runtime response is incompatible. Use the current menu with its matching runtime.");
      const expected = await options.expectedBuildId();
      if (!expected) return unavailable("The menu could not read the build its runtime was accepted against. Reinstall the current menu.");
      if (value.buildId !== expected) {
        // Naming both sides turns a game patch into an obvious, actionable message
        // instead of an unexplained disconnection.
        return unavailable(`The game runtime reports build ${value.buildId ?? "unknown"}, but this menu was accepted against build ${expected}. Reinstall the current menu for the installed game build.`);
      }
      const heartbeatAgeSeconds = Math.abs(now() / 1000 - value.heartbeat!);
      if (heartbeatAgeSeconds <= 5) quietSince = undefined;
      if (heartbeatAgeSeconds > 5) {
        // The heartbeat has stopped. That is all the file can say: a normal exit and a
        // hung runtime leave it identically. So the process is asked, and the message
        // says only what was actually established - a confirmed exit, a confirmed
        // running game whose runtime has gone quiet, or that neither could be checked.
        const lastSeen = new Date(value.heartbeat! * 1000).toLocaleTimeString();
        const running = options.gameRunning ? await options.gameRunning() : undefined;
        if (running === false) {
          // A confirmed exit ends the quiet period: the next launch starts its own clock,
          // otherwise a relaunch after the freeze advice would be mislabelled as frozen at 0 s.
          quietSince = undefined;
          gameplayObserved = false;
          if (typeof value.shutdown === "string") {
            return unavailable(`The game was closed normally (runtime last seen ${lastSeen}). Start the game, then load a save.`);
          }
          // Missing markers also occur when the shutdown callback is unavailable.
          // Report only the missing confirmation; do not infer a crash or forced close.
          if (uncleanHandled !== value.heartbeat) {
            uncleanHandled = value.heartbeat!;
            if (options.onUncleanExit) {
              // An optional caller-owned handler runs without blocking state polling.
              // The desktop does not install a handler or restart Steam automatically.
              uncleanOutcome = "Recovery is running; wait for this message to change before starting the game.";
              const exit = { lastHeartbeat: value.heartbeat!, sessionId: value.sessionId };
              void options.onUncleanExit(exit).then(
                outcome => { if (uncleanHandled === exit.lastHeartbeat) uncleanOutcome = outcome ?? "Steam restart finished."; },
                error => { if (uncleanHandled === exit.lastHeartbeat) uncleanOutcome = `Steam could not be restarted (${error instanceof Error ? error.message : String(error)}). Restart Steam yourself before launching the game.`; });
            } else {
              uncleanOutcome = undefined;
            }
          }
          return unavailable(`The game ended without a recorded shutdown confirmation (runtime last seen ${lastSeen}).${uncleanOutcome ? ` ${uncleanOutcome}` : " The next launch may freeze on a black screen at startup; if it does, close the game and start it again - this recovered the observed startup freezes."} Then load a save.`);
        }
        if (running === true) {
          // A game process with no runtime heartbeat is either still booting or frozen at
          // startup. The freeze (qa/validation-20260918/HANG-ANALYSIS.md): with UE4SS loaded,
          // a launch that follows a crash or forced close can deadlock the game thread
          // against the render thread during startup; Unreal's 120 s render-fence timeout
          // then reports a hang behind the fullscreen window and the boot is dead. A normal
          // boot reaches the menu screen in under two minutes here, so after that the message
          // names the state and the recovery that has worked every time: close and relaunch.
          return stoppedRuntime(running, lastSeen);
        }
        return unavailable(`The mod runtime has not responded for ${Math.round(heartbeatAgeSeconds)}s (last seen ${lastSeen}). If the game is open, its runtime may have stopped; if not, start the game, then load a save.`);
      }
      if (!value.ready) return unavailable("Load a playable save to connect the game controls.");
      if (!await options.verifyRuntime()) return unavailable(options.verificationFailure?.() ?? "The runtime files could not be verified. Use the current menu with its matching runtime.");
      gameplayObserved = true;
      const gated = await applyBuildPins(value);
      if (pending?.session !== value.sessionId) pending = undefined;
      if (pending) {
        if (value.operation?.id === pending.id) pending = undefined;
        else {
          const expired = now() - pending.at > 8000;
          // Only this reviewed automatic read can release a missing acknowledgement.
          // Its five-second wire deadline is already over; never replay it or clear an
          // uncertain mutation. A different running native operation still owns the channel.
          const nativeBusy = gated.operation && ["queued", "running", "awaiting-confirmation"].includes(gated.operation.status);
          if (expired && pending.readOnly && !nativeBusy && !gated.confirmation) {
            const id = pending.id;
            pending = undefined;
            return { ...gated, operation: { id, status: "failed", message: "Quest refresh was not acknowledged. The game is connected; refresh the journal again when ready." } };
          }
          return { ...gated, ready: !expired,
            operation: { id: pending.id, status: expired ? "failed" : "queued", message: "Waiting for the game to acknowledge the request." } };
        }
      }
      return gated;
    } catch {
      let running: boolean | undefined;
      try { running = await options.gameRunning?.(); } catch { /* A failed process probe cannot establish whether the game exited. */ }
      return stoppedRuntime(running);
    }
  }
  async function dispatch(request: ImportedMenuDispatchRequest): Promise<{ accepted: boolean; message: string; operationId?: string }> {
    if (writing) return { accepted: false, message: "A request is already being sent." };
    writing = true;
    let temporary: string | undefined;
    try {
      const snapshot = await state();
      // Two different situations were sharing one message. "Wait for the game
      // connection" over a connected game with a request in flight sent the player
      // looking for a disconnection that was not there.
      if (!snapshot.ready) throw new Error(snapshot.message ?? "Load a playable save to connect the game controls.");
      if (pending) throw new Error("Another request is still being applied. Wait for it to finish, then try again.");
      const readOnlyItem = Boolean(request.sectionId && request.itemId
        && options.buildPinReadOnlyItems?.[request.sectionId]?.includes(request.itemId));
      const pinned = request.sectionId && !readOnlyItem ? await buildPinReason(request.sectionId) : undefined;
      if (pinned) throw new Error(pinned);
      validateImportedRequest(request, snapshot);
      const id = randomUUID();
      const fields: Record<string, string> = {
        request_id: id, session_id: snapshot.sessionId, action: request.action,
        section_id: request.sectionId ?? "", item_id: request.itemId ?? "",
        value: request.value === undefined ? "" : String(request.value),
        value_type: request.value === undefined ? "" : typeof request.value,
        confirmation_token: request.confirmationToken ?? "", confirmed: request.confirmed === true ? "true" : "false",
        expires_at: String(Math.floor(now() / 1000) + 5),
      };
      const contents = Object.entries(fields).map(([key, value]) => `${key}=${encodeURIComponent(value)}`).join("\n") + "\n";
      await mkdir(options.channelRoot, { recursive: true });
      temporary = join(options.channelRoot, `command-${id}.tmp`);
      await writeFile(temporary, contents, { flag: "wx" });
      await rename(temporary, join(options.channelRoot, "command.txt"));
      pending = { id, session: snapshot.sessionId, at: now(), readOnly: request.action === "invoke" && request.sectionId === "DWQuestReadback" && request.itemId === "refresh" };
      return { accepted: true, operationId: id, message: "Request queued. Check the control's game status." };
    } catch (error) { return { accepted: false, message: error instanceof Error ? error.message : "The request could not be sent." }; }
    finally { if (temporary) await unlink(temporary).catch(() => undefined); writing = false; }
  }
  return { state, dispatch };
}


