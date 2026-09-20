import { createHash } from "node:crypto";
import { link, mkdir, mkdtemp, open, readFile, rm, symlink, truncate, utimes, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { deflateSync } from "node:zlib";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createNativeEyePngEvidenceConsumer, inspectArchivedNativeEyePng, inspectNativeEyePng, inspectNativeEyePngEvidence, type NativeEyeExportIdentity } from "../electron/eyeFrameTransport";
import type { EyePreviewFrame } from "./eyeAppearanceContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_frame_transport_tests");
// Each PNG read is attested twice by assertWindowsPlainPaths, which reads the Windows
// reparse attribute Node does not expose. That used to spawn PowerShell per call at
// ~1.2 s each; it now runs on one reused worker at ~67 ms per attestation. The budget
// below covers the first call, which still pays for starting that worker, on a machine
// under load.
const ATTESTED_READ_TIMEOUT_MS = 30000;

const roots: string[] = [];
const bootId = "1788660000-123456";
const nonce = "0123456789abcdef0123456789abcdef";

function pngChunk(name: string, data: Buffer): Buffer {
  const type = Buffer.from(name, "ascii");
  let checksum = 0xffffffff;
  for (const byte of Buffer.concat([type, data])) {
    checksum ^= byte;
    for (let bit = 0; bit < 8; bit += 1) checksum = (checksum & 1) ? ((checksum >>> 1) ^ 0xedb88320) : (checksum >>> 1);
  }
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE((checksum ^ 0xffffffff) >>> 0);
  return Buffer.concat([length, type, data, crc]);
}

function testPng(width = 2048, height = 2048, raw?: Buffer): Buffer {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(raw ?? Buffer.alloc((width * 4 + 1) * height))), pngChunk("IEND", Buffer.alloc(0))]);
}

const png = testPng();

function testIdentity(): NativeEyeExportIdentity {
  const object = (name: string, address: number) => ({ name, address: String(address) });
  return { player: object("Player Test", 1), world: object("World Test", 2), form: 0, is_wolf_form: false,
    doll: object("Doll Test", 3), capture: object("Capture Test", 4), head: object("Head Test", 5),
    head_asset: object("HeadAsset Test", 6), target: object("RenderTarget Test", 7),
    head_materials: [{ ...object("Material Test", 8), slot: 0, slot_name: "Test Slot", dynamic: false }] };
}

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "dawnwalker-eye-frame-test-"));
  roots.push(root);
  const sessionDirectory = join(root, bootId);
  await mkdir(sessionDirectory);
  const fileName = `eye-frame-${nonce}.png`;
  const filePath = join(sessionDirectory, fileName);
  await writeFile(filePath, png);
  const now = Math.floor(Date.now() / 1000) * 1000;
  await utimes(filePath, now / 1000, now / 1000);
  const expectedIdentity = testIdentity();
  const window = { nonce, intent: "eye-readback-export" as const, issuedAtMs: now - 1000, expiresAtMs: now + 119000 };
  const receipt = { ok: true, schema: 2, operation: "export", production_capabilities: "none", kind: "native-eye-frame-export-evidence", nonce, boot_id: bootId,
    file_name: fileName, export_invoked: true, capture_requested: false, width: 2048, height: 2048, render_target_format: 2, capture_source: 9,
    export_started_at_epoch_ms: now, export_completed_at_epoch_ms: now,
    capture_timestamp_known: false, frame_verified: false, preview_verified: false, gameplay_verified: false, identity: expectedIdentity };
  const options = { sessionDirectory, bootId, expectedIdentity, now: () => now + 1000 };
  return { root, filePath, fileName, sessionDirectory, now, window, receipt, options };
}

afterEach(async () => {
  for (const root of roots.splice(0)) {
    const absolute = resolve(root);
    if (dirname(absolute) !== resolve(tmpdir()) || !basename(absolute).startsWith("dawnwalker-eye-frame-test-")) throw new Error("Test cleanup target escaped its temporary fixture directory.");
    await rm(absolute, { recursive: true, force: true });
  }
});

