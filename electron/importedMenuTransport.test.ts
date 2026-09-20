import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, rm, writeFile, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep, basename } from "node:path";
import { createImportedMenuTransport, validateImportedRequest } from "./importedMenuTransport.js";
import type { ImportedMenuSnapshot } from "./importedMenuContract.js";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_transport_tests");
const folders: string[] = [];
afterEach(async () => { for (const folder of folders.splice(0)) {
  if (!resolve(folder).startsWith(resolve(tmpdir()) + sep) || !basename(folder).startsWith("dawnwalker-import-test-")) throw new Error("Unexpected test cleanup path.");
  await rm(folder, { recursive: true, force: true });
} });
// The build the fixture's payload manifest is taken to have been accepted against.
const ACCEPTED_BUILD = "25129649";
const baseline = (): ImportedMenuSnapshot => ({ schema: 1, sessionId: "boot-world-player", revision: 1, heartbeat: 1000, buildId: ACCEPTED_BUILD, ready: true,
  sections: [{ id: "player", title: "Player", items: [
    { id: "toggle", type: "checkbox", value: false }, { id: "amount", type: "number", min: 1, max: 10 },
    { id: "choice", type: "dropdown", options: ["Available"] }, { id: "apply", type: "button" },
  ] }] });
async function fixture(verify = true) {
  const root = await mkdtemp(join(tmpdir(), "dawnwalker-import-test-")); folders.push(root);
  await writeFile(join(root, "state.json"), JSON.stringify(baseline()));
  const catalogPath = join(root, "catalog.json"); await writeFile(catalogPath, JSON.stringify(baseline()));
  return { root, transport: createImportedMenuTransport({ channelRoot: root, catalogPath,
    expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => verify, now: () => 1000000 }) };
}
describe("Imported native menu transport", () => {
  it("accepts the expanded bounded section catalog and still rejects oversized snapshots", async () => {
    const { root, transport } = await fixture();
    const sections = Array.from({ length: 65 }, (_, index) => ({
      id: `section-${index}`, title: `Section ${index}`, items: [] as ImportedMenuSnapshot["sections"][number]["items"],
    }));
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), sections }));
    expect(await transport.state()).toMatchObject({ ready: true, sections });

    const oversized = Array.from({ length: 97 }, (_, index) => ({ id: `oversized-${index}`, title: `Oversized ${index}`, items: [] }));
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), revision: 2, sections: oversized }));
    expect(await transport.state()).toMatchObject({ ready: false, message: expect.stringMatching(/incompatible/i) });
  });
  it("rejects writes to native read-only status controls", () => {
    const snapshot = baseline();
    snapshot.sections[0].items[0] = { ...snapshot.sections[0].items[0], readOnly: true } as unknown as ImportedMenuSnapshot["sections"][number]["items"][number];
    expect(() => validateImportedRequest({ sessionId: snapshot.sessionId, action: "set", sectionId: "player", itemId: "toggle", value: true }, snapshot)).toThrow(/read-only/i);
  });
  it.each([-1, NaN, Infinity, "1", null, 1.5])("rejects invalid finite callback counts (%s)", (count) => {
    const snapshot = { ...baseline(), pendingFiniteTasks: count } as unknown as ImportedMenuSnapshot;
    expect(() => validateImportedRequest({ sessionId: snapshot.sessionId, action: "refresh" }, snapshot)).toThrow(/callback count/);
  });
  it("refuses known busy callback queues without writing a command, then permits a new read after drain", async () => {
    const { root, transport } = await fixture();
    const snapshot = { ...baseline(), sections: [...baseline().sections,
      { id: "DWQuestReadback", title: "Quests", items: [{ id: "refresh", type: "button" }] }], pendingFiniteTasks: 2 };
    await writeFile(join(root, "state.json"), JSON.stringify(snapshot));
    const read = { sessionId: snapshot.sessionId, action: "invoke" as const, sectionId: "DWQuestReadback", itemId: "refresh" };
    expect((await transport.dispatch(read)).accepted).toBe(false);
    expect((await transport.dispatch({ sessionId: snapshot.sessionId, action: "set", sectionId: "player", itemId: "toggle", value: true })).accepted).toBe(false);
    await expect(readFile(join(root, "command.txt"))).rejects.toMatchObject({ code: "ENOENT" });
    await writeFile(join(root, "state.json"), JSON.stringify({ ...snapshot, pendingFiniteTasks: 0 }));
    expect((await transport.dispatch(read)).accepted).toBe(true);
  });
  it("releases an expired unacknowledged quest read without replaying it", async () => {
    const { root } = await fixture();
    let clock = 1000000;
    const snapshot = { ...baseline(), sections: [...baseline().sections,
      { id: "DWQuestReadback", title: "Quests", items: [{ id: "refresh", type: "button" }] }] } as ImportedMenuSnapshot;
    await writeFile(join(root, "state.json"), JSON.stringify(snapshot));
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => clock });
    const sent = await transport.dispatch({ sessionId: snapshot.sessionId, action: "invoke", sectionId: "DWQuestReadback", itemId: "refresh" });
    const originalCommand = await readFile(join(root, "command.txt"), "utf8");
    clock += 9000;
    await writeFile(join(root, "state.json"), JSON.stringify({ ...snapshot, heartbeat: clock / 1000 }));
    expect(await transport.state()).toMatchObject({ ready: true, operation: { id: sent.operationId, status: "failed" } });
    expect(await readFile(join(root, "command.txt"), "utf8")).toBe(originalCommand);
    const next = await transport.dispatch({ sessionId: snapshot.sessionId, action: "set", sectionId: "player", itemId: "toggle", value: true });
    expect(next.accepted).toBe(true);
    // A late acknowledgement of the old read must not acknowledge the new mutation.
    await writeFile(join(root, "state.json"), JSON.stringify({ ...snapshot, heartbeat: clock / 1000,
      operation: { id: sent.operationId, status: "completed", message: "Old read finished" } }));
    expect((await transport.state()).operation).toMatchObject({ id: next.operationId, status: "queued" });
  });
  it("does not release a timed-out quest read while another native operation is running", async () => {
    const { root } = await fixture();
    let clock = 1000000;
    const snapshot = { ...baseline(), sections: [{ id: "DWQuestReadback", title: "Quests", items: [{ id: "refresh", type: "button" }] }] } as ImportedMenuSnapshot;
    await writeFile(join(root, "state.json"), JSON.stringify(snapshot));
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => clock });
    await transport.dispatch({ sessionId: snapshot.sessionId, action: "invoke", sectionId: "DWQuestReadback", itemId: "refresh" });
    clock += 9000;
    await writeFile(join(root, "state.json"), JSON.stringify({ ...snapshot, heartbeat: clock / 1000,
      operation: { id: "other-native-operation", status: "running", message: "Busy" } }));
    expect((await transport.state()).ready).toBe(false);
  });
  it("keeps an unacknowledged mutation blocked after its deadline", async () => {
    const { root } = await fixture();
    let clock = 1000000;
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => clock });
    const sent = await transport.dispatch({ sessionId: baseline().sessionId, action: "set", sectionId: "player", itemId: "toggle", value: true });
    clock += 9000;
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: clock / 1000 }));
    expect(await transport.state()).toMatchObject({ ready: false, operation: { id: sent.operationId, status: "failed" } });
    expect((await transport.dispatch({ sessionId: baseline().sessionId, action: "set", sectionId: "player", itemId: "toggle", value: false })).accepted).toBe(false);
  });
  it("reports the failed connection gate without accepting the state", async () => {
    const { root } = await fixture();
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD,
      verifyRuntime: async () => false, verificationFailure: () => "Runtime file differs; open the current menu.", now: () => 1000000 });
    expect(await transport.state()).toMatchObject({ ready: false, message: "Runtime file differs; open the current menu." });
    // With no way to ask the process, a stale heartbeat is reported as exactly that -
    // not as a hang and not as an exit, because the file cannot tell the two apart.
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 990 }));
    const unknown = (await transport.state()).message ?? "";
    expect(unknown).toContain("has not responded");
    expect(unknown).not.toContain("not running");
    expect(unknown).not.toContain("game is running");
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), ready: false }));
    expect((await transport.state()).message).toContain("Load a playable save");
  });
  it("tells a confirmed exit apart from a running game whose runtime went quiet", async () => {
    // The screenshots that prompted this said "restart the game" over a state file
    // from the previous day - the game was not open. But a stale heartbeat alone does
    // not establish that, so the process is asked and the message says what was found.
    const { root } = await fixture();
    const make = (gameRunning: () => Promise<boolean | undefined>) => createImportedMenuTransport({
      channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => 1000000, gameRunning });
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 900, shutdown: "quit" }));

    const exited = (await make(async () => false).state()).message ?? "";
    expect(exited).toContain("closed normally");
    expect(exited).toContain("Start the game");
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 900 }));

    const quiet = (await make(async () => true).state()).message ?? "";
    expect(quiet).toContain("game is running");
    expect(quiet).toContain("has not responded");
    expect(quiet).not.toContain("not running");

    // A game that keeps running without any heartbeat for long enough is the startup
    // freeze candidate; the message offers recovery guidance, and a fresh
    // heartbeat resets the clock so a later real stall starts counting from zero.
    let clock = 1000000;
    const frozen = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => clock, gameRunning: async () => true });
    expect((await frozen.state()).message).not.toContain("startup freeze");
    clock += 149_000;
    expect((await frozen.state()).message).not.toContain("startup freeze");
    clock += 2_000;
    const stuck = (await frozen.state()).message ?? "";
    expect(stuck).toContain("startup freeze");
    expect(stuck).toContain("running for 151s");
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: Math.floor(clock / 1000) }));
    expect((await frozen.state()).ready).toBe(true);
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 900 }));
    expect((await frozen.state()).message).not.toContain("startup freeze");

    // Following the advice (close the game, relaunch) must not carry the old quiet period
    // into the new boot: a confirmed exit ends it, so the relaunch counts from zero again.
    let running = true;
    const relaunched = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => clock, gameRunning: async () => running });
    expect((await relaunched.state()).message).not.toContain("startup freeze");
    clock += 160_000;
    expect((await relaunched.state()).message).toContain("startup freeze");
    running = false;
    expect((await relaunched.state()).message).toContain("without a recorded shutdown confirmation");
    running = true;
    const fresh = (await relaunched.state()).message ?? "";
    expect(fresh).not.toContain("startup freeze");
    expect(fresh).toContain("has not responded");
    clock += 151_000;
    expect((await relaunched.state()).message).toContain("running for 151s");

    const unsure = (await make(async () => undefined).state()).message ?? "";
    expect(unsure).not.toContain("not running");
    expect(unsure).not.toContain("game is running");
  });
  it("reports an unconfirmed shutdown and calls an optional handler once per exit", async () => {
    // A missing shutdown marker does not establish how the process ended. An optional
    // exit handler, when supplied by a caller, must
    // run exactly once for that exit, however many polls see the same stale file.
    const { root } = await fixture();
    const seen: number[] = [];
    let finish: (message: string) => void = () => {};
    const transport = createImportedMenuTransport({
      channelRoot: root, catalogPath: join(root, "catalog.json"), expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true,
      now: () => 1000000, gameRunning: async () => false,
      onUncleanExit: info => { seen.push(info.lastHeartbeat); return new Promise<string>(resolve => { finish = resolve; }); } });
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 900 }));
    const first = (await transport.state()).message ?? "";
    expect(first).toContain("ended without a recorded shutdown confirmation");
    // While the optional handler runs the outcome remains pending.
    expect(first).toContain("wait for this message to change");
    expect((await transport.state()).message).toContain("wait for this message to change");
    finish("Recovery done. You can start the game now.");
    await new Promise(resolve => setTimeout(resolve, 0));
    expect((await transport.state()).message).toContain("You can start the game now");
    expect(seen).toEqual([900]);
    // A later session that also died uncleanly is a new exit and is recovered again.
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 950 }));
    await transport.state();
    expect(seen).toEqual([900, 950]);
    finish("done");
    // A clean quit is never treated as an unclean exit.
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 980, shutdown: "quit" }));
    expect((await transport.state()).message).toContain("closed normally");
    expect(seen).toEqual([900, 950]);
  });
  it("tells the player how to recover from an unclean exit when no recovery hook is wired", async () => {
    const { root } = await fixture();
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"), expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => 1000000, gameRunning: async () => false });
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 900 }));
    const message = (await transport.state()).message ?? "";
    expect(message).toContain("ended without a recorded shutdown confirmation");
    expect(message).toContain("close the game and start it again");
  });
  it("does not ask about the process while the heartbeat is fresh", async () => {
    const { root } = await fixture();
    let asked = 0;
    const transport = createImportedMenuTransport({
      channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => 1000000,
      gameRunning: async () => { asked += 1; return true; } });
    expect((await transport.state()).ready).toBe(true);
    expect(asked).toBe(0);
  });
  it("provides bounded startup guidance when no runtime snapshot has ever arrived", async () => {
    const { root } = await fixture();
    await unlink(join(root, "state.json"));
    let clock = 1000000;
    let running = true;
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true,
      now: () => clock, gameRunning: async () => running });
    expect((await transport.state()).message).toContain("game is running");
    clock += 151000;
    expect((await transport.state()).message).toContain("startup freeze");
    expect((await transport.state()).ready).toBe(false);
    running = false;
    expect((await transport.state()).message).toContain("Start the game");
    running = true;
    expect((await transport.state()).message).not.toContain("startup freeze");
  });
  it("does not diagnose a known gameplay session's lost heartbeat as a startup freeze", async () => {
    const { root } = await fixture();
    let clock = 1000000;
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true,
      now: () => clock, gameRunning: async () => true });
    expect((await transport.state()).ready).toBe(true);
    clock += 6000;
    await transport.state();
    clock += 151000;
    const message = (await transport.state()).message ?? "";
    expect(message).toContain("runtime stopped responding");
    expect(message).not.toContain("startup freeze");
  });
  it("disables a section pinned to another build and refuses requests to it", async () => {
    // Eye colour was reviewed on one executable. The Lua gate compares a constant to
    // itself, so the only real check is here, against the build the inspector reads.
    const { root } = await fixture();
    const eye = { id: "DWEyeColor", title: "Eye", items: [
      { id: "color", type: "input", label: "Eye color", value: "" },
      { id: "restore", type: "button", label: "Restore" },
      { id: "status", type: "label", label: "Original game eyes restored." },
    ] };
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), sections: [...baseline().sections, eye] }));
    const make = (installed: string) => createImportedMenuTransport({
      channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => 1000000,
      sectionBuildPins: { DWEyeColor: "25129649" }, installedBuildId: async () => installed });

    const mismatched = make("25232147");
    const snapshot = await mismatched.state();
    // A read-only observation stays usable on the refused build - it is how the pin
    // gets re-verified - while every mutating control is disabled.
    const observing = createImportedMenuTransport({
      channelRoot: root, catalogPath: join(root, "catalog.json"),
      expectedBuildId: async () => ACCEPTED_BUILD, verifyRuntime: async () => true, now: () => 1000000,
      sectionBuildPins: { DWEyeColor: "25129649" }, installedBuildId: async () => "25232147",
      buildPinReadOnlyItems: { DWEyeColor: ["observe"] } });
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), sections: [...baseline().sections,
      { ...eye, items: [...eye.items, { id: "observe", type: "button", label: "Observe" }] }] }));
    const observed = (await observing.state()).sections.find(item => item.id === "DWEyeColor")!;
    expect(observed.items.find(item => item.id === "observe")?.disabled).toBeUndefined();
    expect(observed.items.find(item => item.id === "color")).toMatchObject({ disabled: true });
    const allowed = await observing.dispatch({ sessionId: "boot-world-player", action: "invoke", sectionId: "DWEyeColor", itemId: "observe" });
    expect(allowed.accepted).toBe(true);
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), sections: [...baseline().sections, eye] }));
    const section = snapshot.sections.find(item => item.id === "DWEyeColor")!;
    expect(snapshot.ready).toBe(true);
    expect(section.items.find(item => item.id === "color")).toMatchObject({ disabled: true, enabled: false });
    expect(section.items.find(item => item.id === "status")?.label).toContain("25129649");
    expect(section.items.find(item => item.id === "status")?.label).toContain("25232147");
    // Other sections are untouched by someone else's pin.
    expect(snapshot.sections.find(item => item.id === "player")?.items.some(item => item.disabled)).toBeFalsy();
    const refused = await mismatched.dispatch({ sessionId: snapshot.sessionId, action: "set", sectionId: "DWEyeColor", itemId: "color", value: "#1a679e" });
    expect(refused.accepted).toBe(false);
    expect(refused.message).toContain("Reviewed only on game build 25129649");

    const matching = make("25129649");
    const fine = (await matching.state()).sections.find(item => item.id === "DWEyeColor")!;
    expect(fine.items.find(item => item.id === "color")?.disabled).toBeUndefined();
    expect(fine.items.find(item => item.id === "status")?.label).toBe("Original game eyes restored.");
  });
  it("says a request is pending rather than blaming the connection", async () => {
    const { transport } = await fixture();
    const first = await transport.dispatch({ sessionId: "boot-world-player", action: "refresh" });
    expect(first.accepted).toBe(true);
    const second = await transport.dispatch({ sessionId: "boot-world-player", action: "refresh" });
    expect(second.accepted).toBe(false);
    expect(second.message).toContain("still being applied");
    expect(second.message).not.toContain("connection");
  });
  it("names both builds when the game has been patched past the accepted payload", async () => {
    const { root, transport } = await fixture();
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), buildId: "25191761" }));
    const snapshot = await transport.state();
    expect(snapshot.ready).toBe(false);
    expect(snapshot.message).toContain("25191761");
    expect(snapshot.message).toContain(ACCEPTED_BUILD);
  });
  it("refuses to judge a snapshot when the accepted build cannot be read", async () => {
    const root = await mkdtemp(join(tmpdir(), "dawnwalker-import-test-")); folders.push(root);
    await writeFile(join(root, "state.json"), JSON.stringify(baseline()));
    const catalogPath = join(root, "catalog.json"); await writeFile(catalogPath, JSON.stringify(baseline()));
    const transport = createImportedMenuTransport({ channelRoot: root, catalogPath,
      expectedBuildId: async () => undefined, verifyRuntime: async () => true, now: () => 1000000 });
    const snapshot = await transport.state();
    expect(snapshot.ready).toBe(false);
    expect(snapshot.message).toContain("could not read the build");
  });
  it("waits through the native mailbox replacement gap without accepting stale data", async () => {
    const { root, transport } = await fixture();
    await unlink(join(root, "state.json"));
    const replacement = new Promise<void>((resolve, reject) => setTimeout(() => {
      void writeFile(join(root, "state.json"), JSON.stringify(baseline())).then(resolve, reject);
    }, 10));
    expect((await transport.state()).ready).toBe(true);
    await replacement;
    await unlink(join(root, "state.json"));
    expect((await transport.state()).ready).toBe(false);
  });
  it("preserves catalog while refusing unverifiable runtime writes", async () => {
    const { root, transport } = await fixture(false);
    expect(await transport.state()).toMatchObject({ ready: false, sections: [{ id: "player" }] });
    expect((await transport.dispatch({ sessionId: "boot-world-player", action: "invoke", sectionId: "player", itemId: "apply" })).accepted).toBe(false);
    await expect(readFile(join(root, "command.txt"))).rejects.toThrow();
  });
  it("rejects stale heartbeat and mismatched sessions", async () => {
    const { root, transport } = await fixture();
    await writeFile(join(root, "state.json"), JSON.stringify({ ...baseline(), heartbeat: 990 }));
    expect((await transport.state()).ready).toBe(false);
    expect(() => validateImportedRequest({ sessionId: "old", action: "refresh" }, baseline())).toThrow(/session changed/);
  });
  it("rejects unregistered controls, wrong types, bounds, and unknown options", () => {
    for (const request of [
      { action: "invoke", itemId: "missing" }, { action: "set", itemId: "toggle", value: "true" },
      { action: "set", itemId: "amount", value: 11 }, { action: "set", itemId: "choice", value: "unknown" },
    ] as const) expect(() => validateImportedRequest({ ...request, sessionId: "boot-world-player", sectionId: "player" }, baseline())).toThrow();
  });
  it("queues a bounded request without claiming application and prevents channel overwrite", async () => {
    const { root, transport } = await fixture();
    const request = { sessionId: "boot-world-player", action: "set", sectionId: "player", itemId: "toggle", value: true } as const;
    const result = await transport.dispatch(request);
    expect(result).toMatchObject({ accepted: true, message: expect.stringContaining("queued"), operationId: expect.any(String) });
    const original = await readFile(join(root, "command.txt"), "utf8");
    expect(original).toContain(`request_id=${result.operationId}\n`);
    expect(original).toContain("expires_at=1005\n");
    const rejected = await transport.dispatch(request);
    expect(rejected.accepted).toBe(false);
    expect(rejected.operationId).toBeUndefined();
    expect(await readFile(join(root, "command.txt"), "utf8")).toBe(original);
  });
  it("requires the current one-use confirmation token", () => {
    const state = { ...baseline(), confirmation: { token: "current", title: "Confirm", message: "Permanent change" }, operation: { id: "op", status: "awaiting-confirmation" as const } };
    expect(() => validateImportedRequest({ sessionId: state.sessionId, action: "confirm", confirmationToken: "old", confirmed: true }, state)).toThrow();
    expect(() => validateImportedRequest({ sessionId: state.sessionId, action: "confirm", confirmationToken: "current", confirmed: false }, state)).not.toThrow();
    expect(() => validateImportedRequest({ sessionId: state.sessionId, action: "invoke", sectionId: "player", itemId: "apply" }, state)).toThrow(/current action/);
  });
});



