import { useEffect, useMemo, useRef, useState } from "react";
import type { SaveInspection, SaveBackup, SaveRestorePreview, SaveEditOutcome } from "../electron/saveEditor";
import type { PerkMetadata } from "../electron/gameAssets";
import { formatDesktopError } from "./desktopError";
import { SavePicker, type SummaryMap } from "./SavePicker";
import { savedAtLabel, saveTypeLabel } from "./saveLabels";
import { ItemIcon } from "./ItemIcon";
import { PerkIcon } from "./PerkIcon";
import { SaveValueIcon } from "./SaveValueIcon";
import { ITEM_CATEGORIES, describeItem } from "../electron/itemCatalog";
import { ITEM_CATALOG_RECORDS } from "../electron/itemCatalogData";
import { VAMPIRE_PRESETS, presetEditsFor, type VampirePresetId } from "./vampirePresets";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_save_tools");

const MS_PER_DAY = 86_400_000;
const SEGMENT_MS = 5_400_000;
const MAX_MUTATION_LEVEL = 15;
const MAX_LEVEL = 100;

function clockLabel(clockMs: number): string {
  const day = Math.floor(clockMs / MS_PER_DAY);
  const timeOfDay = clockMs % MS_PER_DAY;
  const hour = Math.floor(timeOfDay / 3_600_000) % 24;
  const minute = Math.floor((timeOfDay % 3_600_000) / 60_000);
  return `Day ${day + 1}, ${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

// Segment moves preserve the saved clock's phase on its own 90-minute grid and stay
// inside the saved 12-hour half, exactly like the game's day/night bar.
function segmentOptions(clockMs: number): readonly { value: number; label: string }[] {
  const options: { value: number; label: string }[] = [];
  for (let segments = -3; segments <= 3; segments += 1) {
    if (segments === 0) continue;
    const value = clockMs + segments * SEGMENT_MS;
    if (value < 0) continue;
    const hours = Math.abs(segments * 1.5);
    const direction = segments < 0 ? "earlier" : "later";
    options.push({ value, label: `${clockLabel(value)}  ·  ${segments > 0 ? "+" : "−"}${hours} h ${direction}` });
  }
  return options;
}

type SaveSection = "character" | "inventory" | "perks" | "backups";
const SECTION_TABS: readonly { id: SaveSection; label: string; editsSave: boolean }[] = [
  { id: "character", label: "Character", editsSave: true },
  { id: "inventory", label: "Inventory", editsSave: true },
  { id: "perks", label: "Perks & traits", editsSave: true },
  { id: "backups", label: "Backups & restore", editsSave: false },
];

// DwSav's ItemLabel.Format, for perk ids the export has no name for.
const spellOut = (id: string) => id.replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2").replace(/([a-zA-Z])([0-9])/g, "$1 $2");

type FieldSet = {
  health: string; blood: string; mutationLevel: string; bloodRestoration: string; corruptionCharge: string;
  level: string; progressPoints: string; skillPoints: string; spentSkillPoints: string; coin: string; segment: string;
  stacks: Record<number, string>; attributes: Record<number, string>; traitRanks: Record<string, string>; perkAcquisitions: Record<string, string>; bookAccess: Record<string, string>; itemUpgrades: Record<string, string>; factChanges: Record<string, string>; infamyPoints: string;
};

function emptyPending(): FieldSet {
  return {
    health: "", blood: "", mutationLevel: "", bloodRestoration: "", corruptionCharge: "",
    level: "", progressPoints: "", skillPoints: "", spentSkillPoints: "", coin: "", segment: "", stacks: {}, attributes: {}, traitRanks: {}, perkAcquisitions: {}, bookAccess: {}, itemUpgrades: {}, factChanges: {}, infamyPoints: "",
  };
}

// One numeric save value the Character tab edits: where it lives in the draft, the
// save field it maps to, and the words that explain it to the player.
type NumberFieldSpec = Readonly<{
  key: "health" | "blood" | "mutationLevel" | "bloodRestoration" | "corruptionCharge" | "level" | "progressPoints" | "skillPoints" | "spentSkillPoints" | "coin";
  label: string; hint: string; integer: boolean; min: number; max: number;
  /** Accessible name kept stable for tests and screen readers when the label is short. */
  ariaLabel?: string;
}>;
const PROGRESSION_FIELDS: readonly NumberFieldSpec[] = [
  { key: "coin", label: "Coins", ariaLabel: "Coin", hint: "Denarii carried in the inventory.", integer: true, min: 0, max: 4_294_967_295 },
  { key: "skillPoints", label: "Skill points", hint: "Unspent points waiting to be put into perks.", integer: true, min: 0, max: 4_294_967_295 },
  { key: "level", label: "Level", ariaLabel: "Character level", hint: `Character level, 1 to ${MAX_LEVEL}. Raising it hands out level-up rewards on load.`, integer: true, min: 1, max: MAX_LEVEL },
  { key: "progressPoints", label: "Current XP", ariaLabel: "Progress points", hint: "Experience towards the next level. Stored value only — the game does not re-run level-ups from it.", integer: true, min: 0, max: 4_294_967_295 },
  { key: "spentSkillPoints", label: "Spent skill points", hint: "The ledger of points already spent. Changing it does not refund or remove perks.", integer: true, min: 0, max: 4_294_967_295 },
];
const VITALS_FIELDS: readonly NumberFieldSpec[] = [
  { key: "health", label: "Health", hint: "Hit points. The game trims anything above your maximum when the save loads.", integer: false, min: 0, max: 100_000 },
  { key: "blood", label: "Blood", hint: "Blood energy the vampire abilities draw on.", integer: false, min: 0, max: 100_000 },
  { key: "bloodRestoration", label: "Blood restoration", hint: "How much health blood can restore (blood-to-health pool).", integer: false, min: 0, max: 100_000 },
  { key: "mutationLevel", label: "Mutation level", ariaLabel: "Vampire mutation level", hint: `Corruption stage from 0 (fully human) to ${MAX_MUTATION_LEVEL} (strongest vampire).`, integer: true, min: 0, max: MAX_MUTATION_LEVEL },
  { key: "corruptionCharge", label: "Corruption charge", hint: "Raw corruption charge the vampire form builds up.", integer: false, min: 0, max: 100_000 },
];
const numberValue = (value: number | undefined) => value === undefined ? undefined : Number.isInteger(value) ? value.toLocaleString() : value.toLocaleString(undefined, { maximumFractionDigits: 2 });

export function SaveTools() {
  const api = window.dawnwalkerDesktop?.saveEditor;
  const [saves, setSaves] = useState<readonly SaveInspection[]>([]);
  const [summaries, setSummaries] = useState<SummaryMap>({});
  const [selected, setSelected] = useState("");
  const [inspection, setInspection] = useState<SaveInspection>();
  const [backups, setBackups] = useState<readonly SaveBackup[]>([]);
  const [backupId, setBackupId] = useState("");
  const [preview, setPreview] = useState<SaveRestorePreview>();
  const [busy, setBusy] = useState(Boolean(api));
  const [hasLoadedSaves, setHasLoadedSaves] = useState(false);
  const [message, setMessage] = useState("");
  const [editBusy, setEditBusy] = useState(false);
  const [editOutcome, setEditOutcome] = useState<SaveEditOutcome>();
  const [pending, setPending] = useState<FieldSet>(emptyPending);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [stackFilter, setStackFilter] = useState("");
  const [stackCategory, setStackCategory] = useState("All");
  const [giveFilter, setGiveFilter] = useState("");
  const [giveCategory, setGiveCategory] = useState("All");
  const [perkFilter, setPerkFilter] = useState("");
  const [perkTree, setPerkTree] = useState("All");
  const [perkMetadata, setPerkMetadata] = useState<ReadonlyMap<string, PerkMetadata>>(new Map());
  const [perkMetadataNote, setPerkMetadataNote] = useState("");
  const [perkAcquisitions, setPerkAcquisitions] = useState<Record<string, string>>({});
  const [bookAccess, setBookAccess] = useState<Record<string, string>>({});
  const [itemUpgrades, setItemUpgrades] = useState<Record<string, string>>({});
  const [factChanges, setFactChanges] = useState<Record<string, string>>({});
  const [infamyPoints, setInfamyPoints] = useState("");
  const [questSelection, setQuestSelection] = useState("");
  const [giveCounts, setGiveCounts] = useState<Record<string, string>>({});
  const [removeRows, setRemoveRows] = useState<Record<number, boolean>>({});
  const [showReplace, setShowReplace] = useState(false);
  const [replacePicks, setReplacePicks] = useState<Record<number, string>>({});
  const [replaceCounts, setReplaceCounts] = useState<Record<number, string>>({});
  const [lastPreset, setLastPreset] = useState<VampirePresetId>();
  // Which part of the chosen save is on screen: values, inventory, or backups. Queued
  // edits live in `pending` regardless of the open section, so switching loses nothing.
  const [section, setSection] = useState<SaveSection>("character");

  const inFlight = useRef(false);
  const operationBusy = busy || editBusy;

  function resetEdits() {
    setPending(emptyPending());
    setGiveCounts({});
    setRemoveRows({});
    setReplacePicks({});
    setReplaceCounts({});
    setPerkAcquisitions({});
    setBookAccess({});
    setItemUpgrades({});
    setFactChanges({});
    setInfamyPoints("");
    setQuestSelection("");
  }

  const fields = inspection?.fields;
  const advanced = inspection?.advanced;
  const perkOptions = useMemo(() => new Map((advanced?.perks ?? []).map(option => [option.id, option])), [advanced]);
  const stackCount = fields?.stacks?.length ?? 0;
  const attributeCount = fields?.attributes?.length ?? 0;

  // Note: editOutcome is deliberately NOT cleared here. applyEdit() sets a
  // fresh inspection and the outcome together; clearing on inspection change
  // would erase the just-earned verification banner. Stale outcomes are
  // cleared explicitly in choose() and the refresh action instead.
  useEffect(() => {
    setPending(emptyPending());
    setStackFilter("");
    setGiveCounts({});
    setRemoveRows({});
    setReplacePicks({});
    setReplaceCounts({});
    setPerkAcquisitions({});
    setBookAccess({});
    setItemUpgrades({});
    setFactChanges({});
    setInfamyPoints("");
    setQuestSelection("");
  }, [inspection?.sha256, selected]);

  // A save whose payload could not be verified offers backups only, so land there.
  const editable = Boolean(inspection?.fields && inspection.payloadValidation?.status === "verified");
  useEffect(() => { setSection(editable ? "character" : "backups"); }, [selected, editable]);

  // The picker shows each save's gameplay numbers. Decoding a save takes a moment, so
  // they are read one file at a time after the list arrives and filled in as they land;
  // a save whose decode fails is marked so instead of stalling the others. The pass is
  // keyed by the listed hashes, so a refresh that changed a file re-reads it.
  const listKey = saves.map(save => `${save.fileName}:${save.sha256}`).join("|");
  useEffect(() => {
    if (!api || !saves.length) { setSummaries({}); return; }
    let disposed = false;
    setSummaries(Object.fromEntries(saves.map(save => [save.fileName, "loading" as const])));
    void (async () => {
      for (const save of saves) {
        if (disposed) return;
        try {
          const summary = await api.readSummary(save.fileName);
          if (!disposed) setSummaries(current => ({ ...current, [save.fileName]: summary }));
        } catch (cause) {
          // The card says the values are unreadable; the save itself can still be inspected.
          console.warn(`Save summary unavailable for ${save.fileName}:`, cause);
          if (!disposed) setSummaries(current => ({ ...current, [save.fileName]: "unavailable" }));
        }
      }
    })();
    return () => { disposed = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- listKey stands in for `saves`
  }, [api, listKey]);

  // A verified inspection carries the freshest numbers for its file (after an edit or a
  // restore the listed hash is stale), so the picker's card follows the inspection.
  useEffect(() => {
    if (!inspection?.fields) return;
    const { clockDisplay, health, blood, mutationLevel, level, coin } = inspection.fields;
    setSummaries(current => ({ ...current, [inspection.fileName]: { clockDisplay, health, blood, mutationLevel, level, coin } }));
  }, [inspection]);

  // Perk names, trees and descriptions come from the game-asset export when one exists;
  // without it the tab still lists the save's perks by their internal ids.
  useEffect(() => {
    const assets = window.dawnwalkerDesktop?.gameAssets;
    if (!assets) return;
    let disposed = false;
    void assets.perks()
      .then(perks => { if (!disposed) { setPerkMetadata(new Map(perks.map(perk => [perk.id, perk]))); setPerkMetadataNote(perks.length ? "" : "No game-asset export found, so perks show their internal ids. Run the asset importer to get names, trees and pictures."); } })
      .catch(cause => { if (!disposed) setPerkMetadataNote(formatDesktopError(cause, "Perk metadata could not be read.")); });
    return () => { disposed = true; };
  }, [api]);

  useEffect(() => {
    let disposed = false;
    if (api) void api.listSaves()
      .then(result => { if (!disposed) { setSaves(result); setHasLoadedSaves(true); } })
      .catch(cause => { if (!disposed) setMessage(formatDesktopError(cause, "Could not load local saves. Refresh to retry.")); })
      .finally(() => { if (!disposed) setBusy(false); });
    return () => { disposed = true; };
  }, [api]);

  async function choose(fileName: string) {
    if (operationBusy || inFlight.current) return;
    setSelected(fileName); setPreview(undefined); setInspection(undefined); setBackups([]); setBackupId(""); setMessage(""); setEditOutcome(undefined);
    if (!fileName || !api) return;
    inFlight.current = true; setBusy(true);
    try { const current = await api.inspectSave(fileName); setInspection(current); setBackups(await api.listBackups(fileName)); }
    catch (cause) { setMessage(formatDesktopError(cause, "Cannot inspect this save.")); }
    finally { inFlight.current = false; setBusy(false); }
  }

  async function refreshInspection(fileName: string): Promise<SaveInspection> {
    if (!api) throw new Error("No save editor API.");
    const [current, history] = await Promise.all([api.inspectSave(fileName), api.listBackups(fileName)]);
    setInspection(current); setBackups(history);
    return current;
  }

  async function operate(action: "refresh" | "backup" | "preview" | "restore") {
    if (!api || operationBusy || inFlight.current) return;
    inFlight.current = true; setBusy(true); setMessage("");
    try {
      if (action === "refresh") {
        setPreview(undefined); setInspection(undefined); setBackups([]); setBackupId(""); setEditOutcome(undefined);
        const currentSaves = await api.listSaves();
        setSaves(currentSaves); setHasLoadedSaves(true);
        if (selected && !currentSaves.some(save => save.fileName === selected)) {
          setSelected("");
          setMessage("The selected save is no longer available. Choose a save from the refreshed list.");
          return;
        }
        if (selected) await refreshInspection(selected);
        setMessage("Save list refreshed.");
      } else if (inspection) {
        const request = { fileName: inspection.fileName, expectedSha256: inspection.sha256, backupId };
        if (action === "backup") {
          const backup = await api.createBackup(request);
          setBackups(current => [backup, ...current]); setBackupId(backup.backupId); setPreview(undefined);
          setMessage(`Backup verified: ${backup.backupPath}`);
          try { setBackups(await api.listBackups(inspection.fileName)); }
          catch { setMessage(`Backup verified: ${backup.backupPath}. Backup history could not be refreshed; refresh saves to retry.`); }
        } else if (action === "preview") setPreview(await api.previewRestore(request));
        else if (preview) {
          setPreview(undefined);
          const restored = await api.restoreBackup({ ...request, previewToken: preview.previewToken });
          // The restored bytes supersede whatever the last edit reported.
          setInspection(restored.inspection); setEditOutcome(undefined); setLastPreset(undefined); setBackups(current => [restored.recoveryBackup, ...current]);
          setMessage(`${restored.message} Recovery backup: ${restored.recoveryBackup.backupPath}`);
          try { setBackups(await api.listBackups(inspection.fileName)); }
          catch { setMessage(`${restored.message} Recovery backup: ${restored.recoveryBackup.backupPath}. Backup history could not be refreshed; refresh saves to retry.`); }
        }
      }
    } catch (cause) { setPreview(undefined); setMessage(formatDesktopError(cause, "Save operation failed.")); }
    finally { inFlight.current = false; setBusy(false); }
  }

  const changes = useMemo(() => {
    const edit: { [key: string]: unknown } = {};
    if (!fields) return edit;
    if (pending.health.trim() && fields.health !== undefined && Number(pending.health) !== fields.health) edit.health = Number(pending.health);
    if (pending.blood.trim() && fields.blood !== undefined && Number(pending.blood) !== fields.blood) edit.blood = Number(pending.blood);
    if (pending.mutationLevel.trim() && fields.mutationLevel !== undefined && Number(pending.mutationLevel) !== fields.mutationLevel) edit.mutationLevel = Number(pending.mutationLevel);
    if (pending.level.trim() && fields.level !== undefined && Number(pending.level) !== fields.level) edit.level = Number(pending.level);
    if (pending.progressPoints.trim() && fields.progressPoints !== undefined && Number(pending.progressPoints) !== fields.progressPoints) edit.progressPoints = Number(pending.progressPoints);
    if (pending.skillPoints.trim() && fields.skillPoints !== undefined && Number(pending.skillPoints) !== fields.skillPoints) edit.skillPoints = Number(pending.skillPoints);
    if (pending.spentSkillPoints.trim() && fields.spentSkillPoints !== undefined && Number(pending.spentSkillPoints) !== fields.spentSkillPoints) edit.spentSkillPoints = Number(pending.spentSkillPoints);
    if (pending.bloodRestoration.trim() && fields.bloodRestoration !== undefined && Number(pending.bloodRestoration) !== fields.bloodRestoration) edit.bloodRestoration = Number(pending.bloodRestoration);
    if (pending.corruptionCharge.trim() && fields.corruptionCharge !== undefined && Number(pending.corruptionCharge) !== fields.corruptionCharge) edit.corruptionCharge = Number(pending.corruptionCharge);
    if (pending.coin.trim() && fields.coin !== undefined && Number(pending.coin) !== fields.coin) edit.coin = Number(pending.coin);
    if (pending.segment && fields) {
      const value = Number(pending.segment);
      if (value !== fields.clockMs) edit.clockMs = value;
    }
    const stacks = Object.entries(pending.stacks)
      .filter(([, value]) => value.trim() !== "")
      .map(([itemIndex, value]) => ({ itemIndex: Number(itemIndex), value: Number(value) }))
      .filter(({ itemIndex, value }) => {
        const current = fields.stacks?.find(stack => stack.itemIndex === itemIndex);
        return current !== undefined && value !== current.value && Number.isSafeInteger(value) && value >= 0;
      });
    if (stacks.length) edit.stacks = stacks;
    const attributes = Object.entries(pending.attributes)
      .filter(([, value]) => value.trim() !== "")
      .map(([id, value]) => ({ id: Number(id), value: Number(value) }))
      .filter(({ id, value }) => {
        const current = fields.attributes?.find(attribute => attribute.id === id);
        return current !== undefined && value !== current.value && Number.isFinite(value);
      });
    if (attributes.length) edit.attributeValues = attributes;
    const traitRanks = Object.entries(pending.traitRanks)
      .filter(([, value]) => value.trim() !== "")
      .map(([id, value]) => ({ id, rank: Number(value) }))
      .filter(({ id, rank }) => {
        const current = fields.traits?.find(trait => trait.id === id);
        return current !== undefined && current.storedRank && Number.isSafeInteger(rank) && rank !== current.rank;
      });
    if (traitRanks.length) edit.traitRanks = traitRanks;
    const owned = new Set((fields.stacks ?? []).map(stack => stack.name));
    const adds = Object.entries(giveCounts)
      .filter(([, value]) => value.trim() !== "")
      .map(([itemId, value]) => ({ itemId, quantity: Number(value) }))
      .filter(({ itemId, quantity }) => !owned.has(itemId) && Number.isSafeInteger(quantity) && quantity >= 1 && quantity <= 9_999_999);
    const removes = Object.entries(removeRows)
      .filter(([, flagged]) => flagged)
      .map(([itemIndex]) => ({ itemIndex: Number(itemIndex) }))
      .filter(({ itemIndex }) => fields.stacks?.some(stack => stack.itemIndex === itemIndex && stack.name !== "Coin"));
    if (adds.length || removes.length) edit.inventory = { ...(adds.length ? { add: adds } : {}), ...(removes.length ? { remove: removes } : {}) };
    const replaces = Object.entries(replacePicks)
      .filter(([, definitionIndex]) => definitionIndex !== "")
      .map(([itemIndex, definitionIndex]) => {
        const raw = replaceCounts[Number(itemIndex)]?.trim();
        return { itemIndex: Number(itemIndex), definitionIndex: Number(definitionIndex), value: raw ? Number(raw) : undefined };
      })
      .filter(({ itemIndex, definitionIndex, value }) => {
        const current = fields.stacks?.find(stack => stack.itemIndex === itemIndex);
        const entry = fields.itemCatalog?.find(candidate => candidate.definitionIndex === definitionIndex);
        return current !== undefined && entry !== undefined && !entry.owned && entry.name !== "Coin" && entry.name !== current.name
          && (value === undefined || (Number.isSafeInteger(value) && value >= 1));
      });
    const perkAcquisitionEdits = Object.entries(perkAcquisitions)
      .filter(([, value]) => value.trim() !== "")
      .map(([id, value]) => ({ id, rank: Number(value) }))
      .filter(({ id, rank }) => !fields.traits?.some(trait => trait.id === id && trait.storedRank) && Number.isSafeInteger(rank) && rank >= 1);
    if (perkAcquisitionEdits.length) edit.perkAcquisitions = perkAcquisitionEdits;
    const bookAccessEdits = Object.entries(bookAccess)
      .filter(([, value]) => value.trim() !== "")
      .map(([id, value]) => ({ id, accessLevel: Number(value) }))
      .filter(({ id, accessLevel }) => Number.isSafeInteger(accessLevel) && accessLevel >= 1 && !fields.traits?.some(trait => trait.id === id && trait.accessLimit >= accessLevel));
    if (bookAccessEdits.length) edit.bookAccess = bookAccessEdits;
    const itemUpgradeEdits = Object.entries(itemUpgrades)
      .filter(([, value]) => value.trim() !== "")
      .flatMap(([handle, value]) => {
        const option = advanced?.upgrades.find(candidate => candidate.handle === Number(handle));
        return option ? [{ itemId: option.itemId, handle: option.handle, targetLevel: Number(value) }] : [];
      })
      .filter(({ targetLevel }) => Number.isSafeInteger(targetLevel) && targetLevel >= 1 && targetLevel <= 50);
    if (itemUpgradeEdits.length) edit.itemUpgrades = itemUpgradeEdits;
    const factEdits = Object.entries(factChanges)
      .filter(([, value]) => value.trim() !== "")
      .map(([tag, value]) => ({ tag, value: Number(value), expectedValue: advanced?.facts.find(fact => fact.tag === tag)?.value }))
      .filter(({ value }) => Number.isSafeInteger(value));
    if (factEdits.length) edit.factChanges = factEdits;
    if (infamyPoints.trim() && Number.isSafeInteger(Number(infamyPoints)) && Number(infamyPoints) !== advanced?.court?.points) edit.infamyPoints = Number(infamyPoints);
    if (questSelection && advanced?.quests) {
      const option = advanced.quests.options.find(candidate => `${candidate.assetPath}|${candidate.objectiveGuid}` === questSelection);
      if (option) edit.questTracking = { assetPath: option.assetPath, objectiveGuid: option.objectiveGuid, expectedMain: advanced.quests.trackedMain, expectedOther: advanced.quests.trackedOther };
    }
    if (replaces.length) edit.replaceItems = replaces;
    return edit;
  }, [fields, pending, giveCounts, removeRows, replacePicks, replaceCounts, perkAcquisitions, bookAccess, itemUpgrades, factChanges, infamyPoints, questSelection, advanced]);

  // Mirror the numeric contract in saveEditing.validateFieldEdit for draft feedback.
  // The backend remains authoritative and verifies the save again before writing.
  const numericDrafts: [string, string, number, number, boolean][] = [
    ["Health", pending.health, 0, 100_000, false],
    ["Blood", pending.blood, 0, 100_000, false],
    ["Mutation level", pending.mutationLevel, 0, MAX_MUTATION_LEVEL, true],
    ["Character level", pending.level, 1, MAX_LEVEL, true],
    ["Progress points", pending.progressPoints, 0, 4_294_967_295, true],
    ["Skill points", pending.skillPoints, 0, 4_294_967_295, true],
    ["Spent skill points", pending.spentSkillPoints, 0, 4_294_967_295, true],
    ["Blood restoration", pending.bloodRestoration, 0, 100_000, false],
    ["Corruption charge", pending.corruptionCharge, 0, 100_000, false],
    ["Coin", pending.coin, 0, 4_294_967_295, true],
    ["Time segment", pending.segment, 0, 4_294_967_295, true],
    ["Infamy points", infamyPoints, 0, 900, true],
    ...Object.entries(perkAcquisitions).map(([id, value]): [string, string, number, number, boolean] =>
      [`Acquire rank for ${id}`, value, 1, 4, true]),
    ...Object.entries(bookAccess).map(([id, value]): [string, string, number, number, boolean] =>
      [`Book rank for ${id}`, value, 1, 32, true]),
    ...Object.entries(itemUpgrades).map(([id, value]): [string, string, number, number, boolean] =>
      [`Upgrade level for ${id}`, value, 1, 50, true]),
    ...Object.entries(factChanges).map(([tag, value]): [string, string, number, number, boolean] =>
      [`Fact ${tag}`, value, -2_147_483_648, 2_147_483_647, true]),
    ...Object.entries(pending.stacks).map(([id, value]): [string, string, number, number, boolean] =>
      [`Stack ${fields?.stacks?.find(stack => stack.itemIndex === Number(id))?.name ?? id}`, value, 0, 9_999_999, true]),
    ...Object.entries(pending.attributes).map(([id, value]): [string, string, number, number, boolean] =>
      [`Attribute ${fields?.attributes?.find(attribute => attribute.id === Number(id))?.name ?? id}`, value, -100_000, 100_000, false]),
    ...Object.entries(giveCounts).map(([id, value]): [string, string, number, number, boolean] =>
      [`Give count ${id}`, value, 1, 9_999_999, true]),
    ...Object.entries(replaceCounts).filter(([id]) => Boolean(replacePicks[Number(id)]))
      .map(([id, value]): [string, string, number, number, boolean] =>
        [`Replacement count for slot ${id}`, value, 1, 9_999_999, true]),
  ];
  const invalidDraft = numericDrafts.find(([, raw, minimum, maximum, whole]) => {
    if (!raw.trim()) return false;
    const value = Number(raw);
    return !Number.isFinite(value) || value < minimum || value > maximum || (whole && !Number.isSafeInteger(value));
  });
  const numericDraftError = invalidDraft
    ? `${invalidDraft[0]}: Enter a valid ${invalidDraft[4] ? "whole " : ""}number from ${invalidDraft[2]} to ${invalidDraft[3]}, or clear it to keep the saved value.`
    : "";

  // Count each queued stack/attribute/give/replace individually, matching how
  // the backend reports planned edits.
  const traitDraftError = useMemo(() => {
    for (const [id, value] of Object.entries(pending.traitRanks)) {
      if (!value.trim()) continue;
      const trait = fields?.traits?.find(entry => entry.id === id);
      if (!trait) continue;
      const rank = Number(value);
      const label = perkMetadata.get(id)?.name ?? spellOut(id);
      if (!Number.isSafeInteger(rank) || rank < 0) return `Enter a whole number for ${label}.`;
      if (rank < trait.rank) return `${label}: a rank cannot be lowered here (that needs a respec in game).`;
      if (rank > trait.accessLimit) return `${label}: the save's stored limit for this perk is ${trait.accessLimit}.`;
    }
    return "";
  }, [pending.traitRanks, fields, perkMetadata]);
  let advancedDraftError = "";
  for (const [id, raw] of Object.entries(perkAcquisitions)) if (raw.trim() && !perkOptions.get(id)?.acquisitionRanks.includes(Number(raw))) advancedDraftError ||= `This rank of ${id} is not eligible in the inspected save.`;
  for (const [id, raw] of Object.entries(bookAccess)) if (raw.trim() && !perkOptions.get(id)?.bookRanks.includes(Number(raw))) advancedDraftError ||= `This book rank of ${id} is not eligible in the inspected save.`;
  for (const [handle, raw] of Object.entries(itemUpgrades)) {
    const option = advanced?.upgrades.find(candidate => candidate.handle === Number(handle));
    if (raw.trim() && (!option || Number(raw) <= option.currentLevel || Number(raw) > option.maximumLevel)) advancedDraftError ||= "Choose an item level within the displayed upgrade range.";
  }
  for (const [tag, raw] of Object.entries(factChanges)) if (raw.trim() && !advanced?.facts.some(fact => fact.tag === tag)) advancedDraftError ||= "Select an existing fact from the local tag catalog.";
  if (infamyPoints.trim() && !advanced?.infamyAvailable) advancedDraftError ||= advanced?.infamyReason ?? "Infamy metadata is unavailable.";
  if (infamyPoints.trim() && advanced?.court && Number(infamyPoints) < advanced.court.activeEdicts * 100) advancedDraftError ||= `Enacted edicts require at least ${advanced.court.activeEdicts * 100} infamy points.`;
  const draftError = numericDraftError || traitDraftError || advancedDraftError;
  const changeCount = Object.entries(changes).reduce((total, [key, value]) => {
    if (key === "inventory") { const structural = value as { add?: unknown[]; remove?: unknown[] }; return total + (structural.add?.length ?? 0) + (structural.remove?.length ?? 0); }
    return total + (Array.isArray(value) ? value.length : 1);
  }, 0);

  async function applyEdit(edit: Record<string, unknown>) {
    if (!api || !inspection || operationBusy || inFlight.current) return;
    inFlight.current = true; setEditBusy(true); setMessage(""); setEditOutcome(undefined);
    try {
      const outcome = await api.editFields({ fileName: inspection.fileName, expectedSha256: inspection.sha256, edit });
      setEditOutcome(outcome);
      setInspection(outcome.inspection);
      setBackups(current => [outcome.backup, ...current]);
      resetEdits();
      setMessage(outcome.message);
      try { setBackups(await api.listBackups(inspection.fileName)); } catch { setMessage(`${outcome.message} Backup history could not be refreshed; refresh saves to retry.`); }
    } catch (cause) { setMessage(formatDesktopError(cause, "Edit failed. The save was left unchanged.")); }
    finally { inFlight.current = false; setEditBusy(false); }
  }

  // One-click quick actions. Each is a plain field edit with prechosen values.
  function quickAction(kind: "full-heal" | "max-blood" | "clear-mutation" | "segment-forward" | "segment-back"): void {
    if (!fields) return;
    const next = emptyPending();
    if (kind === "full-heal") { if (fields.health !== undefined) next.health = String(Math.min(100_000, Math.max(fields.health, 100))); }
    if (kind === "max-blood") { if (fields.blood !== undefined) next.blood = String(Math.max(fields.blood, 100)); }
    if (kind === "clear-mutation") { if (fields.mutationLevel !== undefined && fields.mutationLevel !== 0) next.mutationLevel = "0"; }
    if (kind === "segment-forward" && fields.clockMs + SEGMENT_MS <= 4_294_967_295) next.segment = String(fields.clockMs + SEGMENT_MS);
    if (kind === "segment-back" && fields.clockMs - SEGMENT_MS >= 0) next.segment = String(fields.clockMs - SEGMENT_MS);
    const edit: Record<string, unknown> = {};
    if (next.health.trim() && fields.health !== undefined && Number(next.health) !== fields.health) edit.health = Number(next.health);
    if (next.blood.trim() && fields.blood !== undefined && Number(next.blood) !== fields.blood) edit.blood = Number(next.blood);
    if (next.mutationLevel.trim() && fields.mutationLevel !== undefined && Number(next.mutationLevel) !== fields.mutationLevel) edit.mutationLevel = Number(next.mutationLevel);
    if (next.segment && Number(next.segment) !== fields.clockMs) edit.clockMs = Number(next.segment);
    if (!Object.keys(edit).length) { setMessage("Nothing to change for that action — the save already matches it."); return; }
    void applyEdit(edit);
  }

  // Vampire presets: prune unchanged values, then apply through the ordinary
  // verified pipeline. Empty result = the save already matches the preset.
  async function applyVampirePreset(presetId: VampirePresetId) {
    if (!fields) return;
    const preset = VAMPIRE_PRESETS.find(candidate => candidate.id === presetId);
    if (!preset) return;
    const edit = presetEditsFor(preset, { health: fields.health, blood: fields.blood, mutationLevel: fields.mutationLevel });
    if (!Object.keys(edit).length) { setMessage(`Already in the “${preset.name}” state — nothing to change.`); return; }
    setLastPreset(presetId);
    await applyEdit(edit);
  }

  const canEdit = Boolean(api && inspection?.fields && inspection.payloadValidation?.status === "verified");
  const matchesItem = (needle: string, entry: { name: string; displayName: string }) => {
    const query = needle.trim().toLowerCase();
    return !query || entry.name.toLowerCase().includes(query) || entry.displayName.toLowerCase().includes(query);
  };
  const filteredStacks = (fields?.stacks ?? []).filter(stack => matchesItem(stackFilter, stack) && (stackCategory === "All" || stack.category === stackCategory));
  const catalog = useMemo(() => fields?.itemCatalog ?? [], [fields?.itemCatalog]);
  const ownedIds = useMemo(() => new Set((fields?.stacks ?? []).map(stack => stack.name)), [fields?.stacks]);
  const addCatalog = useMemo(() => {
    const seen = new Set<string>();
    const rows: { name: string; displayName: string; category: string; rarity?: string; sensitive: boolean }[] = [];
    for (const record of ITEM_CATALOG_RECORDS) { seen.add(record.id); rows.push({ name: record.id, displayName: record.name, category: record.category, rarity: record.rarity, sensitive: record.sensitive === true }); }
    for (const entry of catalog) if (!seen.has(entry.name)) { const described = describeItem(entry.name); rows.push({ name: entry.name, displayName: described.name, category: described.category, sensitive: false }); }
    return rows.filter(row => row.name !== "Coin").sort((a, b) => a.displayName.localeCompare(b.displayName));
  }, [catalog]);
  const giveOptions = addCatalog.filter(entry => !ownedIds.has(entry.name) && matchesItem(giveFilter, entry) && (giveCategory === "All" || entry.category === giveCategory));
  const queuedRemovals = Object.values(removeRows).filter(Boolean).length;
  // Keep catalog identity separate from saved state. The asset export marks internal
  // definitions; the backend separately reports definition support and current-save
  // eligibility, so an absent save row is never mislabeled as a broken mapping.
  const allPerkRows = useMemo(() => {
    const saved = new Map((fields?.traits ?? []).map(trait => [trait.id, trait]));
    const ids = new Set<string>([...perkMetadata.keys(), ...saved.keys()]);
    return [...ids].map(id => {
      const meta = perkMetadata.get(id);
      const option = perkOptions.get(id);
      const trait = saved.get(id) ?? { id, rank: 0, highestRank: 0, accessLimit: 0, storedRank: false, acquired: false };
      const editable = trait.storedRank && trait.rank < trait.accessLimit;
      const acquisitionStructureMapped = option?.acquisitionStructureMapped === true;
      const catalogMetadataIncomplete = meta?.iconStatus.startsWith("Internal definition:") === true;
      const obsolete = meta?.description.trim().toUpperCase() === "[OBSOLETE]";
      const learned = trait.rank > 0 || trait.acquired;
      const available = editable || Boolean(option?.acquisitionRanks.length);
      const classification = obsolete ? "Obsolete definition" : catalogMetadataIncomplete ? "Catalog metadata incomplete" : acquisitionStructureMapped ? "Acquisition structure mapped" : "Unresolved acquisition structure";
      const acquisitionState = learned ? "Learned" : available ? "Eligible now in this save" : "Not currently eligible";
      const reason = option?.acquisitionReason ?? option?.definitionReason ?? (catalogMetadataIncomplete ? meta?.iconStatus : undefined);
      return { trait, meta, name: meta?.name || spellOut(id), tree: meta?.tree ?? "Unknown", description: meta?.description ?? "", editable, acquisitionStructureMapped, learned, available, classification, acquisitionState, reason };
    }).sort((a, b) => a.name.localeCompare(b.name));
  }, [fields?.traits, perkMetadata, perkOptions]);
  const perkRows = useMemo(() => allPerkRows.filter(row => {
      const query = perkFilter.trim().toLowerCase();
      return (!query || row.name.toLowerCase().includes(query) || row.trait.id.toLowerCase().includes(query)) && (perkTree === "All" || row.tree === perkTree);
    }), [allPerkRows, perkFilter, perkTree]);
  const perkCounts = useMemo(() => ({ catalog: perkMetadata.size,
    mapped: allPerkRows.filter(row => row.acquisitionStructureMapped).length,
    available: allPerkRows.filter(row => row.available).length,
    learned: allPerkRows.filter(row => row.learned).length,
  }), [allPerkRows, perkMetadata.size]);
  const perkTrees = ["All", ...new Set([...perkMetadata.values()].map(perk => perk.tree).concat((fields?.traits ?? []).map(trait => perkMetadata.get(trait.id)?.tree ?? "Unknown")))].sort((a, b) => a === "All" ? -1 : b === "All" ? 1 : a.localeCompare(b));
  const categoriesOf = (entries: readonly { category: string }[]) => ["All", ...ITEM_CATEGORIES.filter(category => entries.some(entry => entry.category === category))];
  const replaceableStacks = (fields?.stacks ?? []).filter(stack => stack.name !== "Coin");

  return <section className="feature-tools save-editor" aria-label="Save tools">
    <div className="feature-title"><h3>Edit a save file</h3></div>
    <p>Change what a save holds — health, blood, vampire mutation, level, coin, time of day and inventory — without playing it back. Pick a save, type the new values, press Apply. Every write backs the original up first, is read back and verified, and can be undone from <strong>Backups &amp; restore</strong> below. Close Dawnwalker before applying: the editor refuses to write while the game is running.</p>
    {!api ? <p>Open the desktop app to access local saves.</p> : <>
      <section className="save-step" aria-labelledby="save-step-choose">
        <h4 id="save-step-choose">Choose a save</h4>
        <p className="save-step-hint">Each entry is the game's own load-list card plus the values stored inside it. Pick the save you want to change; the game must be closed before anything is written, and loading that save in game afterwards shows the new values.</p>
        <div className="save-picker-toolbar"><span>Selected save: <strong>{selected ? saveTypeLabel(saves.find(save => save.fileName === selected)?.metadata?.type, selected) + " \u00b7 " + savedAtLabel(saves.find(save => save.fileName === selected)?.metadata?.savedAt) : "none"}</strong></span>
          <button type="button" disabled={operationBusy} onClick={() => void operate("refresh")}>Refresh saves</button></div>
        {saves.length > 0 && <SavePicker saves={saves} summaries={summaries} selected={selected} disabled={operationBusy} onChoose={fileName => void choose(fileName)} />}
        {!hasLoadedSaves && busy && <p>Loading local saves…</p>}
        {hasLoadedSaves && !saves.length && <p>No gameplay saves found in the local Dawnwalker save folder.</p>}
        {inspection && <details className="save-file-details">
          <summary>File details</summary>
          <p className="file-path save-file-line"><span>{inspection.fullPath}</span><span>{inspection.sha256}</span></p>
          {inspection.metadataWarning && <p>{inspection.metadataWarning}</p>}
          {inspection.payloadValidation && <p className="feature-status">{inspection.payloadValidation.message}</p>}
        </details>}
      </section>
      {inspection && <>
        <div className="save-tabs" role="tablist" aria-label="Save editor sections">
          {SECTION_TABS.map(tab => <button key={tab.id} type="button" role="tab" id={`save-tab-${tab.id}`} aria-selected={section === tab.id} aria-controls={`save-panel-${tab.id}`}
            disabled={tab.editsSave && !canEdit} onClick={() => setSection(tab.id)}>{tab.label}</button>)}
        </div>
        {section === "character" && fields && canEdit && <section className="save-step" role="tabpanel" id="save-panel-character" aria-labelledby="save-tab-character">
          <details className="save-guide" open>
            <summary>How to edit character values</summary>
            <ul>
              <li>Every box shows the value the save holds now (<em>keep 200</em> means it is 200). Type a whole number to change it, or leave the box empty to keep it.</li>
              <li><strong>Health</strong> and <strong>Blood</strong> are the bars you see in game; anything above your maximum is trimmed when the save loads, so 100–1000 is a sensible range.</li>
              <li><strong>Vampire mutation level</strong> is how far the curse has progressed: 0 is fully human, 15 is the strongest vampire. It controls which powers and drawbacks are active.</li>
              <li><strong>Character level</strong> and <strong>Progress points</strong> drive levelling: raising the level hands out the level-up rewards on load; progress points are the experience towards the next level.</li>
              <li><strong>Coin</strong> is your money. <strong>Time of day</strong> moves the clock in the game's own 90-minute steps inside the saved day or night.</li>
              <li>Queued changes are listed under <strong>Apply</strong> below. Quick actions and presets skip the queue and write straight away.</li>
            </ul>
          </details>
          <div className="save-value-groups">
            {([["Progression", PROGRESSION_FIELDS], ["Vitals", VITALS_FIELDS]] as const).map(([title, specs]) => <section key={title} className="save-value-group" aria-label={title}>
              <h5>{title}</h5>
              {specs.map(spec => {
                const current = fields[spec.key];
                if (current === undefined) return null;
                return <label key={spec.key} className="save-value-row" title={spec.hint}>
                  <SaveValueIcon name={spec.key} />
                  <span className="save-value-name">{spec.label}<small>{spec.hint}</small></span>
                  <input aria-label={spec.ariaLabel ?? spec.label}
                    inputMode={spec.integer ? "numeric" : "decimal"} value={pending[spec.key]} disabled={operationBusy}
                    placeholder={`keep ${numberValue(current)}`} onChange={event => setPending(p => ({ ...p, [spec.key]: event.target.value }))} />
                </label>;
              })}
              {title === "Progression" && <p className="save-step-hint">Stored values only: XP and level do not replay level-up logic, and spent points do not respec perks.</p>}
              {title === "Vitals" && <label className="save-value-row" title="Moves in the game's 90-minute steps and stays in the same day or night half.">
                <SaveValueIcon name="clock" />
                <span className="save-value-name">Time of day<small>Saved clock: {clockLabel(fields.clockMs)}. Moves in 90-minute steps inside the same day or night half.</small></span>
                <select aria-label="Time segment" value={pending.segment} disabled={operationBusy} onChange={event => setPending(p => ({ ...p, segment: event.target.value }))}>
                  <option value="">Keep the saved time</option>
                  {segmentOptions(fields.clockMs).map(option => <option key={option.value} value={option.value}>{option.label}</option>)}
                </select>
              </label>}
            </section>)}
          </div>
          <h5>Quick actions</h5>
          <p className="save-step-hint">One-click edits that write straight away (with the same automatic backup) — no need to press Apply. A button is greyed out when the save already matches it.</p>
          <div className="feature-actions" role="group" aria-label="Quick actions">
            <button type="button" disabled={operationBusy || fields.health === undefined || fields.health >= 100} title="Raises Health to 100 when it is lower; leaves a higher value alone." onClick={() => quickAction("full-heal")}>Heal to 100</button>
            <button type="button" disabled={operationBusy || fields.blood === undefined || fields.blood >= 100} title="Raises Blood to 100 when it is lower; leaves a higher value alone." onClick={() => quickAction("max-blood")}>Blood to 100</button>
            <button type="button" disabled={operationBusy || !fields.mutationLevel} title="Sets the vampire mutation level to 0 (fully human)." onClick={() => quickAction("clear-mutation")}>Mutation to 0</button>
            <button type="button" disabled={operationBusy} title="Moves the saved clock 90 minutes later." onClick={() => quickAction("segment-forward")}>Clock +90 min</button>
            <button type="button" disabled={operationBusy} title="Moves the saved clock 90 minutes earlier." onClick={() => quickAction("segment-back")}>Clock −90 min</button>
            {fields.coin !== undefined && <button type="button" disabled={operationBusy} onClick={() => void applyEdit({ coin: fields.coin! + 10_000 })}>+10,000 Coin</button>}
            {fields.coin !== undefined && <button type="button" disabled={operationBusy} onClick={() => void applyEdit({ coin: 1_000_000 })}>Coin to 1,000,000</button>}
            {fields.level !== undefined && fields.level < MAX_LEVEL && <button type="button" disabled={operationBusy} onClick={() => void applyEdit({ level: fields.level! + 1 })}>Level +1</button>}
          </div>
          <h5>Vampire presets</h5>
          <p className="save-step-hint" role="note">Each preset writes mutation level, Health and Blood together, straight away; the label counts how many of the three it would change. <strong>Unverified in game</strong> — the values are proven on disk, but how Dawnwalker's vampire systems react on load has not been tested, so keep the automatic backup until you have reloaded the save and checked.</p>
          <div className="feature-actions" role="group" aria-label="Vampire presets">
            {VAMPIRE_PRESETS.map(preset => {
              const edit = presetEditsFor(preset, { health: fields.health, blood: fields.blood, mutationLevel: fields.mutationLevel });
              const pendingCount = Object.keys(edit).length;
              return <button
                key={preset.id}
                type="button"
                disabled={operationBusy || pendingCount === 0}
                title={pendingCount === 0 ? `Already in the “${preset.name}” state.` : preset.description}
                onClick={() => void applyVampirePreset(preset.id)}
              >{preset.name}{pendingCount > 0 && ` (${pendingCount} change${pendingCount === 1 ? "" : "s"})`}</button>;
            })}
          </div>
          {lastPreset && editOutcome && <p className="feature-status">Preset “{VAMPIRE_PRESETS.find(p => p.id === lastPreset)?.name}” applied and verified on disk. <strong>Unverified in game</strong> — reload this save in Dawnwalker and check the vampire state before relying on it.</p>}
          <h5>Saved attributes</h5>
          <p className="save-step-hint">Every numeric attribute the save stores, by the game's own id — the same Health, Blood and mutation values as above plus the rest. Only change one if you know what it does.</p>
          <p className="save-step-hint">
            <button type="button" aria-expanded={showAdvanced} onClick={() => setShowAdvanced(current => !current)}>{showAdvanced ? "▾" : "▸"} Advanced: saved attributes ({attributeCount})</button>
          </p>
          <h5>Save-system editors</h5>
          <p className="save-step-hint">Choose saved facts, infamy or an active quest objective. These edits are checked on disk; their effects still need checking after loading the save.</p>
          {advanced?.court && <p className="save-step-hint">Infamy {advanced.court.points} · level {advanced.court.level} · enacted edicts {advanced.court.activeEdicts} · pending {advanced.court.pending}</p>}
          <p className="save-step-hint" role="note"><strong>Unverified in game:</strong> quest tracking, fact effects and the numeric Infamy value. A Quicksave2 edit to 100 Infamy loaded and triggered Dawnwalker's Infamy tutorial, but the Court screen did not expose the edited number.</p>
          <div className="feature-fields">
            <label>Infamy points (0–900)<input aria-label="Infamy points" inputMode="numeric" value={infamyPoints} disabled={operationBusy || !advanced?.infamyAvailable} title={advanced?.infamyReason} placeholder={`keep ${advanced?.court?.points ?? "saved value"}`} onChange={event => setInfamyPoints(event.target.value)} /></label>
            <label>Fact tag to change<input aria-label="Fact tag" list="save-fact-tags" value={Object.keys(factChanges)[0] ?? ""} disabled={operationBusy || !advanced?.facts.length} placeholder="Search saved fact tags" onChange={event => { const value = event.target.value; setFactChanges(value ? { [value]: "" } : {}); }} /></label>
            <datalist id="save-fact-tags">{advanced?.facts.map(fact => <option key={fact.tag} value={fact.tag}>{fact.value}</option>)}</datalist>
            {Object.entries(factChanges).map(([tag, value]) => <label key={tag}>Value for {tag}<input aria-label={`Value for fact ${tag}`} inputMode="numeric" value={value} disabled={operationBusy} placeholder={`keep ${advanced?.facts.find(fact => fact.tag === tag)?.value ?? "saved value"}`} onChange={event => setFactChanges(current => ({ ...current, [tag]: event.target.value }))} /></label>)}
            <label>Track a quest objective<select aria-label="Track a quest objective" value={questSelection} disabled={operationBusy || !advanced?.quests?.options.length} onChange={event => setQuestSelection(event.target.value)}>
              <option value="">Keep current tracking</option>
              {advanced?.quests?.options.map(option => <option key={`${option.assetPath}|${option.objectiveGuid}`} value={`${option.assetPath}|${option.objectiveGuid}`}>{option.title} — {option.objectiveName}</option>)}
            </select></label>
          </div>
          <p className="save-step-hint">Quest tracking selects an already-active objective; it does not complete quests. Infamy cannot fall below enacted edicts.</p>
          {advanced?.infamyReason && <p className="save-step-hint">{advanced.infamyReason}</p>}
          {!!advanced?.issues.length && <details className="save-guide"><summary>Unavailable save operations</summary><ul>{advanced.issues.map((issue, index) => <li key={index}>{issue}</li>)}</ul></details>}
          {showAdvanced && <div className="feature-fields save-scroll-list">
            {(fields.attributes ?? []).map(attribute => <label key={attribute.id}>{attribute.name} (id {attribute.id})<input
              aria-label={`Attribute ${attribute.name}`} inputMode="decimal" disabled={operationBusy}
              value={pending.attributes[attribute.id] ?? ""}
              placeholder={`keep ${attribute.value}`}
              onChange={event => setPending(p => ({ ...p, attributes: { ...p.attributes, [attribute.id]: event.target.value } }))}
            /></label>)}
            <p className="feature-status">Numeric ids come from the game's own attribute table; only change a value if you know what it does.</p>
          </div>}
        </section>}
        {section === "inventory" && fields && canEdit && <section className="save-step" role="tabpanel" id="save-panel-inventory" aria-labelledby="save-tab-inventory">
          <details className="save-guide" open>
            <summary>How to edit the inventory</summary>
            <ul>
              <li>Items show their in-game name with the internal id underneath (for example <em>Minor Mending Ointment · Medicaments1</em>); search matches either, and the category box narrows the list.</li>
              <li><strong>Owned items</strong>: type a new count next to an item to change how many you carry (1 for gear, more for consumables). Use <em>Find item</em> to filter the list.</li>
              <li><strong>Add an item</strong>: search the whole item catalog and type a count next to anything you do not own yet; the save gets a new row for it. Rows marked <em>story item</em> are quest, key or currency items — giving those can confuse a quest.</li>
              <li><strong>Remove</strong>: tick <em>Remove</em> on an owned row to drop it from the save (it also comes off any equipment slot). Coins are changed through the Coins value instead.</li>
              <li><strong>Replace an owned item</strong>: swap what an existing row points at, keeping its position.</li>
              <li>Nothing is written until you press <strong>Apply</strong> below; every write keeps an automatic backup.</li>
            </ul>
          </details>
          {stackCount > 0 && <>
            <h5>Owned items ({stackCount} stacks)</h5>
            <div className="save-item-toolbar">
              <input aria-label="Filter inventory" value={stackFilter} disabled={operationBusy} onChange={event => setStackFilter(event.target.value)} placeholder="Search items by name or id…" />
              <select aria-label="Inventory category" value={stackCategory} disabled={operationBusy} onChange={event => setStackCategory(event.target.value)}>
                {categoriesOf(fields.stacks ?? []).map(category => <option key={category} value={category}>{category}</option>)}
              </select>
            </div>
            <div className="save-item-table" role="table" aria-label="Owned items">
              <div className="save-item-head save-owned-row" role="row"><span role="columnheader">Item</span><span role="columnheader">Category</span><span role="columnheader">Quantity</span><span role="columnheader">Remove</span></div>
              <div className="save-item-body save-scroll-list">
                {filteredStacks.map(stack => <div key={stack.itemIndex} className={`save-item-row save-owned-row${removeRows[stack.itemIndex] ? " save-item-removing" : ""}`} role="row">
                  <span className="save-item-cell save-item-name" role="cell"><ItemIcon id={stack.name} /><span><strong>{stack.displayName}</strong><small>{stack.name}</small></span></span>
                  <span className="save-item-cell" role="cell">{stack.category}</span>
                  <span className="save-item-cell save-item-quantity" role="cell"><input
                    aria-label={`Stack for ${stack.name}`} inputMode="numeric" disabled={operationBusy || Boolean(removeRows[stack.itemIndex])}
                    value={pending.stacks[stack.itemIndex] ?? ""}
                    placeholder={`keep ${stack.value}`}
                    onChange={event => setPending(p => ({ ...p, stacks: { ...p.stacks, [stack.itemIndex]: event.target.value } }))}
                  /></span>
                  <span className="save-item-cell save-item-remove" role="cell">{stack.name === "Coin"
                    ? <small>Use Coins</small>
                    : <label><input type="checkbox" aria-label={`Remove ${stack.name}`} disabled={operationBusy} checked={Boolean(removeRows[stack.itemIndex])}
                      onChange={event => setRemoveRows(current => ({ ...current, [stack.itemIndex]: event.target.checked }))} /> Remove</label>}</span>
                </div>)}
                {!filteredStacks.length && <p>No items match “{stackFilter}”{stackCategory !== "All" ? ` in ${stackCategory}` : ""}.</p>}
              </div>
            </div>
          </>}
          {catalog.length > 0 && <>
            <h5>Add an item — {addCatalog.length.toLocaleString()} items in the catalog</h5>
            <div className="save-item-toolbar">
              <input aria-label="Search items" value={giveFilter} disabled={operationBusy} onChange={event => setGiveFilter(event.target.value)} placeholder="Search name or item id…" />
              <select aria-label="Catalog category" value={giveCategory} disabled={operationBusy} onChange={event => setGiveCategory(event.target.value)}>
                {categoriesOf(catalog).map(category => <option key={category} value={category}>{category}</option>)}
              </select>
            </div>
            <p className="save-step-hint">Type a count next to anything you do not carry yet and press Apply; the item gets its own row in the save. Items you already own are edited in the list above.{queuedRemovals ? ` ${queuedRemovals} row${queuedRemovals === 1 ? "" : "s"} marked for removal.` : ""}</p>
            <div className="save-item-table" role="table" aria-label="Catalog items">
              <div className="save-item-head" role="row"><span role="columnheader">Item</span><span role="columnheader">Category</span><span role="columnheader">Give</span></div>
              <div className="save-item-body save-scroll-list">
                {giveOptions.slice(0, 400).map(entry => <label key={entry.name} className={`save-item-row${entry.sensitive ? " save-item-sensitive" : ""}`} role="row" title={entry.sensitive ? "Quest, key, currency or story item — giving it can confuse a quest." : undefined}>
                  <span className="save-item-cell save-item-name" role="cell"><ItemIcon id={entry.name} /><span><strong>{entry.displayName}</strong><small>{entry.name}{entry.rarity ? ` · ${entry.rarity}` : ""}{entry.sensitive ? " · story item" : ""}</small></span></span>
                  <span className="save-item-cell" role="cell">{entry.category}</span>
                  <span className="save-item-cell save-item-quantity" role="cell"><input
                    aria-label={`Give count for ${entry.name}`} inputMode="numeric" disabled={operationBusy}
                    value={giveCounts[entry.name] ?? ""}
                    placeholder="count"
                    onChange={event => setGiveCounts(current => ({ ...current, [entry.name]: event.target.value }))}
                  /></span>
                </label>)}
                {giveOptions.length > 400 && <p>Showing the first 400 of {giveOptions.length.toLocaleString()} matches — narrow the search to see the rest.</p>}
                {!giveOptions.length && <p>No unowned items match “{giveFilter}”{giveCategory !== "All" ? ` in ${giveCategory}` : ""}.</p>}
              </div>
            </div>
          </>}
          {catalog.length > 0 && <>
            <h5>Item level upgrades</h5>
            <p className="save-step-hint">For owned weapons and clothing, enter a target level. Each upgrade changes one unit and respects the character-level cap. Apply upgrades separately from quantity, item and character-level changes. Stored levels may differ from the level shown in game.</p>
            <p className="save-step-hint" role="note"><strong>Verified in game on Quicksave2:</strong> one Common Sword changed from level 2 to level 3, appeared as Level 3 after loading, and the original save was restored afterward.</p>
            <div className="feature-fields save-scroll-list">
              {(advanced?.upgrades ?? []).map(option => <label key={`upgrade-${option.handle}`}>Upgrade {describeItem(option.itemId).name} · stored level {option.currentLevel} → {option.maximumLevel}<input aria-label={`Upgrade level for ${option.itemId} handle ${option.handle}`} inputMode="numeric" disabled={operationBusy} value={itemUpgrades[option.handle] ?? ""} placeholder={`${option.currentLevel + 1}–${option.maximumLevel}`} onChange={event => setItemUpgrades(current => ({ ...current, [option.handle]: event.target.value }))} /></label>)}
              {!advanced?.upgrades.length && <p className="save-step-hint">No eligible item upgrades in this save. The item and character levels must fit the local game configuration.</p>}
            </div>
          </>}
          {replaceableStacks.length > 0 && catalog.length > 0 && <>
            <h5>
              <button type="button" aria-expanded={showReplace} onClick={() => setShowReplace(current => !current)}>{showReplace ? "▾" : "▸"} Replace an owned item ({replaceableStacks.length} slots)</button>
            </h5>
            {showReplace && <div className="feature-fields save-scroll-list">
              {replaceableStacks.map(stack => <div key={stack.itemIndex} className="feature-fields">
                <label>{`Swap ${stack.displayName} (${stack.name}, slot ${stack.itemIndex}) for`}<select
                  aria-label={`Replace ${stack.name} with`} disabled={operationBusy}
                  value={replacePicks[stack.itemIndex] ?? ""}
                  onChange={event => setReplacePicks(current => ({ ...current, [stack.itemIndex]: event.target.value }))}
                >
                  <option value="">Keep {stack.displayName}</option>
                  {catalog.filter(entry => !entry.owned && entry.name !== "Coin").map(entry => <option key={entry.definitionIndex} value={entry.definitionIndex}>{entry.displayName === entry.name ? entry.name : `${entry.displayName} (${entry.name})`}</option>)}
                </select></label>
                {replacePicks[stack.itemIndex] !== undefined && replacePicks[stack.itemIndex] !== "" && <label>Count (blank keeps {stack.value})<input
                  aria-label={`Replacement count for ${stack.name}`} inputMode="numeric" disabled={operationBusy}
                  value={replaceCounts[stack.itemIndex] ?? ""}
                  placeholder={`current ${stack.value}`}
                  onChange={event => setReplaceCounts(current => ({ ...current, [stack.itemIndex]: event.target.value }))}
                /></label>}
              </div>)}
              <p className="feature-status">Replacement rewrites which item that inventory slot points to — the save layout cannot grow. The game validates items on load; restore the automatic backup if one misbehaves.</p>
            </div>}
          </>}
        </section>}
        {section === "perks" && fields && canEdit && <section className="save-step" role="tabpanel" id="save-panel-perks" aria-labelledby="save-tab-perks">
          <details className="save-guide" open>
            <summary>How perks work here</summary>
            <ul>
              <li>The save keeps a small table of perk ranks. A perk with a <strong>stored rank</strong> can be raised in place up to its <strong>stored limit</strong> (the rank the save says you may hold); that is the same rule the game applies when you spend a point.</li>
              <li>Perks without a stored rank can be acquired when their prerequisites are met. A mapped book unlock can open a locked rank before acquisition; apply the book unlock first, then inspect the new choices.</li>
              <li>Ranks are never lowered here: the game ties spent points and equipped abilities to them, and unpicking that safely needs its respec.</li>
              <li>Nothing is written until you press <strong>Apply</strong> below; every write keeps an automatic backup.</li>
            </ul>
          </details>
          {fields.traitsUnavailable && <p className="feature-status" role="note">This save's perk table could not be read: {fields.traitsUnavailable}</p>}
          {perkMetadataNote && <p className="save-step-hint">{perkMetadataNote}</p>}
          <p className="save-step-hint" role="note"><strong>Verified in game on Quicksave2:</strong> acquiring rank 1 of Sustained Focus (Shared_FocusCharges) produced the learned first-rank state and 2 maximum Activation Charges without spending the save's 7 skill points. <strong>Unverified in game:</strong> book unlocks and every other perk or rank remain individually unproven.</p>
          <div className="save-item-toolbar">
            <input aria-label="Search perks" value={perkFilter} disabled={operationBusy} onChange={event => setPerkFilter(event.target.value)} placeholder="Search perk name or internal id…" />
            <select aria-label="Perk tree" value={perkTree} disabled={operationBusy} onChange={event => setPerkTree(event.target.value)}>
              {perkTrees.map(tree => <option key={tree} value={tree}>{tree}</option>)}
            </select>
          </div>
          <p className="save-step-hint">{perkRows.length} shown. {perkCounts.catalog} catalog · {perkCounts.mapped} acquisition structures mapped · {perkCounts.available} eligible now in this save · {perkCounts.learned} learned</p>
          <div className="save-item-table" role="table" aria-label="Perks and traits">
            <div className="save-item-head save-perk-row" role="row"><span role="columnheader">Perk / trait</span><span role="columnheader">Tree</span><span role="columnheader">Stored limit</span><span role="columnheader">Rank</span></div>
            <div className="save-item-body save-scroll-list">
                {perkRows.map((row) => { const { trait, name, tree, description, editable } = row; return <div key={trait.id} className="save-item-row save-perk-row" role="row" title={description || undefined}>
                <span className="save-item-cell save-item-name" role="cell"><PerkIcon id={trait.id} name={name} tree={tree} iconStatus={row.meta?.iconStatus} /><span><strong>{name}</strong><small>{trait.id} · {row.classification} · {row.acquisitionState}{trait.storedRank ? " · stored rank" : ""}</small>{row.reason && <small className="save-perk-reason">{row.reason}</small>}</span></span>
                <span className="save-item-cell" role="cell">{tree}</span>
                <span className="save-item-cell" role="cell">{trait.storedRank ? trait.accessLimit : "—"}</span>
                <span className="save-item-cell save-item-quantity" role="cell">{editable
                  ? <input aria-label={`Rank for ${trait.id}`} inputMode="numeric" disabled={operationBusy} value={pending.traitRanks[trait.id] ?? ""} placeholder={`keep ${trait.rank}`}
                    onChange={event => setPending(p => ({ ...p, traitRanks: { ...p.traitRanks, [trait.id]: event.target.value } }))} />
                  : <span className="save-perk-fixed">{trait.storedRank ? `${trait.rank} (at limit)` : "Not learned"}</span>}
                {!trait.storedRank && <label className="save-perk-action" title={perkOptions.get(trait.id)?.acquisitionReason ?? "Inspect local metadata to check this perk."}>Acquire rank<input aria-label={`Acquire rank for ${trait.id}`} inputMode="numeric" disabled={operationBusy || !perkOptions.get(trait.id)?.acquisitionRanks.length} value={perkAcquisitions[trait.id] ?? ""} placeholder={perkOptions.get(trait.id)?.acquisitionRanks.join(", ") || "unavailable"}
                  onChange={event => setPerkAcquisitions(current => ({ ...current, [trait.id]: event.target.value }))} /></label>}
                {!!perkOptions.get(trait.id)?.bookRanks.length && <label className="save-perk-action">Unlock book rank<input aria-label={`Unlock book for ${trait.id}`} inputMode="numeric" disabled={operationBusy} value={bookAccess[trait.id] ?? ""} placeholder={perkOptions.get(trait.id)?.bookRanks.join(", ")}
                  onChange={event => setBookAccess(current => ({ ...current, [trait.id]: event.target.value }))} /></label>}
                </span>
              </div>})}
              {!perkRows.length && <p>{fields.traits.length || perkMetadata.size ? `No perks match “${perkFilter}”.` : "This save stores no perk ranks yet."}</p>}
            </div>
          </div>
        </section>}
        {section !== "backups" && fields && canEdit && <section className="save-step save-apply" aria-labelledby="save-step-apply">
          <h4 id="save-step-apply">Apply</h4>
          <p className="save-step-hint">{changeCount ? `${changeCount} change${changeCount === 1 ? "" : "s"} waiting. Applying backs the save up, writes it, and reads it back to prove the new values.` : "Nothing queued yet — change a value above and it will be listed here."}</p>
          {draftError && <p role="alert">{draftError}</p>}
          <div className="feature-actions">
            <button type="button" disabled={operationBusy || Boolean(draftError) || changeCount === 0} onClick={() => void applyEdit(changes)}>Apply {changeCount || "no"} change{changeCount === 1 ? "" : "s"} with automatic backup</button>
            <button type="button" disabled={operationBusy || (!changeCount && !draftError)} onClick={resetEdits}>Reset edits</button>
          </div>
          {editOutcome && <p className="feature-status" role="status">Changed: {editOutcome.verification.changedFields.join(", ")}. Backup: {editOutcome.backup.backupPath}</p>}
        </section>}
        {section === "backups" && <section className="save-step" role="tabpanel" id="save-panel-backups" aria-labelledby="save-tab-backups">
          <details className="save-guide" open>
            <summary>How backups work</summary>
            <ul>
              <li>Every Apply, quick action and preset copies the save (and its companion files) to a backup folder first — the exact bytes, so restoring puts things back precisely.</li>
              <li><strong>Create verified backup</strong> takes one by hand before you experiment. <strong>Backup to restore</strong> lists them newest first with the time they were taken.</li>
              <li>Pick a backup and press <strong>Review restoration</strong>: nothing changes until you confirm on the review card, and the current files are backed up again before the restore.</li>
            </ul>
          </details>
          {editOutcome && <p className="feature-status" role="status">Changed: {editOutcome.verification.changedFields.join(", ")}. Backup: {editOutcome.backup.backupPath}</p>}
        <div className="feature-actions"><button type="button" disabled={operationBusy} onClick={() => void operate("backup")}>Create verified backup</button></div>
        <div className="feature-fields"><label>Backup to restore<select aria-label="Backup to restore" value={backupId} disabled={operationBusy} onChange={event => { setBackupId(event.target.value); setPreview(undefined); }}><option value="">Choose a backup</option>{backups.map(backup => <option key={backup.backupId} value={backup.backupId}>{backup.createdAt} · {backup.sha256.slice(0, 12)}</option>)}</select></label>
          <button type="button" disabled={operationBusy || !backupId} onClick={() => void operate("preview")}>Review restoration</button></div>
        {preview && <section className="restore-preview" aria-label="Pending restoration"><h4>Pending restoration</h4><p>{preview.message}</p><p className="file-path">{preview.fullPath}</p><p>Files: {preview.files.join(", ")}</p><p className="file-path">Current: {preview.currentSha256}<br />Restore: {preview.restoredSha256}</p><div className="feature-actions"><button type="button" disabled={operationBusy} onClick={() => void operate("restore")}>Back up current files &amp; restore</button><button type="button" disabled={operationBusy} onClick={() => setPreview(undefined)}>Cancel restoration</button></div></section>}
        </section>}
      </>}
    </>}
    {message && <p role="status" className="file-path">{message}</p>}
  </section>;
}
