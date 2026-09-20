import { afterEach, expect, it } from "vitest";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createQuestReminderStore, isQuestReminderSetting, QUEST_REMINDER_DEFAULT } from "./questReminderSetting.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("quest_reminder_setting_tests");

const roots: string[] = [];
afterEach(async () => { for (const root of roots.splice(0)) await rm(root, { recursive: true, force: true }); });

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "dawnwalker-quest-reminder-test-")); roots.push(root);
  const path = join(root, "nested", "quest-reminder.json");
  return { path, store: createQuestReminderStore(path) };
}

it("stays off until the user turns it on", async () => {
  const { store } = await fixture();
  expect(QUEST_REMINDER_DEFAULT).toBe(false);
  await store.load();
  expect(store.get()).toBe(false);
});

it("saves through a temporary file and reads the value back", async () => {
  const { path, store } = await fixture();
  await expect(store.set(true)).resolves.toBe(true);
  expect(store.get()).toBe(true);
  expect(JSON.parse(await readFile(path, "utf8"))).toBe(true);

  const reopened = createQuestReminderStore(path);
  await reopened.load();
  expect(reopened.get()).toBe(true);
});

it("refuses a value that is not a boolean and keeps the stored one", async () => {
  const { store } = await fixture();
  await store.set(true);
  await expect(store.set("yes")).rejects.toThrow(/true or false/);
  expect(store.get()).toBe(true);
  expect(isQuestReminderSetting("yes")).toBe(false);
});

it("falls back to off when the saved file is not a boolean", async () => {
  const { path, store } = await fixture();
  await store.set(true);
  await writeFile(path, '"sometimes"', "utf8");
  const reopened = createQuestReminderStore(path);
  await reopened.load();
  expect(reopened.get()).toBe(false);
});
