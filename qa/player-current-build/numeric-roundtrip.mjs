import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createPilotQaBridge } from "../../scripts/Run-DawnwalkerLivePilotQa.mjs";

function cyberfox1337x(moduleName) { return moduleName; }
cyberfox1337x("player_current_build_numeric_roundtrip");

const BLOOD = "player:blood-energy";
const TRAITS = "player:trait-points";
const GOLD = "player:add-gold";
const CAPABILITIES = [BLOOD, TRAITS, GOLD];

function numberReadback(capability, response) {
  if (typeof response.readback !== "string" || response.readback.trim() === "") throw new Error("Missing numeric readback.");
  const amount = Number(response.readback);
  const maximum = capability === BLOOD ? 100 : capability === TRAITS ? 9999 : 2147483647;
  if (!Number.isFinite(amount) || amount < 0 || amount > maximum
      || (capability !== BLOOD && !Number.isInteger(amount))) throw new Error(`Invalid ${capability} readback.`);
  return amount;
}

function equal(capability, first, second) {
  // Blood API reports six decimals and its native setter uses a float percentage.
  return Math.abs(first - second) <= (capability === BLOOD ? 0.001 : 0);
}

export async function runNumericRoundtrip({ bridge, bootId }) {
  if (!/^\d{9,12}-\d{6}$/.test(bootId ?? "")) throw new Error("Exact observed boot ID required.");
  const evidence = { schema: 1, buildId: "25129649", bootId, steps: [], roundtrips: [],
    passed: false, cleanupErrors: [], saveReloadVerified: false };
  async function session() {
    const status = await bridge.status();
    if (!status.connected || status.bootId !== bootId || status.phase !== "pilot"
        || status.bridgeVersion !== "0.3.21-pilot"
        || ![...CAPABILITIES, "player:player-info"].every((capability) => status.capabilities.includes(capability))) {
      throw new Error("Exact fresh gameplay session required; replacement-session writes refused.");
    }
    if (!Array.isArray(status.active) || status.active.length) throw new Error("Numeric test requires no active controls.");
    return status;
  }
  async function command(capability, value) {
    await session();
    const response = await bridge.dispatch({ capability, value }, bootId);
    evidence.steps.push({ capability, value, response, at: new Date().toISOString() });
    await session();
    if (!response.accepted || response.status !== "applied") throw new Error(response.message || "Command rejected.");
    return response;
  }
  async function read(capability) { return numberReadback(capability, await command(capability)); }
  async function restore(capability, baseline, target, roundtrip) {
    const observed = await read(capability);
    if (equal(capability, observed, baseline)) {
      roundtrip.restored = true;
      roundtrip.restoredReadback = observed;
      return;
    }
    if (!equal(capability, observed, target)) {
      throw new Error(`${capability} changed outside the owned probe range; do not overwrite unrelated state. Restore the protected save.`);
    }
    // Query first after a lost response: never blindly apply a second currency inverse.
    let restoreError;
    try { await command(capability, capability === GOLD ? -1 : baseline); }
    catch (error) { restoreError = error.message; }
    const final = await read(capability);
    if (!equal(capability, final, baseline)) throw new Error(`${capability} baseline not restored (${restoreError ?? final}).`);
    roundtrip.restored = true;
    roundtrip.restoredReadback = final;
    if (restoreError) roundtrip.restoreResponseError = restoreError;
  }
  try {
    await session();
    const player = await command("player:player-info");
    if (!/(^|;)alive=1(;|$)/.test(player.readback ?? "")) throw new Error("A living player is required.");
    const baselines = {};
    for (const capability of CAPABILITIES) baselines[capability] = await read(capability);
    evidence.baselines = baselines;
    if (baselines[TRAITS] >= 9999 || baselines[GOLD] >= 2147483647) throw new Error("No safe +1 probe within setter bounds.");
    for (const capability of CAPABILITIES) {
      const baseline = await read(capability);
      if (!equal(capability, baseline, baselines[capability])) throw new Error("Baseline drift before mutation; stop gameplay during this test.");
      const target = capability === BLOOD ? 80 : baseline + 1;
      const roundtrip = { capability, baseline, target, restored: false, mutationAttempted: false };
      evidence.roundtrips.push(roundtrip);
      if (equal(capability, baseline, target)) {
        roundtrip.skipped = "Blood is already at 80%; no distinct mutation tested.";
        roundtrip.restored = true;
        continue;
      }
      try {
        roundtrip.mutationAttempted = true;
        const changed = numberReadback(capability, await command(capability, capability === GOLD ? 1 : target));
        if (!equal(capability, changed, target)) throw new Error("Mutation response does not match target.");
        const verified = await read(capability);
        if (!equal(capability, verified, target)) throw new Error("Independent query does not match target.");
        roundtrip.mutationVerified = true;
      } finally {
        if (roundtrip.mutationAttempted) {
          try { await restore(capability, baseline, target, roundtrip); }
          catch (error) { evidence.cleanupErrors.push(error.message); }
        }
      }
      if (evidence.cleanupErrors.length) throw new Error("Restoration failed; no further controls tested.");
    }
    evidence.final = {};
    for (const capability of CAPABILITIES) {
      evidence.final[capability] = await read(capability);
      if (!equal(capability, evidence.final[capability], baselines[capability])) throw new Error("Final baseline drift.");
    }
    evidence.restorationVerified = true;
  } catch (error) { evidence.error = error.message; }
  evidence.passed = !evidence.error && !evidence.cleanupErrors.length && evidence.restorationVerified === true;
  return evidence;
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length % 2) throw new Error("Use named option/value pairs.");
  const options = Object.fromEntries(Array.from({ length: args.length / 2 }, (_, index) => [args[index * 2], args[index * 2 + 1]]));
  for (const required of ["--execute", "--boot-id", "--bridge-root", "--game-exe", "--evidence"]) {
    if (!options[required]) throw new Error(`Missing ${required}; no commands sent.`);
  }
  if (options["--execute"] !== "numeric-roundtrip") throw new Error("Explicit numeric-roundtrip mode required.");
  const executable = await readFile(options["--game-exe"]);
  const executableSha256 = createHash("sha256").update(executable).digest("hex").toUpperCase();
  if (executable.length !== 176196472 || executableSha256 !== "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853") throw new Error("Current executable identity mismatch.");
  const source = await readFile(new URL("../../integration/uue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua", import.meta.url), "utf8");
  const block = source.match(/local CAPABILITY_LIST = \{([\s\S]*?)\n\}/)?.[1];
  if (!block) throw new Error("Canonical native capabilities not found.");
  const expectedCapabilities = [...block.matchAll(/"([a-z:-]+)"/g)].map((match) => match[1]);
  const bridge = createPilotQaBridge(resolve(options["--bridge-root"]), { expectedCapabilities });
  const evidencePath = resolve(options["--evidence"]);
  await writeFile(evidencePath, JSON.stringify({ started: new Date().toISOString(), executableSha256 }), { flag: "wx" });
  const evidence = await runNumericRoundtrip({ bridge, bootId: options["--boot-id"] });
  Object.assign(evidence, { executableSha256, expectedCapabilities, nativeSourceSha256: createHash("sha256").update(source).digest("hex") });
  await writeFile(evidencePath, JSON.stringify(evidence, null, 2) + "\n");
  process.stdout.write(JSON.stringify({ passed: evidence.passed, evidencePath, error: evidence.error, cleanupErrors: evidence.cleanupErrors }) + "\n");
  process.exitCode = evidence.passed ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => { process.stderr.write(error.message + "\n"); process.exitCode = 1; });
}
