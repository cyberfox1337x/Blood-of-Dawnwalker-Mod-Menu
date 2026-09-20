import { describe, expect, it, vi } from "vitest";
import type { ImportedMenuSnapshot } from "./importedMenuContract.js";
import { createQuestReminderMonitor } from "./questReminderMonitor.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("quest_reminder_monitor_tests");

type Timer = Readonly<{ callback: () => void; delay: number }>;

function questPayload(objective: string, current = 0, maximum = 1): string {
  return [
    "schema=1", "open_total=1", "returned=1", "truncated=0",
    "q=0,active,1,Withering%20Away,1,0",
    `o=0,active,${encodeURIComponent(objective)},${current},${maximum},0`,
  ].join(";");
}

function snapshot(payload: string, overrides: Partial<ImportedMenuSnapshot> = {}): ImportedMenuSnapshot {
  return {
    schema: 1,
    sessionId: "session-a",
    revision: 1,
    ready: true,
    sections: [{ id: "DWQuestReadback", title: "Quests", items: [
      { id: "refresh", type: "button" },
      { id: "snapshot", type: "label", label: payload },
    ] }],
    ...overrides,
  };
}

function setup(initial: ImportedMenuSnapshot) {
  let current = initial;
  let enabled = true;
  const timers: Timer[] = [];
  const notify = vi.fn(async () => true);
  const publish = vi.fn();
  const dispatch = vi.fn(async () => ({ accepted: true, message: "Queued", operationId: "refresh-1" }));
  const monitor = createQuestReminderMonitor({
    getEnabled: () => enabled,
    state: async () => current,
    dispatch,
    notify,
    publish,
    schedule: (callback: () => void, delay: number) => { const timer = { callback, delay }; timers.push(timer); return timer; },
    cancel: (timer: unknown) => { const index = timers.indexOf(timer as Timer); if (index >= 0) timers.splice(index, 1); },
  });
  const runNext = async () => {
    const timer = timers.shift();
    if (!timer) throw new Error("No timer was scheduled.");
    timer.callback();
    await vi.waitFor(() => expect(monitor.inspect().running).toBe(false));
  };
  return {
    monitor, timers, notify, publish, dispatch, runNext,
    setSnapshot: (next: ImportedMenuSnapshot) => { current = next; },
    setEnabled: (next: boolean) => { enabled = next; monitor.settingChanged(next); },
  };
}

describe("quest reminder main-process monitor", () => {
  it("seeds the current objective without notifying and refreshes through the imported transport", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    expect(fixture.notify).not.toHaveBeenCalled();
    expect(fixture.dispatch).toHaveBeenCalledWith({
      sessionId: "session-a", action: "invoke", sectionId: "DWQuestReadback", itemId: "refresh",
    });
    expect(fixture.timers.at(-1)?.delay).toBe(2_000);
  });

  it("announces a changed objective once after refresh completion", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.setSnapshot(snapshot(questPayload("Put firewood in the stove"), {
      revision: 2,
      operation: { id: "refresh-1", status: "completed", message: "Quest journal refreshed." },
    }));
    await fixture.runNext();
    expect(fixture.notify).toHaveBeenCalledWith("Withering Away", "Put firewood in the stove");
    expect(fixture.publish).toHaveBeenCalledWith({
      title: "Withering Away", objective: "Put firewood in the stove", desktopAccepted: true,
    });
    expect(fixture.timers.at(-1)?.delay).toBe(20_000);
    await fixture.runNext();
    expect(fixture.notify).toHaveBeenCalledTimes(1);
  });

  it("retries soon while another operation or finite task is busy", async () => {
    const fixture = setup(snapshot(questPayload("Split logs"), {
      pendingFiniteTasks: 1,
      operation: { id: "player-command", status: "running" },
    }));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.monitor.inspect().running).toBe(false));
    expect(fixture.dispatch).not.toHaveBeenCalled();
    expect(fixture.timers.at(-1)?.delay).toBe(2_000);
  });

  it("reseeds on a new game session instead of replaying its current objective", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.setSnapshot(snapshot(questPayload("Find your family"), { sessionId: "session-b", revision: 1 }));
    await fixture.runNext();
    expect(fixture.notify).not.toHaveBeenCalled();
  });

  it("announces count progress and keeps the objective text useful", async () => {
    const fixture = setup(snapshot(questPayload("Split logs", 1, 5)));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.setSnapshot(snapshot(questPayload("Split logs", 2, 5), {
      revision: 2, operation: { id: "refresh-1", status: "completed" },
    }));
    await fixture.runNext();
    expect(fixture.notify).toHaveBeenCalledWith("Withering Away", "Split logs (2/5)");
  });

  it("survives disconnect and silently seeds the reconnected session", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.setSnapshot(snapshot(questPayload("Split logs"), { ready: false, sections: [] }));
    await fixture.runNext();
    expect(fixture.timers.at(-1)?.delay).toBe(2_000);
    fixture.setSnapshot(snapshot(questPayload("Find your family"), { sessionId: "session-b" }));
    await fixture.runNext();
    expect(fixture.notify).not.toHaveBeenCalled();
    expect(fixture.dispatch).toHaveBeenLastCalledWith(expect.objectContaining({ sessionId: "session-b" }));
  });

  it("keeps monitoring when Windows refuses or throws while showing a notification", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    fixture.notify.mockRejectedValueOnce(new Error("refused"));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.setSnapshot(snapshot(questPayload("Put firewood in the stove"), {
      revision: 2, operation: { id: "refresh-1", status: "completed" },
    }));
    await fixture.runNext();
    expect(fixture.publish).toHaveBeenCalledWith({
      title: "Withering Away", objective: "Put firewood in the stove", desktopAccepted: false,
    });
    expect(fixture.timers.at(-1)?.delay).toBe(20_000);
  });

  it("stops every scheduled read when reminders are switched off", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.setEnabled(false);
    expect(fixture.timers).toHaveLength(0);
    expect(fixture.monitor.inspect().enabled).toBe(false);
    fixture.monitor.dispose();
  });

  it("cancels background work when the application disposes the monitor", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.monitor.dispose();
    expect(fixture.timers).toHaveLength(0);
    fixture.monitor.start();
    expect(fixture.dispatch).toHaveBeenCalledTimes(1);
  });

  it("suppresses a late renderer event when reminders are disabled during notification delivery", async () => {
    const fixture = setup(snapshot(questPayload("Split logs")));
    let releaseNotification!: (accepted: boolean) => void;
    fixture.notify.mockImplementationOnce(() => new Promise(resolve => { releaseNotification = resolve; }));
    fixture.monitor.start();
    await vi.waitFor(() => expect(fixture.dispatch).toHaveBeenCalledTimes(1));
    fixture.setSnapshot(snapshot(questPayload("Find your family"), {
      revision: 2, operation: { id: "refresh-1", status: "completed" },
    }));
    const next = fixture.timers.shift();
    next?.callback();
    await vi.waitFor(() => expect(fixture.notify).toHaveBeenCalledTimes(1));
    fixture.setEnabled(false);
    releaseNotification(true);
    await vi.waitFor(() => expect(fixture.monitor.inspect().running).toBe(false));
    expect(fixture.publish).not.toHaveBeenCalled();
    expect(fixture.timers).toHaveLength(0);
  });
});
