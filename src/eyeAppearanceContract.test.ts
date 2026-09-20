import { describe, expect, it } from "vitest";
import {
  EyeLatestQueue, clampEyeYaw, clampEyeZoom, eyePickerHex, eyeReceiptMatches,
  eyeSettingsMatch, eyeSettingsSupported, eyeSettingsWithColor, eyeObservationFresh, eyeCaptureFresh, validateEyeSession,
  type EyeOperationRequest, type EyeParameterDefinition,
} from "./eyeAppearanceContract";
import { mockEyeReceipt, mockEyeSession } from "./eyeAppearance.testFixtures";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_ui_contract_tests");

describe("eye appearance native boundary", () => {
  it("requires complete readiness evidence, a supported form, and proven camera bounds", () => {
    const session = mockEyeSession();
    expect(validateEyeSession(session)).toBe(true);
    expect(validateEyeSession({ ...session, evidence: { ...session.evidence, reversibleLiveSetter: false as never } })).toBe(false);
    expect(validateEyeSession({ ...session, identity: { ...session.identity, isWolfForm: true } })).toBe(false);
    expect(session.evidence.verifiedTransitions).toEqual([]);
    expect(validateEyeSession({ ...session, identity: { ...session.identity, form: "vampire" } })).toBe(false);
    expect(validateEyeSession({ ...session, evidence: { ...session.evidence,
      supportedForms: [{ form: "human", schemaId: "another-schema", originalRestore: true }] } })).toBe(false);
    expect(validateEyeSession({ ...session, zoomBounds: { ...session.zoomBounds, "eyes-close-up": { min: 1, max: 0, initial: 1, step: 0.1 } } })).toBe(false);
  });

  it("uses the host request's earliest bound without pretending to know GPU completion time", () => {
    const timing = { requestSequence: 7, hostRequestSentAtMs: 10000, hostReceiptReceivedAtMs: 10500 };
    const capture = { ...timing, kind: "native-call-interval" as const, nativeClockId: "test-native-clock",
      nativeStartedMs: 80, nativeCompletedMs: 90, renderCompletedAtMs: null };
    expect(eyeObservationFresh(timing, 11000, 1000)).toBe(true);
    expect(eyeCaptureFresh(capture, 11000, 1000)).toBe(true);
    expect(eyeCaptureFresh({ ...capture, hostReceiptReceivedAtMs: 12000 }, 12000, 1000)).toBe(false);
    expect(eyeCaptureFresh({ ...capture, nativeStartedMs: 91 }, 11000, 1000)).toBe(false);
    expect(eyeCaptureFresh({ ...capture, renderCompletedAtMs: 90 as never }, 11000, 1000)).toBe(false);
    expect(eyeCaptureFresh({ ...capture, nativeClockId: "" }, 11000, 1000)).toBe(false);
    expect(eyeObservationFresh({ ...timing, hostRequestSentAtMs: 10501 }, 11000, 1000)).toBe(false);
    expect(eyeObservationFresh({ ...timing, hostReceiptReceivedAtMs: 12000 }, 11000, 1000)).toBe(false);
    expect(eyeObservationFresh({ ...timing, requestSequence: 0 }, 11000, 1000)).toBe(false);
    expect(eyeCaptureFresh(undefined, 11000, 1000)).toBe(false);
  });

  it("rejects unknown parameter identities, duplicate values, and nonfinite values", () => {
    const session = mockEyeSession();
    const entry = session.current.values[0];
    expect(eyeSettingsSupported({ ...session.current, values: [{ ...entry, parameter: { ...entry.parameter, association: 1 } }] }, session.schema)).toBe(false);
    expect(eyeSettingsSupported({ ...session.current, values: [entry, entry] }, session.schema)).toBe(false);
    expect(eyeSettingsSupported({ ...session.current, values: [{ ...entry, value: { kind: "vector", value: [NaN, 0, 0, 1] } }] }, session.schema)).toBe(false);
    for (const parameter of [{ ...entry.parameter, name: "" }, { ...entry.parameter, association: 3 }, { ...entry.parameter, index: -2 }]) {
      expect(validateEyeSession({ ...session, schema: { ...session.schema, parameters: [{ ...session.schema.parameters[0], parameter }] } })).toBe(false);
    }
  });

  it("only exposes supported color conversion and preserves the observed alpha", () => {
    const session = mockEyeSession();
    const definition = session.schema.parameters[0];
    expect(eyePickerHex(session.current, definition)).toBe("#00ff00");
    const changed = eyeSettingsWithColor(session.current, definition, "#808080");
    expect(changed?.values[0].value.kind).toBe("vector");
    if (changed?.values[0].value.kind === "vector") {
      expect(changed.values[0].value.value[0]).toBeCloseTo(0.2158605, 6);
      expect(changed.values[0].value.value[3]).toBe(0.4);
      expect(eyePickerHex(changed, definition)).toBe("#808080");
    }
    const unsupported: EyeParameterDefinition = { parameter: definition.parameter, label: "Texture", kind: "texture", allowedTextureIds: ["observed-authorized-texture"] };
    expect(eyeSettingsWithColor(session.current, unsupported, "#ff0000")).toBeUndefined();
    expect(eyePickerHex(session.current, unsupported)).toBeUndefined();
  });

  it("never accepts an old request and receipt against a replacement session or baseline", () => {
    const session = mockEyeSession();
    const request: EyeOperationRequest = { identity: session.identity, baselineId: session.baselineId, requestId: "test-request", eyeRevision: 3, desired: session.current };
    const receipt = mockEyeReceipt(request);
    expect(eyeReceiptMatches(receipt, request, "apply", session, Date.now())).toBe(true);
    expect(eyeReceiptMatches(receipt, request, "restore", session, Date.now())).toBe(false);
    expect(eyeReceiptMatches(receipt, request, "apply", { ...session, identity: { ...session.identity, worldGeneration: "new-world" } }, Date.now())).toBe(false);
    expect(eyeReceiptMatches(receipt, request, "apply", { ...session, baselineId: "new-baseline" }, Date.now())).toBe(false);
    expect(eyeReceiptMatches(receipt, { ...request, eyeRevision: 4 }, "apply", session, Date.now())).toBe(false);
    expect(eyeReceiptMatches(receipt, { ...request, desired: session.schema.presets[1].settings }, "apply", session, Date.now())).toBe(false);
    expect(eyeReceiptMatches(receipt, request, "apply", session, Date.now() + session.maxReadbackAgeMs + 1)).toBe(false);
  });

  it("uses only the observed comparison tolerance for corresponding settings", () => {
    const session = mockEyeSession();
    const entry = session.current.values[0];
    const near = { ...session.current, values: [{ ...entry, value: { kind: "vector" as const, value: [0.0000001, 1, 0, 0.4] as const } }] };
    expect(eyeSettingsMatch(near, session.current, session.schema)).toBe(true);
    expect(eyeSettingsMatch(session.schema.presets[1].settings, session.current, session.schema)).toBe(false);
  });

  it("clamps rotation and model-provided zoom bounds without permitting nonfinite view state", () => {
    const bounds = mockEyeSession().zoomBounds["eyes-close-up"];
    expect(clampEyeYaw(-10000)).toBe(-69);
    expect(clampEyeYaw(10000)).toBe(69);
    expect(clampEyeYaw(NaN)).toBe(0);
    expect(clampEyeZoom(10000, bounds)).toBe(bounds.max);
    expect(clampEyeZoom(-10000, bounds)).toBe(bounds.min);
    expect(clampEyeZoom(Infinity, bounds)).toBe(bounds.initial);
  });

  it("serializes native work and coalesces repeated edits to the latest waiting value", async () => {
    const calls: number[] = [];
    let release: (() => void) | undefined;
    const queue = new EyeLatestQueue<number>(async value => {
      calls.push(value);
      if (value === 1) await new Promise<void>(resolve => { release = resolve; });
    });
    queue.enqueue(1);
    queue.enqueue(2);
    queue.enqueue(3);
    expect(calls).toEqual([1]);
    release?.();
    await Promise.resolve();
    await Promise.resolve();
    expect(calls).toEqual([1, 3]);
    queue.close();
    queue.enqueue(4);
    expect(calls).toEqual([1, 3]);
  });
});
