import {
  eyeCaptureFresh, eyeIdentityMatches, eyeObservationFresh, eyeParameterKey, eyeReceiptMatches,
  eyeSettingsMatch, eyeSettingsSupported, eyeViewSupported, validateEyeSession,
  type EyeAppearanceBridge, type EyeAppearanceSession, type EyeOperationReceipt,
  type EyeOperationRequest, type EyePreviewAddress, type EyePreviewFrame,
  type EyePreviewRequest, type EyeReadback, type ReadyEyeSession,
} from "./eyeAppearanceContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_desktop_transport");

// Renderer-side facade only. No IPC registration, native connection, timer,
// capability promotion or ReadyEyeSession construction occurs in this module.
export type EyeDesktopFrame = Omit<EyePreviewFrame, "image"> & Readonly<{ pngBytes: Uint8Array }>;
export type EyeDesktopPreviewAck = EyePreviewAddress & Readonly<{
  status: "queued" | "unchanged" | "superseded"; viewRevision: number; eyeRevision: number;
}>;
export type EyeDesktopCancelAck = EyePreviewAddress & Readonly<{ status: "cancelled" }>;

export interface EyeDesktopTransport {
  subscribeFrames(address: EyePreviewAddress, receive: (frame: unknown) => void, fail: (error: unknown) => void): () => void;
  updatePreview(request: EyePreviewRequest): Promise<unknown>;
  apply(request: EyeOperationRequest, address: EyePreviewAddress): Promise<unknown>;
  restore(request: EyeOperationRequest, address: EyePreviewAddress): Promise<unknown>;
  inspect(identity: EyePreviewAddress["identity"], baselineId: string): Promise<unknown>;
  cancelQueued(address: EyePreviewAddress): Promise<unknown>;
}

const MAX_PNG_BYTES = 16 * 1024 * 1024;
const HUMAN_SCHEMA = "dawnwalker-human-iris-uv-v1-25129649";
const NAMES = ["IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V"];

function requireCondition(condition: unknown, reason: string): asserts condition {
  if (!condition) throw new Error(reason);
}

function copy<T>(value: T): T { return structuredClone(value); }

function sameAddress(left: EyePreviewAddress, right: EyePreviewAddress): boolean {
  return Boolean(left && left.identity && eyeIdentityMatches(left.identity, right.identity)
    && left.previewId === right.previewId && left.renderTargetGeneration === right.renderTargetGeneration);
}

export function readEyeDesktopSession(candidate: unknown): EyeAppearanceSession {
  requireCondition(candidate && typeof candidate === "object", "Eye session response is missing.");
  const session = copy(candidate) as EyeAppearanceSession;
  requireCondition(Array.isArray(session.diagnostics) && session.diagnostics.length <= 32
    && session.diagnostics.every(detail => typeof detail === "string" && detail.length <= 1024), "Eye diagnostics are invalid.");
  if (session.availability === "unavailable") {
    requireCondition(typeof session.reason === "string" && session.reason.length > 0 && session.reason.length <= 1024, "Eye availability reason is invalid.");
    return session;
  }
  requireCondition(session.availability === "ready" && validateEyeSession(session), "The native eye session has not established its required evidence.");
  requireCondition(session.identity.buildId === "25129649" && session.identity.form === "human" && !session.identity.isWolfForm
    && session.schema.id === HUMAN_SCHEMA && session.schema.parameters.length === 8, "This desktop adapter supports only the verified human eye schema.");
  requireCondition(session.evidence.supportedForms.length === 1 && session.evidence.supportedForms[0].form === "human"
    && session.evidence.verifiedTransitions.length === 0, "This desktop adapter does not claim verified cross-form support.");
  for (let index = 0; index < 8; index++) {
    const expectedSlot = index < 4 ? "head:3" : "head:4";
    const expectedMaterial = index < 4 ? "coen-human-eye-left" : "coen-human-eye-right";
    const parameter = session.schema.parameters[index];
    requireCondition(parameter.kind === "scalar" && parameter.parameter.slotId === expectedSlot
      && parameter.parameter.materialId === expectedMaterial && parameter.parameter.name === NAMES[index % 4]
      && parameter.parameter.association === 2 && parameter.parameter.index === -1, "Unsupported human eye parameter identity.");
  }
  requireCondition(session.schema.presets.length === 2 && session.schema.presets[0].id === "original"
    && session.schema.presets[0].label === "Original" && session.schema.presets[1].id === "alternate"
    && session.schema.presets[1].label === "Alternate", "Human eye presets must describe only the observed pair.");
  requireCondition(eyeSettingsMatch(session.schema.presets[0].settings, session.original, session.schema), "Original preset does not match the native baseline.");
  const alternate = { ...copy(session.original), values: session.schema.parameters.map(definition =>
    copy(session.original.values.find(entry => eyeParameterKey(entry.parameter) === eyeParameterKey(definition.parameter))!)) };
  const swapped = alternate.values.map((entry, index) => ({ ...entry, value: copy(alternate.values[index < 4
    ? [2, 3, 0, 1][index] : [6, 7, 4, 5][index - 4]].value) }));
  requireCondition(eyeSettingsMatch(session.schema.presets[1].settings, { ...alternate, values: swapped }, session.schema), "Alternate preset does not match the observed iris-pair swap.");
  return session;
}

