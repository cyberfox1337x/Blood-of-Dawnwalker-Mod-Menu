import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createStoryDaySettings, updateStoryDayConfiguration, handleStoryDayRequest } from "./storyDaySettings.js";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("story_day_configuration_tests");
const directories: string[] = [];
afterEach(async () => { for (const path of directories.splice(0)) await rm(path, { recursive: true, force: true }); });
async function fixture(running = false) {
  const directory = await mkdtemp(join(tmpdir(), "dawnwalker-story-day-test-")); directories.push(directory);
  const configurationPath = join(directory, "Game.ini");
  const options = { configurationPath, backupDirectory: join(directory, "backups"), isGameRunning: async () => running, isBuildVerified: async () => true };
  return { path: configurationPath, options, api: createStoryDaySettings(options) };
}
describe("91-value story configuration transactions", () => {
  it("preserves other sections and edits only the intended setting", () => {
    const before = "[Other]\r\nDaysToPass=8\r\n[/Script/Quest.QuestSettings]\r\n; note\r\nDaysToPass = 31 ; keep\r\nOther=Yes\r\n";
    expect(updateStoryDayConfiguration(Buffer.from(before)).toString()).toBe(before.replace("31 ; keep", "91 ; keep"));
  });
  it("preserves UTF16 BOM and rejects duplicate ambiguous entries", () => {
    const before = Buffer.concat([Buffer.from([255, 254]), Buffer.from("[/Script/Quest.QuestSettings]\r\nDaysToPass=31", "utf16le")]);
    const result = updateStoryDayConfiguration(before);
    expect(result.subarray(0, 2)).toEqual(before.subarray(0, 2));
    expect(result.subarray(2).toString("utf16le")).toContain("DaysToPass=91");
    expect(() => updateStoryDayConfiguration(Buffer.from("[/Script/Quest.QuestSettings]\nDaysToPass=31\nDaysToPass=32"))).toThrow(/duplicate/);
  });
  it("creates absent Game.ini, persists ownership across instances, and restores absence", async () => {
    const f = await fixture(); const baseline = await f.api.inspect();
    const applied = await f.api.apply({ expectedSha256: baseline.sha256 });
    expect(applied).toMatchObject({ enabled: true, owned: true, configuredDays: 91, restartRequired: true });
    expect(await readFile(applied.backupPath!)).toEqual(Buffer.alloc(0));
    const reopened = createStoryDaySettings(f.options);
    expect(await reopened.inspect()).toMatchObject({ enabled: true, owned: true });
    expect(await reopened.restore(applied.sha256)).toMatchObject({ exists: false, owned: false, enabled: false });
  });
  it("restores the exact original bytes including comments and newline style", async () => {
    const f = await fixture(); const original = Buffer.from("[Other]\r\nKeep=Yes\r\n[/Script/Quest.QuestSettings]\r\nDaysToPass=31");
    await writeFile(f.path, original); const applied = await f.api.apply({ expectedSha256: (await f.api.inspect()).sha256 });
    await f.api.restore(applied.sha256); expect(await readFile(f.path)).toEqual(original);
  });
  it("refuses stale inspection and all writes while the game runs", async () => {
    const f = await fixture(); const before = await f.api.inspect(); await writeFile(f.path, "[Other]\nKeep=Yes");
    await expect(f.api.apply({ expectedSha256: before.sha256 })).rejects.toThrow(/changed/);
    const running = await fixture(true);
    await expect(running.api.apply({ expectedSha256: (await running.api.inspect()).sha256 })).rejects.toThrow(/Close Dawnwalker/);
    expect((await running.api.inspect()).exists).toBe(false);
  });
  it("retains external changes and backup instead of overwriting during OFF", async () => {
    const f = await fixture(); const applied = await f.api.apply({ expectedSha256: (await f.api.inspect()).sha256 });
    await writeFile(f.path, (await readFile(f.path, "utf8")) + "[Other]\nUserChange=Yes\n");
    const changed = await f.api.inspect(); expect(changed.conflict).toBe(true);
    await expect(f.api.restore(changed.sha256)).rejects.toThrow(/outside this menu/);
    expect(await readFile(f.path, "utf8")).toContain("UserChange=Yes");
    expect(await readFile(applied.backupPath!)).toEqual(Buffer.alloc(0));
  });
  it("rejects unknown build and invalid IPC operation or payload", async () => {
    const f = await fixture(); const snapshot = await f.api.inspect();
    const unverified = createStoryDaySettings({ ...f.options, isBuildVerified: async () => false });
    await expect(unverified.apply({ expectedSha256: snapshot.sha256 })).rejects.toThrow(/build must be verified/);
    await expect(handleStoryDayRequest(f.api, "delete", snapshot.sha256)).rejects.toThrow(/Invalid/);
    await expect(handleStoryDayRequest(f.api, "apply", { expectedSha256: snapshot.sha256, path: "other" })).rejects.toThrow(/Invalid/);
    expect((await f.api.inspect()).exists).toBe(false);
  });
  it("refuses corrupt backups without touching the applied configuration", async () => {
    const f = await fixture(); const applied = await f.api.apply({ expectedSha256: (await f.api.inspect()).sha256 });
    await writeFile(applied.backupPath!, "corrupt");
    await expect(f.api.restore(applied.sha256)).rejects.toThrow(/hash mismatch/);
    expect((await f.api.inspect()).enabled).toBe(true);
  });
});
