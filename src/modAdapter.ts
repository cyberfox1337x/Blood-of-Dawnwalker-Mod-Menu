import {
  normalizeRuntimeCapabilities,
  type RuntimeCommand,
  type RuntimeInfo,
  type RuntimeResult,
} from "./runtimeContract";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_mod_adapter");

type DesktopRuntimeBridge = Readonly<{
  getRuntimeInfo?: () => Promise<RuntimeInfo>;
  dispatch?: (command: RuntimeCommand) => Promise<RuntimeResult>;
}>;

export interface ModAdapter {
  readonly transport: "electron" | "browser";
  getRuntimeInfo(): Promise<RuntimeInfo>;
  dispatch(command: RuntimeCommand): Promise<RuntimeResult>;
}

function disconnectedRuntimeInfo(platform: string): RuntimeInfo {
  return {
    platform,
    mode: "disconnected",
    connected: false,
    gameRunning: false,
    buildVerified: false,
    interactionEligible: false,
    capabilities: [],
    activeCapabilities: [],
  };
}

function disconnectedResult(command: RuntimeCommand): RuntimeResult {
  return {
    accepted: false,
    capability: command.capability,
    requestId: command.requestId,
    status: "rejected",
    message: "The verified Dawnwalker offline runtime bridge is not connected.",
  };
}

function readDesktopBridge(): DesktopRuntimeBridge | undefined {
  return (window as typeof window & { dawnwalkerDesktop?: DesktopRuntimeBridge }).dawnwalkerDesktop;
}

export function createModAdapter(): ModAdapter {
  const desktopBridge = readDesktopBridge();
  if (!desktopBridge?.getRuntimeInfo || !desktopBridge.dispatch) {
    return {
      transport: "browser",
      async getRuntimeInfo() {
        return disconnectedRuntimeInfo("browser");
      },
      async dispatch(command) {
        return disconnectedResult(command);
      },
    };
  }

  return {
    transport: "electron",
    async getRuntimeInfo() {
      const info = await desktopBridge.getRuntimeInfo!();
      return {
        ...info,
        capabilities: normalizeRuntimeCapabilities(info.capabilities),
        activeCapabilities: normalizeRuntimeCapabilities(info.activeCapabilities),
      };
    },
    dispatch(command) {
      return desktopBridge.dispatch!(command);
    },
  };
}
