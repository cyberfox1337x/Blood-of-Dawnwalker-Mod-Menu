import { expect, it } from "vitest";
import { selectQuestReminder, questReminderText } from "./questReminder";
import type { RuntimeQuestJournalReadback, RuntimeQuestReadback, RuntimeQuestObjectiveReadback, RuntimeQuestState } from "../electron/runtimeReadback";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("quest_reminder_tests");

function objective(text: string, state: RuntimeQuestState, extra: Partial<RuntimeQuestObjectiveReadback> = {}): RuntimeQuestObjectiveReadback {
  return { text, state, currentCount: 0, maxCount: 1, optional: false, ...extra };
}
function quest(title: string, tracked: boolean, objectives: RuntimeQuestObjectiveReadback[], state: RuntimeQuestState = "active"): RuntimeQuestReadback {
  return { title, state, tracked, objectiveCount: objectives.length, objectivesTruncated: false, objectives };
}
function journal(quests: RuntimeQuestReadback[]): RuntimeQuestJournalReadback {
  return { openQuestCount: quests.length, returnedQuestCount: quests.length, truncated: false, quests };
}

it("has nothing to announce without a journal", () => {
  expect(selectQuestReminder(undefined)).toBeUndefined();
  expect(selectQuestReminder(journal([]))).toBeUndefined();
});

it("names the tracked quest's active step, matching the journal panel", () => {
  const reminder = selectQuestReminder(journal([
    quest("The Blood of Dawnwalker", false, [objective("Bring Lunka back", "success"), objective("Find your family", "unknown")]),
    quest("Withering Away", true, [
      objective("Split logs for firewood", "active"),
      objective("Add the firewood to the stove", "unknown"),
    ]),
  ]));
  expect(reminder).toMatchObject({ questTitle: "Withering Away", objective: "Split logs for firewood" });
});

it("skips optional objectives so the reminder names what actually blocks progress", () => {
  const reminder = selectQuestReminder(journal([
    quest("Withering Away", true, [
      objective("Take your clothes out of the storage chest", "active", { optional: true }),
      objective("Split logs for firewood", "active"),
    ]),
  ]));
  expect(reminder?.objective).toBe("Split logs for firewood");
});

it("falls back to the first active quest when nothing is tracked", () => {
  const reminder = selectQuestReminder(journal([
    quest("Finished Business", false, [objective("Done", "success")]),
    quest("Withering Away", false, [objective("Split logs for firewood", "active")]),
  ]));
  expect(reminder?.questTitle).toBe("Withering Away");
});

it("ignores a tracked quest that is no longer active", () => {
  const reminder = selectQuestReminder(journal([
    quest("Old Tracked", true, [objective("Stale step", "active")], "success"),
    quest("Withering Away", false, [objective("Split logs for firewood", "active")]),
  ]));
  expect(reminder?.questTitle).toBe("Withering Away");
});

it("includes countable progress and changes identity when the count moves", () => {
  const build = (current: number) => selectQuestReminder(journal([
    quest("Withering Away", true, [objective("Split logs for firewood", "active", { currentCount: current, maxCount: 5 })]),
  ]));
  const first = build(2)!, second = build(3)!;
  expect(questReminderText(first)).toBe("Split logs for firewood (2/5)");
  expect(first.key).not.toBe(second.key);
});

it("keeps the same identity while the objective is unchanged", () => {
  const build = () => selectQuestReminder(journal([quest("Withering Away", true, [objective("Split logs for firewood", "active")])]))!;
  expect(build().key).toBe(build().key);
  expect(questReminderText(build())).toBe("Split logs for firewood");
});
