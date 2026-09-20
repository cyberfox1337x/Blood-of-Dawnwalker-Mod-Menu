import { describe, expect, it, vi } from "vitest";
import { createEyeAppearanceService, type EyeServiceAcceptance, type EyeServiceRuntime } from "./eyeAppearanceService.js";
import type { createEyeSessionCoordinator, EyeCoordinatorDescriptor, EyeCoordinatorSettings, EyeCoordinatorTuple } from "./eyeSessionCoordinator.js";
import type { EyeServiceFrame, EyeServiceReady } from "./eyeAppearanceWire.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_appearance_service_tests");

// Deliberate adapter fixtures. These do not attest the game or install a pilot.
const schema = "dawnwalker-human-iris-uv-v1-25129649";
function settings(): EyeCoordinatorSettings {
  return { schemaId: schema, values: [0.2, 0.3, 0.8, 0.7, 0.25, 0.35, 0.85, 0.75].map((value, i) => ({
    parameter: { slotId: i < 4 ? "head:3" : "head:4", materialId: i < 4 ? "coen-human-eye-left" : "coen-human-eye-right",
      name: ["IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V"][i % 4], association: 2, index: -1 }, value: { kind: "scalar", value } })) };
}
function fixture(accepted = true) {
  let now = 1_000_000, active = false, owned = false, lease = 0, sequence = 0, command = 0, wireRevision = -1;
  let current = settings(), desired: EyeCoordinatorTuple, stepHook: (() => Promise<void>) | undefined;
  let mutateFrame: ((frame: Record<string, unknown>) => void) | undefined;
  const object = (name: string, address: number) => ({ name, address: String(address) });
  function descriptor(): EyeCoordinatorDescriptor {
    return { identityKey: "native-observed-identity", baselineId: "native-original-baseline", schemaId: schema,
      player: object("Player Coen", 1), world: object("World", 2), head: object("Head", 3), asset: object("SK_Head", 4),
      form: "human", isWolfForm: false, original: settings(), current: structuredClone(current),
      bindings: [0, 1].map(i => ({ slot: i + 3, slotName: i ? "shader_eyeRight_shader" : "shader_eyeLeft_shader",
        original: object("Original MIC", 10 + i), current: object("Current material", 20 + i),
        parameters: settings().values.slice(i * 4, i * 4 + 4).map(entry => ({ parameter: entry.parameter, min: 0.1, max: 0.9, tolerance: 0.000001 })) })) };
  }
  const runtime: EyeServiceRuntime = { buildId: "25129649", executableSha256: "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853",
    payloadManifestSha256: "A".repeat(64), bootId: "1788697238-427484", ownerId: "b".repeat(32), processId: 42, processStartedAt: "2026-09-06T12:00:00Z" };
  const proof: EyeServiceAcceptance = { buildId: "25129649", executableSha256: runtime.executableSha256, payloadManifestSha256: runtime.payloadManifestSha256,
    sessionEvidenceSha256: "C".repeat(64), appearanceEvidenceSha256: "D".repeat(64), liveRestoreEvidenceSha256: "E".repeat(64),
    actualPlayerModel: true, isolatedPreviewInput: true, correspondingEyeMaterials: true, reversibleLiveSetter: true,
    profile: { frameIntervalMs: 100, leaseMs: 10000, renewIntervalMs: 2000, maximumLifetimeMs: 30000,
      maximumFramesPerLease: 9, maximumLeases: 3, maxFrameAgeMs: 1000, maxReadbackAgeMs: 1000 } };
  function timing() { return { requestSequence: ++command, hostRequestSentAtMs: now - 20, hostReceiptReceivedAtMs: now - 1 }; }
  function result(status: string) { return { status, productionReady: false as const, timing: timing(), nativeFields: {} }; }
  function preview() { return { actor: object("Actor", 100 + lease), capture: object("Capture", 200 + lease), target: object("Target", 300 + lease),
    targetOuter: descriptor().world, width: 1024, height: 1024, renderTargetFormat: 2, captureSource: 9, targetGamma: 0, forceLinearGamma: true,
    zoomBounds: { "head-and-shoulders": { min: 0.8, max: 1.5, initial: 1 }, "eyes-close-up": { min: 0.7, max: 1.3, initial: 1 } },
    nativeFields: { "result.preview.nonce": String(lease).padStart(32, "0"), "result.preview.boot_id": runtime.bootId } }; }
  const coordinator = {
    getState: vi.fn(() => ({ status: active ? "active" : "idle", ownershipConfirmed: owned, liveEyeRevision: wireRevision, descriptor: descriptor() })),
    connect: vi.fn(async () => ({ bootId: runtime.bootId, ownerId: runtime.ownerId, transport: "eye-session-prototype", productionReady: false, sha256: "F".repeat(64) })),
    inspect: vi.fn(async () => ({ ...result("observed"), operation: "inspect", descriptor: descriptor(), nativeReadbackVerified: true, originalBindingsRestored: false, appliedInGame: false })),
    open: vi.fn(async (input: EyeCoordinatorTuple) => { lease++; sequence = 0; active = owned = true; desired = structuredClone(input); return { ...result("opened"), descriptor: descriptor(), preview: preview() }; }),
    updatePreview: vi.fn(async (input: EyeCoordinatorTuple) => { desired = structuredClone(input); return result("queued"); }),
    step: vi.fn(async () => {
      await stepHook?.();
      const frame = { kind: "native-frame-evidence", productionReady: false, previewVerified: false, sequence: ++sequence,
        ...structuredClone(desired), width: 1024, height: 1024, pngBytes: new Uint8Array(33), pngEvidence: {}, nativeFields: {},
        captureTiming: { ...timing(), kind: "native-call-interval", nativeClockId: "actual-native-clock", nativeStartedMs: 100, nativeCompletedMs: 110, renderCompletedAtMs: null } };
      mutateFrame?.(frame); return frame;
    }),
    renew: vi.fn(async () => result("renewed")), cancelQueued: vi.fn(async () => result("cancelled")),
    apply: vi.fn(async (revision: number, desiredSettings: EyeCoordinatorSettings) => { wireRevision = revision; current = structuredClone(desiredSettings);
      return { ...result("native-readback"), operation: "apply", descriptor: descriptor(), nativeReadbackVerified: true, originalBindingsRestored: false, appliedInGame: false }; }),
    restore: vi.fn(async (revision: number) => { wireRevision = revision; current = settings();
      return { ...result("native-readback"), operation: "restore", descriptor: descriptor(), nativeReadbackVerified: true, originalBindingsRestored: true, appliedInGame: false }; }),
    close: vi.fn(async () => { active = false; return result("closed"); }),
  };
  const timers: { callback: () => void; cancelled: boolean }[] = [], frameEvents: EyeServiceFrame[] = [];
  const onSession = vi.fn(), onFault = vi.fn();
  const service = createEyeAppearanceService({ coordinator: coordinator as unknown as ReturnType<typeof createEyeSessionCoordinator>, acceptance: accepted ? proof : undefined,
    inspectRuntime: async () => structuredClone(runtime), now: () => now,
    schedule(callback) { const timer = { callback, cancelled: false }; timers.push(timer); return () => { timer.cancelled = true; }; },
    onSession, onFault, onFrame: frame => { frameEvents.push(frame); } });
  return { service, coordinator, runtime, proof, timers, frameEvents, onSession, onFault,
    advance(ms: number) { now += ms; }, stepHook(hook?: () => Promise<void>) { stepHook = hook; }, mutateFrame(hook: (frame: Record<string, unknown>) => void) { mutateFrame = hook; } };
}
async function flush() { for (let i = 0; i < 60; i++) await Promise.resolve(); }
async function opened(h: ReturnType<typeof fixture>): Promise<EyeServiceReady> {
  const session = await h.service.open(); expect(session.availability).toBe("ready"); return session as EyeServiceReady;
}
function request(session: EyeServiceReady, eyeRevision = 1, original = false) {
  return { identity: session.identity, baselineId: session.baselineId, requestId: `request-${eyeRevision}`, eyeRevision,
    desired: session.schema.presets[original ? 0 : 1].settings };
}
function view(session: EyeServiceReady, revision = 1) {
  return { identity: session.identity, previewId: session.previewId, renderTargetGeneration: session.renderTargetGeneration,
    viewRevision: revision, eyeRevision: 0, view: { framing: "head-and-shoulders" as const, yawDegrees: revision, zoom: 1 }, settings: session.current };
}

