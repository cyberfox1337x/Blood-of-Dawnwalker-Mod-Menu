import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("quest_reminder_setting");

/** Off unless the user has turned it on: the menu must not raise desktop notifications
 *  on a fresh install without being asked. */
export const QUEST_REMINDER_DEFAULT = false;

export function isQuestReminderSetting(value: unknown): value is boolean {
  return typeof value === "boolean";
}

/**
 * Stores whether objective reminders may be shown, using the same replace-by-rename
 * write the interface scale uses so a half-written file can never be read back.
 */
export function createQuestReminderStore(preferencePath: string) {
  let enabled = QUEST_REMINDER_DEFAULT;
  let pendingWrite = Promise.resolve();
  return {
    get: (): boolean => enabled,
    async load(): Promise<void> {
      try {
        const saved: unknown = JSON.parse(await readFile(preferencePath, "utf8"));
        if (!isQuestReminderSetting(saved)) throw new Error("Invalid saved quest reminder setting; reminders stay off.");
        enabled = saved;
      } catch (error) {
        // A missing file is the normal first run; anything else is worth reporting
        // once, and the safe default still applies.
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") console.warn("Unable to load the quest reminder setting:", error);
      }
    },
    set(value: unknown): Promise<boolean> {
      if (!isQuestReminderSetting(value)) return Promise.reject(new Error("The quest reminder setting must be true or false."));
      const operation = pendingWrite.then(async () => {
        await mkdir(dirname(preferencePath), { recursive: true });
        await writeFile(`${preferencePath}.tmp`, JSON.stringify(value), "utf8");
        await rename(`${preferencePath}.tmp`, preferencePath);
        enabled = value;
      });
      // Keep the rejection for the caller while letting the next save retry.
      pendingWrite = operation.catch(() => undefined);
      return operation.then(() => value);
    },
  };
}
