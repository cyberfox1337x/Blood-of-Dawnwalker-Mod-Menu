import { expect, it } from "vitest";
import { buildReminderToastXml } from "./reminderToast.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("reminder_toast_tests");

// Built from a character code so the separator survives every editing step that
// touches this file; a literal backslash here is easy to lose and hard to spot.
const windowsPath = (...segments: string[]) => ["C:", ...segments].join(String.fromCharCode(92));

it("builds toast XML carrying the quest, the objective and the app's own imagery", () => {
  const xml = buildReminderToastXml({ questTitle: "Withering Away", objective: "Split logs for firewood",
    logoPath: windowsPath("menu", "icon.png") });
  expect(xml).toContain("<text hint-maxLines=\"1\">Withering Away</text>");
  expect(xml).toContain("<text>Split logs for firewood</text>");
  expect(xml).toContain('placement="appLogoOverride"');
  expect(xml).toContain("file:///C:/menu/icon.png");
  expect(xml).toContain("Blood of Dawnwalker Mod Menu");
});

it("escapes quest text so a title can never break the toast markup", () => {
  const xml = buildReminderToastXml({ questTitle: 'Ale & "Iron"', objective: "<script>alert(1)</script>", logoPath: windowsPath("i.png") });
  expect(xml).toContain("Ale &amp; &quot;Iron&quot;");
  expect(xml).toContain("&lt;script&gt;alert(1)&lt;/script&gt;");
  expect(xml).not.toContain("<script>");
});
