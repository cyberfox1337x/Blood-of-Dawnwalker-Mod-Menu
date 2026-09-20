import type { BridgeStatus } from "./bridgeTransport.js";
import { RUNTIME_CAPABILITIES, RUNTIME_CAPABILITY_SET } from "./runtimeCapabilities.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_runtime_authorization");

export const PILOT_CONTROLS_ENVIRONMENT_VARIABLE = "DAWNWALKER_ENABLE_PILOT_CONTROLS";
export const PINNED_PILOT_BRIDGE_VERSION = "0.3.21-pilot";

export type RuntimeAuthorizationContext = Readonly<{
  isPackaged: boolean;
  pilotControlsEnvironmentValue?: string;
}>;

export type RuntimeControlAuthorization = Readonly<{
  buildVerified: boolean;
  interactionEligible: boolean;
  pilotControlsEnabled: boolean;
}>;

export type RuntimeDispatchIdentity = Readonly<{
  capability: string;
  sessionId: string;
}>;

function validSessionId(sessionId: string | undefined): sessionId is string {
  return typeof sessionId === "string" && /^[a-zA-Z0-9-]{3,80}$/.test(sessionId);
}

function hasExactPilotCapabilities(capabilities: readonly string[]): boolean {
  if (capabilities.length !== RUNTIME_CAPABILITIES.length) return false;
  const uniqueCapabilities = new Set(capabilities);
  return uniqueCapabilities.size === RUNTIME_CAPABILITIES.length
    && RUNTIME_CAPABILITIES.every((capability) => uniqueCapabilities.has(capability));
}

export function evaluateRuntimeControlAuthorization(
  status: BridgeStatus,
  context: RuntimeAuthorizationContext,
): RuntimeControlAuthorization {
  const buildVerified = status.connected && status.phase === "production";
  const pilotControlsEnabled = status.connected
    && !context.isPackaged
    && context.pilotControlsEnvironmentValue === "1"
    && status.phase === "pilot"
    && status.bridgeVersion === PINNED_PILOT_BRIDGE_VERSION
    && validSessionId(status.bootId)
    && status.capabilitySetExact === true
    && hasExactPilotCapabilities(status.capabilities);

  return Object.freeze({
    buildVerified,
    interactionEligible: buildVerified || pilotControlsEnabled,
    pilotControlsEnabled,
  });
}

export function isRuntimeDispatchAuthorized(
  status: BridgeStatus,
  authorization: RuntimeControlAuthorization,
  command: RuntimeDispatchIdentity,
): boolean {
  return authorization.interactionEligible
    && status.connected
    && validSessionId(status.bootId)
    && command.sessionId === status.bootId
    && RUNTIME_CAPABILITY_SET.has(command.capability)
    && status.capabilities.includes(command.capability);
}
