import { link, lstat, mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile } from "node:fs/promises";
import { existsSync, watch, type FSWatcher } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, it } from "vitest";
import { createEyeNativeChannel, type EyeNativeCommand } from "./eyeNativeChannel.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_native_channel_tests");

const watchers: FSWatcher[] = [];
const bootId = "1788670000-123456", ownerId = "a".repeat(32);
const roots: string[] = [], channels: Awaited<ReturnType<typeof createEyeNativeChannel>>[] = [];
const readyText = `wire_version=1\nboot_id=${bootId}\nowner_id=${ownerId}\nbuild_id=25129649\nexecutable_sha256=7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853\ntransport=eye-session-prototype\nproduction_ready=false\n`;

async function fixture(ready = readyText) {
  const root = await mkdtemp(join(tmpdir(), "dawnwalker-eye-channel-test-")); roots.push(root);
  const channel = await createEyeNativeChannel({ bootId, ownerId, trustedTestRoot: root }); channels.push(channel);
  await writeFile(join(channel.directory, "channel.ready"), ready);
  return { channel, root };
}
async function absent(path: string) { try { await lstat(path); return false; } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return true; throw error; } }
async function commandAt(directory: string): Promise<string> {
  const deadline = Date.now() + 10000, path = join(directory, "command.txt");
  while (await absent(path)) {
    if (Date.now() > deadline) throw new Error("Mock producer did not receive a command.");
    await new Promise(resolveWait => setTimeout(resolveWait, 10));
  }
  return readFile(path, "utf8");
}
async function respond(directory: string, change = (text: string) => text) {
  const command = await commandAt(directory);
  await writeFile(join(directory, "response.txt"), change(command) + "status=fixture-only\n");
  return command;
}

afterEach(async () => {
  for (const watcher of watchers.splice(0)) watcher.close();
  for (const channel of channels.splice(0)) channel.dispose();
  for (const root of roots.splice(0)) {
    checkFixture(root);
    await rm(root, { recursive: true, force: true });
  }
});
function checkFixture(root: string) {
  if (dirname(resolve(root)) !== resolve(tmpdir()) || !basename(root).startsWith("dawnwalker-eye-channel-test-")) throw new Error("Fixture cleanup escaped its named temporary root.");
}

