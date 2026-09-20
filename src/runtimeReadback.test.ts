import { describe, expect, it, vi } from "vitest";
import {
  collectRuntimeControlReadback,
  collectRuntimePlayerReadback,
  collectRuntimeQuestJournalReadback,
  runtimeReadbackTestApi,
} from "../electron/runtimeReadback";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_runtime_readback_tests");

type RuntimeReadbackDispatch = Parameters<typeof collectRuntimePlayerReadback>[1];

const COMPLETE_READBACK_CAPABILITIES = Object.freeze([
  "player:player-info",
  "world:location-readback",
  "visuals:hud-visible",
  "world:game-speed",
  "combat:rpg-difficulty",
  "combat:action-difficulty",
  "quests:journal-readback",
  "player:add-gold",
]);

function createAppliedReadbackResult(capability: string) {
  const readbacks: Readonly<Record<string, string>> = {
    "player:player-info": "alive=1;health_percent=75;stamina_percent=80;blood=9;blood_max=15",
    "world:location-readback": "x=1;y=2;z=3",
    "visuals:hud-visible": "0",
    "world:game-speed": "1.5",
    "combat:rpg-difficulty": "2",
    "combat:action-difficulty": "3",
    "player:add-gold": "250",
  };
  return {
    accepted: true,
    capability,
    requestId: `test-${capability}`,
    status: "applied" as const,
    message: "read",
    readback: readbacks[capability],
  };
}

async function collectCompleteRuntimeReadback(dispatch: RuntimeReadbackDispatch) {
  const [player, controls, questJournal] = await Promise.all([
    collectRuntimePlayerReadback(COMPLETE_READBACK_CAPABILITIES, dispatch),
    collectRuntimeControlReadback(COMPLETE_READBACK_CAPABILITIES, dispatch),
    collectRuntimeQuestJournalReadback(COMPLETE_READBACK_CAPABILITIES, dispatch),
  ]);
  return { player, controls, questJournal };
}

