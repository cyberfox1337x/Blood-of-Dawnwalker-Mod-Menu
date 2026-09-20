import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { constants, type BigIntStats } from "node:fs";
import { lstat, mkdir, open, realpath, rename, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, normalize, resolve } from "node:path";
import { performance } from "node:perf_hooks";
import { assertEyeResponseCorrespondence, encodeEyeNativeRequest, parseEyeNativeResponse, type EyeNativeWireRequest } from "./eyeNativeProtocol.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_native_channel");

// Unactivated QA channel. No import creates files or enables a native/UI session.
const ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-channel";
const EXE = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853";
const COMMAND_BYTES = 32 * 1024, RESPONSE_BYTES = 256 * 1024;
const channels = new Set<string>();
const slots = ["command.tmp", "command.txt", "response.tmp", "response.txt"] as const;
type Slot = typeof slots[number] | "channel.ready";
type DirectoryIdentity = Readonly<{ path: string; canonical: string; status: BigIntStats }>;
type FileSnapshot = Readonly<{ slot: Slot; status: BigIntStats; bytes: Buffer; sha256: string }>;
type WithoutAddress<T> = T extends EyeNativeWireRequest ? Omit<T, "boot_id" | "owner_id" | "request_id" | "command_sequence"> : never;
export type EyeNativeCommand = WithoutAddress<EyeNativeWireRequest>;
export type EyeNativeChannelOptions = Readonly<{
  bootId: string;
  ownerId: string;
  // Explicit isolated fixtures only. Production callers cannot select a root.
  trustedTestRoot?: string;
}>;
export type EyeNativeChannelState = Readonly<{
  status: "open" | "faulted" | "disposed";
  busy: boolean;
  lastSequence: number;
  reason?: string;
}>;

