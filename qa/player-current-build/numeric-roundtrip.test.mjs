import assert from "node:assert/strict";
import { test } from "node:test";
import { runNumericRoundtrip } from "./numeric-roundtrip.mjs";

function cyberfox1337x(moduleName) { return moduleName; }
cyberfox1337x("player_current_build_numeric_roundtrip_tests");

const bootId = "1788822080-776940";
function fakeBridge({ loseGoldEnable = false, loseGoldRestore = false, replaceBoot = false,
  unrelatedGold = false, traitBaseline = 4 } = {}) {
  const amounts = { "player:blood-energy": 64, "player:trait-points": traitBaseline, "player:add-gold": 20 };
  const commands = [];
  let replaced = false;
  return {
    amounts, commands,
    async status() { return { connected: true, bootId: replaced ? "1788822081-123456" : bootId,
      phase: "pilot", bridgeVersion: "0.3.21-pilot", active: [], capabilities: [...Object.keys(amounts), "player:player-info"] }; },
    async dispatch({ capability, value }) {
      commands.push({ capability, value });
      if (capability === "player:player-info") return { accepted: true, status: "applied", readback: "alive=1;health_percent=100" };
      if (value !== undefined) {
        if (capability === "player:add-gold") amounts[capability] += value;
        else amounts[capability] = value;
        if (replaceBoot) replaced = true;
        if (capability === "player:add-gold" && value === 1 && unrelatedGold) amounts[capability] += 10;
        if (capability === "player:add-gold" && ((value === 1 && loseGoldEnable) || (value === -1 && loseGoldRestore))) {
          return { accepted: false, status: "timeout", message: "Response lost after apply" };
        }
      }
      return { accepted: true, status: "applied", readback: String(amounts[capability]) };
    },
  };
}

test("three numeric controls restore independently with no progression or item commands", async () => {
  const bridge = fakeBridge();
  const evidence = await runNumericRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, true);
  assert.deepEqual(evidence.final, evidence.baselines);
  assert.equal(evidence.roundtrips.length, 3);
  assert.deepEqual(bridge.commands.filter((command) => command.value !== undefined).map((command) => command.value), [80, 64, 5, 4, 1, -1]);
});
test("lost gold enable response still queries and restores exactly one coin", async () => {
  const bridge = fakeBridge({ loseGoldEnable: true });
  const evidence = await runNumericRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, false);
  assert.equal(bridge.amounts["player:add-gold"], 20);
  assert.equal(evidence.roundtrips.at(-1).restored, true);
});
test("lost inverse response is independently verified without repeating the inverse", async () => {
  const bridge = fakeBridge({ loseGoldRestore: true });
  const evidence = await runNumericRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, true);
  assert.equal(bridge.commands.filter((command) => command.value === -1).length, 1);
  assert.equal(bridge.amounts["player:add-gold"], 20);
});
test("does not reverse an unrelated currency change", async () => {
  const bridge = fakeBridge({ unrelatedGold: true });
  const evidence = await runNumericRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, false);
  assert.ok(evidence.cleanupErrors.length);
  assert.equal(bridge.commands.some((command) => command.value === -1), false);
});
test("refuses baseline writes after boot replacement", async () => {
  const bridge = fakeBridge({ replaceBoot: true });
  const evidence = await runNumericRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, false);
  assert.ok(evidence.cleanupErrors.length);
  assert.equal(bridge.commands.filter((command) => command.value !== undefined).length, 1);
});
test("out-of-range trait baseline prevents every mutation", async () => {
  const bridge = fakeBridge({ traitBaseline: 9999 });
  const evidence = await runNumericRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, false);
  assert.equal(bridge.commands.some((command) => command.value !== undefined), false);
});
