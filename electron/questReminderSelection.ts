import type { RuntimeQuestJournalReadback, RuntimeQuestReadback } from "./runtimeReadback.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("quest_reminder_selection");

export type QuestReminder = Readonly<{
  questTitle: string;
  objective: string;
  progress?: string;
  key: string;
}>;

function activeObjectiveOf(quest: RuntimeQuestReadback): QuestReminder | undefined {
  const objective = quest.objectives.find(candidate => candidate.state === "active" && !candidate.optional);
  if (!objective) return undefined;
  const countable = Number.isFinite(objective.maxCount) && objective.maxCount > 1;
  return {
    questTitle: quest.title,
    objective: objective.text,
    ...(countable ? { progress: `${objective.currentCount}/${objective.maxCount}` } : {}),
    key: `${quest.title}|${objective.text}|${objective.currentCount}/${objective.maxCount}`,
  };
}

export function selectQuestReminder(journal: RuntimeQuestJournalReadback | undefined): QuestReminder | undefined {
  if (!journal) return undefined;
  const tracked = journal.quests.find(quest => quest.tracked && quest.state === "active");
  const trackedObjective = tracked && activeObjectiveOf(tracked);
  if (trackedObjective) return trackedObjective;
  for (const quest of journal.quests) {
    if (quest.state !== "active") continue;
    const objective = activeObjectiveOf(quest);
    if (objective) return objective;
  }
  return undefined;
}

export function questReminderText(reminder: QuestReminder): string {
  return reminder.progress ? `${reminder.objective} (${reminder.progress})` : reminder.objective;
}
