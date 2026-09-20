import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { join } from "node:path";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_game_process");
const execute = promisify(execFile);

// A disconnected bridge does not prove that the game has stopped saving.
async function queryDawnwalkerRunning(): Promise<boolean> {
  if (process.platform !== "win32") throw new Error("File changes require Windows process verification.");
  const executable = join(process.env.SystemRoot ?? "C:\\Windows", "System32", "tasklist.exe");
  const { stdout } = await execute(executable, ["/FO", "CSV", "/NH"], { windowsHide: true, timeout: 5000, maxBuffer: 4 * 1024 * 1024 });
  if (!/^"[^"]+","\d+"/m.test(stdout)) throw new Error("Unable to verify game process status; no files may be changed.");
  return /^"Dawnwalker(?:-Win64-Shipping)?\.exe",/im.test(stdout);
}

// tasklist is a process spawn that costs a few hundred milliseconds of CPU; the runtime-info
// refresh asked for it every 2 s, and that alone was ~20% of a core while the menu sat idle
// (measured 2026-09-18: 21% → 13% of a core with a 1.5 s window, 6.7% with 6 s). One answer is reused for a short window and concurrent callers
// share the in-flight query. A failure is never cached, so a broken tasklist still refuses
// writes exactly as before.
// Six seconds: the two status callers refresh every 2 s, so one spawn serves three refreshes.
// File-write guards must request a fresh probe; a cached stopped verdict cannot establish
// that the game is still closed at the time of a save or configuration operation.
const PROCESS_CHECK_TTL_MS = 6000;
let cachedAnswer: Readonly<{ at: number; running: boolean }> | undefined;
let inFlight: Promise<boolean> | undefined;

export async function isDawnwalkerRunning(options: { fresh?: boolean } = {}): Promise<boolean> {
  // Do not join an older in-flight status query either: it may have observed the process
  // list before this write was requested. Each write guard obtains its own observation.
  if (options.fresh) return queryDawnwalkerRunning();
  if (cachedAnswer && Date.now() - cachedAnswer.at < PROCESS_CHECK_TTL_MS) return cachedAnswer.running;
  if (!inFlight) {
    inFlight = queryDawnwalkerRunning()
      .then(running => { cachedAnswer = { at: Date.now(), running }; return running; })
      .finally(() => { inFlight = undefined; });
  }
  return inFlight;
}

/** Test seam: forget the cached answer so the next call queries the process list again. */
export function resetDawnwalkerRunningCache(): void {
  cachedAnswer = undefined;
}
