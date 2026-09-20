import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { constants, type BigIntStats } from "node:fs";
import { lstat, open, realpath, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, normalize, resolve } from "node:path";
import { inflateSync } from "node:zlib";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_native_frame_evidence_transport");

const MAX_PNG_BYTES = 16 * 1024 * 1024;
// Actual V5 2048-square exports retain about 2.36 MiB after IEND. This
// discard-only cap remains within the separate immutable 16 MiB file cap.
const MAX_NATIVE_TRAILER_BYTES = 4 * 1024 * 1024;
const MAX_PIXELS = 4096 * 4096;
const MAX_DIMENSION = 4096;
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const NONCE_PATTERN = /^[a-f0-9]{32}$/;

export type NativeEyeObjectIdentity = Readonly<{ address: string; name: string }>;
export type NativeEyeExportIdentity = Readonly<{
  player: NativeEyeObjectIdentity;
  world: NativeEyeObjectIdentity;
  form: 0 | 1;
  is_wolf_form: false;
  doll: NativeEyeObjectIdentity;
  capture: NativeEyeObjectIdentity;
  head: NativeEyeObjectIdentity;
  head_asset: NativeEyeObjectIdentity;
  target: NativeEyeObjectIdentity;
  head_materials: readonly (NativeEyeObjectIdentity & Readonly<{ slot: number; slot_name: string; dynamic: boolean }>)[];
}>;

export type NativeEyeExportReceipt = Readonly<{
  schema: 2;
  operation: "export";
  production_capabilities: "none";
  kind: "native-eye-frame-export-evidence";
  nonce: string;
  boot_id: string;
  file_name: string;
  width: 2048;
  height: 2048;
  render_target_format: 2;
  capture_source: 9;
  export_started_at_epoch_ms: number;
  export_completed_at_epoch_ms: number;
  capture_timestamp_known: false;
  frame_verified: false;
  preview_verified: false;
  gameplay_verified: false;
  identity: NativeEyeExportIdentity;
}>;

export type NativeEyeCameraPhase = "baseline" | "changed" | "restored";
type NativeRotation = Readonly<{ pitch: number; yaw: number; roll: number }>;
export type NativeEyeCameraPhaseReceipt = Omit<NativeEyeExportReceipt, "kind" | "operation"> & Readonly<{
  kind: "native-eye-camera-roundtrip-evidence";
  operation: "camera-roundtrip";
  phase: NativeEyeCameraPhase;
  relative_rotation: NativeRotation;
  before: NativeRotation;
  changed: NativeRotation;
  restored: true;
}>;

export type NativeEyePngEvidence = Readonly<{
  purpose: "native-eye-export-evidence";
  previewVerified: false;
  capturedAtMs: null;
  nonce: string;
  fileName: string;
  sha256: string;
  pngPrefixSha256: string;
  trailerSha256: string;
  nativeFileBytes: number;
  pngPrefixBytes: number;
  trailingZeroPadding: number;
  trailingBytes: number;
  trailerKind: "none" | "zero" | "nonzero";
  width: number;
  height: number;
  fileModifiedAtMs: number;
  receipt: NativeEyeExportReceipt | NativeEyeCameraPhaseReceipt;
  pngBytes: ArrayBuffer;
}>;

export type NativeEyeExportWindow = Readonly<{
  nonce: string;
  intent: "eye-readback-export" | "eye-preview-camera-roundtrip";
  issuedAtMs: number;
  expiresAtMs: number;
}>;

export const PRIVATE_EYE_PHASES = ["front", "yaw-min", "yaw-max", "eyes-closeup", "head-zoom-min", "head-zoom-max", "eyes-zoom-min", "eyes-zoom-max", "restored-front"] as const;
export const PRIVATE_EYE_DIAGNOSTICS = ["diag-world-ldr", "diag-isolated-ldr", "diag-manual-zero", "diag-manual-low", "diag-manual-high", "diag-inventory-color"] as const;
type PrivateEyePhase = typeof PRIVATE_EYE_PHASES[number];
type NativeVector = Readonly<{ X: number; Y: number; Z: number }>;
type PrivateWindow = Omit<NativeEyeExportWindow, "intent"> & Readonly<{ intent: "eye-private-preview-roundtrip" }>;
export type NativePrivateEyeSource = Readonly<{
  player: NativeEyeObjectIdentity; world: NativeEyeObjectIdentity; head: NativeEyeObjectIdentity; asset: NativeEyeObjectIdentity;
  form: 0 | 1; is_wolf_form: false;
  eye_materials: readonly [NativeEyeObjectIdentity, NativeEyeObjectIdentity];
  eye_bones: readonly [Readonly<{ name: string; index: number }>, Readonly<{ name: string; index: number }>];
}>;

export const HUMAN_IRIS_SCALARS = ["IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V", "IrisColorBalance", "IrisColorBalanceSmoothness", "Iris_Saturation", "Iris_Value", "Emissivnes"] as const;
export const HUMAN_IRIS_VECTORS = ["Leukocoria_Color", "CloudyIrisColor"] as const;
const IRIS_SWAPS: Readonly<Record<string, string>> = { IrisColor1_U: "IrisColor2_U", IrisColor1_V: "IrisColor2_V", IrisColor2_U: "IrisColor1_U", IrisColor2_V: "IrisColor1_V" };
type IrisValue = number | Readonly<{ R: number; G: number; B: number; A: number }>;
export type NativeHumanIrisSource = Readonly<{ source: NativePrivateEyeSource; parameters: readonly [Readonly<Record<string, IrisValue>>, Readonly<Record<string, IrisValue>>] }>;
type IrisWindow = Omit<NativeEyeExportWindow, "intent"> & Readonly<{ intent: "human-iris-pair-roundtrip" }>;

export type EyeFrameEvidenceOptions = Readonly<{
  // Selected once by the coordinator. A native filename or receipt cannot
  // choose a directory; no directories or files are created by this reader.
  sessionDirectory: string;
  bootId: string;
  expectedIdentity: NativeEyeExportIdentity;
  now?: () => number;
}>;

type PathSnapshot = Readonly<{ path: string; canonicalPath: string; status: BigIntStats }>;

function boundedRecord(value: unknown, label: string, maximumKeys: number): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).length > maximumKeys) throw new Error(`Native eye ${label} metadata is invalid or oversized.`);
  return value as Record<string, unknown>;
}

function nativeText(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length < 1 || value.length > 1024
    || [...value].some(character => character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127)) throw new Error(`Native eye ${label} is invalid.`);
  return value;
}

function normalizeNativeObject(value: unknown): NativeEyeObjectIdentity {
  const entry = boundedRecord(value, "object", 8);
  const address = nativeText(entry.address, "object address");
  if (!/^[1-9][0-9]{0,19}$/.test(address) || BigInt(address) > 18446744073709551615n) throw new Error("Native eye object address is invalid.");
  const name = nativeText(entry.name, "object name");
  if (name.includes("Default__")) throw new Error("Native eye evidence cannot bind a class-default object.");
  return { address, name };
}

export function normalizeNativeEyeExportIdentity(value: unknown): NativeEyeExportIdentity {
  const entry = boundedRecord(value, "identity", 12);
  if (![0, 1].includes(entry.form as number) || entry.is_wolf_form !== false) throw new Error("Native eye evidence form is unsupported.");
  if (!Array.isArray(entry.head_materials) || entry.head_materials.length < 1 || entry.head_materials.length > 16) throw new Error("Native eye evidence head-material list is invalid.");
  const materials = entry.head_materials.map((value, index) => {
    const material = boundedRecord(value, "material", 8);
    if (material.slot !== index || typeof material.dynamic !== "boolean") throw new Error("Native eye head-material slot order or type is invalid.");
    return { ...normalizeNativeObject(material), slot: index, slot_name: nativeText(material.slot_name, "material slot name"), dynamic: material.dynamic };
  });
  return { player: normalizeNativeObject(entry.player), world: normalizeNativeObject(entry.world), form: entry.form as 0 | 1,
    is_wolf_form: false, doll: normalizeNativeObject(entry.doll), capture: normalizeNativeObject(entry.capture),
    head: normalizeNativeObject(entry.head), head_asset: normalizeNativeObject(entry.head_asset), target: normalizeNativeObject(entry.target), head_materials: materials };
}

function verifiedReceipt(value: unknown, window: NativeEyeExportWindow, bootId: string, identity: NativeEyeExportIdentity, now: number): NativeEyeExportReceipt {
  const entry = boundedRecord(value, "export receipt", 32);
  // The frozen v3 dispatcher wraps the export under schema 2. Direct module
  // fixtures with schema 1 are not evidence of that attested dispatch route.
  if (entry.ok !== true || entry.schema !== 2 || entry.operation !== "export" || entry.production_capabilities !== "none"
    || entry.kind !== "native-eye-frame-export-evidence" || entry.export_invoked !== true || entry.capture_requested !== false
    || entry.nonce !== window.nonce || entry.boot_id !== bootId || entry.file_name !== `eye-frame-${window.nonce}.png`
    || entry.width !== 2048 || entry.height !== 2048 || entry.render_target_format !== 2 || entry.capture_source !== 9
    || entry.capture_timestamp_known !== false || entry.frame_verified !== false || entry.preview_verified !== false || entry.gameplay_verified !== false) throw new Error("Native eye export receipt does not match this evidence request.");
  const started = entry.export_started_at_epoch_ms;
  const completed = entry.export_completed_at_epoch_ms;
  if (typeof started !== "number" || typeof completed !== "number" || !Number.isSafeInteger(started) || !Number.isSafeInteger(completed)
    || started < window.issuedAtMs || completed < started || completed > window.expiresAtMs || completed > now) throw new Error("Native eye export interval is stale, future-dated, or outside its request.");
  const observedIdentity = normalizeNativeEyeExportIdentity(entry.identity);
  if (JSON.stringify(observedIdentity) !== JSON.stringify(identity)) throw new Error("Native eye export identity or material bindings changed.");
  return { schema: 2, operation: "export", production_capabilities: "none", kind: "native-eye-frame-export-evidence", nonce: window.nonce, boot_id: bootId,
    file_name: `eye-frame-${window.nonce}.png`, width: 2048, height: 2048, render_target_format: 2, capture_source: 9,
    export_started_at_epoch_ms: started, export_completed_at_epoch_ms: completed, capture_timestamp_known: false,
    frame_verified: false, preview_verified: false, gameplay_verified: false, identity: observedIdentity };
}

