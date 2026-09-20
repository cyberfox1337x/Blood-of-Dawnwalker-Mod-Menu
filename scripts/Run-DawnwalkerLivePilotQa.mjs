import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function cyberfox1337x(moduleName) {
  return moduleName;
}

cyberfox1337x("dawnwalker_live_pilot_qa_runner");

const BRIDGE_PROTOCOL = "1";
const REQUIRED_BRIDGE_VERSION = "0.3.21-pilot";
const REQUIRED_BRIDGE_PHASE = "pilot";
const READY_FRESHNESS_SECONDS = 5;
const MAX_BRIDGE_FILE_BYTES = 64 * 1024;
const RESPONSE_POLL_MILLISECONDS = 50;
const RESPONSE_TIMEOUT_MILLISECONDS = 3_500;
const ACTIVE_SET_POLL_MILLISECONDS = 50;
const ACTIVE_SET_SETTLE_TIMEOUT_MILLISECONDS = 2_500;
const GAME_SPEED_COMPARISON_TOLERANCE = 0.000001;
const EXPECTED_DISABLED_HOOK_NAMES = Object.freeze([
  "LoadMap",
  "InitGameState",
  "BeginPlay",
  "EndPlay",
  "ULocalPlayerExec",
  "CallFunctionByNameWithArguments",
  "ProcessConsoleExec",
]);
const UE4SS_TIMESTAMP_PREFIX = /^\[(?:\d{4}-\d{2}-\d{2} )?\d{2}:\d{2}:\d{2}\.\d+\]\s*/;
const LOADER_FAILURE_MARKER = /\[(?:error|fatal)\]|\b(?:error|fatal|failed|failure|unhandled exception|access violation|stack overflow|crash(?:ed)?)\b/i;

export const EXPECTED_CAPABILITIES = Object.freeze([
  "player:infinite-health",
  "player:unlimited-stamina",
  "player:sprint-no-drain",
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

export const READ_ONLY_CAPABILITIES = Object.freeze([
  "player:player-info",
  "world:location-readback",
  "visuals:hud-visible",
  "world:game-speed",
  "player:trait-points",
  "player:blood-energy",
  "combat:rpg-difficulty",
  "combat:action-difficulty",
  "quests:journal-readback",
  "player:add-gold",
]);

export const SAFE_REVERSIBLE_CAPABILITIES = Object.freeze([
  "visuals:hud-visible",
  "world:game-speed",
  "player:add-gold",
  "combat:rpg-difficulty",
  "combat:action-difficulty",
]);

class PilotQaError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "PilotQaError";
    this.code = code;
  }
}

function errorRecord(error) {
  return {
    name: error instanceof Error ? error.name : "Error",
    code: error instanceof PilotQaError ? error.code : "unexpected-error",
    message: error instanceof Error ? error.message : String(error),
  };
}

function fail(code, message) {
  throw new PilotQaError(code, message);
}

function isExpectedPreModStartupNotice(message) {
  if (message === "ProcessLocalScriptFunction is not available, the following features will be unavailable:") {
    return true;
  }

  return EXPECTED_DISABLED_HOOK_NAMES.some((hookName) => (
    message === `[${hookName}] Tried to install hook but hooking is disabled for this function.`
    || message === `[${hookName}] Tried to install hook but function is unavailable.`
    || message === `[UE4SS.${hookName}.LuaModImpl] Failed to add hook, detour installation likely failed!`
    || message === `[.${hookName}.] Failed to add hook, detour installation likely failed!`
  ));
}

export function classifyUe4ssStartupLog(rawLogText) {
  if (typeof rawLogText !== "string") throw new TypeError("UE4SS startup log text must be a string.");

  const expectedNotices = [];
  const unexpectedFailures = [];
  for (const rawLine of rawLogText.split(/\r\n|\n|\r/)) {
    const message = rawLine.replace(UE4SS_TIMESTAMP_PREFIX, "");
    if (isExpectedPreModStartupNotice(message)) {
      expectedNotices.push(rawLine);
    } else if (LOADER_FAILURE_MARKER.test(message)) {
      unexpectedFailures.push(rawLine);
    }
  }

  return Object.freeze({
    rawLogText,
    expectedNotices: Object.freeze(expectedNotices),
    unexpectedFailures: Object.freeze(unexpectedFailures),
  });
}

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

function arraysHaveSameMembersExactly(actual, expected) {
  if (actual.length !== expected.length || new Set(actual).size !== actual.length) return false;
  const actualSorted = [...actual].sort();
  const expectedSorted = [...expected].sort();
  return actualSorted.every((item, index) => item === expectedSorted[index]);
}

