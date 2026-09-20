import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { FogInspection } from "../electron/fogSettings";
import type { SaveBackup, SaveInspection, SaveRestorePreview } from "../electron/saveEditor";
import { FeatureCredits } from "./FeatureCredits";
import { FogSettings } from "./FogSettings";
import { SaveTools } from "./SaveTools";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_feature_tools_component_tests");

type DesktopBridge = NonNullable<Window["dawnwalkerDesktop"]>;
type SaveApi = NonNullable<DesktopBridge["saveEditor"]>;

function installDesktop(overrides: Partial<DesktopBridge> = {}) {
  window.dawnwalkerDesktop = {
    beginWindowDrag: vi.fn(), updateWindowDrag: vi.fn(), endWindowDrag: vi.fn(), minimizeWindow: vi.fn(), closeWindow: vi.fn(),
    onGameplayHotkey: vi.fn(() => () => undefined),
    getRuntimeInfo: vi.fn<DesktopBridge["getRuntimeInfo"]>(async () => ({ platform: "test", mode: "disconnected", connected: false, gameRunning: false, buildVerified: false, interactionEligible: false, capabilities: [], activeCapabilities: [] })),
    dispatch: vi.fn<DesktopBridge["dispatch"]>(async (command) => ({ accepted: false, capability: command.capability, requestId: command.requestId, status: "rejected", message: "No gameplay bridge in component tests." })),
    ...overrides,
  };
}

function fogSnapshot(overrides: Partial<FogInspection> = {}): FogInspection {
  return {
    fullPath: "C:\\fixture\\Dawnwalker\\Saved\\Config\\Windows\\Engine.ini", sha256: "a".repeat(64), exists: true,
    configured: { "r.Fog": "1", "r.VolumetricFog": "1" }, owned: false,
    restartRequired: true, verification: "Not verified in game", ...overrides,
  };
}

const selectedSave = saveSnapshot();
const otherSave = saveSnapshot("Quicksave0.sav", "b".repeat(64));
const originalBackup: SaveBackup = {
  backupId: "1788640000000-00000000-0000-4000-8000-000000000001", fileName: selectedSave.fileName,
  createdAt: "2026-09-05T19:00:00.000Z", backupPath: "C:\\fixture\\backups\\original", sha256: "c".repeat(64),
  files: [{ name: selectedSave.fileName, sha256: "c".repeat(64), sizeBytes: 96_606 }, { name: "ManualSave2.meta", sha256: "d".repeat(64), sizeBytes: 416 }],
};
const recoveryBackup: SaveBackup = { ...originalBackup, backupId: "1788640000000-00000000-0000-4000-8000-000000000002", backupPath: "C:\\fixture\\backups\\recovery", sha256: selectedSave.sha256 };
const restorePreview: SaveRestorePreview = {
  previewToken: "one-use-preview-token", fileName: selectedSave.fileName, fullPath: selectedSave.fullPath,
  currentSha256: selectedSave.sha256, restoredSha256: originalBackup.sha256, backupId: originalBackup.backupId,
  files: originalBackup.files.map(({ name }) => name), reloadRequired: true,
  message: "The current files will be backed up before replacing this save and its companion metadata. Reload the save afterward.",
};

function saveSnapshot(fileName = "ManualSave2.sav", hash = "a".repeat(64)): SaveInspection {
  return {
    fileName, fullPath: `C:\\fixture\\Dawnwalker\\Saved\\SaveGames\\${fileName}`, sha256: hash,
    sizeBytes: 96_606, modifiedAt: "2026-09-05T20:00:00.000Z", format: "DSAV compressed envelope",
    metadata: { day: 0, buildVersion: 256181, saveVersion: 134 }, editableFields: ["clockMs", "health", "blood", "mutationLevel", "coin"],
    fields: {
      clockMs: 28_800_000, clockDisplay: "Day 1, 08:00", health: 100, blood: 100, mutationLevel: 0, level: 1,
      progressPoints: 250, skillPoints: 3, spentSkillPoints: 0, bloodRestoration: 100, corruptionCharge: 0,
      traits: [
        { id: "CombatFocus_DustThrow", rank: 1, highestRank: 1, accessLimit: 3, storedRank: true, acquired: false },
        { id: "Vigour", rank: 0, highestRank: 0, accessLimit: 1, storedRank: false, acquired: false },
      ],
      attributes: [
        { id: 1, name: "Health", value: 100 }, { id: 2, name: "Blood", value: 100 }, { id: 8, name: "Vampire mutation level", value: 0 },
      ],
      stacks: [{ itemIndex: 0, name: "Coin", displayName: "Denarius", category: "Currency", value: 250, offset: 512, keyIndex: 3, keySlotOffset: 900 }],
      itemCatalog: [
        { definitionIndex: 0, name: "Coin", displayName: "Denarius", category: "Currency", sensitive: true, owned: true },
        { definitionIndex: 1, name: "Medicaments1", displayName: "Minor Mending Ointment", category: "Consumables", sensitive: false, owned: false },
        { definitionIndex: 2, name: "SwordLongCommon2", displayName: "Common Sword", category: "Weapons", sensitive: false, owned: false },
      ],
      freeItemSlots: [4],
    },
    payloadValidation: { status: "verified", message: "Compressed save structure decoded and verified; recognized gameplay values are read from it." },
  };
}

