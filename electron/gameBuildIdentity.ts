import { createHash } from "node:crypto";
import { open, readFile, realpath, stat } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_installed_game_identity");

export type InstalledBuildIdentity = Readonly<{
  verified: boolean;
  reason: string;
  expectedBuildId?: string;
  actualBuildId?: string;
  gameVersion?: Readonly<{ version: string; changelist: string }>;
  // The changelist of the exact verified bytes, reported even when no marketing
  // version has been confirmed for this build.
  gameChangelist?: string;
}>;

type BuildContract = Readonly<{
  steam: Readonly<{ appId: string; buildId: string }>;
  executable: Readonly<{ relativePath: string; bytes: number; sha256: string }>;
  gameVersion?: Readonly<{ version: string; changelist: string }>;
}>;

type FileIdentity = Readonly<{ size: bigint; mtimeNs: bigint; ctimeNs: bigint; ino: bigint }>;

function fingerprint(identity: FileIdentity): string {
  // Millisecond rounding can reuse a digest after a rapid same-size replacement.
  return [identity.size, identity.mtimeNs, identity.ctimeNs, identity.ino].join(":");
}

function contractFromJson(contents: string): BuildContract {
  const contract = JSON.parse(contents.replace(/^\uFEFF/, "")) as BuildContract;
  if (contract?.steam?.appId !== "3751260" || !/^\d+$/.test(contract.steam.buildId)
    || !Number.isSafeInteger(contract.executable?.bytes) || contract.executable.bytes <= 0
    || !/^[a-f\d]{64}$/i.test(contract.executable.sha256)) {
    throw new Error("Invalid build contract.");
  }
  const executablePath = contract.executable.relativePath;
  if (typeof executablePath !== "string" || isAbsolute(executablePath)
    || executablePath.split(/[\\/]/).some((part) => !part || part === "." || part === ".." || part.includes(":"))) {
    throw new Error("Invalid executable path.");
  }
  return contract;
}

function manifestField(contents: string, key: string): string {
  const matches = [...contents.matchAll(new RegExp(`"${key}"\\s+"([^"\\r\\n]+)"`, "g"))];
  if (matches.length !== 1) throw new Error(`Invalid manifest field ${key}.`);
  return matches[0][1];
}

async function readBoundedText(filePath: string, limit: number): Promise<string> {
  const identity = await stat(filePath);
  if (!identity.isFile() || identity.size > limit) throw new Error("Invalid identity file.");
  return readFile(filePath, "utf8");
}

async function hashStableExecutable(executablePath: string, expectedFingerprint: string): Promise<string> {
  const handle = await open(executablePath, "r");
  try {
    if (fingerprint(await handle.stat({ bigint: true })) !== expectedFingerprint) throw new Error("Executable changed before validation.");
    const digest = createHash("sha256");
    for await (const chunk of handle.createReadStream({ autoClose: false })) digest.update(chunk);
    if (fingerprint(await handle.stat({ bigint: true })) !== expectedFingerprint
      || fingerprint(await stat(executablePath, { bigint: true })) !== expectedFingerprint) {
      throw new Error("Executable changed during validation.");
    }
    return digest.digest("hex").toUpperCase();
  } finally {
    await handle.close();
  }
}

export function createGameBuildInspector(paths: Readonly<{ contractPath: string; manifestPath: string }>) {
  let cachedDigest: Readonly<{ key: string; digest: Promise<string> }> | undefined;

  async function inspectInstalledBuild(): Promise<InstalledBuildIdentity> {
    let expectedBuildId: string | undefined;
    let actualBuildId: string | undefined;
    try {
      const [contractContents, manifest] = await Promise.all([
        readBoundedText(paths.contractPath, 128 * 1024),
        readBoundedText(paths.manifestPath, 128 * 1024),
      ]);
      const contract = contractFromJson(contractContents);
      expectedBuildId = contract.steam.buildId;
      const manifestBuildId = manifestField(manifest, "buildid");
      if (manifestField(manifest, "appid") !== contract.steam.appId || !/^\d+$/.test(manifestBuildId)) {
        throw new Error("Unexpected Steam application.");
      }
      actualBuildId = manifestBuildId;
      if (actualBuildId !== expectedBuildId) {
        cachedDigest = undefined;
        return { verified: false, expectedBuildId, actualBuildId,
          reason: `Installed build ${actualBuildId} differs from verified build ${expectedBuildId}. Runtime controls require a new compatibility test.` };
      }
      const installDirectory = manifestField(manifest, "installdir");
      if (!installDirectory || installDirectory === "." || installDirectory === ".." || /[\\/:]/.test(installDirectory)) {
        throw new Error("Invalid install directory.");
      }
      const gameRoot = await realpath(join(dirname(resolve(paths.manifestPath)), "common", installDirectory));
      const executablePath = await realpath(resolve(gameRoot, contract.executable.relativePath));
      const relativeExecutable = relative(gameRoot, executablePath);
      if (!relativeExecutable || relativeExecutable.startsWith(`..${sep}`) || isAbsolute(relativeExecutable)) {
        throw new Error("Executable resolved outside the game installation.");
      }
      const identity = await stat(executablePath, { bigint: true });
      if (!identity.isFile() || identity.size !== BigInt(contract.executable.bytes)) {
        return { verified: false, expectedBuildId, actualBuildId,
          reason: "The installed executable size differs from the verified build. Runtime controls are unavailable." };
      }
      const identityFingerprint = fingerprint(identity);
      const cacheKey = `${executablePath}:${identityFingerprint}`;
      // Filesystem timestamps can coalesce rapid writes even when exposed as nanoseconds.
      // Recently changed binaries must settle before their digests can be reused.
      const cacheSafeBefore = BigInt(Date.now() - 2000) * 1_000_000n;
      const recentlyChanged = identity.mtimeNs >= cacheSafeBefore || identity.ctimeNs >= cacheSafeBefore;
      if (recentlyChanged || cachedDigest?.key !== cacheKey) {
        cachedDigest = { key: cacheKey, digest: hashStableExecutable(executablePath, identityFingerprint) };
      }
      const digest = await cachedDigest.digest;
      if (fingerprint(await stat(executablePath, { bigint: true })) !== identityFingerprint) throw new Error("Executable changed during validation.");
      if (digest !== contract.executable.sha256.toUpperCase()) {
        return { verified: false, expectedBuildId, actualBuildId,
          reason: "The installed executable hash differs from the verified build. Runtime controls are unavailable." };
      }
      // Matching the complete pinned digest also matches the previously verified signed bytes.
      // Display metadata belongs to these exact bytes, never just a matching Steam label.
      const gameVersion = contract.gameVersion;
      const hasValidChangelist = typeof gameVersion?.changelist === "string" && /^\d+$/.test(gameVersion.changelist);
      const hasValidVersion = typeof gameVersion?.version === "string" && /^\d+\.\d+\.\d+$/.test(gameVersion.version)
        && hasValidChangelist;
      return { verified: true, expectedBuildId, actualBuildId,
        ...(hasValidVersion ? { gameVersion } : {}),
        ...(hasValidChangelist ? { gameChangelist: gameVersion!.changelist } : {}),
        reason: `Installed build ${actualBuildId} matches the verified executable.` };
    } catch {
      cachedDigest = undefined;
      return { verified: false, expectedBuildId, actualBuildId,
        reason: "The installed game identity could not be verified. Runtime controls are unavailable." };
    }
  }

  return Object.freeze({ inspectInstalledBuild });
}
