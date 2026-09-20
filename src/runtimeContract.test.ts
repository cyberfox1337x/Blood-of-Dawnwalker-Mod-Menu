import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  GAMEPLAY_CAPABILITIES,
  isGameplayCapability,
  normalizeRuntimeCapabilities,
} from "./runtimeContract";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_runtime_contract_tests");

type MatrixFeature = Readonly<{
  id: string;
  status: string;
  control: string;
}>;

type MatrixCategory = Readonly<{
  id: string;
  features: readonly MatrixFeature[];
}>;

type MatrixBridgePilot = Readonly<{
  capabilities: readonly Readonly<{ id: string; disposition?: string }>[];
}>;

const matrix = JSON.parse(
  readFileSync(resolve(process.cwd(), "analysis/dawnwalker-uue4ss/feature-contract-matrix.json"), "utf8"),
) as Readonly<{
  bridgePilot: MatrixBridgePilot;
  categories: readonly MatrixCategory[];
}>;

describe("Dawnwalker runtime capability contract", () => {
  it("matches the exact static-audited bridge pilot capability set", () => {
    const matrixCapabilities = matrix.bridgePilot.capabilities
      .filter((feature) => feature.disposition !== "withdrawn-feasibility-probe")
      .map((feature) => feature.id);

    expect([...GAMEPLAY_CAPABILITIES].sort()).toEqual(matrixCapabilities.sort());
  });

  it("rejects unknown bridge-advertised capabilities and removes duplicates", () => {
    expect(isGameplayCapability("player:god-mode")).toBe(true);
    expect(isGameplayCapability("player:imaginary-mode")).toBe(false);
    expect(normalizeRuntimeCapabilities([
      "player:god-mode",
      "player:imaginary-mode",
      "player:god-mode",
      42,
    ])).toEqual(["player:god-mode"]);
  });

  it("keeps all game-changing features capability-gated until reflection proves them", () => {
    const prematurelyLive = matrix.categories.flatMap((category) =>
      category.features.filter((feature) => feature.status === "live").map((feature) => `${category.id}:${feature.id}`),
    );
    expect(prematurelyLive).toEqual([]);
  });
});
