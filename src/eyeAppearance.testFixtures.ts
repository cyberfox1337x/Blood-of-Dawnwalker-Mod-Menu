import type { EyeOperationReceipt, EyeOperationRequest, EyePreviewFrame, EyePreviewRequest, EyeReadback, EyeSettings, ReadyEyeSession } from "./eyeAppearanceContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_ui_mock_test_fixtures");

// Test doubles only. This module contains no character/model assets and is
// imported exclusively by tests; it cannot establish native feature readiness.
export function mockEyeSession(): ReadyEyeSession {
  const parameter = { slotId: "test-head-slot", materialId: "test-eye-binding", name: "TestObservedColor", association: 0, index: -1 };
  const original: EyeSettings = { schemaId: "test-schema", values: [{ parameter, value: { kind: "vector", value: [0, 1, 0, 0.4] } }] };
  const ruby: EyeSettings = { schemaId: "test-schema", values: [{ parameter, value: { kind: "vector", value: [1, 0, 0, 0.4] } }] };
  const blue: EyeSettings = { schemaId: "test-schema", values: [{ parameter, value: { kind: "vector", value: [0, 0, 1, 0.4] } }] };
  const domain = { min: 0, max: 1, readbackTolerance: 0.000001 };
  return {
    availability: "ready", identity: { buildId: "test-build", sessionId: "test-session", worldGeneration: "test-world",
      pawnId: "test-pawn", appearanceRevision: "test-appearance", form: "human", isWolfForm: false,
      meshId: "test-head", eyeMaterialGeneration: "test-material" },
    previewId: "test-preview", renderTargetGeneration: "test-target", baselineId: "test-baseline", original, current: original,
    schema: { id: "test-schema", parameters: [{ parameter, label: "Iris", kind: "vector", domains: [domain, domain, domain, domain], picker: { colorSpace: "linear-srgb" } }],
      presets: [{ id: "original", label: "Original green", settings: original }, { id: "ruby", label: "Test red", settings: ruby }, { id: "blue", label: "Test blue", settings: blue }] },
    zoomBounds: { "head-and-shoulders": { min: 1, max: 2, initial: 1.25, step: 0.1 }, "eyes-close-up": { min: 3, max: 4, initial: 3.25, step: 0.1 } },
    maxFrameAgeMs: 1000, maxReadbackAgeMs: 2000, diagnostics: ["Mocked UI test; actual game rendering and materials are not exercised."],
    evidence: { actualPlayerModel: true, isolatedPreviewInput: true, correspondingEyeMaterials: true, reversibleLiveSetter: true,
      supportedForms: [{ form: "human", schemaId: "test-schema", originalRestore: true }], verifiedTransitions: [] },
  };
}

let mockRequestSequence = 0;
export function mockEyeTiming() {
  return { requestSequence: ++mockRequestSequence, hostRequestSentAtMs: Date.now() - 10, hostReceiptReceivedAtMs: Date.now() };
}

export function mockEyeReadback(session: ReadyEyeSession, settings = session.current): EyeReadback {
  return { source: "runtime-material-getter", identity: session.identity, baselineId: session.baselineId, observationTiming: mockEyeTiming(), settings };
}

export function mockEyeReceipt(request: EyeOperationRequest, operation: "apply" | "restore" = "apply"): EyeOperationReceipt {
  return { status: "verified", operation, requestId: request.requestId, eyeRevision: request.eyeRevision,
    readback: { source: "runtime-material-getter", identity: request.identity, baselineId: request.baselineId, observationTiming: mockEyeTiming(), settings: request.desired } };
}

export function mockEyeFrame(request: EyePreviewRequest, sequence: number): EyePreviewFrame {
  return { ...request, source: "native-scene-capture", sequence, captureTiming: { ...mockEyeTiming(), kind: "native-call-interval",
    nativeClockId: "test-native-clock", nativeStartedMs: sequence * 100, nativeCompletedMs: sequence * 100 + 5, renderCompletedAtMs: null }, width: 300, height: 300,
    image: new Blob(["mock-frame-decoding-is-stubbed-in-tests"], { type: "image/png" }) };
}