function nativeRotation(value: unknown): NativeRotation {
  const entry = boundedRecord(value, "camera rotation", 3);
  if (![entry.pitch, entry.yaw, entry.roll].every(value => typeof value === "number" && Number.isFinite(value))
    || Math.abs(entry.pitch as number) > 90 || Math.abs(entry.yaw as number) > 363 || Math.abs(entry.roll as number) > 360) throw new Error("Native eye camera rotation is invalid.");
  return { pitch: entry.pitch as number, yaw: entry.yaw as number, roll: entry.roll as number };
}

function rotationsMatch(left: NativeRotation, right: NativeRotation): boolean {
  return (["pitch", "yaw", "roll"] as const).every(key => Math.abs(((left[key] - right[key] + 180) % 360 + 360) % 360 - 180) <= 0.00001);
}

function verifiedCameraReceipt(value: unknown, phase: NativeEyeCameraPhase, window: NativeEyeExportWindow, bootId: string, identity: NativeEyeExportIdentity, now: number): { receipt: NativeEyeCameraPhaseReceipt; proof: string } {
  const entry = boundedRecord(value, "camera receipt", 24);
  if (entry.ok !== true || entry.schema !== 2 || entry.operation !== "camera-roundtrip" || entry.production_capabilities !== "none"
    || entry.kind !== "native-eye-camera-roundtrip-evidence"
    || entry.nonce !== window.nonce || entry.boot_id !== bootId || entry.mutation_attempted !== true || entry.restored !== true
    || entry.delta_yaw_degrees !== 3 || entry.exports_invoked !== 3 || entry.frame_verified !== false || entry.gameplay_verified !== false
    || !Array.isArray(entry.frames) || entry.frames.length !== 3) throw new Error("Native eye camera receipt is incomplete or does not match its request.");
  const observedIdentity = normalizeNativeEyeExportIdentity(entry.identity);
  if (JSON.stringify(observedIdentity) !== JSON.stringify(identity)) throw new Error("Native eye camera identity or material bindings changed.");
  const before = nativeRotation(entry.before);
  const changed = nativeRotation(entry.changed);
  if (!rotationsMatch(changed, { ...before, yaw: before.yaw + 3 })) throw new Error("Native eye camera change did not read back three degrees.");
  const phases = ["baseline", "changed", "restored"] as const;
  let priorCompleted = window.issuedAtMs;
  let selected: NativeEyeCameraPhaseReceipt | undefined;
  const observations: unknown[] = [];
  for (let index = 0; index < phases.length; index += 1) {
    const expectedPhase = phases[index];
    const frame = boundedRecord(entry.frames[index], "camera frame", 16);
    const fileName = `eye-camera-${window.nonce}-${expectedPhase}.png`;
    if (frame.phase !== expectedPhase || frame.file_name !== fileName || frame.export_invoked !== true || frame.capture_requested !== true
      || frame.width !== 2048 || frame.height !== 2048 || frame.render_target_format !== 2 || frame.capture_source !== 9
      || frame.capture_timestamp_known !== false || frame.frame_verified !== false) throw new Error("Native eye camera phase, filename or capture metadata is invalid.");
    const started = frame.export_started_at_epoch_ms;
    const completed = frame.export_completed_at_epoch_ms;
    if (typeof started !== "number" || typeof completed !== "number" || !Number.isSafeInteger(started) || !Number.isSafeInteger(completed)
      || started < priorCompleted || completed < started || completed > window.expiresAtMs || completed > now) throw new Error("Native eye camera exports are stale, future-dated or out of order.");
    priorCompleted = completed;
    const rotation = nativeRotation(frame.relative_rotation);
    if (!rotationsMatch(rotation, expectedPhase === "changed" ? changed : before)) throw new Error("Native eye camera phase does not match its observed rotation or restoration.");
    observations.push({ phase: expectedPhase, fileName, started, completed, rotation });
    if (expectedPhase === phase) selected = { schema: 2, operation: "camera-roundtrip", production_capabilities: "none",
      kind: "native-eye-camera-roundtrip-evidence", nonce: window.nonce, boot_id: bootId,
      file_name: fileName, width: 2048, height: 2048, render_target_format: 2, capture_source: 9,
      export_started_at_epoch_ms: started, export_completed_at_epoch_ms: completed, capture_timestamp_known: false,
      frame_verified: false, preview_verified: false, gameplay_verified: false, identity: observedIdentity,
      phase, relative_rotation: rotation, before, changed, restored: true };
  }
  if (!selected) throw new Error("Unknown native eye camera phase.");
  return { receipt: selected, proof: JSON.stringify({ identity: observedIdentity, before, changed, observations }) };
}

function matchingIdentity(left: BigIntStats, right: BigIntStats): boolean {
  return left.dev === right.dev && left.ino === right.ino && left.mode === right.mode;
}

function matchingFile(left: BigIntStats, right: BigIntStats): boolean {
  return matchingIdentity(left, right) && left.nlink === right.nlink && left.size === right.size
    && left.mtimeNs === right.mtimeNs && left.ctimeNs === right.ctimeNs;
}

function pathEqual(left: string, right: string): boolean {
  const normalizePath = (value: string) => process.platform === "win32" ? normalize(value).toLowerCase() : normalize(value);
  return normalizePath(left) === normalizePath(right);
}

// Node identifies symlinks/junctions, but does not expose every Windows reparse
// attribute, so the native attribute is read through PowerShell. The program is a
// constant and every path reaches it as JSON on stdin, never as script text.
//
// It runs as one reused worker rather than a process per question. Each PNG read
// attests its path chain twice, before and after the read, and a cold powershell.exe
// measured 788 ms to start: 1.6 s per read, about 14 s of pure process startup for a
// nine-frame consume. The check itself is unchanged - every request still does its own
// Get-Item at the moment it is asked - so what is amortised is the startup, not the
// guarantee.
const PATH_ATTESTATION_PROGRAM = "$ErrorActionPreference='Stop';"
  + "while($null -ne ($line=[Console]::In.ReadLine())){"
  + "$verdict='error';"
  + "try{$items=$line|ConvertFrom-Json;$verdict='plain';"
  + "foreach($itemPath in $items){$item=Get-Item -LiteralPath $itemPath -Force;"
  + "if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){$verdict='reparse';break}}}"
  + "catch{$verdict='error'};"
  + "[Console]::Out.WriteLine($verdict);[Console]::Out.Flush()}";
// Two budgets, because the two costs differ by more than two orders of magnitude.
// Measured on this machine: a new worker's first answer costs ~1.5 s, almost all of it
// PowerShell's own startup, and every answer after it costs 2-5 ms. Charging startup
// against a steady-state allowance is how a slow start gets reported as a reparse point.
const PATH_ATTESTATION_TIMEOUT_MS = 10000;
const PATH_ATTESTATION_STARTUP_TIMEOUT_MS = 60000;
const PATH_ATTESTATION_MAX_REPLY_BYTES = 4096;
const PATH_ATTESTATION_FAILED = "Native eye evidence contains a reparse point or its path attributes could not be verified.";

export type PathAttestationWorker = Readonly<{
  ask: (paths: readonly string[]) => Promise<string>;
  alive: () => boolean;
  stop: () => void;
}>;

function unreferenceStream(stream: unknown): void {
  const candidate = stream as { unref?: () => void } | null;
  if (candidate && typeof candidate.unref === "function") candidate.unref();
}

