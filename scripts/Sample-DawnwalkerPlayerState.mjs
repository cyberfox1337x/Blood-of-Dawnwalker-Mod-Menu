import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";

const cyberfox1337x = () => "function(dawnwalker_player_state_sampler)";
void cyberfox1337x;

// Read-only high-rate sampler for the resource-lock endurance protocols documented in
// GAMEPLAY-CONTRACT-RESEARCH.md. It issues only `player:player-info`, which is a read-only
// capability, and never sends a value that could mutate state. A single process reuses one
// verified handshake so sampling can reach the 150-250 ms cadence the protocol requires;
// spawning Dispatch-DawnwalkerPilotCommand.mjs per sample costs ~500 ms of startup instead.

const MAX_FILE_BYTES = 64 * 1024;
const RESPONSE_POLL_MILLISECONDS = 20;
const RESPONSE_TIMEOUT_MILLISECONDS = 5_000;
const READ_ONLY_CAPABILITY = "player:player-info";

function parseFields(contents) {
  return Object.fromEntries(
    contents
      .split(/\r?\n/u)
      .filter(Boolean)
      .map((line) => {
        const separator = line.indexOf("=");
        if (separator < 1) throw new Error("Malformed bridge field.");
        return [line.slice(0, separator), line.slice(separator + 1)];
      }),
  );
}

async function readFields(filePath) {
  const file = await stat(filePath);
  if (!file.isFile() || file.size > MAX_FILE_BYTES) throw new Error(`Invalid bridge file: ${filePath}`);
  return parseFields(await readFile(filePath, "utf8"));
}

// The game side reads command.txt on its own tick, so a high-rate replace can collide with
// that open handle and raise EBUSY/EPERM on Windows. Retry briefly instead of aborting the
// run; a genuinely stuck file still fails after the bounded attempts.
async function writeAtomic(filePath, contents) {
  const temporaryPath = `${filePath}.${process.pid}.${Date.now()}.${randomUUID().slice(0, 8)}.tmp`;
  await writeFile(temporaryPath, contents, { encoding: "utf8", flag: "wx" });
  let lastError = null;
  for (let attempt = 0; attempt < 25; attempt += 1) {
    try {
      await rm(filePath, { force: true });
      await rename(temporaryPath, filePath);
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolveRetry) => setTimeout(resolveRetry, 20));
    }
  }
  await rm(temporaryPath, { force: true }).catch(() => {});
  throw lastError ?? new Error(`Unable to replace ${filePath}.`);
}

/** Parses `alive=1;health_percent=100.0;...` into a plain object of numbers. */
function parseReadback(readback) {
  const parsed = {};
  for (const pair of String(readback ?? "").split(";")) {
    if (!pair) continue;
    const separator = pair.indexOf("=");
    if (separator < 1) continue;
    const value = Number(pair.slice(separator + 1));
    parsed[pair.slice(0, separator)] = Number.isFinite(value) ? value : null;
  }
  return parsed;
}

async function requestPlayerInfo(bridgeRoot, bootId) {
  const requestId = `${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
  await writeAtomic(join(bridgeRoot, "command.txt"), [
    "protocol=1",
    `boot_id=${bootId}`,
    `request_id=${requestId}`,
    `capability=${READ_ONLY_CAPABILITY}`,
    "value=",
    "",
  ].join("\n"));

  const deadline = Date.now() + RESPONSE_TIMEOUT_MILLISECONDS;
  while (Date.now() < deadline) {
    try {
      const response = await readFields(join(bridgeRoot, "response.txt"));
      if (response.protocol === "1" && response.boot_id === bootId && response.request_id === requestId) {
        if (response.accepted !== "1" || response.status !== "applied") {
          throw new Error(`Bridge rejected the read-only query: ${response.message ?? "no message"}`);
        }
        return parseReadback(response.readback);
      }
    } catch (error) {
      // The response file is briefly absent during its atomic replacement. A genuine
      // rejection is rethrown rather than swallowed.
      if (error instanceof Error && error.message.startsWith("Bridge rejected")) throw error;
    }
    await new Promise((resolvePoll) => setTimeout(resolvePoll, RESPONSE_POLL_MILLISECONDS));
  }
  throw new Error("The exact pilot session did not answer before the bounded timeout.");
}

function parseArguments(args) {
  const options = {};
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index];
    const value = args[index + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error(`Invalid argument near ${key ?? "end"}.`);
    options[key.slice(2)] = value;
  }
  for (const required of ["expected-version", "boot-id", "seconds"]) {
    if (!options[required]) throw new Error(`Missing required --${required}.`);
  }
  return options;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const bridgeRoot = resolve(options["bridge-root"] ?? join(process.env.TEMP, "DawnwalkerModMenuBridge"));
  const seconds = Number(options.seconds);
  if (!Number.isFinite(seconds) || seconds <= 0 || seconds > 300) {
    throw new Error("--seconds must be a finite number between 0 and 300.");
  }
  const label = options.label ?? "sample";

  const ready = await readFields(join(bridgeRoot, "ready.txt"));
  if (ready.protocol !== "1") throw new Error(`Expected protocol 1; received ${ready.protocol ?? "missing"}.`);
  if (ready.phase !== "pilot") throw new Error(`Expected pilot phase; received ${ready.phase ?? "missing"}.`);
  if (ready.version !== options["expected-version"]) {
    throw new Error(`Expected ${options["expected-version"]}; received ${ready.version ?? "missing"}.`);
  }
  if (ready.boot_id !== options["boot-id"]) {
    throw new Error(`Expected boot ${options["boot-id"]}; received ${ready.boot_id ?? "missing"}.`);
  }
  await mkdir(bridgeRoot, { recursive: true });

  const samples = [];
  const startedAt = Date.now();
  const endAt = startedAt + seconds * 1000;
  while (Date.now() < endAt) {
    const reading = await requestPlayerInfo(bridgeRoot, options["boot-id"]);
    samples.push({ atMilliseconds: Date.now() - startedAt, ...reading });
  }

  const summarise = (field) => {
    const values = samples.map((sample) => sample[field]).filter((value) => typeof value === "number");
    if (values.length === 0) return null;
    const first = values[0];
    const last = values[values.length - 1];
    return {
      first,
      last,
      min: Math.min(...values),
      max: Math.max(...values),
      // Negative drop means the value fell during the window.
      drop: Number((first - Math.min(...values)).toFixed(4)),
    };
  };

  const cadences = samples.slice(1).map((sample, index) => sample.atMilliseconds - samples[index].atMilliseconds);
  const meanCadence = cadences.length
    ? Math.round(cadences.reduce((total, value) => total + value, 0) / cadences.length)
    : null;

  process.stdout.write(`${JSON.stringify({
    label,
    bootId: options["boot-id"],
    bridgeVersion: ready.version,
    readOnly: true,
    sampleCount: samples.length,
    meanCadenceMilliseconds: meanCadence,
    health: summarise("health_percent"),
    stamina: summarise("stamina_percent"),
    blood: summarise("blood"),
    alive: summarise("alive"),
  }, null, 2)}\n`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