describe("inactive main eye service", () => {
  it("constructs without any native calls and refuses missing session acceptance", async () => {
    const h = fixture(false); expect(h.coordinator.connect).not.toHaveBeenCalled(); expect(h.timers).toHaveLength(0);
    await expect(h.service.open()).rejects.toThrow(/not been accepted/); expect(h.coordinator.open).not.toHaveBeenCalled();
  });
  it("does not treat the ready-file checksum as the accepted payload checksum", async () => {
    const h = fixture(); (h.runtime as { payloadManifestSha256: string }).payloadManifestSha256 = "F".repeat(64);
    await expect(h.service.open()).rejects.toThrow(/differs/); expect(h.coordinator.open).not.toHaveBeenCalled();
  });
  it("maps actual identities, native intervals and Original/Alternate only after a matching first frame", async () => {
    const h = fixture(); let release!: () => void;
    h.stepHook(() => new Promise<void>(resolve => { release = resolve; })); const pending = h.service.open(); await flush();
    expect(h.service.getState().session.availability).toBe("unavailable"); expect(h.frameEvents).toHaveLength(0);
    release(); const session = await pending as EyeServiceReady;
    expect(session.schema.presets.map(preset => preset.label)).toEqual(["Original", "Alternate"]);
    expect(session.evidence.verifiedTransitions).toEqual([]); expect(session.identity.eyeMaterialGeneration).toHaveLength(64);
    expect(h.frameEvents[0].captureTiming.nativeStartedMs).toBe(100); expect(h.frameEvents[0].captureTiming.renderCompletedAtMs).toBeNull();
    expect(h.frameEvents[0]).not.toHaveProperty("nativeFields"); expect(session).not.toHaveProperty("payloadManifestSha256");
  });
  it("retains original baseline across live apply, close and new preview while rebasing local revisions", async () => {
    const h = fixture(), first = await opened(h);
    const applied = await h.service.apply(request(first), first);
    expect(applied.eyeRevision).toBe(1); expect(applied.readback.settings).toEqual(first.schema.presets[1].settings);
    const firstNativeRevision = h.coordinator.apply.mock.calls[0][0]; await h.service.close();
    expect(h.coordinator.restore).not.toHaveBeenCalled(); const second = await opened(h);
    expect(second.identity).toEqual(first.identity); expect(second.baselineId).toBe(first.baselineId); expect(second.original).toEqual(first.original);
    expect(second.current).toEqual(first.schema.presets[1].settings); expect(second.previewId).not.toBe(first.previewId);
    expect(h.coordinator.open.mock.calls[1][0].eyeRevision).toBeGreaterThan(firstNativeRevision);
    await expect(h.service.apply(request(first, 2), first)).rejects.toThrow(/stale/);
    await h.service.restore(request(second, 1, true), second); expect(h.coordinator.restore.mock.calls[0][0]).toBeGreaterThan(firstNativeRevision);
  });
  it("permits explicit original restoration after preview close without creating another actor", async () => {
    const h = fixture(), session = await opened(h); await h.service.apply(request(session), session); await h.service.close();
    const restored = await h.service.restore(request(session, 2, true), session);
    expect(restored.operation).toBe("restore"); expect(restored.readback.settings).toEqual(session.original); expect(h.coordinator.open).toHaveBeenCalledTimes(1);
  });
  it("coalesces waiting views, saves immutable requests and rejects reused view revisions", async () => {
    const h = fixture(), session = await opened(h), first = view(session, 1), second = view(session, 2);
    const one = h.service.updatePreview(first), two = h.service.updatePreview(second); second.view.yawDegrees = 50;
    expect((await one).status).toBe("superseded"); await two;
    expect(h.coordinator.updatePreview).toHaveBeenCalledTimes(1); expect(h.coordinator.updatePreview.mock.calls[0][0].view.yawDegrees).toBe(2);
    expect(() => h.service.updatePreview({ ...view(session, 2), view: { ...view(session, 2).view, yawDegrees: 20 } })).toThrow(/reused/);
  });
  it("keeps the view watermark while a newer tuple is queued but has not reached native code", async () => {
    const h = fixture(), session = await opened(h), newest = h.service.updatePreview(view(session, 2));
    expect(() => h.service.updatePreview(view(session, 1))).toThrow(/stale/);
    await newest; expect(h.coordinator.updatePreview.mock.calls[0][0].viewRevision).toBe(2);
  });
  it("suppresses cancelled frames until a new explicit tuple and never restores committed eyes", async () => {
    const h = fixture(), session = await opened(h); await h.service.cancelQueued(session);
    h.timers.at(-1)!.callback(); await flush(); expect(h.coordinator.step).toHaveBeenCalledTimes(1); expect(h.coordinator.restore).not.toHaveBeenCalled();
    await h.service.updatePreview(view(session)); h.timers.at(-1)!.callback(); await flush(); expect(h.frameEvents).toHaveLength(2);
  });
  it("maintains one scheduled capture and ignores duplicate/cancelled timer delivery", async () => {
    const h = fixture(); await opened(h); const old = h.timers[0]; old.callback(); old.callback(); await flush();
    expect(h.coordinator.step).toHaveBeenCalledTimes(2); expect(h.timers).toHaveLength(2);
    await h.service.close(); await opened(h); const newest = h.timers.at(-1)!; old.callback();
    await h.service.close(); expect(newest.cancelled).toBe(true);
  });
  it("drops an in-flight preview on hide and cancels a queued live operation before native mutation", async () => {
    const h = fixture(), session = await opened(h); let release!: () => void;
    h.stepHook(() => new Promise<void>(resolve => { release = resolve; })); h.timers[0].callback(); await flush();
    const applying = h.service.apply(request(session), session); const rejection = expect(applying).rejects.toThrow(/cancelled/);
    const closing = h.service.close(); release(); await closing; await rejection;
    expect(h.frameEvents).toHaveLength(1); expect(h.coordinator.apply).not.toHaveBeenCalled(); expect(h.coordinator.restore).not.toHaveBeenCalled();
  });
  it("cancels a queued live operation without requiring preview close or restoring existing eyes", async () => {
    const h = fixture(), session = await opened(h); let release!: () => void;
    h.stepHook(() => new Promise<void>(resolve => { release = resolve; })); h.timers[0].callback(); await flush();
    const applying = h.service.apply(request(session), session); const rejection = expect(applying).rejects.toThrow(/cancelled/);
    const cancelling = h.service.cancelQueued(session); release(); await cancelling; await rejection;
    expect(h.coordinator.apply).not.toHaveBeenCalled(); expect(h.coordinator.restore).not.toHaveBeenCalled(); expect(h.service.getState().active).toBe(true);
  });
  it("refuses a mismatched or stale frame and retains cleanup failure as unavailable", async () => {
    const h = fixture(); h.mutateFrame(frame => { frame.eyeRevision = 10; });
    await expect(h.service.open()).rejects.toThrow(/does not match/); expect(h.frameEvents).toHaveLength(0);
    expect(h.coordinator.close).toHaveBeenCalled(); expect(h.service.getState().session.availability).toBe("unavailable");
  });
  it("renews within the accepted lease and closes at the lifetime bound without automatic reopening", async () => {
    const h = fixture(); await opened(h); h.advance(2100); h.timers.at(-1)!.callback(); await flush();
    expect(h.coordinator.renew).toHaveBeenCalledTimes(1); h.advance(28000); h.timers.at(-1)!.callback(); await flush();
    expect(h.service.getState().active).toBe(false); expect(h.coordinator.close).toHaveBeenCalledTimes(1); expect(h.coordinator.open).toHaveBeenCalledTimes(1);
  });
  it("rejects fabricated palette settings and a replaced process without a live setter", async () => {
    const h = fixture(), session = await opened(h), invalid = structuredClone(request(session));
    (invalid.desired.values[0].value as { value: number }).value = 0.5;
    await expect(h.service.apply(invalid, session)).rejects.toThrow(/observed human/);
    (h.runtime as { processId: number }).processId++;
    await expect(h.service.apply(request(session), session)).rejects.toThrow(/generation changed/); expect(h.coordinator.apply).not.toHaveBeenCalled();
  });
});