function installSaveApi() {
  const api = {
    listSaves: vi.fn<SaveApi["listSaves"]>().mockResolvedValue([selectedSave, otherSave]),
    inspectSave: vi.fn<SaveApi["inspectSave"]>().mockImplementation(async (name) => name === otherSave.fileName ? otherSave : selectedSave),
    readSummary: vi.fn<SaveApi["readSummary"]>().mockResolvedValue({ clockDisplay: "Day 1, 08:00", health: 100, blood: 100, mutationLevel: 0, level: 1, coin: 250 }),
    readFields: vi.fn<SaveApi["readFields"]>().mockResolvedValue({
      clockMs: 28_800_000, clockDisplay: "Day 1, 08:00", health: 100, blood: 100, mutationLevel: 0, level: 1,
      progressPoints: 250, skillPoints: 3, spentSkillPoints: 0, bloodRestoration: 100, corruptionCharge: 0,
      traits: [
        { id: "CombatFocus_DustThrow", rank: 1, highestRank: 1, accessLimit: 3, storedRank: true, acquired: false },
        { id: "Vigour", rank: 0, highestRank: 0, accessLimit: 1, storedRank: false, acquired: false },
      ],
      attributes: [
        { id: 1, name: "Health", value: 100 }, { id: 2, name: "Blood", value: 100 }, { id: 8, name: "Vampire mutation level", value: 0 },
      ],
      stacks: [{ itemIndex: 0, name: "Coin", displayName: "Denarius", category: "Currency", value: 250, offset: 512, keyIndex: 3, keySlotOffset: 900 }],
      itemCatalog: [
        { definitionIndex: 0, name: "Coin", displayName: "Denarius", category: "Currency", sensitive: true, owned: true },
        { definitionIndex: 1, name: "Medicaments1", displayName: "Minor Mending Ointment", category: "Consumables", sensitive: false, owned: false },
        { definitionIndex: 2, name: "SwordLongCommon2", displayName: "Common Sword", category: "Weapons", sensitive: false, owned: false },
      ],
      freeItemSlots: [4],
    }),
    editFields: vi.fn<SaveApi["editFields"]>().mockRejectedValue(new Error("Edit not exercised in this test.")),
    createBackup: vi.fn<SaveApi["createBackup"]>().mockResolvedValue(originalBackup),
    listBackups: vi.fn<SaveApi["listBackups"]>().mockResolvedValue([originalBackup]),
    previewRestore: vi.fn<SaveApi["previewRestore"]>().mockResolvedValue(restorePreview),
    restoreBackup: vi.fn<SaveApi["restoreBackup"]>().mockResolvedValue({
      inspection: saveSnapshot(selectedSave.fileName, originalBackup.sha256), recoveryBackup,
      message: "Exact backup bytes restored and verified. Reload this save.",
    }),
  };
  installDesktop({ saveEditor: api });
  return api;
}

// The picker is a dropdown of save cards (screenshot + type/date/day/play time): the
// closed control is the "Selected save" button, its options carry the file name in their
// accessible name; tests pick a save the way a user does.
function savePickerTrigger() {
  return screen.getByRole("button", { name: /^Selected save/ });
}
function saveOption(fileName: string) {
  return screen.getByRole("option", { name: (name) => name.includes(fileName) });
}

// Once a save is inspected, its editor is split into Character / Inventory / Backups &
// restore tabs; a test opens the one it works in, the way a user would.
async function openSection(user: ReturnType<typeof userEvent.setup>, name: "Character" | "Inventory" | "Perks & traits" | "Backups & restore") {
  const tab = screen.getByRole("tab", { name });
  if (tab.getAttribute("aria-selected") !== "true") await user.click(tab);
}
async function chooseSave(user: ReturnType<typeof userEvent.setup>, fileName = selectedSave.fileName) {
  await screen.findByRole("button", { name: /^Selected save/ });
  await user.click(savePickerTrigger());
  await user.click(saveOption(fileName));
  await waitFor(() => expect(screen.getByRole("tab", { name: "Backups & restore" })).toBeEnabled());
}

async function chooseBackup(user: ReturnType<typeof userEvent.setup>) {
  await user.selectOptions(screen.getByRole("combobox", { name: "Backup to restore" }), originalBackup.backupId);
  await user.click(screen.getByRole("button", { name: "Review restoration" }));
  return screen.findByRole("region", { name: "Pending restoration" });
}

afterEach(() => {
  cleanup();
  delete window.dawnwalkerDesktop;
  vi.restoreAllMocks();
});