export function createEyeDesktopBridge(input: ReadyEyeSession, transport: EyeDesktopTransport,
  onFault: (error: unknown) => void, now: () => number = Date.now): Readonly<{ bridge: EyeAppearanceBridge; dispose(): void }> {
  const candidate = readEyeDesktopSession(input);
  requireCondition(candidate.availability === "ready", "A supported native session is required.");
  const session = candidate;
  let disposed = false;
  const subscriptions = new Set<() => void>();
  function address(value: EyePreviewAddress): void {
    requireCondition(!disposed && sameAddress(value, session), "Eye preview address is stale or closed.");
  }
  function request(value: EyeOperationRequest, operation: "apply" | "restore"): void {
    requireCondition(!disposed && eyeIdentityMatches(value.identity, session.identity) && value.baselineId === session.baselineId,
      "Eye operation belongs to another native baseline.");
    requireCondition(typeof value.requestId === "string" && value.requestId.length > 0 && value.requestId.length <= 128
      && Number.isSafeInteger(value.eyeRevision) && value.eyeRevision >= 0, "Eye request identity or revision is invalid.");
    requireCondition(eyeSettingsSupported(value.desired, session.schema) && (operation === "restore"
      ? eyeSettingsMatch(value.desired, session.original, session.schema)
      : session.schema.presets.some(preset => eyeSettingsMatch(value.desired, preset.settings, session.schema))), "Only the observed eye choices can be applied.");
  }
  async function operation(kind: "apply" | "restore", value: EyeOperationRequest): Promise<EyeOperationReceipt> {
    request(value, kind);
    const expected = copy(value);
    // Local revision numbers restart for each mounted preview. Carry its bound
    // address so a delayed IPC request cannot enter a newer native lease.
    const boundAddress = { identity: copy(session.identity), previewId: session.previewId, renderTargetGeneration: session.renderTargetGeneration };
    const result = copy(await transport[kind](copy(expected), boundAddress)) as EyeOperationReceipt;
    requireCondition(!disposed, "Eye desktop bridge closed while awaiting the native operation.");
    if (result.status === "verified") {
      requireCondition(eyeReceiptMatches(result, expected, kind, session, now()), "Eye native receipt does not match the request.");
    } else {
      requireCondition(["rejected", "timeout", "unverified"].includes(result.status) && result.requestId === expected.requestId
        && typeof result.reason === "string" && result.reason.length > 0 && result.reason.length <= 1024, "Eye failure receipt is invalid.");
    }
    return result;
  }
  const bridge: EyeAppearanceBridge = {
    subscribeFrames(value, receive, fail) {
      address(value);
      let closed = false, latest = 0;
      let stop: (() => void) | undefined;
      const unsubscribe = () => { if (!closed) { closed = true; subscriptions.delete(unsubscribe); stop?.(); } };
      subscriptions.add(unsubscribe);
      const receiveFrame = (raw: unknown) => {
        if (closed || disposed) return;
        try {
          const frame = raw as EyeDesktopFrame;
          requireCondition(sameAddress(frame, session) && frame.source === "native-scene-capture"
            && Number.isSafeInteger(frame.sequence) && frame.sequence > latest && frame.sequence <= 1200, "Eye frame generation or sequence is invalid.");
          requireCondition(Number.isSafeInteger(frame.viewRevision) && frame.viewRevision >= 0
            && Number.isSafeInteger(frame.eyeRevision) && frame.eyeRevision >= 0
            && eyeViewSupported(frame.view, session) && eyeSettingsSupported(frame.settings, session.schema)
            && eyeCaptureFresh(frame.captureTiming, now(), session.maxFrameAgeMs), "Eye frame settings, view or age is invalid.");
          requireCondition(frame.width === 1024 && frame.height === 1024 && frame.pngBytes instanceof Uint8Array
            && frame.pngBytes.byteLength >= 33 && frame.pngBytes.byteLength <= MAX_PNG_BYTES, "Eye frame payload exceeds its native bounds.");
          // Main has already performed immutable file and full PNG validation.
          // Copy only its normalized prefix; never share its backing buffer.
          const bytes = Uint8Array.from(frame.pngBytes);
          const signature = [137, 80, 78, 71, 13, 10, 26, 10];
          requireCondition(signature.every((byte, index) => bytes[index] === byte), "Eye frame is not a PNG payload.");
          const header = new DataView(bytes.buffer);
          requireCondition(header.getUint32(8) === 13 && header.getUint32(12) === 0x49484452
            && header.getUint32(16) === frame.width && header.getUint32(20) === frame.height, "Eye PNG header does not match its receipt.");
          latest = frame.sequence;
          receive({ identity: copy(frame.identity), previewId: frame.previewId, renderTargetGeneration: frame.renderTargetGeneration,
            source: "native-scene-capture", sequence: frame.sequence, viewRevision: frame.viewRevision, eyeRevision: frame.eyeRevision,
            view: copy(frame.view), settings: copy(frame.settings), captureTiming: copy(frame.captureTiming),
            width: frame.width, height: frame.height, image: new Blob([bytes], { type: "image/png" }) });
        } catch (error) { fail(error); }
      };
      try {
        stop = transport.subscribeFrames(copy(value), receiveFrame, error => { if (!closed && !disposed) fail(error); });
        if (closed || disposed) stop();
      } catch (error) { unsubscribe(); throw error; }
      return unsubscribe;
    },
    async updatePreview(value) {
      address(value);
      requireCondition(Number.isSafeInteger(value.viewRevision) && value.viewRevision >= 0
        && Number.isSafeInteger(value.eyeRevision) && value.eyeRevision >= 0 && eyeViewSupported(value.view, session)
        && eyeSettingsSupported(value.settings, session.schema) && (eyeSettingsMatch(value.settings, session.current, session.schema)
          || session.schema.presets.some(preset => eyeSettingsMatch(value.settings, preset.settings, session.schema))), "Eye preview request is invalid.");
      const expected = copy(value);
      const ack = await transport.updatePreview(copy(expected)) as EyeDesktopPreviewAck;
      requireCondition(!disposed && sameAddress(ack, session) && ["queued", "unchanged", "superseded"].includes(ack.status)
        && ack.viewRevision === expected.viewRevision && ack.eyeRevision === expected.eyeRevision, "Eye preview acknowledgement does not match the request.");
    },
    apply: value => operation("apply", value),
    restore: value => operation("restore", value),
    async inspect(identity, baselineId) {
      requireCondition(!disposed && eyeIdentityMatches(identity, session.identity) && baselineId === session.baselineId, "Eye inspection baseline is stale.");
      const result = copy(await transport.inspect(copy(identity), baselineId)) as EyeReadback;
      requireCondition(!disposed && result.source === "runtime-material-getter" && eyeIdentityMatches(result.identity, session.identity)
        && result.baselineId === baselineId && eyeSettingsSupported(result.settings, session.schema)
        && eyeObservationFresh(result.observationTiming, now(), session.maxReadbackAgeMs), "Eye inspection is stale or belongs to another baseline.");
      return result;
    },
    cancelQueued(value) {
      address(value);
      // The component's void API still needs a handled, observable IPC failure.
      void transport.cancelQueued(copy(value)).then(raw => {
        const ack = raw as EyeDesktopCancelAck;
        requireCondition(sameAddress(ack, session) && ack.status === "cancelled", "Eye cancellation acknowledgement does not match the preview.");
      }).catch(onFault);
    },
  };
  return { bridge, dispose() { if (!disposed) { disposed = true; for (const stop of [...subscriptions]) stop(); } } };
}