function createPathAttestationWorker(): PathAttestationWorker {
  const encoded = Buffer.from(PATH_ATTESTATION_PROGRAM, "utf16le").toString("base64");
  const executable = join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const child = spawn(executable, ["-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
    { windowsHide: true, stdio: ["pipe", "pipe", "ignore"] });
  let buffered = "";
  let waiting: { settle: (verdict: string) => void; fail: (failure: Error) => void; timer: NodeJS.Timeout } | null = null;
  let running = true;
  // Whether this worker has ever answered. Until it has, a request is still paying for
  // PowerShell to start; afterwards the pipe is warm and the tight budget applies.
  let answered = false;

  // Every route out of this worker ends here, so a worker that dies, hangs or answers
  // out of turn rejects the request in flight. Silence is never read as a pass.
  const halt = (reason: string) => {
    if (!running) return;
    running = false;
    const pending = waiting;
    waiting = null;
    if (pending) { clearTimeout(pending.timer); pending.fail(new Error(reason)); }
    child.kill();
  };

  child.stdout.setEncoding("utf8");
  child.stdout.on("data", chunk => {
    buffered += chunk;
    if (buffered.length > PATH_ATTESTATION_MAX_REPLY_BYTES) { halt("Native eye path verification returned an oversized answer."); return; }
    while (running) {
      const breakAt = buffered.indexOf("\n");
      if (breakAt < 0) return;
      const verdict = buffered.slice(0, breakAt).trim();
      buffered = buffered.slice(breakAt + 1);
      // A blank line is startup noise, not an answer; consuming it here keeps every
      // later reply lined up with the request that asked for it.
      if (verdict === "") continue;
      const pending = waiting;
      waiting = null;
      if (!pending) { halt("Native eye path verification answered a question it was not asked."); return; }
      clearTimeout(pending.timer);
      answered = true;
      pending.settle(verdict);
    }
  });
  child.stdout.on("error", () => halt("Native eye path verification could not be read."));
  child.stdin.on("error", () => halt("Native eye path verification could not be asked."));
  child.on("error", () => halt("Native eye path verification could not be started."));
  child.on("exit", () => halt("Native eye path verification stopped unexpectedly."));
  // The worker must not hold the host process open. Closing our stdin ends its read
  // loop, so it also shuts itself down when the host goes away.
  child.unref();
  // The pipes are sockets at runtime and keep the host's event loop alive, but Node
  // types them as plain streams, so the capability is checked rather than assumed.
  unreferenceStream(child.stdin);
  unreferenceStream(child.stdout);

  return {
    alive: () => running,
    stop: () => halt("Native eye path verification was discarded."),
    ask: paths => new Promise<string>((settle, fail) => {
      if (!running) { fail(new Error("Native eye path verification is not running.")); return; }
      if (waiting) { fail(new Error("Native eye path verification is already busy.")); return; }
      const budget = answered ? PATH_ATTESTATION_TIMEOUT_MS : PATH_ATTESTATION_STARTUP_TIMEOUT_MS;
      const timer = setTimeout(() => halt("Native eye path verification timed out after "
        + budget + "ms" + (answered ? "." : " while starting.")), budget);
      waiting = { settle, fail, timer };
      // A Windows path cannot contain a newline and JSON escapes anything that could,
      // so one request is always exactly one line.
      child.stdin.write(JSON.stringify(paths) + "\n", failure => { if (failure) halt("Native eye path verification could not be asked."); });
    }),
  };
}

// One question at a time: the worker is a single pipe, and its replies are matched to
// requests by order.
let pathAttestationQueue: Promise<unknown> = Promise.resolve();

// One retry, and only when the worker failed to answer at all. A verdict is never
// retried: "reparse" and "error" are answers, and re-asking until one of them changes is
// exactly how a check like this stops meaning anything. A worker that could not start,
// died, or timed out is a broken pipe rather than evidence about the path, and refusing
// on that reported a reparse point that was never there.
export const PATH_ATTESTATION_ATTEMPTS = 2;

// The reuse-and-retry policy owns its cached worker and takes the process as a
// dependency, so what it does when a worker dies can be exercised without a live
// PowerShell - and so there is no mutable worker handle at module scope.
export function cyberfox1337x_createAttestationAsker(makeWorker: () => PathAttestationWorker) {
  let reused: PathAttestationWorker | null = null;
  return async function askPathAttestation(paths: readonly string[]): Promise<string> {
    for (let attempt = 1; ; attempt += 1) {
      if (!reused || !reused.alive()) reused = makeWorker();
      const worker = reused;
      try {
        return await worker.ask(paths);
      } catch (failure) {
        // A worker that failed once is not trusted again; the retry starts a fresh
        // process rather than reusing a pipe of unknown state.
        worker.stop();
        if (reused === worker) reused = null;
        if (attempt >= PATH_ATTESTATION_ATTEMPTS) throw failure;
      }
    }
  };
}

const askPathAttestationWorker = cyberfox1337x_createAttestationAsker(createPathAttestationWorker);

async function assertWindowsPlainPaths(paths: readonly string[]): Promise<void> {
  if (process.platform !== "win32") return;
  const answer = pathAttestationQueue.then(() => askPathAttestationWorker(paths), () => askPathAttestationWorker(paths));
  pathAttestationQueue = answer.catch(() => undefined);
  let verdict: string;
  try {
    verdict = await answer;
  } catch (failure) {
    // Why the worker could not answer is the entire diagnosis when this fails
    // intermittently. Discarding it turned one rare failure into a hunt through the
    // whole suite, so the reason travels with the error from here on.
    const reason = failure instanceof Error ? failure.message : String(failure);
    throw new Error(PATH_ATTESTATION_FAILED + " " + reason, { cause: failure });
  }
  if (verdict !== "plain") throw new Error(PATH_ATTESTATION_FAILED + " Worker verdict: " + verdict + ".");
}

async function directorySnapshots(directory: string): Promise<readonly PathSnapshot[]> {
  if (!isAbsolute(directory)) throw new Error("Eye evidence requires an absolute, fixed session directory.");
  const absolute = resolve(directory);
  if (process.platform === "win32" && (/^(?:\\\\|\/\/)/.test(absolute) || !/^[A-Za-z]:\\/.test(absolute))) throw new Error("Eye evidence must use a local drive directory.");
  const snapshots: PathSnapshot[] = [];
  let current = absolute;
  while (true) {
    const status = await lstat(current, { bigint: true });
    if (!status.isDirectory() || status.isSymbolicLink()) throw new Error("Eye evidence directories must be ordinary directories without links or junctions.");
    const canonicalPath = await realpath(current);
    if (!matchingIdentity(status, await lstat(canonicalPath, { bigint: true }))) throw new Error("Eye evidence directory resolves outside its fixed identity.");
    snapshots.push({ path: current, canonicalPath, status });
    const parent = dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return snapshots;
}

async function recheckDirectories(snapshots: readonly PathSnapshot[]): Promise<void> {
  for (const snapshot of snapshots) {
    const current = await lstat(snapshot.path, { bigint: true });
    if (!current.isDirectory() || current.isSymbolicLink() || !matchingIdentity(current, snapshot.status)
      || !pathEqual(await realpath(snapshot.path), snapshot.canonicalPath)) throw new Error("Eye evidence directory changed during the read.");
  }
}

async function readImmutablePng(directory: string, fileName: string, window: Pick<NativeEyeExportWindow, "issuedAtMs" | "expiresAtMs"> | undefined, openFile: typeof open, allowEmpty = false): Promise<{ bytes: Buffer; modifiedAtMs: number; status: BigIntStats; directories: readonly PathSnapshot[] }> {
  const directories = await directorySnapshots(directory);
  const filePath = join(directory, fileName);
  await assertWindowsPlainPaths([...directories.map(snapshot => snapshot.path), filePath]);
  const before = await lstat(filePath, { bigint: true });
  if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n || before.size < (allowEmpty ? 0n : 1n) || before.size > BigInt(MAX_PNG_BYTES)) throw new Error("Native eye PNG must be an ordinary, bounded file with a single link.");
  if (!pathEqual(await realpath(filePath), join(directories[0].canonicalPath, fileName))) throw new Error("Native eye PNG resolves outside its fixed path.");
  const modifiedAtMs = Number(before.mtimeNs / 1000000n);
  if (window && (modifiedAtMs < window.issuedAtMs || modifiedAtMs > window.expiresAtMs)) throw new Error("Native eye PNG was not produced inside the attested export window.");
  const handle = await openFile(filePath, constants.O_RDONLY | (process.platform === "win32" ? 0 : constants.O_NOFOLLOW));
  try {
    const opened = await handle.stat({ bigint: true });
    if (!matchingFile(before, opened)) throw new Error("Native eye PNG changed while opening.");
    const bytes = Buffer.alloc(Number(opened.size));
    let offset = 0;
    while (offset < bytes.length) {
      const { bytesRead } = await handle.read(bytes, offset, bytes.length - offset, offset);
      if (bytesRead === 0) throw new Error("Native eye PNG was truncated during the read.");
      offset += bytesRead;
    }
    const after = await handle.stat({ bigint: true });
    const pathAfter = await lstat(filePath, { bigint: true });
    if (!matchingFile(opened, after) || !matchingFile(opened, pathAfter) || pathAfter.isSymbolicLink()) throw new Error("Native eye PNG changed during the read.");
    await recheckDirectories(directories);
    await assertWindowsPlainPaths([...directories.map(snapshot => snapshot.path), filePath]);
    const final = await lstat(filePath, { bigint: true });
    if (!matchingFile(opened, final)) throw new Error("Native eye PNG changed during final verification.");
    return { bytes, modifiedAtMs, status: final, directories };
  } finally { await handle.close(); }
}

export type EyeSessionFileAddress = Readonly<{ bootId: string; previewNonce: string; sequence: number; fileName: string }>;

/** Privileged host file port. Raw bytes never cross IPC: the coordinator must
 * validate the PNG and copy only its prefix before publishing a renderer frame.
 * Native ACK follows successful removal, never merely a successful read.
 */
export function createEyeSessionPngStore(options: Readonly<{
  bootId: string; previewNonce: string; trustedTestRoot?: string;
  beforeRemove?: (address: EyeSessionFileAddress, nativeBytes: Uint8Array) => Promise<void>;
}>) {
  const { bootId, previewNonce, beforeRemove } = options;
  if (!/^\d{1,16}-\d{1,16}$/.test(bootId) || !NONCE_PATTERN.test(previewNonce)) throw new Error("Invalid native frame store identity.");
  let root = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames";
  if (options.trustedTestRoot) {
    const fixture = resolve(options.trustedTestRoot);
    if (!pathEqual(dirname(fixture), resolve(tmpdir())) || !basename(fixture).startsWith("dawnwalker-eye-frame-test-")) throw new Error("Frame fixture root is not an isolated temporary directory.");
    root = fixture;
  }
  const directory = join(root, bootId);
  const pending = new Map<number, Awaited<ReturnType<typeof readImmutablePng>>>();
  const removed = new Set<number>();
  let busy = false;
  function address(value: EyeSessionFileAddress): string {
    if (value.bootId !== bootId || value.previewNonce !== previewNonce || !Number.isSafeInteger(value.sequence)
      || value.sequence < 1 || value.sequence > 1200 || value.fileName !== `eye-live-${previewNonce}-${String(value.sequence).padStart(4, "0")}.png`) throw new Error("Frame address differs from its owned native generation.");
    return value.fileName;
  }
  async function remove(value: EyeSessionFileAddress): Promise<void> {
    const fileName = address(value), original = pending.get(value.sequence);
    if (!original || removed.has(value.sequence) || busy) throw new Error("Frame removal lacks an unconsumed read receipt.");
    busy = true;
    try {
      const current = await readImmutablePng(directory, fileName, undefined, open, original.status.size === 0n);
      if (!matchingFile(original.status, current.status) || !original.bytes.equals(current.bytes)) throw new Error("Native frame changed after consumption; retained for diagnosis.");
      // A trusted QA host may preserve the full original before consumption.
      // Failure retains the file and prevents the caller's native ACK.
      await beforeRemove?.(Object.freeze({ ...value }), new Uint8Array(original.bytes));
      await recheckDirectories(original.directories);
      const path = join(directory, fileName), final = await lstat(path, { bigint: true });
      if (!matchingFile(original.status, final) || final.isSymbolicLink()) throw new Error("Native frame changed before removal.");
      await unlink(path);
      pending.delete(value.sequence); removed.add(value.sequence);
    } finally { busy = false; }
  }
  async function read(value: EyeSessionFileAddress, cleanupOnly = false) {
    const request = Object.freeze({ ...value }), fileName = address(request);
    if (busy || pending.size >= 2 || pending.has(request.sequence) || removed.has(request.sequence)) throw new Error("Native frame is busy, replayed or exceeds the two-file backlog.");
    busy = true;
    try {
      const snapshot = await readImmutablePng(directory, fileName, undefined, open, cleanupOnly);
      pending.set(request.sequence, snapshot);
      return { nativeBytes: new Uint8Array(snapshot.bytes), remove: () => remove(request) };
    } finally { busy = false; }
  }
  return {
    read: (value: EyeSessionFileAddress) => read(value),
    // Call only with a sequence/name from the matching native cleanup ledger.
    // Partial exports may be empty/non-PNG, but remain bounded ordinary files.
    async discardKnown(input: EyeSessionFileAddress): Promise<void> {
      const value = Object.freeze({ ...input });
      const fileName = address(value);
      if (pending.has(value.sequence)) return remove(value);
      if (busy || removed.has(value.sequence)) throw new Error("Native cleanup is busy or already consumed.");
      busy = true;
      // A failed export may reserve its native ledger entry before creating a
      // file. Verify absence under unchanged ordinary directories before ACK.
      try {
        const directories = await directorySnapshots(directory);
        await assertWindowsPlainPaths(directories.map(entry => entry.path));
        let absent = false;
        try { await lstat(join(directory, fileName)); }
        catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; absent = true; }
        if (absent) {
          await recheckDirectories(directories);
          try { await lstat(join(directory, fileName)); throw new Error("Native cleanup file appeared during absence verification."); }
          catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
          removed.add(value.sequence);
          return;
        }
      } finally { busy = false; }
      const file = await read(value, true); await file.remove();
    },
  };
}

