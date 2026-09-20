// @vitest-environment node
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { expect, it } from "vitest";

const cyberfox1337x = Object.freeze({ function: (moduleName) => void moduleName });
cyberfox1337x.function("dawnwalker_pilot_dispatch_timeout_tests");

it("returns the runtime's deferred rejection instead of hiding it behind an early timeout", async () => {
  const root = mkdtempSync(join(tmpdir(), "dawnwalker-pilot-dispatch-test-"));
  writeFileSync(join(root, "ready.txt"), [
    "protocol=1", "boot_id=test-boot-1", "version=0.3.21-pilot", "phase=pilot", "",
  ].join("\n"));
  let requestSeenAt = 0;
  const responder = setInterval(() => {
    let command;
    try {
      command = readFileSync(join(root, "command.txt"), "utf8");
    } catch {
      // The child process has not published its command yet.
      return;
    }
    const requestId = command.match(/^request_id=(.+)$/m)?.[1];
    if (!requestId) return;
    if (!requestSeenAt) requestSeenAt = Date.now();
    if (Date.now() - requestSeenAt < 6_100) return;
    writeFileSync(join(root, "response.txt"), [
      "protocol=1", "boot_id=test-boot-1", `request_id=${requestId}`,
      "accepted=0", "status=rejected",
      "message=Unblock Trait did not change within the bounded verification window; level 3 remained exact.",
      "readback=", "",
    ].join("\n"));
  }, 10);
  const child = spawn(process.execPath, [
    resolve("scripts/Dispatch-DawnwalkerPilotCommand.mjs"),
    "--bridge-root", root, "--expected-version", "0.3.21-pilot", "--boot-id", "test-boot-1",
    "--capability", "player:unblock-trait", "--value", "Human_CraftingOne|4",
  ], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
  child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
  try {
    const exitCode = await new Promise((resolveExit, reject) => {
      child.once("error", reject);
      child.once("exit", resolveExit);
    });
    expect(exitCode).toBe(2);
    expect(stderr).toBe("");
    expect(JSON.parse(stdout)).toMatchObject({ accepted: "0", status: "rejected" });
    expect(JSON.parse(stdout).message).toContain("level 3 remained exact");
  } finally {
    clearInterval(responder);
    if (child.exitCode === null) child.kill();
    rmSync(root, { recursive: true, force: true });
  }
}, 10_000);