describe("unactivated native eye file channel", () => {
  it("verifies transport metadata, publishes one immutable command and removes command before its corresponding response", async () => {
    const { channel } = await fixture();
    const transport = await channel.waitForTransport();
    expect(transport.productionReady).toBe(false);
    const removals: string[] = [];
    let responsePresentAtCommandRemoval = false;
    // libuv's Windows watcher requires the canonical long directory spelling.
    watchers.push(watch(await realpath(channel.directory), (event, file) => {
      const name = file?.toString();
      if (event !== "rename" || !name || !["command.txt", "response.txt"].includes(name) || existsSync(join(channel.directory, name))) return;
      if (name === "command.txt") responsePresentAtCommandRemoval = existsSync(join(channel.directory, "response.txt"));
      if (!removals.includes(name)) removals.push(name);
    }));
    const producer = respond(channel.directory);
    const result = await channel.send({ operation: "inspect" });
    const command = await producer;
    expect(command).toContain("command_sequence=1\n");
    expect(result.request.request_id).toMatch(/^[a-f0-9]{32}$/);
    expect(result.response.status).toBe("fixture-only");
    expect(result.productionReady).toBe(false);
    expect(result.commandSha256).toMatch(/^[a-f0-9]{64}$/);
    expect(result.timing.hostReceiptReceivedAtMs).toBeGreaterThanOrEqual(result.timing.hostRequestSentAtMs);
    expect(result.timing.requestSequence).toBe(1);
    await new Promise(resolveWait => setTimeout(resolveWait, 50));
    expect(removals).toEqual(["command.txt", "response.txt"]);
    expect(responsePresentAtCommandRemoval).toBe(true);
    expect(await readFile(join(channel.directory, "channel.ready"), "utf8")).toBe(readyText);
    expect(await absent(join(channel.directory, "command.tmp"))).toBe(true);
  }, 20000);

  it("rejects concurrent commands without consuming their sequence and gives the next completed request a new identity", async () => {
    const { channel } = await fixture(); await channel.waitForTransport();
    const first = channel.send({ operation: "inspect" });
    await expect(channel.send({ operation: "inspect" })).rejects.toThrow(/outstanding/);
    const producer = respond(channel.directory); const result = await first; await producer;
    const nextProducer = respond(channel.directory); const next = await channel.send({ operation: "inspect" }); await nextProducer;
    expect(next.timing.requestSequence).toBe(2);
    expect(next.request.request_id).not.toBe(result.request.request_id);
    expect(channel.getState()).toEqual({ status: "open", busy: false, lastSequence: 2 });
  }, 20000);

  it("preserves mismatched responses and commands, latches failure and never automatically replays an operation", async () => {
    const { channel } = await fixture(); await channel.waitForTransport();
    const producer = respond(channel.directory, text => text.replace(/request_id=[a-f0-9]+/, "request_id=" + "f".repeat(32)));
    await expect(channel.send({ operation: "inspect" })).rejects.toThrow(/does not match/); await producer;
    expect(channel.getState().status).toBe("faulted");
    const original = await readFile(join(channel.directory, "command.txt"));
    await expect(channel.send({ operation: "inspect" })).rejects.toThrow();
    expect(await readFile(join(channel.directory, "command.txt"))).toEqual(original);
    expect(await absent(join(channel.directory, "response.txt"))).toBe(false);
  }, 20000);

  it("leaves timed-out publication as diagnostics and does not replay it after a late response", async () => {
    const { channel } = await fixture(); await channel.waitForTransport();
    await expect(channel.send({ operation: "inspect" }, 1000)).rejects.toThrow(/timeout|timed out/);
    const original = await readFile(join(channel.directory, "command.txt"), "utf8");
    await writeFile(join(channel.directory, "response.txt"), original);
    await expect(channel.send({ operation: "inspect" })).rejects.toThrow(/timeout|timed out/);
    expect(channel.getState().lastSequence).toBe(1);
    expect(await readFile(join(channel.directory, "command.txt"), "utf8")).toBe(original);
  }, 20000);

  it("rejects oversize or multiply linked responses without deleting either slot or the other link", async () => {
    for (const mode of ["oversize", "linked"] as const) {
      const { channel, root } = await fixture(); await channel.waitForTransport();
      const operation = channel.send({ operation: "inspect" });
      const rejection = expect(operation).rejects.toThrow(/bounded ordinary single-link/);
      const command = await commandAt(channel.directory);
      if (mode === "oversize") await writeFile(join(channel.directory, "response.txt"), Buffer.alloc(256 * 1024 + 1, 65));
      else {
        await writeFile(join(root, "preserved-response.txt"), command);
        await link(join(root, "preserved-response.txt"), join(channel.directory, "response.txt"));
      }
      await rejection;
      expect(await absent(join(channel.directory, "command.txt"))).toBe(false);
      expect(await absent(join(channel.directory, "response.txt"))).toBe(false);
      if (mode === "linked") expect(await readFile(join(root, "preserved-response.txt"), "utf8")).toBe(command);
      channel.dispose();
    }
  }, 30000);

  it("retains a changed command instead of removing it after a matching response arrives", async () => {
    const { channel } = await fixture(); await channel.waitForTransport();
    const operation = channel.send({ operation: "inspect" });
    const rejection = expect(operation).rejects.toThrow(/changed/);
    const command = await commandAt(channel.directory);
    await new Promise(resolveWait => setTimeout(resolveWait, 100));
    await writeFile(join(channel.directory, "command.txt"), command + "changed=true\n");
    await writeFile(join(channel.directory, "response.txt"), command);
    await rejection;
    expect(await absent(join(channel.directory, "response.txt"))).toBe(false);
    expect(await readFile(join(channel.directory, "command.txt"), "utf8")).toContain("changed=true");
  }, 20000);

  it("requires exact transport identity and refuses host-owned fields or invalid payloads before publication", async () => {
    const invalid = await fixture(readyText.replace("production_ready=false", "production_ready=true"));
    await expect(invalid.channel.waitForTransport()).rejects.toThrow(/identity differs/);
    const { channel } = await fixture(); await channel.waitForTransport();
    await expect(channel.send({ operation: "inspect", owner_id: "f".repeat(32) } as EyeNativeCommand)).rejects.toThrow(/host-owned/);
    await expect(channel.send({ operation: "inspect", code: "arbitrary" } as EyeNativeCommand)).rejects.toThrow(/Unknown/);
    expect(channel.getState().lastSequence).toBe(0);
    expect(await absent(join(channel.directory, "command.txt"))).toBe(true);
  }, 20000);

  it("refuses linked ancestors and never creates the owner inside their target", async () => {
    const root = await mkdtemp(join(tmpdir(), "dawnwalker-eye-channel-test-")); roots.push(root);
    const target = join(root, "retained-target"); await mkdir(target);
    await writeFile(join(target, "sentinel.txt"), "preserve");
    await symlink(target, join(root, bootId), process.platform === "win32" ? "junction" : "dir");
    await expect(createEyeNativeChannel({ bootId, ownerId, trustedTestRoot: root })).rejects.toThrow(/ordinary|alias/);
    expect(await readFile(join(target, "sentinel.txt"), "utf8")).toBe("preserve");
    expect(await absent(join(target, ownerId))).toBe(true);
  }, 20000);
});