const CRC_TABLE = Uint32Array.from({ length: 256 }, (_, value) => {
  let result = value;
  for (let bit = 0; bit < 8; bit += 1) result = (result & 1) ? (0xedb88320 ^ (result >>> 1)) : (result >>> 1);
  return result >>> 0;
});

function pngCrc(bytes: Buffer): number {
  let value = 0xffffffff;
  for (const byte of bytes) value = CRC_TABLE[(value ^ byte) & 255] ^ (value >>> 8);
  return (value ^ 0xffffffff) >>> 0;
}

export function inspectNativeEyePng(bytes: Buffer): Readonly<{ width: number; height: number }> {
  if (bytes.length < 57 || bytes.length > MAX_PNG_BYTES || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) throw new Error("Native eye frame is not a bounded PNG.");
  let offset = 8;
  let width = 0;
  let height = 0;
  let channels = 0;
  let ended = false;
  let idatEnded = false;
  const compressed: Buffer[] = [];
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) throw new Error("Native eye PNG has a truncated chunk.");
    const length = bytes.readUInt32BE(offset);
    if (length > bytes.length - offset - 12) throw new Error("Native eye PNG chunk exceeds the file.");
    const type = bytes.toString("ascii", offset + 4, offset + 8);
    const end = offset + 12 + length;
    if (!/^[A-Za-z]{4}$/.test(type) || pngCrc(bytes.subarray(offset + 4, end - 4)) !== bytes.readUInt32BE(end - 4)) throw new Error("Native eye PNG chunk checksum is invalid.");
    if (offset === 8 && type !== "IHDR") throw new Error("Native eye PNG header is missing.");
    if (type === "IHDR") {
      if (offset !== 8 || length !== 13) throw new Error("Native eye PNG has an invalid or repeated header.");
      width = bytes.readUInt32BE(offset + 8);
      height = bytes.readUInt32BE(offset + 12);
      const depth = bytes[offset + 16];
      const colorType = bytes[offset + 17];
      if (!width || !height || width > MAX_DIMENSION || height > MAX_DIMENSION || width * height > MAX_PIXELS
        || depth !== 8 || ![2, 6].includes(colorType) || bytes[offset + 18] !== 0 || bytes[offset + 19] !== 0 || bytes[offset + 20] !== 0) throw new Error("Native eye PNG dimensions or encoding are unsupported.");
      channels = colorType === 6 ? 4 : 3;
    } else if (type === "IDAT") {
      if (idatEnded) throw new Error("Native eye PNG image data is not contiguous.");
      compressed.push(bytes.subarray(offset + 8, end - 4));
    } else {
      if (compressed.length) idatEnded = true;
      if (type === "IEND") {
        if (length !== 0 || end !== bytes.length || !compressed.length) throw new Error("Native eye PNG end marker or image data is invalid.");
        ended = true;
      } else if (type[0] === type[0].toUpperCase() && type !== "PLTE") throw new Error("Native eye PNG has an unsupported critical chunk.");
    }
    offset = end;
  }
  if (!ended) throw new Error("Native eye PNG end marker is missing.");
  const rowBytes = width * channels + 1;
  const expectedBytes = rowBytes * height;
  let decoded: Buffer;
  try { decoded = inflateSync(Buffer.concat(compressed), { maxOutputLength: expectedBytes }); }
  catch { throw new Error("Native eye PNG image data is invalid or exceeds its dimensions."); }
  if (decoded.length !== expectedBytes) throw new Error("Native eye PNG image data does not match its dimensions.");
  for (let row = 0; row < height; row += 1) if (decoded[row * rowBytes] > 4) throw new Error("Native eye PNG row filter is invalid.");
  return { width, height };
}

/** Native ExportRenderTarget has produced valid PNGs with retained suffix bytes.
 * Normalize only the exact validated PNG prefix; a bounded native trailer is
 * classified and hashed with the original file, never interpreted or forwarded.
 * The native artifact is never changed. No engine-internal cause is assumed.
 */
export function inspectNativeEyePngEvidence(bytes: Buffer): Readonly<{
  width: number; height: number; nativeFileBytes: number; pngPrefixBytes: number; trailingZeroPadding: number;
  trailingBytes: number; trailerKind: "none" | "zero" | "nonzero";
  sha256: string; pngPrefixSha256: string; trailerSha256: string;
}> {
  if (bytes.length < 57 || bytes.length > MAX_PNG_BYTES || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) throw new Error("Native eye PNG container signature or byte bound is invalid.");
  let offset = 8;
  let imageEnd: number | undefined;
  let chunks = 0;
  while (offset + 12 <= bytes.length && chunks++ < 4096) {
    const length = bytes.readUInt32BE(offset);
    if (length > bytes.length - offset - 12) throw new Error("Native eye PNG container has a truncated chunk.");
    const type = bytes.toString("ascii", offset + 4, offset + 8);
    offset += 12 + length;
    if (type === "IEND") { imageEnd = offset; break; }
  }
  if (imageEnd === undefined) throw new Error("Native eye PNG container has no bounded end marker.");
  const prefix = bytes.subarray(0, imageEnd);
  const dimensions = inspectNativeEyePng(prefix);
  const trailingBytes = bytes.length - imageEnd;
  if (trailingBytes > MAX_NATIVE_TRAILER_BYTES) throw new Error("Native eye PNG trailer exceeds the discard bound.");
  const trailerKind = trailingBytes === 0 ? "none" : bytes.subarray(imageEnd).every(byte => byte === 0) ? "zero" : "nonzero";
  const trailingZeroPadding = trailerKind === "zero" ? trailingBytes : 0;
  return { ...dimensions, nativeFileBytes: bytes.length, pngPrefixBytes: imageEnd, trailingBytes, trailerKind, trailingZeroPadding,
    sha256: createHash("sha256").update(bytes).digest("hex"), pngPrefixSha256: createHash("sha256").update(prefix).digest("hex"),
    trailerSha256: createHash("sha256").update(bytes.subarray(imageEnd)).digest("hex") };
}

/** Offline artifact inspection, deliberately separate from request freshness.
 * It retains all immutable-file/path/container checks and supplies no receipt,
 * sequence, request revision or captured-at time suitable for a live frame.
 */
export async function inspectArchivedNativeEyePng(filePath: string) {
  const absolute = resolve(filePath);
  const directory = dirname(absolute);
  const fileName = basename(absolute);
  if (!isAbsolute(filePath) || !/^\d+-\d+$/.test(basename(directory)) || basename(directory).length > 64
    || (!/^(?:eye-frame-[a-f0-9]{32}|eye-(?:camera|iris)-[a-f0-9]{32}-(?:baseline|changed|restored))\.png$/.test(fileName)
      && ![...PRIVATE_EYE_PHASES, ...PRIVATE_EYE_DIAGNOSTICS].some(phase => new RegExp(`^eye-private-[a-f0-9]{32}-${phase}\\.png$`).test(fileName)))) throw new Error("Archived eye evidence requires an exact native export filename and boot directory.");
  const file = await readImmutablePng(directory, fileName, undefined, open);
  return { purpose: "historical-native-eye-png-evidence" as const, fileName, ...inspectNativeEyePngEvidence(file.bytes),
    fileModifiedAtMs: file.modifiedAtMs, capturedAtMs: null, previewVerified: false, liveFrameAccepted: false, exportReceiptVerified: false };
}

