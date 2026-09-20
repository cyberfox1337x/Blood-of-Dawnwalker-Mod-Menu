import { createHash } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import type { createEyeSessionCoordinator, EyeCoordinatorDescriptor, EyeCoordinatorSettings, EyeCoordinatorTuple,
  EyeCoordinatorPreview, EyeCoordinatorFrame, EyeCoordinatorReadback, EyeCoordinatorTiming } from "./eyeSessionCoordinator.js";
import type { EyeServiceAddress, EyeServiceFrame, EyeServiceIdentity, EyeServiceOperationRequest,
  EyeServicePreviewRequest, EyeServiceReadback, EyeServiceReceipt, EyeServiceReady, EyeServiceSession } from "./eyeAppearanceWire.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_appearance_service");

const BUILD = "25129649", SCHEMA = "dawnwalker-human-iris-uv-v1-25129649";
const EXE_SHA = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853";
type Coordinator = ReturnType<typeof createEyeSessionCoordinator>;
export type EyeServiceRuntime = Readonly<{
  buildId: string; executableSha256: string; payloadManifestSha256: string;
  bootId: string; ownerId: string; processId: number; processStartedAt: string;
}>;
export type EyeServiceAcceptance = Readonly<{
  buildId: typeof BUILD; executableSha256: string; payloadManifestSha256: string;
  // Reviewed persistent-session evidence, not channel.ready's checksum or a
  // one-shot construction result. Main supplies this only after native review.
  sessionEvidenceSha256: string; appearanceEvidenceSha256: string; liveRestoreEvidenceSha256: string;
  actualPlayerModel: true; isolatedPreviewInput: true; correspondingEyeMaterials: true; reversibleLiveSetter: true;
  profile: Readonly<{ frameIntervalMs: number; leaseMs: number; renewIntervalMs: number; maximumLifetimeMs: number;
    maximumFramesPerLease: number; maximumLeases: number; maxFrameAgeMs: number; maxReadbackAgeMs: number }>;
}>;
type Dependencies = Readonly<{
  coordinator: Coordinator; acceptance?: EyeServiceAcceptance;
  inspectRuntime(): Promise<EyeServiceRuntime>;
  now(): number;
  schedule(callback: () => void, delayMs: number): () => void;
  onSession(session: EyeServiceSession): void;
  onFrame(frame: EyeServiceFrame): void;
  onFault(error: unknown): void;
}>;

function check(condition: unknown, message: string): asserts condition { if (!condition) throw new Error(message); }
function copy<T>(value: T): T { return structuredClone(value); }
function equal(left: unknown, right: unknown): boolean { return isDeepStrictEqual(left, right); }
function id(...parts: unknown[]): string { return createHash("sha256").update(JSON.stringify(parts)).digest("hex"); }
function revision(value: number): void { check(Number.isSafeInteger(value) && value >= 0 && value <= 2147483647, "Invalid eye revision"); }
function baseline(value: EyeCoordinatorDescriptor): unknown {
  return { ...value, current: undefined, bindings: value.bindings.map(binding => ({ ...binding, current: undefined })) };
}
function alternate(original: EyeCoordinatorSettings): EyeCoordinatorSettings {
  const swap = [2, 3, 0, 1, 6, 7, 4, 5];
  return { schemaId: original.schemaId, values: original.values.map((entry, i) => ({ parameter: copy(entry.parameter), value: copy(original.values[swap[i]].value) })) };
}
function settingsMatch(left: EyeCoordinatorSettings, right: EyeCoordinatorSettings, descriptor: EyeCoordinatorDescriptor): boolean {
  return Boolean(left && left.schemaId === SCHEMA && Array.isArray(left.values) && left.values.length === 8
    && left.values.every((entry, i) => equal(entry.parameter, right.values[i].parameter) && entry.value?.kind === "scalar"
      && Number.isFinite(entry.value.value) && Math.abs(entry.value.value - right.values[i].value.value) <= descriptor.bindings[Math.floor(i / 4)].parameters[i % 4].tolerance));
}
function validateAcceptance(value: EyeServiceAcceptance): void {
  const hashes = [value.executableSha256, value.payloadManifestSha256, value.sessionEvidenceSha256, value.appearanceEvidenceSha256, value.liveRestoreEvidenceSha256];
  check(value.buildId === BUILD && value.executableSha256 === EXE_SHA && hashes.every(hash => /^[A-F0-9]{64}$/u.test(hash)), "Eye acceptance identity is incomplete");
  check(value.actualPlayerModel === true && value.isolatedPreviewInput === true && value.correspondingEyeMaterials === true && value.reversibleLiveSetter === true, "Eye native acceptance is incomplete");
  const p = value.profile;
  check(p && Object.values(p).every(Number.isFinite) && p.frameIntervalMs >= 100 && p.frameIntervalMs <= 1000
    && p.leaseMs >= 1000 && p.leaseMs <= 10000 && p.renewIntervalMs >= 100 && p.renewIntervalMs <= p.leaseMs / 2
    && p.maximumLifetimeMs >= p.leaseMs && p.maximumLifetimeMs <= 30000
    && Number.isInteger(p.maximumFramesPerLease) && p.maximumFramesPerLease >= 1 && p.maximumFramesPerLease <= 120
    && Number.isInteger(p.maximumLeases) && p.maximumLeases >= 1 && p.maximumLeases <= 64
    && [p.maxFrameAgeMs, p.maxReadbackAgeMs].every(age => age >= 250 && age <= 5000), "Eye accepted lifecycle bounds are invalid");
}

