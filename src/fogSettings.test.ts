// @vitest-environment node
import { mkdtemp, readFile, rm, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, it } from "vitest";
import { createFogSettings, updateFogConfiguration } from "../electron/fogSettings";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_fog_tests");
const directories: string[] = [];
afterEach(async () => { await Promise.all(directories.splice(0).map(directory => rm(directory, { recursive: true, force: true }))); });
async function fixture(initial?: Buffer, running = false) {
  const directory = await mkdtemp(join(tmpdir(), "dawnwalker-fog-test-")); directories.push(directory);
  const path = join(directory, "Engine.ini");
  if (initial) await writeFile(path, initial);
  return { path, api: createFogSettings({ configurationPath: path, backupDirectory: join(directory, "backups"), isGameRunning: async () => running }) };
}
describe("fog configuration transactions", () => {
  it("preserves unrelated settings, encoding and exact original across repeated changes and restart", async () => {
    const original = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from("; my preferences\r\n[SystemSettings]\r\nr.Fog=1 ; keep\r\nr.ShadowQuality=4\r\n[Other]\r\nx=y\r\n", "utf16le")]);
    const { path, api } = await fixture(original);
    let state = await api.inspect();
    state = await api.apply({ expectedSha256: state.sha256, fog: false, volumetricFog: true });
    expect(state.configured).toEqual({ "r.Fog": "0", "r.VolumetricFog": "1" });
    expect((await readFile(path)).subarray(2).toString("utf16le")).toContain("r.ShadowQuality=4\r\n[Other]\r\nx=y");
    state = await api.apply({ expectedSha256: state.sha256, fog: true, volumetricFog: false });
    const reopened = createFogSettings({ configurationPath: path, backupDirectory: join(path, "..", "backups"), isGameRunning: async () => false });
    await reopened.restore(state.sha256);
    expect(await readFile(path)).toEqual(original);
    expect((await reopened.inspect()).owned).toBe(false);
  });
  it("restores absence for a newly created Engine.ini and retains backup", async () => {
    const { path, api } = await fixture();
    const state = await api.apply({ expectedSha256: (await api.inspect()).sha256, fog: false, volumetricFog: false });
    await api.restore(state.sha256);
    await expect(readFile(path)).rejects.toMatchObject({ code: "ENOENT" });
    expect(await readFile(state.backupPath!)).toEqual(Buffer.alloc(0));
  });
  it("refuses changes while running and refuses stale revisions", async () => {
    const live = await fixture(Buffer.from("[Other]\nx=1"), true);
    await expect(live.api.apply({ expectedSha256: (await live.api.inspect()).sha256, fog: false, volumetricFog: false })).rejects.toThrow("Close Dawnwalker");
    const stopped = await fixture();
    await expect(stopped.api.apply({ expectedSha256: "stale", fog: false, volumetricFog: false })).rejects.toThrow("changed");
  });
  it("does not overwrite later user changes or corrupted backups on restore", async () => {
    const { path, api } = await fixture(Buffer.from("[Other]\nx=1"));
    let state = await api.apply({ expectedSha256: (await api.inspect()).sha256, fog: false, volumetricFog: false });
    const written = await readFile(path);
    await writeFile(path, Buffer.concat([written, Buffer.from("; user change")]));
    await expect(api.restore(state.sha256)).rejects.toThrow("changed outside");
    await writeFile(path, written);
    state = await api.inspect();
    await writeFile(state.backupPath!, "corrupt");
    await expect(api.restore(state.sha256)).rejects.toThrow("hash mismatch");
    expect(await readFile(path)).toEqual(written);
  });
  it("rejects ambiguous sections, conflicting values and invalid encodings", () => {
    for (const text of ["[Other]\nr.Fog=1", "[SystemSettings]\nr.Fog=0\nr.Fog=1", "a\0b"]) expect(() => updateFogConfiguration(Buffer.from(text), false, false)).toThrow();
    expect(() => updateFogConfiguration(Buffer.from([0xff]), false, false)).toThrow();
  });
  it("recovers a journal persisted before a failed configuration rename", async () => {
    const original = Buffer.from("[SystemSettings]\nr.Fog=1\n");
    const { path, api } = await fixture(original);
    let state = await api.apply({ expectedSha256: (await api.inspect()).sha256, fog: false, volumetricFog: false });
    // Reproduce the interrupted commit: journal and verified backup exist, but
    // Engine.ini still contains the pre-commit bytes.
    await writeFile(path, original);
    state = await api.inspect();
    state = await api.apply({ expectedSha256: state.sha256, fog: false, volumetricFog: true });
    expect(state.configured["r.Fog"]).toBe("0");
    await writeFile(path, original); // Restore committed, journal cleanup interrupted.
    state = await api.inspect();
    expect((await api.restore(state.sha256)).owned).toBe(false);
    expect(await readFile(path)).toEqual(original);
  });

  it("refuses unknown process status instead of treating it as a stopped game", async () => {
    const original = Buffer.from("[Other]\nx=1\n"); const { path } = await fixture(original);
    const api = createFogSettings({ configurationPath: path, backupDirectory: join(path, "..", "backups"), isGameRunning: async () => undefined as unknown as boolean });
    await expect(api.apply({ expectedSha256: (await api.inspect()).sha256, fog: false, volumetricFog: false })).rejects.toThrow("Process status must be verified");
    expect(await readFile(path)).toEqual(original);
  });

  it("serializes independent menu instances before either can replace the shared recovery journal", async () => {
    const original = Buffer.from("[Other]\nx=1\n"); const { path } = await fixture(original);
    let unblock!: () => void; let entered!: () => void;
    const blocked = new Promise<void>(resolve => { unblock = resolve; });
    const atBackup = new Promise<void>(resolve => { entered = resolve; });
    let checks = 0;
    const first = createFogSettings({ configurationPath: path, backupDirectory: join(path, "..", "backups"), isGameRunning: async () => { if (++checks === 2) { entered(); await blocked; } return false; } });
    const second = createFogSettings({ configurationPath: path, backupDirectory: join(path, "..", "backups"), isGameRunning: async () => false });
    const before = await first.inspect();
    const pending = first.apply({ expectedSha256: before.sha256, fog: false, volumetricFog: true });
    try {
      await atBackup;
      await expect(second.apply({ expectedSha256: before.sha256, fog: true, volumetricFog: false })).rejects.toThrow("Another menu owns");
      expect(await readFile(path)).toEqual(original);
    } finally { unblock(); }
    const applied = await pending;
    await second.restore(applied.sha256);
    expect(await readFile(path)).toEqual(original);
  });

  it("refuses a game start after journal persistence and recovers the untouched baseline", async () => {
    const original = Buffer.from("[Other]\nx=1\n"); const { path } = await fixture(original);
    let checks = 0;
    const api = createFogSettings({ configurationPath: path, backupDirectory: join(path, "..", "backups"), isGameRunning: async () => ++checks === 3 });
    await expect(api.apply({ expectedSha256: (await api.inspect()).sha256, fog: false, volumetricFog: false })).rejects.toThrow("Close Dawnwalker");
    expect(await readFile(path)).toEqual(original);
    const pending = await api.inspect(); expect(pending.owned).toBe(true);
    expect(await readFile(pending.backupPath!)).toEqual(original);
    expect((await api.restore(pending.sha256)).owned).toBe(false);
  });

  it("preserves an external edit made between journal persistence and configuration replacement", async () => {
    const original = Buffer.from("[Other]\nx=1\n"); const external = Buffer.from("[Other]\nx=2\n"); const { path } = await fixture(original);
    let checks = 0;
    const api = createFogSettings({ configurationPath: path, backupDirectory: join(path, "..", "backups"), isGameRunning: async () => { if (++checks === 3) await writeFile(path, external); return false; } });
    await expect(api.apply({ expectedSha256: (await api.inspect()).sha256, fog: false, volumetricFog: false })).rejects.toThrow("changed before commit");
    expect(await readFile(path)).toEqual(external);
    const pending = await api.inspect(); expect(pending.owned).toBe(true);
    expect(await readFile(pending.backupPath!)).toEqual(original);
    await expect(api.restore(pending.sha256)).rejects.toThrow("changed outside");
    expect(await readFile(path)).toEqual(external);
  });

  it("retains a stale lock after a crash and resumes existing journal recovery after deliberate lock removal", async () => {
    const original = Buffer.from("[Other]\nx=1\n"); const { path, api } = await fixture(original);
    const state = await api.apply({ expectedSha256: (await api.inspect()).sha256, fog: false, volumetricFog: false });
    await writeFile(path, original); // Simulate journal persistence before the configuration commit.
    const lockPath = join(path, "..", "backups", "fog-operation.lock");
    await writeFile(lockPath, "interrupted menu lock", { flag: "wx" });
    const reopened = createFogSettings({ configurationPath: path, backupDirectory: join(path, "..", "backups"), isGameRunning: async () => false });
    const pending = await reopened.inspect();
    await expect(reopened.restore(pending.sha256)).rejects.toThrow("After a crash, close every menu and Dawnwalker");
    await expect(reopened.restore(pending.sha256)).rejects.toThrow(lockPath);
    expect(await readFile(lockPath, "utf8")).toBe("interrupted menu lock");
    expect(await readFile(state.backupPath!)).toEqual(original);
    expect(await readFile(path)).toEqual(original);
    await unlink(lockPath); // Models the documented action with both menu instances and game stopped.
    expect((await reopened.restore(pending.sha256)).owned).toBe(false);
    expect(await readFile(path)).toEqual(original);
  });
});