describe("Dawnwalker runtime readback", () => {
  it("parses bounded player percentages and exact blood values", () => {
    expect(runtimeReadbackTestApi.parsePlayerStatus(
      "alive=1;health_percent=87.5;stamina_percent=42.25;blood=12.5;blood_max=20;level=7;trait_points=3",
    )).toEqual({
      alive: true,
      health: 87.5,
      maxHealth: 100,
      stamina: 42.25,
      maxStamina: 100,
      bloodEnergy: 12.5,
      maxBloodEnergy: 20,
      level: 7,
      traitPoints: 3,
    });
  });

  it("rejects malformed or non-finite fields without poisoning valid coordinates", () => {
    expect(runtimeReadbackTestApi.parseLocation("x=125.5;y=Infinity;z=-81.25;bad-key=4")).toEqual({
      x: 125.5,
      z: -81.25,
    });
    expect(runtimeReadbackTestApi.parsePlayerStatus("health_percent=101;stamina_percent=NaN;blood=-1;blood_max=0")).toEqual({});
  });

  it("rejects ambiguous fields and nondecimal or fractional progression values", () => {
    expect(runtimeReadbackTestApi.parsePlayerStatus("alive=1;health_percent=10;health_percent=90")).toEqual({});
    expect(runtimeReadbackTestApi.parseLocation("x=0xFF;y= 12;z=-1.25e3")).toEqual({ z: -1250 });
    expect(runtimeReadbackTestApi.parsePlayerStatus("level=1.5;trait_points=2147483648;health_percent=80"))
      .toEqual({ health: 80, maxHealth: 100 });
    expect(runtimeReadbackTestApi.parseGoldQuantity("0xFF")).toBeUndefined();
  });

  it.each(COMPLETE_READBACK_CAPABILITIES)("isolates rejected and throwing %s queries", async (failedCapability) => {
    const baseline = await collectCompleteRuntimeReadback(async ({ capability }) => createAppliedReadbackResult(capability));
    for (const throwsSynchronously of [false, true]) {
      const dispatch: RuntimeReadbackDispatch = vi.fn(({ capability }) => {
        if (capability !== failedCapability) return Promise.resolve(createAppliedReadbackResult(capability));
        if (throwsSynchronously) throw new Error("Transport unavailable");
        return Promise.reject(new Error("Transport unavailable"));
      });
      const snapshot = await collectCompleteRuntimeReadback(dispatch);
      const missingFields: Readonly<Record<string, readonly string[]>> = {
        "player:player-info": ["alive", "health", "maxHealth", "stamina", "maxStamina", "bloodEnergy", "maxBloodEnergy"],
        "world:location-readback": ["x", "y", "z"],
        "player:add-gold": ["gold"],
        "visuals:hud-visible": ["hudVisible"],
        "world:game-speed": ["gameSpeed"],
        "combat:rpg-difficulty": ["rpgDifficulty"],
        "combat:action-difficulty": ["actionDifficulty"],
      };
      const expected = {
        player: Object.fromEntries(Object.entries(baseline.player ?? {}).filter(([key]) => !missingFields[failedCapability]?.includes(key))),
        controls: Object.fromEntries(Object.entries(baseline.controls ?? {}).filter(([key]) => !missingFields[failedCapability]?.includes(key))),
        questJournal: undefined,
      };
      expect(snapshot).toEqual(expected);
      expect(dispatch).toHaveBeenCalledTimes(COMPLETE_READBACK_CAPABILITIES.length);
    }
  });

  it("does not expose a value from a rejected or mismatched command response", async () => {
    for (const overrides of [{ accepted: false }, { status: "rejected" as const }, { capability: "unrelated:query" }]) {
      const dispatch: RuntimeReadbackDispatch = async ({ capability }) => ({
        ...createAppliedReadbackResult(capability), ...overrides,
      });
      await expect(collectCompleteRuntimeReadback(dispatch)).resolves.toEqual({
        player: undefined, controls: undefined, questJournal: undefined,
      });
    }
  });

  it("parses only canonical HUD and bounded game-speed readbacks", () => {
    expect(runtimeReadbackTestApi.parseBoolean("1")).toBe(true);
    expect(runtimeReadbackTestApi.parseBoolean("0")).toBe(false);
    expect(runtimeReadbackTestApi.parseBoolean("true")).toBeUndefined();
    expect(runtimeReadbackTestApi.parseGameSpeed("1.25")).toBe(1.25);
    expect(runtimeReadbackTestApi.parseGameSpeed("0")).toBeUndefined();
    expect(runtimeReadbackTestApi.parseGameSpeed("Infinity")).toBeUndefined();
    expect(runtimeReadbackTestApi.parseDifficulty("0")).toBe(0);
    expect(runtimeReadbackTestApi.parseDifficulty("3")).toBe(3);
    expect(runtimeReadbackTestApi.parseDifficulty("4")).toBeUndefined();
    expect(runtimeReadbackTestApi.parseDifficulty("1.5")).toBeUndefined();
  });

  it("parses only nonnegative int32 Gold balances", () => {
    expect(runtimeReadbackTestApi.parseGoldQuantity("0")).toBe(0);
    expect(runtimeReadbackTestApi.parseGoldQuantity("2147483647")).toBe(2_147_483_647);
    expect(runtimeReadbackTestApi.parseGoldQuantity("-1")).toBeUndefined();
    expect(runtimeReadbackTestApi.parseGoldQuantity("1.5")).toBeUndefined();
    expect(runtimeReadbackTestApi.parseGoldQuantity("2147483648")).toBeUndefined();
    expect(runtimeReadbackTestApi.parseGoldQuantity("Infinity")).toBeUndefined();
  });

  it("dispatches only advertised read-only capabilities and merges accepted results", async () => {
    const dispatch = vi.fn(async ({ capability }: Readonly<{ capability: string }>) => ({
      accepted: true,
      capability,
      requestId: `test-${capability}`,
      status: "applied" as const,
      message: "read",
      readback: capability === "player:player-info"
        ? "alive=1;health_percent=75;stamina_percent=80;blood=9;blood_max=15"
        : capability === "player:add-gold" ? "250" : "x=1;y=2;z=3",
    }));

    await expect(collectRuntimePlayerReadback(
      ["player:player-info", "world:location-readback", "player:add-gold", "world:game-speed"],
      dispatch,
    )).resolves.toMatchObject({ health: 75, stamina: 80, bloodEnergy: 9, gold: 250, x: 1, y: 2, z: 3 });
    expect(dispatch).toHaveBeenCalledTimes(3);
  });

  it("returns no player object when no read-only capability is advertised", async () => {
    const dispatch = vi.fn();
    await expect(collectRuntimePlayerReadback(["world:game-speed"], dispatch)).resolves.toBeUndefined();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("collects only advertised HUD and game-speed control readbacks", async () => {
    const dispatch = vi.fn(async ({ capability }: Readonly<{ capability: string }>) => ({
      accepted: true,
      capability,
      requestId: `test-${capability}`,
      status: "applied" as const,
      message: "read",
      readback: capability === "visuals:hud-visible" ? "0" : "1.5",
    }));

    await expect(collectRuntimeControlReadback(
      ["visuals:hud-visible", "world:game-speed", "player:player-info"],
      dispatch,
    )).resolves.toEqual({ hudVisible: false, gameSpeed: 1.5 });
    expect(dispatch).toHaveBeenCalledTimes(2);
  });

  it("collects independent RPG and Action difficulty readbacks and isolates either rejection", async () => {
    const dispatch = vi.fn(({ capability }: Readonly<{ capability: string }>) => {
      if (capability === "combat:rpg-difficulty") return Promise.reject(new Error("RPG query rejected"));
      return Promise.resolve(createAppliedReadbackResult(capability));
    });

    await expect(collectRuntimeControlReadback([
      "visuals:hud-visible",
      "world:game-speed",
      "combat:rpg-difficulty",
      "combat:action-difficulty",
    ], dispatch)).resolves.toEqual({ hudVisible: false, gameSpeed: 1.5, actionDifficulty: 3 });
    expect(dispatch).toHaveBeenCalledTimes(4);
  });

  it("parses the bounded Quest Journal schema without treating encoded delimiters as records", () => {
    expect(runtimeReadbackTestApi.parseQuestJournal([
      "schema=1",
      "open_total=1",
      "returned=1",
      "truncated=0",
      "q=0,active,1,Blood%2C Stone%3B%3D Dawn,2,0",
      "o=0,active,Find the key%2C then return%3B safely.,1.500000,3,0",
      "o=0,success,Visit %C5%81uk%C3%B3w,1.000000,1,1",
    ].join(";"))).toEqual({
      openQuestCount: 1,
      returnedQuestCount: 1,
      truncated: false,
      quests: [{
        title: "Blood, Stone;= Dawn",
        state: "active",
        tracked: true,
        objectiveCount: 2,
        objectivesTruncated: false,
        objectives: [
          { text: "Find the key, then return; safely.", state: "active", currentCount: 1.5, maxCount: 3, optional: false },
          { text: "Visit Łuków", state: "success", currentCount: 1, maxCount: 1, optional: true },
        ],
      }],
    });
  });

  it("accepts an empty Journal and rejects malformed, inconsistent, or oversized snapshots", () => {
    expect(runtimeReadbackTestApi.parseQuestJournal(
      "schema=1;open_total=0;returned=0;truncated=0",
    )).toEqual({ openQuestCount: 0, returnedQuestCount: 0, truncated: false, quests: [] });
    expect(runtimeReadbackTestApi.parseQuestJournal(
      "schema=1;open_total=1;returned=1;truncated=0;q=0,active,0,Bad%ZZ,0,0",
    )).toBeUndefined();
    expect(runtimeReadbackTestApi.parseQuestJournal(
      "schema=1;open_total=2;returned=1;truncated=0;q=0,active,0,Quest,0,0",
    )).toBeUndefined();
    expect(runtimeReadbackTestApi.parseQuestJournal("x".repeat(8_193))).toBeUndefined();
  });

  it("dispatches Quest Journal only when advertised and keeps a valid empty snapshot", async () => {
    const dispatch = vi.fn(async ({ capability }: Readonly<{ capability: string }>) => ({
      accepted: true,
      capability,
      requestId: "quest-readback",
      status: "applied" as const,
      message: "read",
      readback: "schema=1;open_total=0;returned=0;truncated=0",
    }));

    await expect(collectRuntimeQuestJournalReadback(["quests:journal-readback"], dispatch)).resolves.toEqual({
      openQuestCount: 0,
      returnedQuestCount: 0,
      truncated: false,
      quests: [],
    });
    await expect(collectRuntimeQuestJournalReadback(["world:game-speed"], dispatch)).resolves.toBeUndefined();
    expect(dispatch).toHaveBeenCalledOnce();
  });

  it("keeps Player, Location, and control readbacks when Quest dispatch rejects", async () => {
    const dispatch: RuntimeReadbackDispatch = vi.fn(({ capability }) => (
      capability === "quests:journal-readback"
        ? Promise.reject(new Error("Quest transport rejected"))
        : Promise.resolve(createAppliedReadbackResult(capability))
    ));

    await expect(collectCompleteRuntimeReadback(dispatch)).resolves.toEqual({
      player: {
        alive: true,
        health: 75,
        maxHealth: 100,
        stamina: 80,
        maxStamina: 100,
        bloodEnergy: 9,
        maxBloodEnergy: 15,
        gold: 250,
        x: 1,
        y: 2,
        z: 3,
      },
      controls: { hudVisible: false, gameSpeed: 1.5, rpgDifficulty: 2, actionDifficulty: 3 },
      questJournal: undefined,
    });
  });

  it("keeps Player, Location, and control readbacks when Quest dispatch throws", async () => {
    const dispatch: RuntimeReadbackDispatch = vi.fn(({ capability }) => {
      if (capability === "quests:journal-readback") throw new Error("Quest transport threw");
      return Promise.resolve(createAppliedReadbackResult(capability));
    });

    await expect(collectCompleteRuntimeReadback(dispatch)).resolves.toEqual({
      player: {
        alive: true,
        health: 75,
        maxHealth: 100,
        stamina: 80,
        maxStamina: 100,
        bloodEnergy: 9,
        maxBloodEnergy: 15,
        gold: 250,
        x: 1,
        y: 2,
        z: 3,
      },
      controls: { hudVisible: false, gameSpeed: 1.5, rpgDifficulty: 2, actionDifficulty: 3 },
      questJournal: undefined,
    });
  });

  it("keeps Player and Location readbacks when the optional Gold query rejects", async () => {
    const dispatch: RuntimeReadbackDispatch = vi.fn(({ capability }) => (
      capability === "player:add-gold"
        ? Promise.reject(new Error("Gold query rejected"))
        : Promise.resolve(createAppliedReadbackResult(capability))
    ));

    await expect(collectRuntimePlayerReadback(COMPLETE_READBACK_CAPABILITIES, dispatch)).resolves.toMatchObject({
      alive: true,
      health: 75,
      x: 1,
      y: 2,
      z: 3,
    });
  });
});
