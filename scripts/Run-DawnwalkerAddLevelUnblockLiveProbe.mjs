import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const cyberfox1337x = () => "function(dawnwalker_add_level_unblock_trait_live_qa)";
void cyberfox1337x;

const BRIDGE_PROTOCOL = "1";
const REQUIRED_BRIDGE_VERSION = "0.3.21-pilot";
const REQUIRED_BRIDGE_PHASE = "pilot";
const READY_FRESHNESS_SECONDS = 5;
const MAX_FILE_BYTES = 64 * 1024;
const POLL_MILLISECONDS = 50;
const TIMEOUT_MILLISECONDS = 5_000;
const ACTIVE_SET_POLL_MILLISECONDS = 50;
const ACTIVE_SET_SETTLE_TIMEOUT_MILLISECONDS = 2_500;

const EXPECTED_CAPABILITIES = Object.freeze([
  "player:infinite-health",
  "player:unlimited-stamina",
  "player:blood-energy",
  "player:god-mode",
  "player:player-info",
  "player:trait-points",
  "player:add-gold",
  "inventory:add-item",
  "player:add-level",
  "player:unblock-trait",
  "combat:infinite-blood-energy",
  "combat:rpg-difficulty",
  "combat:action-difficulty",
  "quests:journal-readback",
  "teleport:save-location",
  "teleport:teleport-saved-location",
  "visuals:hud-visible",
  "world:game-speed",
  "world:location-readback",
]);

function parseFields(contents) {
  const fields = {};
  for (const line of contents.split(/\r?\n/)) {
    const separator = line.indexOf("=");
    if (separator <= 0) continue;
    const key = line.slice(0, separator);
    if (/^[a-z_]+$/.test(key)) fields[key] = line.slice(separator + 1);
  }
  return fields;
}

function splitList(value) {
  if (!value) return [];
  return value.split(",").map((item) => item.trim()).filter(Boolean);
}

async function readFields(filePath) {
  const file = await stat(filePath);
  if (!file.isFile() || file.size > MAX_FILE_BYTES) throw new Error(`Invalid bridge file: ${filePath}`);
  return parseFields(await readFile(filePath, "utf8"));
}

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

async function readStrictReady(bridgeRoot, nowMilliseconds = Date.now()) {
  const fields = await readFields(join(bridgeRoot, "ready.txt"));
  const heartbeat = Number(fields.heartbeat);
  const heartbeatFresh = Number.isFinite(heartbeat)
    && Math.abs(nowMilliseconds / 1000 - heartbeat) <= READY_FRESHNESS_SECONDS;
  const bootIdValid = /^\d{9,12}-\d{6}$/.test(fields.boot_id ?? "");
  const connected = fields.protocol === BRIDGE_PROTOCOL && heartbeatFresh && bootIdValid;
  return {
    connected,
    protocol: fields.protocol,
    phase: fields.phase,
    bootId: fields.boot_id,
    bridgeVersion: fields.version,
    heartbeat,
    capabilities: splitList(fields.capabilities),
    active: splitList(fields.active),
    diagnostic: connected ? undefined : "ready.txt did not contain a fresh protocol-1 0.3.21-pilot session",
  };
}

function assertExactSession(status) {
  if (!status.connected) fail(`bridge-disconnected: ${status.diagnostic ?? "no diagnostic"}`);
  if (status.protocol !== BRIDGE_PROTOCOL) fail(`protocol-mismatch: expected ${BRIDGE_PROTOCOL}; got ${status.protocol}`);
  if (status.bridgeVersion !== REQUIRED_BRIDGE_VERSION || status.phase !== REQUIRED_BRIDGE_PHASE) {
    fail(`pilot-identity-mismatch: expected ${REQUIRED_BRIDGE_VERSION} phase ${REQUIRED_BRIDGE_PHASE}; got ${status.bridgeVersion} phase ${status.phase}`);
  }
  if (!/^\d{9,12}-\d{6}$/.test(status.bootId ?? "")) fail("invalid-boot-id: missing or malformed boot id");
  const sameMembers = (actual, expected) => actual.length === expected.length
    && [...actual].sort().join(",") === [...expected].sort().join(",");
  if (!sameMembers(status.capabilities ?? [], EXPECTED_CAPABILITIES)) {
    fail(`capability-mismatch: expected exactly the 19 audited pilot capabilities; got ${(status.capabilities ?? []).join(",")}`);
  }
  if ((status.active ?? []).some((item) => !EXPECTED_CAPABILITIES.includes(item))) {
    fail(`invalid-active-set: ${status.active.join(",")}`);
  }
  return status;
}

