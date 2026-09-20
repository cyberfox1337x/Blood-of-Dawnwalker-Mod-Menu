import { mkdirSync } from "node:fs";
import { readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_bridge_transport");

const BRIDGE_PROTOCOL = "1";
const READY_FRESHNESS_SECONDS = 5;
const MAX_BRIDGE_FILE_BYTES = 64 * 1024;
const RESPONSE_POLL_MILLISECONDS = 50;
const FILE_CONTENTION_RETRY_DELAYS_MILLISECONDS = [10, 25, 50, 100] as const;

export type BridgeCommand = Readonly<{
  capability: string;
  value?: boolean | number | string;
  expectedBootId?: string;
}>;

export type BridgeResult = Readonly<{
  accepted: boolean;
  capability: string;
  requestId: string;
  status: "applied" | "rejected" | "timeout";
  message: string;
  readback?: string;
}>;

export type BridgeStatus = Readonly<{
  connected: boolean;
  phase?: string;
  bootId?: string;
  bridgeVersion?: string;
  capabilities: readonly string[];
  active: readonly string[];
  capabilitySetExact?: boolean;
}>;

type BridgeFields = Readonly<Record<string, string>>;
type AtomicFileOperations = Readonly<{
  remove: (targetPath: string, options: Readonly<{ force: boolean }>) => Promise<void>;
  rename: (temporaryPath: string, targetPath: string) => Promise<void>;
}>;

const DEFAULT_ATOMIC_FILE_OPERATIONS: AtomicFileOperations = Object.freeze({
  remove: (targetPath, options) => rm(targetPath, options),
  rename,
});

function parseFields(contents: string): BridgeFields {
  const fields: Record<string, string> = {};
  for (const line of contents.split(/\r?\n/)) {
    const separator = line.indexOf("=");
    if (separator <= 0) continue;
    const key = line.slice(0, separator);
    if (/^[a-z_]+$/.test(key)) fields[key] = line.slice(separator + 1);
  }
  return fields;
}

async function readFields(targetPath: string): Promise<BridgeFields | null> {
  try {
    const fileInfo = await stat(targetPath);
    if (!fileInfo.isFile() || fileInfo.size > MAX_BRIDGE_FILE_BYTES) return null;
    return parseFields(await readFile(targetPath, "utf8"));
  } catch {
    return null;
  }
}

function isRetryableFileContention(error: unknown): error is NodeJS.ErrnoException {
  if (!(error instanceof Error)) return false;
  const errorCode = (error as NodeJS.ErrnoException).code;
  return errorCode === "EBUSY" || errorCode === "EPERM";
}

async function retryFileContention(operation: () => Promise<void>): Promise<void> {
  for (let attempt = 0; ; attempt += 1) {
    try {
      await operation();
      return;
    } catch (error: unknown) {
      const retryDelay = FILE_CONTENTION_RETRY_DELAYS_MILLISECONDS[attempt];
      if (!isRetryableFileContention(error) || retryDelay === undefined) throw error;
      await new Promise((resolveRetry) => setTimeout(resolveRetry, retryDelay));
    }
  }
}

async function writeAtomic(
  targetPath: string,
  contents: string,
  fileOperations: AtomicFileOperations,
): Promise<void> {
  const temporaryPath = `${targetPath}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temporaryPath, contents, { encoding: "utf8", flag: "wx" });
  await retryFileContention(() => fileOperations.remove(targetPath, { force: true }));
  await retryFileContention(() => fileOperations.rename(temporaryPath, targetPath));
}

function cleanList(value: string | undefined): readonly string[] {
  if (!value) return [];
  return [...new Set(value.split(",").map((item) => item.trim()).filter(Boolean))];
}

function safeProtocolValue(value: boolean | number | string | undefined): string {
  if (value === undefined) return "";
  const serialized = typeof value === "boolean" ? (value ? "1" : "0") : String(value);
  if (serialized.length > 4096 || /[\r\n]/.test(serialized)) throw new Error("Invalid bridge command value.");
  return serialized;
}

function validReady(fields: BridgeFields | null, nowSeconds: number): fields is BridgeFields {
  if (!fields || fields.protocol !== BRIDGE_PROTOCOL || !/^[a-zA-Z0-9-]{3,80}$/.test(fields.boot_id ?? "")) return false;
  const heartbeat = Number(fields.heartbeat);
  return Number.isFinite(heartbeat) && Math.abs(nowSeconds - heartbeat) <= READY_FRESHNESS_SECONDS;
}

export function createBridgeTransport(
  bridgeRoot: string,
  knownCapabilities: ReadonlySet<string>,
  fileOperations: AtomicFileOperations = DEFAULT_ATOMIC_FILE_OPERATIONS,
) {
  mkdirSync(bridgeRoot, { recursive: true });
  const commandPath = join(bridgeRoot, "command.txt");
  const responsePath = join(bridgeRoot, "response.txt");
  const readyPath = join(bridgeRoot, "ready.txt");
  let commandSequence = 0;
  let dispatchQueue: Promise<BridgeResult> = Promise.resolve({
    accepted: false,
    capability: "",
    requestId: "bootstrap",
    status: "rejected",
    message: "Bridge queue initialized.",
  });

  async function status(): Promise<BridgeStatus> {
    const ready = await readFields(readyPath);
    if (!validReady(ready, Date.now() / 1000)) return { connected: false, capabilities: [], active: [] };
    const rawCapabilities = ready.capabilities
      ? ready.capabilities.split(",").map((capability) => capability.trim()).filter(Boolean)
      : [];
    const capabilities = cleanList(ready.capabilities).filter((capability) => knownCapabilities.has(capability));
    return {
      connected: true,
      phase: ready.phase,
      bootId: ready.boot_id,
      bridgeVersion: ready.version,
      capabilities,
      active: cleanList(ready.active).filter((capability) => knownCapabilities.has(capability)),
      capabilitySetExact: rawCapabilities.length === knownCapabilities.size
        && new Set(rawCapabilities).size === rawCapabilities.length
        && capabilities.length === knownCapabilities.size,
    };
  }

  async function waitForResponse(
    capability: string,
    requestId: string,
    bootId: string,
    timeoutMilliseconds: number,
  ): Promise<BridgeResult> {
    const deadline = Date.now() + timeoutMilliseconds;
    while (Date.now() < deadline) {
      const response = await readFields(responsePath);
      if (response?.protocol === BRIDGE_PROTOCOL && response.boot_id === bootId && response.request_id === requestId) {
        const accepted = response.accepted === "1" && response.status === "applied";
        return {
          accepted,
          capability,
          requestId,
          status: accepted ? "applied" : "rejected",
          message: response.message || "The bridge returned no message.",
          ...(response.readback ? { readback: response.readback } : {}),
        };
      }
      await new Promise((resolvePoll) => setTimeout(resolvePoll, RESPONSE_POLL_MILLISECONDS));
    }
    return {
      accepted: false,
      capability,
      requestId,
      status: "timeout",
      message: "The game bridge did not answer before the bounded timeout.",
    };
  }

  async function dispatchNow(command: BridgeCommand): Promise<BridgeResult> {
    if (!knownCapabilities.has(command.capability)) {
      return {
        accepted: false,
        capability: command.capability,
        requestId: "rejected",
        status: "rejected",
        message: "Rejected an unknown Dawnwalker capability.",
      };
    }

    const ready = await readFields(readyPath);
    if (!validReady(ready, Date.now() / 1000)) {
      return {
        accepted: false,
        capability: command.capability,
        requestId: "disconnected",
        status: "rejected",
        message: "The verified Dawnwalker offline bridge is not connected.",
      };
    }
    if (command.expectedBootId && ready.boot_id !== command.expectedBootId) {
      return {
        accepted: false,
        capability: command.capability,
        requestId: "session-changed",
        status: "rejected",
        message: "The Dawnwalker bridge session changed before command dispatch.",
      };
    }
    if (!cleanList(ready.capabilities).includes(command.capability)) {
      return {
        accepted: false,
        capability: command.capability,
        requestId: "not-advertised",
        status: "rejected",
        message: "The running bridge does not advertise this verified capability.",
      };
    }

    commandSequence += 1;
    const requestId = `${Date.now().toString(36)}-${commandSequence.toString(36)}`;
    await writeAtomic(commandPath, [
      `protocol=${BRIDGE_PROTOCOL}`,
      `boot_id=${ready.boot_id}`,
      `request_id=${requestId}`,
      `capability=${command.capability}`,
      `value=${safeProtocolValue(command.value)}`,
      "",
    ].join("\n"), fileOperations);
    // Unblock Trait can defer its readback for forty 150 ms game ticks. Keep the
    // dispatch queue locked until that verdict can arrive, including file-poll slack.
    const timeoutMilliseconds = command.capability.startsWith("teleport:")
      ? 10_000
      : command.capability === "player:unblock-trait" ? 8_000 : 3_500;
    return waitForResponse(command.capability, requestId, ready.boot_id, timeoutMilliseconds);
  }

  function dispatch(command: BridgeCommand): Promise<BridgeResult> {
    const run = dispatchQueue.then(() => dispatchNow(command));
    const safeRun = run.catch((error: unknown) => ({
      accepted: false,
      capability: command.capability,
      requestId: "failed-safe",
      status: "rejected" as const,
      message: error instanceof Error ? error.message : "The local bridge failed safely.",
    }));
    dispatchQueue = safeRun;
    return safeRun;
  }

  return Object.freeze({ status, dispatch });
}
