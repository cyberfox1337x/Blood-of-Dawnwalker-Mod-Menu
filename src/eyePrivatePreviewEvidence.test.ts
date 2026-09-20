import { mkdir, mkdtemp, rm, utimes, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { deflateSync } from "node:zlib";
import { afterEach, describe, expect, it } from "vitest";
import { createNativePrivateEyeEvidenceConsumer, PRIVATE_EYE_PHASES, validateNativePrivateEyeReceipt, type NativePrivateEyeSource } from "../electron/eyeFrameTransport";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_private_eye_evidence_tests");
const bootId = "1788660000-654321", nonce = "a".repeat(32);
const roots: string[] = [];
const object = (name: string, address: number) => ({ name, address: String(address) });

function privateReceiptFixture(now = 1788660000000) {
  const source: NativePrivateEyeSource = { player: object("Player mock", 1), world: object("World mock", 2), head: object("SkeletalMeshComponentBudgeted mock.Head", 3),
    asset: object("SkeletalMesh mock.HeadAsset", 4), form: 0, is_wolf_form: false,
    eye_materials: [object("MaterialInstanceConstant mock.Left", 5), object("MaterialInstanceConstant mock.Right", 6)],
    eye_bones: [{ name: "eye_l", index: 10 }, { name: "eye_r", index: 11 }] };
  const center = { X: 0, Y: 0, Z: 100000 };
  const profiles = ["head-and-shoulders", "eyes-close-up"].map((name, index) => {
    const pivot = { ...center, Z: index ? 100000 : 99994.5 }, fov = index ? 20 : 30;
    const safe = index ? 12 : 17.5;
    const initial = Math.max(safe * 1.15, (index ? 6.6 : 16.5) / Math.tan(fov * Math.PI / 360));
    return { name, pivot, field_of_view: fov, near_clip: 1, safe_distance: safe, default_distance: initial,
      minimum_distance: Math.max(safe, initial * 0.78), maximum_distance: initial * 1.35 };
  });
  const frames = PRIVATE_EYE_PHASES.map((phase, index) => {
    const profile = profiles[[3, 6, 7].includes(index) ? 1 : 0], yaw = index === 1 ? -69 : index === 2 ? 69 : 0;
    const zoom = [4, 6].includes(index) ? "minimum" : [5, 7].includes(index) ? "maximum" : "default";
    const distance = zoom === "minimum" ? profile.maximum_distance : zoom === "maximum" ? profile.minimum_distance : profile.default_distance;
    const angle = yaw * Math.PI / 180, pivot = profile.pivot;
    const location = { X: pivot.X + Math.cos(angle) * distance, Y: pivot.Y + Math.sin(angle) * distance, Z: pivot.Z };
    return { phase, file_name: `eye-private-${nonce}-${phase}.png`, framing: profile.name, yaw_degrees: yaw, zoom, camera_distance: distance,
      field_of_view: profile.field_of_view, near_clip: 1, pivot, camera_location: location,
      camera_rotation: { pitch: 0, Yaw: Math.atan2(pivot.Y - location.Y, pivot.X - location.X) * 180 / Math.PI, Roll: 0 },
      export_started_at_epoch_ms: now, export_completed_at_epoch_ms: now };
  });
  const materials = [object("MaterialInstanceConstant mock.Skin", 20), object("MaterialInstanceConstant mock.Teeth", 21), object("MaterialInstanceConstant mock.Edge", 22), ...source.eye_materials];
  const receipt = { schema: 3, kind: "native-private-eye-preview-evidence", operation: "private-preview-roundtrip", production_capabilities: "none", ok: true,
    nonce, boot_id: bootId, width: 1024, height: 1024, render_target_format: 3, capture_source: 2, target_gamma: 2.2,
    player: source.player, world: source.world, form: 0, is_wolf_form: false,
    actor: object("SceneCapture2D mock.Private", 30), capture: object("SceneCaptureComponent2D mock.Private.Capture", 31),
    target: object("TextureRenderTarget2D /Engine/Transient.mock", 32), pivot_bone_name: "Head",
    source_meshes: [{ field: "HeadMesh", mesh: source.head, asset: source.asset, materials },
      { field: "TorsoMesh", mesh: object("SkeletalMeshComponent mock.Torso", 33), asset: object("SkeletalMesh mock.TorsoAsset", 34), materials: [materials[0]] }],
    eye_pair: { left: { ...source.eye_bones[0], location: { X: -3, Y: 0, Z: 0 } }, right: { ...source.eye_bones[1], location: { X: 3, Y: 0, Z: 0 } } },
    head_center: center, head_radius: 10, eye_distance: 6, framing_profiles: Object.fromEntries(profiles.map(({ name, ...profile }) => [name, profile])), frames,
    capture_timestamp_known: false, frame_verified: false, preview_verified: false, gameplay_verified: false, created: true,
    front_restored: true, target_released: true, destruction_acknowledged: true, destruction_pending: true, actor_invalidated: false, capture_requests: 9, export_invoked: true };
  const window = { nonce, intent: "eye-private-preview-roundtrip" as const, issuedAtMs: now - 1000, expiresAtMs: now + 119000 };
  return { source, receipt, window, now };
}

function pngChunk(name: string, data: Buffer): Buffer {
  const type = Buffer.from(name), length = Buffer.alloc(4), checksum = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  let crc = 0xffffffff;
  for (const byte of Buffer.concat([type, data])) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc & 1) ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
  }
  checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([length, type, data, checksum]);
}
function png() {
  const header = Buffer.alloc(13); header.writeUInt32BE(1024); header.writeUInt32BE(1024, 4); header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(Buffer.alloc((1024 * 4 + 1) * 1024))), pngChunk("IEND", Buffer.alloc(0))]);
}

