const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_appearance_ui_contract");

// This boundary is deliberately separate from the gameplay bridge. No ready
// session is constructed here: its native renderer and reversible material
// adapter must establish these capabilities before the component is mounted.
export type EyeIdentity = Readonly<{
  buildId: string;
  sessionId: string;
  worldGeneration: string;
  pawnId: string;
  appearanceRevision: string;
  form: "human" | "vampire";
  isWolfForm: boolean;
  meshId: string;
  eyeMaterialGeneration: string;
}>;

export type EyeParameterIdentity = Readonly<{
  slotId: string;
  // Stable verified binding identity, not a silently replaced MID address.
  materialId: string;
  name: string;
  association: number;
  index: number;
}>;

export type EyeValue =
  | Readonly<{ kind: "scalar"; value: number }>
  | Readonly<{ kind: "vector"; value: readonly [number, number, number, number] }>
  | Readonly<{ kind: "texture"; supportedTextureId: string }>;

export type EyeSettings = Readonly<{
  schemaId: string;
  values: readonly Readonly<{ parameter: EyeParameterIdentity; value: EyeValue }>[];
}>;

type NumberDomain = Readonly<{ min: number; max: number; readbackTolerance: number }>;
export type EyeParameterDefinition = Readonly<{
  parameter: EyeParameterIdentity;
  label: string;
}> & (
  | Readonly<{ kind: "scalar"; domain: NumberDomain }>
  | Readonly<{
      kind: "vector";
      domains: readonly [NumberDomain, NumberDomain, NumberDomain, NumberDomain];
      // Present only when exact shader semantics and conversion were verified.
      picker?: Readonly<{ colorSpace: "srgb" | "linear-srgb" }>;
    }>
  | Readonly<{ kind: "texture"; allowedTextureIds: readonly string[] }>
);

export type EyeSchema = Readonly<{
  id: string;
  parameters: readonly EyeParameterDefinition[];
  presets: readonly Readonly<{ id: string; label: string; settings: EyeSettings }>[];
}>;

export type EyeFraming = "head-and-shoulders" | "eyes-close-up";
export type EyeView = Readonly<{ yawDegrees: number; framing: EyeFraming; zoom: number }>;
export type EyeZoomBounds = Readonly<{ min: number; max: number; initial: number; step: number }>;

export type EyePreviewAddress = Readonly<{
  identity: EyeIdentity;
  previewId: string;
  renderTargetGeneration: string;
}>;

export type EyePreviewRequest = EyePreviewAddress & Readonly<{
  viewRevision: number;
  eyeRevision: number;
  view: EyeView;
  settings: EyeSettings;
}>;

// These are actual host timestamps for one serialized native request. The
// earliest bound stays fixed even if the response/file is read again later.
export type EyeObservationTiming = Readonly<{
  requestSequence: number;
  hostRequestSentAtMs: number;
  hostReceiptReceivedAtMs: number;
}>;

export type EyeCaptureTiming = EyeObservationTiming & Readonly<{
  kind: "native-call-interval";
  nativeClockId: string;
  nativeStartedMs: number;
  nativeCompletedMs: number;
  // CaptureScene followed by ExportRenderTarget provides a native call interval,
  // not a GPU completion timestamp. Its matching pixels are verified separately.
  renderCompletedAtMs: null;
}>;

export type EyePreviewFrame = EyePreviewAddress & Readonly<{
  source: "native-scene-capture";
  sequence: number;
  viewRevision: number;
  eyeRevision: number;
  settings: EyeSettings;
  view: EyeView;
  captureTiming: EyeCaptureTiming;
  width: number;
  height: number;
  image: Blob;
}>;

export type EyeReadback = Readonly<{
  source: "runtime-material-getter";
  identity: EyeIdentity;
  baselineId: string;
  observationTiming: EyeObservationTiming;
  settings: EyeSettings;
}>;

export type EyeOperationRequest = Readonly<{
  identity: EyeIdentity;
  baselineId: string;
  requestId: string;
  eyeRevision: number;
  desired: EyeSettings;
}>;

export type EyeOperationReceipt =
  | Readonly<{
      status: "verified";
      operation: "apply" | "restore";
      requestId: string;
      eyeRevision: number;
      readback: EyeReadback;
    }>
  | Readonly<{ status: "rejected" | "timeout" | "unverified"; requestId: string; reason: string }>;

