import type { ImportedMenuDispatchRequest, ImportedMenuSnapshot } from "./importedMenuContract.js";
import { parseQuestJournal } from "./runtimeReadback.js";
import { questReminderText, selectQuestReminder } from "./questReminderSelection.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("quest_reminder_monitor");

export type QuestReminderEvent = Readonly<{
  title: string;
  objective: string;
  desktopAccepted: boolean;
}>;

type TimerHandle = unknown;
type DispatchResult = Readonly<{ accepted: boolean; message: string; operationId?: string }>;

export type QuestReminderMonitorDependencies = Readonly<{
  getEnabled: () => boolean;
  state: () => Promise<ImportedMenuSnapshot>;
  dispatch: (request: ImportedMenuDispatchRequest) => Promise<DispatchResult>;
  notify: (title: string, objective: string) => Promise<boolean>;
  publish: (event: QuestReminderEvent) => void;
  schedule?: (callback: () => void, delay: number) => TimerHandle;
  cancel?: (handle: TimerHandle) => void;
  intervalMs?: number;
  retryMs?: number;
}>;

function objectiveFrom(snapshot: ImportedMenuSnapshot) {
  const section = snapshot.sections.find(candidate => candidate.id === "DWQuestReadback");
  const payload = section?.items.find(item => item.id === "snapshot")?.label;
  return selectQuestReminder(parseQuestJournal(typeof payload === "string" ? payload : undefined));
}

export function createQuestReminderMonitor(dependencies: QuestReminderMonitorDependencies) {
  const intervalMs = dependencies.intervalMs ?? 20_000;
  const retryMs = dependencies.retryMs ?? 2_000;
  const scheduleTimer = dependencies.schedule ?? ((callback, delay) => setTimeout(callback, delay));
  const cancelTimer = dependencies.cancel ?? (handle => clearTimeout(handle as ReturnType<typeof setTimeout>));
  let timer: TimerHandle | undefined;
  let disposed = false;
  let enabled = dependencies.getEnabled();
  let running = false;
  let sessionId: string | undefined;
  let announcedKey: string | undefined;
  let refreshOperationId: string | undefined;
  let generation = 0;

  const clearScheduled = (): void => {
    if (timer !== undefined) cancelTimer(timer);
    timer = undefined;
  };
  const schedule = (delay: number): void => {
    clearScheduled();
    if (disposed || !enabled) return;
    timer = scheduleTimer(() => { timer = undefined; void tick(); }, delay);
  };
  const resetSession = (): void => {
    sessionId = undefined;
    announcedKey = undefined;
    refreshOperationId = undefined;
  };
  const publishChangedObjective = async (snapshot: ImportedMenuSnapshot, expectedGeneration: number): Promise<void> => {
    const reminder = objectiveFrom(snapshot);
    if (!reminder) return;
    if (announcedKey === undefined) { announcedKey = reminder.key; return; }
    if (announcedKey === reminder.key) return;
    announcedKey = reminder.key;
    const objective = questReminderText(reminder);
    let desktopAccepted = false;
    try { desktopAccepted = await dependencies.notify(reminder.questTitle, objective); }
    catch { desktopAccepted = false; }
    if (disposed || !enabled || generation !== expectedGeneration) return;
    dependencies.publish({ title: reminder.questTitle, objective, desktopAccepted });
  };
  const tick = async (): Promise<void> => {
    if (disposed || !enabled || running) return;
    const expectedGeneration = generation;
    running = true;
    try {
      const snapshot = await dependencies.state();
      if (disposed || !enabled) return;
      if (!snapshot.ready || !snapshot.sessionId) {
        resetSession();
        schedule(retryMs);
        return;
      }
      if (sessionId !== snapshot.sessionId) {
        sessionId = snapshot.sessionId;
        announcedKey = undefined;
        refreshOperationId = undefined;
      }
      await publishChangedObjective(snapshot, expectedGeneration);
      if (disposed || !enabled || generation !== expectedGeneration) return;

      if (refreshOperationId) {
        const operation = snapshot.operation;
        if (operation?.id === refreshOperationId && ["queued", "running", "awaiting-confirmation"].includes(operation.status)) {
          schedule(retryMs);
          return;
        }
        refreshOperationId = undefined;
        schedule(intervalMs);
        return;
      }

      if ((snapshot.pendingFiniteTasks ?? 0) > 0
        || ["queued", "running", "awaiting-confirmation"].includes(snapshot.operation?.status ?? "")) {
        schedule(retryMs);
        return;
      }
      const result = await dependencies.dispatch({
        sessionId: snapshot.sessionId,
        action: "invoke",
        sectionId: "DWQuestReadback",
        itemId: "refresh",
      });
      if (result.accepted && result.operationId) {
        refreshOperationId = result.operationId;
        schedule(retryMs);
      } else schedule(intervalMs);
    } catch {
      if (!disposed && enabled) schedule(retryMs);
    } finally {
      running = false;
      if (!disposed && enabled && generation !== expectedGeneration && timer === undefined) schedule(0);
    }
  };

  return {
    start(): void { if (!disposed && enabled) void tick(); },
    settingChanged(next: boolean): void {
      generation += 1;
      enabled = next;
      clearScheduled();
      resetSession();
      if (!disposed && enabled) void tick();
    },
    dispose(): void { generation += 1; disposed = true; enabled = false; clearScheduled(); resetSession(); },
    inspect: () => ({ enabled, running, sessionId, announcedKey, refreshOperationId }),
  };
}
