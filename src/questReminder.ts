const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("quest_reminder");

// One selector is shared by the renderer and Electron's background monitor so both
// announce the same tracked, required objective and use the same de-duplication key.
export {
  questReminderText,
  selectQuestReminder,
  type QuestReminder,
} from "../electron/questReminderSelection";
