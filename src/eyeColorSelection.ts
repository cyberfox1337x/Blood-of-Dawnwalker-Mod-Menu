const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("eye_color_selection");

export type EyeColorValue = string | null;
export type EyeColorSelectionState = {
  phase: "idle" | "pending" | "applied" | "error";
  value: EyeColorValue;
  message?: string;
};

/** apply must resolve only after the matching native operation has completed. */
export function createEyeColorSelection(options: {
  apply: (value: EyeColorValue, glow: number) => Promise<void>;
  notify: (state: EyeColorSelectionState) => void;
  delayMs?: number;
}) {
  let revision = 0;
  let disposed = false;
  let running = false;
  let due = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let queued: { value: EyeColorValue; glow: number; revision: number } | undefined;

  function cancelTimer() {
    if (timer !== undefined) clearTimeout(timer);
    timer = undefined;
  }

  async function drain() {
    if (disposed || running || !due || !queued) return;
    const request = queued;
    queued = undefined;
    due = false;
    running = true;
    try {
      await options.apply(request.value, request.glow);
      if (!disposed && request.revision === revision) {
        options.notify({ phase: "applied", value: request.value });
      }
    } catch (error) {
      if (!disposed && request.revision === revision) {
        options.notify({ phase: "error", value: request.value,
          message: error instanceof Error ? error.message : "Eye color could not be applied. Check the game connection and retry." });
      }
    } finally {
      running = false;
      if (!disposed && due && queued) void drain();
    }
  }

  function request(value: EyeColorValue, glow = 0) {
    if (disposed) return;
    if (value !== null && !/^#[\da-f]{6}$/i.test(value)) throw new Error("Choose a valid six-digit eye color.");
    if (!Number.isFinite(glow) || glow < 0) throw new Error("Choose a valid eye glow strength.");
    cancelTimer();
    queued = { value: value?.toLowerCase() ?? null, glow: value === null ? 0 : glow, revision: ++revision };
    due = false;
    options.notify({ phase: "pending", value: queued.value });
    if (value === null) {
      due = true;
      void drain();
    } else {
      timer = setTimeout(() => { timer = undefined; due = true; void drain(); }, options.delayMs ?? 250);
    }
  }

  // Session changes invalidate unsent work and receipts, but cannot undo a sent write.
  function invalidate() {
    ++revision;
    cancelTimer();
    queued = undefined;
    due = false;
    if (!disposed) options.notify({ phase: "idle", value: null });
  }

  function dispose() {
    disposed = true;
    invalidate();
  }

  return Object.freeze({ request, invalidate, dispose });
}
