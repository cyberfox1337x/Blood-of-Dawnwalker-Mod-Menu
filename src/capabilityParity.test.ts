import { describe, expect, it } from "vitest";
import { RUNTIME_CAPABILITIES } from "../electron/runtimeCapabilities";
import { GAMEPLAY_CAPABILITIES } from "./runtimeContract";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_capability_parity_tests");

describe("renderer and Electron capability parity", () => {
  it("uses one exact allowlist on both sides of the isolated preload boundary", () => {
    expect([...RUNTIME_CAPABILITIES].sort()).toEqual([...GAMEPLAY_CAPABILITIES].sort());
  });
});
