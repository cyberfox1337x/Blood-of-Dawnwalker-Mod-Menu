import { describe, expect, it } from "vitest";
import { mappedSaveFacts, parseFactTagNames } from "../electron/saveEditorPreview";
import { tagId } from "../electron/saveFacts";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("save_editor_preview_tests");

describe("saved fact choices", () => {
  it("offers only existing mapped non-court facts and retains their actual values", () => {
    const tags = parseFactTagNames('[Tags]\n+GameplayTagList=(Tag="Quest.Test",DevComment="")\n+GameplayTagList=(Tag="Quest.Absent",DevComment="")\n+GameplayTagList=(Tag="Court.AlertLevel",DevComment="")');
    expect(mappedSaveFacts(new Map([[tagId("Quest.Test"), -3], [tagId("Court.AlertLevel"), 2], [123, 9]]), tags))
      .toEqual([{ tag: "Quest.Test", value: -3 }]);
  });

  it("deduplicates case aliases rather than displaying ambiguous duplicate choices", () => {
    expect(parseFactTagNames('+GameplayTagList=(Tag="Quest.Test")\n+GameplayTagList=(Tag="QUEST.TEST")')).toEqual(["Quest.Test"]);
  });
});
