import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createPilotQaBridge } from "../../scripts/Run-DawnwalkerLivePilotQa.mjs";

function cyberfox1337x(moduleName) { return moduleName; }
cyberfox1337x("player_current_build_resource_roundtrip");

const HEALTH = "player:infinite-health";
const STAMINA = "player:unlimited-stamina";
const GOD = "player:god-mode";
const FIELDS = ["health_percent", "stamina_percent", "blood", "blood_max"];
const EXPECTED_EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853";

function parsePlayer(readback) {
  const player = Object.fromEntries(String(readback).split(";").map((pair) => {
    const [key, number] = pair.split("=");
    return [key, Number(number)];
  }));
  if (Number.isFinite(player.blood_max) && player.blood_max <= 0) {
    throw new Error("Blood resource unavailable in this form/save; God Mode roundtrip cannot be tested safely.");
  }
  if (player.alive !== 1 || FIELDS.some((field) => !Number.isFinite(player[field]))
      || player.health_percent < 0 || player.health_percent > 100
      || player.stamina_percent < 0 || player.stamina_percent > 100
      || player.blood_max <= 0 || player.blood < 0 || player.blood > player.blood_max) {
    throw new Error("Missing, dead, or invalid player resource readback.");
  }
  return player;
}

function assertRestored(before, after, fields) {
  for (const field of fields) {
    if (Math.abs(before[field] - after[field]) > 0.001) {
      throw new Error(`Baseline restoration mismatch: ${field} ${before[field]} -> ${after[field]}.`);
    }
  }
}

/** Tests command/readback restoration, not combat endurance or invulnerability. */
export async function runResourceRoundtrip({ bridge, bootId, holdMilliseconds = 0,
  wait = (duration) => new Promise((done) => setTimeout(done, duration)) }) {
  if (!/^\d{9,12}-\d{6}$/.test(bootId ?? "")) throw new Error("An exact observed boot ID is required.");
  if (!Number.isInteger(holdMilliseconds) || holdMilliseconds < 0 || holdMilliseconds > 30000) {
    throw new Error("Hold duration must be 0..30000 milliseconds.");
  }
  const evidence = { schema: 1, buildId: "25129649", bootId, steps: [], passed: false,
    gameplayEnduranceVerified: false, cleanupErrors: [], limitation:
      "Resource ON/OFF and shared-owner readback only. Does not establish damage or sprint endurance." };
  const owned = new Set();
  let baseline;
  async function session() {
    const status = await bridge.status();
    if (!status.connected || status.bootId !== bootId || status.phase !== "pilot"
        || status.bridgeVersion !== "0.3.21-pilot"
        || ![HEALTH, STAMINA, GOD, "player:player-info"].every((name) => status.capabilities.includes(name))) {
      throw new Error("Exact fresh gameplay pilot session required; no command was sent to a replacement session.");
    }
    return status;
  }
  async function dispatch(capability, value) {
    await session();
    // Record possible ownership before dispatch: a lost response may follow a successful mutation.
    if (value === true) owned.add(capability);
    const response = await bridge.dispatch({ capability, value }, bootId);
    evidence.steps.push({ capability, value, response, at: new Date().toISOString() });
    await session();
    if (!response.accepted || response.status !== "applied") throw new Error(response.message || "Command rejected.");
    if (value !== undefined && response.readback !== (value ? "1" : "0")) throw new Error("Toggle readback mismatch.");
    if (value === false) owned.delete(capability);
    return response;
  }
  async function player() { return parsePlayer((await dispatch("player:player-info")).readback); }
  async function full(capability) {
    const reading = await player();
    const fields = capability === HEALTH ? ["health_percent"] : capability === STAMINA
      ? ["stamina_percent"] : ["health_percent", "stamina_percent"];
    if (fields.some((field) => reading[field] < 99.9)
        || (capability === GOD && reading.blood / reading.blood_max < 0.999)) {
      throw new Error("Enabled resource was not full in independent player readback.");
    }
    return reading;
  }
  try {
    const initial = await session();
    if (!Array.isArray(initial.active) || initial.active.length) throw new Error("Start with no active capabilities.");
    baseline = await player();
    evidence.baseline = baseline;
    for (const capability of [HEALTH, STAMINA, GOD]) {
      const before = await player();
      await dispatch(capability, true);
      await full(capability);
      if (holdMilliseconds) {
        await wait(holdMilliseconds);
        await full(capability);
      }
      await dispatch(capability, false);
      assertRestored(before, await player(), capability === HEALTH ? ["health_percent"]
        : capability === STAMINA ? ["stamina_percent"] : FIELDS);
    }
    // Both release orders catch an implementation that accidentally unlocks another owner's resource.
    for (const individual of [HEALTH, STAMINA]) {
      for (const releaseGodFirst of [true, false]) {
        const before = await player();
        await dispatch(individual, true);
        await dispatch(GOD, true);
        await full(GOD);
        await dispatch(releaseGodFirst ? GOD : individual, false);
        await full(releaseGodFirst ? individual : GOD);
        await dispatch(releaseGodFirst ? individual : GOD, false);
        assertRestored(before, await player(), FIELDS);
      }
    }
  } catch (error) {
    evidence.error = error.message;
  } finally {
    for (const capability of [GOD, STAMINA, HEALTH]) {
      if (!owned.has(capability)) continue;
      try { await dispatch(capability, false); }
      catch (error) { evidence.cleanupErrors.push(`${capability}: ${error.message}`); }
    }
    if (baseline) {
      try {
        evidence.final = await player();
        assertRestored(baseline, evidence.final, FIELDS);
        let status = await session();
        // ready.txt updates once per second; permit a bounded heartbeat settling period.
        for (let attempt = 0; status.active.length && attempt < 12; attempt++) {
          await wait(250);
          status = await session();
        }
        if (status.active.length) throw new Error("Active capabilities remain after cleanup.");
        evidence.restorationVerified = true;
      } catch (error) { evidence.cleanupErrors.push(error.message); }
    }
  }
  evidence.passed = !evidence.error && evidence.restorationVerified === true && !evidence.cleanupErrors.length;
  return evidence;
}

