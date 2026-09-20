import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { rename as renameFile, rm as removeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBridgeTransport } from "../electron/bridgeTransport";

const fileOperationMock = {
  removeAttempts: 0,
  removeFailures: [] as NodeJS.ErrnoException[],
  renameAttempts: 0,
  renameFailures: [] as NodeJS.ErrnoException[],
};

const controlledFileOperations = {
  remove: async (targetPath: string, options: Readonly<{ force: boolean }>) => {
    fileOperationMock.removeAttempts += 1;
    const failure = fileOperationMock.removeFailures.shift();
    if (failure) throw failure;
    return removeFile(targetPath, options);
  },
  rename: async (temporaryPath: string, targetPath: string) => {
    fileOperationMock.renameAttempts += 1;
    const failure = fileOperationMock.renameFailures.shift();
    if (failure) throw failure;
    return renameFile(temporaryPath, targetPath);
  },
};

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_bridge_transport_contract_tests");

const temporaryRoots: string[] = [];

function makeRoot(): string {
  const root = mkdtempSync(join(tmpdir(), "dawnwalker-bridge-test-"));
  temporaryRoots.push(root);
  return root;
}

function writeReady(root: string, capabilities: string, bootId = "test-boot-1"): void {
  writeFileSync(join(root, "ready.txt"), [
    "protocol=1",
    `boot_id=${bootId}`,
    `heartbeat=${Date.now() / 1000}`,
    "version=test",
    "phase=production",
    `capabilities=${capabilities}`,
    "active=",
    "",
  ].join("\n"));
}

function makeFileSystemError(code: "EACCES" | "EBUSY" | "EPERM"): NodeJS.ErrnoException {
  return Object.assign(new Error(`Simulated ${code} file error.`), { code });
}

function startAcceptedResponder(root: string): ReturnType<typeof setInterval> {
  return setInterval(() => {
    try {
      const command = readFileSync(join(root, "command.txt"), "utf8");
      const requestId = command.match(/^request_id=(.+)$/m)?.[1];
      if (!requestId) return;
      writeFileSync(join(root, "response.txt"), [
        "protocol=1",
        "boot_id=test-boot-1",
        `request_id=${requestId}`,
        "accepted=1",
        "status=applied",
        "message=God Mode enabled and read back.",
        "readback=1",
        "",
      ].join("\n"));
    } catch {
      // The atomic command file may not exist during the first poll.
    }
  }, 10);
}

