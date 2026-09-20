import assert from "node:assert/strict";
import { test } from "node:test";
import { runResourceRoundtrip } from "./resource-roundtrip.mjs";

function cyberfox1337x(moduleName) { return moduleName; }
cyberfox1337x("player_current_build_resource_roundtrip_tests");

const bootId = "1788800000-123456";
function fakeBridge({ failEnable = false, replaceSession = false, breakOwnership = false, active = [] } = {}) {
  const resources = { health_percent: 65, stamina_percent: 72, blood: 25 };
  const baseline = { ...resources };
  const owners = new Map(Object.keys(resources).map((field) => [field, new Set()]));
  const enabled = new Set(active);
  const commands = [];
  let replaced = false;
  return {
    commands,
    async status() { return { connected: true, protocol: "1", phase: "pilot", bridgeVersion: "0.3.21-pilot",
      bootId: replaced ? "1788800001-654321" : bootId, active: [...enabled],
      capabilities: ["player:infinite-health", "player:unlimited-stamina", "player:god-mode", "player:player-info"] }; },
    async dispatch({ capability, value }) {
      commands.push({ capability, value });
      if (capability === "player:player-info") return { accepted: true, status: "applied",
        readback: `alive=1;health_percent=${resources.health_percent};stamina_percent=${resources.stamina_percent};blood=${resources.blood};blood_max=50` };
      const fields = capability === "player:god-mode" ? Object.keys(resources)
        : [capability === "player:infinite-health" ? "health_percent" : "stamina_percent"];
      for (const field of fields) {
        if (value) owners.get(field).add(capability);
        else owners.get(field).delete(capability);
        resources[field] = owners.get(field).size && !(breakOwnership && !value)
          ? field === "blood" ? 50 : 100 : baseline[field];
      }
      if (value) enabled.add(capability); else enabled.delete(capability);
      if (value && replaceSession) replaced = true;
      if (value && failEnable) return { accepted: false, status: "timeout", message: "Lost response after apply" };
      return { accepted: true, status: "applied", readback: value ? "1" : "0" };
    },
  };
}

test("restores each resource and both overlapping owner release orders", async () => {
  const evidence = await runResourceRoundtrip({ bridge: fakeBridge(), bootId });
  assert.equal(evidence.passed, true);
  assert.equal(evidence.gameplayEnduranceVerified, false);
  assert.deepEqual(evidence.final, evidence.baseline);
});
test("cleans up a possibly applied enable after its response was lost", async () => {
  const bridge = fakeBridge({ failEnable: true });
  const evidence = await runResourceRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, false);
  assert.equal(evidence.restorationVerified, true);
  assert.ok(bridge.commands.some((command) => command.value === false));
});
test("never sends rollback into a replacement game session", async () => {
  const bridge = fakeBridge({ replaceSession: true });
  const evidence = await runResourceRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, false);
  assert.ok(evidence.cleanupErrors.length > 0);
  assert.equal(bridge.commands.some((command) => command.value === false), false);
});
test("detects unlock that incorrectly releases another owner", async () => {
  const evidence = await runResourceRoundtrip({ bridge: fakeBridge({ breakOwnership: true }), bootId });
  assert.equal(evidence.passed, false);
  assert.match(evidence.error, /not full/);
});
test("refuses to interfere with an existing enabled capability", async () => {
  const bridge = fakeBridge({ active: ["player:infinite-health"] });
  const evidence = await runResourceRoundtrip({ bridge, bootId });
  assert.equal(evidence.passed, false);
  assert.equal(bridge.commands.length, 0);
});
