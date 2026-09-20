// @vitest-environment node
import { createHash } from "node:crypto";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createGameBuildInspector } from "../electron/gameBuildIdentity";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_installed_game_identity_tests");

const roots: string[] = [];

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "dawnwalker-build-identity-test-"));
  roots.push(root);
  const manifestPath = join(root, "appmanifest_3751260.acf");
  const executablePath = join(root, "common", "Dawnwalker", "Dawnwalker", "Binaries", "Win64", "Dawnwalker.exe");
  const contractPath = join(root, "official-build.json");
  mkdirSync(dirname(executablePath), { recursive: true });
  const contents = Buffer.from("verified executable fixture");
  writeFileSync(executablePath, contents);
  const contract = {
    steam: { appId: "3751260", buildId: "25107392" },
    executable: { relativePath: "Dawnwalker/Binaries/Win64/Dawnwalker.exe", bytes: contents.length,
      sha256: createHash("sha256").update(contents).digest("hex") },
  };
  writeFileSync(contractPath, JSON.stringify(contract));
  function writeManifest(buildId = "25107392", installDirectory = "Dawnwalker") {
    writeFileSync(manifestPath, `"AppState" { "appid" "3751260" "buildid" "${buildId}" "installdir" "${installDirectory}" }`);
  }
  writeManifest();
  return { contractPath, manifestPath, executablePath, contract, writeManifest,
    inspector: createGameBuildInspector({ contractPath, manifestPath }) };
}

afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe("installed game build identity", () => {
  it("exposes the public game version only for the exact verified executable", async () => {
    const { inspector, contractPath, contract, writeManifest, executablePath } = fixture();
    const gameVersion = { version: "1.0.3", changelist: "257186" };
    writeFileSync(contractPath, JSON.stringify({ ...contract, gameVersion }));
    expect(await inspector.inspectInstalledBuild()).toMatchObject({ verified: true, gameVersion });
    writeManifest("25129649");
    expect((await inspector.inspectInstalledBuild()).gameVersion).toBeUndefined();
    writeManifest();
    const changed = readFileSync(executablePath);
    changed[0] ^= 1;
    writeFileSync(executablePath, changed);
    expect((await inspector.inspectInstalledBuild()).gameVersion).toBeUndefined();
    rmSync(executablePath);
    expect((await inspector.inspectInstalledBuild()).gameVersion).toBeUndefined();
  });

  it("leaves missing or malformed display metadata unavailable without changing compatibility", async () => {
    const { inspector, contractPath, contract } = fixture();
    expect(await inspector.inspectInstalledBuild()).toMatchObject({ verified: true });
    expect((await inspector.inspectInstalledBuild()).gameVersion).toBeUndefined();
    for (const gameVersion of [null, {}, { version: "invalid", changelist: "257186" },
      { version: "1.0.3", changelist: "invalid" }, { version: 103, changelist: "257186" }]) {
      writeFileSync(contractPath, JSON.stringify({ ...contract, gameVersion }));
      const identity = await inspector.inspectInstalledBuild();
      expect(identity.verified).toBe(true);
      expect(identity.gameVersion).toBeUndefined();
    }
  });

  it("accepts exact pinned bytes and rejects a Steam update on the next call", async () => {
    const { inspector, writeManifest } = fixture();
    expect(await inspector.inspectInstalledBuild()).toMatchObject({ verified: true, actualBuildId: "25107392" });
    writeManifest("25129649");
    expect(await inspector.inspectInstalledBuild()).toMatchObject({ verified: false, actualBuildId: "25129649" });
  });

  it("invalidates the digest cache for a same-size executable replacement", async () => {
    const { inspector, executablePath } = fixture();
    expect((await inspector.inspectInstalledBuild()).verified).toBe(true);
    const changed = readFileSync(executablePath);
    changed[0] ^= 1;
    writeFileSync(executablePath, changed);
    const result = await inspector.inspectInstalledBuild();
    expect(result.verified).toBe(false);
    expect(result.reason).toContain("hash differs");
  });

  it("does not reuse digests across rapid same-size rewrites", async () => {
    const { inspector, executablePath } = fixture();
    const original = readFileSync(executablePath);
    const changed = Buffer.from(original);
    changed[0] ^= 1;
    for (let cycle = 0; cycle < 10; cycle += 1) {
      writeFileSync(executablePath, original);
      expect((await inspector.inspectInstalledBuild()).verified).toBe(true);
      writeFileSync(executablePath, changed);
      expect((await inspector.inspectInstalledBuild()).verified).toBe(false);
    }
  });

  it("rejects missing files, wrong lengths, and malformed manifests", async () => {
    const { inspector, executablePath, manifestPath, writeManifest } = fixture();
    writeFileSync(executablePath, "short");
    expect((await inspector.inspectInstalledBuild()).verified).toBe(false);
    writeFileSync(manifestPath, '"buildid" "25107392" "buildid" "25129649"');
    expect((await inspector.inspectInstalledBuild()).verified).toBe(false);
    writeFileSync(manifestPath, '"appid" "999" "buildid" "25129649"');
    expect(await inspector.inspectInstalledBuild()).toMatchObject({ verified: false, actualBuildId: undefined });
    writeManifest("invalid-build-id");
    expect(await inspector.inspectInstalledBuild()).toMatchObject({ verified: false, actualBuildId: undefined });
    writeManifest();
    rmSync(executablePath);
    expect((await inspector.inspectInstalledBuild()).verified).toBe(false);
  });

  it("refuses path traversal in both the manifest and build contract", async () => {
    const { inspector, contractPath, contract, writeManifest } = fixture();
    writeManifest("25107392", "../outside");
    expect((await inspector.inspectInstalledBuild()).verified).toBe(false);
    writeManifest();
    contract.executable.relativePath = "../../outside.exe";
    writeFileSync(contractPath, JSON.stringify(contract));
    expect((await inspector.inspectInstalledBuild()).verified).toBe(false);
  });
});