function finiteNative(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new Error("Private eye numeric observation is not finite.");
  return value;
}
function privateVector(value: unknown): NativeVector {
  const entry = boundedRecord(value, "private vector", 3);
  const result = { X: finiteNative(entry.X), Y: finiteNative(entry.Y), Z: finiteNative(entry.Z) };
  if (Object.values(result).some(axis => Math.abs(axis) > 1e9)) throw new Error("Private eye position exceeds its bound.");
  return result;
}
function privateClose(actual: number, expected: number): boolean { return Math.abs(actual - expected) <= 0.0001; }
function privateDistance(left: NativeVector, right: NativeVector): number { return Math.hypot(left.X - right.X, left.Y - right.Y, left.Z - right.Z); }
function sameNativeObject(actual: unknown, expected: NativeEyeObjectIdentity): void {
  const object = normalizeNativeObject(actual);
  if (object.address !== expected.address || object.name !== expected.name) throw new Error("Private eye source identity or material changed.");
}

export function normalizeNativePrivateEyeSource(value: unknown): NativePrivateEyeSource {
  const entry = boundedRecord(value, "private source", 8);
  if (![0, 1].includes(entry.form as number) || entry.is_wolf_form !== false || !Array.isArray(entry.eye_materials)
    || entry.eye_materials.length !== 2 || !Array.isArray(entry.eye_bones) || entry.eye_bones.length !== 2) throw new Error("Private eye source form or eye observations are invalid.");
  const bones = entry.eye_bones.map(value => {
    const bone = boundedRecord(value, "eye bone", 2);
    if (!Number.isInteger(bone.index) || (bone.index as number) < 0 || (bone.index as number) >= 2048) throw new Error("Private eye bone index is invalid.");
    return { name: nativeText(bone.name, "eye bone name"), index: bone.index as number };
  });
  if (bones[0].name === bones[1].name || bones[0].index === bones[1].index) throw new Error("Private eye landmarks are not distinct.");
  return { player: normalizeNativeObject(entry.player), world: normalizeNativeObject(entry.world), head: normalizeNativeObject(entry.head),
    asset: normalizeNativeObject(entry.asset), form: entry.form as 0 | 1, is_wolf_form: false,
    eye_materials: entry.eye_materials.map(normalizeNativeObject) as [NativeEyeObjectIdentity, NativeEyeObjectIdentity],
    eye_bones: bones as [{ name: string; index: number }, { name: string; index: number }] };
}

export function validateNativePrivateEyeReceipt(value: unknown, expected: NativePrivateEyeSource, request: PrivateWindow, bootId: string) {
  const entry = boundedRecord(value, "private receipt", 64);
  const v6 = entry.schema === 5;
  const captureCompleted = entry.ok === true || (v6 && entry.ok === false && entry.capture_operation_completed === true);
  if (![3, 4, 5].includes(entry.schema as number) || entry.operation !== "private-preview-roundtrip" || entry.kind !== "native-private-eye-preview-evidence"
    || !captureCompleted || entry.production_capabilities !== "none" || entry.boot_id !== bootId || entry.nonce !== request.nonce
    || entry.width !== 1024 || entry.height !== 1024 || entry.render_target_format !== 3 || entry.capture_source !== 2
    || !privateClose(finiteNative(entry.target_gamma), 2.2) || entry.capture_timestamp_known !== false || entry.frame_verified !== false
    || entry.preview_verified !== false || entry.gameplay_verified !== false || entry.created !== true
    || entry.capture_requests !== 9 || entry.export_invoked !== true
    || [entry.front_restored, entry.target_released, entry.destruction_acknowledged, entry.actor_invalidated, entry.destruction_pending].some(flag => typeof flag !== "boolean")
    || (!v6 && (entry.front_restored !== true || entry.target_released !== true || entry.destruction_acknowledged !== true || entry.actor_invalidated === entry.destruction_pending))
    || entry.form !== expected.form || entry.is_wolf_form !== expected.is_wolf_form || entry.pivot_bone_name !== "Head") throw new Error("Private eye operation, cleanup or display evidence is incomplete or mismatched.");
  let displayConfiguration: Record<string, unknown> | undefined;
  const cleanupErrors: Record<string, string> = {};
  if (v6) {
    displayConfiguration = boundedRecord(entry.display_configuration, "private display configuration", 12);
    const gamma = boundedRecord(displayConfiguration.gamma_after, "native gamma observation", 3);
    const linear = boundedRecord(displayConfiguration.force_linear_after, "native gamma flag observation", 3);
    if (displayConfiguration.requested_gamma !== 2.2 || displayConfiguration.requested_force_linear_gamma !== false
      || displayConfiguration.write_ok !== true || gamma.ok !== true || gamma.type !== "number" || !privateClose(finiteNative(gamma.value), 2.2)
      || linear.ok !== true || !((linear.type === "boolean" && linear.value === false) || (linear.type === "number" && linear.value === 0))) {
      throw new Error("Private display configuration lacks matching native write/readback evidence.");
    }
    for (const key of ["reason", "cleanup_error", "restore_error", "release_error", "source_error"]) {
      if (entry[key] !== undefined) {
        if (typeof entry[key] !== "string" || (entry[key] as string).length > 1024) throw new Error("Private cleanup diagnostic exceeds bounds.");
        cleanupErrors[key] = entry[key] as string;
      }
    }
    if ((entry.actor_invalidated && entry.destruction_pending) || (entry.destruction_pending && !entry.destruction_acknowledged)
      || (entry.ok === true && (!entry.front_restored || !entry.target_released || !entry.destruction_acknowledged
        || entry.actor_invalidated === entry.destruction_pending || Object.keys(cleanupErrors).length))) throw new Error("Private initial cleanup claims are inconsistent.");
  }
  sameNativeObject(entry.player, expected.player);
  sameNativeObject(entry.world, expected.world);
  const actor = normalizeNativeObject(entry.actor), capture = normalizeNativeObject(entry.capture), target = normalizeNativeObject(entry.target);
  if (!actor.name.startsWith("SceneCapture2D ") || !capture.name.startsWith("SceneCaptureComponent2D ")
    || !target.name.startsWith("TextureRenderTarget2D ") || (entry.schema === 3 && target.name.includes("/Game/"))
    || new Set([actor.address, capture.address, target.address]).size !== 3) throw new Error("Private eye resource identities or transient target are invalid.");
  // V5 proves a newly allocated target belongs to this exact native world.
  // World-owned transient targets may legitimately have a /Game/ object path.
  // Frozen V4 has no such receipt fields; retain its separate evidence rules.
  let targetOuter: NativeEyeObjectIdentity | undefined;
  if (entry.schema === 4 || v6) {
    targetOuter = normalizeNativeObject(entry.target_outer);
    sameNativeObject(targetOuter, expected.world);
    if (entry.target_new_address !== true || entry.target_owned !== true || entry.spawn_finish_attempted !== true
      || entry.spawn_finished !== true) throw new Error("Private eye new-resource ownership or spawn completion is unproved.");
  }
  const forbidden = [expected.player, expected.world, expected.head, expected.asset, ...expected.eye_materials].map(object => object.address);
  if ([actor, capture, target].some(object => forbidden.includes(object.address))) throw new Error("Private eye resource aliases a source object.");
  if (!Array.isArray(entry.source_meshes) || entry.source_meshes.length < 2 || entry.source_meshes.length > 5) throw new Error("Private eye source mesh list is invalid.");
  const sourceFields = new Set<string>();
  const sourceMeshes = entry.source_meshes.map(value => {
    const source = boundedRecord(value, "source mesh", 4);
    const field = nativeText(source.field, "source field");
    if (!["HeadMesh", "HairMesh", "EyebrowMeshComponent", "BeardMeshComponent", "TorsoMesh"].includes(field) || sourceFields.has(field)
      || !Array.isArray(source.materials) || source.materials.length < 1 || source.materials.length > 16) throw new Error("Private eye source mesh fields or bindings are invalid.");
    sourceFields.add(field);
    const mesh = normalizeNativeObject(source.mesh), asset = normalizeNativeObject(source.asset), materials = source.materials.map(normalizeNativeObject);
    if (!/^(?:SkeletalMeshComponent|SkeletalMeshComponentBudgeted) /.test(mesh.name) || !asset.name.startsWith("SkeletalMesh ")
      || [mesh, asset, ...materials].some(object => [actor.address, capture.address, target.address].includes(object.address))) throw new Error("Private eye source mesh aliases a private resource or has the wrong class.");
    if (field === "HeadMesh") {
      sameNativeObject(mesh, expected.head); sameNativeObject(asset, expected.asset);
      sameNativeObject(materials[3], expected.eye_materials[0]); sameNativeObject(materials[4], expected.eye_materials[1]);
    }
    return { field, mesh, asset, materials };
  });
  if (!sourceFields.has("HeadMesh") || !sourceFields.has("TorsoMesh")) throw new Error("Private eye head and torso observations are required.");
  const eyePair = boundedRecord(entry.eye_pair, "eye pair", 2);
  const eyes = [eyePair.left, eyePair.right].map((value, index) => {
    const bone = boundedRecord(value, "eye endpoint", 3);
    if (bone.name !== expected.eye_bones[index].name || bone.index !== expected.eye_bones[index].index) throw new Error("Private eye landmark identity changed.");
    return privateVector(bone.location);
  });
  const center = privateVector(entry.head_center), radius = finiteNative(entry.head_radius), eyeDistance = finiteNative(entry.eye_distance);
  if (radius < 2 || radius > 200 || eyeDistance < 0.5 || eyeDistance > 25 || !privateClose(privateDistance(eyes[0], eyes[1]), eyeDistance)) throw new Error("Private eye native bounds or eye spacing are invalid.");
  const profileValues = boundedRecord(entry.framing_profiles, "framing profiles", 2);
  const profiles = (["head-and-shoulders", "eyes-close-up"] as const).map((name, index) => {
    const profile = boundedRecord(profileValues[name], "framing profile", 7);
    const pivot = privateVector(profile.pivot);
    const expectedPivot = index === 0 ? { X: center.X, Y: center.Y, Z: center.Z - radius * 0.55 }
      : { X: (eyes[0].X + eyes[1].X) / 2, Y: (eyes[0].Y + eyes[1].Y) / 2, Z: (eyes[0].Z + eyes[1].Z) / 2 + 100000 };
    const fov = index === 0 ? 30 : 20;
    const clearance = radius + privateDistance(pivot, center) + 1 + Math.max(1, radius * 0.05);
    const initial = Math.max(clearance * 1.15, (index === 0 ? radius * 1.65 : eyeDistance * 1.1) / Math.tan(fov * Math.PI / 360));
    const minimum = Math.max(clearance, initial * 0.78), maximum = initial * 1.35;
    if (privateDistance(pivot, expectedPivot) > 0.0001 || profile.field_of_view !== fov || profile.near_clip !== 1 || initial > 5000
      || !privateClose(finiteNative(profile.safe_distance), clearance) || !privateClose(finiteNative(profile.default_distance), initial)
      || !privateClose(finiteNative(profile.minimum_distance), minimum) || !privateClose(finiteNative(profile.maximum_distance), maximum)) throw new Error("Private eye camera bounds do not match native geometry.");
    return { name, pivot, fov, clearance, initial, minimum, maximum };
  });
  if (!Array.isArray(entry.frames) || entry.frames.length !== 9) throw new Error("All nine private eye phases are required.");
  let completed = request.issuedAtMs;
  let forward: NativeVector | undefined;
  const frames = entry.frames.map((value, index) => {
    const frame = boundedRecord(value, "private frame", 16), phase = PRIVATE_EYE_PHASES[index];
    const profile = profiles[[3, 6, 7].includes(index) ? 1 : 0];
    const zoom = [4, 6].includes(index) ? "minimum" : [5, 7].includes(index) ? "maximum" : "default";
    const yaw = index === 1 ? -69 : index === 2 ? 69 : 0;
    const distance = zoom === "minimum" ? profile.maximum : zoom === "maximum" ? profile.minimum : profile.initial;
    const pivot = privateVector(frame.pivot), location = privateVector(frame.camera_location), rotation = boundedRecord(frame.camera_rotation, "private rotation", 3);
    const actualRotation = { pitch: finiteNative(rotation.pitch), yaw: finiteNative(rotation.Yaw), roll: finiteNative(rotation.Roll) };
    const started = finiteNative(frame.export_started_at_epoch_ms), ended = finiteNative(frame.export_completed_at_epoch_ms);
    if (frame.phase !== phase || frame.file_name !== `eye-private-${request.nonce}-${phase}.png` || frame.framing !== profile.name
      || frame.zoom !== zoom || frame.yaw_degrees !== yaw || frame.field_of_view !== profile.fov || frame.near_clip !== 1
      || !privateClose(finiteNative(frame.camera_distance), distance) || privateDistance(pivot, profile.pivot) > 0.0001
      || !Number.isSafeInteger(started) || !Number.isSafeInteger(ended) || started < completed || ended < started || ended > request.expiresAtMs) throw new Error("Private eye phase, camera, filename or export interval differs from its request.");
    completed = ended;
    if (index === 0) {
      forward = { X: (location.X - pivot.X) / distance, Y: (location.Y - pivot.Y) / distance, Z: 0 };
      if (!privateClose(Math.hypot(forward.X, forward.Y), 1)) throw new Error("Private front camera has an invalid horizontal facing.");
    }
    const radians = yaw * Math.PI / 180;
    const expectedLocation = { X: pivot.X + (forward!.X * Math.cos(radians) - forward!.Y * Math.sin(radians)) * distance,
      Y: pivot.Y + (forward!.X * Math.sin(radians) + forward!.Y * Math.cos(radians)) * distance, Z: pivot.Z };
    const expectedRotation = { pitch: 0, yaw: Math.atan2(pivot.Y - location.Y, pivot.X - location.X) * 180 / Math.PI, roll: 0 };
    if (privateDistance(location, expectedLocation) > 0.0001 || !rotationsMatch(actualRotation, expectedRotation)) throw new Error("Private eye native camera readback does not match its orbit or look-at direction.");
    return { phase: phase as PrivateEyePhase, fileName: frame.file_name as string, framing: profile.name, yawDegrees: yaw, zoom,
      cameraLocation: location, cameraRotation: actualRotation, distance, startedAtMs: started, completedAtMs: ended };
  });
  return { schema: entry.schema as 3 | 4 | 5, operation: "private-preview-roundtrip" as const, bootId, nonce: request.nonce,
    actor, capture, target, targetOuter, sources: sourceMeshes, frames, actorInvalidated: entry.actor_invalidated,
    destructionPending: entry.destruction_pending, destructionAcknowledged: entry.destruction_acknowledged,
    targetReleased: entry.target_released, frontRestored: entry.front_restored, initialOperationOk: entry.ok,
    captureOperationCompleted: true, displayConfiguration, cleanupErrors };
}