function check(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
function identity(a: BigIntStats, b: BigIntStats): boolean { return a.dev === b.dev && a.ino === b.ino && a.birthtimeNs === b.birthtimeNs; }
function sameFile(a: BigIntStats, b: BigIntStats): boolean {
  return identity(a, b) && a.size === b.size && a.mtimeNs === b.mtimeNs && a.ctimeNs === b.ctimeNs && a.nlink === b.nlink;
}
function pathKey(path: string): string { const value = normalize(path); return process.platform === "win32" ? value.toLowerCase() : value; }
function missing(error: unknown): boolean { return (error as NodeJS.ErrnoException)?.code === "ENOENT"; }
function hash(bytes: Uint8Array): string { return createHash("sha256").update(bytes).digest("hex"); }

function createPathVerifier() {
  // lstat catches links/junctions; native attributes cover other reparse types.
  // Literal paths are data on stdin, never interpolated into shell source.
  const program = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';while($null -ne ($line=[Console]::In.ReadLine())){try{$paths=$line|ConvertFrom-Json;foreach($path in $paths){$item=Get-Item -LiteralPath $path -Force;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'Reparse'}};[Console]::Out.WriteLine('plain')}catch{[Console]::Out.WriteLine('invalid')}}";
  const executable = join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  let child: ChildProcessWithoutNullStreams | undefined, output = "", closed = false;
  let queued = Promise.resolve();
  let pending: { resolve: () => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> } | undefined;
  function stop(reason = "Eye channel path verifier closed.") {
    closed = true;
    if (pending) { clearTimeout(pending.timer); pending.reject(new Error(reason)); pending = undefined; }
    child?.kill();
  }
  function start() {
    if (child) return;
    child = spawn(executable, ["-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(program, "utf16le").toString("base64")], { windowsHide: true, stdio: "pipe" });
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (data: string) => {
      output += data;
      if (output.length > 4096) return stop("Eye channel path verifier response exceeded bounds.");
      const end = output.indexOf("\n");
      if (end < 0) return;
      const line = output.slice(0, end).replace(/\r$/, ""); output = output.slice(end + 1);
      if (!pending || line !== "plain" || output.length) return stop("Eye channel path attributes could not be verified as ordinary paths.");
      const operation = pending; pending = undefined; clearTimeout(operation.timer); operation.resolve();
    });
    child.stderr.on("data", () => stop("Eye channel path verifier reported an error."));
    child.on("error", () => stop("Eye channel path verifier could not start."));
    child.on("exit", () => stop("Eye channel path verifier exited."));
    child.stdin.on("error", () => stop("Eye channel path verification input failed."));
  }
  return {
    verify(paths: readonly string[]): Promise<void> {
      const run = queued.then(async () => {
        check(!closed, "Eye channel path verifier is closed.");
        if (process.platform !== "win32") return;
        start();
        await new Promise<void>((resolveCheck, rejectCheck) => {
          const timer = setTimeout(() => stop("Eye channel path verifier timed out."), 5000);
          pending = { resolve: resolveCheck, reject: rejectCheck, timer };
          child?.stdin.write(JSON.stringify(paths) + "\n");
        });
      });
      queued = run.catch(() => undefined);
      return run;
    },
    close: stop,
  };
}

async function directoryChain(path: string, verify: (paths: readonly string[]) => Promise<void>): Promise<readonly DirectoryIdentity[]> {
  check(isAbsolute(path), "Eye channel directory must be absolute.");
  if (process.platform === "win32") check(/^[a-z]:\\/i.test(path) && !path.startsWith("\\\\"), "Eye channel requires a local drive.");
  const chain: DirectoryIdentity[] = [];
  let current = path;
  while (true) {
    const status = await lstat(current, { bigint: true });
    check(status.isDirectory() && !status.isSymbolicLink(), "Eye channel ancestor is not an ordinary directory.");
    const canonical = await realpath(current);
    // Windows TEMP may use its ordinary 8.3 spelling. Require the same native
    // directory identity and reject reparse attributes, rather than comparing names.
    check(identity(status, await lstat(canonical, { bigint: true })), "Eye channel ancestor resolves outside its fixed identity.");
    chain.push({ path: current, canonical, status });
    const parent = dirname(current);
    if (parent === current) break;
    current = parent;
  }
  await verify(chain.map(entry => entry.path));
  return chain;
}

async function checkChain(chain: readonly DirectoryIdentity[]): Promise<void> {
  for (const entry of chain) {
    const status = await lstat(entry.path, { bigint: true });
    check(status.isDirectory() && !status.isSymbolicLink() && identity(status, entry.status)
      && pathKey(await realpath(entry.path)) === pathKey(entry.canonical), "Eye channel ancestor changed identity.");
  }
}

async function ensureChild(parent: string, name: string, verify: (paths: readonly string[]) => Promise<void>): Promise<string> {
  const chain = await directoryChain(parent, verify), child = join(parent, name);
  try { await mkdir(child); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
  await checkChain(chain);
  await directoryChain(child, verify);
  return child;
}

export async function createEyeNativeChannel(options: EyeNativeChannelOptions) {
  options = Object.freeze({ ...options });
  check(/^\d{1,16}-\d{1,16}$/.test(options.bootId) && /^[a-f0-9]{32}$/.test(options.ownerId), "Invalid eye channel boot or owner identity.");
  const verifier = createPathVerifier();
  async function prepare() {
  let root = resolve(ROOT);
  if (options.trustedTestRoot !== undefined) {
    const testRoot = resolve(options.trustedTestRoot);
    check(isAbsolute(options.trustedTestRoot) && pathKey(dirname(testRoot)) === pathKey(resolve(tmpdir()))
      && /^dawnwalker-eye-channel-test-[a-zA-Z0-9_-]+$/.test(basename(testRoot)), "Trusted eye channel test root must be an isolated named temporary fixture.");
    await directoryChain(testRoot, verifier.verify);
    root = testRoot;
  } else {
    await ensureChild(dirname(root), basename(root), verifier.verify);
  }
  const bootDirectory = await ensureChild(root, options.bootId, verifier.verify);
  const directory = await ensureChild(bootDirectory, options.ownerId, verifier.verify);
  const chain = await directoryChain(directory, verifier.verify), key = pathKey(directory);
  check(!channels.has(key), "This eye channel owner already has an active host instance.");
  channels.add(key);
  return { directory, chain, key };
  }
  let prepared;
  try { prepared = await prepare(); } catch (error) { verifier.close(); throw error; }
  const { directory, chain, key } = prepared;
  let state: EyeNativeChannelState = { status: "open", busy: false, lastSequence: 0 };
  let ready: FileSnapshot | undefined;

  function active(): void { check(state.status === "open", state.reason || "Eye channel is disposed."); }
  function fault(error: unknown): Error {
    const reason = error instanceof Error ? error.message : "Eye channel request did not complete.";
    state = { ...state, status: state.status === "disposed" ? "disposed" : "faulted", busy: false, reason };
    verifier.close();
    return new Error(reason);
  }
  async function exists(slot: Slot): Promise<boolean> {
    try { await lstat(join(directory, slot)); return true; } catch (error) { if (missing(error)) return false; throw error; }
  }
  async function absent(slot: Slot): Promise<void> { check(!(await exists(slot)), `Eye channel slot is already occupied: ${slot}`); }
  async function read(slot: Slot, limit: number): Promise<FileSnapshot> {
    await checkChain(chain);
    const path = join(directory, slot), before = await lstat(path, { bigint: true });
    check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1n && before.size > 0n && before.size <= BigInt(limit), `Eye channel ${slot} must be a bounded ordinary single-link file.`);
    check(pathKey(await realpath(path)) === pathKey(join(chain[0].canonical, slot)), "Eye channel file resolves outside its fixed directory.");
    await verifier.verify([...chain.map(entry => entry.path), path]);
    const handle = await open(path, constants.O_RDONLY | (process.platform === "win32" ? 0 : constants.O_NOFOLLOW));
    try {
      const opened = await handle.stat({ bigint: true });
      check(sameFile(before, opened), "Eye channel file changed while opening.");
      const bytes = Buffer.alloc(Number(opened.size));
      let offset = 0;
      while (offset < bytes.length) {
        const result = await handle.read(bytes, offset, bytes.length - offset, offset);
        check(result.bytesRead > 0, "Eye channel file was truncated during read.");
        offset += result.bytesRead;
      }
      check(sameFile(opened, await handle.stat({ bigint: true })) && sameFile(opened, await lstat(path, { bigint: true })), "Eye channel file changed during read.");
      await checkChain(chain);
      await verifier.verify([...chain.map(entry => entry.path), path]);
      check(sameFile(opened, await lstat(path, { bigint: true })), "Eye channel file changed during final validation.");
      return { slot, status: opened, bytes, sha256: hash(bytes) };
    } finally { await handle.close(); }
  }
  async function unchanged(snapshot: FileSnapshot, limit: number): Promise<void> {
    const current = await read(snapshot.slot, limit);
    check(sameFile(snapshot.status, current.status) && current.sha256 === snapshot.sha256, `Eye channel ${snapshot.slot} changed after validation.`);
  }
  async function remove(snapshot: FileSnapshot, limit: number): Promise<void> {
    active();
    check(snapshot.slot === "command.txt" || snapshot.slot === "response.txt", "Only completed command/response slots may be removed.");
    await unchanged(snapshot, limit);
    await checkChain(chain);
    check(sameFile(snapshot.status, await lstat(join(directory, snapshot.slot), { bigint: true })), "Eye channel slot changed before removal.");
    await unlink(join(directory, snapshot.slot));
  }
  async function poll(slot: Slot, deadline: number): Promise<void> {
    while (!(await exists(slot))) {
      active();
      check(performance.now() < deadline, `Eye channel timed out waiting for ${slot}; files were preserved and no operation was replayed.`);
      await new Promise(resolveWait => setTimeout(resolveWait, 25));
    }
    active();
    check(performance.now() < deadline, `Eye channel ${slot} arrived after its request timeout.`);
  }
  function timeout(value: number): number { check(Number.isFinite(value) && value >= 50 && value <= 30000, "Eye channel timeout must be between 50 and 30000 ms."); return value; }
  async function inspectReady(): Promise<FileSnapshot> {
    const snapshot = await read("channel.ready", 2048);
    const expected = { wire_version: "1", boot_id: options.bootId, owner_id: options.ownerId, build_id: "25129649",
      executable_sha256: EXE, transport: "eye-session-prototype", production_ready: "false" };
    const text = new TextDecoder("utf-8", { fatal: true }).decode(snapshot.bytes);
    check(text.endsWith("\n") && !text.includes("\r"), "Malformed eye channel transport metadata.");
    const values: Record<string, string> = Object.create(null) as Record<string, string>;
    for (const line of text.slice(0, -1).split("\n")) {
      const at = line.indexOf("="), field = line.slice(0, at);
      check(at > 0 && Object.hasOwn(expected, field) && !Object.hasOwn(values, field), "Unknown or duplicate eye channel metadata field.");
      values[field] = line.slice(at + 1);
    }
    check(Object.entries(expected).every(([field, value]) => values[field] === value), "Eye channel transport identity differs from the expected build/owner.");
    if (ready) check(sameFile(ready.status, snapshot.status) && ready.sha256 === snapshot.sha256, "Eye channel transport metadata changed during this host connection.");
    return snapshot;
  }
  try { for (const slot of slots) await absent(slot); } catch (error) { channels.delete(key); verifier.close(); throw error; }

  return {
    directory,
    getState: (): EyeNativeChannelState => ({ ...state }),
    async waitForTransport(timeoutMs = 10000) {
      active(); check(!state.busy, "Eye channel already has an outstanding request.");
      const deadline = performance.now() + timeout(timeoutMs);
      state = { ...state, busy: true };
      try {
        await poll("channel.ready", deadline);
        ready = await inspectReady();
        check(performance.now() <= deadline, "Eye channel transport validation exceeded its timeout.");
        return { transport: "eye-session-prototype" as const, bootId: options.bootId, ownerId: options.ownerId, productionReady: false as const, sha256: ready.sha256 };
      } catch (error) { throw fault(error); }
      finally { state = { ...state, busy: false }; if (state.status === "disposed") channels.delete(key); }
    },
    async send(command: EyeNativeCommand, timeoutMs = 10000) {
      active(); check(!state.busy, "Eye channel already has an outstanding request.");
      check(ready, "Eye channel transport metadata must be verified before sending.");
      const duration = timeout(timeoutMs), sequence = state.lastSequence + 1;
      check(!["boot_id", "owner_id", "request_id", "command_sequence"].some(field => Object.hasOwn(command, field)), "Eye command cannot choose host-owned request identity.");
      const request = { ...structuredClone(command), boot_id: options.bootId, owner_id: options.ownerId, request_id: randomBytes(16).toString("hex"), command_sequence: sequence } as EyeNativeWireRequest;
      // The codec validates all payload fields before any publication or sequence consumption.
      const bytes = Buffer.from(encodeEyeNativeRequest(request), "utf8");
      const deadline = performance.now() + duration;
      state = { ...state, busy: true, lastSequence: sequence };
      try {
        ready = await inspectReady();
        for (const slot of slots) await absent(slot);
        await checkChain(chain);
        active();
        const temporary = await open(join(directory, "command.tmp"), "wx", 0o600);
        try { await temporary.writeFile(bytes); await temporary.sync(); } finally { await temporary.close(); }
        const written = await read("command.tmp", COMMAND_BYTES);
        check(written.sha256 === hash(bytes), "Eye command temporary bytes changed before publication.");
        await absent("command.txt");
        await checkChain(chain);
        active(); check(performance.now() < deadline, "Eye request timed out before publication; temporary evidence was preserved.");
        const hostRequestSentAtMs = Date.now();
        await rename(join(directory, "command.tmp"), join(directory, "command.txt"));
        const published = await read("command.txt", COMMAND_BYTES);
        check(identity(written.status, published.status) && published.sha256 === written.sha256, "Eye command changed during atomic publication.");
        await poll("response.txt", deadline);
        const received = await read("response.txt", RESPONSE_BYTES);
        const response = parseEyeNativeResponse(received.bytes);
        assertEyeResponseCorrespondence(request, response);
        active();
        const hostReceiptReceivedAtMs = Date.now();
        check(performance.now() <= deadline && hostReceiptReceivedAtMs >= hostRequestSentAtMs, "Eye response validation exceeded its timeout or host clock regressed.");
        // Native retains both slots. Remove the command first so it cannot be
        // executed from its cache between response removal and command removal.
        await unchanged(received, RESPONSE_BYTES);
        await remove(published, COMMAND_BYTES);
        await remove(received, RESPONSE_BYTES);
        return { request, response, timing: { requestSequence: sequence, hostRequestSentAtMs, hostReceiptReceivedAtMs },
          commandSha256: published.sha256, responseSha256: received.sha256, productionReady: false as const };
      } catch (error) { throw fault(error); }
      finally { state = { ...state, busy: false }; if (state.status === "disposed") channels.delete(key); }
    },
    // Disposal is host-only: callers must close the native lease explicitly.
    // It never sweeps files, retries a mutation, or claims native cleanup.
    dispose() { state = { ...state, status: "disposed" }; verifier.close(); if (!state.busy) channels.delete(key); },
  };
}
