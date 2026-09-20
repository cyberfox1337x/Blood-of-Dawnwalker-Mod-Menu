import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, writeFile, rm, stat, utimes, rename } from "node:fs/promises";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join, resolve, sep, basename } from "node:path";
import { createImportedPayloadVerifier } from "./importedPayloadVerifier.js";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_payload_verifier_tests");
const folders: string[] = [];
afterEach(async () => { for (const folder of folders.splice(0)) {
  if (!resolve(folder).startsWith(resolve(tmpdir()) + sep) || !basename(folder).startsWith("dawnwalker-payload-test-")) throw new Error("Unexpected cleanup path");
  await rm(folder, { recursive: true, force: true });
} });
async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "dawnwalker-payload-test-")); folders.push(root);
  const file = join(root, "main.lua"), manifest = join(root, "manifest.json");
  await writeFile(file, "safe");
  const contract = { schema: 1, files: [{ path: "main.lua", sha256: createHash("sha256").update("safe").digest("hex") }] };
  await writeFile(manifest, JSON.stringify(contract));
  return { root, file, manifest, contract, verify: createImportedPayloadVerifier(root, manifest) };
}
describe("stable runtime payload verification", () => {
  it("hashes unchanged installed files once while validating each manifest", async () => {
    const f = await fixture(); expect(await f.verify()).toMatchObject({ verified: true, hashedFiles: 1 });
    expect(await f.verify()).toMatchObject({ verified: true, hashedFiles: 0 });
    f.contract.files[0].sha256 = "0".repeat(64); await writeFile(f.manifest, JSON.stringify(f.contract));
    expect((await f.verify()).verified).toBe(false);
  });
  it("detects same-size replacement even with restored mtime", async () => {
    const f = await fixture(); await f.verify(); const original = await stat(f.file);
    const replacement = join(f.root, "replacement.lua"); await writeFile(replacement, "evil");
    await utimes(replacement, original.atime, original.mtime); await rename(replacement, f.file);
    expect(await f.verify()).toMatchObject({ verified: false, hashedFiles: 1 });
  });
  it("does not preserve successful cache entries across an unknown failure", async () => {
    const f = await fixture(); await f.verify(); await writeFile(f.manifest, "invalid");
    expect((await f.verify()).verified).toBe(false);
    await writeFile(f.manifest, JSON.stringify(f.contract));
    expect(await f.verify()).toMatchObject({ verified: true, hashedFiles: 1 });
  });
  it("rejects traversal and duplicate file contracts", async () => {
    const f = await fixture(); f.contract.files[0].path = "../main.lua";
    await writeFile(f.manifest, JSON.stringify(f.contract)); expect((await f.verify()).verified).toBe(false);
    f.contract.files[0].path = "main.lua"; f.contract.files.push({ ...f.contract.files[0] });
    await writeFile(f.manifest, JSON.stringify(f.contract)); expect((await f.verify()).verified).toBe(false);
  });
  it("rehashes modified valid content after matching contract update", async () => {
    const f = await fixture(); await f.verify(); await writeFile(f.file, "new safe content");
    f.contract.files[0].sha256 = createHash("sha256").update("new safe content").digest("hex");
    await writeFile(f.manifest, JSON.stringify(f.contract));
    expect(await f.verify()).toMatchObject({ verified: true, hashedFiles: 1 });
  });
});
