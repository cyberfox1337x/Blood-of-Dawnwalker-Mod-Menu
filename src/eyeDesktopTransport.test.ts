import { describe, expect, it, vi } from "vitest";
import { createEyeDesktopBridge, readEyeDesktopSession, type EyeDesktopFrame, type EyeDesktopTransport } from "./eyeDesktopTransport";
import type { EyeOperationRequest, EyePreviewFrame, EyePreviewRequest, EyeSettings, ReadyEyeSession } from "./eyeAppearanceContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_desktop_transport_tests");

const NOW = 1_000_000;
const SCHEMA = "dawnwalker-human-iris-uv-v1-25129649";

function sessionFixture(): ReadyEyeSession {
  const parameters = Array.from({ length: 8 }, (_, index) => ({ kind: "scalar" as const, label: "Observed iris coordinate",
    parameter: { slotId: index < 4 ? "head:3" : "head:4", materialId: index < 4 ? "coen-human-eye-left" : "coen-human-eye-right",
      name: ["IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V"][index % 4], association: 2, index: -1 },
    domain: { min: 0.1, max: 0.9, readbackTolerance: 0.000001 } }));
  const original: EyeSettings = { schemaId: SCHEMA, values: parameters.map((definition, index) => ({ parameter: definition.parameter,
    value: { kind: "scalar", value: [0.2, 0.3, 0.8, 0.7, 0.25, 0.35, 0.85, 0.75][index] } })) };
  const alternate: EyeSettings = { schemaId: SCHEMA, values: original.values.map((entry, index) => ({ ...entry,
    value: original.values[[2, 3, 0, 1, 6, 7, 4, 5][index]].value })) };
  return { availability: "ready", identity: { buildId: "25129649", sessionId: "boot", worldGeneration: "world", pawnId: "pawn",
    appearanceRevision: "appearance", form: "human", isWolfForm: false, meshId: "mesh", eyeMaterialGeneration: "original-materials" },
    previewId: "preview-1", renderTargetGeneration: "target-1", baselineId: "baseline", schema: { id: SCHEMA, parameters,
      presets: [{ id: "original", label: "Original", settings: original }, { id: "alternate", label: "Alternate", settings: alternate }] },
    original, current: original, zoomBounds: { "head-and-shoulders": { min: 0.8, max: 1.2, initial: 1, step: 0.01 },
      "eyes-close-up": { min: 0.9, max: 1.1, initial: 1, step: 0.01 } }, maxFrameAgeMs: 1000, maxReadbackAgeMs: 1000, diagnostics: [],
    evidence: { actualPlayerModel: true, isolatedPreviewInput: true, correspondingEyeMaterials: true, reversibleLiveSetter: true,
      supportedForms: [{ form: "human", schemaId: SCHEMA, originalRestore: true }], verifiedTransitions: [] } };
}

function pngHeader(): Uint8Array {
  const bytes = new Uint8Array(33);
  bytes.set([137, 80, 78, 71, 13, 10, 26, 10]);
  const header = new DataView(bytes.buffer);
  header.setUint32(8, 13); header.setUint32(12, 0x49484452); header.setUint32(16, 1024); header.setUint32(20, 1024);
  return bytes; // Boundary fixture only: full CRC/inflate validation belongs to main.
}

function harness() {
  const session = sessionFixture(), fault = vi.fn(), unsubscribe = vi.fn();
  let receive: ((frame: unknown) => void) | undefined;
  const timing = { requestSequence: 1, hostRequestSentAtMs: NOW - 50, hostReceiptReceivedAtMs: NOW - 10 };
  const readback = { source: "runtime-material-getter", identity: session.identity, baselineId: session.baselineId,
    observationTiming: timing, settings: session.current };
  const transport = {
    subscribeFrames: vi.fn<EyeDesktopTransport["subscribeFrames"]>((_address, listener) => { receive = listener; return unsubscribe; }),
    updatePreview: vi.fn<EyeDesktopTransport["updatePreview"]>(async request => ({ ...request, status: "queued" })),
    apply: vi.fn<EyeDesktopTransport["apply"]>(async request => ({ status: "verified", operation: "apply", requestId: request.requestId,
      eyeRevision: request.eyeRevision, readback: { ...readback, settings: request.desired } })),
    restore: vi.fn<EyeDesktopTransport["restore"]>(async request => ({ status: "verified", operation: "restore", requestId: request.requestId,
      eyeRevision: request.eyeRevision, readback: { ...readback, settings: session.original } })),
    inspect: vi.fn<EyeDesktopTransport["inspect"]>(async () => readback),
    cancelQueued: vi.fn<EyeDesktopTransport["cancelQueued"]>(async address => ({ ...address, status: "cancelled" })),
  };
  const adapter = createEyeDesktopBridge(session, transport, fault, () => NOW);
  const request: EyePreviewRequest = { ...session, eyeRevision: 0, viewRevision: 0, settings: session.current,
    view: { framing: "head-and-shoulders", yawDegrees: 0, zoom: 1 } };
  const frame: EyeDesktopFrame = { ...request, source: "native-scene-capture", sequence: 1,
    captureTiming: { ...timing, kind: "native-call-interval", nativeClockId: "native-clock", nativeStartedMs: 100,
      nativeCompletedMs: 101, renderCompletedAtMs: null }, width: 1024, height: 1024, pngBytes: pngHeader() };
  const operation: EyeOperationRequest = { identity: session.identity, baselineId: session.baselineId,
    requestId: "request-1", eyeRevision: 1, desired: session.schema.presets[1].settings };
  return { session, transport, adapter, fault, unsubscribe, request, frame, operation, emit: (value: unknown) => receive?.(value) };
}