export function createNativePrivateEyeEvidenceConsumer(options: Readonly<{
  sessionDirectory: string; bootId: string; expectedSource: NativePrivateEyeSource; now?: () => number;
}>) {
  const directory = resolve(options.sessionDirectory), bootId = options.bootId;
  if (!isAbsolute(options.sessionDirectory) || !/^\d+-\d+$/.test(bootId) || bootId.length > 64 || basename(directory) !== bootId) throw new Error("Private eye evidence requires its exact absolute boot directory.");
  const expected = normalizeNativePrivateEyeSource(options.expectedSource), now = options.now ?? Date.now;
  const consumed = new Set<string>();
  let busy = false;
  return { async consume(input: PrivateWindow, value: unknown, mode: "fresh" | "historical" = "fresh") {
    const request = { ...input };
    if (busy || consumed.has(request.nonce) || consumed.size >= 2) throw new Error("Private eye evidence is busy or its nonce budget is consumed.");
    if (!NONCE_PATTERN.test(request.nonce) || request.intent !== "eye-private-preview-roundtrip"
      || !Number.isSafeInteger(request.issuedAtMs) || !Number.isSafeInteger(request.expiresAtMs) || request.issuedAtMs <= 0
      || request.expiresAtMs <= request.issuedAtMs || request.expiresAtMs - request.issuedAtMs > 120000
      || !["fresh", "historical"].includes(mode) || (mode === "fresh" && (now() < request.issuedAtMs || now() > request.expiresAtMs))) throw new Error("Private eye attestation window is invalid, stale or future-dated.");
    busy = true;
    try {
      const receipt = validateNativePrivateEyeReceipt(value, expected, request, bootId);
      const frames = [];
      let bytes = 0;
      for (const frame of receipt.frames) {
        const file = await readImmutablePng(directory, frame.fileName, mode === "fresh" ? request : undefined, open);
        const metadata = inspectNativeEyePngEvidence(file.bytes);
        bytes += metadata.nativeFileBytes;
        if (bytes > 32 * 1024 * 1024 || metadata.width !== 1024 || metadata.height !== 1024
          || file.modifiedAtMs < frame.startedAtMs || file.modifiedAtMs > frame.completedAtMs + 999
          || (mode === "fresh" && (frame.completedAtMs > now() || now() > request.expiresAtMs))) throw new Error("Private eye PNG dimensions, write interval, aggregate budget or fresh lease validation failed.");
        frames.push({ ...frame, ...metadata, fileModifiedAtMs: file.modifiedAtMs, pngBytes: new Uint8Array(file.bytes.subarray(0, metadata.pngPrefixBytes)).buffer });
      }
      consumed.add(request.nonce);
      return { purpose: mode === "fresh" ? "attested-private-eye-export-evidence" : "historical-private-eye-export-evidence",
        leaseStatus: mode, receipt, frames, capturedAtMs: null, previewVerified: false, liveFrameAccepted: false, readySession: false };
    } finally { busy = false; }
  } };
}

