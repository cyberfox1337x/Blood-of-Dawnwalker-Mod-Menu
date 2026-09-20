import { afterEach, describe, expect, it, vi } from "vitest";
import { createModAdapter } from "./modAdapter";
import type { RuntimeCommand, RuntimeInfo, RuntimeResult } from "./runtimeContract";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_mod_adapter_tests");

describe("Dawnwalker mod adapter", () => {
  afterEach(() => {
    delete window.dawnwalkerDesktop;
  });

  it("fails closed in a browser or unpackaged renderer", async () => {
    const adapter = createModAdapter();
    expect(adapter.transport).toBe("browser");
    expect(await adapter.getRuntimeInfo()).toMatchObject({ connected: false, buildVerified: false, capabilities: [] });

    const command: RuntimeCommand = {
      capability: "player:god-mode",
      requestId: "browser-test-1",
      sessionId: "test-boot-1",
      value: true,
    };
    expect(await adapter.dispatch(command)).toMatchObject({
      accepted: false,
      capability: "player:god-mode",
      requestId: "browser-test-1",
      status: "rejected",
    });
  });

  it("routes through the isolated Electron preload and filters unknown advertised capabilities", async () => {
    const runtimeInfo: RuntimeInfo = {
      platform: "win32",
      mode: "live-offline",
      connected: true,
      gameRunning: true,
      buildVerified: true,
      interactionEligible: true,
      sessionId: "test-boot-1",
      capabilities: ["player:god-mode", "not-real" as "player:god-mode"],
      activeCapabilities: ["player:god-mode", "not-real" as "player:god-mode"],
    };
    const result: RuntimeResult = {
      accepted: true,
      capability: "player:god-mode",
      requestId: "electron-test-1",
      status: "applied",
      message: "Applied and read back.",
      readback: true,
    };
    const getRuntimeInfo = vi.fn(async () => runtimeInfo);
    const dispatch = vi.fn(async () => result);
    window.dawnwalkerDesktop = {
      beginWindowDrag: vi.fn(),
      updateWindowDrag: vi.fn(),
      endWindowDrag: vi.fn(),
      minimizeWindow: vi.fn(),
      closeWindow: vi.fn(),
      onGameplayHotkey: vi.fn(() => () => undefined),
      getRuntimeInfo,
      dispatch,
    };

    const adapter = createModAdapter();
    expect(adapter.transport).toBe("electron");
    expect(await adapter.getRuntimeInfo()).toMatchObject({
      capabilities: ["player:god-mode"],
      activeCapabilities: ["player:god-mode"],
    });

    const command: RuntimeCommand = {
      capability: "player:god-mode",
      requestId: "electron-test-1",
      sessionId: "test-boot-1",
      value: true,
    };
    expect(await adapter.dispatch(command)).toEqual(result);
    expect(dispatch).toHaveBeenCalledWith(command);
  });
});