export type ReadyEyeSession = EyePreviewAddress & Readonly<{
  availability: "ready";
  baselineId: string;
  schema: EyeSchema;
  original: EyeSettings;
  current: EyeSettings;
  zoomBounds: Readonly<Record<EyeFraming, EyeZoomBounds>>;
  maxFrameAgeMs: number;
  maxReadbackAgeMs: number;
  diagnostics: readonly string[];
  evidence: Readonly<{
    actualPlayerModel: true;
    isolatedPreviewInput: true;
    correspondingEyeMaterials: true;
    reversibleLiveSetter: true;
    // Evidence belongs to the exact listed form/schema. An unsupported form
    // invalidates this session; an empty transition list claims no cross-form test.
    supportedForms: readonly Readonly<{ form: EyeIdentity["form"]; schemaId: string; originalRestore: true }>[];
    verifiedTransitions: readonly Readonly<{ from: EyeIdentity["form"]; to: EyeIdentity["form"] }>[];
  }>;
}>;

export type EyeAppearanceSession = ReadyEyeSession | Readonly<{
  availability: "unavailable";
  reason: string;
  diagnostics: readonly string[];
}>;

export interface EyeAppearanceBridge {
  subscribeFrames(address: EyePreviewAddress, onFrame: (frame: EyePreviewFrame) => void, onError: (error: unknown) => void): () => void;
  // Alters only the independently owned native preview doll/capture.
  updatePreview(request: EyePreviewRequest): Promise<void>;
  apply(request: EyeOperationRequest): Promise<EyeOperationReceipt>;
  restore(request: EyeOperationRequest): Promise<EyeOperationReceipt>;
  inspect(identity: EyeIdentity, baselineId: string): Promise<EyeReadback>;
  // Cancels queued work only. It never restores eyes or transforms the player.
  cancelQueued(address: EyePreviewAddress): void;
}

const identityKeys = ["buildId", "sessionId", "worldGeneration", "pawnId", "appearanceRevision", "form", "isWolfForm", "meshId", "eyeMaterialGeneration"] as const;

export function eyeIdentityMatches(left: EyeIdentity, right: EyeIdentity): boolean {
  return identityKeys.every(key => left[key] === right[key]);
}

export function eyeParameterKey(parameter: EyeParameterIdentity): string {
  return JSON.stringify([parameter.slotId, parameter.materialId, parameter.name, parameter.association, parameter.index]);
}

export function clampEyeYaw(yaw: number): number {
  return Number.isFinite(yaw) ? Math.max(-69, Math.min(69, yaw)) : 0;
}

export function clampEyeZoom(zoom: number, bounds: EyeZoomBounds): number {
  return Number.isFinite(zoom) ? Math.max(bounds.min, Math.min(bounds.max, zoom)) : bounds.initial;
}

export function eyeViewSupported(view: EyeView | undefined, session: ReadyEyeSession): view is EyeView {
  if (!view || !["head-and-shoulders", "eyes-close-up"].includes(view.framing)
    || !Number.isFinite(view.yawDegrees) || view.yawDegrees < -69 || view.yawDegrees > 69 || !Number.isFinite(view.zoom)) return false;
  const bounds = session.zoomBounds[view.framing];
  return view.zoom >= bounds.min && view.zoom <= bounds.max;
}

function within(value: number, domain: NumberDomain): boolean {
  return Number.isFinite(value) && value >= domain.min && value <= domain.max;
}

export function eyeSettingsSupported(settings: EyeSettings, schema: EyeSchema): boolean {
  if (settings.schemaId !== schema.id || settings.values.length !== schema.parameters.length) return false;
  const values = new Map(settings.values.map(entry => [eyeParameterKey(entry.parameter), entry.value]));
  if (values.size !== settings.values.length) return false;
  return schema.parameters.every(definition => {
    const value = values.get(eyeParameterKey(definition.parameter));
    if (!value || value.kind !== definition.kind) return false;
    if (value.kind === "scalar" && definition.kind === "scalar") return within(value.value, definition.domain);
    if (value.kind === "vector" && definition.kind === "vector") return value.value.length === 4 && value.value.every((channel, index) => within(channel, definition.domains[index]));
    return value.kind === "texture" && definition.kind === "texture" && definition.allowedTextureIds.includes(value.supportedTextureId);
  });
}

