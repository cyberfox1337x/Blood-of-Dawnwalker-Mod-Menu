import { afterEach, describe, expect, it } from "vitest";
import { link, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { createEyeSessionPngStore } from "./eyeFrameTransport.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("eye_session_png_store_tests");
const roots: string[] = [], bootId = "1788697238-427484", previewNonce = "0123456789abcdef0123456789abcdef";
async function fixture(beforeRemove?: Parameters<typeof createEyeSessionPngStore>[0]["beforeRemove"]) {
  const root = await mkdtemp(join(tmpdir(), "dawnwalker-eye-frame-test-")); roots.push(root);
  const directory = join(root, bootId); await mkdir(directory);
  const store = createEyeSessionPngStore({ bootId, previewNonce, trustedTestRoot: root, beforeRemove });
  const address = (sequence: number) => ({ bootId, previewNonce, sequence, fileName: `eye-live-${previewNonce}-${String(sequence).padStart(4, "0")}.png` });
  return { root, directory, store, address, path: (sequence: number) => join(directory, address(sequence).fileName) };
}
afterEach(async () => {
  for (const root of roots.splice(0)) {
    if (resolve(dirname(root)) !== resolve(tmpdir()) || !basename(root).startsWith("dawnwalker-eye-frame-test-")) throw new Error("Unsafe frame fixture cleanup");
    await rm(root, { recursive: true });
  }
});

// Every PNG read is attested twice by assertWindowsPlainPaths in eyeFrameTransport,
// which reads the Windows reparse attribute Node does not expose. That used to spawn
// PowerShell per call - ~1.2 s each, ~4.6 s per frame read, past vitest's 5 s default -
// and now runs on one reused worker at ~67 ms per attestation. The budget still exceeds
// vitest's default because the first attestation pays to start that worker, and
// PowerShell startup varies with what else the machine is doing.
const ATTESTED_READ_TIMEOUT_MS = 30000;
describe("owned native frame file lifecycle", () => {
  it("returns isolated bytes and removes only the exact consumed file once", async () => {
    const f = await fixture(); await writeFile(f.path(1), "native host bytes");
    const result = await f.store.read(f.address(1)); result.nativeBytes[0] = 0;
    expect((await readFile(f.path(1))).toString()).toBe("native host bytes");
    await result.remove(); await expect(stat(f.path(1))).rejects.toThrow();
    await expect(result.remove()).rejects.toThrow();
  }, ATTESTED_READ_TIMEOUT_MS);
  it("retains rewritten files instead of acknowledging or deleting them", async () => {
    const f = await fixture(); await writeFile(f.path(1), "original");
    const result = await f.store.read(f.address(1)); await writeFile(f.path(1), "modified");
    await expect(result.remove()).rejects.toThrow(/changed/);
    expect((await readFile(f.path(1))).toString()).toBe("modified");
  }, ATTESTED_READ_TIMEOUT_MS);
  it("retains the native file when preserving its original evidence fails", async () => {
    const f = await fixture(async () => { throw new Error("Archive unavailable"); });
    await writeFile(f.path(1), "original native bytes");
    const result = await f.store.read(f.address(1));
    await expect(result.remove()).rejects.toThrow("Archive unavailable");
    expect((await readFile(f.path(1))).toString()).toBe("original native bytes");
  }, ATTESTED_READ_TIMEOUT_MS);
  it("rejects cross-generation names, traversal and hard links", async () => {
    const f = await fixture(); await writeFile(f.path(1), "source");
    await expect(f.store.read({ ...f.address(1), fileName: "../outside.png" })).rejects.toThrow();
    await expect(f.store.read({ ...f.address(1), bootId: "1-2" })).rejects.toThrow();
    await link(f.path(1), join(f.directory, "another-name.png"));
    await expect(f.store.read(f.address(1))).rejects.toThrow(/single link/);
  }, ATTESTED_READ_TIMEOUT_MS);
  it("allows bounded empty partial exports only through explicit cleanup", async () => {
    const f = await fixture(); await writeFile(f.path(1), "");
    await expect(f.store.read(f.address(1))).rejects.toThrow();
    await f.store.discardKnown(f.address(1)); await expect(stat(f.path(1))).rejects.toThrow();
    await f.store.discardKnown(f.address(2));
    await expect(f.store.discardKnown(f.address(2))).rejects.toThrow(/consumed/);
  }, ATTESTED_READ_TIMEOUT_MS);
  it("enforces the two-file backlog and rejects consumed sequence replay", async () => {
    const f = await fixture(); for (const i of [1, 2, 3]) await writeFile(f.path(i), `frame${i}`);
    const first = await f.store.read(f.address(1)); await f.store.read(f.address(2));
    await expect(f.store.read(f.address(3))).rejects.toThrow(/backlog/);
    await first.remove(); await f.store.read(f.address(3));
    await expect(f.store.read(f.address(1))).rejects.toThrow();
  }, ATTESTED_READ_TIMEOUT_MS);
});
