import { randomUUID } from "node:crypto";
import { lstat, mkdir, open, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("configuration_files");

export function decodeConfiguration(bytes: Buffer, fileName: string): { text: string; encode: (text: string) => Buffer } {
  if (bytes[0] === 0xff && bytes[1] === 0xfe) {
    if (bytes.length % 2) throw new Error(`${fileName} has an invalid UTF-16 length.`);
    return { text: bytes.subarray(2).toString("utf16le"), encode: text => Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(text, "utf16le")]) };
  }
  const bom = bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf;
  const text = new TextDecoder("utf-8", { fatal: true }).decode(bom ? bytes.subarray(3) : bytes);
  if (text.includes("\0")) throw new Error(`Unsupported ${fileName} encoding.`);
  return { text, encode: value => Buffer.concat([bom ? Buffer.from([0xef, 0xbb, 0xbf]) : Buffer.alloc(0), Buffer.from(value)]) };
}

export async function readConfigurationFile(path: string, fileName: string) {
  try {
    const stat = await lstat(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 1024 * 1024) throw new Error(`${fileName} must be a regular file smaller than 1 MiB.`);
    return { bytes: await readFile(path), exists: true };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { bytes: Buffer.alloc(0), exists: false };
    throw error;
  }
}

export async function replaceConfigurationFile(path: string, bytes: Buffer) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  await writeFile(temporary, bytes, { flag: "wx" });
  try { await rename(temporary, path); }
  finally { await unlink(temporary).catch(error => { if (error.code !== "ENOENT") throw error; }); }
}

// Each settings owner retains its own in-process guard and named on-disk lock.
// Feature-specific validation and transaction journals remain with that owner.
export function createConfigurationOperation(backupDirectory: string, feature: string, requireClosed: () => Promise<void>) {
  let busy = false;
  return async function exclusive<T>(action: () => Promise<T>): Promise<T> {
    if (busy) throw new Error(`A ${feature} configuration operation is already in progress.`);
    busy = true;
    const lockPath = join(backupDirectory, `${feature}-operation.lock`);
    let lock: Awaited<ReturnType<typeof open>> | undefined;
    try {
      await requireClosed();
      await mkdir(backupDirectory, { recursive: true });
      try { lock = await open(lockPath, "wx"); }
      catch (error) {
        if ((error as NodeJS.ErrnoException).code === "EEXIST") throw new Error(`Another menu owns the ${feature} configuration lock. After a crash, close every menu and Dawnwalker before removing this exact lock file: ${lockPath}`);
        throw error;
      }
      return await action();
    } finally {
      try { if (lock) { await lock.close(); await unlink(lockPath); } }
      finally { busy = false; }
    }
  };
}