describe("vampire presets", () => {
  it("shows the unverified-in-game notice before any preset is applied", async () => {
    const user = userEvent.setup();
    installSaveApi();
    render(<SaveTools />);
    await chooseSave(user);
    expect(screen.getByText(/quest tracking, fact effects and the numeric Infamy value/)).toBeVisible();
    expect(screen.getByText(/^Unverified in game$/)).toBeVisible();
    const group = screen.getByRole("group", { name: "Vampire presets" });
    expect(within(group).getByRole("button", { name: /Prime vampire/ })).toBeVisible();
    expect(within(group).getByRole("button", { name: /Shed the curse/ })).toBeVisible();
  });

  it("applies a preset through the verified edit pipeline and keeps the unverified-in-game warning visible", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    api.editFields.mockResolvedValue({
      inspection: saveSnapshot(selectedSave.fileName, "e".repeat(64)),
      backup: originalBackup,
      verification: { decodedBytes: 96_606, changedBytes: 8, allowedFields: ["mutationLevel", "health"], changedFields: ["mutationLevel", "health"], fieldsBefore: selectedSave.fields!, fieldsAfter: selectedSave.fields! },
      message: "Edit applied and verified: mutationLevel, health. Reload the save in game.",
    });
    render(<SaveTools />);
    await chooseSave(user);
    await user.click(screen.getByRole("button", { name: /Freshly turned/ }));
    await waitFor(() => expect(api.editFields).toHaveBeenCalledOnce());
    // The fixture save already holds Health 100 / Blood 100, so the pruner
    // sends only the mutation-level change that actually differs.
    expect(api.editFields).toHaveBeenCalledWith(expect.objectContaining({
      fileName: selectedSave.fileName,
      expectedSha256: selectedSave.sha256,
      edit: { mutationLevel: 1 },
    }));
    const confirmations = await screen.findAllByText(/applied and verified on disk/);
    expect(confirmations[0]).toHaveTextContent(/Unverified in game/);
  });

  it("disables a preset whose state the save already matches instead of pretending to apply it", async () => {
    const user = userEvent.setup();
    installSaveApi();
    render(<SaveTools />);
    await chooseSave(user);
    // The fixture save is Health 100, Blood 100, mutation 0: "Shed the curse"
    // (mutation 0, health 100) is already satisfied and must be disabled.
    expect(screen.getByRole("button", { name: /Shed the curse/ })).toBeDisabled();
  });

  it("never sends a Blood field when the inspected save has no Blood stack", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    api.inspectSave.mockResolvedValue({
      ...selectedSave,
      fields: { ...selectedSave.fields!, blood: undefined },
    });
    render(<SaveTools />);
    await chooseSave(user);
    await user.click(screen.getByRole("button", { name: /Freshly turned/ }));
    await waitFor(() => expect(api.editFields).toHaveBeenCalledOnce());
    const request = api.editFields.mock.calls[0][0] as { edit: Record<string, unknown> };
    expect(request.edit.blood).toBeUndefined();
  });
});

describe("Settings credits", () => {
  it("shows the owner and every verified community contributor with profile pictures", () => {
    render(<FeatureCredits />);
    const cards = screen.getAllByRole("article");
    expect(cards).toHaveLength(9);
    const owner = screen.getByRole("heading", { name: "cyberfox1337x" }).closest("article");
    expect(owner).not.toBeNull();
    expect(within(owner!).getByText("Full Stack Developer")).toBeVisible();
    expect(owner!.querySelector<HTMLImageElement>(".credit-avatar img")?.getAttribute("src")).toContain("credits-cyberfox1337x.png");

    for (const handle of ["Su4enka", "DaraTeaGod", "nectarines", "KZekai", "FullTimePatriot", "Caites", "Alahria", "bruender09"]) {
      const card = screen.getByRole("heading", { name: handle }).closest("article");
      expect(card).not.toBeNull();
      expect(card!.querySelector<HTMLImageElement>(".credit-avatar img")?.getAttribute("src")).toContain(`nexus-${handle.toLowerCase()}.webp`);
      expect(within(card!).getByRole("button", { name: "Nexus profile" })).toBeVisible();
      expect(within(card!).getByRole("button", { name: "Reference mod" })).toBeVisible();
    }
  });

  it("credits only features that remain in the menu", () => {
    render(<FeatureCredits />);
    expect(screen.getByText(/Timeless Court Activities - No Time Cost inspired/)).toBeVisible();
    expect(screen.getByText(/Live skin colour controls inspired/)).toBeVisible();
    expect(screen.queryByText("Grimpil")).not.toBeInTheDocument();
    expect(screen.queryByText(/Attack speed/)).not.toBeInTheDocument();
  });

  it("does not carry the licence pointer paragraph any more", () => {
    render(<FeatureCredits />);
    expect(screen.queryByText(/THIRD_PARTY_NOTICES/)).not.toBeInTheDocument();
    expect(screen.queryByText(/UE4SS-LICENSE/)).not.toBeInTheDocument();
  });

  it("falls back to the icon when the credit picture cannot be loaded", () => {
    render(<FeatureCredits />);
    const owner = screen.getByRole("heading", { name: "cyberfox1337x" }).closest("article")!;
    const picture = owner.querySelector<HTMLImageElement>(".credit-avatar img");
    expect(picture).not.toBeNull();
    fireEvent.error(picture!);
    expect(owner.querySelector(".credit-avatar img")).toBeNull();
    expect(owner.querySelector(".credit-avatar svg")).not.toBeNull();
  });

  it("keeps the owner's developer tone", () => {
    render(<FeatureCredits />);
    const owner = screen.getByRole("heading", { name: "cyberfox1337x" }).closest("article")!;
    expect(owner.querySelector(".credit-avatar")).toHaveAttribute("data-tone", "dev");
  });
});