async function main() {
  const argumentsList = process.argv.slice(2);
  if (argumentsList.length % 2) throw new Error("Use named option/value pairs.");
  const options = Object.fromEntries(Array.from({ length: argumentsList.length / 2 }, (_, index) =>
    [argumentsList[index * 2], argumentsList[index * 2 + 1]]));
  for (const required of ["--execute", "--boot-id", "--bridge-root", "--game-exe", "--evidence"]) {
    if (!options[required]) throw new Error(`Missing ${required}. No live commands sent.`);
  }
  if (!["resource-roundtrip", "read-only"].includes(options["--execute"])) throw new Error("Explicit read-only or resource-roundtrip mode required.");
  const executable = await readFile(options["--game-exe"]);
  const digest = createHash("sha256").update(executable).digest("hex").toUpperCase();
  if (digest !== EXPECTED_EXECUTABLE_SHA256 || executable.length !== 176196472) throw new Error("Current-build identity mismatch.");
  const bridgeSource = await readFile(new URL("../../integration/uue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua", import.meta.url), "utf8");
  const capabilityBlock = bridgeSource.match(/local CAPABILITY_LIST = \{([\s\S]*?)\n\}/)?.[1];
  if (!capabilityBlock) throw new Error("Canonical native capability list was not found.");
  const expectedCapabilities = [...capabilityBlock.matchAll(/"([a-z:-]+)"/g)].map((match) => match[1]);
  const bridge = createPilotQaBridge(resolve(options["--bridge-root"]), { expectedCapabilities });
  // Reserve evidence path before mutations so an unwritable destination fails early.
  const evidencePath = resolve(options["--evidence"]);
  await writeFile(evidencePath, JSON.stringify({ started: new Date().toISOString(), executableSha256: digest }), { flag: "wx" });
  let evidence;
  if (options["--execute"] === "read-only") {
    const response = await bridge.dispatch({ capability: "player:player-info" }, options["--boot-id"]);
    evidence = { passed: response.accepted === true, readOnly: true, response, cleanupErrors: [] };
    if (response.accepted) evidence.player = parsePlayer(response.readback);
  } else {
    evidence = await runResourceRoundtrip({ bridge,
      bootId: options["--boot-id"], holdMilliseconds: Number(options["--hold-ms"] ?? 0) });
  }
  evidence.executableSha256 = digest;
  evidence.nativeSourceSha256 = createHash("sha256").update(bridgeSource).digest("hex");
  evidence.expectedCapabilities = expectedCapabilities;
  await writeFile(evidencePath, JSON.stringify(evidence, null, 2) + "\n");
  process.stdout.write(JSON.stringify({ passed: evidence.passed, evidencePath, error: evidence.error,
    cleanupErrors: evidence.cleanupErrors }) + "\n");
  process.exitCode = evidence.passed ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => { process.stderr.write(error.message + "\n"); process.exitCode = 1; });
}