describe("local Dawnwalker bridge transport", () => {
  afterEach(() => {
    fileOperationMock.removeAttempts = 0;
    fileOperationMock.removeFailures.splice(0);
    fileOperationMock.renameAttempts = 0;
    fileOperationMock.renameFailures.splice(0);
    for (const root of temporaryRoots.splice(0)) rmSync(root, { recursive: true, force: true });
  });

  it("fails closed for stale handshakes and unadvertised capabilities", async () => {
    const root = makeRoot();
    const transport = createBridgeTransport(root, new Set(["player:god-mode"]));
    expect(await transport.status()).toEqual({ connected: false, capabilities: [], active: [] });

    writeReady(root, "");
    const result = await transport.dispatch({ capability: "player:god-mode", value: true });
    expect(result).toMatchObject({ accepted: false, status: "rejected", requestId: "not-advertised" });
    expect(() => readFileSync(join(root, "command.txt"), "utf8")).toThrow();
  });

  it("writes a session-bound allowlisted command and accepts only its matched response", async () => {
    const root = makeRoot();
    const transport = createBridgeTransport(root, new Set(["player:god-mode"]));
    writeReady(root, "player:god-mode");

    const responder = startAcceptedResponder(root);

    const result = await transport.dispatch({ capability: "player:god-mode", value: true });
    clearInterval(responder);
    expect(result).toMatchObject({ accepted: true, status: "applied", readback: "1" });
    expect(readFileSync(join(root, "command.txt"), "utf8")).toContain("capability=player:god-mode");
  });

  it("filters unknown capabilities out of the ready handshake", async () => {
    const root = makeRoot();
    const transport = createBridgeTransport(root, new Set(["player:god-mode"]));
    writeReady(root, "player:god-mode,player:imaginary-mode,player:god-mode");
    expect(await transport.status()).toMatchObject({
      connected: true,
      capabilities: ["player:god-mode"],
      capabilitySetExact: false,
    });
  });

  it("keeps a later command queued until a deferred unblock verdict arrives", async () => {
    const root = makeRoot();
    const capabilities = "player:unblock-trait,player:god-mode";
    const transport = createBridgeTransport(root, new Set(capabilities.split(",")));
    writeReady(root, capabilities);
    let firstRequestId: string | undefined;
    let firstRequestSeenAt = 0;
    let deferredAnswered = false;
    let nextCommandArrivedEarly = false;
    const responder = setInterval(() => {
      writeReady(root, capabilities);
      let command: string;
      try {
        command = readFileSync(join(root, "command.txt"), "utf8");
      } catch {
        // Command publication is asynchronous; the first poll may precede it.
        return;
      }
      const requestId = command.match(/^request_id=(.+)$/m)?.[1];
      if (!requestId) return;
      if (!firstRequestId) {
        firstRequestId = requestId;
        firstRequestSeenAt = Date.now();
      }
      if (requestId === firstRequestId && Date.now() - firstRequestSeenAt < 6_100) return;
      if (requestId !== firstRequestId && !deferredAnswered) nextCommandArrivedEarly = true;
      if (requestId === firstRequestId) deferredAnswered = true;
      writeFileSync(join(root, "response.txt"), [
        "protocol=1", "boot_id=test-boot-1", `request_id=${requestId}`,
        "accepted=1", "status=applied", "message=Exact readback confirmed.",
        `readback=${requestId === firstRequestId ? "3" : "1"}`, "",
      ].join("\n"));
    }, 10);

    try {
      const unblock = transport.dispatch({ capability: "player:unblock-trait", value: "Human_CraftingOne|3" });
      const toggle = transport.dispatch({ capability: "player:god-mode", value: true });
      expect(await unblock).toMatchObject({ accepted: true, status: "applied", readback: "3" });
      expect(await toggle).toMatchObject({ accepted: true, status: "applied", readback: "1" });
      expect(nextCommandArrivedEarly).toBe(false);
    } finally {
      clearInterval(responder);
    }
  }, 10_000);

  it("rejects a stale expected session before writing a command", async () => {
    const root = makeRoot();
    const transport = createBridgeTransport(root, new Set(["player:god-mode"]));
    writeReady(root, "player:god-mode", "current-boot-1");

    const result = await transport.dispatch({
      capability: "player:god-mode",
      value: true,
      expectedBootId: "previous-boot-1",
    });

    expect(result).toMatchObject({ accepted: false, status: "rejected", requestId: "session-changed" });
    expect(() => readFileSync(join(root, "command.txt"), "utf8")).toThrow();
  });

  it("retries only bounded Windows remove and rename contention before dispatching", async () => {
    const root = makeRoot();
    const transport = createBridgeTransport(root, new Set(["player:god-mode"]), controlledFileOperations);
    writeReady(root, "player:god-mode");
    writeFileSync(join(root, "command.txt"), "previous command");
    fileOperationMock.removeFailures.push(makeFileSystemError("EBUSY"), makeFileSystemError("EPERM"));
    fileOperationMock.renameFailures.push(makeFileSystemError("EPERM"), makeFileSystemError("EBUSY"));
    const responder = startAcceptedResponder(root);

    const result = await transport.dispatch({ capability: "player:god-mode", value: true });
    clearInterval(responder);

    expect(result).toMatchObject({ accepted: true, status: "applied", readback: "1" });
    expect(fileOperationMock.removeAttempts).toBe(3);
    expect(fileOperationMock.renameAttempts).toBe(3);
  });

  it("does not retry non-contention file errors", async () => {
    const root = makeRoot();
    const transport = createBridgeTransport(root, new Set(["player:god-mode"]), controlledFileOperations);
    writeReady(root, "player:god-mode");
    writeFileSync(join(root, "command.txt"), "previous command");
    fileOperationMock.removeFailures.push(makeFileSystemError("EACCES"));

    const result = await transport.dispatch({ capability: "player:god-mode", value: true });

    expect(result).toMatchObject({ accepted: false, status: "rejected", requestId: "failed-safe" });
    expect(fileOperationMock.removeAttempts).toBe(1);
    expect(fileOperationMock.renameAttempts).toBe(0);
  });

  it("stops after the bounded contention retry budget is exhausted", async () => {
    const root = makeRoot();
    const transport = createBridgeTransport(root, new Set(["player:god-mode"]), controlledFileOperations);
    writeReady(root, "player:god-mode");
    writeFileSync(join(root, "command.txt"), "previous command");
    fileOperationMock.removeFailures.push(
      makeFileSystemError("EBUSY"),
      makeFileSystemError("EBUSY"),
      makeFileSystemError("EBUSY"),
      makeFileSystemError("EBUSY"),
      makeFileSystemError("EBUSY"),
    );

    const result = await transport.dispatch({ capability: "player:god-mode", value: true });

    expect(result).toMatchObject({ accepted: false, status: "rejected", requestId: "failed-safe" });
    expect(fileOperationMock.removeAttempts).toBe(5);
    expect(fileOperationMock.renameAttempts).toBe(0);
  });
});