describe("fog configuration controls", () => {
  it("keeps refresh locked until the initial configuration read settles", async () => {
    const user = userEvent.setup();
    let finish: ((snapshot: FogInspection) => void) | undefined;
    const inspect = vi.fn(() => new Promise<FogInspection>(resolve => { finish = resolve; }));
    installDesktop({ fogSettings: { inspect, apply: vi.fn(), restore: vi.fn() } });
    render(<FogSettings />);
    const refresh = screen.getByRole("button", { name: "Refresh configuration" });
    expect(refresh).toBeDisabled();
    await user.click(refresh);
    expect(inspect).toHaveBeenCalledOnce();
    await act(async () => { finish!(fogSnapshot()); });
    expect(refresh).toBeEnabled();
    expect(screen.getByRole("combobox", { name: "Fog after restart" })).toBeVisible();
  });

  it("preserves saved readback after a rejected apply and makes the failure visible", async () => {
    const user = userEvent.setup();
    const initial = fogSnapshot();
    const apply = vi.fn().mockRejectedValue(new Error("Dawnwalker is running. Close the game before writing."));
    installDesktop({ fogSettings: { inspect: vi.fn().mockResolvedValue(initial), apply, restore: vi.fn() } });
    render(<FogSettings />);
    const fog = await screen.findByRole("combobox", { name: /^Fog after restart/ });
    await user.selectOptions(fog, "false");
    await user.click(screen.getByRole("button", { name: "Back up & apply configuration" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Dawnwalker is running");
    expect(apply).toHaveBeenCalledWith({ expectedSha256: initial.sha256, fog: false, volumetricFog: true });
    expect(within(fog.closest("label")!).getByText("Saved value: 1")).toBeVisible();
    expect(screen.queryByText(/Configuration saved and read back/)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Restore original configuration" })).toBeDisabled();
    expect(screen.getByText("Not verified in game.")).toBeVisible();
  });

  it("uses returned configuration values and fresh hashes for apply and exact restore without claiming a live visual effect", async () => {
    const user = userEvent.setup();
    const initial = fogSnapshot();
    const applied = fogSnapshot({ sha256: "b".repeat(64), configured: { "r.Fog": "0", "r.VolumetricFog": "1" }, owned: true, backupPath: "C:\\fixture\\backups\\fog-original.bak" });
    const apply = vi.fn().mockResolvedValue(applied);
    const restore = vi.fn().mockResolvedValue(initial);
    installDesktop({ fogSettings: { inspect: vi.fn().mockResolvedValue(initial), apply, restore } });
    render(<FogSettings />);
    const fog = await screen.findByRole("combobox", { name: /^Fog after restart/ });
    const volumetric = screen.getByRole("combobox", { name: /^Volumetric fog after restart/ });
    await user.selectOptions(fog, "false");
    await user.selectOptions(volumetric, "false");
    await user.click(screen.getByRole("button", { name: "Back up & apply configuration" }));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Configuration saved and read back. Restart Dawnwalker to test its visual effect."));
    expect(fog).toHaveValue("false");
    expect(volumetric).toHaveValue("true");
    expect(within(fog.closest("label")!).getByText("Saved value: 0")).toBeVisible();
    expect(screen.getByText(/Original backup: C:/)).toHaveTextContent(applied.backupPath!);
    await user.click(screen.getByRole("button", { name: "Restore original configuration" }));
    expect(restore).toHaveBeenCalledWith(applied.sha256);
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Original configuration restored and verified. Restart Dawnwalker."));
    expect(fog).toHaveValue("true");
    expect(within(fog.closest("label")!).getByText("Saved value: 1")).toBeVisible();
    expect(screen.getByRole("button", { name: "Restore original configuration" })).toBeDisabled();
    expect(screen.getByText("Not verified in game.")).toBeVisible();
  });

  it("keeps the owned saved values when restoration is rejected", async () => {
    const user = userEvent.setup();
    const applied = fogSnapshot({ configured: { "r.Fog": "0", "r.VolumetricFog": "0" }, owned: true });
    const restore = vi.fn().mockRejectedValue(new Error("Engine.ini changed outside the menu. Refresh before restoring."));
    installDesktop({ fogSettings: { inspect: vi.fn().mockResolvedValue(applied), apply: vi.fn(), restore } });
    render(<FogSettings />);
    const fog = await screen.findByRole("combobox", { name: /^Fog after restart/ });
    await user.click(screen.getByRole("button", { name: "Restore original configuration" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Engine.ini changed outside the menu");
    expect(fog).toHaveValue("false");
    expect(within(fog.closest("label")!).getByText("Saved value: 0")).toBeVisible();
    expect(screen.queryByText(/Original configuration restored and verified/)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Restore original configuration" })).toBeEnabled();
  });
});

describe("integrated save controls", () => {
  it("shows each save the way the game's load list does, and explains every editable value", async () => {
    const user = userEvent.setup();
    const pictured: SaveInspection = {
      ...selectedSave, thumbnail: "data:image/png;base64,iVBORw0KGgo=",
      metadata: { ...selectedSave.metadata, type: "Quicksave", savedAt: "2026.09.03-00.28.41", day: 2, playTimeSeconds: 5_025 },
    };
    const api = installSaveApi();
    api.listSaves.mockResolvedValue([pictured, otherSave]);
    api.inspectSave.mockResolvedValue(pictured);
    render(<SaveTools />);
    // Closed, the dropdown says nothing is chosen and no option is on screen.
    const trigger = await screen.findByRole("button", { name: /^Selected save/ });
    expect(trigger).toHaveTextContent("Choose a save");
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(screen.queryByRole("combobox", { name: "Selected save" })).not.toBeInTheDocument();
    // Open, every save is a card: the game's screenshot plus type, date, day and play time.
    await user.click(trigger);
    const option = saveOption(pictured.fileName);
    expect(option.querySelector("img")).toHaveAttribute("src", pictured.thumbnail);
    expect(option).toHaveTextContent("Quick save");
    expect(option).toHaveTextContent("2026-09-03 00:28");
    expect(option).toHaveTextContent("Day 3 · 1h 23m played");
    expect(within(saveOption(otherSave.fileName)).getByText("No picture")).toBeInTheDocument();
    await user.click(option);
    // Choosing closes the list and the closed control now wears the chosen card.
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(trigger).toHaveTextContent("Quick save");
    expect(trigger.querySelector("img")).toHaveAttribute("src", pictured.thumbnail);
    expect(screen.getByText(/Selected save:/)).toHaveTextContent("Quick save · 2026-09-03 00:28");
    // Keyboard: Escape closes without changing the choice.
    await user.click(trigger);
    expect(saveOption(pictured.fileName)).toHaveAttribute("aria-selected", "true");
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(api.inspectSave).toHaveBeenCalledTimes(1);
    // Every edit box says what the number is and what the save holds right now.
    await waitFor(() => expect(screen.getByRole("textbox", { name: "Health" })).toBeEnabled());
    // Values sit in two stat-sheet groups, each row naming the value and what it does.
    const progression = within(screen.getByRole("region", { name: "Progression" }));
    const vitals = within(screen.getByRole("region", { name: "Vitals" }));
    expect(progression.getByRole("textbox", { name: "Progress points" })).toHaveAttribute("placeholder", "keep 250");
    expect(progression.getByRole("textbox", { name: "Skill points" })).toHaveAttribute("placeholder", "keep 3");
    expect(progression.getByRole("textbox", { name: "Character level" })).toHaveAttribute("placeholder", "keep 1");
    expect(vitals.getByRole("textbox", { name: "Health" })).toHaveAttribute("placeholder", "keep 100");
    expect(vitals.getByRole("textbox", { name: "Corruption charge" })).toHaveAttribute("placeholder", "keep 0");
    expect(vitals.getByText(/Hit points\. The game trims anything above your maximum/)).toBeInTheDocument();
    expect(vitals.getByText(/Corruption stage from 0 \(fully human\) to \d+/)).toBeInTheDocument();
    expect(vitals.getByRole("textbox", { name: "Vampire mutation level" })).toHaveAttribute("placeholder", "keep 0");
    expect(screen.getByText(/Saved clock: Day 1, 08:00/)).toBeInTheDocument();
    expect(screen.getByText("How to edit character values")).toBeInTheDocument();
    expect(screen.getByText(/Queued changes are listed under/)).toBeInTheDocument();
  });

  it("keeps refresh locked while the initial save list is loading without claiming no saves exist", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    let finish: ((saves: readonly SaveInspection[]) => void) | undefined;
    api.listSaves.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
    render(<SaveTools />);
    const refresh = screen.getByRole("button", { name: "Refresh saves" });
    expect(refresh).toBeDisabled();
    expect(screen.getByText("Loading local saves…")).toBeVisible();
    expect(screen.queryByText(/No gameplay saves found/)).not.toBeInTheDocument();
    await user.click(refresh);
    expect(api.listSaves).toHaveBeenCalledOnce();
    await act(async () => { finish!([selectedSave]); });
    expect(refresh).toBeEnabled();
    await user.click(savePickerTrigger());
    expect(saveOption(selectedSave.fileName)).toBeInTheDocument();
  });

  it("clears stale inspection and restore choices when the selected save disappears", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    await chooseBackup(user);
    api.listSaves.mockResolvedValue([otherSave]);
    await user.click(screen.getByRole("button", { name: "Refresh saves" }));
    expect(await screen.findByRole("status")).toHaveTextContent("selected save is no longer available");
    expect(savePickerTrigger()).toHaveTextContent("Choose a save");
    expect(screen.queryByText(selectedSave.fullPath)).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Create verified backup" })).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Pending restoration" })).not.toBeInTheDocument();
    expect(api.restoreBackup).not.toHaveBeenCalled();
  });

  it("removes stale actionable save details if refresh cannot inspect the selected file", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    api.inspectSave.mockRejectedValue(new Error("Save file changed while reading."));
    await user.click(screen.getByRole("button", { name: "Refresh saves" }));
    expect(await screen.findByRole("status")).toHaveTextContent("Save file changed while reading");
    expect(screen.queryByRole("button", { name: "Create verified backup" })).not.toBeInTheDocument();
    expect(screen.queryByText(selectedSave.sha256)).not.toBeInTheDocument();
  });

  it("inspects the selected file and invalidates its pending restore when another slot is selected", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    expect(api.inspectSave).toHaveBeenCalledWith(selectedSave.fileName);
    expect(api.listBackups).toHaveBeenCalledWith(selectedSave.fileName);
    expect(screen.getByText(selectedSave.fullPath)).toBeInTheDocument();
    expect(screen.getByText("Compressed save structure decoded and verified; recognized gameplay values are read from it.")).toBeInTheDocument();
    await chooseBackup(user);
    await chooseSave(user, otherSave.fileName);
    await openSection(user, "Backups & restore");
    expect(screen.getByText(otherSave.fullPath)).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Pending restoration" })).not.toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: "Backup to restore" })).toHaveValue("");
    expect(api.restoreBackup).not.toHaveBeenCalled();
  });

  it("creates a backup of the selected hash and shows the verified recovery location only after success", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    api.listBackups.mockResolvedValueOnce([]).mockResolvedValue([originalBackup]);
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    await user.click(screen.getByRole("button", { name: "Create verified backup" }));
    expect(api.createBackup).toHaveBeenCalledWith(expect.objectContaining({ fileName: selectedSave.fileName, expectedSha256: selectedSave.sha256 }));
    expect(await screen.findByRole("status")).toHaveTextContent(`Backup verified: ${originalBackup.backupPath}`);
    expect(screen.getByRole("combobox", { name: "Backup to restore" })).toHaveValue(originalBackup.backupId);
    expect(api.restoreBackup).not.toHaveBeenCalled();
  });

  it("locks selection and repeated writes while a backup request is still pending", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    let finishBackup: ((backup: SaveBackup) => void) | undefined;
    api.createBackup.mockImplementation(() => new Promise((resolve) => { finishBackup = resolve; }));
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    const backupButton = screen.getByRole("button", { name: "Create verified backup" });
    await user.click(backupButton);
    expect(backupButton).toBeDisabled();
    expect(savePickerTrigger()).toBeDisabled();
    expect(screen.getByRole("button", { name: "Refresh saves" })).toBeDisabled();
    expect(screen.queryByText(/Backup verified:/)).not.toBeInTheDocument();
    await user.click(backupButton);
    expect(api.createBackup).toHaveBeenCalledOnce();
    await act(async () => { finishBackup!(originalBackup); });
    expect(await screen.findByRole("status")).toHaveTextContent("Backup verified:");
    expect(backupButton).toBeEnabled();
  });

  it("requires an explicit reviewed confirmation before restoring and presents the retained recovery backup", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    const panel = await chooseBackup(user);
    expect(api.previewRestore).toHaveBeenCalledWith({ fileName: selectedSave.fileName, expectedSha256: selectedSave.sha256, backupId: originalBackup.backupId });
    expect(within(panel).getByText(/Current:/)).toHaveTextContent(selectedSave.sha256);
    expect(within(panel).getByText(/Restore:/)).toHaveTextContent(originalBackup.sha256);
    expect(within(panel).getByText(/Files:/)).toHaveTextContent("ManualSave2.sav, ManualSave2.meta");
    expect(api.restoreBackup).not.toHaveBeenCalled();
    await user.click(within(panel).getByRole("button", { name: "Back up current files & restore" }));
    expect(api.restoreBackup).toHaveBeenCalledWith({ fileName: selectedSave.fileName, expectedSha256: selectedSave.sha256, backupId: originalBackup.backupId, previewToken: restorePreview.previewToken });
    expect(await screen.findByRole("status")).toHaveTextContent(`Recovery backup: ${recoveryBackup.backupPath}`);
    expect(screen.getByRole("status")).toHaveTextContent("Reload this save.");
    expect(screen.getByText(originalBackup.sha256)).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Pending restoration" })).not.toBeInTheDocument();
  });

  it("cancels a pending restoration without any write request", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    const panel = await chooseBackup(user);
    await user.click(within(panel).getByRole("button", { name: "Cancel restoration" }));
    expect(screen.queryByRole("region", { name: "Pending restoration" })).not.toBeInTheDocument();
    expect(api.restoreBackup).not.toHaveBeenCalled();
    expect(screen.getByText(selectedSave.sha256)).toBeInTheDocument();
  });

  it("clears a consumed preview on restore failure and never reports restored bytes or a success state", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    api.restoreBackup.mockRejectedValue(new Error("The save changed after preview. No write was applied."));
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    const panel = await chooseBackup(user);
    await user.click(within(panel).getByRole("button", { name: "Back up current files & restore" }));
    expect(await screen.findByRole("status")).toHaveTextContent("The save changed after preview. No write was applied.");
    expect(screen.queryByText(/Exact backup bytes restored and verified/)).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Pending restoration" })).not.toBeInTheDocument();
    expect(screen.getByText(selectedSave.sha256)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Review restoration" })).toBeEnabled();
    expect(api.restoreBackup).toHaveBeenCalledOnce();
  });

  it("shows a rejected backup operation without adding a fabricated backup or success message", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    api.listBackups.mockResolvedValue([]);
    api.createBackup.mockRejectedValue(new Error("Close Dawnwalker before backing up saves."));
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    await user.click(screen.getByRole("button", { name: "Create verified backup" }));
    expect(await screen.findByRole("status")).toHaveTextContent("Close Dawnwalker before backing up saves.");
    expect(screen.queryByText(/Backup verified:/)).not.toBeInTheDocument();
    expect(within(screen.getByRole("combobox", { name: "Backup to restore" })).getAllByRole("option")).toHaveLength(1);
    expect(screen.getByRole("button", { name: "Review restoration" })).toBeDisabled();
  });

  it("retains a successful backup location and selectable backup when the subsequent history refresh fails", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    api.listBackups.mockResolvedValueOnce([]).mockRejectedValue(new Error("Backup history is temporarily unavailable."));
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    await user.click(screen.getByRole("button", { name: "Create verified backup" }));
    const status = await screen.findByRole("status");
    expect(status).toHaveTextContent(`Backup verified: ${originalBackup.backupPath}`);
    await waitFor(() => expect(status).toHaveTextContent("Backup history could not be refreshed"));
    expect(screen.getByRole("combobox", { name: "Backup to restore" })).toHaveValue(originalBackup.backupId);
    expect(screen.getByRole("button", { name: "Review restoration" })).toBeEnabled();
    expect(api.createBackup).toHaveBeenCalledOnce();
    expect(api.listBackups).toHaveBeenCalledTimes(2);
    expect(screen.getByText(selectedSave.sha256)).toBeInTheDocument();
  });

  it("retains restored readback and the recovery backup when only the following history refresh fails", async () => {
    const user = userEvent.setup();
    const api = installSaveApi();
    api.listBackups.mockResolvedValueOnce([originalBackup]).mockRejectedValue(new Error("Backup history is temporarily unavailable."));
    render(<SaveTools />);
    await chooseSave(user);
    await openSection(user, "Backups & restore");
    const panel = await chooseBackup(user);
    await user.click(within(panel).getByRole("button", { name: "Back up current files & restore" }));
    const status = await screen.findByRole("status");
    expect(status).toHaveTextContent("Exact backup bytes restored and verified.");
    expect(status).toHaveTextContent(`Recovery backup: ${recoveryBackup.backupPath}`);
    await waitFor(() => expect(status).toHaveTextContent("Backup history could not be refreshed"));
    expect(screen.getByText(originalBackup.sha256)).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Pending restoration" })).not.toBeInTheDocument();
    const recoveryOption = within(screen.getByRole("combobox", { name: "Backup to restore" })).getByRole("option", { name: `${recoveryBackup.createdAt} · ${recoveryBackup.sha256.slice(0, 12)}` });
    expect(recoveryOption).toHaveValue(recoveryBackup.backupId);
    expect(api.restoreBackup).toHaveBeenCalledOnce();
    expect(api.listBackups).toHaveBeenCalledTimes(2);
  });
});


