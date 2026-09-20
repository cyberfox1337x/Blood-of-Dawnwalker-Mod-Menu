import { deflateSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import { createEyeSessionCoordinator, type EyeCoordinatorSettings, type EyeCoordinatorTuple } from "./eyeSessionCoordinator.js";
import { encodeEyeNativeRequest, HUMAN_IRIS_WIRE_KEYS, parseEyeNativeResponse, type EyeNativeWireRequest } from "./eyeNativeProtocol.js";
import type { EyeNativeCommand } from "./eyeNativeChannel.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_session_coordinator_tests");

// Codec-shaped fixtures only; no game, filesystem channel or ready UI is started.
const boot = "1788697238-427484", owner = "a".repeat(32), schema = "dawnwalker-human-iris-uv-v1-25129649";
const names = ["IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V"];
function nativeObject(name: string, address: string) { return { name, address }; }
function settings(values = [0.25, 0.5, 0.75, 1, 0.25, 0.5, 0.75, 1]): EyeCoordinatorSettings {
  return { schemaId: schema, values: values.map((value, i) => ({ parameter: { slotId: i < 4 ? "head:3" : "head:4", materialId: i < 4 ? "coen-human-eye-left" : "coen-human-eye-right", name: names[i % 4], association: 2, index: -1 }, value: { kind: "scalar", value } })) };
}
function original() { return settings(); }
function alternate() { return settings([0.75, 1, 0.25, 0.5, 0.75, 1, 0.25, 0.5]); }
function tuple(eye = original(), eyeRevision = 0, yawDegrees = 0, viewRevision = 0): EyeCoordinatorTuple {
  return { settings: eye, eyeRevision, viewRevision, view: { yawDegrees, zoom: 1, framing: "head-and-shoulders" } };
}
function descriptor(current = original(), changedBindings = false) {
  return { identity_key: `${boot}:player-world-head-human`, baseline_id: `${boot}:human-eyes:1`, schema_id: schema,
    player: nativeObject("Player Coen", "111"), world: nativeObject("World Main", "222"), head: nativeObject("SkeletalMeshComponent HeadMesh", "333"), asset: nativeObject("SkeletalMesh CoenHead", "444"),
    form: 0, is_wolf_form: false, original_settings: original(), current_settings: current,
    bindings: [0, 1].map(i => ({ slot: i + 3, slot_name: i === 0 ? "shader_eyeLeft_shader" : "shader_eyeRight_shader",
      original: nativeObject(`MaterialInstanceConstant Eye${i}`, `${555 + i}`), current: nativeObject(changedBindings ? `MaterialInstanceDynamic Eye${i}` : `MaterialInstanceConstant Eye${i}`, `${(changedBindings ? 777 : 555) + i}`),
      parameters: original().values.slice(i * 4, i * 4 + 4).map((entry, j) => ({ parameter: entry.parameter, min: j % 2 === 0 ? 0.25 : 0.5, max: j % 2 === 0 ? 0.75 : 1, tolerance: 0.000001 })) })) };
}
function flat(value: unknown, prefix = "", output: Record<string, string> = {}): Record<string, string> {
  if (Array.isArray(value)) value.forEach((entry, i) => flat(entry, `${prefix}.${i + 1}`, output));
  else if (value !== null && typeof value === "object") Object.entries(value).forEach(([key, entry]) => flat(entry, prefix ? `${prefix}.${key}` : key, output));
  else if (value !== undefined) output[prefix] = String(value);
  return output;
}
function reply(request: EyeNativeWireRequest, result: unknown, known: unknown) {
  const echoes = { ...request } as Record<string, unknown>; delete echoes.settings;
  const fields = flat({ ...echoes, wire_version: 1, production_ready: false, gameplay_verified: false, production_capabilities: "none", known_preview: known, result });
  const bytes = Buffer.from(Object.entries(fields).map(([key, value]) => `${key}=${value.replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A")}`).join("\n") + "\n");
  return parseEyeNativeResponse(bytes);
}
function png() {
  function crc(bytes: Buffer) { let crcValue = 0xffffffff; for (const byte of bytes) { crcValue ^= byte; for (let i = 0; i < 8; i++) crcValue = (crcValue >>> 1) ^ (crcValue & 1 ? 0xedb88320 : 0); } return (crcValue ^ 0xffffffff) >>> 0; }
  function chunk(name: string, data: Buffer) { const result = Buffer.alloc(data.length + 12); result.writeUInt32BE(data.length); result.write(name, 4); data.copy(result, 8); result.writeUInt32BE(crc(result.subarray(4, -4)), result.length - 4); return result; }
  const header = Buffer.alloc(13); header.writeUInt32BE(1024); header.writeUInt32BE(1024, 4); header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header), chunk("IDAT", deflateSync(Buffer.alloc(1024 * (1024 * 4 + 1)))), chunk("IEND", Buffer.alloc(0))]);
}