function irisColor(value: unknown): Exclude<IrisValue, number> {
  const entry = boundedRecord(value, "iris vector4", 4);
  return { R: finiteNative(entry.R), G: finiteNative(entry.G), B: finiteNative(entry.B), A: finiteNative(entry.A) };
}
function irisEqual(left: IrisValue, right: IrisValue): boolean {
  return typeof left === "number" && typeof right === "number" ? Math.abs(left - right) <= 0.000001
    : typeof left === "object" && typeof right === "object" && (["R", "G", "B", "A"] as const).every(key => Math.abs(left[key] - right[key]) <= 0.000001);
}
function irisParameters(value: unknown, observed: boolean): Record<string, IrisValue> {
  const parameters = boundedRecord(value, "iris parameters", 11);
  if (Object.keys(parameters).length !== 11) throw new Error("All eleven native iris parameters are required per eye.");
  return Object.fromEntries([...HUMAN_IRIS_SCALARS, ...HUMAN_IRIS_VECTORS].map(name => {
    const kind = HUMAN_IRIS_VECTORS.some(vector => vector === name) ? "vector" : "scalar";
    const parameter = observed ? boundedRecord(parameters[name], "iris parameter", 4) : undefined;
    if (parameter && (parameter.kind !== kind || parameter.association !== 2 || parameter.index !== -1)) throw new Error("Iris parameter kind or native identity changed.");
    const original = parameter ? parameter.value : parameters[name];
    return [name, kind === "vector" ? irisColor(original) : finiteNative(original)];
  }));
}
export function normalizeNativeHumanIrisSource(value: NativeHumanIrisSource): NativeHumanIrisSource {
  const source = normalizeNativePrivateEyeSource(value.source);
  if (source.form !== 0 || source.asset.name !== "SkeletalMesh /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/SK_HMA_Coen_Head_A.SK_HMA_Coen_Head_A"
    || !Array.isArray(value.parameters) || value.parameters.length !== 2) throw new Error("Independent human iris source is not the exact supported head.");
  for (const [index, side] of ["L", "R"].entries()) {
    if (source.eye_materials[index].name !== `MaterialInstanceConstant /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/Materials/MI_Coen_Eyeball_${side}.MI_Coen_Eyeball_${side}`) throw new Error("Independent human iris original material differs.");
  }
  return { source, parameters: [irisParameters(value.parameters[0], false), irisParameters(value.parameters[1], false)] };
}
function irisRotation(value: unknown): NativeRotation {
  const rotation = boundedRecord(value, "iris rotation", 3);
  return { pitch: finiteNative(rotation.pitch), yaw: finiteNative(rotation.Yaw), roll: finiteNative(rotation.Roll) };
}
function irisTransform(value: unknown) {
  const transform = boundedRecord(value, "iris relative transform", 3), quaternion = boundedRecord(transform.Rotation, "iris quaternion", 4);
  return { translation: privateVector(transform.Translation), scale: privateVector(transform.Scale3D),
    rotation: { X: finiteNative(quaternion.X), Y: finiteNative(quaternion.Y), Z: finiteNative(quaternion.Z), W: finiteNative(quaternion.W) } };
}
function irisSameNumbers(left: unknown, right: unknown): boolean {
  if (typeof left === "number" && typeof right === "number") return Math.abs(left - right) <= 0.00001;
  if (typeof left === "boolean" || typeof right === "boolean") return left === right;
  if (!left || !right || typeof left !== "object" || typeof right !== "object") return false;
  const a = left as Record<string, unknown>, b = right as Record<string, unknown>;
  return Object.keys(a).length === Object.keys(b).length && Object.keys(a).every(key => irisSameNumbers(a[key], b[key]));
}
function irisCamera(value: unknown) {
  const entry = boundedRecord(value, "iris camera", 14);
  if (typeof entry.override_near !== "boolean" || typeof entry.every_frame !== "boolean" || typeof entry.on_movement !== "boolean"
    || entry.capture_source !== 9 || entry.primitive_render_mode !== 2) throw new Error("Iris inventory camera flags or capture mode are invalid.");
  const fov = finiteNative(entry.fov), projection = finiteNative(entry.projection), near = finiteNative(entry.near_clip);
  if (fov <= 0 || fov >= 180 || projection !== 0 || Math.abs(near) > 100000) throw new Error("Iris inventory camera projection is invalid.");
  return { location: privateVector(entry.location), rotation: irisRotation(entry.rotation), fov, projection, near,
    overrideNear: entry.override_near, everyFrame: entry.every_frame, onMovement: entry.on_movement };
}
function irisEyes(value: unknown) {
  if (!Array.isArray(value) || value.length !== 2) throw new Error("Two native iris eye readbacks are required.");
  return value.map((value, index) => {
    const eye = boundedRecord(value, "iris eye", 4);
    if (eye.slot !== index + 3 || eye.slot_name !== (index === 0 ? "shader_eyeLeft_shader" : "shader_eyeRight_shader")) throw new Error("Iris eye slot topology changed.");
    return { slot: index + 3, material: normalizeNativeObject(eye.material), parameters: irisParameters(eye.parameters, true) };
  });
}

export function validateNativeHumanIrisReceipt(value: unknown, expected: NativeHumanIrisSource, request: IrisWindow, bootId: string) {
  const entry = boundedRecord(value, "human iris receipt", 28), source = expected.source;
  if (entry.schema !== 4 || entry.operation !== "human-iris-pair-roundtrip" || entry.kind !== "native-human-iris-pair-roundtrip-evidence"
    || entry.ok !== true || entry.boot_id !== bootId || entry.nonce !== request.nonce || entry.production_capabilities !== "none"
    || entry.mutation_attempted !== true || entry.private_materials_created !== true || entry.scalar_swap_readback_verified !== true
    || entry.original_bindings_restored !== true || entry.original_values_verified !== true || entry.visual_effect_verified !== false
    || entry.gameplay_verified !== false || entry.applied_in_game !== false || !Array.isArray(entry.captures) || entry.captures.length !== 3
    || !Array.isArray(entry.failed_captures) || entry.failed_captures.length !== 0 || !Array.isArray(entry.cleanup_failures) || entry.cleanup_failures.length !== 0
    || JSON.stringify(entry.scalar_parameters_verified) !== JSON.stringify(HUMAN_IRIS_SCALARS)
    || JSON.stringify(entry.vector_parameters_verified) !== JSON.stringify(HUMAN_IRIS_VECTORS)) throw new Error("Human iris success, restoration or exact parameter evidence is incomplete.");
  const baselineId = `${bootId}:${request.nonce}`;
  let completed = request.issuedAtMs;
  let initialInventory: { doll: NativeEyeObjectIdentity; capture: NativeEyeObjectIdentity; head: NativeEyeObjectIdentity; target: NativeEyeObjectIdentity; originalEyes: NativeEyeObjectIdentity[] } | undefined;
  let changedParameterCount = 0;
  const frames = entry.captures.map((value, phaseIndex) => {
    const phase = (["baseline", "changed", "restored"] as const)[phaseIndex], changed = phase === "changed";
    const pair = boundedRecord(value, "iris phase", 3), sample = boundedRecord(pair.native_readback, "iris independent sample", 11);
    const frame = boundedRecord(pair.capture_receipt, "iris capture receipt", 44);
    if (pair.phase !== phase || sample.phase !== phase || sample.nonce !== request.nonce || sample.boot_id !== bootId || sample.baseline_id !== baselineId
      || sample.form !== 0 || sample.is_wolf_form !== false || frame.phase !== phase || frame.ok !== true || frame.nonce !== request.nonce
      || frame.boot_id !== bootId || frame.baseline_id !== baselineId || frame.kind !== "native-inventory-iris-capture-evidence"
      || frame.file_name !== `eye-iris-${request.nonce}-${phase}.png` || frame.width !== 2048 || frame.height !== 2048 || frame.render_target_format !== 2 || frame.capture_source !== 9
      || frame.inventory_bindings_restored !== true || frame.inventory_camera_restored !== true || frame.inventory_refresh_requested !== true || frame.export_invoked !== true
      || frame.capture_timestamp_known !== false || frame.frame_verified !== false || frame.preview_verified !== false || frame.gameplay_verified !== false) throw new Error("Human iris phase or capture identity does not match its operation.");
    for (const key of ["player", "world", "head", "asset"] as const) sameNativeObject(sample[key], source[key]);
    sameNativeObject(frame.player, source.player); sameNativeObject(frame.world, source.world);
    sameNativeObject(frame.player_head, source.head); sameNativeObject(frame.player_asset, source.asset);
    const eyes = irisEyes(sample.eyes), borrowedEyes = irisEyes(frame.sampled_eyes);
    if (eyes[0].material.address === eyes[1].material.address) throw new Error("Left and right live iris materials are not distinct.");
    for (const [index, eye] of eyes.entries()) {
      if (changed) {
        const path = source.head.name.slice(source.head.name.indexOf(" ") + 1);
        const scopedName = index === 0 ? "IrisColor1_U" : "IrisColor2_U";
        if (eye.material.name !== `MaterialInstanceDynamic ${path}.${scopedName}` || source.eye_materials.some(original => original.address === eye.material.address)) throw new Error("Changed iris binding is not its distinct scoped dynamic material.");
      } else sameNativeObject(eye.material, source.eye_materials[index]);
      sameNativeObject(borrowedEyes[index].material, eye.material);
      for (const name of [...HUMAN_IRIS_SCALARS, ...HUMAN_IRIS_VECTORS]) {
        const desired = expected.parameters[index][changed ? (IRIS_SWAPS[name] ?? name) : name];
        if (!irisEqual(eye.parameters[name], desired) || !irisEqual(borrowedEyes[index].parameters[name], eye.parameters[name])) throw new Error("Native iris getter or borrowed values differ from the exact observed scalar swap.");
        if (changed && !irisEqual(eye.parameters[name], expected.parameters[index][name])) changedParameterCount++;
      }
    }
    const inventory = { doll: normalizeNativeObject(frame.doll), capture: normalizeNativeObject(frame.capture), head: normalizeNativeObject(frame.preview_head), target: normalizeNativeObject(frame.target) };
    if (!inventory.capture.name.startsWith("SceneCaptureComponent2D ") || !/^(?:SkeletalMeshComponent|SkeletalMeshComponentBudgeted) /.test(inventory.head.name)
      || inventory.target.name !== "TextureRenderTarget2D /Game/_Dawnwalker/UI/_Unified/GameHub/Inventory/Doll/RT_RenderDoll.RT_RenderDoll"
      || new Set(Object.values(inventory).map(object => object.address)).size !== 4 || Object.values(inventory).some(object => [source.player.address, source.head.address].includes(object.address))) throw new Error("Inventory iris resource identities alias gameplay objects or have the wrong capture type.");
    if (!Array.isArray(frame.preview_eye_bindings) || frame.preview_eye_bindings.length !== 2) throw new Error("Original and restored inventory eye bindings are required.");
    const originalEyes = frame.preview_eye_bindings.map((value, index) => {
      const binding = boundedRecord(value, "inventory iris binding", 4), original = normalizeNativeObject(binding.original);
      if (binding.slot !== index + 3) throw new Error("Inventory iris restoration slot changed.");
      sameNativeObject(binding.borrowed, eyes[index].material); sameNativeObject(binding.restored, original);
      if (initialInventory) sameNativeObject(original, initialInventory.originalEyes[index]);
      return original;
    });
    if (initialInventory) for (const key of ["doll", "capture", "head", "target"] as const) sameNativeObject(inventory[key], initialInventory[key]);
    else initialInventory = { ...inventory, originalEyes };
    const before = irisCamera(frame.camera_before), after = irisCamera(frame.camera_after);
    const afterRecord = boundedRecord(frame.camera_after, "restored iris camera", 14);
    if (!irisSameNumbers(before.location, after.location) || before.fov !== after.fov || before.projection !== after.projection || before.near !== after.near
      || before.overrideNear !== after.overrideNear || before.everyFrame !== after.everyFrame || before.onMovement !== after.onMovement) throw new Error("Inventory iris camera did not restore its original settings.");
    if (!rotationsMatch(before.rotation, after.rotation) || !irisSameNumbers(irisTransform(frame.camera_relative_before), irisTransform(afterRecord.relative_transform))) throw new Error("Inventory iris camera transform did not restore.");
    const view = boundedRecord(frame.view, "iris close-up view", 10), center = privateVector(frame.head_center), radius = finiteNative(frame.head_radius);
    const landmarks = boundedRecord(frame.eye_pair, "inventory iris eye pair", 2);
    const endpoints = [landmarks.left, landmarks.right].map((value, index) => {
      const bone = boundedRecord(value, "inventory iris bone", 3);
      if (bone.name !== source.eye_bones[index].name || bone.index !== source.eye_bones[index].index) throw new Error("Inventory iris landmark differs from the actual head.");
      return privateVector(bone.location);
    });
    const spacing = privateDistance(endpoints[0], endpoints[1]);
    const pivot = { X: (endpoints[0].X + endpoints[1].X) / 2, Y: (endpoints[0].Y + endpoints[1].Y) / 2, Z: (endpoints[0].Z + endpoints[1].Z) / 2 };
    const clearance = radius + privateDistance(pivot, center) + 1 + Math.max(1, radius * 0.05);
    const distance = Math.max(clearance * 1.15, spacing * 1.1 / Math.tan(20 * Math.PI / 360));
    const location = privateVector(view.location), rotation = irisRotation(frame.camera_rotation);
    if (radius < 2 || radius > 200 || spacing < 0.5 || spacing > 25 || endpoints.some(eye => privateDistance(eye, center) > radius * 2.5)
      || view.phase !== "eyes-closeup" || view.framing !== "eyes-close-up" || view.yaw_degrees !== 0 || view.zoom !== "default" || view.field_of_view !== 20 || view.near_clip !== 1
      || distance > 5000 || !privateClose(finiteNative(view.distance), distance) || privateDistance(privateVector(view.pivot), pivot) > 0.0001
      || !privateClose(privateDistance(location, pivot), distance) || !privateClose(location.Z, pivot.Z)
      || !rotationsMatch(rotation, { pitch: 0, yaw: Math.atan2(pivot.Y - location.Y, pivot.X - location.X) * 180 / Math.PI, roll: 0 })) throw new Error("Native iris close-up geometry or camera readback is invalid.");
    const started = finiteNative(frame.export_started_at_epoch_ms), ended = finiteNative(frame.export_completed_at_epoch_ms);
    if (!Number.isSafeInteger(started) || !Number.isSafeInteger(ended) || started < completed || ended < started || ended > request.expiresAtMs) throw new Error("Native iris export interval is outside its attested phase order.");
    completed = ended;
    return { phase, fileName: frame.file_name as string, startedAtMs: started, completedAtMs: ended, eyes, inventory, originalEyes,
      cameraBefore: before, cameraAfter: after, cameraLocation: location, cameraRotation: rotation, distance };
  });
  return { schema: 4 as const, bootId, nonce: request.nonce, baselineId, frames, changedParameterCount,
    originalValuesVerified: true, originalBindingsRestored: true, inventoryBindingsRestored: true, inventoryCameraRestored: true };
}