describe("bounded native eye PNG evidence transport", () => {
  it("binds the exact native receipt and immutable PNG while keeping evidence separate from a live preview frame", async () => {
    const test = await fixture();
    const openFile = vi.fn(open);
    const consumer = createNativeEyePngEvidenceConsumer(test.options, { openFile });
    const result = await consumer.consume(test.window, test.receipt);
    expect(result.sha256).toBe(createHash("sha256").update(png).digest("hex"));
    expect(Buffer.from(result.pngBytes)).toEqual(png);
    expect(result.width).toBe(2048);
    expect(result.previewVerified).toBe(false);
    expect(result.capturedAtMs).toBeNull();
    expect(result.receipt.identity).toEqual(testIdentity());
    // @ts-expect-error A one-shot export has no production frame identity/revision/freshness proof.
    const productionFrame: EyePreviewFrame = result;
    expect(productionFrame).not.toHaveProperty("eyeRevision");
    await expect(consumer.consume(test.window, test.receipt)).rejects.toThrow(/consumed/);
  }, ATTESTED_READ_TIMEOUT_MS);

  it("rejects directory escapes, boot mismatch and nonce filenames before opening image content", async () => {
    const test = await fixture();
    expect(() => createNativeEyePngEvidenceConsumer({ ...test.options, sessionDirectory: "relative" })).toThrow(/absolute/);
    expect(() => createNativeEyePngEvidenceConsumer({ ...test.options, bootId: "another-boot" })).toThrow(/boot/);
    const openFile = vi.fn(open);
    const consumer = createNativeEyePngEvidenceConsumer(test.options, { openFile });
    await expect(consumer.consume({ ...test.window, nonce: "../escape" }, test.receipt)).rejects.toThrow(/nonce/);
    await expect(consumer.consume(test.window, { ...test.receipt, file_name: "../outside.png" })).rejects.toThrow(/receipt/);
    expect(openFile).not.toHaveBeenCalled();
  });

  it("rejects stale, future, changed-identity and fabricated verified metadata before reading the PNG", async () => {
    const test = await fixture();
    const openFile = vi.fn(open);
    const consumer = createNativeEyePngEvidenceConsumer(test.options, { openFile });
    await expect(consumer.consume({ ...test.window, expiresAtMs: test.now - 1 }, test.receipt)).rejects.toThrow(/stale/);
    await expect(consumer.consume({ ...test.window, issuedAtMs: test.now + 1001 }, test.receipt)).rejects.toThrow(/future/);
    for (const receipt of [
      { ...test.receipt, schema: 1 },
      { ...test.receipt, operation: "camera-roundtrip" },
      { ...test.receipt, production_capabilities: "eyeAppearance" },
      { ...test.receipt, capture_requested: true },
      { ...test.receipt, boot_id: "1788660000-654321" },
      { ...test.receipt, export_completed_at_epoch_ms: test.now + 2000 },
      { ...test.receipt, frame_verified: true },
      { ...test.receipt, identity: { ...test.receipt.identity, form: 1 } },
      { ...test.receipt, identity: { ...test.receipt.identity, target: { address: "99", name: "RenderTarget Test" } } },
      { ...test.receipt, identity: { ...test.receipt.identity, head_materials: [{ ...test.receipt.identity.head_materials[0], address: "99" }] } },
    ]) await expect(consumer.consume(test.window, receipt)).rejects.toThrow();
    expect(openFile).not.toHaveBeenCalled();
  });

  it("rejects oversized images and hard-linked frame files", async () => {
    const test = await fixture();
    await truncate(test.filePath, 16 * 1024 * 1024 + 1);
    await expect(createNativeEyePngEvidenceConsumer(test.options).consume(test.window, test.receipt)).rejects.toThrow(/bounded/);
    await writeFile(test.filePath, png);
    await link(test.filePath, join(test.root, "linked.png"));
    await expect(createNativeEyePngEvidenceConsumer(test.options).consume(test.window, test.receipt)).rejects.toThrow(/single link/);
  }, ATTESTED_READ_TIMEOUT_MS);

  it("refuses a symlink or Windows junction anywhere in the session directory path", async () => {
    const test = await fixture();
    const target = join(test.root, "actual");
    await mkdir(target);
    const alias = join(test.root, "alias");
    await symlink(target, alias, process.platform === "win32" ? "junction" : "dir");
    await mkdir(join(target, bootId));
    await expect(createNativeEyePngEvidenceConsumer({ ...test.options, sessionDirectory: join(alias, bootId) }).consume(test.window, test.receipt)).rejects.toThrow(/directory|directories/);
  });

  it("rejects bytes rewritten during a handle read even when the path and length stay the same", async () => {
    const test = await fixture();
    const changed = vi.fn();
    const openFile = vi.fn<typeof open>(async (...arguments_) => {
      const handle = await open(...arguments_);
      return new Proxy(handle, {
        get(target, property) {
          if (property === "read") return async (...readArguments: unknown[]) => {
            const result = await Reflect.apply(target.read, target, readArguments);
            changed();
            await utimes(test.filePath, (test.now + 2000) / 1000, (test.now + 2000) / 1000);
            return result;
          };
          const value = Reflect.get(target, property);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });
    });
    const outcome = await createNativeEyePngEvidenceConsumer(test.options, { openFile }).consume(test.window, test.receipt)
      .then(() => "accepted", error => error instanceof Error ? error.message : String(error));
    expect(openFile).toHaveBeenCalled();
    expect(changed).toHaveBeenCalled();
    expect(outcome).toMatch(/changed during/);
  }, ATTESTED_READ_TIMEOUT_MS);

  it("checks PNG checksums, bounded inflation, dimensions and final chunk boundaries", () => {
    expect(inspectNativeEyePng(testPng(1, 1))).toEqual({ width: 1, height: 1 });
    const corrupt = Buffer.from(png);
    corrupt[40] ^= 1;
    expect(() => inspectNativeEyePng(corrupt)).toThrow(/checksum/);
    expect(() => inspectNativeEyePng(Buffer.concat([png, Buffer.from("trailing")]))).toThrow(/end marker/);
    expect(() => inspectNativeEyePng(testPng(5000, 1, Buffer.alloc(5)))).toThrow(/dimensions/);
    expect(() => inspectNativeEyePng(testPng(1, 1, Buffer.alloc(500000)))).toThrow(/exceeds its dimensions/);
  });

  it("classifies bounded native suffixes only after completely validating the PNG prefix", () => {
    const original = testPng(1, 1);
    const padded = Buffer.concat([original, Buffer.alloc(258520)]);
    const result = inspectNativeEyePngEvidence(padded);
    expect(result.trailingZeroPadding).toBe(258520);
    expect(result.pngPrefixBytes).toBe(original.length);
    expect(result.nativeFileBytes).toBe(padded.length);
    expect(result.sha256).toBe(createHash("sha256").update(padded).digest("hex"));
    expect(result.pngPrefixSha256).toBe(createHash("sha256").update(original).digest("hex"));
    expect(() => inspectNativeEyePng(padded)).toThrow(/end marker/);
    expect(inspectNativeEyePngEvidence(Buffer.concat([original, Buffer.from([0, 1])])).trailerKind).toBe("nonzero");
    expect(inspectNativeEyePngEvidence(Buffer.concat([original, original])).pngPrefixBytes).toBe(original.length);
    expect(inspectNativeEyePngEvidence(Buffer.concat([original, Buffer.alloc(2470907)])).trailingBytes).toBe(2470907);
    for (const bytes of [Buffer.concat([original, Buffer.alloc(4 * 1024 * 1024 + 1)]), original.subarray(0, -1)]) {
      expect(() => inspectNativeEyePngEvidence(bytes)).toThrow();
    }
    const corrupt = Buffer.from(padded);
    corrupt[40] ^= 1;
    expect(() => inspectNativeEyePngEvidence(corrupt)).toThrow(/checksum/);
  });

  it("preserves padded native files and separates historical artifact checks from expired request acceptance", async () => {
    const test = await fixture();
    const original = Buffer.concat([png, Buffer.alloc(258520)]);
    await writeFile(test.filePath, original);
    await utimes(test.filePath, test.now / 1000, test.now / 1000);
    const consumer = createNativeEyePngEvidenceConsumer(test.options);
    const result = await consumer.consume(test.window, test.receipt);
    expect(Buffer.from(result.pngBytes)).toEqual(png);
    expect(result.trailingZeroPadding).toBe(258520);
    expect(await readFile(test.filePath)).toEqual(original);
    await expect(createNativeEyePngEvidenceConsumer(test.options).consume({ ...test.window, expiresAtMs: test.now - 1 }, test.receipt)).rejects.toThrow(/stale/);
    const historical = await inspectArchivedNativeEyePng(test.filePath);
    expect(historical.sha256).toBe(result.sha256);
    expect(historical.pngPrefixSha256).toBe(result.pngPrefixSha256);
    expect(historical.purpose).toBe("historical-native-eye-png-evidence");
    expect(historical.liveFrameAccepted).toBe(false);
    expect(historical.exportReceiptVerified).toBe(false);
    expect(historical.capturedAtMs).toBeNull();
    const irisPath = join(test.sessionDirectory, `eye-iris-${nonce}-changed.png`);
    await writeFile(irisPath, original);
    const iris = await inspectArchivedNativeEyePng(irisPath);
    expect(iris.pngPrefixSha256).toBe(result.pngPrefixSha256);
    expect(iris.exportReceiptVerified).toBe(false);
    expect(iris.liveFrameAccepted).toBe(false);
    await expect(inspectArchivedNativeEyePng(join(test.sessionDirectory, `eye-iris-${nonce}-unknown.png`))).rejects.toThrow(/filename/);
  }, ATTESTED_READ_TIMEOUT_MS);

  it("never returns any retained nonzero suffix or second image to a decoder", async () => {
    const test = await fixture();
    const suffix = Buffer.concat([Buffer.from("retained native suffix"), png]);
    const original = Buffer.concat([png, suffix]);
    await writeFile(test.filePath, original);
    await utimes(test.filePath, test.now / 1000, test.now / 1000);
    const result = await createNativeEyePngEvidenceConsumer(test.options).consume(test.window, test.receipt);
    expect(Buffer.from(result.pngBytes)).toEqual(png);
    expect(result.pngBytes.byteLength).toBe(png.length);
    expect(result.trailingBytes).toBe(suffix.length);
    expect(result.trailerSha256).toBe(createHash("sha256").update(suffix).digest("hex"));
    expect(result.trailerKind).toBe("nonzero");
    expect(result.trailingZeroPadding).toBe(0);
    expect(result.sha256).toBe(createHash("sha256").update(original).digest("hex"));
    expect(result.pngPrefixSha256).toBe(createHash("sha256").update(png).digest("hex"));
    expect(await readFile(test.filePath)).toEqual(original);
  }, ATTESTED_READ_TIMEOUT_MS);

  it("binds camera phases to their exact file order and restored native rotation without asserting render freshness", async () => {
    const test = await fixture();
    const window = { ...test.window, intent: "eye-preview-camera-roundtrip" as const };
    const before = { pitch: -5, yaw: 179, roll: 0 };
    const changed = { ...before, yaw: 182 };
    const frames = ["baseline", "changed", "restored"].map(phase => ({ ...test.receipt,
      file_name: `eye-camera-${nonce}-${phase}.png`, phase, capture_requested: true, relative_rotation: phase === "changed" ? changed : before }));
    for (const frame of frames) {
      const filePath = join(test.sessionDirectory, frame.file_name);
      await writeFile(filePath, png);
      await utimes(filePath, test.now / 1000, test.now / 1000);
    }
    const receipt = { ok: true, schema: 2, operation: "camera-roundtrip", production_capabilities: "none",
      kind: "native-eye-camera-roundtrip-evidence", nonce, boot_id: bootId,
      identity: test.options.expectedIdentity, before, changed, delta_yaw_degrees: 3, mutation_attempted: true, restored: true,
      exports_invoked: 3, frames: frames.map(frame => ({ file_name: frame.file_name, phase: frame.phase, capture_requested: true,
        export_invoked: true, relative_rotation: frame.relative_rotation, width: 2048, height: 2048, render_target_format: 2, capture_source: 9,
        export_started_at_epoch_ms: test.now, export_completed_at_epoch_ms: test.now, capture_timestamp_known: false, frame_verified: false })),
      frame_verified: false, gameplay_verified: false };
    const consumer = createNativeEyePngEvidenceConsumer(test.options);
    const result = await consumer.consume(window, receipt, "changed");
    expect(result.fileName).toBe(`eye-camera-${nonce}-changed.png`);
    expect(result.capturedAtMs).toBeNull();
    await expect(consumer.consume({ ...window, issuedAtMs: window.issuedAtMs - 1, expiresAtMs: window.expiresAtMs - 1 }, receipt, "baseline")).rejects.toThrow(/changed after/);
    await expect(consumer.consume(window, { ...receipt, frames: receipt.frames.map(frame => frame.phase === "baseline"
      ? { ...frame, export_started_at_epoch_ms: test.now - 1 } : frame) }, "baseline")).rejects.toThrow(/changed after/);
    await expect(consumer.consume(window, { ...receipt, frames: [receipt.frames[1], receipt.frames[0], receipt.frames[2]] }, "baseline")).rejects.toThrow(/phase/);
    await expect(consumer.consume(window, { ...receipt, restored: false }, "restored")).rejects.toThrow(/incomplete/);
    await expect(consumer.consume(window, { ...receipt, frames: receipt.frames.map(frame => frame.phase === "restored" ? { ...frame, relative_rotation: changed } : frame) }, "restored")).rejects.toThrow(/rotation|restoration/);
    await expect(consumer.consume(test.window, receipt, "restored")).rejects.toThrow(/intent/);
  }, ATTESTED_READ_TIMEOUT_MS);

  it("rejects PNG dimensions or file write time inconsistent with the native export receipt", async () => {
    const test = await fixture();
    await writeFile(test.filePath, testPng(1, 1));
    await utimes(test.filePath, test.now / 1000, test.now / 1000);
    await expect(createNativeEyePngEvidenceConsumer(test.options).consume(test.window, test.receipt)).rejects.toThrow(/receipt dimensions/);
    await writeFile(test.filePath, png);
    await utimes(test.filePath, (test.now - 5000) / 1000, (test.now - 5000) / 1000);
    await expect(createNativeEyePngEvidenceConsumer(test.options).consume(test.window, test.receipt)).rejects.toThrow(/export window/);
  }, ATTESTED_READ_TIMEOUT_MS);
});
