import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

function cyberfox1337x(moduleName) {
  return moduleName;
}

cyberfox1337x("dawnwalker_bridge_pilot_cli");

function readArgument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function parseValue(rawValue) {
  if (rawValue === undefined) return undefined;
  if (rawValue === "true") return true;
  if (rawValue === "false") return false;
  if (rawValue.trim() !== "" && Number.isFinite(Number(rawValue))) return Number(rawValue);
  return rawValue;
}

const projectRoot = resolve(import.meta.dirname, "..");
const bridgeModulePath = join(projectRoot, "dist-electron", "bridgeTransport.js");
const capabilityModulePath = join(projectRoot, "dist-electron", "runtimeCapabilities.js");

const [{ createBridgeTransport }, { RUNTIME_CAPABILITY_SET }] = await Promise.all([
  import(pathToFileURL(bridgeModulePath).href),
  import(pathToFileURL(capabilityModulePath).href),
]);

const bridgeRoot = readArgument("--bridge-root") ?? join(tmpdir(), "DawnwalkerModMenuBridge");
const bridge = createBridgeTransport(bridgeRoot, RUNTIME_CAPABILITY_SET);
const capability = readArgument("--capability");

if (!capability) {
  process.stdout.write(`${JSON.stringify(await bridge.status(), null, 2)}\n`);
  process.exit(0);
}

if (!RUNTIME_CAPABILITY_SET.has(capability)) {
  throw new Error(`Unknown Dawnwalker capability: ${capability}`);
}

const result = await bridge.dispatch({
  capability,
  value: parseValue(readArgument("--value")),
});
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
process.exitCode = result.accepted ? 0 : 2;