function fail(message) {
  const error = new Error(message);
  error.probeFailed = true;
  throw error;
}

async function dispatch({ bridgeRoot, status, capability, value, requestId }) {
  await writeAtomic(join(bridgeRoot, "command.txt"), [
    `protocol=${BRIDGE_PROTOCOL}`,
    `boot_id=${status.bootId}`,
    `request_id=${requestId}`,
    `capability=${capability}`,
    `value=${value}`,
    "",
  ].join("\n"));

  const deadline = Date.now() + TIMEOUT_MILLISECONDS;
  while (Date.now() < deadline) {
    try {
      const response = await readFields(join(bridgeRoot, "response.txt"));
      if (response.protocol === BRIDGE_PROTOCOL
        && response.boot_id === status.bootId
        && response.request_id === requestId) {
        return response;
      }
    } catch {
      // The bridge response can be momentarily absent during its atomic replacement.
    }
    await new Promise((resolvePoll) => setTimeout(resolvePoll, POLL_MILLISECONDS));
  }
  fail(`timeout: the exact pilot session did not answer ${capability} before the bounded timeout`);
}

function parsePlayerInfoReadback(readback) {
  const fields = {};
  for (const entry of readback.split(";")) {
    const separator = entry.indexOf("=");
    if (separator <= 0) fail(`player-info readback malformed: ${readback}`);
    fields[entry.slice(0, separator)] = entry.slice(separator + 1);
  }
  if (fields.alive !== "1") fail(`player-info reported alive=${fields.alive}; a live pawn is required`);
  const level = Number(fields.level);
  if (!Number.isFinite(level) || !Number.isInteger(level) || level < 0) {
    fail(`player-info level readback invalid: ${fields.level}`);
  }
  const traitPoints = Number(fields.trait_points);
  if (!Number.isFinite(traitPoints) || !Number.isInteger(traitPoints) || traitPoints < 0) {
    fail(`player-info trait_points readback invalid: ${fields.trait_points}`);
  }
  return { level, traitPoints, raw: readback };
}

function parseLevelReadback(readback, label) {
  const level = Number(readback);
  if (!Number.isFinite(level) || !Number.isInteger(level) || level < 0) {
    fail(`${label} level readback invalid: ${readback}`);
  }
  return level;
}

async function waitForInactiveSession(bridgeRoot, status) {
  const deadline = Date.now() + ACTIVE_SET_SETTLE_TIMEOUT_MILLISECONDS;
  let latest = status;
  while (Date.now() < deadline) {
    latest = assertExactSession(await readStrictReady(bridgeRoot));
    if (latest.active.length === 0) return latest;
    await new Promise((resolvePoll) => setTimeout(resolvePoll, ACTIVE_SET_POLL_MILLISECONDS));
  }
  fail(`active-set-not-settled: ${latest.active.join(",") || "unknown"}`);
}