afterEach(async () => {
  for (const root of roots.splice(0)) {
    const absolute = resolve(root);
    if (dirname(absolute) !== resolve(tmpdir()) || !basename(absolute).startsWith("dawnwalker-private-eye-test-")) throw new Error("Fixture cleanup path escaped its temporary root.");
    await rm(absolute, { recursive: true, force: true });
  }
});

// This case consumes nine frames, and eyeFrameTransport attests every read twice for
// the Windows reparse attribute Node does not expose. Those eighteen attestations used
// to spawn PowerShell each time and cost ~21.6 s on their own; on the reused worker
// they cost ~1.2 s. See qa/RESUME_HERE.md. The budget below leaves room for the replay
// and historical passes and for starting the worker on a machine under load.
const NINE_FRAME_ATTESTED_TIMEOUT_MS = 60000;
describe("v4/v5/v6 private native preview evidence", () => {
  it("checks all nine phases, exact geometry, independent source bindings and distinct cleanup states", () => {
    const { source, receipt, window } = privateReceiptFixture();
    const result = validateNativePrivateEyeReceipt(receipt, source, window, bootId);
    expect(result.frames.map(frame => frame.phase)).toEqual(PRIVATE_EYE_PHASES);
    expect(result.frames.map(frame => frame.yawDegrees)).toEqual([0, -69, 69, 0, 0, 0, 0, 0, 0]);
    expect(result.destructionPending).toBe(true);
    expect(result.actorInvalidated).toBe(false);
    expect(validateNativePrivateEyeReceipt({ ...receipt, destruction_pending: false, actor_invalidated: true }, source, window, bootId).actorInvalidated).toBe(true);
  });

  it("rejects changed phases, camera readback, source form/material, resource aliases and incomplete cleanup", () => {
    const { source, receipt, window } = privateReceiptFixture();
    const changed = (index: number, update: object) => ({ ...receipt, frames: receipt.frames.map((frame, i) => i === index ? { ...frame, ...update } : frame) });
    for (const invalid of [{ ...receipt, form: 1 }, { ...receipt, capture: receipt.actor }, { ...receipt, target_released: false },
      { ...receipt, actor_invalidated: true }, { ...receipt, frame_verified: true }, { ...receipt, frames: receipt.frames.slice(1) },
      changed(1, { yaw_degrees: 70 }), changed(2, { camera_location: receipt.frames[0].camera_location }), changed(8, { file_name: "../elsewhere.png" }),
      changed(3, { export_completed_at_epoch_ms: window.expiresAtMs + 1 }), changed(4, { camera_distance: 1 })]) {
      expect(() => validateNativePrivateEyeReceipt(invalid, source, window, bootId)).toThrow();
    }
    expect(() => validateNativePrivateEyeReceipt(receipt, { ...source, eye_materials: [source.eye_materials[1], source.eye_materials[0]] }, window, bootId)).toThrow(/material/);
  });

  it("requires v5 world-owned new-target and finished-spawn evidence without rejecting its native world path", () => {
    const { source, receipt, window } = privateReceiptFixture();
    const v5 = { ...receipt, schema: 4, target: { ...receipt.target, name: "TextureRenderTarget2D /Game/Test.World.NewTarget" },
      target_outer: source.world, target_new_address: true, target_owned: true, spawn_finish_attempted: true, spawn_finished: true };
    expect(validateNativePrivateEyeReceipt(v5, source, window, bootId).targetOuter).toEqual(source.world);
    for (const invalid of [{ ...v5, target_outer: source.player }, { ...v5, target_new_address: false }, { ...v5, target_owned: false },
      { ...v5, spawn_finish_attempted: false }, { ...v5, spawn_finished: false }, { ...v5, target_outer: undefined }, { ...v5, schema: 3 }]) {
      expect(() => validateNativePrivateEyeReceipt(invalid, source, window, bootId)).toThrow();
    }
  });

  it("keeps V6 completed capture evidence separate from an unacknowledged initial cleanup", () => {
    const { source, receipt, window } = privateReceiptFixture();
    const display = { requested_gamma: 2.2, requested_force_linear_gamma: false, write_ok: true,
      gamma_after: { ok: true, type: "number", value: 2.2 }, force_linear_after: { ok: true, type: "number", value: 0 } };
    const v6 = { ...receipt, schema: 5, target_outer: source.world, target_new_address: true, target_owned: true,
      spawn_finish_attempted: true, spawn_finished: true, display_configuration: display, ok: false, capture_operation_completed: true,
      destruction_acknowledged: false, destruction_pending: false, cleanup_error: "Private actor destruction is not yet acknowledged" };
    const result = validateNativePrivateEyeReceipt(v6, source, window, bootId);
    expect(result.initialOperationOk).toBe(false);
    expect(result.captureOperationCompleted).toBe(true);
    expect(result.destructionAcknowledged).toBe(false);
    expect(result.frames).toHaveLength(9);
    expect(result.cleanupErrors.cleanup_error).toContain("not yet acknowledged");
    for (const invalid of [{ ...v6, capture_operation_completed: false }, { ...v6, ok: true }, { ...v6, schema: 4 },
      { ...v6, display_configuration: { ...display, write_ok: false } },
      { ...v6, display_configuration: { ...display, force_linear_after: { ok: true, type: "number", value: 1 } } },
      { ...v6, frames: receipt.frames.slice(0, 8) }]) expect(() => validateNativePrivateEyeReceipt(invalid, source, window, bootId)).toThrow();
  });

  it("reads all nine immutable files as prefix-only evidence and keeps historical analysis out of the fresh lease gate", async () => {
    const sample = privateReceiptFixture(Math.floor(Date.now() / 1000) * 1000);
    const root = await mkdtemp(join(tmpdir(), "dawnwalker-private-eye-test-")); roots.push(root);
    const directory = join(root, bootId); await mkdir(directory);
    const image = png();
    for (const frame of sample.receipt.frames) {
      const path = join(directory, frame.file_name);
      await writeFile(path, Buffer.concat([image, Buffer.from("retained suffix data")]));
      await utimes(path, sample.now / 1000, sample.now / 1000);
    }
    const options = { sessionDirectory: directory, bootId, expectedSource: sample.source, now: () => sample.now + 1000 };
    const consumer = createNativePrivateEyeEvidenceConsumer(options);
    const result = await consumer.consume(sample.window, sample.receipt);
    expect(result.frames).toHaveLength(9);
    for (const frame of result.frames) { expect(Buffer.from(frame.pngBytes)).toEqual(image); expect(frame.trailerKind).toBe("nonzero"); }
    expect(result.readySession).toBe(false);
    expect(result.liveFrameAccepted).toBe(false);
    expect(result.capturedAtMs).toBeNull();
    await expect(consumer.consume(sample.window, sample.receipt)).rejects.toThrow(/consumed/);
    const expired = createNativePrivateEyeEvidenceConsumer({ ...options, now: () => sample.window.expiresAtMs + 1 });
    await expect(expired.consume(sample.window, sample.receipt)).rejects.toThrow(/stale/);
    const historical = await expired.consume(sample.window, sample.receipt, "historical");
    expect(historical.leaseStatus).toBe("historical");
    expect(historical.readySession).toBe(false);
  }, NINE_FRAME_ATTESTED_TIMEOUT_MS);
});
