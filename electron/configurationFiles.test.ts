import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createConfigurationOperation, decodeConfiguration, readConfigurationFile, replaceConfigurationFile } from "./configurationFiles.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("configuration_files_tests");
const directories: string[] = [];
afterEach(async () => { for (const path of directories.splice(0)) await rm(path, { recursive: true, force: true }); });
async function directory() {
  const path = await mkdtemp(join(tmpdir(), "configuration-files-"));
  directories.push(path);
  return path;
}

describe("shared configuration file behavior", () => {
  it.each([Buffer.from("value=1\r\n"), Buffer.from([239, 187, 191, 97]), Buffer.from([255, 254, 97, 0])])("round-trips the original encoding", bytes => {
    const decoded = decodeConfiguration(bytes, "Game.ini");
    expect(decoded.encode(decoded.text)).toEqual(bytes);
  });
  it("preserves named invalid encoding failures", () => {
    expect(() => decodeConfiguration(Buffer.from([255, 254, 0]), "Game.ini")).toThrow("Game.ini has an invalid UTF-16 length.");
    expect(() => decodeConfiguration(Buffer.from([0]), "Engine.ini")).toThrow("Unsupported Engine.ini encoding.");
    expect(() => decodeConfiguration(Buffer.from([255]), "Game.ini")).toThrow();
  });
  it("handles absent configuration and replaces exact bytes without temporary files", async () => {
    const folder = await directory();
    const path = join(folder, "Game.ini");
    expect(await readConfigurationFile(path, "Game.ini")).toEqual({ exists: false, bytes: Buffer.alloc(0) });
    await replaceConfigurationFile(path, Buffer.from("first"));
    await replaceConfigurationFile(path, Buffer.from("second"));
    expect(await readFile(path, "utf8")).toBe("second");
    expect(await readdir(folder)).toEqual(["Game.ini"]);
    await expect(readConfigurationFile(folder, "Game.ini")).rejects.toThrow("regular file");
  });
  it("rejects same-owner and cross-owner overlap, then releases after failure", async () => {
    const folder = await directory();
    const owner = createConfigurationOperation(folder, "fog", async () => undefined);
    const other = createConfigurationOperation(folder, "fog", async () => undefined);
    await owner(async () => {
      await expect(owner(async () => undefined)).rejects.toThrow("already in progress");
      await expect(other(async () => undefined)).rejects.toThrow("Another menu owns");
    });
    await expect(owner(async () => { throw new Error("operation failed"); })).rejects.toThrow("operation failed");
    await expect(other(async () => "recovered")).resolves.toBe("recovered");
    expect(await readdir(folder)).toEqual([]);
  });
  it("releases in-process guard when closed-game validation fails", async () => {
    const folder = await directory();
    let running = true;
    const owner = createConfigurationOperation(folder, "story-day", async () => { if (running) throw new Error("game running"); });
    await expect(owner(async () => undefined)).rejects.toThrow("game running");
    running = false;
    await expect(owner(async () => "allowed")).resolves.toBe("allowed");
  });
});