export function eyeSettingsMatch(left: EyeSettings, right: EyeSettings, schema: EyeSchema): boolean {
  if (!eyeSettingsSupported(left, schema) || !eyeSettingsSupported(right, schema)) return false;
  const values = new Map(right.values.map(entry => [eyeParameterKey(entry.parameter), entry.value]));
  return left.values.every(entry => {
    const value = values.get(eyeParameterKey(entry.parameter));
    const definition = schema.parameters.find(item => eyeParameterKey(item.parameter) === eyeParameterKey(entry.parameter));
    if (entry.value.kind === "scalar" && value?.kind === "scalar" && definition?.kind === "scalar") return Math.abs(entry.value.value - value.value) <= definition.domain.readbackTolerance;
    if (entry.value.kind === "vector" && value?.kind === "vector" && definition?.kind === "vector") return entry.value.value.every((channel, index) => Math.abs(channel - value.value[index]) <= definition.domains[index].readbackTolerance);
    return entry.value.kind === "texture" && value?.kind === "texture" && entry.value.supportedTextureId === value.supportedTextureId;
  });
}

export function eyeObservationFresh(timing: EyeObservationTiming | undefined, now: number, maximumAge: number): boolean {
  return Boolean(timing && Number.isSafeInteger(timing.requestSequence) && timing.requestSequence > 0
    && [timing.hostRequestSentAtMs, timing.hostReceiptReceivedAtMs, now, maximumAge].every(Number.isFinite)
    && timing.hostRequestSentAtMs > 0 && timing.hostReceiptReceivedAtMs >= timing.hostRequestSentAtMs
    && timing.hostReceiptReceivedAtMs <= now + 250 && maximumAge >= 0
    && now - timing.hostRequestSentAtMs <= maximumAge);
}

export function eyeCaptureFresh(timing: EyeCaptureTiming | undefined, now: number, maximumAge: number): boolean {
  return Boolean(eyeObservationFresh(timing, now, maximumAge) && timing
    && timing.kind === "native-call-interval" && typeof timing.nativeClockId === "string" && timing.nativeClockId.length > 0
    && Number.isFinite(timing.nativeStartedMs) && Number.isFinite(timing.nativeCompletedMs)
    && timing.nativeStartedMs >= 0 && timing.nativeCompletedMs >= timing.nativeStartedMs
    && timing.renderCompletedAtMs === null);
}

export function validateEyeSession(session: ReadyEyeSession): boolean {
  const validDomain = (domain: NumberDomain) => Number.isFinite(domain.min) && Number.isFinite(domain.max) && domain.max >= domain.min && Number.isFinite(domain.readbackTolerance) && domain.readbackTolerance >= 0 && domain.readbackTolerance <= Math.max(1, domain.max - domain.min) * 0.001;
  if (![session.evidence.actualPlayerModel, session.evidence.isolatedPreviewInput, session.evidence.correspondingEyeMaterials,
    session.evidence.reversibleLiveSetter].every(value => value === true)) return false;
  const forms = session.evidence.supportedForms;
  const transitions = session.evidence.verifiedTransitions;
  if (!Array.isArray(forms) || forms.length < 1 || forms.length > 2 || new Set(forms.map(item => item.form)).size !== forms.length
    || forms.some(item => !["human", "vampire"].includes(item.form) || !item.schemaId || item.originalRestore !== true)
    || !forms.some(item => item.form === session.identity.form && item.schemaId === session.schema.id)
    || !Array.isArray(transitions) || transitions.some(item => !["human", "vampire"].includes(item.from)
      || !["human", "vampire"].includes(item.to) || item.from === item.to)) return false;
  if (identityKeys.some(key => key !== "isWolfForm" && (typeof session.identity[key] !== "string" || !session.identity[key]))) return false;
  if (typeof session.identity.isWolfForm !== "boolean" || session.identity.isWolfForm || !["human", "vampire"].includes(session.identity.form)) return false;
  if (![session.previewId, session.renderTargetGeneration, session.baselineId, session.schema.id].every(value => typeof value === "string" && value.length > 0)) return false;
  if (session.schema.parameters.length < 1 || session.schema.parameters.length > 64 || session.schema.presets.length > 32) return false;
  if (new Set(session.schema.parameters.map(definition => eyeParameterKey(definition.parameter))).size !== session.schema.parameters.length || new Set(session.schema.presets.map(preset => preset.id)).size !== session.schema.presets.length) return false;
  for (const definition of session.schema.parameters) {
    const parameter = definition.parameter;
    if (![parameter.slotId, parameter.materialId, parameter.name, definition.label].every(value => typeof value === "string" && value.length > 0)
      || !Number.isInteger(parameter.association) || parameter.association < 0 || parameter.association > 2
      || !Number.isInteger(parameter.index) || parameter.index < -1 || parameter.index > 128) return false;
    if (definition.kind === "scalar" && !validDomain(definition.domain)) return false;
    if (definition.kind === "vector" && (definition.domains.length !== 4 || !definition.domains.every(validDomain))) return false;
    if (definition.kind === "vector" && definition.picker && (definition.domains.slice(0, 3).some(domain => domain.min > 0 || domain.max < 1) || !["srgb", "linear-srgb"].includes(definition.picker.colorSpace))) return false;
    if (definition.kind === "texture" && (definition.allowedTextureIds.length === 0 || definition.allowedTextureIds.length > 64)) return false;
  }
  if (![session.current, session.original, ...session.schema.presets.map(preset => preset.settings)].every(settings => eyeSettingsSupported(settings, session.schema))) return false;
  for (const framing of ["head-and-shoulders", "eyes-close-up"] as const) {
    const bounds = session.zoomBounds[framing];
    if (!bounds || ![bounds.min, bounds.max, bounds.initial, bounds.step].every(Number.isFinite) || bounds.max <= bounds.min || bounds.initial < bounds.min || bounds.initial > bounds.max || bounds.step <= 0 || bounds.step > bounds.max - bounds.min) return false;
  }
  return [session.maxFrameAgeMs, session.maxReadbackAgeMs].every(age => Number.isFinite(age) && age >= 250 && age <= 5000);
}