function fixture() {
  const requests: EyeNativeWireRequest[] = [], events: string[] = [];
  let commandSequence = 0, frameSequence = 0, current = original(), bindingsChanged = false, queuedTuple = tuple(), previewNonce = "", suspended = false;
  let mutate: ((operation: EyeNativeCommand["operation"], result: Record<string, unknown>) => void) | undefined;
  let intercept: ((command: EyeNativeCommand) => Promise<void>) | undefined;
  let removed = false, cleanupFailure = false, cleanupLedger: { sequence: number; file_name: string }[] = [];
  let known: Record<string, unknown> = { present: false }, openFailure: "early" | "factory" | undefined;
  let nativeBytes = Buffer.concat([png(), Buffer.from("discarded-native-suffix")]);
  const source = descriptor(), resources = { actor: nativeObject("SceneCapture2D Private", "800"), capture: nativeObject("SceneCaptureComponent2D Capture", "801"), target: nativeObject("TextureRenderTarget2D Private", "802"), target_outer: source.world };
  function preview() { return { kind: "native-private-eye-preview-descriptor", nonce: previewNonce, boot_id: boot, identity_key: source.identity_key, baseline_id: source.baseline_id, schema_id: schema,
    ...resources, player: source.player, world: source.world, form: 0, is_wolf_form: false, width: 1024, height: 1024, render_target_format: 3, capture_source: 2,
    display_configuration: { write_ok: true, gamma_after: { ok: true, value: 2.2 } }, yaw_min: -69, yaw_max: 69,
    zoom_bounds: { "head-and-shoulders": { min: 0.75, max: 1.5, initial: 1 }, "eyes-close-up": { min: 0.8, max: 1.3, initial: 1 } },
    production_ready: false, preview_verified: false, gameplay_verified: false }; }
  const channel = {
    async waitForTransport() { return { bootId: boot, ownerId: owner, transport: "eye-session-prototype" as const, productionReady: false as const, sha256: "d".repeat(64) }; },
    async send(command: EyeNativeCommand) {
      await intercept?.(command);
      const request = { ...command, boot_id: boot, owner_id: owner, request_id: (++commandSequence).toString(16).padStart(32, "0"), command_sequence: commandSequence } as EyeNativeWireRequest;
      encodeEyeNativeRequest(request); requests.push(request); events.push(command.operation);
      let result: Record<string, unknown>;
      switch (command.operation) {
        case "inspect": result = { status: "observed", descriptor: descriptor(current, bindingsChanged) }; break;
        case "open":
        case "enqueue": {
          if (command.operation === "open" && openFailure === "early") { result = { status: "rejected", reason: "preview budget exhausted" }; break; }
          if (command.operation === "open") known = { present: true, boot_id: boot, owner_id: owner, lease_id: command.lease_id, preview_nonce: command.preview_nonce, identity_key: command.identity_key, baseline_id: command.baseline_id, active: false, cleanup_blocked: true };
          if (command.operation === "open" && openFailure === "factory") { result = { status: "rejected", reason: "preview factory failed" }; break; }
          previewNonce = command.preview_nonce;
          queuedTuple = tuple(settings(HUMAN_IRIS_WIRE_KEYS.map(key => command.settings[key])), command.eye_revision, command.yaw_degrees, command.view_revision);
          queuedTuple = { ...queuedTuple, view: { ...queuedTuple.view, zoom: command.zoom, framing: command.framing } }; suspended = false;
          known.active = true; known.cleanup_blocked = false;
          result = command.operation === "open" ? { status: "opened", descriptor: descriptor(current, bindingsChanged), preview: preview() } : { status: "queued", eye_revision: command.eye_revision, view_revision: command.view_revision }; break;
        }
        case "step": {
          if (suspended) { result = { status: "waiting-for-preview-request" }; break; }
          const sequence = ++frameSequence;
          result = { status: "captured-evidence", sequence, evidence: { kind: "native-private-eye-session-evidence", nonce: previewNonce, boot_id: boot, identity_key: source.identity_key, baseline_id: source.baseline_id,
            sequence, file_name: `eye-live-${previewNonce}-${String(sequence).padStart(4, "0")}.png`, ...resources, width: 1024, height: 1024, render_target_format: 3, capture_source: 2, target_gamma: 2.2,
            view_revision: queuedTuple.viewRevision, eye_revision: queuedTuple.eyeRevision, view: queuedTuple.view, settings: queuedTuple.settings,
            native_clock_id: `ue-gameplay-real-time-seconds:${boot}:${source.world.address}`, export_call_started_monotonic_ms: sequence * 100, export_call_completed_monotonic_ms: sequence * 100,
            capture_timestamp_known: false, frame_verified: false, preview_verified: false, gameplay_verified: false } }; break;
        }
        case "apply": case "restore":
          current = command.operation === "restore" ? original() : settings(HUMAN_IRIS_WIRE_KEYS.map(key => command.settings[key])); bindingsChanged = command.operation === "apply";
          result = { status: "native-readback", ok: true, kind: command.operation, identity_key: source.identity_key, baseline_id: source.baseline_id, schema_id: schema,
            current_settings: current, descriptor: descriptor(current, bindingsChanged), original_bindings_restored: command.operation === "restore", native_readback_verified: true, applied_in_game: false }; break;
        case "ack": expect(removed).toBe(true); result = { status: "acknowledged", frame_sequence: command.frame_sequence, file_name: command.file_name }; break;
        case "cancel": suspended = true; result = { status: "cancelled" }; break;
        case "renew": result = { status: "renewed" }; break;
        case "close": known.active = false; known.cleanup_blocked = cleanupFailure; result = { status: cleanupFailure ? "cleanup-failed" : "closed", cleanup_error: cleanupFailure ? "actor destruction pending" : undefined,
          cleanup: { ...resources, nonce: previewNonce, boot_id: boot, owned_cleanup_acknowledged: !cleanupFailure, pending_frames: cleanupLedger } }; break;
      }
      mutate?.(command.operation, result);
      return { request, response: reply(request, result, known), timing: { requestSequence: commandSequence, hostRequestSentAtMs: 100000 + commandSequence * 100, hostReceiptReceivedAtMs: 100020 + commandSequence * 100 }, commandSha256: "c".repeat(64), responseSha256: "d".repeat(64), productionReady: false as const };
    },
  };
  const coordinator = createEyeSessionCoordinator({ channel, frames: {
    async read(address) { events.push("read"); expect(address.bootId).toBe(boot); expect(address.previewNonce).toBe(previewNonce); return { nativeBytes, async remove() { events.push("remove"); removed = true; } }; },
    async discardKnown(address) { events.push(`discard:${address.sequence}`); removed = true; },
  } });
  return { coordinator, requests, events, setMutator(fn: typeof mutate) { mutate = fn; }, setInterceptor(fn: typeof intercept) { intercept = fn; },
    setPng(bytes: Buffer) { nativeBytes = bytes; }, setCleanupFailure(value: boolean) { cleanupFailure = value; },
    rejectOpen(kind: typeof openFailure) { openFailure = kind; },
    pending(index: number) { cleanupLedger = [{ sequence: index, file_name: `eye-live-${previewNonce}-${String(index).padStart(4, "0")}.png` }]; } };
}
async function opened() { const f = fixture(); await f.coordinator.connect(); await f.coordinator.open(tuple()); return f; }

