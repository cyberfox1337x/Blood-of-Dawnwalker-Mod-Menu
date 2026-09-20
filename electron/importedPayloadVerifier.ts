import { createHash } from "node:crypto";
import { open, stat } from "node:fs/promises";
import { resolve, sep } from "node:path";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_payload_verifier");
type Identity = { size: bigint; mtimeNs: bigint; ctimeNs: bigint; ino: bigint };
const fingerprint = (identity: Identity) => [identity.size, identity.mtimeNs, identity.ctimeNs, identity.ino].join(":");
async function readStable(path: string, expected: string, limit: number): Promise<Buffer> {
  const handle = await open(path, "r");
  try {
    if (fingerprint(await handle.stat({ bigint: true })) !== expected) throw new Error("Runtime file changed before verification.");
    const chunks: Buffer[] = []; let bytes = 0;
    for await (const chunk of handle.createReadStream({ autoClose: false, highWaterMark: 64 * 1024 })) {
      bytes += chunk.length;
      if (bytes > limit) throw new Error("Runtime file exceeds verification limits.");
      chunks.push(chunk);
    }
    if (fingerprint(await handle.stat({ bigint: true })) !== expected || fingerprint(await stat(path, { bigint: true })) !== expected) {
      throw new Error("Runtime file changed during verification.");
    }
    return Buffer.concat(chunks);
  } finally { await handle.close(); }
}
export function createImportedPayloadVerifier(modRoot: string, manifestPath: string) {
  const cache = new Map<string, { fingerprint: string; digest: string }>();
  return async () => {
    let hashedFiles = 0;
    try {
      const manifestInfo = await stat(manifestPath, { bigint: true });
      if (!manifestInfo.isFile() || manifestInfo.size > 65536n) throw new Error("Packaged runtime manifest is invalid.");
      const bytes = await readStable(manifestPath, fingerprint(manifestInfo), 65536);
      const manifest = JSON.parse(bytes.toString("utf8")) as { schema: number; files: { path: string; sha256: string }[] };
      if (manifest.schema !== 1 || !Array.isArray(manifest.files) || !manifest.files.length || manifest.files.length > 128) throw new Error("Packaged runtime manifest is invalid.");
      const seen = new Set<string>();
      for (const file of manifest.files) {
        if (!file || typeof file.path !== "string" || typeof file.sha256 !== "string" || !/^[a-f\d]{64}$/i.test(file.sha256)
          || file.path.split(/[\\/]/).some(part => !part || part === "." || part === ".." || part.includes(":"))) throw new Error("Packaged runtime manifest contains an invalid file.");
        const target = resolve(modRoot, file.path), key = target.toLowerCase();
        if (!target.startsWith(resolve(modRoot) + sep) || seen.has(key)) throw new Error("Packaged runtime manifest contains an invalid path.");
        seen.add(key);
        const info = await stat(target, { bigint: true });
        if (!info.isFile() || info.size > 2097152n) throw new Error("Installed runtime file is invalid.");
        const current = fingerprint(info);
        let entry = cache.get(key);
        if (!entry || entry.fingerprint !== current) {
          cache.delete(key);
          const contents = await readStable(target, current, 2097152);
          entry = { fingerprint: current, digest: createHash("sha256").update(contents).digest("hex") };
          hashedFiles += 1;
          if (entry.digest !== file.sha256.toLowerCase()) throw new Error("Menu and installed runtime differ. Open the matching menu release or repair its runtime.");
          cache.set(key, entry);
        }
        if (entry.digest !== file.sha256.toLowerCase()) throw new Error("Menu and installed runtime differ. Open the matching menu release or repair its runtime.");
      }
      for (const key of cache.keys()) if (!seen.has(key)) cache.delete(key);
      return { verified: true, reason: "Runtime payload matches this menu.", hashedFiles };
    } catch (error) {
      cache.clear();
      const reason = error instanceof Error && !('code' in error) ? error.message : "Installed runtime files are missing or unreadable. Repair the runtime.";
      return { verified: false, reason, hashedFiles };
    }
  };
}
