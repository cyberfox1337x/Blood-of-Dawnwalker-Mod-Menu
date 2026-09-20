import { mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, it } from "vitest";
import { RUNTIME_CAPABILITIES } from "../electron/runtimeCapabilities.ts";
import {
  EXPECTED_CAPABILITIES,
  classifyUe4ssStartupLog,
  createPilotQaBridge,
  readStrictBridgeStatus,
  runPilotQa,
  writePilotEvidence,
} from "./Run-DawnwalkerLivePilotQa.mjs";

function cyberfox1337x(moduleName) {
  return moduleName;
}

cyberfox1337x("dawnwalker_live_pilot_qa_tests");

const temporaryRoots = [];
const TEST_BOOT_ID = "1788390000-123456";

function parseFields(contents) {
  const fields = {};
  for (const line of contents.split(/\r?\n/)) {
    const separator = line.indexOf("=");
    if (separator > 0) fields[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return fields;
}

function writeReady(root, { version = "0.3.21-pilot", phase = "pilot", capabilities = EXPECTED_CAPABILITIES, active = [] } = {}) {
  writeFileSync(join(root, "ready.txt"), [
    "protocol=1",
    `boot_id=${TEST_BOOT_ID}`,
    `version=${version}`,
    `heartbeat=${Date.now() / 1000}`,
    `phase=${phase}`,
    `capabilities=${capabilities.join(",")}`,
    `active=${active.join(",")}`,
    "",
  ].join("\n"));
}

function createFakePilot(options = {}) {
  const root = mkdtempSync(join(tmpdir(), "dawnwalker-live-pilot-qa-test-"));
  temporaryRoots.push(root);
  writeReady(root, options.ready);

  const state = {
    alive: options.alive ?? true,
    hudVisible: options.hudVisible ?? true,
    gameSpeed: options.gameSpeed ?? 1,
    traitPoints: options.traitPoints ?? 4,
    bloodEnergy: options.bloodEnergy ?? 72.5,
    gold: options.gold ?? 250,
    rpgDifficulty: options.rpgDifficulty ?? 1,
    actionDifficulty: options.actionDifficulty ?? 2,
  };
  const commands = [];
  const handledRequestIds = new Set();
  let forceWrongHudVerification = options.forceWrongHudVerification ?? false;
  let safeRoundTripComplete = false;
  let staleActivePollsRemaining = options.staleActiveAfterRestorePolls ?? 0;

  function responseFor(command) {
    const queryOnly = command.value === "";
    if (command.capability === "player:player-info" && queryOnly) {
      return `alive=${state.alive ? "1" : "0"};health_percent=91.000000;stamina_percent=82.000000;blood=14.500000;blood_max=20.000000;level=6;trait_points=${state.traitPoints}`;
    }
    if (command.capability === "world:location-readback" && queryOnly) return "x=125.500000;y=-42.250000;z=8.000000";
    if (command.capability === "visuals:hud-visible") {
      if (!queryOnly) state.hudVisible = command.value === "1";
      if (queryOnly && forceWrongHudVerification && state.hudVisible === false) {
        forceWrongHudVerification = false;
        return "1";
      }
      return state.hudVisible ? "1" : "0";
    }
    if (command.capability === "world:game-speed") {
      if (queryOnly && options.invalidGameSpeedReadback) return options.invalidGameSpeedReadback;
      if (!queryOnly) state.gameSpeed = Number(command.value);
      if (queryOnly && commands.filter((item) => item.capability === "world:game-speed" && item.value !== "").length >= 2) {
        safeRoundTripComplete = true;
      }
      return state.gameSpeed.toFixed(6);
    }
    if (command.capability === "player:trait-points" && queryOnly) return String(state.traitPoints);
    if (command.capability === "player:blood-energy" && queryOnly) return state.bloodEnergy.toFixed(6);
    if (command.capability === "quests:journal-readback" && queryOnly) {
      return "schema=1;open_total=1;returned=1;truncated=0;q=0,active,1,A Quiet Night,1,0;o=0,active,Follow the trail,1.000000,3,0";
    }
    if (command.capability === "player:add-gold") {
      if (!queryOnly) state.gold += Number(command.value);
      return String(state.gold);
    }
    if (command.capability === "combat:rpg-difficulty") {
      if (!queryOnly) state.rpgDifficulty = Number(command.value);
      return String(state.rpgDifficulty);
    }
    if (command.capability === "combat:action-difficulty") {
      if (!queryOnly) state.actionDifficulty = Number(command.value);
      return String(state.actionDifficulty);
    }
    return null;
  }

  const responder = setInterval(() => {
    try {
      const command = parseFields(readFileSync(join(root, "command.txt"), "utf8"));
      if (!command.request_id || handledRequestIds.has(command.request_id)) return;
      handledRequestIds.add(command.request_id);
      commands.push(command);
      const readback = responseFor(command);
      const accepted = readback !== null;
      const responsePath = join(root, "response.txt");
      const temporaryResponsePath = join(root, "response.test.tmp");
      writeFileSync(temporaryResponsePath, [
        "protocol=1",
        `boot_id=${TEST_BOOT_ID}`,
        `request_id=${command.request_id}`,
        `accepted=${accepted ? "1" : "0"}`,
        `status=${accepted ? "applied" : "rejected"}`,
        `message=${accepted ? "Fake pilot response." : "Unsafe or unknown fake command."}`,
        `readback=${readback ?? ""}`,
        "",
      ].join("\n"));
      rmSync(responsePath, { force: true });
      renameSync(temporaryResponsePath, responsePath);
    } catch {
      // The atomic command file does not exist before the first dispatch.
    }
  }, 5);

  const transport = createPilotQaBridge(root);
  return {
    root,
    state,
    commands,
    bridge: {
      dispatch: transport.dispatch,
      status: async () => {
        const status = await readStrictBridgeStatus(root);
        if (safeRoundTripComplete && staleActivePollsRemaining > 0) {
          staleActivePollsRemaining -= 1;
          return { ...status, active: ["visuals:hud-visible"] };
        }
        return status;
      },
    },
    stop() {
      clearInterval(responder);
    },
  };
}

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("Dawnwalker live-pilot QA runner", () => {
  it("classifies only the observed pre-mod UE4SS startup notices as expected and preserves their raw text", () => {
    const disabledHookNotices = [
      ["LoadMap", "hooking is disabled for this function", "UE4SS.LoadMap.LuaModImpl"],
      ["InitGameState", "hooking is disabled for this function", "UE4SS.InitGameState.LuaModImpl"],
      ["BeginPlay", "hooking is disabled for this function", "UE4SS.BeginPlay.LuaModImpl"],
      ["EndPlay", "hooking is disabled for this function", "UE4SS.EndPlay.LuaModImpl"],
      ["ULocalPlayerExec", "hooking is disabled for this function", ".ULocalPlayerExec."],
      ["CallFunctionByNameWithArguments", "hooking is disabled for this function", ".CallFunctionByNameWithArguments."],
      ["ProcessConsoleExec", "function is unavailable", ".ProcessConsoleExec."],
    ].flatMap(([hookName, unavailableReason, failedHookLabel]) => [
      `[2026-09-02 22:09:47.4058550] [${hookName}] Tried to install hook but ${unavailableReason}.`,
      `[2026-09-02 22:09:47.4069851] [${failedHookLabel}] Failed to add hook, detour installation likely failed!`,
    ]);
    const expectedNotices = [
      "[2026-09-02 22:09:47.4044181] ProcessLocalScriptFunction is not available, the following features will be unavailable:",
      ...disabledHookNotices,
    ];
    const rawLogText = [
      ...expectedNotices,
      "[2026-09-02 22:09:47.4330943] [Lua] [DawnwalkerModBridge] loaded bridge pilot version 0.3.1-pilot",
    ].join("\r\n");

    const classification = classifyUe4ssStartupLog(rawLogText);
    expect(classification.rawLogText).toBe(rawLogText);
    expect(classification.expectedNotices).toEqual(expectedNotices);
    expect(classification.unexpectedFailures).toEqual([]);
  });

  it("recognizes the time-only timestamp form from the captured UE4SS startup notices", () => {
    const lines = [
      "[22:09:47.4044564] ProcessLocalScriptFunction is not available, the following features will be unavailable:",
      "[22:09:47.4058550] [LoadMap] Tried to install hook but hooking is disabled for this function.",
      "[22:09:47.4060472] [UE4SS.LoadMap.LuaModImpl] Failed to add hook, detour installation likely failed!",
    ];

    const classification = classifyUe4ssStartupLog(lines.join("\n"));
    expect(classification.expectedNotices).toEqual(lines);
    expect(classification.unexpectedFailures).toEqual([]);
  });

  it("keeps bridge failures, broad errors, and non-allowlisted hook failures actionable", () => {
    const lines = [
      "[2026-09-02 22:09:47.4330943] [Lua] [DawnwalkerModBridge] Failed to initialize the pilot.",
      "[2026-09-02 22:09:47.4400000] [Error] Arbitrary loader error.",
      "[2026-09-02 22:09:47.4500000] [UE4SS.EngineTick.LuaModImpl] Failed to add hook, detour installation likely failed!",
      "[2026-09-02 22:09:47.4600000] Fatal error: access violation",
    ];

    const classification = classifyUe4ssStartupLog(lines.join("\n"));
    expect(classification.expectedNotices).toEqual([]);
    expect(classification.unexpectedFailures).toEqual(lines);
  });

  it("pins the same exact 20 capabilities as the desktop transport contract", () => {
    expect(EXPECTED_CAPABILITIES).toEqual([...RUNTIME_CAPABILITIES]);
    expect(EXPECTED_CAPABILITIES).toHaveLength(20);
    expect(EXPECTED_CAPABILITIES).not.toContain("combat:no-focus-ability-cooldowns");
    expect(EXPECTED_CAPABILITIES).not.toContain("player:unlimited-weight");
  });

  it("runs all ten read-only queries and writes unmistakable pilot-only evidence", async () => {
    const fake = createFakePilot();
    try {
      const evidence = await runPilotQa({ bridge: fake.bridge, suite: "read-only", expectedBootId: TEST_BOOT_ID });
      expect(evidence).toMatchObject({
        evidenceClass: "pilot-only",
        productionProof: false,
        passed: true,
        result: "passed",
        session: { bootId: TEST_BOOT_ID, bridgeVersion: "0.3.21-pilot", phase: "pilot" },
      });
      expect(fake.commands).toHaveLength(10);
      expect(fake.commands.every((command) => command.value === "")).toBe(true);
      expect(new Set(fake.commands.map((command) => command.capability))).toEqual(new Set([
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
      ]));
      expect(evidence.readings["player:add-gold"]).toBe(250);
      expect(evidence.readings["combat:rpg-difficulty"]).toBe(1);
      expect(evidence.readings["combat:action-difficulty"]).toBe(2);
      expect(evidence.readings["quests:journal-readback"]).toMatchObject({
        openQuestCount: 1,
        returnedQuestCount: 1,
        truncated: false,
        quests: [expect.objectContaining({ title: "A Quiet Night", tracked: true, objectiveCount: 1 })],
      });

      const evidenceDirectory = join(fake.root, "evidence");
      const evidencePath = await writePilotEvidence(evidence, evidenceDirectory);
      expect(basename(evidencePath)).toMatch(/^dawnwalker-live-pilot-qa-\d{8}T\d{6}Z\.json$/);
      expect(JSON.parse(readFileSync(evidencePath, "utf8"))).toMatchObject({
        evidenceClass: "pilot-only",
        productionProof: false,
      });
    } finally {
      fake.stop();
    }
  }, 10_000);

  it("changes only HUD, game speed, both Combat difficulty axes, and a +1 Gold delta one at a time and restores exact baselines", async () => {
    const fake = createFakePilot({ hudVisible: true, gameSpeed: 1, staleActiveAfterRestorePolls: 2 });
    try {
      const evidence = await runPilotQa({ bridge: fake.bridge, suite: "safe-reversible" });
      expect(evidence.passed, JSON.stringify(evidence.error)).toBe(true);
      expect(evidence.finalSession.active).toEqual([]);
      expect(evidence.restorations).toEqual([
        expect.objectContaining({ capability: "visuals:hud-visible", baseline: true, passed: true, verifiedReadback: true }),
        expect.objectContaining({ capability: "world:game-speed", baseline: 1, passed: true, verifiedReadback: 1 }),
        expect.objectContaining({ capability: "combat:rpg-difficulty", baseline: 1, passed: true, verifiedReadback: 1 }),
        expect.objectContaining({ capability: "combat:action-difficulty", baseline: 2, passed: true, verifiedReadback: 2 }),
        expect.objectContaining({ capability: "player:add-gold", baseline: 250, probeDelta: 1, restoreDelta: -1, passed: true, verifiedReadback: 250 }),
      ]);
      expect(fake.state).toMatchObject({
        hudVisible: true,
        gameSpeed: 1,
        traitPoints: 4,
        bloodEnergy: 72.5,
        gold: 250,
        rpgDifficulty: 1,
        actionDifficulty: 2,
      });

      const mutations = fake.commands.filter((command) => command.value !== "");
      expect(mutations.map(({ capability, value }) => [capability, value])).toEqual([
        ["visuals:hud-visible", "0"],
        ["visuals:hud-visible", "1"],
        ["world:game-speed", "1.1"],
        ["world:game-speed", "1"],
        ["combat:rpg-difficulty", "2"],
        ["combat:rpg-difficulty", "1"],
        ["combat:action-difficulty", "3"],
        ["combat:action-difficulty", "2"],
        ["player:add-gold", "1"],
        ["player:add-gold", "-1"],
      ]);
      expect(mutations.some((command) => command.capability.startsWith("teleport:")
        || command.capability === "player:trait-points"
        || command.capability === "player:blood-energy"
        || command.capability === "player:god-mode"
        || command.capability === "player:infinite-health"
        || command.capability === "player:unlimited-stamina"
        || command.capability === "combat:infinite-blood-energy")).toBe(false);
    } finally {
      fake.stop();
    }
  }, 10_000);

  it("restores the HUD baseline in finally when mutation verification fails", async () => {
    const fake = createFakePilot({ forceWrongHudVerification: true });
    try {
      const evidence = await runPilotQa({ bridge: fake.bridge, suite: "safe-reversible" });
      expect(evidence.passed).toBe(false);
      expect(evidence.error?.code, JSON.stringify(evidence.steps)).toBe("mutation-query-mismatch");
      expect(evidence.restorations[0]).toMatchObject({
        capability: "visuals:hud-visible",
        baseline: true,
        attempted: true,
        passed: true,
        verifiedReadback: true,
      });
      expect(fake.state.hudVisible).toBe(true);
      expect(fake.commands.filter((command) => command.value !== "").map(({ capability, value }) => [capability, value])).toEqual([
        ["visuals:hud-visible", "0"],
        ["visuals:hud-visible", "1"],
      ]);
    } finally {
      fake.stop();
    }
  }, 10_000);

  it("refuses every mutation when a preflight query is invalid or the player is not alive", async () => {
    for (const options of [{ invalidGameSpeedReadback: "NaN" }, { alive: false }]) {
      const fake = createFakePilot(options);
      try {
        const evidence = await runPilotQa({ bridge: fake.bridge, suite: "safe-reversible" });
        expect(evidence.passed).toBe(false);
        const expectedCode = options.alive === false ? "player-not-playable" : "invalid-readback";
        expect(evidence.error?.code).toBe(expectedCode);
        expect(fake.commands.every((command) => command.value === "")).toBe(true);
      } finally {
        fake.stop();
      }
    }
  }, 10_000);

  it("rejects the wrong bridge identity and missing capabilities before mutation", async () => {
    const cases = [
      { ready: { version: "0.3.1-pilot" }, expectedCode: "pilot-identity-mismatch", expectedCommands: 0 },
      { ready: { capabilities: EXPECTED_CAPABILITIES.slice(0, -1) }, expectedCode: "capability-mismatch", expectedCommands: 0 },
    ];
    for (const testCase of cases) {
      const fake = createFakePilot(testCase);
      try {
        const evidence = await runPilotQa({ bridge: fake.bridge, suite: "safe-reversible" });
        expect(evidence.passed).toBe(false);
        expect(evidence.error?.code).toBe(testCase.expectedCode);
        expect(fake.commands).toHaveLength(testCase.expectedCommands);
        expect(fake.commands.every((command) => command.value === "")).toBe(true);
      } finally {
        fake.stop();
      }
    }
  }, 10_000);

  it("permits an explicit exact audited subset but refuses unexpected advertised capabilities", async () => {
    const subset = EXPECTED_CAPABILITIES.filter((capability) => capability !== "player:sprint-no-drain");
    const fake = createFakePilot({ ready: { capabilities: subset } });
    try {
      const transport = createPilotQaBridge(fake.root, { expectedCapabilities: subset });
      const response = await transport.dispatch({ capability: "player:player-info" }, TEST_BOOT_ID);
      expect(response.accepted).toBe(true);
      const absent = await transport.dispatch({ capability: "player:sprint-no-drain", value: true }, TEST_BOOT_ID);
      expect(absent.accepted).toBe(false);
      writeReady(fake.root, { capabilities: EXPECTED_CAPABILITIES });
      const changed = await transport.dispatch({ capability: "player:player-info" }, TEST_BOOT_ID);
      expect(changed.accepted).toBe(false);
      expect(fake.commands).toHaveLength(1);
      expect(() => createPilotQaBridge(fake.root, { expectedCapabilities: ["invented:capability"] })).toThrow();
    } finally { fake.stop(); }
  });
});