describe("unactivated desktop eye facade", () => {
  it("passes unavailable through and never promotes transport or prototype flags", () => {
    expect(readEyeDesktopSession({ availability: "unavailable", reason: "Native preview remains unverified.", diagnostics: [] }).availability).toBe("unavailable");
    const session = sessionFixture();
    expect(() => readEyeDesktopSession({ ...session, evidence: { ...session.evidence, actualPlayerModel: false } })).toThrow();
    expect(() => readEyeDesktopSession({ productionReady: false, previewVerified: false })).toThrow();
  });

  it("accepts only exact human Original and Alternate parameter semantics", () => {
    const session = sessionFixture();
    expect(readEyeDesktopSession(session).availability).toBe("ready");
    expect(() => readEyeDesktopSession({ ...session, identity: { ...session.identity, form: "vampire" } })).toThrow();
    const wrong = structuredClone(session);
    (wrong.schema.presets[1].settings.values[0] as { value: { kind: "scalar"; value: number } }).value = { kind: "scalar", value: 0.5 };
    expect(() => readEyeDesktopSession(wrong)).toThrow(/pair swap/);
    const shuffled = { ...session, original: { ...session.original, values: [...session.original.values].reverse() } };
    expect(readEyeDesktopSession(shuffled).availability).toBe("ready");
  });

  it("construction is inert and copies validated frames into local PNG Blobs", () => {
    const h = harness(), received = vi.fn<(frame: EyePreviewFrame) => void>(), failed = vi.fn();
    expect(h.transport.subscribeFrames).not.toHaveBeenCalled();
    h.adapter.bridge.subscribeFrames(h.session, received, failed);
    h.emit({ ...h.frame, nativeFields: { privatePath: "must not cross" } });
    const frame = received.mock.calls[0][0];
    expect(frame.image).toBeInstanceOf(Blob); expect(frame.image.size).toBe(33); expect(frame.image.type).toBe("image/png");
    expect(frame).not.toHaveProperty("pngBytes"); expect(frame).not.toHaveProperty("nativeFields");
    expect(failed).not.toHaveBeenCalled(); expect(h.transport.apply).not.toHaveBeenCalled();
  });

  it("rejects stale generations, sequences, age, view, and malformed image bounds", () => {
    const changes: Partial<EyeDesktopFrame>[] = [{ previewId: "other" }, { sequence: 0 }, { width: 2048 },
      { captureTiming: { ...harness().frame.captureTiming, hostRequestSentAtMs: NOW - 2000 } },
      { view: { framing: "eyes-close-up", yawDegrees: 70, zoom: 1 } }, { pngBytes: new Uint8Array(33) }];
    for (const change of changes) {
      const h = harness(), received = vi.fn(), failed = vi.fn();
      h.adapter.bridge.subscribeFrames(h.session, received, failed); h.emit({ ...h.frame, ...change });
      expect(received).not.toHaveBeenCalled(); expect(failed).toHaveBeenCalledOnce();
    }
  });

  it("keeps preview updates separate from live requests and rejects foreign addresses", async () => {
    const h = harness();
    await h.adapter.bridge.updatePreview(h.request);
    expect(h.transport.apply).not.toHaveBeenCalled();
    await expect(h.adapter.bridge.updatePreview({ ...h.request, previewId: "other" })).rejects.toThrow(/address/);
    expect(h.transport.updatePreview).toHaveBeenCalledOnce();
    h.transport.updatePreview.mockResolvedValueOnce({ status: "queued", viewRevision: 0, eyeRevision: 0 });
    await expect(h.adapter.bridge.updatePreview(h.request)).rejects.toThrow(/acknowledgement/);
  });

  it("accepts matching native receipts but rejects arbitrary UV changes and mismatched readback", async () => {
    const h = harness();
    expect((await h.adapter.bridge.apply(h.operation)).status).toBe("verified");
    const arbitrary = structuredClone(h.operation);
    (arbitrary.desired.values[0].value as { value: number }).value = 0.5;
    await expect(h.adapter.bridge.apply(arbitrary)).rejects.toThrow(/observed eye choices/);
    h.transport.apply.mockResolvedValueOnce({ status: "verified", operation: "apply", requestId: "other", eyeRevision: 1 });
    await expect(h.adapter.bridge.apply(h.operation)).rejects.toThrow();
    expect(h.transport.apply).toHaveBeenCalledTimes(2);
  });

  it("restores only exact original settings and passes genuine unverified results unchanged", async () => {
    const h = harness();
    await expect(h.adapter.bridge.restore(h.operation)).rejects.toThrow();
    const request = { ...h.operation, desired: h.session.original };
    expect((await h.adapter.bridge.restore(request)).status).toBe("verified");
    h.transport.apply.mockResolvedValueOnce({ status: "unverified", requestId: h.operation.requestId, reason: "Native evidence remains unaccepted." });
    expect((await h.adapter.bridge.apply(h.operation)).status).toBe("unverified");
  });

  it("uses fresh actual baseline inspection and reports asynchronous cancel failures", async () => {
    const h = harness();
    expect((await h.adapter.bridge.inspect(h.session.identity, h.session.baselineId)).settings).toEqual(h.session.current);
    await expect(h.adapter.bridge.inspect(h.session.identity, "foreign")).rejects.toThrow();
    h.transport.cancelQueued.mockRejectedValueOnce(new Error("Native cancellation failed."));
    h.adapter.bridge.cancelQueued(h.session);
    await vi.waitFor(() => expect(h.fault).toHaveBeenCalledOnce());
    expect(h.transport.restore).not.toHaveBeenCalled();
  });

  it("unsubscribes exactly once and ignores all late frames without restoring live eyes", () => {
    const h = harness(), receive = vi.fn();
    const unsubscribe = h.adapter.bridge.subscribeFrames(h.session, receive, vi.fn());
    h.adapter.dispose(); h.adapter.dispose(); unsubscribe(); h.emit(h.frame);
    expect(h.unsubscribe).toHaveBeenCalledOnce(); expect(receive).not.toHaveBeenCalled(); expect(h.transport.restore).not.toHaveBeenCalled();
    expect(() => h.adapter.bridge.subscribeFrames(h.session, receive, vi.fn())).toThrow();
  });

  it("handles synchronous disposal during a subscription's initial replay", () => {
    const h = harness();
    h.transport.subscribeFrames.mockImplementationOnce((_address, receive) => { receive(h.frame); return h.unsubscribe; });
    h.adapter.bridge.subscribeFrames(h.session, () => h.adapter.dispose(), vi.fn());
    expect(h.unsubscribe).toHaveBeenCalledOnce();
  });

  it("keeps private expected requests unchanged when transport mutates outgoing arguments", async () => {
    const h = harness();
    h.transport.updatePreview.mockImplementationOnce(async request => {
      (request as { eyeRevision: number }).eyeRevision = 99;
      return { ...request, status: "queued" };
    });
    await expect(h.adapter.bridge.updatePreview(h.request)).rejects.toThrow(/acknowledgement/);
    h.transport.apply.mockImplementationOnce(async request => {
      (request as { eyeRevision: number }).eyeRevision = 99;
      return { status: "verified", operation: "apply", requestId: request.requestId, eyeRevision: request.eyeRevision,
        readback: { source: "runtime-material-getter", identity: request.identity, baselineId: request.baselineId,
          settings: request.desired, observationTiming: { requestSequence: 1, hostRequestSentAtMs: NOW - 50, hostReceiptReceivedAtMs: NOW - 10 } } };
    });
    await expect(h.adapter.bridge.apply(h.operation)).rejects.toThrow(/receipt/);
    expect(h.request.eyeRevision).toBe(0); expect(h.operation.eyeRevision).toBe(1);
  });
});