describe("unactivated application eye session coordinator", () => {
  it("performs no work on construction, opens without inventing a frame or ready session, and protects the original baseline", async () => {
    const f = fixture(); expect(f.requests).toHaveLength(0); await f.coordinator.connect(); const opened = await f.coordinator.open(tuple());
    expect(f.requests.map(request => request.operation)).toEqual(["inspect", "open"]); expect(opened.productionReady).toBe(false);
    expect(opened).not.toHaveProperty("frame"); expect(opened).not.toHaveProperty("availability", "ready");
    (opened.descriptor.original.values[0].value as { value: number }).value = 99;
    expect(f.coordinator.getState().descriptor?.original).toEqual(original());
  });
  it("copies only CRC/inflate-validated PNG prefix bytes, removes then ACKs, and preserves real request/native intervals", async () => {
    const f = await opened(), frame = await f.coordinator.step();
    expect("kind" in frame && frame.kind).toBe("native-frame-evidence"); if (!("pngBytes" in frame)) throw new Error("Missing fixture frame");
    expect(Buffer.from(frame.pngBytes)).toEqual(png()); expect(Buffer.from(frame.pngBytes).includes(Buffer.from("discarded-native-suffix"))).toBe(false);
    expect(frame.pngEvidence.trailerKind).toBe("nonzero"); expect(frame.captureTiming).toMatchObject({ requestSequence: 3, hostRequestSentAtMs: 100300, hostReceiptReceivedAtMs: 100320, nativeStartedMs: 100, nativeCompletedMs: 100, renderCompletedAtMs: null });
    expect(f.events.slice(-4)).toEqual(["step", "read", "remove", "ack"]); expect(frame.productionReady).toBe(false);
  });
  it.each(["sequence", "revision", "target", "clock", "view", "settings"])("rejects mismatched %s evidence before reading/removing any frame", async kind => {
    const f = await opened(); f.setMutator((operation, result) => { if (operation !== "step") return; const evidence = result.evidence as Record<string, unknown>;
      if (kind === "sequence") evidence.sequence = 2;
      if (kind === "revision") evidence.eye_revision = 1;
      if (kind === "target") evidence.target = nativeObject("Another Target", "999");
      if (kind === "clock") evidence.native_clock_id = "host-receipt-time";
      if (kind === "view") evidence.view = { yawDegrees: 70, zoom: 1, framing: "head-and-shoulders" };
      if (kind === "settings") evidence.settings = alternate();
    });
    await expect(f.coordinator.step()).rejects.toThrow(); expect(f.events).not.toContain("read"); expect(f.coordinator.getState().status).toBe("faulted");
  });
  it("does not remove or acknowledge a corrupted PNG and does not replay its native capture", async () => {
    const f = await opened(), bytes = png(); bytes[bytes.length - 1] ^= 1; f.setPng(bytes);
    await expect(f.coordinator.step()).rejects.toThrow(); await expect(f.coordinator.step()).rejects.toThrow("explicit recovery");
    expect(f.events.filter(event => event === "step")).toHaveLength(1); expect(f.events).not.toContain("remove"); expect(f.events).not.toContain("ack");
  });
  it("coalesces rapid queued preview tuples and rejects conflicting revisions before native work", async () => {
    const f = await opened(); const first = f.coordinator.updatePreview(tuple(original(), 0, 3, 1)), second = f.coordinator.updatePreview(tuple(original(), 0, 6, 2));
    expect((await first).status).toBe("superseded"); expect((await second).status).toBe("queued");
    expect(f.requests.filter(request => request.operation === "enqueue")).toHaveLength(1);
    await expect(f.coordinator.updatePreview(tuple(original(), 0, 9, 2))).rejects.toThrow("revision reused");
    expect(f.requests.filter(request => request.operation === "enqueue")).toHaveLength(1);
  });
  it("cancels preview work without mutating player eyes and requires explicit enqueue to resume", async () => {
    const f = await opened(); await f.coordinator.cancelQueued(); await f.coordinator.renew(); expect((await f.coordinator.step() as { status: string }).status).toBe("waiting-for-preview-request");
    await f.coordinator.updatePreview(tuple()); expect(await f.coordinator.step()).toHaveProperty("kind", "native-frame-evidence");
    expect(f.requests.some(request => request.operation === "apply" || request.operation === "restore")).toBe(false);
  });
  it("serializes native apply/readback and preserves getter float quantization rather than requested doubles", async () => {
    const f = await opened(); f.setMutator((operation, result) => {
      if (operation !== "apply") return;
      const observed = settings([0.75000001, 1, 0.25, 0.5, 0.75, 1, 0.25, 0.5]); result.current_settings = observed;
      result.descriptor = descriptor(observed, true);
    });
    const applied = await f.coordinator.apply(1, alternate()); expect(applied.nativeReadbackVerified).toBe(true); expect(applied.appliedInGame).toBe(false);
    expect(applied.descriptor.current.values[0].value.value).toBe(0.75000001); expect(applied.descriptor.original).toEqual(original());
    await f.coordinator.close(); const restored = await f.coordinator.restore(2); expect(restored.originalBindingsRestored).toBe(true); expect(restored.descriptor.current).toEqual(original());
  });
  it("refuses an apparently successful restore whose actual material bindings are still changed", async () => {
    const f = await opened(); await f.coordinator.apply(1, alternate());
    f.setMutator((operation, result) => { if (operation === "restore") result.descriptor = descriptor(original(), true); });
    await expect(f.coordinator.restore(2)).rejects.toThrow("bindings/settings were not restored");
  });
  it("rejects a changed original baseline, human form or sparse parameter array instead of replacing cached originals", async () => {
    for (const failure of ["baseline", "form", "array"]) {
      const f = await opened(); f.setMutator((operation, result) => { if (operation !== "inspect") return; const d = result.descriptor as ReturnType<typeof descriptor>;
        if (failure === "baseline") d.original_settings = alternate();
        if (failure === "form") d.form = 1;
        if (failure === "array") d.bindings[0].parameters.pop();
      });
      await expect(f.coordinator.inspect()).rejects.toThrow(); expect(f.coordinator.getState().descriptor?.original).toEqual(original());
    }
  });
  it("preserves cleanup failure while removing and acknowledging only the exact partial-file ledger", async () => {
    const f = await opened(); f.pending(1); f.setCleanupFailure(true); const closed = await f.coordinator.close();
    expect(closed.status).toBe("cleanup-failed"); expect(f.coordinator.getState().status).toBe("faulted"); expect(f.events.slice(-3)).toEqual(["close", "discard:1", "ack"]);
    await expect(f.coordinator.open(tuple())).rejects.toThrow("explicit recovery");
    // Known baseline restoration remains available despite private cleanup failure.
    expect((await f.coordinator.restore(1)).originalBindingsRestored).toBe(true);
  });
  it("rejects a cleanup path substitution before removing any file", async () => {
    const f = await opened(); f.pending(1); f.setMutator((operation, result) => { if (operation === "close") (result.cleanup as { pending_frames: { file_name: string }[] }).pending_frames[0].file_name = "../other.png"; });
    await expect(f.coordinator.close()).rejects.toThrow("exact frame ledger"); expect(f.events.some(event => event.startsWith("discard:"))).toBe(false);
  });
  it("does not automatically retry a timed out mutation, while allowing an explicit restore attempt", async () => {
    const f = await opened(); let attempted = 0; f.setInterceptor(async command => { if (command.operation === "apply") { attempted++; throw new Error("native request timed out"); } });
    await expect(f.coordinator.apply(1, alternate())).rejects.toThrow("timed out"); await expect(f.coordinator.apply(1, alternate())).rejects.toThrow("explicit recovery");
    expect(attempted).toBe(1); expect((await f.coordinator.restore(2)).nativeReadbackVerified).toBe(true);
  });
  it.each(["early", "factory"] as const)("uses the explicitly confirmed recovery lease after %s reopen rejection", async failure => {
    const f = await opened(); await f.coordinator.close(); f.rejectOpen(failure);
    await expect(f.coordinator.open(tuple())).rejects.toThrow(); await f.coordinator.restore(1);
    const opens = f.requests.filter(request => request.operation === "open"), restore = f.requests.at(-1);
    expect(restore?.operation).toBe("restore"); if (!restore || restore.operation !== "restore") throw new Error("Missing restore");
    const expected = opens[failure === "early" ? 0 : 1]; if (expected.operation !== "open") throw new Error("Missing open");
    expect(restore.lease_id).toBe(expected.lease_id); expect(restore.preview_nonce).toBe(expected.preview_nonce);
  });
  it("rejects requested values outside strict native domains even when within readback tolerance", async () => {
    const f = await opened(); const out = settings([0.75000001, 1, 0.25, 0.5, 0.75, 1, 0.25, 0.5]);
    await expect(f.coordinator.apply(1, out)).rejects.toThrow("observed native domain"); expect(f.requests.some(request => request.operation === "apply")).toBe(false);
  });
  it("cancels queued host captures before they reach the native channel", async () => {
    const f = await opened(); const pending = f.coordinator.step(), cancelled = f.coordinator.cancelQueued();
    expect(await pending).toHaveProperty("status", "cancelled-before-capture"); await cancelled;
    expect(f.requests.some(request => request.operation === "step")).toBe(false);
  });
  it("retains the exact rejected native evidence and never reports an unacknowledged cleanup as closed", async () => {
    const f = await opened(); f.setMutator((operation, result) => { if (operation === "close") (result.cleanup as { owned_cleanup_acknowledged: boolean }).owned_cleanup_acknowledged = false; });
    await expect(f.coordinator.close()).rejects.toThrow("cleanup acknowledgement");
    const failure = f.coordinator.getState().lastFailure;
    expect(failure?.nativeFields?.["result.cleanup.owned_cleanup_acknowledged"]).toBe("false");
    expect(failure?.exchangeObserved).toBe(true); expect(failure?.timing?.requestSequence).toBeGreaterThan(0);
  });
  it("does not attribute a previous successful exchange to an operation that never reached the native channel", async () => {
    const f = await opened();
    expect(await f.coordinator.renew()).toHaveProperty("status", "renewed");
    f.setInterceptor(async command => { if (command.operation === "step") throw new Error("Eye channel request timed out"); });
    await expect(f.coordinator.step()).rejects.toThrow("timed out");
    const failure = f.coordinator.getState().lastFailure;
    expect(failure).toMatchObject({ reason: expect.stringContaining("timed out"), exchangeObserved: false });
    expect(failure?.nativeFields).toBeUndefined(); expect(failure?.timing).toBeUndefined();
    expect(f.requests.filter(request => request.operation === "step")).toHaveLength(0);
  });
  it("accepts only the explicit read-back V8 factory profile without inventing display writes", async () => {
    const f = fixture(); f.setMutator((operation, result) => {
      if (operation === "open") Object.assign(result.preview as object, { render_target_format: 2, capture_source: 9,
        display_configuration: { configuration_source: "native-factory-defaults", configuration_verified: true, writes_performed: false,
          gamma_after: { ok: true, type: "number", value: 0 }, force_linear_after: { ok: true, type: "boolean", value: true } } });
      if (operation === "step") Object.assign(result.evidence as object, { render_target_format: 2, capture_source: 9, target_gamma: 0, force_linear_gamma: true });
    });
    await f.coordinator.connect(); const opened = await f.coordinator.open(tuple()); expect(opened.preview).toMatchObject({ targetGamma: 0, forceLinearGamma: true, captureSource: 9, renderTargetFormat: 2 });
    expect(await f.coordinator.step()).toHaveProperty("kind", "native-frame-evidence");
    f.setMutator((operation, result) => { if (operation === "step") Object.assign(result.evidence as object, { render_target_format: 2, capture_source: 9, target_gamma: 0, force_linear_gamma: false }); });
    await expect(f.coordinator.step()).rejects.toThrow("force-linear profile");
  });
});