function timestampForFilename(isoTimestamp) {
  return isoTimestamp.replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

async function writeEvidence(evidence, evidenceDirectory) {
  await mkdir(evidenceDirectory, { recursive: true });
  const timestamp = timestampForFilename(evidence.startedAt);
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const suffix = attempt === 0 ? "" : `-${attempt}`;
    const targetPath = join(evidenceDirectory, `dawnwalker-add-level-unblock-trait-live-${timestamp}${suffix}.json`);
    try {
      await writeFile(targetPath, `${JSON.stringify(evidence, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
      return targetPath;
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
    }
  }
  fail("evidence-name-exhausted: unable to allocate a unique evidence filename");
}

function parseCliArguments(argumentsList) {
  const options = {
    bridgeRoot: join(process.env.TEMP ?? "/tmp", "DawnwalkerModMenuBridge"),
    evidenceDirectory: resolve(fileURLToPath(new URL("..", import.meta.url)), "qa", "pilot-evidence"),
    traitId: null,
    traitUnblockedBefore: null,
    saveSafety: null,
    help: false,
  };
  const valueOptions = new Map([
    ["--bridge-root", "bridgeRoot"],
    ["--evidence-dir", "evidenceDirectory"],
    ["--trait-id", "traitId"],
    ["--trait-unblocked-before", "traitUnblockedBefore"],
    ["--save-safety", "saveSafety"],
  ]);
  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else if (valueOptions.has(argument)) {
      const value = argumentsList[index + 1];
      if (!value || value.startsWith("--")) fail(`missing-argument-value: ${argument} requires a value`);
      options[valueOptions.get(argument)] = value;
      index += 1;
    } else {
      fail(`unknown-argument: ${argument}`);
    }
  }
  if (!options.help) {
    if (!options.traitId) fail("missing-argument: --trait-id <Skill_ID> is required");
    if (options.traitUnblockedBefore !== null && !/^\d+$/.test(options.traitUnblockedBefore)) {
      fail("invalid-argument: --trait-unblocked-before must be a whole number");
    }
  }
  return options;
}

async function main() {
  const options = parseCliArguments(process.argv.slice(2));
  if (options.help) {
    process.stdout.write([
      "Dawnwalker 0.3.21 Add Level + Unblock Trait live probe (one-way; closed-game save backup is the only recovery)",
      "",
      "Usage:",
      "  node scripts/Run-DawnwalkerAddLevelUnblockLiveProbe.mjs \\",
      "    --trait-id <Skill_ID> [--trait-unblocked-before <N>] [options]",
      "",
      "Options:",
      "  --bridge-root <path>         Override the local bridge directory.",
      "  --evidence-dir <path>        Override the pilot evidence output directory.",
      "  --save-safety <path>         Embed a saveSafety JSON object produced after restore verification.",
      "  --help                       Show this help.",
      "",
    ].join("\n"));
    return;
  }

  const startedAt = new Date().toISOString();
  const evidence = {
    cyberfox1337x: cyberfox1337x(),
    schemaVersion: 1,
    evidenceClass: "pilot-only",
    productionProof: false,
    disclaimer: "Pilot-only diagnostic evidence. This file must never be used as Dawnwalker production or release proof.",
    scope: "offline-single-player Add Level + Unblock Trait one-way probe on the FName-safe 0.3.21-pilot bridge",
    startedAt,
    finishedAt: null,
    passed: false,
    result: "failed",
    bridge: null,
    roster: {
      traitId: options.traitId,
      traitUnblockedBefore: options.traitUnblockedBefore === null ? null : Number(options.traitUnblockedBefore),
    },
    probe: null,
    saveSafety: null,
    error: null,
  };

  try {
    const status = assertExactSession(await readStrictReady(options.bridgeRoot));
    evidence.bridge = {
      protocol: status.protocol,
      phase: status.phase,
      bootId: status.bootId,
      version: status.bridgeVersion,
      heartbeat: status.heartbeat,
      capabilities: [...status.capabilities],
      active: [...status.active],
      activeEmpty: status.active.length === 0,
    };
    if (status.active.length !== 0) fail("bridge-already-active: the probe requires an empty active set");

    const steps = [];
    const recordStep = (capability, value, operation) => async () => {
      const requestId = `${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
      const before = assertExactSession(await readStrictReady(options.bridgeRoot));
      const step = {
        sequence: steps.length + 1,
        operation,
        capability,
        value,
        requestId,
        startedAt: new Date().toISOString(),
        bootIdBefore: before.bootId,
      };
      const response = await dispatch({ bridgeRoot: options.bridgeRoot, status, capability, value, requestId });
      const after = assertExactSession(await readStrictReady(options.bridgeRoot));
      Object.assign(step, {
        finishedAt: new Date().toISOString(),
        bootIdAfter: after.bootId,
        accepted: response.accepted === "1",
        status: response.status,
        message: response.message ?? "",
        readback: response.readback ?? "",
      });
      steps.push(step);
      if (response.accepted !== "1" || response.status !== "applied") {
        fail(`${capability} ${operation} was rejected: ${response.message ?? "no bridge response"}`);
      }
      return step;
    };

    const playerInfoStep = await recordStep("player:player-info", "", "query")();
    const playerInfo = parsePlayerInfoReadback(playerInfoStep.readback);

    const levelQueryStep = await recordStep("player:add-level", "", "query-baseline")();
    const baselineLevel = parseLevelReadback(levelQueryStep.readback, "Add Level baseline");
    if (baselineLevel !== playerInfo.level) {
      fail(`baseline mismatch: player-info level ${playerInfo.level} != add-level readback ${baselineLevel}`);
    }

    const targetLevel = baselineLevel + 1;
    const mutateStep = await recordStep("player:add-level", String(targetLevel), "mutate-one-way")();
    const mutatedLevel = parseLevelReadback(mutateStep.readback, "Add Level mutation");
    if (mutatedLevel !== targetLevel) {
      fail(`Add Level mutation mismatch: expected ${targetLevel}, got ${mutatedLevel}`);
    }

    const verifyLevelStep = await recordStep("player:add-level", "", "verify-mutation")();
    const verifiedLevel = parseLevelReadback(verifyLevelStep.readback, "Add Level verification");
    if (verifiedLevel !== targetLevel) {
      fail(`Add Level verification mismatch: expected ${targetLevel}, got ${verifiedLevel}`);
    }

    const unblockValue = `${options.traitId}|1`;
    const unblockStep = await recordStep("player:unblock-trait", unblockValue, "mutate-one-way")();
    const unblockedLevel = parseLevelReadback(unblockStep.readback, "Unblock Trait mutation");
    if (unblockedLevel < 1) fail(`Unblock Trait readback invalid: ${unblockStep.readback}`);
    if (options.traitUnblockedBefore !== null && unblockedLevel <= Number(options.traitUnblockedBefore)) {
      fail(`Unblock Trait did not advance: before=${options.traitUnblockedBefore}, after=${unblockedLevel}`);
    }

    const repeatStep = await recordStep("player:unblock-trait", unblockValue, "verify-mutation")();
    const repeatLevel = parseLevelReadback(repeatStep.readback, "Unblock Trait repeat");
    if (repeatLevel < unblockedLevel) {
      fail(`Unblock Trait regressed on repeat: ${unblockedLevel} -> ${repeatLevel}`);
    }

    const finalSession = await waitForInactiveSession(options.bridgeRoot, status);
    evidence.probe = {
      playerInfo,
      baselineLevel,
      targetLevel,
      traitId: options.traitId,
      traitUnblockedBefore: options.traitUnblockedBefore === null ? null : Number(options.traitUnblockedBefore),
      unblockedLevel,
      repeatLevel,
      finalActiveCapabilities: [...finalSession.active],
      passed: true,
    };
    evidence.passed = true;
    evidence.result = "passed";
    evidence.steps = steps;
  } catch (error) {
    evidence.error = {
      name: error instanceof Error ? error.name : "Error",
      message: error instanceof Error ? error.message : String(error),
    };
  } finally {
    evidence.finishedAt = new Date().toISOString();
    if (options.saveSafety) {
      try {
        evidence.saveSafety = JSON.parse(await readFile(options.saveSafety, "utf8"));
      } catch (error) {
        evidence.error = {
          name: error instanceof Error ? error.name : "Error",
          message: `saveSafety could not be embedded: ${error instanceof Error ? error.message : String(error)}`,
        };
        evidence.passed = false;
        evidence.result = "failed";
      }
    }
  }

  const evidencePath = await writeEvidence(evidence, options.evidenceDirectory);
  process.stdout.write(`${JSON.stringify({
    evidenceClass: evidence.evidenceClass,
    productionProof: false,
    passed: evidence.passed,
    evidencePath,
    bootId: evidence.bridge?.bootId ?? null,
    baselineLevel: evidence.probe?.baselineLevel ?? null,
    targetLevel: evidence.probe?.targetLevel ?? null,
    unblockedLevel: evidence.probe?.unblockedLevel ?? null,
    error: evidence.error,
  }, null, 2)}\n`);
  process.exitCode = evidence.passed ? 0 : 2;
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}