export async function readStrictBridgeStatus(bridgeRoot, nowMilliseconds = Date.now()) {
  const readyPath = join(bridgeRoot, "ready.txt");
  try {
    const fileInfo = await stat(readyPath);
    if (!fileInfo.isFile() || fileInfo.size > MAX_BRIDGE_FILE_BYTES) {
      return { connected: false, capabilities: [], active: [], diagnostic: "ready.txt was missing or oversized" };
    }

    const fields = parseFields(await readFile(readyPath, "utf8"));
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
      ...(!connected ? { diagnostic: "ready.txt did not contain a fresh protocol-1 pilot session" } : {}),
    };
  } catch (error) {
    return {
      connected: false,
      capabilities: [],
      active: [],
      diagnostic: error instanceof Error ? error.message : "ready.txt could not be read",
    };
  }
}

async function readBoundedFields(targetPath) {
  try {
    const fileInfo = await stat(targetPath);
    if (!fileInfo.isFile() || fileInfo.size > MAX_BRIDGE_FILE_BYTES) return null;
    return parseFields(await readFile(targetPath, "utf8"));
  } catch {
    return null;
  }
}

async function writeAtomic(targetPath, contents) {
  const temporaryPath = `${targetPath}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temporaryPath, contents, { encoding: "utf8", flag: "wx" });
  await rm(targetPath, { force: true });
  await rename(temporaryPath, targetPath);
}

function safeProtocolValue(value) {
  if (value === undefined) return "";
  const serialized = typeof value === "boolean" ? (value ? "1" : "0") : String(value);
  if (serialized.length > 4096 || /[\r\n]/.test(serialized)) fail("invalid-command-value", "Invalid bridge command value.");
  return serialized;
}

export function createPilotQaBridge(bridgeRoot, { expectedCapabilities = EXPECTED_CAPABILITIES } = {}) {
  if (!Array.isArray(expectedCapabilities) || expectedCapabilities.length === 0
      || new Set(expectedCapabilities).size !== expectedCapabilities.length
      || expectedCapabilities.some((capability) => !EXPECTED_CAPABILITIES.includes(capability))) {
    throw new TypeError("Expected capabilities must be a nonempty unique subset of the audited pilot contract.");
  }
  const exactCapabilities = [...expectedCapabilities];
  const commandPath = join(bridgeRoot, "command.txt");
  const responsePath = join(bridgeRoot, "response.txt");
  let commandSequence = 0;
  let dispatchQueue = Promise.resolve();

  async function waitForResponse(capability, requestId, expectedBootId) {
    const deadline = Date.now() + RESPONSE_TIMEOUT_MILLISECONDS;
    while (Date.now() < deadline) {
      const response = await readBoundedFields(responsePath);
      if (response?.protocol === BRIDGE_PROTOCOL
        && response.boot_id === expectedBootId
        && response.request_id === requestId) {
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
      message: "The exact pilot session did not answer before the bounded timeout.",
    };
  }

  async function dispatchNow(command, expectedBootId) {
    if (!exactCapabilities.includes(command.capability)) {
      return {
        accepted: false,
        capability: command.capability,
        requestId: "unknown-capability",
        status: "rejected",
        message: "Rejected a capability outside the exact Dawnwalker pilot contract.",
      };
    }

    assertExactSession(await readStrictBridgeStatus(bridgeRoot), expectedBootId, exactCapabilities);
    await mkdir(bridgeRoot, { recursive: true });
    commandSequence += 1;
    const requestId = `${Date.now().toString(36)}-${commandSequence.toString(36)}`;
    await writeAtomic(commandPath, [
      `protocol=${BRIDGE_PROTOCOL}`,
      `boot_id=${expectedBootId}`,
      `request_id=${requestId}`,
      `capability=${command.capability}`,
      `value=${safeProtocolValue(command.value)}`,
      "",
    ].join("\n"));
    return waitForResponse(command.capability, requestId, expectedBootId);
  }

  function dispatch(command, expectedBootId) {
    const run = dispatchQueue.then(() => dispatchNow(command, expectedBootId));
    const safeRun = run.catch((error) => ({
      accepted: false,
      capability: command.capability,
      requestId: "failed-safe",
      status: "rejected",
      message: errorRecord(error).message,
    }));
    dispatchQueue = safeRun.then(() => undefined);
    return safeRun;
  }

  return Object.freeze({
    status: () => readStrictBridgeStatus(bridgeRoot),
    dispatch,
  });
}

function assertExactSession(status, expectedBootId, expectedCapabilities = EXPECTED_CAPABILITIES) {
  if (!status || status.connected !== true) {
    fail("bridge-disconnected", `The Dawnwalker bridge is not freshly connected${status?.diagnostic ? `: ${status.diagnostic}` : "."}`);
  }
  if (status.protocol !== BRIDGE_PROTOCOL) {
    fail("protocol-mismatch", `Expected bridge protocol ${BRIDGE_PROTOCOL}; received ${status.protocol ?? "missing"}.`);
  }
  if (status.bridgeVersion !== REQUIRED_BRIDGE_VERSION || status.phase !== REQUIRED_BRIDGE_PHASE) {
    fail(
      "pilot-identity-mismatch",
      `Expected ${REQUIRED_BRIDGE_VERSION} phase ${REQUIRED_BRIDGE_PHASE}; received ${status.bridgeVersion ?? "missing"} phase ${status.phase ?? "missing"}.`,
    );
  }
  if (!/^\d{9,12}-\d{6}$/.test(status.bootId ?? "")) {
    fail("invalid-boot-id", "The bridge boot ID is missing or does not match the pilot session format.");
  }
  if (expectedBootId && status.bootId !== expectedBootId) {
    fail("session-changed", `The bridge session changed from ${expectedBootId} to ${status.bootId}.`);
  }
  if (!arraysHaveSameMembersExactly(status.capabilities ?? [], expectedCapabilities)) {
    fail("capability-mismatch", "The bridge must advertise exactly the audited 16-capability pilot set.");
  }
  if (!Array.isArray(status.active) || status.active.some((item) => !EXPECTED_CAPABILITIES.includes(item))) {
    fail("invalid-active-set", "The bridge reported an invalid active-capability set.");
  }

  return {
    protocol: status.protocol,
    phase: status.phase,
    bootId: status.bootId,
    bridgeVersion: status.bridgeVersion,
    capabilities: [...status.capabilities],
    active: [...status.active],
  };
}

async function waitForInactiveSession(bridge, expectedBootId) {
  const deadline = Date.now() + ACTIVE_SET_SETTLE_TIMEOUT_MILLISECONDS;
  let latest = null;
  while (Date.now() < deadline) {
    latest = assertExactSession(await bridge.status(), expectedBootId);
    if (latest.active.length === 0) return latest;
    await new Promise((resolvePoll) => setTimeout(resolvePoll, ACTIVE_SET_POLL_MILLISECONDS));
  }
  fail(
    "active-set-not-settled",
    `The bridge active set did not settle empty after restoration: ${latest?.active.join(",") || "unknown"}.`,
  );
}

function parseBooleanReadback(value, label) {
  if (value === "1") return true;
  if (value === "0") return false;
  fail("invalid-readback", `${label} must return exactly 0 or 1.`);
}

function parseFiniteReadback(value, label, { minimum = -Infinity, maximum = Infinity, integer = false } = {}) {
  if (typeof value !== "string" || value.trim() === "") fail("invalid-readback", `${label} returned an empty readback.`);
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < minimum || parsed > maximum || (integer && !Number.isInteger(parsed))) {
    fail("invalid-readback", `${label} returned an invalid number: ${String(value)}.`);
  }
  return parsed;
}

function parseKeyValueReadback(value, label) {
  if (typeof value !== "string" || value.trim() === "") fail("invalid-readback", `${label} returned an empty readback.`);
  const fields = {};
  for (const entry of value.split(";")) {
    const separator = entry.indexOf("=");
    if (separator <= 0) fail("invalid-readback", `${label} returned a malformed field.`);
    const key = entry.slice(0, separator);
    if (!/^[a-z_]+$/.test(key) || Object.hasOwn(fields, key)) {
      fail("invalid-readback", `${label} returned an invalid or duplicate field.`);
    }
    fields[key] = entry.slice(separator + 1);
  }
  return fields;
}

function parsePlayerInfo(value) {
  const fields = parseKeyValueReadback(value, "Player Info");
  const alive = parseBooleanReadback(fields.alive, "Player Info alive");
  const healthPercent = parseFiniteReadback(fields.health_percent, "Player Info health", { minimum: 0, maximum: 100 });
  const staminaPercent = parseFiniteReadback(fields.stamina_percent, "Player Info stamina", { minimum: 0, maximum: 100 });
  const blood = parseFiniteReadback(fields.blood, "Player Info blood", { minimum: 0 });
  const bloodMax = parseFiniteReadback(fields.blood_max, "Player Info blood maximum", { minimum: Number.EPSILON });
  if (blood > bloodMax + 0.001) fail("invalid-readback", "Player Info blood exceeds its reported maximum.");

  const parsed = { alive, healthPercent, staminaPercent, blood, bloodMax };
  if (fields.level !== undefined) parsed.level = parseFiniteReadback(fields.level, "Player Info level", { minimum: 0, integer: true });
  if (fields.trait_points !== undefined) {
    parsed.traitPoints = parseFiniteReadback(fields.trait_points, "Player Info Trait Points", { minimum: 0, integer: true });
  }
  return parsed;
}

function parseLocation(value) {
  const fields = parseKeyValueReadback(value, "Location");
  return {
    x: parseFiniteReadback(fields.x, "Location X"),
    y: parseFiniteReadback(fields.y, "Location Y"),
    z: parseFiniteReadback(fields.z, "Location Z"),
  };
}

function hasControlCharacter(value) {
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
}

function parseQuestJournal(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 8_192) {
    fail("invalid-readback", "Quest Journal returned an empty or oversized snapshot.");
  }

  const headers = {};
  const quests = [];
  for (const record of value.split(";")) {
    if (!record) continue;
    const separator = record.indexOf("=");
    if (separator <= 0) fail("invalid-readback", "Quest Journal returned a malformed record.");
    const key = record.slice(0, separator);
    const recordValue = record.slice(separator + 1);
    if (["schema", "open_total", "returned", "truncated"].includes(key)) {
      if (Object.hasOwn(headers, key)) fail("invalid-readback", `Quest Journal repeated ${key}.`);
      headers[key] = recordValue;
      continue;
    }

    const fields = recordValue.split(",");
    if (key === "q") {
      if (fields.length !== 6) fail("invalid-readback", "Quest Journal returned a malformed quest record.");
      const index = parseFiniteReadback(fields[0], "Quest Journal quest index", { minimum: 0, maximum: 5, integer: true });
      const state = fields[1];
      const tracked = parseBooleanReadback(fields[2], "Quest Journal tracked state");
      let title;
      try { title = decodeURIComponent(fields[3]); } catch { fail("invalid-readback", "Quest Journal returned invalid title encoding."); }
      const objectiveCount = parseFiniteReadback(fields[4], "Quest Journal objective count", { minimum: 0, maximum: 1_000_000, integer: true });
      const objectivesTruncated = parseBooleanReadback(fields[5], "Quest Journal objective truncation");
      if (index !== quests.length || !["active", "success", "failure", "unknown"].includes(state)
        || typeof title !== "string" || title.length === 0 || title.length > 240 || hasControlCharacter(title)) {
        fail("invalid-readback", "Quest Journal returned an invalid quest record.");
      }
      quests.push({ title, state, tracked, objectiveCount, objectivesTruncated, objectives: [] });
      continue;
    }

    if (key === "o") {
      if (fields.length !== 6) fail("invalid-readback", "Quest Journal returned a malformed objective record.");
      const questIndex = parseFiniteReadback(fields[0], "Quest Journal objective quest index", { minimum: 0, maximum: 5, integer: true });
      const quest = quests[questIndex];
      const state = fields[1];
      let text;
      try { text = decodeURIComponent(fields[2]); } catch { fail("invalid-readback", "Quest Journal returned invalid objective encoding."); }
      const currentCount = parseFiniteReadback(fields[3], "Quest Journal objective progress", { minimum: 0, maximum: 1_000_000_000 });
      const maxCount = parseFiniteReadback(fields[4], "Quest Journal objective maximum", { minimum: 0, maximum: 1_000_000_000, integer: true });
      const optional = parseBooleanReadback(fields[5], "Quest Journal optional state");
      if (!quest || quest.objectives.length >= 3 || !["active", "success", "failure", "unknown"].includes(state)
        || typeof text !== "string" || text.length === 0 || text.length > 240 || hasControlCharacter(text)) {
        fail("invalid-readback", "Quest Journal returned an invalid objective record.");
      }
      quest.objectives.push({ text, state, currentCount, maxCount, optional });
      continue;
    }
    fail("invalid-readback", `Quest Journal returned an unknown ${key} record.`);
  }

  const openQuestCount = parseFiniteReadback(headers.open_total, "Quest Journal open count", { minimum: 0, maximum: 1_000_000, integer: true });
  const returnedQuestCount = parseFiniteReadback(headers.returned, "Quest Journal returned count", { minimum: 0, maximum: 6, integer: true });
  const truncated = parseBooleanReadback(headers.truncated, "Quest Journal truncation state");
  if (headers.schema !== "1" || returnedQuestCount !== quests.length || returnedQuestCount > openQuestCount
    || truncated !== (returnedQuestCount < openQuestCount)
    || quests.some((quest) => quest.objectives.length > quest.objectiveCount
      || quest.objectivesTruncated !== (quest.objectives.length < quest.objectiveCount))) {
    fail("invalid-readback", "Quest Journal snapshot counts were inconsistent.");
  }
  return { openQuestCount, returnedQuestCount, truncated, quests };
}

const READ_ONLY_QUERY_SPECS = Object.freeze([
  { capability: "player:player-info", label: "Player Info", parse: parsePlayerInfo },
  { capability: "world:location-readback", label: "Location", parse: parseLocation },
  { capability: "visuals:hud-visible", label: "HUD visibility", parse: (value) => parseBooleanReadback(value, "HUD visibility") },
  { capability: "world:game-speed", label: "Game Speed", parse: (value) => parseFiniteReadback(value, "Game Speed", { minimum: Number.EPSILON }) },
  { capability: "player:trait-points", label: "Trait Points", parse: (value) => parseFiniteReadback(value, "Trait Points", { minimum: 0, maximum: 9999, integer: true }) },
  { capability: "player:blood-energy", label: "Blood Energy", parse: (value) => parseFiniteReadback(value, "Blood Energy", { minimum: 0, maximum: 100 }) },
  { capability: "combat:rpg-difficulty", label: "RPG Difficulty", parse: (value) => parseFiniteReadback(value, "RPG Difficulty", { minimum: 0, maximum: 3, integer: true }) },
  { capability: "combat:action-difficulty", label: "Action Difficulty", parse: (value) => parseFiniteReadback(value, "Action Difficulty", { minimum: 0, maximum: 3, integer: true }) },
  { capability: "quests:journal-readback", label: "Quest Journal", parse: parseQuestJournal },
  { capability: "player:add-gold", label: "Gold balance", parse: (value) => parseFiniteReadback(value, "Gold balance", { minimum: 0, maximum: 2_147_483_647, integer: true }) },
]);

function createEvidence(suite, startedAt) {
  return {
    cyberfox1337x: "function(dawnwalker_live_pilot_qa_evidence)",
    schemaVersion: 1,
    evidenceClass: "pilot-only",
    productionProof: false,
    disclaimer: "Pilot-only diagnostic evidence. This file must never be used as Dawnwalker production or release proof.",
    suite,
    startedAt,
    finishedAt: null,
    passed: false,
    result: "failed",
    requirements: {
      protocol: BRIDGE_PROTOCOL,
      bridgeVersion: REQUIRED_BRIDGE_VERSION,
      phase: REQUIRED_BRIDGE_PHASE,
      exactCapabilityCount: EXPECTED_CAPABILITIES.length,
      exactCapabilities: [...EXPECTED_CAPABILITIES],
    },
    session: null,
    finalSession: null,
    readings: {},
    steps: [],
    restorations: [],
    error: null,
  };
}

async function performCommand({ bridge, capability, value, operation, session, evidence, now }) {
  const before = assertExactSession(await bridge.status(), session.bootId);
  const step = {
    sequence: evidence.steps.length + 1,
    operation,
    capability,
    ...(value !== undefined ? { value } : {}),
    startedAt: now().toISOString(),
    bootIdBefore: before.bootId,
    accepted: false,
    status: "not-dispatched",
    validation: "pending",
  };
  evidence.steps.push(step);

  try {
    const result = await bridge.dispatch({ capability, value }, session.bootId);
    const after = assertExactSession(await bridge.status(), session.bootId);
    Object.assign(step, {
      finishedAt: now().toISOString(),
      bootIdAfter: after.bootId,
      requestId: result?.requestId,
      accepted: result?.accepted === true,
      status: result?.status ?? "missing",
      message: result?.message ?? "",
      readback: result?.readback ?? "",
    });
    if (result?.accepted !== true || result.status !== "applied") {
      step.validation = "rejected";
      fail("command-rejected", `${capability} ${operation} was not accepted: ${result?.message ?? "no bridge response"}`);
    }
    return { result, step };
  } catch (error) {
    step.finishedAt ??= now().toISOString();
    step.validation = step.validation === "pending" ? "failed" : step.validation;
    step.error = errorRecord(error);
    throw error;
  }
}

function validateStepReadback(result, step, parser) {
  try {
    const parsed = parser(result.readback);
    step.parsedReadback = parsed;
    step.validation = "valid";
    return parsed;
  } catch (error) {
    step.validation = "invalid-readback";
    step.error = errorRecord(error);
    throw error;
  }
}

async function runReadOnlySuite(context) {
  const readings = {};
  for (const spec of READ_ONLY_QUERY_SPECS) {
    const { result, step } = await performCommand({
      ...context,
      capability: spec.capability,
      value: undefined,
      operation: "query",
    });
    readings[spec.capability] = validateStepReadback(result, step, spec.parse);
  }
  return readings;
}

function readbacksEqual(actual, expected, tolerance = 0) {
  if (typeof actual === "number" && typeof expected === "number") return Math.abs(actual - expected) <= tolerance;
  return actual === expected;
}

async function exerciseReversibleCapability({
  bridge,
  session,
  evidence,
  now,
  capability,
  baseline,
  probe,
  parser,
  tolerance = 0,
}) {
  let mutationError = null;
  let restorationError = null;
  const restoration = {
    capability,
    baseline,
    attempted: false,
    passed: false,
  };
  evidence.restorations.push(restoration);

  try {
    const mutation = await performCommand({ bridge, session, evidence, now, capability, value: probe, operation: "mutate" });
    const mutationReadback = validateStepReadback(mutation.result, mutation.step, parser);
    if (!readbacksEqual(mutationReadback, probe, tolerance)) {
      fail("mutation-mismatch", `${capability} did not report the requested reversible probe value.`);
    }

    const verification = await performCommand({ bridge, session, evidence, now, capability, value: undefined, operation: "verify-mutation" });
    const verifiedValue = validateStepReadback(verification.result, verification.step, parser);
    if (!readbacksEqual(verifiedValue, probe, tolerance)) {
      fail("mutation-query-mismatch", `${capability} query did not verify the reversible probe value.`);
    }
  } catch (error) {
    mutationError = error;
  } finally {
    restoration.attempted = true;
    try {
      const restore = await performCommand({ bridge, session, evidence, now, capability, value: baseline, operation: "restore" });
      const restoreReadback = validateStepReadback(restore.result, restore.step, parser);
      if (!readbacksEqual(restoreReadback, baseline, tolerance)) {
        fail("restore-response-mismatch", `${capability} restore response did not match the captured baseline.`);
      }

      const verification = await performCommand({ bridge, session, evidence, now, capability, value: undefined, operation: "verify-restore" });
      const verifiedValue = validateStepReadback(verification.result, verification.step, parser);
      if (!readbacksEqual(verifiedValue, baseline, tolerance)) {
        fail("restore-query-mismatch", `${capability} query did not verify the captured baseline after restoration.`);
      }
      restoration.passed = true;
      restoration.verifiedReadback = verifiedValue;
    } catch (error) {
      restorationError = error;
      restoration.error = errorRecord(error);
    }
  }

  if (restorationError) {
    const mutationContext = mutationError ? ` The probe also failed: ${errorRecord(mutationError).message}` : "";
    fail("restoration-failed", `${capability} baseline restoration could not be verified.${mutationContext} ${errorRecord(restorationError).message}`);
  }
  if (mutationError) throw mutationError;
}

async function exerciseAddGold(context, baseline) {
  let mutationAccepted = false;
  let mutationError = null;
  let restorationError = null;
  const parser = (value) => parseFiniteReadback(value, "Gold balance", {
    minimum: 0,
    maximum: 2_147_483_647,
    integer: true,
  });
  const restoration = {
    capability: "player:add-gold",
    baseline,
    probeDelta: 1,
    restoreDelta: -1,
    attempted: false,
    passed: false,
  };
  context.evidence.restorations.push(restoration);

  try {
    if (baseline >= 2_147_483_647) {
      fail("unsafe-gold-baseline", "Gold is already at the int32 maximum; a reversible +1 probe is unsafe.");
    }
    const mutation = await performCommand({
      ...context,
      capability: "player:add-gold",
      value: 1,
      operation: "mutate-delta",
    });
    mutationAccepted = true;
    const mutatedBalance = validateStepReadback(mutation.result, mutation.step, parser);
    if (mutatedBalance !== baseline + 1) {
      fail("mutation-mismatch", "Add Gold did not report the exact baseline + 1 balance.");
    }
    const verification = await performCommand({
      ...context,
      capability: "player:add-gold",
      value: undefined,
      operation: "verify-mutation",
    });
    if (validateStepReadback(verification.result, verification.step, parser) !== baseline + 1) {
      fail("mutation-query-mismatch", "Add Gold query did not verify the exact baseline + 1 balance.");
    }
  } catch (error) {
    mutationError = error;
  } finally {
    if (mutationAccepted) {
      restoration.attempted = true;
      try {
        const restore = await performCommand({
          ...context,
          capability: "player:add-gold",
          value: -1,
          operation: "restore-delta",
        });
        if (validateStepReadback(restore.result, restore.step, parser) !== baseline) {
          fail("restore-response-mismatch", "Add Gold -1 response did not restore the exact baseline.");
        }
        const verification = await performCommand({
          ...context,
          capability: "player:add-gold",
          value: undefined,
          operation: "verify-restore",
        });
        const restoredBalance = validateStepReadback(verification.result, verification.step, parser);
        if (restoredBalance !== baseline) {
          fail("restore-query-mismatch", "Add Gold query did not verify the exact baseline after -1 restoration.");
        }
        restoration.passed = true;
        restoration.verifiedReadback = restoredBalance;
      } catch (error) {
        restorationError = error;
        restoration.error = errorRecord(error);
      }
    }
  }

  if (restorationError) {
    const mutationContext = mutationError ? ` The +1 probe also failed: ${errorRecord(mutationError).message}` : "";
    fail("restoration-failed", `Add Gold -1 restoration could not be verified.${mutationContext} ${errorRecord(restorationError).message}`);
  }
  if (mutationError) throw mutationError;
}

function chooseGameSpeedProbe(baseline) {
  if (baseline < 0.1 || baseline > 3) {
    fail("unsafe-game-speed-baseline", "Game Speed is outside the bridge's reversible 0.1x to 3.0x setter range.");
  }
  const candidate = baseline <= 2.85 ? baseline + 0.1 : baseline - 0.1;
  const rounded = Number(candidate.toFixed(6));
  if (rounded < 0.1 || rounded > 3 || Math.abs(rounded - baseline) <= 0.01) {
    fail("unsafe-game-speed-probe", "A distinct reversible Game Speed probe could not be selected.");
  }
  return rounded;
}

function chooseDifficultyProbe(baseline, label) {
  if (!Number.isInteger(baseline) || baseline < 0 || baseline > 3) {
    fail("unsafe-difficulty-baseline", `${label} is outside the reflected Story through Nightmare range.`);
  }
  return (baseline + 1) % 4;
}

async function runSafeReversibleSuite(context, readings) {
  if (readings["player:player-info"].alive !== true) {
    fail("player-not-playable", "Safe reversible mutations require a loaded, living Dawnwalker player pawn.");
  }

  const preMutationStatus = assertExactSession(await context.bridge.status(), context.session.bootId);
  if (preMutationStatus.active.length !== 0) {
    fail("bridge-already-active", "Safe reversible QA requires an empty bridge active set before its first mutation.");
  }

  const hudBaseline = readings["visuals:hud-visible"];
  const speedBaseline = readings["world:game-speed"];
  const speedProbe = chooseGameSpeedProbe(speedBaseline);
  const rpgDifficultyBaseline = readings["combat:rpg-difficulty"];
  const actionDifficultyBaseline = readings["combat:action-difficulty"];
  await exerciseReversibleCapability({
    ...context,
    capability: "visuals:hud-visible",
    baseline: hudBaseline,
    probe: !hudBaseline,
    parser: (value) => parseBooleanReadback(value, "HUD visibility"),
  });
  await exerciseReversibleCapability({
    ...context,
    capability: "world:game-speed",
    baseline: speedBaseline,
    probe: speedProbe,
    parser: (value) => parseFiniteReadback(value, "Game Speed", { minimum: Number.EPSILON }),
    tolerance: GAME_SPEED_COMPARISON_TOLERANCE,
  });
  await exerciseReversibleCapability({
    ...context,
    capability: "combat:rpg-difficulty",
    baseline: rpgDifficultyBaseline,
    probe: chooseDifficultyProbe(rpgDifficultyBaseline, "RPG Difficulty"),
    parser: (value) => parseFiniteReadback(value, "RPG Difficulty", { minimum: 0, maximum: 3, integer: true }),
  });
  await exerciseReversibleCapability({
    ...context,
    capability: "combat:action-difficulty",
    baseline: actionDifficultyBaseline,
    probe: chooseDifficultyProbe(actionDifficultyBaseline, "Action Difficulty"),
    parser: (value) => parseFiniteReadback(value, "Action Difficulty", { minimum: 0, maximum: 3, integer: true }),
  });
  await exerciseAddGold(context, readings["player:add-gold"]);
}

export async function runPilotQa({ bridge, suite, expectedBootId, now = () => new Date() }) {
  const startedAt = now().toISOString();
  const evidence = createEvidence(suite, startedAt);
  try {
    if (suite !== "read-only" && suite !== "safe-reversible") {
      fail("invalid-suite", "Choose exactly one suite: read-only or safe-reversible.");
    }

    const session = assertExactSession(await bridge.status(), expectedBootId);
    evidence.session = session;
    if (suite === "safe-reversible" && session.active.length !== 0) {
      fail("bridge-already-active", "Safe reversible QA requires an empty bridge active set.");
    }

    const context = { bridge, session, evidence, now };
    const readings = await runReadOnlySuite(context);
    evidence.readings = readings;
    if (suite === "safe-reversible") await runSafeReversibleSuite(context, readings);

    evidence.finalSession = suite === "safe-reversible"
      ? await waitForInactiveSession(bridge, session.bootId)
      : assertExactSession(await bridge.status(), session.bootId);
    evidence.passed = true;
    evidence.result = "passed";
  } catch (error) {
    evidence.error = errorRecord(error);
  } finally {
    evidence.finishedAt = now().toISOString();
  }
  return evidence;
}

function timestampForFilename(isoTimestamp) {
  return isoTimestamp.replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

export async function writePilotEvidence(evidence, evidenceDirectory) {
  await mkdir(evidenceDirectory, { recursive: true });
  const timestamp = timestampForFilename(evidence.startedAt);
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const suffix = attempt === 0 ? "" : `-${attempt}`;
    const targetPath = join(evidenceDirectory, `dawnwalker-live-pilot-qa-${timestamp}${suffix}.json`);
    try {
      await writeFile(targetPath, `${JSON.stringify(evidence, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
      return targetPath;
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
    }
  }
  fail("evidence-name-exhausted", "Unable to allocate a unique timestamped pilot evidence filename.");
}

