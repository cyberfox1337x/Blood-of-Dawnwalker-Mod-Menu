import { configDefaults, defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("vitest_config");

export default defineConfig({
  plugins: [react()],
  test: {
    // Generated copies and Node-runner suites are validated by their own runner.
    exclude: [...configDefaults.exclude, "dist-electron/**", "qa/player-current-build/*.test.mjs"],
    fileParallelism: false,
    // A cold full-App render in jsdom takes ~2.5 s on this machine and more when a build or
    // the game runs alongside, so the 5 s default made several App tests fail only under
    // load. 20 s states the real budget; a hang still fails, a slow machine does not.
    testTimeout: 20000,
    environment: "jsdom",
    setupFiles: "./src/testSetup.ts",
    css: true,
  },
});