/** Inert main-process service. It never discovers/installs a pilot, registers
 * IPC, trusts renderer evidence, or restores live eyes during preview teardown.
 * Main authenticates the calling webContents and supplies reviewed acceptance.
 * Exhausted native lifetime/budget closes explicitly; it never silently restarts
 * the pilot or disguises a new lease as the previous preview generation. */
export function createEyeAppearanceService(dependencies: Dependencies) {
  const coordinator = dependencies.coordinator, acceptance = dependencies.acceptance && copy(dependencies.acceptance);
  if (acceptance) validateAcceptance(acceptance);
  let runtime: EyeServiceRuntime | undefined, descriptor: EyeCoordinatorDescriptor | undefined;
  let identity: EyeServiceIdentity | undefined, address: EyeServiceAddress | undefined, preview: EyeCoordinatorPreview | undefined;
  let session: EyeServiceSession = unavailable("Eye appearance has no accepted native session.");
  let active = false, disposed = false, suspended = false, epoch = 0, latestPreview = 0, cancellationGeneration = 0;
  let chain = Promise.resolve(), queued = 0, cancelTimer: (() => void) | undefined, timerToken = 0;
  let leaseCount = 0, frames = 0, openedAt = 0, renewedAt = 0, wireBase = 0, highestWire = -1;
  let highestEye = 0, highestEyeSettings: EyeCoordinatorSettings | undefined;
  let highestViewRevision = 0, highestView: EyeCoordinatorTuple["view"] | undefined;
  let desired: EyeServicePreviewRequest | undefined, firstFrame: EyeServiceFrame | undefined;
  let lastFrameSequence = 0, fault: unknown, openingAttempted = false;
  const listeners = new Set<(frame: EyeServiceFrame) => void>();
  function unavailable(reason: string): EyeServiceSession { return { availability: "unavailable", reason, diagnostics: [] }; }
  function serial<T>(operation: () => Promise<T>): Promise<T> {
    if (queued >= 16) return Promise.reject(new Error("Eye service command queue is full"));
    queued++;
    const result = chain.then(operation);
    chain = result.then(() => undefined, () => undefined).finally(() => { queued--; });
    return result;
  }
  function publishSession(next: EyeServiceSession): void { session = copy(next); dependencies.onSession(copy(session)); }
  function stopTimer(): void { timerToken++; cancelTimer?.(); cancelTimer = undefined; }
  function currentDescriptor(): EyeCoordinatorDescriptor { check(descriptor && identity, "No observed native eye baseline"); return descriptor; }
  function acceptDescriptor(next: EyeCoordinatorDescriptor): void {
    check(next.schemaId === SCHEMA && next.form === "human" && !next.isWolfForm && next.original.values.length === 8
      && next.bindings.length === 2 && next.bindings.every(binding => binding.parameters.length === 4), "Unsupported native eye baseline");
    check(!descriptor || equal(baseline(next), baseline(descriptor)), "Native eye baseline generation changed");
    descriptor = copy(next);
    if (!identity) identity = { buildId: runtime!.buildId, sessionId: id(runtime!.bootId, runtime!.processId, runtime!.processStartedAt),
      worldGeneration: id(runtime!.bootId, next.world), pawnId: id(next.player), appearanceRevision: id(next.identityKey, next.asset),
      form: "human", isWolfForm: false, meshId: id(next.head, next.asset),
      eyeMaterialGeneration: id(next.baselineId, next.bindings.map(binding => ({ slot: binding.slot, original: binding.original }))) };
  }
  async function verifiedRuntime(): Promise<void> {
    check(acceptance, "Persistent native eye session has not been accepted");
    const observed = copy(await dependencies.inspectRuntime());
    check(observed.buildId === BUILD && observed.executableSha256 === acceptance.executableSha256
      && observed.payloadManifestSha256 === acceptance.payloadManifestSha256 && /^\d+-\d+$/u.test(observed.bootId)
      && /^[a-f0-9]{32}$/u.test(observed.ownerId) && Number.isSafeInteger(observed.processId) && observed.processId > 0
      && typeof observed.processStartedAt === "string" && observed.processStartedAt.length > 0, "Native eye runtime differs from accepted evidence");
    check(!runtime || equal(runtime, observed), "Native eye process or channel generation changed"); runtime = observed;
  }
  function assertAddress(candidate: EyeServiceAddress, requireActive = true): void {
    check(!disposed && address && candidate && equal(candidate.identity, address.identity)
      && candidate.previewId === address.previewId && candidate.renderTargetGeneration === address.renderTargetGeneration
      && (!requireActive || active), "Eye preview address is stale or closed");
  }
  function assertEpoch(expected: number, requireActive = true): void {
    check(epoch === expected && !disposed && (!requireActive || active), "Eye request was cancelled by preview lifecycle");
  }
  function supported(settings: EyeCoordinatorSettings, includeCurrent = false): void {
    const current = currentDescriptor();
    check(settingsMatch(settings, current.original, current) || settingsMatch(settings, alternate(current.original), current)
      || (includeCurrent && settingsMatch(settings, current.current, current)), "Only the observed human Original and Alternate eyes are supported");
  }
  function reserveEye(eyeRevision: number, settings: EyeCoordinatorSettings): void {
    revision(eyeRevision);
    check(eyeRevision >= highestEye && (eyeRevision !== highestEye || !highestEyeSettings || equal(settings, highestEyeSettings)), "Eye revision is stale or reused for different settings");
    highestEye = eyeRevision; highestEyeSettings = copy(settings);
    highestWire = Math.max(highestWire, wireBase + eyeRevision); revision(highestWire);
  }
  function tuple(request: EyeServicePreviewRequest): EyeCoordinatorTuple {
    return { eyeRevision: wireBase + request.eyeRevision, viewRevision: request.viewRevision, view: copy(request.view), settings: copy(request.settings) };
  }
  function fresh(timing: EyeCoordinatorTiming, maximumAge: number): void {
    const now = dependencies.now();
    check(Number.isSafeInteger(timing.requestSequence) && timing.requestSequence > 0
      && [timing.hostRequestSentAtMs, timing.hostReceiptReceivedAtMs, now].every(Number.isFinite)
      && timing.hostRequestSentAtMs > 0 && timing.hostReceiptReceivedAtMs >= timing.hostRequestSentAtMs
      && timing.hostReceiptReceivedAtMs <= now + 250 && now - timing.hostRequestSentAtMs <= maximumAge, "Native eye readback interval is stale or invalid");
  }
  function readback(result: EyeCoordinatorReadback): EyeServiceReadback {
    acceptDescriptor(result.descriptor); fresh(result.timing, acceptance!.profile.maxReadbackAgeMs);
    return { source: "runtime-material-getter", identity: copy(identity!), baselineId: descriptor!.baselineId,
      settings: copy(descriptor!.current), observationTiming: copy(result.timing) };
  }
  function ready(): EyeServiceReady {
    const current = currentDescriptor(), bounds = preview!.zoomBounds;
    return { ...copy(address!), availability: "ready", baselineId: current.baselineId,
      schema: { id: SCHEMA, parameters: current.bindings.flatMap(binding => binding.parameters.map(domain => ({
        kind: "scalar" as const, parameter: copy(domain.parameter), label: domain.parameter.name,
        domain: { min: domain.min, max: domain.max, readbackTolerance: domain.tolerance },
      }))), presets: [{ id: "original", label: "Original", settings: copy(current.original) }, { id: "alternate", label: "Alternate", settings: alternate(current.original) }] },
      original: copy(current.original), current: copy(current.current),
      zoomBounds: { "head-and-shoulders": { ...bounds["head-and-shoulders"], step: Math.min(0.05, (bounds["head-and-shoulders"].max - bounds["head-and-shoulders"].min) / 20) },
        "eyes-close-up": { ...bounds["eyes-close-up"], step: Math.min(0.05, (bounds["eyes-close-up"].max - bounds["eyes-close-up"].min) / 20) } },
      maxFrameAgeMs: acceptance!.profile.maxFrameAgeMs, maxReadbackAgeMs: acceptance!.profile.maxReadbackAgeMs, diagnostics: [],
      evidence: { actualPlayerModel: acceptance!.actualPlayerModel, isolatedPreviewInput: acceptance!.isolatedPreviewInput,
        correspondingEyeMaterials: acceptance!.correspondingEyeMaterials, reversibleLiveSetter: acceptance!.reversibleLiveSetter,
        supportedForms: [{ form: "human", schemaId: SCHEMA, originalRestore: true }], verifiedTransitions: [] } };
  }
  async function closeOwned(reason: string): Promise<void> {
    active = false; suspended = true; stopTimer(); firstFrame = undefined;
    if (openingAttempted && !coordinator.getState().ownershipConfirmed) await coordinator.inspect();
    if (coordinator.getState().ownershipConfirmed) {
      const result = await coordinator.close(); check(result.status === "closed", "Native preview cleanup remains unacknowledged");
    }
    openingAttempted = false; publishSession(unavailable(reason));
  }
  async function fail(error: unknown): Promise<void> {
    fault = error; active = false; epoch++; latestPreview++; stopTimer(); firstFrame = undefined;
    try { await closeOwned("Eye appearance is unavailable after a native session error."); }
    catch (cleanupError) { dependencies.onFault(cleanupError); publishSession(unavailable("Eye preview cleanup requires recovery.")); }
    dependencies.onFault(error);
  }
  function scheduleNext(): void {
    if (!active || disposed || cancelTimer || !acceptance) return;
    const expectedEpoch = epoch, token = ++timerToken; let delivered = false;
    cancelTimer = dependencies.schedule(() => {
      if (delivered || token !== timerToken) return; delivered = true; cancelTimer = undefined;
      if (!active || disposed || expectedEpoch !== epoch) return;
      void serial(async () => {
        if (!active || disposed || expectedEpoch !== epoch) return;
        try { await pump(expectedEpoch); } catch (error) { await fail(error); }
      }).finally(scheduleNext).catch(dependencies.onFault);
    }, acceptance.profile.frameIntervalMs);
  }
  async function pump(expectedEpoch: number): Promise<void> {
    assertEpoch(expectedEpoch); await verifiedRuntime(); assertEpoch(expectedEpoch);
    const now = dependencies.now(), profile = acceptance!.profile;
    if (now - openedAt >= profile.maximumLifetimeMs - profile.frameIntervalMs || frames >= profile.maximumFramesPerLease) {
      epoch++; latestPreview++; await closeOwned("Eye preview reached its accepted session limit."); return;
    }
    if (now - renewedAt >= profile.renewIntervalMs) { await coordinator.renew(); assertEpoch(expectedEpoch); renewedAt = dependencies.now(); }
    if (suspended || !desired) return;
    const expected = copy(desired), requestVersion = latestPreview;
    const result = await coordinator.step();
    if (!("kind" in result) || result.kind !== "native-frame-evidence") return;
    frames++;
    if (!active || expectedEpoch !== epoch || requestVersion !== latestPreview) return;
    const frame = result as EyeCoordinatorFrame;
    check(frame.eyeRevision === wireBase + expected.eyeRevision && frame.viewRevision === expected.viewRevision
      && equal(frame.view, expected.view) && settingsMatch(frame.settings, expected.settings, currentDescriptor())
      && frame.sequence > lastFrameSequence && frame.width === preview!.width && frame.height === preview!.height,
    "Native eye frame does not match the saved preview request");
    fresh(frame.captureTiming, profile.maxFrameAgeMs);
    check(frame.captureTiming.kind === "native-call-interval" && frame.captureTiming.renderCompletedAtMs === null
      && typeof frame.captureTiming.nativeClockId === "string" && frame.captureTiming.nativeClockId.length > 0
      && Number.isFinite(frame.captureTiming.nativeStartedMs) && frame.captureTiming.nativeStartedMs >= 0
      && frame.captureTiming.nativeCompletedMs >= frame.captureTiming.nativeStartedMs, "Native eye capture interval is incomplete");
    lastFrameSequence = frame.sequence;
    const outgoing: EyeServiceFrame = { ...copy(address!), source: "native-scene-capture", sequence: frame.sequence,
      eyeRevision: expected.eyeRevision, viewRevision: expected.viewRevision, settings: copy(frame.settings), view: copy(frame.view),
      captureTiming: copy(frame.captureTiming), width: frame.width, height: frame.height, pngBytes: Uint8Array.from(frame.pngBytes) };
    firstFrame = copy(outgoing);
    if (session.availability !== "ready") publishSession(ready());
    dependencies.onFrame(copy(outgoing)); for (const listener of listeners) listener(copy(outgoing));
  }
  async function operate(kind: "apply" | "restore", input: unknown, inputAddress: unknown): Promise<EyeServiceReceipt> {
    const request = copy(input) as EyeServiceOperationRequest, suppliedAddress = copy(inputAddress) as EyeServiceAddress;
    assertAddress(suppliedAddress, kind === "apply");
    check(request && equal(request.identity, identity) && request.baselineId === descriptor!.baselineId
      && typeof request.requestId === "string" && /^[a-zA-Z0-9_-]{1,128}$/u.test(request.requestId), "Eye operation baseline or request identity is invalid");
    supported(request.desired);
    check(kind !== "restore" || settingsMatch(request.desired, descriptor!.original, descriptor!), "Restore must request the observed original eyes");
    reserveEye(request.eyeRevision, request.desired);
    const expectedEpoch = epoch, expectedCancellation = cancellationGeneration, nativeRevision = wireBase + request.eyeRevision;
    return serial(async () => {
      assertEpoch(expectedEpoch, kind === "apply"); assertAddress(suppliedAddress, kind === "apply");
      check(expectedCancellation === cancellationGeneration, "Eye operation was cancelled before native dispatch");
      await verifiedRuntime(); assertEpoch(expectedEpoch, kind === "apply");
      check(expectedCancellation === cancellationGeneration, "Eye operation was cancelled before native dispatch");
      const result = kind === "apply" ? await coordinator.apply(nativeRevision, copy(request.desired)) : await coordinator.restore(nativeRevision);
      check(result.operation === kind && result.nativeReadbackVerified && (kind !== "restore" || result.originalBindingsRestored)
        && settingsMatch(result.descriptor.current, request.desired, currentDescriptor()), "Native eye operation has not verified its requested readback");
      // A hide during the native call cannot undo a committed edit. Preserve its
      // actual readback; teardown only rejects work that has not started yet.
      const observed = readback(result);
      return { status: "verified", operation: kind, requestId: request.requestId, eyeRevision: request.eyeRevision, readback: observed };
    });
  }
  return {
    getState() { return { session: copy(session), active, disposed, queued, leaseCount, fault, baselineId: descriptor?.baselineId }; },
    open() {
      check(!disposed && !active && !fault, "Eye service is active, disposed or requires recovery");
      const expectedEpoch = ++epoch;
      return serial(async () => {
        assertEpoch(expectedEpoch, false); await verifiedRuntime(); assertEpoch(expectedEpoch, false);
        check(leaseCount < acceptance!.profile.maximumLeases, "Accepted native preview lease budget exhausted");
        try {
          const connection = await coordinator.connect();
          check(connection.bootId === runtime!.bootId && connection.ownerId === runtime!.ownerId, "Eye transport belongs to another native runtime");
          const inspected = await coordinator.inspect(); acceptDescriptor(inspected.descriptor); fresh(inspected.timing, acceptance!.profile.maxReadbackAgeMs);
          assertEpoch(expectedEpoch, false);
          wireBase = Math.max(highestWire, coordinator.getState().liveEyeRevision ?? -1) + 1; revision(wireBase);
          highestEye = 0; highestEyeSettings = copy(descriptor!.current); highestWire = wireBase;
          const initial: EyeCoordinatorTuple = { eyeRevision: wireBase, viewRevision: 0, settings: copy(descriptor!.current), view: { framing: "head-and-shoulders", yawDegrees: 0, zoom: 1 } };
          highestViewRevision = 0; highestView = copy(initial.view);
          openingAttempted = true; leaseCount++;
          const opened = await coordinator.open(copy(initial)); acceptDescriptor(opened.descriptor); preview = copy(opened.preview);
          check(preview.width === 1024 && preview.height === 1024 && preview.captureSource === 9 && preview.renderTargetFormat === 2
            && preview.targetGamma === 0 && preview.forceLinearGamma === true && equal(preview.targetOuter, descriptor!.world), "Native preview differs from the accepted display profile");
          const nonce = preview.nativeFields["result.preview.nonce"];
          check(/^[a-f0-9]{32}$/u.test(nonce) && preview.nativeFields["result.preview.boot_id"] === runtime!.bootId, "Native preview generation is missing");
          address = { identity: copy(identity!), previewId: id(runtime!.bootId, nonce, preview.actor, preview.capture), renderTargetGeneration: id(runtime!.bootId, nonce, preview.target, preview.targetOuter) };
          desired = { ...copy(address), eyeRevision: 0, viewRevision: 0, settings: copy(descriptor!.current), view: copy(initial.view) };
          frames = 0; lastFrameSequence = 0; firstFrame = undefined; suspended = false; openedAt = renewedAt = dependencies.now();
          assertEpoch(expectedEpoch, false); active = true;
          publishSession(unavailable("Preparing the current player's eye preview."));
          await pump(expectedEpoch); scheduleNext(); return copy(session);
        } catch (error) { await fail(error); throw error; }
      });
    },
    updatePreview(input: unknown) {
      const request = copy(input) as EyeServicePreviewRequest; assertAddress(request); supported(request.settings, true);
      revision(request.viewRevision);
      const bounds = preview!.zoomBounds[request.view?.framing];
      check(bounds && Number.isFinite(request.view.yawDegrees) && Math.abs(request.view.yawDegrees) <= 69
        && Number.isFinite(request.view.zoom) && request.view.zoom >= bounds.min && request.view.zoom <= bounds.max, "Eye view exceeds its native geometry");
      check(request.viewRevision >= highestViewRevision && (request.viewRevision !== highestViewRevision || equal(request.view, highestView)), "Eye view revision is stale or reused");
      reserveEye(request.eyeRevision, request.settings);
      highestViewRevision = request.viewRevision; highestView = copy(request.view);
      const requestVersion = ++latestPreview, expectedEpoch = epoch;
      return serial(async () => {
        assertEpoch(expectedEpoch); assertAddress(request);
        if (requestVersion !== latestPreview) return { ...copy(request), status: "superseded" as const };
        await verifiedRuntime(); assertEpoch(expectedEpoch);
        const result = await coordinator.updatePreview(copy(tuple(request)));
        check(["queued", "unchanged"].includes(result.status), "Native preview update was not accepted");
        desired = copy(request); suspended = false;
        return { ...copy(address!), eyeRevision: request.eyeRevision, viewRevision: request.viewRevision, status: result.status as "queued" | "unchanged" };
      });
    },
    apply: (request: unknown, suppliedAddress: unknown) => operate("apply", request, suppliedAddress),
    restore: (request: unknown, suppliedAddress: unknown) => operate("restore", request, suppliedAddress),
    inspect(inputIdentity: unknown, baselineId: string) {
      check(equal(inputIdentity, identity) && descriptor?.baselineId === baselineId, "Eye inspection baseline is stale");
      return serial(async () => { await verifiedRuntime(); return readback(await coordinator.inspect()); });
    },
    cancelQueued(input: unknown) {
      const supplied = copy(input) as EyeServiceAddress; assertAddress(supplied); suspended = true; latestPreview++; cancellationGeneration++;
      const expectedEpoch = epoch;
      return serial(async () => { assertEpoch(expectedEpoch); await coordinator.cancelQueued(); return { ...copy(supplied), status: "cancelled" as const }; });
    },
    renew() { const expectedEpoch = epoch; return serial(async () => { assertEpoch(expectedEpoch); await verifiedRuntime(); assertEpoch(expectedEpoch); const result = await coordinator.renew(); renewedAt = dependencies.now(); return result.status; }); },
    subscribeFrames(input: unknown, listener: (frame: EyeServiceFrame) => void) {
      const supplied = copy(input) as EyeServiceAddress; assertAddress(supplied);
      const bound = (frame: EyeServiceFrame) => { if (equal(frame.identity, supplied.identity) && frame.previewId === supplied.previewId && frame.renderTargetGeneration === supplied.renderTargetGeneration) listener(copy(frame)); };
      listeners.add(bound);
      if (firstFrame && dependencies.now() - firstFrame.captureTiming.hostRequestSentAtMs <= acceptance!.profile.maxFrameAgeMs) bound(copy(firstFrame));
      return () => { listeners.delete(bound); };
    },
    close() { active = false; suspended = true; epoch++; latestPreview++; stopTimer(); return serial(() => closeOwned("Eye preview is closed.")); },
    dispose() { disposed = true; active = false; suspended = true; epoch++; latestPreview++; stopTimer(); listeners.clear(); return serial(() => closeOwned("Eye preview is closed.")); },
  };
}