export function parseCliArguments(argumentsList) {
  const options = {
    suite: null,
    bridgeRoot: join(tmpdir(), "DawnwalkerModMenuBridge"),
    evidenceDirectory: resolve(fileURLToPath(new URL("..", import.meta.url)), "qa", "pilot-evidence"),
    expectedBootId: undefined,
    help: false,
  };
  const valueOptions = new Map([
    ["--bridge-root", "bridgeRoot"],
    ["--evidence-dir", "evidenceDirectory"],
    ["--expected-boot-id", "expectedBootId"],
  ]);

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else if (argument === "--read-only" || argument === "--safe-reversible") {
      const suite = argument.slice(2);
      if (options.suite && options.suite !== suite) fail("ambiguous-suite", "Choose only one QA suite.");
      options.suite = suite;
    } else if (valueOptions.has(argument)) {
      const value = argumentsList[index + 1];
      if (!value || value.startsWith("--")) fail("missing-argument-value", `${argument} requires a value.`);
      options[valueOptions.get(argument)] = value;
      index += 1;
    } else {
      fail("unknown-argument", `Unknown argument: ${argument}`);
    }
  }

  if (!options.help && !options.suite) fail("missing-suite", "Choose --read-only or --safe-reversible.");
  return options;
}

function usage() {
  return [
    "Dawnwalker 0.3.21 live-pilot QA (pilot evidence only; never production proof)",
    "",
    "Usage:",
    "  node scripts/Run-DawnwalkerLivePilotQa.mjs --read-only [options]",
    "  node scripts/Run-DawnwalkerLivePilotQa.mjs --safe-reversible [options]",
    "",
    "Options:",
    "  --bridge-root <path>       Override the local bridge directory.",
    "  --evidence-dir <path>      Override the pilot evidence output directory.",
    "  --expected-boot-id <id>    Require a specific already-observed bridge boot ID.",
    "  --help                     Show this help.",
    "",
    "The safe-reversible suite mutates only HUD visibility, game speed, each Combat difficulty axis, and a +1/-1 Gold delta; every baseline must be restored and verified.",
    "",
    "Add Level and Unblock Trait are one-way capabilities and are exercised by their own",
    "dedicated live probe (scripts/Run-DawnwalkerAddLevelUnblockLiveProbe.mjs), never by the",
    "safe-reversible suite, because they have no in-memory inverse and require the closed-game",
    "save-backup restoration procedure.",
  ].join("\n");
}

async function runCli() {
  let options;
  try {
    options = parseCliArguments(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${errorRecord(error).message}\n\n${usage()}\n`);
    process.exitCode = 2;
    return;
  }
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  let evidence;
  try {
    const bridge = createPilotQaBridge(options.bridgeRoot);
    evidence = await runPilotQa({
      bridge,
      suite: options.suite,
      expectedBootId: options.expectedBootId,
    });
  } catch (error) {
    evidence = createEvidence(options.suite, new Date().toISOString());
    evidence.finishedAt = new Date().toISOString();
    evidence.error = errorRecord(error);
  }

  try {
    const evidencePath = await writePilotEvidence(evidence, resolve(options.evidenceDirectory));
    process.stdout.write(`${JSON.stringify({
      evidenceClass: evidence.evidenceClass,
      productionProof: false,
      suite: evidence.suite,
      passed: evidence.passed,
      evidencePath,
      error: evidence.error,
    }, null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`Pilot QA evidence could not be written: ${errorRecord(error).message}\n`);
    process.exitCode = 3;
    return;
  }
  process.exitCode = evidence.passed ? 0 : 2;
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : "";
if (invokedPath === resolve(fileURLToPath(import.meta.url))) await runCli();