describe("save edit transaction controls", () => {
  it("does not queue zero when a stack or attribute edit is cleared", async () => {
    const user = userEvent.setup(); installSaveApi(); render(<SaveTools />); await chooseSave(user);
    await openSection(user, "Inventory");
    expect(screen.getByText(/one Common Sword changed from level 2 to level 3/)).toBeVisible();
    const stack = screen.getByRole("textbox", { name: "Stack for Coin" });
    await user.type(stack, "3"); await user.clear(stack);
    await openSection(user, "Character");
    await user.click(screen.getByRole("button", { name: /Advanced: saved attributes/ }));
    const attribute = screen.getByRole("textbox", { name: "Attribute Health" });
    await user.type(attribute, "50"); await user.clear(attribute);
    expect(screen.getByRole("button", { name: /Apply no changes/ })).toBeDisabled();
  });

  it("resets queued inventory grants as well as ordinary edits", async () => {
    const user = userEvent.setup(); installSaveApi(); render(<SaveTools />); await chooseSave(user);
    await openSection(user, "Inventory");
    await user.type(screen.getByRole("textbox", { name: "Search items" }), "Medicaments1");
    const grant = screen.getByRole("textbox", { name: "Give count for Medicaments1" });
    await user.type(grant, "5");
    await user.click(screen.getByRole("button", { name: "Reset edits" }));
    expect(grant).toHaveValue("");
    expect(screen.getByRole("button", { name: /Apply no changes/ })).toBeDisabled();
  });

  it("locks refresh, selection and backup throughout a pending field edit", async () => {
    const user = userEvent.setup(); const api = installSaveApi();
    let reject!: (reason: Error) => void;
    api.editFields.mockImplementation(() => new Promise((_resolve, failure) => { reject = failure; }));
    render(<SaveTools />); await chooseSave(user);
    await user.type(screen.getByRole("textbox", { name: "Character level" }), "2");
    await user.click(screen.getByRole("button", { name: /Apply 1 change with/ }));
    expect(screen.getByRole("button", { name: "Refresh saves" })).toBeDisabled();
    expect(savePickerTrigger()).toBeDisabled();
    await openSection(user, "Backups & restore");
    expect(screen.getByRole("button", { name: "Create verified backup" })).toBeDisabled();
    await user.click(screen.getByRole("button", { name: "Create verified backup" }));
    expect(api.createBackup).not.toHaveBeenCalled();
    await act(async () => reject(new Error("Fixture rejection")));
    expect(screen.getByRole("button", { name: "Refresh saves" })).toBeEnabled();
    expect(api.editFields).toHaveBeenCalledOnce();
  });
});


