import { describe, expect, it } from "vitest";
import { cyberfox1337x_createAttestationAsker, PATH_ATTESTATION_ATTEMPTS, type PathAttestationWorker } from "../electron/eyeFrameTransport";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("path_attestation_retry_tests");

// The suite failed once in three full runs with "contains a reparse point or its path
// attributes could not be verified", thrown from the branch that catches a worker which
// never answered - not from a verdict. A dead pipe is not evidence about a path, so it
// is retried once on a fresh worker; a verdict never is.

type Answer = string | Error;

function workerReturning(answers: readonly Answer[]) {
  const asked: string[][] = [];
  let running = true, stopped = 0, index = 0;
  const worker: PathAttestationWorker = {
    alive: () => running,
    stop: () => { stopped += 1; running = false; },
    ask: paths => {
      asked.push([...paths]);
      const answer = answers[Math.min(index, answers.length - 1)];
      index += 1;
      if (answer instanceof Error) { running = false; return Promise.reject(answer); }
      return Promise.resolve(answer);
    },
  };
  return { worker, asked: () => asked, stops: () => stopped };
}

function askerOver(scripts: readonly (readonly Answer[])[]) {
  const built: ReturnType<typeof workerReturning>[] = [];
  const ask = cyberfox1337x_createAttestationAsker(() => {
    const made = workerReturning(scripts[Math.min(built.length, scripts.length - 1)]);
    built.push(made);
    return made.worker;
  });
  return { ask, built: () => built };
}

describe("path attestation reuse and retry", () => {
  it("reuses one worker for every answer it can give", async () => {
    const world = askerOver([["plain"]]);
    for (let call = 0; call < 5; call += 1) expect(await world.ask(["C:/evidence"])).toBe("plain");
    expect(world.built()).toHaveLength(1);
    expect(world.built()[0].asked()).toHaveLength(5);
  });

  it("retries a worker that could not answer on a fresh process", async () => {
    const world = askerOver([[new Error("Native eye path verification timed out.")], ["plain"]]);
    expect(await world.ask(["C:/evidence"])).toBe("plain");
    expect(world.built()).toHaveLength(2);
    // The dead worker is discarded rather than left to be reused with an unknown pipe.
    expect(world.built()[0].stops()).toBeGreaterThan(0);
  });

  it("gives up rather than retrying without end", async () => {
    const failure = new Error("Native eye path verification stopped unexpectedly.");
    const world = askerOver([[failure]]);
    await expect(world.ask(["C:/evidence"])).rejects.toThrow(/stopped unexpectedly/);
    expect(world.built()).toHaveLength(PATH_ATTESTATION_ATTEMPTS);
  });

  it("never retries a verdict, because re-asking until one changes is how the check stops meaning anything", async () => {
    const world = askerOver([["reparse"]]);
    expect(await world.ask(["C:/evidence"])).toBe("reparse");
    expect(world.built()).toHaveLength(1);
    expect(world.built()[0].asked()).toHaveLength(1);
  });

  it("reports the worker's own reason instead of a bare refusal", async () => {
    const world = askerOver([[new Error("Native eye path verification could not be started.")]]);
    await expect(world.ask(["C:/evidence"])).rejects.toThrow(/could not be started/);
  });

  it("starts a new worker once the reused one is no longer alive", async () => {
    const world = askerOver([["plain"], ["plain"]]);
    expect(await world.ask(["C:/evidence"])).toBe("plain");
    world.built()[0].worker.stop();
    expect(await world.ask(["C:/evidence"])).toBe("plain");
    expect(world.built()).toHaveLength(2);
  });
});
