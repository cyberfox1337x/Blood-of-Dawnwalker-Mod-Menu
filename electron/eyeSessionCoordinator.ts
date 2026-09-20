import { randomBytes } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import type { createEyeNativeChannel, EyeNativeCommand } from "./eyeNativeChannel.js";
import { assertEyeResponseCorrespondence, HUMAN_IRIS_WIRE_KEYS, type HumanIrisWireSettings } from "./eyeNativeProtocol.js";
import { inspectNativeEyePngEvidence } from "./eyeFrameTransport.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_session_coordinator");

// Inert application adapter. Construction does not create a channel, schedule
// work, expose IPC, or promote prototype native evidence into a ready UI.
const SCHEMA = "dawnwalker-human-iris-uv-v1-25129649";
const NAMES = ["IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V"] as const;
const FRAMINGS = ["head-and-shoulders", "eyes-close-up"] as const;
type Fields = Readonly<Record<string, string>>;
type Channel = Pick<Awaited<ReturnType<typeof createEyeNativeChannel>>, "send" | "waitForTransport">;
type Exchange = Awaited<ReturnType<Channel["send"]>>;
export type EyeCoordinatorTiming = Exchange["timing"];
export type EyeCoordinatorObject = Readonly<{ name: string; address: string }>;
export type EyeCoordinatorParameter = Readonly<{ slotId: string; materialId: string; name: string; association: number; index: number }>;
export type EyeCoordinatorSettings = Readonly<{ schemaId: string; values: readonly Readonly<{
  parameter: EyeCoordinatorParameter; value: Readonly<{ kind: "scalar"; value: number }>;
}>[] }>;
export type EyeCoordinatorView = Readonly<{ yawDegrees: number; framing: typeof FRAMINGS[number]; zoom: number }>;
export type EyeCoordinatorTuple = Readonly<{ viewRevision: number; eyeRevision: number; view: EyeCoordinatorView; settings: EyeCoordinatorSettings }>;
type Domain = Readonly<{ parameter: EyeCoordinatorParameter; min: number; max: number; tolerance: number }>;
export type EyeCoordinatorDescriptor = Readonly<{
  identityKey: string; baselineId: string; schemaId: typeof SCHEMA;
  player: EyeCoordinatorObject; world: EyeCoordinatorObject; head: EyeCoordinatorObject; asset: EyeCoordinatorObject;
  form: "human"; isWolfForm: false; original: EyeCoordinatorSettings; current: EyeCoordinatorSettings;
  bindings: readonly Readonly<{ slot: number; slotName: string; original: EyeCoordinatorObject; current: EyeCoordinatorObject; parameters: readonly Domain[] }>[];
}>;
export type EyeCoordinatorPreview = Readonly<{
  actor: EyeCoordinatorObject; capture: EyeCoordinatorObject; target: EyeCoordinatorObject; targetOuter: EyeCoordinatorObject;
  width: number; height: number; renderTargetFormat: number; captureSource: number; targetGamma: number; forceLinearGamma?: boolean;
  zoomBounds: Readonly<Record<typeof FRAMINGS[number], Readonly<{ min: number; max: number; initial: number }>>>;
  // Keep native display/source observations available without assigning visual fidelity.
  nativeFields: Fields;
}>;
export type EyeCoordinatorFrameAddress = Readonly<{ bootId: string; previewNonce: string; sequence: number; fileName: string }>;
export type EyeCoordinatorFrameStore = Readonly<{
  /** Read only this exact native-frames/<boot>/<basename> into bounded memory.
   * Verify ordinary single-link file, every ancestor, immutable handle/stat/hash
   * and the full 16 MiB bound. remove() must revalidate that same snapshot before
   * unlinking and prove absence; never enumerate or accept a caller-selected root.
   * Coordinator performs PNG CRC/inflate normalization before removal/ACK. */
  read(address: EyeCoordinatorFrameAddress): Promise<{ nativeBytes: Uint8Array; remove(): Promise<void> }>;
  /** Explicit close recovery only: snapshot/remove a known ledger entry even if
   * partially exported, or prove already absent. Same path/identity protections. */
  discardKnown(address: EyeCoordinatorFrameAddress): Promise<void>;
}>;
export type EyeCoordinatorFrame = Readonly<{
  kind: "native-frame-evidence"; productionReady: false; previewVerified: false;
  sequence: number; viewRevision: number; eyeRevision: number; view: EyeCoordinatorView; settings: EyeCoordinatorSettings;
  width: number; height: number; pngBytes: Uint8Array;
  pngEvidence: ReturnType<typeof inspectNativeEyePngEvidence>;
  captureTiming: EyeCoordinatorTiming & Readonly<{ kind: "native-call-interval"; nativeClockId: string; nativeStartedMs: number; nativeCompletedMs: number; renderCompletedAtMs: null }>;
  nativeFields: Fields;
}>;
export type EyeCoordinatorResult = Readonly<{
  status: string; productionReady: false; timing: EyeCoordinatorTiming; nativeFields: Fields;
}>;
export type EyeCoordinatorReadback = EyeCoordinatorResult & Readonly<{
  descriptor: EyeCoordinatorDescriptor; operation: "inspect" | "apply" | "restore";
  nativeReadbackVerified: boolean; appliedInGame: false; originalBindingsRestored: boolean;
}>;
type Lease = { lease_id: string; preview_nonce: string; identity_key: string; baseline_id: string };

