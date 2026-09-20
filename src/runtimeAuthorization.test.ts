import { describe, expect, it } from "vitest";
import type { BridgeStatus } from "../electron/bridgeTransport";
import {
  evaluateRuntimeControlAuthorization,
  isRuntimeDispatchAuthorized,
  PINNED_PILOT_BRIDGE_VERSION,
} from "../electron/runtimeAuthorization";
import { RUNTIME_CAPABILITIES } from "../electron/runtimeCapabilities";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_runtime_authorization_tests");

const pilotStatus: BridgeStatus = {
  connected: true,
  phase: "pilot",
  bootId: "1788403617-471079",
  bridgeVersion: PINNED_PILOT_BRIDGE_VERSION,
  capabilities: RUNTIME_CAPABILITIES,
  active: [],
  capabilitySetExact: true,
};

describe("Dawnwalker runtime-control authorization", () => {
  it("denies a packaged pilot even when the environment flag is set", () => {
    const authorization = evaluateRuntimeControlAuthorization(pilotStatus, {
      isPackaged: true,
      pilotControlsEnvironmentValue: "1",
    });

    expect(authorization).toEqual({
      buildVerified: false,
      interactionEligible: false,
      pilotControlsEnabled: false,
    });
    expect(isRuntimeDispatchAuthorized(pilotStatus, authorization, {
      capability: "player:unlimited-stamina",
      sessionId: pilotStatus.bootId!,
    })).toBe(false);
  });

  it("denies an unpackaged pilot without the explicit flag or exact pinned identity", () => {
    expect(evaluateRuntimeControlAuthorization(pilotStatus, {
      isPackaged: false,
    }).interactionEligible).toBe(false);
    expect(evaluateRuntimeControlAuthorization({
      ...pilotStatus,
      bridgeVersion: "0.3.0-pilot",
    }, {
      isPackaged: false,
      pilotControlsEnvironmentValue: "1",
    }).interactionEligible).toBe(false);
    expect(evaluateRuntimeControlAuthorization({
      ...pilotStatus,
      bridgeVersion: "0.3.2-pilot",
    }, {
      isPackaged: false,
      pilotControlsEnvironmentValue: "1",
    }).interactionEligible).toBe(false);
    expect(evaluateRuntimeControlAuthorization({
      ...pilotStatus,
      capabilities: ["player:unlimited-stamina"],
    }, {
      isPackaged: false,
      pilotControlsEnvironmentValue: "1",
    }).interactionEligible).toBe(false);
  });

  it("allows only the exact explicitly enabled unpackaged pilot session and advertised capability", () => {
    const authorization = evaluateRuntimeControlAuthorization(pilotStatus, {
      isPackaged: false,
      pilotControlsEnvironmentValue: "1",
    });

    expect(authorization).toEqual({
      buildVerified: false,
      interactionEligible: true,
      pilotControlsEnabled: true,
    });
    expect(isRuntimeDispatchAuthorized(pilotStatus, authorization, {
      capability: "player:unlimited-stamina",
      sessionId: "1788403617-471079",
    })).toBe(true);
    expect(isRuntimeDispatchAuthorized(pilotStatus, authorization, {
      capability: "player:unlimited-stamina",
      sessionId: "1788403617-999999",
    })).toBe(false);
    expect(isRuntimeDispatchAuthorized(pilotStatus, authorization, {
      capability: "player:not-real",
      sessionId: "1788403617-471079",
    })).toBe(false);
    expect(isRuntimeDispatchAuthorized(pilotStatus, authorization, {
      capability: "player:unlimited-weight",
      sessionId: "1788403617-471079",
    })).toBe(false);
  });

  it("keeps the existing connected production path available when packaged", () => {
    const productionStatus: BridgeStatus = {
      ...pilotStatus,
      phase: "production",
      bridgeVersion: "1.0.0",
      capabilities: ["player:unlimited-stamina"],
    };
    const authorization = evaluateRuntimeControlAuthorization(productionStatus, {
      isPackaged: true,
    });

    expect(authorization).toEqual({
      buildVerified: true,
      interactionEligible: true,
      pilotControlsEnabled: false,
    });
    expect(isRuntimeDispatchAuthorized(productionStatus, authorization, {
      capability: "player:unlimited-stamina",
      sessionId: "1788403617-471079",
    })).toBe(true);
  });
});