export function createNativeHumanIrisEvidenceConsumer(options: Readonly<{ sessionDirectory: string; bootId: string; expectedSource: NativeHumanIrisSource; now?: () => number }>) {
  const directory = resolve(options.sessionDirectory), bootId = options.bootId, now = options.now ?? Date.now;
  if (!isAbsolute(options.sessionDirectory) || !/^\d+-\d+$/.test(bootId) || bootId.length > 64 || basename(directory) !== bootId) throw new Error("Human iris evidence requires its exact absolute boot directory.");
  const expected = normalizeNativeHumanIrisSource(options.expectedSource);
  let consumed = false, busy = false;
  return { async consume(input: IrisWindow, value: unknown, mode: "fresh" | "historical" = "fresh") {
    const request = { ...input };
    if (busy || consumed) throw new Error("Human iris evidence is busy or its one-request budget is consumed.");
    if (!NONCE_PATTERN.test(request.nonce) || request.intent !== "human-iris-pair-roundtrip" || !Number.isSafeInteger(request.issuedAtMs) || !Number.isSafeInteger(request.expiresAtMs)
      || request.issuedAtMs <= 0 || request.expiresAtMs <= request.issuedAtMs || request.expiresAtMs - request.issuedAtMs > 120000
      || !["fresh", "historical"].includes(mode) || (mode === "fresh" && (now() < request.issuedAtMs || now() > request.expiresAtMs))) throw new Error("Human iris attestation is invalid, stale or future-dated.");
    busy = true;
    try {
      const receipt = validateNativeHumanIrisReceipt(value, expected, request, bootId), frames = [];
      let bytes = 0;
      for (const frame of receipt.frames) {
        const file = await readImmutablePng(directory, frame.fileName, mode === "fresh" ? request : undefined, open), metadata = inspectNativeEyePngEvidence(file.bytes);
        bytes += metadata.nativeFileBytes;
        if (bytes > 32 * 1024 * 1024 || metadata.width !== 2048 || metadata.height !== 2048 || file.modifiedAtMs < frame.startedAtMs || file.modifiedAtMs > frame.completedAtMs + 999
          || (mode === "fresh" && (frame.completedAtMs > now() || now() > request.expiresAtMs))) throw new Error("Human iris frame dimensions, original interval or fresh lease validation failed.");
        frames.push({ ...frame, ...metadata, fileModifiedAtMs: file.modifiedAtMs, pngBytes: new Uint8Array(file.bytes.subarray(0, metadata.pngPrefixBytes)).buffer });
      }
      consumed = true;
      return { purpose: mode === "fresh" ? "attested-human-iris-export-evidence" : "historical-human-iris-export-evidence", leaseStatus: mode, receipt, frames,
        capturedAtMs: null, previewVerified: false, liveFrameAccepted: false, readySession: false, visualEffectVerified: false, appliedInGame: false };
    } finally { busy = false; }
  } };
}

/**
 * One-frame export evidence only. File timestamps are not render-completion
 * timestamps, and this result intentionally cannot satisfy EyePreviewFrame.
 * A production stream must additionally prove native identity, actual view,
 * corresponding material readbacks, sequence and both requested revisions.
 */
export function createNativeEyePngEvidenceConsumer(options: EyeFrameEvidenceOptions, fileOperations: Readonly<{ openFile: typeof open }> = { openFile: open }) {
  const directory = resolve(options.sessionDirectory);
  if (!isAbsolute(options.sessionDirectory)) throw new Error("Eye evidence requires an absolute, fixed session directory.");
  if (!/^\d+-\d+$/.test(options.bootId) || options.bootId.length > 64 || basename(directory) !== options.bootId) throw new Error("Native eye evidence directory must match its exact driver boot.");
  const expectedIdentity = normalizeNativeEyeExportIdentity(options.expectedIdentity);
  const bootId = options.bootId;
  const now = options.now ?? Date.now;
  const consumed = new Set<string>();
  const consumedNonces = new Map<string, string>();
  let busy = false;
  return {
    async consume(request: NativeEyeExportWindow, nativeReceipt: unknown, phase: "single" | NativeEyeCameraPhase = "single"): Promise<NativeEyePngEvidence> {
      // Preserve the coordinator's exact request through asynchronous file reads.
      const window = { nonce: request.nonce, intent: request.intent, issuedAtMs: request.issuedAtMs, expiresAtMs: request.expiresAtMs };
      const currentTime = now();
      const key = `${window.nonce}:${phase}`;
      if (busy || (consumedNonces.size >= 8 && !consumedNonces.has(window.nonce)) || consumed.has(key)) throw new Error("Eye export evidence is busy or its nonce budget has been consumed.");
      if (!NONCE_PATTERN.test(window.nonce) || !Number.isSafeInteger(window.issuedAtMs) || !Number.isSafeInteger(window.expiresAtMs)
        || window.expiresAtMs <= window.issuedAtMs || window.expiresAtMs - window.issuedAtMs > 120000
        || currentTime < window.issuedAtMs || currentTime > window.expiresAtMs
        || !["single", "baseline", "changed", "restored"].includes(phase)
        || window.intent !== (phase === "single" ? "eye-readback-export" : "eye-preview-camera-roundtrip")) throw new Error("Eye export nonce, intent or time window is invalid, stale, or future-dated.");
      busy = true;
      try {
        const single = phase === "single" ? verifiedReceipt(nativeReceipt, window, bootId, expectedIdentity, currentTime) : undefined;
        const camera = phase !== "single" ? verifiedCameraReceipt(nativeReceipt, phase, window, bootId, expectedIdentity, currentTime) : undefined;
        const receipt = single ?? camera!.receipt;
        const requestProof = JSON.stringify({ window, evidence: single ? JSON.stringify(single) : camera!.proof });
        if (consumedNonces.has(window.nonce) && consumedNonces.get(window.nonce) !== requestProof) throw new Error("Native eye export request or phase metadata changed after a previous phase was consumed.");
        const fileName = receipt.file_name;
        const file = await readImmutablePng(directory, fileName, window, fileOperations.openFile);
        const dimensions = inspectNativeEyePngEvidence(file.bytes);
        // The current producer uses os.time(), so its export interval has one
        // second granularity. This bounds the file write, not render freshness.
        if (file.modifiedAtMs < receipt.export_started_at_epoch_ms || file.modifiedAtMs > receipt.export_completed_at_epoch_ms + 999
          || dimensions.width !== receipt.width || dimensions.height !== receipt.height) throw new Error("Native eye PNG does not match its export receipt dimensions or write interval.");
        if (now() > window.expiresAtMs) throw new Error("Eye export window expired before verification completed.");
        consumed.add(key);
        consumedNonces.set(window.nonce, requestProof);
        return { purpose: "native-eye-export-evidence", previewVerified: false, capturedAtMs: null, nonce: window.nonce,
          fileName, ...dimensions,
          fileModifiedAtMs: file.modifiedAtMs, receipt, pngBytes: new Uint8Array(file.bytes.subarray(0, dimensions.pngPrefixBytes)).buffer };
      } finally { busy = false; }
    },
  };
}