function check(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
function clone<T>(value: T): T { return structuredClone(value); }
function token(): string { return randomBytes(16).toString("hex"); }
function equal(a: unknown, b: unknown): boolean { return isDeepStrictEqual(a, b); }
function text(f: Fields, key: string): string {
  const value = f[key]; check(typeof value === "string" && value.length > 0 && value.length <= 2048 && !Array.from(value).some(character => character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127), `Missing or invalid native field: ${key}`); return value;
}
function number(f: Fields, key: string): number {
  const value = text(f, key); check(/^-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/u.test(value) && Number.isFinite(Number(value)), `Invalid native number: ${key}`); return Number(value);
}
function integer(f: Fields, key: string, min = 0, max = 2147483647): number {
  const value = number(f, key); check(Number.isSafeInteger(value) && value >= min && value <= max, `Invalid native integer: ${key}`); return value;
}
function isTrue(f: Fields, key: string): boolean { check(f[key] === "true" || f[key] === "false", `Invalid native boolean: ${key}`); return f[key] === "true"; }
function object(f: Fields, key: string): EyeCoordinatorObject {
  const address = text(f, `${key}.address`); check(/^[1-9]\d*(?:\.0)?$/u.test(address), `Invalid native object address: ${key}`);
  return { name: text(f, `${key}.name`), address }; // Addresses remain strings.
}
function arrayCount(f: Fields, key: string, max: number): number {
  const indices = new Set<string>();
  for (const field of Object.keys(f)) if (field.startsWith(`${key}.`)) indices.add(field.slice(key.length + 1).split(".")[0]);
  check(indices.size <= max && [...indices].every(index => /^[1-9]\d*$/u.test(index) && Number(index) <= indices.size), `Invalid bounded native array: ${key}`);
  return indices.size;
}
function expectedParameter(index: number): EyeCoordinatorParameter {
  return { slotId: index < 4 ? "head:3" : "head:4", materialId: index < 4 ? "coen-human-eye-left" : "coen-human-eye-right", name: NAMES[index % 4], association: 2, index: -1 };
}
function parameter(f: Fields, key: string): EyeCoordinatorParameter {
  return { slotId: text(f, `${key}.slotId`), materialId: text(f, `${key}.materialId`), name: text(f, `${key}.name`), association: integer(f, `${key}.association`, 0, 2), index: integer(f, `${key}.index`, -1, 128) };
}
function parseSettings(f: Fields, key: string): EyeCoordinatorSettings {
  check(text(f, `${key}.schemaId`) === SCHEMA && arrayCount(f, `${key}.values`, 8) === 8, "Native human settings schema/count mismatch");
  const values = Array.from({ length: 8 }, (_, i) => {
    const prefix = `${key}.values.${i + 1}`, id = parameter(f, `${prefix}.parameter`);
    check(equal(id, expectedParameter(i)) && text(f, `${prefix}.value.kind`) === "scalar", "Native human parameter identity mismatch");
    return { parameter: id, value: { kind: "scalar" as const, value: number(f, `${prefix}.value.value`) } };
  });
  return { schemaId: SCHEMA, values };
}
function canonical(settings: EyeCoordinatorSettings, descriptor: EyeCoordinatorDescriptor, nativeReadback = false): EyeCoordinatorSettings {
  check(settings?.schemaId === SCHEMA && Array.isArray(settings.values) && settings.values.length === 8, "Unsupported human settings schema");
  const values = Array.from({ length: 8 }, (_, i) => {
    const id = expectedParameter(i), matches = settings.values.filter(entry => equal(entry.parameter, id));
    check(matches.length === 1 && matches[0].value.kind === "scalar", "Missing, duplicate or unsupported eye parameter");
    const value = matches[0].value.value, domain = descriptor.bindings[Math.floor(i / 4)].parameters[i % 4];
    const allowance = nativeReadback ? domain.tolerance : 0;
    check(Number.isFinite(value) && value >= domain.min - allowance && value <= domain.max + allowance, "Eye value exceeds its observed native domain");
    return { parameter: id, value: { kind: "scalar" as const, value } };
  });
  return { schemaId: SCHEMA, values };
}
function settingsMatch(actual: EyeCoordinatorSettings, desired: EyeCoordinatorSettings, descriptor: EyeCoordinatorDescriptor): boolean {
  return actual.values.every((entry, i) => Math.abs(entry.value.value - desired.values[i].value.value) <= descriptor.bindings[Math.floor(i / 4)].parameters[i % 4].tolerance);
}
function parseDescriptor(f: Fields, prefix = "result.descriptor"): EyeCoordinatorDescriptor {
  check(text(f, `${prefix}.schema_id`) === SCHEMA && number(f, `${prefix}.form`) === 0 && !isTrue(f, `${prefix}.is_wolf_form`), "Only the observed human schema is supported");
  check(arrayCount(f, `${prefix}.bindings`, 2) === 2, "Native human eye bindings are incomplete");
  const bindings = [0, 1].map(i => {
    const p = `${prefix}.bindings.${i + 1}`;
    check(integer(f, `${p}.slot`) === i + 3 && text(f, `${p}.slot_name`) === (i === 0 ? "shader_eyeLeft_shader" : "shader_eyeRight_shader") && arrayCount(f, `${p}.parameters`, 4) === 4, "Native eye slot topology changed");
    const parameters = [0, 1, 2, 3].map(j => {
      const q = `${p}.parameters.${j + 1}`, id = parameter(f, `${q}.parameter`);
      const min = number(f, `${q}.min`), max = number(f, `${q}.max`), tolerance = number(f, `${q}.tolerance`);
      check(equal(id, expectedParameter(i * 4 + j)) && min <= max && tolerance === 0.000001, "Native eye parameter domain differs from the reviewed registry");
      return { parameter: id, min, max, tolerance };
    });
    return { slot: i + 3, slotName: text(f, `${p}.slot_name`), original: object(f, `${p}.original`), current: object(f, `${p}.current`), parameters };
  });
  const result: EyeCoordinatorDescriptor = { identityKey: text(f, `${prefix}.identity_key`), baselineId: text(f, `${prefix}.baseline_id`), schemaId: SCHEMA,
    player: object(f, `${prefix}.player`), world: object(f, `${prefix}.world`), head: object(f, `${prefix}.head`), asset: object(f, `${prefix}.asset`),
    form: "human", isWolfForm: false, original: parseSettings(f, `${prefix}.original_settings`), current: parseSettings(f, `${prefix}.current_settings`), bindings };
  canonical(result.original, result); canonical(result.current, result, true); return result;
}
function baseline(descriptor: EyeCoordinatorDescriptor): unknown {
  return { ...descriptor, current: undefined, bindings: descriptor.bindings.map(binding => ({ ...binding, current: undefined })) };
}
function validView(view: EyeCoordinatorView, preview?: EyeCoordinatorPreview): void {
  check(view && Number.isFinite(view.yawDegrees) && Math.abs(view.yawDegrees) <= 69 && FRAMINGS.includes(view.framing) && Number.isFinite(view.zoom) && view.zoom > 0 && view.zoom <= 10, "Invalid bounded eye view");
  if (preview) { const bounds = preview.zoomBounds[view.framing]; check(view.zoom >= bounds.min && view.zoom <= bounds.max, "Eye zoom exceeds native geometry bounds"); }
}
function revision(value: number): void { check(Number.isSafeInteger(value) && value >= 0 && value <= 2147483647, "Invalid eye revision"); }
function parsePreview(f: Fields, descriptor: EyeCoordinatorDescriptor, lease: Lease, boot: string): EyeCoordinatorPreview {
  const p = "result.preview";
  check(text(f, `${p}.kind`) === "native-private-eye-preview-descriptor" && text(f, `${p}.nonce`) === lease.preview_nonce && text(f, `${p}.boot_id`) === boot
    && text(f, `${p}.identity_key`) === descriptor.identityKey && text(f, `${p}.baseline_id`) === descriptor.baselineId && text(f, `${p}.schema_id`) === SCHEMA, "Preview descriptor generation mismatch");
  check(equal(object(f, `${p}.player`), descriptor.player) && equal(object(f, `${p}.world`), descriptor.world) && number(f, `${p}.form`) === 0 && !isTrue(f, `${p}.is_wolf_form`), "Preview does not correspond to the observed player");
  check(number(f, `${p}.yaw_min`) === -69 && number(f, `${p}.yaw_max`) === 69 && !isTrue(f, `${p}.production_ready`) && !isTrue(f, `${p}.preview_verified`) && !isTrue(f, `${p}.gameplay_verified`), "Unexpected prototype preview capability");
  const zoomBounds = Object.fromEntries(FRAMINGS.map(framing => {
    const q = `${p}.zoom_bounds.${framing}`, min = number(f, `${q}.min`), max = number(f, `${q}.max`), initial = number(f, `${q}.initial`);
    check(min > 0 && min <= initial && initial === 1 && initial <= max && max <= 10, "Invalid native geometry zoom bounds"); return [framing, { min, max, initial }];
  })) as EyeCoordinatorPreview["zoomBounds"];
  const display = `${p}.display_configuration`;
  check(isTrue(f, `${display}.gamma_after.ok`), "Native display readback is absent");
  const renderTargetFormat = integer(f, `${p}.render_target_format`, 0, 20), captureSource = integer(f, `${p}.capture_source`, 0, 20), targetGamma = number(f, `${display}.gamma_after.value`);
  let forceLinearGamma: boolean | undefined;
  if (f[`${display}.configuration_source`] === "native-factory-defaults") {
    check(isTrue(f, `${display}.configuration_verified`) && !isTrue(f, `${display}.writes_performed`) && renderTargetFormat === 2 && captureSource === 9 && targetGamma === 0,
      "Native factory display profile differs from the reviewed configuration");
    check(isTrue(f, `${display}.force_linear_after.ok`), "Native factory force-linear readback is absent");
    const kind = text(f, `${display}.force_linear_after.type`), value = f[`${display}.force_linear_after.value`];
    check((kind === "boolean" && value === "true") || (kind === "number" && number(f, `${display}.force_linear_after.value`) === 1), "Native factory force-linear default differs");
    forceLinearGamma = true;
  } else check(isTrue(f, `${display}.write_ok`), "Native display configuration was not acknowledged");
  const width = integer(f, `${p}.width`, 1, 2048), height = integer(f, `${p}.height`, 1, 2048);
  return { actor: object(f, `${p}.actor`), capture: object(f, `${p}.capture`), target: object(f, `${p}.target`), targetOuter: object(f, `${p}.target_outer`), width, height,
    renderTargetFormat, captureSource, targetGamma, forceLinearGamma, zoomBounds, nativeFields: f };
}

/** Main-process use only. Keep one coordinator per fixed host/native channel.
 * Methods serialize operations; there are no timers, automatic mutation retries,
 * hidden restores, arbitrary native paths or renderer-controlled owner tokens. */
export function createEyeSessionCoordinator(dependencies: Readonly<{ channel: Channel; frames: EyeCoordinatorFrameStore; timeoutMs?: number }>) {
  const { channel, frames } = dependencies, timeout = dependencies.timeoutMs ?? 10000;
  check(Number.isInteger(timeout) && timeout >= 50 && timeout <= 30000, "Eye channel timeout is outside its supported bound");
  let chain = Promise.resolve(), queued = 0, connected: Awaited<ReturnType<Channel["waitForTransport"]>> | undefined;
  let descriptor: EyeCoordinatorDescriptor | undefined, preview: EyeCoordinatorPreview | undefined, lease: Lease | undefined, attemptedLease: Lease | undefined;
  let ownershipUncertain = false;
  let desired: EyeCoordinatorTuple | undefined, sequence = 0, clockEnd: number | undefined, fault: string | undefined, active = false;
  let liveRevision: number | undefined, liveDesired: EyeCoordinatorSettings | undefined, latestPreviewRequest = 0, cancellationGeneration = 0;
  let lastExchange: Exchange | undefined, exchangeCount = 0;
  let lastFailure: { reason: string; exchangeObserved: boolean; nativeFields?: Fields; timing?: EyeCoordinatorTiming } | undefined;
  const acknowledged = new Set<number>();
  function serial<T>(operation: () => Promise<T>): Promise<T> {
    if (queued >= 16) return Promise.reject(new Error("Eye coordinator command queue is full"));
    queued++;
    const result = chain.then(operation); chain = result.then(() => undefined, () => undefined).finally(() => { queued--; }); return result;
  }
  function current(): EyeCoordinatorDescriptor { check(descriptor, "Inspect the native eye baseline first"); return descriptor; }
  function owned(): Lease { check(lease && !ownershipUncertain, "No confirmed owned native eye lease"); return lease; }
  function healthy(): void { check(!fault, `Eye coordinator requires explicit recovery: ${fault}`); }
  function accept(next: EyeCoordinatorDescriptor): void {
    check(!descriptor || equal(baseline(descriptor), baseline(next)), "Native eye baseline or player generation changed"); descriptor = next;
  }
  function confirmOwnership(f: Fields): void {
    const p = "known_preview";
    if (!isTrue(f, `${p}.present`)) {
      check(!lease, "Native known eye lease unexpectedly disappeared"); ownershipUncertain = false; active = false; return;
    }
    check(text(f, `${p}.boot_id`) === connected!.bootId && text(f, `${p}.owner_id`) === connected!.ownerId, "Native recovery lease has a different channel owner");
    const known: Lease = { lease_id: text(f, `${p}.lease_id`), preview_nonce: text(f, `${p}.preview_nonce`), identity_key: text(f, `${p}.identity_key`), baseline_id: text(f, `${p}.baseline_id`) };
    check(equal(known, lease) || equal(known, attemptedLease), "Native recovery lease was not allocated by this host");
    isTrue(f, `${p}.cleanup_blocked`); active = isTrue(f, `${p}.active`); lease = known; ownershipUncertain = false;
  }
  async function send(command: EyeNativeCommand): Promise<Exchange> {
    try {
      check(connected, "Connect the fixed eye transport first");
      const exchange = await channel.send(command, timeout), f = exchange.response, t = exchange.timing;
      assertEyeResponseCorrespondence(exchange.request, f);
      check(exchange.request.boot_id === connected.bootId && exchange.request.owner_id === connected.ownerId && t.requestSequence === exchange.request.command_sequence
        && Number.isFinite(t.hostRequestSentAtMs) && Number.isFinite(t.hostReceiptReceivedAtMs) && t.hostRequestSentAtMs > 0 && t.hostReceiptReceivedAtMs >= t.hostRequestSentAtMs, "Eye response host identity/timing mismatch");
      check(f.production_ready === "false" && f.gameplay_verified === "false" && f.production_capabilities === "none", "Unexpected prototype capability promotion");
      lastExchange = { ...exchange, response: Object.freeze({ ...f }) }; exchangeCount++;
      confirmOwnership(f);
      return lastExchange;
    } catch (error) { if (command.operation === "open") ownershipUncertain = true; fault = error instanceof Error ? error.message : String(error); throw error; }
  }
  function result(exchange: Exchange): EyeCoordinatorResult {
    return { status: text(exchange.response, "result.status"), productionReady: false, timing: clone(exchange.timing), nativeFields: exchange.response };
  }
  async function guarded<T>(operation: () => Promise<T>): Promise<T> {
    // Diagnostics must describe the operation that actually failed. A timed-out step completes no
    // exchange, so lastExchange still holds the previous successful command; attaching it would
    // report that command's native fields and timing as if the failure had produced them.
    const exchangesBeforeOperation = exchangeCount;
    try { return await operation(); } catch (error) {
      fault = error instanceof Error ? error.message : String(error);
      const exchangeObserved = exchangeCount > exchangesBeforeOperation;
      lastFailure = exchangeObserved
        ? { reason: fault, exchangeObserved, nativeFields: lastExchange?.response, timing: lastExchange?.timing }
        : { reason: fault, exchangeObserved };
      throw error;
    }
  }
  function tuple(input: EyeCoordinatorTuple, reopening = false): EyeCoordinatorTuple {
    revision(input.viewRevision); revision(input.eyeRevision); validView(input.view, reopening ? undefined : preview);
    const next = { ...input, settings: canonical(input.settings, current()) };
    if (desired && !reopening) {
      check(next.viewRevision >= desired.viewRevision && next.eyeRevision >= desired.eyeRevision, "Stale preview revision");
      check(next.viewRevision !== desired.viewRevision || equal(next.view, desired.view), "View revision reused for another camera");
      check(next.eyeRevision !== desired.eyeRevision || equal(next.settings, desired.settings), "Eye revision reused for another payload");
    }
    return clone(next);
  }
  function viewCommand(operation: "open" | "enqueue", value: EyeCoordinatorTuple, address = owned()): EyeNativeCommand {
    return { operation, ...address, view_revision: value.viewRevision, eye_revision: value.eyeRevision, yaw_degrees: value.view.yawDegrees, framing: value.view.framing, zoom: value.view.zoom,
      settings: Object.fromEntries(HUMAN_IRIS_WIRE_KEYS.map((key, i) => [key, value.settings.values[i].value.value])) as HumanIrisWireSettings };
  }
  async function inspect(): Promise<EyeCoordinatorReadback> {
    const exchange = await send({ operation: "inspect" }); check(exchange.response["result.status"] === "observed", exchange.response["result.reason"] ?? "Native eye inspection was rejected");
    accept(parseDescriptor(exchange.response)); return { ...result(exchange), operation: "inspect", descriptor: clone(current()), nativeReadbackVerified: false, appliedInGame: false, originalBindingsRestored: false };
  }
  async function ack(address: EyeCoordinatorFrameAddress): Promise<void> {
    const response = await send({ operation: "ack", ...owned(), frame_sequence: address.sequence, file_name: address.fileName });
    check(response.response["result.status"] === "acknowledged" && integer(response.response, "result.frame_sequence", 1, 1200) === address.sequence && text(response.response, "result.file_name") === address.fileName, "Native exact-frame acknowledgement failed");
    acknowledged.add(address.sequence);
  }
  function frameAddress(index: number): EyeCoordinatorFrameAddress {
    check(connected, "Transport is absent"); const nonce = owned().preview_nonce;
    return { bootId: connected.bootId, previewNonce: nonce, sequence: index, fileName: `eye-live-${nonce}-${String(index).padStart(4, "0")}.png` };
  }
  async function step(): Promise<EyeCoordinatorResult | EyeCoordinatorFrame> {
    check(active && preview && desired && connected, "Native preview is not active");
    const exchange = await send({ operation: "step", ...owned() }), f = exchange.response, status = text(f, "result.status");
    if (["waiting", "waiting-for-frame-consumer", "waiting-for-preview-request"].includes(status)) return result(exchange);
    check(status === "captured-evidence", f["result.reason"] ?? "Native preview did not capture");
    const p = "result.evidence", index = integer(f, `${p}.sequence`, 1, 1200), address = frameAddress(index);
    check(index === sequence + 1 && integer(f, "result.sequence", 1, 1200) === index && text(f, `${p}.file_name`) === address.fileName
      && text(f, `${p}.kind`) === "native-private-eye-session-evidence" && text(f, `${p}.nonce`) === address.previewNonce && text(f, `${p}.boot_id`) === address.bootId
      && text(f, `${p}.identity_key`) === owned().identity_key && text(f, `${p}.baseline_id`) === owned().baseline_id, "Native frame generation/sequence mismatch");
    for (const [field, expected] of Object.entries({ actor: preview.actor, capture: preview.capture, target: preview.target, target_outer: preview.targetOuter })) check(equal(object(f, `${p}.${field}`), expected), `Native frame resource changed: ${field}`);
    const view: EyeCoordinatorView = { yawDegrees: number(f, `${p}.view.yawDegrees`), framing: text(f, `${p}.view.framing`) as EyeCoordinatorView["framing"], zoom: number(f, `${p}.view.zoom`) }; validView(view, preview);
    const settings = parseSettings(f, `${p}.settings`); canonical(settings, current(), true);
    check(integer(f, `${p}.view_revision`) === desired.viewRevision && integer(f, `${p}.eye_revision`) === desired.eyeRevision && equal(view, desired.view) && settingsMatch(settings, desired.settings, current()), "Frame does not match requested camera/settings revisions");
    check(integer(f, `${p}.width`) === preview.width && integer(f, `${p}.height`) === preview.height && integer(f, `${p}.render_target_format`) === preview.renderTargetFormat
      && integer(f, `${p}.capture_source`) === preview.captureSource && number(f, `${p}.target_gamma`) === preview.targetGamma, "Frame display profile differs from the owned target");
    if (preview.forceLinearGamma !== undefined) check(isTrue(f, `${p}.force_linear_gamma`) === preview.forceLinearGamma, "Frame force-linear profile differs from the native factory readback");
    for (const flag of ["capture_timestamp_known", "frame_verified", "preview_verified", "gameplay_verified"]) check(!isTrue(f, `${p}.${flag}`), "Unexpected native evidence promotion");
    const nativeClockId = text(f, `${p}.native_clock_id`), nativeStartedMs = number(f, `${p}.export_call_started_monotonic_ms`), nativeCompletedMs = number(f, `${p}.export_call_completed_monotonic_ms`);
    check(nativeClockId === `ue-gameplay-real-time-seconds:${connected.bootId}:${current().world.address}` && nativeStartedMs >= 0 && nativeCompletedMs >= nativeStartedMs
      && nativeCompletedMs <= Number.MAX_SAFE_INTEGER && (clockEnd === undefined || nativeStartedMs >= clockEnd), "Native capture clock identity/interval regressed");
    const file = await frames.read(address), bytes = Buffer.from(file.nativeBytes), pngEvidence = inspectNativeEyePngEvidence(bytes);
    check(pngEvidence.width === preview.width && pngEvidence.height === preview.height, "Native PNG dimensions do not match its frame receipt");
    const pngBytes = Uint8Array.from(bytes.subarray(0, pngEvidence.pngPrefixBytes));
    await file.remove(); await ack(address); // Publish only after exact consumption/ACK.
    sequence = index; clockEnd = nativeCompletedMs;
    return { kind: "native-frame-evidence", productionReady: false, previewVerified: false, sequence: index, viewRevision: desired.viewRevision, eyeRevision: desired.eyeRevision,
      view, settings, width: preview.width, height: preview.height, pngBytes, pngEvidence,
      captureTiming: { ...exchange.timing, kind: "native-call-interval", nativeClockId, nativeStartedMs, nativeCompletedMs, renderCompletedAtMs: null }, nativeFields: f };
  }
  async function live(operation: "apply" | "restore", eyeRevision: number, input?: EyeCoordinatorSettings): Promise<EyeCoordinatorReadback> {
    revision(eyeRevision); const expected = operation === "restore" ? current().original : canonical(input!, current()); owned();
    check(liveRevision === undefined || eyeRevision >= liveRevision, "Stale live eye revision");
    check(liveRevision !== eyeRevision || equal(expected, liveDesired), "Live eye revision reused for another payload");
    const command: EyeNativeCommand = operation === "restore" ? { operation, ...owned(), eye_revision: eyeRevision }
      : { operation, ...owned(), eye_revision: eyeRevision, settings: Object.fromEntries(HUMAN_IRIS_WIRE_KEYS.map((key, i) => [key, expected.values[i].value.value])) as HumanIrisWireSettings };
    liveRevision = eyeRevision; liveDesired = clone(expected);
    const exchange = await send(command), f = exchange.response;
    check(f["result.status"] === "native-readback" && isTrue(f, "result.ok") && isTrue(f, "result.native_readback_verified") && !isTrue(f, "result.applied_in_game")
      && text(f, "result.kind") === operation && text(f, "result.identity_key") === owned().identity_key && text(f, "result.baseline_id") === owned().baseline_id && text(f, "result.schema_id") === SCHEMA, f["result.reason"] ?? "Native live eye readback was rejected");
    const next = parseDescriptor(f), readback = parseSettings(f, "result.current_settings");
    check(equal(next.current, readback) && settingsMatch(readback, expected, current()), "Native live getter does not match requested settings");
    const restored = isTrue(f, "result.original_bindings_restored");
    check(operation !== "restore" || (restored && next.bindings.every(binding => equal(binding.current, binding.original)) && equal(readback, next.original)), "Original native bindings/settings were not restored");
    accept(next); return { ...result(exchange), operation, descriptor: clone(current()), nativeReadbackVerified: true, originalBindingsRestored: restored, appliedInGame: false };
  }
  return {
    getState() { return { status: fault ? "faulted" as const : active ? "active" as const : "idle" as const, reason: fault, productionReady: false as const, queued, ownershipConfirmed: Boolean(lease && !ownershipUncertain), liveEyeRevision: liveRevision, lastFailure: lastFailure && clone(lastFailure), descriptor: descriptor && clone(descriptor), preview: preview && clone(preview) }; },
    connect() { return serial(async () => { healthy(); connected = await channel.waitForTransport(timeout); check(!connected.productionReady, "Unexpected transport readiness"); return clone(connected); }); },
    inspect() { return serial(() => guarded(inspect)); },
    open(input: EyeCoordinatorTuple) {
      const requested = clone(input);
      return serial(async () => {
        healthy(); check(!active, "Native preview is already active"); await guarded(inspect);
        const next = tuple(requested, true); // Validate before allocating an owned attempt.
        attemptedLease = { lease_id: token(), preview_nonce: token(), identity_key: current().identityKey, baseline_id: current().baselineId };
        return guarded(async () => {
          const attempted = attemptedLease!;
          const exchange = await send(viewCommand("open", next, attempted)); check(exchange.response["result.status"] === "opened", exchange.response["result.reason"] ?? "Native preview creation failed");
          check(equal(owned(), attempted) && active, "Opened preview lacks matching native ownership acknowledgement");
          accept(parseDescriptor(exchange.response)); preview = parsePreview(exchange.response, current(), owned(), connected!.bootId); validView(next.view, preview);
          desired = next; sequence = 0; clockEnd = undefined; acknowledged.clear(); active = true;
          return { ...result(exchange), descriptor: clone(current()), preview: clone(preview) };
        });
      });
    },
    updatePreview(input: EyeCoordinatorTuple) {
      const requested = clone(input), request = ++latestPreviewRequest;
      return serial(async () => {
        healthy(); check(active, "Native preview is not active"); const next = tuple(requested);
        if (request !== latestPreviewRequest) return { status: "superseded" as const, productionReady: false as const };
        return guarded(async () => { const exchange = await send(viewCommand("enqueue", next)); check(["queued", "unchanged"].includes(exchange.response["result.status"]), exchange.response["result.reason"] ?? "Native preview update rejected"); desired = next; return result(exchange); });
      });
    },
    step() {
      const generation = cancellationGeneration;
      return serial<EyeCoordinatorResult | EyeCoordinatorFrame | Readonly<{ status: "cancelled-before-capture"; productionReady: false }>>(() => {
        if (generation !== cancellationGeneration) return Promise.resolve({ status: "cancelled-before-capture" as const, productionReady: false as const });
        healthy(); return guarded(step);
      });
    },
    renew() { return serial(() => { healthy(); check(active, "Native preview is not active"); return guarded(async () => { const exchange = await send({ operation: "renew", ...owned() }); check(exchange.response["result.status"] === "renewed", "Native eye lease renewal failed"); return result(exchange); }); }); },
    cancelQueued() { latestPreviewRequest++; cancellationGeneration++; return serial(() => { healthy(); check(active, "Native preview is not active"); return guarded(async () => { const exchange = await send({ operation: "cancel", ...owned() }); check(exchange.response["result.status"] === "cancelled", "Native preview cancellation failed"); return result(exchange); }); }); },
    apply(eyeRevision: number, settings: EyeCoordinatorSettings) { const requested = clone(settings); return serial(() => { healthy(); return guarded(() => live("apply", eyeRevision, requested)); }); },
    // Explicit recovery may restore a known baseline after preview close/failure.
    restore(eyeRevision: number) { return serial(() => guarded(() => live("restore", eyeRevision))); },
    close() {
      latestPreviewRequest++; cancellationGeneration++;
      return serial(() => guarded(async () => {
        const exchange = await send({ operation: "close", ...owned() }), f = exchange.response, status = text(f, "result.status"); active = false;
        check(status === "closed" || status === "cleanup-failed", "Native eye close was rejected");
        const p = "result.cleanup", count = arrayCount(f, `${p}.pending_frames`, 2);
        if (f[`${p}.nonce`] !== undefined) {
          check(text(f, `${p}.nonce`) === owned().preview_nonce && text(f, `${p}.boot_id`) === connected!.bootId, "Native cleanup ledger has a different owner");
          check(status !== "closed" || isTrue(f, `${p}.owned_cleanup_acknowledged`), "Native close lacks an owned cleanup acknowledgement");
          for (let i = 1; i <= count; i++) {
            const index = integer(f, `${p}.pending_frames.${i}.sequence`, 1, 1200), address = frameAddress(index);
            check(text(f, `${p}.pending_frames.${i}.file_name`) === address.fileName, "Native cleanup path differs from its exact frame ledger");
            if (!acknowledged.has(index)) { await frames.discardKnown(address); await ack(address); }
          }
        } else check(count === 0, "Native cleanup ledger has no ownership metadata");
        if (status === "cleanup-failed") fault = f["result.cleanup_error"] ?? "Native owned cleanup is not acknowledged";
        return result(exchange); // Initial cleanup failure is never overwritten by file ACKs.
      }));
    },
  };
}