it("blocks a nonnumeric save edit and allows correcting or clearing the draft", async () => {
  const user = userEvent.setup(); const api = installSaveApi(); render(<SaveTools />); await chooseSave(user);
  const health = screen.getByRole("textbox", { name: "Health" });
  await user.type(health, "not-a-number");
  expect(screen.getByRole("alert")).toHaveTextContent("Enter a valid number");
  const apply = screen.getByRole("button", { name: /Apply 1 change with/ });
  expect(apply).toBeDisabled(); await user.click(apply); expect(api.editFields).not.toHaveBeenCalled();
  await user.clear(health); await user.type(health, "90");
  expect(screen.queryByRole("alert")).not.toBeInTheDocument(); expect(apply).toBeEnabled();
});


describe("numeric save draft bounds", () => {
  it("classifies perk definitions, exposes lock reasons, and gives internal rows a symbolic image", async () => {
    const user = userEvent.setup(); const api = installSaveApi();
    api.inspectSave.mockResolvedValue({ ...selectedSave, advanced: {
      upgrades: [], facts: [], infamyAvailable: false, issues: [], perks: [
        { id: "CombatFocus_DustThrow", acquisitionRanks: [], bookRanks: [], acquisitionStructureMapped: true, acquisitionReason: "Choose a rank above the current rank." },
        { id: "Vigour", acquisitionRanks: [1], bookRanks: [], acquisitionStructureMapped: true },
        { id: "CombatFocus_Internal", acquisitionRanks: [], bookRanks: [], acquisitionStructureMapped: false, definitionReason: "Hidden ability acquisition requires a separately verified ability profile and is not supported here." },
      ],
    } } as SaveInspection);
    window.dawnwalkerDesktop = { ...window.dawnwalkerDesktop!, gameAssets: {
      status: vi.fn(), perks: vi.fn().mockResolvedValue([
        { id: "CombatFocus_DustThrow", name: "Dirty Trick", description: "", tree: "CombatFocus", quest: false, parents: [], rankDescriptions: [], iconStatus: "Original game icon" },
        { id: "Vigour", name: "Vigour", description: "", tree: "Shared", quest: false, parents: [], rankDescriptions: [], iconStatus: "Original game icon" },
        { id: "CombatFocus_Internal", name: "CombatFocus_Internal", description: "", tree: "CombatFocus", quest: false, parents: [], rankDescriptions: [], iconStatus: "Internal definition: no localized name or verified icon association" },
      ]),
    } };
    render(<SaveTools />); await chooseSave(user); await openSection(user, "Perks & traits");
    expect(screen.getByText(/acquiring rank 1 of Sustained Focus/)).toBeVisible();
    expect(await screen.findByText(/3 catalog · 2 acquisition structures mapped · 2 eligible now in this save · 1 learned/)).toBeVisible();
    expect(screen.getByText(/CombatFocus_Internal · Catalog metadata incomplete · Not currently eligible/)).toBeVisible();
    expect(screen.getByText("Hidden ability acquisition requires a separately verified ability profile and is not supported here.")).toBeVisible();
    expect(screen.getByRole("img", { name: "CombatFocus_Internal symbolic CombatFocus perk icon" })).toBeVisible();
    expect(screen.getByRole("textbox", { name: "Acquire rank for CombatFocus_Internal" })).toBeDisabled();
  });

  it("does not enable first acquisition without inspected metadata eligibility", async () => {
    const user = userEvent.setup(); installSaveApi(); render(<SaveTools />); await chooseSave(user);
    await openSection(user, "Perks & traits");
    expect(screen.getByRole("textbox", { name: "Acquire rank for Vigour" })).toBeDisabled();
  });
  it.each(["not-a-number", "901", "1.5"])("blocks other edits when the infamy draft is invalid: %s", async (value) => {
    const user = userEvent.setup(); const api = installSaveApi();
    api.inspectSave.mockResolvedValue({ ...selectedSave, advanced: {
      upgrades: [], perks: [], facts: [], court: { points: 350, level: 3, pending: 1, activeEdicts: 2 },
      infamyAvailable: true, issues: [],
    } } as SaveInspection);
    render(<SaveTools />); await chooseSave(user);
    await user.type(screen.getByRole("textbox", { name: "Blood" }), "90");
    fireEvent.change(screen.getByRole("textbox", { name: "Infamy points" }), { target: { value } });
    expect(screen.getByRole("alert")).toHaveTextContent("Infamy");
    expect(screen.getByRole("button", { name: /Apply .*change/ })).toBeDisabled();
    expect(api.editFields).not.toHaveBeenCalled();
  });

  it.each([
    ["Character level", "1.5"], ["Character level", "101"], ["Health", "100001"],
    ["Stack for Coin", "-1"], ["Stack for Coin", "10000000"],
    ["Give count for Medicaments1", "0"], ["Give count for Medicaments1", "2.5"],
  ])("blocks the whole batch for invalid %s = %s", async (name, value) => {
    const user = userEvent.setup(); const api = installSaveApi(); render(<SaveTools />); await chooseSave(user);
    await user.type(screen.getByRole("textbox", { name: "Blood" }), "90");
    if (!/^(Health|Character level)$/.test(name)) await openSection(user, "Inventory");
    if (name.startsWith("Give count for ")) await user.type(screen.getByRole("textbox", { name: "Search items" }), name.slice("Give count for ".length));
    await user.type(screen.getByRole("textbox", { name }), value);
    expect(screen.getByRole("alert")).toHaveTextContent("Enter a valid");
    const apply = screen.getByRole("button", { name: /Apply .* with automatic backup/ });
    expect(apply).toBeDisabled(); await user.click(apply); expect(api.editFields).not.toHaveBeenCalled();
    await user.click(screen.getByRole("button", { name: "Reset edits" }));
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("blocks an oversized attribute alongside a valid edit", async () => {
    const user = userEvent.setup(); const api = installSaveApi(); render(<SaveTools />); await chooseSave(user);
    await user.type(screen.getByRole("textbox", { name: "Blood" }), "90");
    await user.click(screen.getByRole("button", { name: /Advanced: saved attributes/ }));
    await user.type(screen.getByRole("textbox", { name: "Attribute Health" }), "-100001");
    expect(screen.getByRole("button", { name: /Apply .* with automatic backup/ })).toBeDisabled();
    expect(api.editFields).not.toHaveBeenCalled();
  });

  it("blocks an invalid replacement count and releases the draft when that replacement is cleared", async () => {
    const user = userEvent.setup(); const api = installSaveApi();
    const snapshot = saveSnapshot();
    api.inspectSave.mockResolvedValue({ ...snapshot, fields: { ...snapshot.fields!, coin: 250,
      stacks: [...snapshot.fields!.stacks!, { itemIndex: 1, name: "OldSword", displayName: "Old Sword", category: "Weapons", value: 1, offset: 600, keyIndex: 4, keySlotOffset: 950 }] } });
    render(<SaveTools />); await chooseSave(user);
    await user.type(screen.getByRole("textbox", { name: "Coin" }), "-1");
    expect(screen.getByRole("alert")).toHaveTextContent("Coin");
    await user.clear(screen.getByRole("textbox", { name: "Coin" }));
    await user.type(screen.getByRole("textbox", { name: "Blood" }), "90");
    await openSection(user, "Inventory");
    await user.click(screen.getByRole("button", { name: /Replace an owned item/ }));
    const replacement = screen.getByRole("combobox", { name: "Replace OldSword with" });
    await user.selectOptions(replacement, "2");
    await user.type(screen.getByRole("textbox", { name: "Replacement count for OldSword" }), "10000000");
    expect(screen.getByRole("button", { name: /Apply .* with automatic backup/ })).toBeDisabled();
    expect(api.editFields).not.toHaveBeenCalled();
    await user.selectOptions(replacement, "");
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Apply 1 change with/ })).toBeEnabled();
  });
});
