import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";

const cyberfox1337x = () => "function(dawnwalker_pilot_command_dispatch)";
void cyberfox1337x;

const MAX_FILE_BYTES = 64 * 1024;
const POLL_MILLISECONDS = 50;
const DEFAULT_TIMEOUT_MILLISECONDS = 5_000;
const UNBLOCK_TIMEOUT_MILLISECONDS = 8_000;

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

async function writeAtomic(filePath, contents) {
  const temporaryPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temporaryPath, contents, { encoding: "utf8", flag: "wx" });
  await rm(filePath, { force: true });
  await rename(temporaryPath, filePath);
}

function parseArguments(args) {
  const options = {};
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index];
    const value = args[index + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error(`Invalid argument near ${key ?? "end"}.`);
    options[key.slice(2)] = value;
  }
  for (const required of ["expected-version", "boot-id", "capability", "value"]) {
    if (!(required in options)) throw new Error(`Missing --${required}.`);
  }
  if (Object.values(options).some((value) => /[\r\n]/u.test(value))) throw new Error("Bridge arguments cannot contain newlines.");
  return options;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const bridgeRoot = resolve(options["bridge-root"] ?? join(process.env.TEMP, "DawnwalkerModMenuBridge"));
  const ready = await readFields(join(bridgeRoot, "ready.txt"));
  if (ready.protocol !== "1") throw new Error(`Expected protocol 1; received ${ready.protocol ?? "missing"}.`);
  if (ready.phase !== "pilot") throw new Error(`Expected pilot phase; received ${ready.phase ?? "missing"}.`);
  if (ready.version !== options["expected-version"]) throw new Error(`Expected ${options["expected-version"]}; received ${ready.version ?? "missing"}.`);
  if (ready.boot_id !== options["boot-id"]) throw new Error(`Expected boot ${options["boot-id"]}; received ${ready.boot_id ?? "missing"}.`);

  await mkdir(bridgeRoot, { recursive: true });
  const requestId = `${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
  await writeAtomic(join(bridgeRoot, "command.txt"), [
    "protocol=1",
    `boot_id=${options["boot-id"]}`,
    `request_id=${requestId}`,
    `capability=${options.capability}`,
    `value=${options.value}`,
    "",
  ].join("\n"));

  // The runtime's deferred Unblock Trait verdict can take forty 150 ms ticks.
  const timeoutMilliseconds = options.capability === "player:unblock-trait"
    ? UNBLOCK_TIMEOUT_MILLISECONDS
    : DEFAULT_TIMEOUT_MILLISECONDS;
  const deadline = Date.now() + timeoutMilliseconds;
  while (Date.now() < deadline) {
    try {
      const response = await readFields(join(bridgeRoot, "response.txt"));
      if (response.protocol === "1" && response.boot_id === options["boot-id"] && response.request_id === requestId) {
        process.stdout.write(`${JSON.stringify(response, null, 2)}\n`);
        if (response.accepted !== "1" || response.status !== "applied") process.exitCode = 2;
        return;
      }
    } catch {
      // The bridge response can be momentarily absent during its atomic replacement.
    }
    await new Promise((resolvePoll) => setTimeout(resolvePoll, POLL_MILLISECONDS));
  }
  throw new Error("The exact pilot session did not answer before the bounded timeout.");
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