export function eyeReceiptMatches(receipt: EyeOperationReceipt, request: EyeOperationRequest, operation: "apply" | "restore", session: ReadyEyeSession, now: number): boolean {
  return eyeIdentityMatches(request.identity, session.identity) && request.baselineId === session.baselineId
    && receipt.status === "verified" && receipt.operation === operation && receipt.requestId === request.requestId && receipt.eyeRevision === request.eyeRevision
    && receipt.readback.source === "runtime-material-getter" && eyeIdentityMatches(receipt.readback.identity, request.identity)
    && receipt.readback.baselineId === request.baselineId && eyeObservationFresh(receipt.readback.observationTiming, now, session.maxReadbackAgeMs)
    && eyeSettingsMatch(receipt.readback.settings, request.desired, session.schema);
}

export function eyePickerHex(settings: EyeSettings, definition: EyeParameterDefinition): string | undefined {
  if (definition.kind !== "vector" || !definition.picker) return undefined;
  const value = settings.values.find(entry => eyeParameterKey(entry.parameter) === eyeParameterKey(definition.parameter))?.value;
  if (value?.kind !== "vector" || value.value.slice(0, 3).some(channel => !Number.isFinite(channel) || channel < 0 || channel > 1)) return undefined;
  return "#" + value.value.slice(0, 3).map(channel => {
    const encoded = definition.picker?.colorSpace === "linear-srgb" ? (channel <= 0.0031308 ? 12.92 * channel : 1.055 * channel ** (1 / 2.4) - 0.055) : channel;
    return Math.round(encoded * 255).toString(16).padStart(2, "0");
  }).join("");
}

export function eyeSettingsWithColor(settings: EyeSettings, definition: EyeParameterDefinition, hex: string): EyeSettings | undefined {
  if (definition.kind !== "vector" || !definition.picker || !/^#[0-9a-f]{6}$/i.test(hex)) return undefined;
  const rgb = [1, 3, 5].map(index => {
    const value = parseInt(hex.slice(index, index + 2), 16) / 255;
    return definition.picker?.colorSpace === "linear-srgb" ? (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4) : value;
  });
  const key = eyeParameterKey(definition.parameter);
  return { ...settings, values: settings.values.map(entry => eyeParameterKey(entry.parameter) === key && entry.value.kind === "vector"
    ? { ...entry, value: { kind: "vector", value: [rgb[0], rgb[1], rgb[2], entry.value.value[3]] } }
    : entry) };
}

/** Serializes native requests while retaining only the latest waiting value. */
export class EyeLatestQueue<T> {
  private waiting: { value: T } | undefined;
  private running = false;
  private closed = false;

  constructor(private readonly execute: (value: T) => Promise<void>) {}

  enqueue(value: T): void {
    if (this.closed) return;
    this.waiting = { value };
    void this.drain();
  }

  close(): void { this.closed = true; this.waiting = undefined; }
  clear(): void { this.waiting = undefined; }

  private async drain(): Promise<void> {
    if (this.running || this.closed) return;
    this.running = true;
    try {
      while (this.waiting && !this.closed) {
        const next = this.waiting.value;
        this.waiting = undefined;
        await this.execute(next);
      }
    } finally { this.running = false; }
  }
}
