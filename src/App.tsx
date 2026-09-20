import { ReferenceDashboard, PlayerOptions, PlayerMovementControls, PlayerReferenceControls, PlayerParryWindow } from "./ReferenceDashboard";
import { StoryDaySettings } from "./StoryDaySettings";
import { InterfaceScaleSettings } from "./InterfaceScaleSettings";
import {
  Backpack,
  ChevronDown,
  Eye,
  Footprints,
  Globe2,
  HeartPulse,
  BellRing,
  Minus,
  Square,
  Copy,
  Save,
  PersonStanding,
  ScrollText,
  Search,
  Settings,
  Sparkles,
  Swords,
  X,
  Award,
  MessageSquareText,
  type LucideIcon,
} from "lucide-react";
import { useCallback, useEffect, useLayoutEffect, useMemo, useReducer, useRef, useState } from "react";
import { CONTROL_CAPABILITIES } from "./gameplayControls";
import { createModAdapter } from "./modAdapter";
import { WindowDragHandle } from "./WindowDragHandle";
import { FeatureCredits } from "./FeatureCredits";
import { SaveTools } from "./SaveTools";
import { EyeAppearancePanel } from "./EyeAppearancePanel";
import { HairColorPanel } from "./HairColorPanel";
import { SkinTintPanel } from "./SkinTintPanel";
import { useImportedMenu, IMPORTED_MENU_CATEGORIES, importedSectionMatches, DEV_TESTING_SECTIONS, type Dispatch as ImportedMenuDispatch } from "./importedMenuState";
import { ImportedMenuPanel, ImportedMenuConfirmation, ImportedActionFeedback } from "./ImportedMenuPanel";
import { parseQuestJournal } from "../electron/runtimeReadback";
import { QuestReminderSettings } from "./QuestReminderSettings";
import { TooltipLayer } from "./TooltipLayer";
import { readStyledTooltipsPreference, writeStyledTooltipsPreference } from "./tooltipPreference";
import {
  characterAppearanceReducer,
  createCharacterAppearanceState,
  selectDisplayedCharacterAppearance,
  type CharacterAppearanceChange,
} from "./characterAppearanceState";
import {
  type CommandValue,
  type GameplayCapability,
  type QuestState,
  type RuntimeInfo,
  type RuntimeResult,
} from "./runtimeContract";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_app");

/** What the menu can honestly say about the installed game.
 *  The marketing version is only ever confirmed from the in-game version screen, so
 *  after a game patch the footer reports the build identity it verified itself - the
 *  Steam build and changelist read from the executable - rather than nothing at all. */
function gameIdentityLabel(info: RuntimeInfo): string {
  if (info.installedGameVersion) return `Game ${info.installedGameVersion.version} (${info.installedGameVersion.changelist})`;
  if (info.installedBuildId && info.installedGameChangelist) return `Game build ${info.installedBuildId} (CL ${info.installedGameChangelist})`;
  if (info.installedBuildId) return `Game build ${info.installedBuildId}`;
  return "Game version unavailable";
}

const DESIGN_WIDTH = 1672;
const DESIGN_HEIGHT = 941;
const PRESET_STORAGE_KEY = "blood-of-dawnwalker-menu-local-presets-v2";
const TOAST_DURATION_MS = 2200;
// An objective reminder is worth reading, so it stays up longer than a confirmation.
const OBJECTIVE_TOAST_DURATION_MS = 7000;
const RUNTIME_REFRESH_VISIBLE_MS = 2000;
const RUNTIME_REFRESH_HIDDEN_MS = 10000;
const ADD_GOLD_HOTKEY_AMOUNT = 10000;
// Skill points, XP, Corruption, perk grants and the Ultimate unlocks are all levelling
// controls, so they render inside the Player level card instead of as loose cards after
// it. Listed once so the card and the panel below it can never both draw them.
const PLAYER_PROGRESSION_SECTIONS = ["DWSkills", "DWXP", "DWMutation", "DWTraitGrant", "DWUltimateControls"] as const;
// PlayerOptions draws one region of the Player controls at a time, so Corruption and
// Experience Multiplier (rendered in the Player level card), the four movement controls
// (rendered in their own labeled block), and Blood Energy (rendered after that block)
// each keep exactly one home.
const PLAYER_RESOURCE_OPTIONS = ["Rapid stamina refill", "Vampire form override", "Infinite Health"] as const;
const PLAYER_BLOOD_OPTIONS = ["Blood Energy"] as const;
const DISCONNECTED_RUNTIME_INFO: RuntimeInfo = Object.freeze({
  platform: "unknown",
  mode: "disconnected",
  connected: false,
  gameRunning: false,
  buildVerified: false,
  interactionEligible: false,
  capabilities: [],
  activeCapabilities: [],
});

// Combat is a section inside Player, not a category of its own.
type NavId = "overview" | "player" | "inventory" | "world" | "teleport" | "visuals" | "quests" | "save-editor" | "settings";
type PanelId = NavId;
type PresetName = "Default Preset" | "Custom Preset" | "Night Stalker";
type SavedPresetName = Exclude<PresetName, "Default Preset">;

type LocalUiPreset = Readonly<{
  activeNav: NavId;
  searchQuery: string;
}>;

type MenuState = Readonly<{
  toggles: Record<string, boolean>;
  values: Record<string, number>;
  choices: Record<string, string>;
  traitPoints: number;
}>;

type DispatchOutcome = Readonly<{
  applied: boolean;
  readback?: CommandValue;
  result?: RuntimeResult;
}>;

function primitiveReadback(result: RuntimeResult): CommandValue | undefined {
  return typeof result.readback === "boolean" || typeof result.readback === "number" || typeof result.readback === "string"
    ? result.readback
    : undefined;
}

function booleanReadback(readback: CommandValue | undefined): boolean | undefined {
  if (typeof readback === "boolean") return readback;
  if (readback === 1 || (typeof readback === "string" && ["true", "1", "on"].includes(readback.toLowerCase()))) return true;
  if (readback === 0 || (typeof readback === "string" && ["false", "0", "off"].includes(readback.toLowerCase()))) return false;
  return undefined;
}

function numberReadback(readback: CommandValue | undefined): number | undefined {
  if (typeof readback === "number" && Number.isFinite(readback)) return readback;
  if (typeof readback === "string" && readback.trim()) {
    const parsedNumber = Number(readback);
    if (Number.isFinite(parsedNumber)) return parsedNumber;
  }
  return undefined;
}

function nonnegativeInt32Readback(readback: CommandValue | undefined): number | undefined {
  const parsed = typeof readback === "number"
    ? readback
    : typeof readback === "string" && readback.trim() ? Number(readback) : undefined;
  return typeof parsed === "number" && Number.isInteger(parsed) && parsed >= 0 && parsed <= 2_147_483_647
    ? parsed
    : undefined;
}

function difficultyReadback(readback: CommandValue | undefined): string | undefined {
  const parsed = typeof readback === "number"
    ? readback
    : typeof readback === "string" && readback.trim() ? Number(readback) : undefined;
  return typeof parsed === "number" && Number.isInteger(parsed) && parsed >= 0 && parsed <= 3
    ? String(parsed)
    : undefined;
}

function locationNameReadback(readback: CommandValue | undefined): string | undefined {
  if (typeof readback !== "string" || !readback.trim() || /[\r\n;=]/.test(readback)
    || new TextEncoder().encode(readback).length > 64) return undefined;
  return readback.trim();
}

const initialState: MenuState = {
  toggles: {
    godMode: false,
    infiniteHealth: false,
    unlimitedStamina: false,
    sprintNoDrain: false,
    infiniteBloodEnergy: false,
    hudVisible: true,
  },
  values: {
    bloodEnergy: 65,
    gameSpeed: 1,
    addGoldAmount: 10000,
    addItemQuantity: 1,
    addLevelTarget: 2,
  },
  choices: {
    savedLocation: "",
    rpgDifficulty: "",
    actionDifficulty: "",
    addItemPath: "",
    unblockTraitId: "",
  },
  traitPoints: 0,
};

const presetNames: readonly PresetName[] = ["Default Preset", "Custom Preset", "Night Stalker"];
const DEFAULT_LOCAL_UI_PRESET: LocalUiPreset = Object.freeze({ activeNav: "player", searchQuery: "" });
const navIds: readonly NavId[] = ["overview", "player", "inventory", "world", "teleport", "visuals", "quests", "save-editor", "settings"];

function normalizeLocalUiPreset(candidate: Partial<LocalUiPreset> | undefined): LocalUiPreset {
  const candidateNav = candidate?.activeNav;
  const activeNav = candidateNav && navIds.includes(candidateNav) ? candidateNav : DEFAULT_LOCAL_UI_PRESET.activeNav;
  const searchQuery = typeof candidate?.searchQuery === "string" ? candidate.searchQuery.slice(0, 160) : "";
  return { activeNav, searchQuery };
}

const ACTIVE_TOGGLE_CAPABILITIES = Object.freeze({
  godMode: CONTROL_CAPABILITIES.godMode,
  infiniteHealth: CONTROL_CAPABILITIES.infiniteHealth,
  unlimitedStamina: CONTROL_CAPABILITIES.unlimitedStamina,
  infiniteBloodEnergy: CONTROL_CAPABILITIES.infiniteBloodEnergy,
} as const);

const navItems: readonly { id: NavId; label: string; icon: LucideIcon }[] = [
  { id: "player", label: "Player", icon: PersonStanding },
  { id: "world", label: "World", icon: Globe2 },
  { id: "inventory", label: "Inventory", icon: Backpack },
  { id: "teleport", label: "Teleport", icon: Sparkles },
  { id: "visuals", label: "Visuals", icon: Eye },
  { id: "quests", label: "Quests", icon: ScrollText },
  { id: "settings", label: "Settings", icon: Settings },
];

const SAVE_EDITOR_SEARCH_TERMS = "save editor save editing save tools local files inspect backup restore recovery time money health daytime stat points";

// Combat controls moved into Player, so their search terms and section ids travel with them.
const COMBAT_SEARCH_TERMS: readonly string[] = [
  "infinite blood energy",
  "rpg difficulty",
  "action difficulty",
  "focus ability cooldowns",
  "extended parry window perfect parry set by caller magnitude",
  "damage defense enemy level kill actions",
  "attack speed sprint block dodge stamina focus range smell zoom target visibility",
];
const COMBAT_SECTION_IDS: readonly string[] = ["DWActivationControl", "DWCooldownControl", "DWParryAssist", "DWCombatDiscovery"];

const panelSearchEntries: Readonly<Record<PanelId, readonly string[]>> = {
  overview: ["player god mode health stamina blood humanity skills level experience speed super jump no clip fly fall damage combat damage defense freeze one hit infinite blood cooldown parry enemy level difficulty kill world time weather season game speed lock moon gravity ambient reveal fog inventory gold red essence item weight durability crafting teleport waypoint marker save saved location"],
  player: ["god mode", "player level target current progression", "sprint no drain stamina cost", "rapid stamina refill", "vampire form override", "infinite health blood energy humanity experience multiplier speed multiplier super jump no clip fly fall damage", "unlimited activation charge instant ability cooldown super damage one-hit kills unlimited consumables edit item amount zero weight ignore crafting requirement unlock all crafting recipes", ...COMBAT_SEARCH_TERMS],
  inventory: ["inventory items equipment coins currency gold materials manuals keys"],
  world: ["game speed", "story days deadline time configuration", "world state time weather quest phase"],
  teleport: ["save location", "saved locations teleport", "session-only locations"],
  visuals: ["eye appearance color presets"],
  quests: ["quest journal tracked objectives progress active optional readback"],
  "save-editor": [SAVE_EDITOR_SEARCH_TERMS],
  settings: [SAVE_EDITOR_SEARCH_TERMS, "interface scale zoom text size display", "objective reminders quest notification toast alert", "reset ui view", "credits creators references inspired"],
};

function calculateScale(viewportWidth: number, viewportHeight: number): number {
  return Math.min(viewportWidth / DESIGN_WIDTH, viewportHeight / DESIGN_HEIGHT);
}

function readPersistedPresets(): Record<SavedPresetName, LocalUiPreset> {
  const fallback = {
    "Custom Preset": { ...DEFAULT_LOCAL_UI_PRESET },
    "Night Stalker": { ...DEFAULT_LOCAL_UI_PRESET },
  };
  try {
    const rawPresets = window.localStorage.getItem(PRESET_STORAGE_KEY);
    if (!rawPresets) return fallback;
    const parsedPresets = JSON.parse(rawPresets) as Partial<Record<SavedPresetName, Partial<LocalUiPreset>>>;
    return {
      "Custom Preset": normalizeLocalUiPreset(parsedPresets["Custom Preset"]),
      "Night Stalker": normalizeLocalUiPreset(parsedPresets["Night Stalker"]),
    };
  } catch (error: unknown) {
    console.warn("The saved Dawnwalker local presets were invalid and have been reset.", error);
    return fallback;
  }
}

type CapabilityControlProps = Readonly<{
  capability: GameplayCapability;
  available: boolean;
  pending: boolean;
  unverified?: boolean;
}>;

function capabilityControlTitle(capability: GameplayCapability, available: boolean, pending: boolean): string | undefined {
  if (pending) return "Waiting for the verified offline bridge.";
  if (!available) return `Unavailable until the verified offline bridge advertises ${capability}.`;
  return undefined;
}

function Toggle({ label, enabled, onChange, capability, available, pending, unverified }: {
  label: string;
  enabled: boolean;
  onChange: () => void;
} & CapabilityControlProps) {
  return (
    <button
      type="button"
      className={`toggle ${enabled && !unverified ? "toggle-on" : ""} ${pending ? "control-pending" : ""}`}
      aria-label={`${label}: ${unverified ? "unverified" : enabled ? "on" : "off"}`}
      aria-pressed={unverified ? undefined : enabled}
      aria-busy={pending}
      data-capability={capability}
      disabled={!available || pending}
      title={capabilityControlTitle(capability, available, pending)}
      onClick={onChange}
    >
      <span />
    </button>
  );
}

function ToggleRow({ label, stateKey, enabled, onToggle, capability, available, pending, unverified, showState = false, help, icon: Icon, iconTone }: {
  label: string;
  stateKey: string;
  enabled: boolean;
  onToggle: (key: string, label: string, capability: GameplayCapability) => void;
  showState?: boolean;
  help?: string;
  icon?: LucideIcon;
  iconTone?: "health" | "stamina";
} & CapabilityControlProps) {
  const toggle = <Toggle label={label} enabled={enabled} onChange={() => onToggle(stateKey, label, capability)} capability={capability} available={available} pending={pending} unverified={unverified} />;
  // The icon is decorative: the visible label already names the control.
  const title = Icon
    ? <span className="toggle-title" data-tone={iconTone}><Icon size={16} aria-hidden="true" /><span>{label}</span></span>
    : label;
  return (
    <div className="control-row toggle-row" data-search-label={label.toLowerCase()} data-control-state={available ? "available" : "locked"}>
      <span className={help ? "player-toggle-label" : undefined} title={help}>{title}{help && <small>{help}</small>}</span>
      {showState ? <div className="player-toggle-control">
        {(!available || unverified) && <span className="player-toggle-state" aria-hidden="true">Unavailable</span>}
        {toggle}
      </div> : toggle}
    </div>
  );
}

function SliderRow({ label, value, min = 0, max = 100, step = 1, suffix = "", onCommit, capability, available, pending, unverified }: {
  label: string;
  value: number;
  min?: number;
  max?: number;
  step?: number;
  suffix?: string;
  onCommit: (value: number) => Promise<boolean>;
} & CapabilityControlProps) {
  const [draftValue, setDraftValue] = useState(value);
  const draftValueRef = useRef(value);
  const submittedValueRef = useRef<number | undefined>(undefined);

  useEffect(() => {
    draftValueRef.current = value;
    setDraftValue(value);
  }, [value]);

  const changeDraft = (nextValue: number) => {
    draftValueRef.current = nextValue;
    setDraftValue(nextValue);
  };

  const commitDraft = async () => {
    const nextValue = draftValueRef.current;
    if (!available || pending || nextValue === value || submittedValueRef.current === nextValue) return;
    submittedValueRef.current = nextValue;
    const applied = await onCommit(nextValue);
    submittedValueRef.current = undefined;
    if (!applied) changeDraft(value);
  };

  return (
    <label className="control-row slider-row" data-search-label={label.toLowerCase()} data-control-state={available ? "available" : "locked"}>
      <span>{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={draftValue}
        aria-label={label}
        aria-valuetext={unverified ? "Unavailable" : `${draftValue}${suffix}`}
        style={{ "--range-progress": `${unverified ? 0 : ((draftValue - min) / (max - min)) * 100}%` } as React.CSSProperties}
        aria-busy={pending}
        data-capability={capability}
        disabled={!available || pending}
        title={capabilityControlTitle(capability, available, pending)}
        onChange={(event) => changeDraft(Number(event.target.value))}
        onPointerUp={() => void commitDraft()}
        onKeyUp={(event) => {
          if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) void commitDraft();
        }}
        onBlur={() => void commitDraft()}
      />
      <output>{unverified ? "—" : `${draftValue}${suffix}`}</output>
    </label>
  );
}

function GameplayButton({ capability, available, pending, unverified, disabled, className = "", ...buttonProps }: React.ButtonHTMLAttributes<HTMLButtonElement> & CapabilityControlProps) {
  return (
    <button
      {...buttonProps}
      type="button"
      className={`${className} ${pending ? "control-pending" : ""}`.trim()}
      aria-busy={pending}
      data-capability={capability}
      disabled={Boolean(disabled) || !available || pending || unverified}
      title={buttonProps.title ?? capabilityControlTitle(capability, available, pending)}
    />
  );
}

function Panel({ id, icon: Icon, title, visible, emphasized, children }: { id: PanelId; icon: LucideIcon; title: string; visible: boolean; emphasized: boolean; children: React.ReactNode }) {
  return (
    <section id={`panel-${id}`} className={`panel panel-${id} ${emphasized ? "panel-emphasized" : ""}`} hidden={!visible} aria-labelledby={`${id}-heading`}>
      <header className="panel-title">
        <Icon size={19} aria-hidden="true" />
        <h2 id={`${id}-heading`}>{title}</h2>
      </header>
      <div className="panel-content">{children}</div>
    </section>
  );
}

const CAPABILITY_SUMMARIES: Readonly<Record<string, string>> = {
  "Unlimited Weight target under correction": "Unlimited Weight is unavailable while carry capacity and restoration are being verified.",
  "Other inventory contracts remain locked": "Additional inventory changes are unavailable until they pass save and restoration tests.",
  "Two-axis development pilot": "Action and RPG difficulty are separate session overrides. Both restore their original settings.",
  "Cooldown replacement under live validation": "Cooldown changes are unavailable until their effects and restoration are verified in game.",
  "Extended Parry Window unavailable": "Extended parry timing is unavailable. Its required player settings are not yet verified.",
  "World state safety": "Time and weather controls are unavailable because they can affect quests and story progression.",
  "Eye appearance unavailable": "Eye color changes are unavailable. Live appearance changes and restoration still need verification.",
  "Quest Journal unavailable": "Quest information is unavailable until a compatible game connection is established.",
};

function CapabilityNotice({ title, children, compact = false }: { title: string; children: React.ReactNode; compact?: boolean }) {
  const summary = CAPABILITY_SUMMARIES[title];
  return (
    <div className="capability-notice" role="note">
      <strong>{title}</strong>
      <p>{summary ?? children}</p>
      {summary && !compact && <details className="capability-details"><summary>Technical details</summary><p>{children}</p></details>}
    </div>
  );
}

const QUEST_STATE_LABELS: Readonly<Record<QuestState, string>> = Object.freeze({
  active: "Active",
  success: "Completed",
  failure: "Failed",
  unknown: "Unclassified",
});

function formatQuestCount(value: number): string {
  return Number.isInteger(value) ? value.toString() : value.toFixed(2).replace(/\.?0+$/, "");
}

function App() {
  const modAdapter = useMemo(() => createModAdapter(), []);
  const [menuState, setMenuState] = useState<MenuState>(initialState);
  const [activeNav, setActiveNav] = useState<NavId>(DEFAULT_LOCAL_UI_PRESET.activeNav);
  // F9 remains available while another tab is open; snapshots do not invoke game getters.
  const importedMenu = useImportedMenu(true);
  const [appearanceState, dispatchAppearance] = useReducer(
    characterAppearanceReducer,
    importedMenu.snapshot,
    createCharacterAppearanceState,
  );
  const appearance = selectDisplayedCharacterAppearance(appearanceState);
  const appearanceOperation = useRef<{ sessionId: string; operationId: string } | undefined>(undefined);
  const dispatchImportedTracked = importedMenu.dispatchTracked;
  const previewAppearance = useCallback((change: CharacterAppearanceChange) => {
    dispatchAppearance({ type: "preview", change });
  }, []);
  const dispatchAppearanceCommand = useCallback(async (request: Parameters<ImportedMenuDispatch>[0]): Promise<void> => {
    const result = await dispatchImportedTracked(request);
    if (!result?.accepted || !result.operationId) {
      dispatchAppearance({ type: "failure" });
      return;
    }
    appearanceOperation.current = { sessionId: result.sessionId, operationId: result.operationId };
  }, [dispatchImportedTracked]);
  useLayoutEffect(() => {
    dispatchAppearance({ type: "snapshot", snapshot: importedMenu.snapshot });
    const pendingAppearance = appearanceOperation.current;
    if (!pendingAppearance) return;
    if (!importedMenu.snapshot.ready || importedMenu.snapshot.sessionId !== pendingAppearance.sessionId) {
      appearanceOperation.current = undefined;
      dispatchAppearance({ type: "failure" });
      return;
    }
    const operation = importedMenu.snapshot.operation;
    if (operation?.id !== pendingAppearance.operationId || !["completed", "failed"].includes(operation.status)) return;
    appearanceOperation.current = undefined;
    dispatchAppearance(operation.status === "completed"
      ? { type: "settled", snapshot: importedMenu.snapshot }
      : { type: "failure" });
  }, [importedMenu.snapshot]);
  const importedCurrency = importedMenu.snapshot.sections.find((section) => section.id === "DWCurrency");
  const currencyItems = importedCurrency?.items.flatMap((item) => [item, ...(item.items ?? [])]);
  const currencyAmount = currencyItems?.find((item) => item.id === "amount");
  const currencyAdd = currencyItems?.find((item) => item.id === "add");
  const goldSequence = useRef<{ session: string; previous: number; phase: "amount" | "add" | "restore"; priorOperation?: string; expires: number } | null>(null);
  const importedGoldAvailable = !importedMenu.disabled && currencyAmount !== undefined && currencyAdd !== undefined
    && currencyAmount.enabled !== false && !currencyAmount.disabled && currencyAdd.enabled !== false && !currencyAdd.disabled;
  useEffect(() => {
    const sequence = goldSequence.current;
    if (!sequence) return;
    const state = importedMenu.snapshot;
    if (!state.ready || state.sessionId !== sequence.session || state.confirmation || Date.now() > sequence.expires) { goldSequence.current = null; return; }
    if (importedMenu.pending || !state.operation || state.operation.id === sequence.priorOperation
      || ["queued", "running"].includes(state.operation.status)) return;
    if (sequence.phase === "restore") { goldSequence.current = null; return; }
    if (state.operation.status === "completed" && sequence.phase === "amount" && currencyAmount?.value === ADD_GOLD_HOTKEY_AMOUNT) {
      sequence.phase = "add";
      sequence.priorOperation = state.operation.id;
      void importedMenu.dispatch({ action: "invoke", sectionId: "DWCurrency", itemId: "add" });
      return;
    }
    // Preserve the user's amount after the one requested grant (or its failure).
    // Do not overwrite a value they changed while this sequence was completing.
    if (sequence.previous !== ADD_GOLD_HOTKEY_AMOUNT && currencyAmount?.value === ADD_GOLD_HOTKEY_AMOUNT) {
      sequence.phase = "restore";
      sequence.priorOperation = state.operation.id;
      void importedMenu.dispatch({ action: "set", sectionId: "DWCurrency", itemId: "amount", value: sequence.previous });
    } else goldSequence.current = null;
  }, [importedMenu, currencyAmount]);
  useEffect(() => {
    const sequence = goldSequence.current;
    if (!sequence) return;
    const timeout = setTimeout(() => {
      if (goldSequence.current === sequence) goldSequence.current = null;
    }, Math.max(0, sequence.expires - Date.now()));
    return () => clearTimeout(timeout);
  }, [importedMenu.pending, importedMenu.snapshot]);
  const importedQuests = importedMenu.snapshot.sections.find((section) => section.id === "DWQuestReadback");
  const importedQuestPayload = importedQuests?.items.find((item) => item.id === "snapshot")?.label;

  const importedGodSection = importedMenu.snapshot.sections.find((section) => section.id === "DWCorePlayer");
  const importedGod = importedGodSection?.items.find((item) => item.id === "god" && item.type === "checkbox");
  const importedBlood = importedGodSection?.items.find((item) => item.id === "bloodEnabled" && item.type === "checkbox");
  const importedSprint = importedGodSection?.items.find((item) => item.id === "sprintEnabled" && item.type === "checkbox");
  const importedGodStatus = importedGodSection?.items.find((item) => item.id === "status")?.label;
  const importedCoreControlPending = (itemId: string) => Boolean(
    (importedMenu.pending || ["running", "queued"].includes(importedMenu.snapshot.operation?.status ?? ""))
    && importedMenu.pendingControl?.sectionId === "DWCorePlayer"
    && importedMenu.pendingControl.itemId === itemId,
  );
  const importedWorld = importedMenu.snapshot.sections.find((section) => section.id === "DWCoreWorld");
  const importedDifficulty = importedMenu.snapshot.sections.find((section) => section.id === "DWCoreDifficulty");
  const importedTeleport = importedMenu.snapshot.sections.find((section) => section.id === "DWCoreTeleport");
  const importedDestination = importedTeleport?.items.find((item) => item.id === "destination");
  const importedLevel = importedMenu.snapshot.sections.find((section) => section.id === "DWCoreLevel");
  const levelCurrent = importedLevel?.items.find((item) => item.id === "current")?.value;
  const levelTarget = importedLevel?.items.find((item) => item.id === "target");
  const levelTargetValid = typeof levelTarget?.value === "number" && levelTarget.options?.some((option) => typeof option !== "string" && option.value === levelTarget.value);
  const destinationValid = typeof importedDestination?.value === "string" && importedDestination.options?.some((option) => typeof option === "string" ? option === importedDestination.value : option.value === importedDestination.value);
  const [locationError, setLocationError] = useState("");
  const [locationPending, setLocationPending] = useState(false);
  const stagedLocationSave = useRef<{ session: string; name: string; operationId?: string; expires: number } | null>(null);
  useEffect(() => {
    const staged = stagedLocationSave.current;
    if (!staged) return;
    const stop = (message: string) => { stagedLocationSave.current = null; setLocationPending(false); setLocationError(message); };
    const timeout = setTimeout(() => stop("Saving the location timed out. Check the connection, then try again."), Math.max(0, staged.expires - Date.now()));
    const state = importedMenu.snapshot;
    if (!state.ready || staged.session !== state.sessionId) stop("The player session changed. Enter a name and save the position again.");
    else if (staged.operationId && state.operation?.id === staged.operationId && !importedMenu.pending) {
      if (state.operation.status === "failed") stop("The game rejected the location name. Check the name and try again.");
      else if (state.operation.status === "completed") {
        const nativeName = importedTeleport?.items.find((item) => item.id === "name")?.value;
        if (nativeName !== staged.name) stop("The saved name changed before confirmation. Try again.");
        else {
          stagedLocationSave.current = null; setLocationPending(false);
          void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreTeleport", itemId: "save" });
        }
      }
    }
    return () => clearTimeout(timeout);
  }, [importedMenu, importedTeleport]);
  const importedRpg = importedDifficulty?.items.find((item) => item.id === "rpg");
  const importedAction = importedDifficulty?.items.find((item) => item.id === "action");
  const importedSpeed = importedWorld?.items.find((item) => item.id === "speed");
  const importedWorldStatus = importedWorld?.items.find((item) => item.id === "status")?.label;
  const importedSpeedAvailable = !importedMenu.disabled && importedSpeed?.enabled !== false && importedSpeed?.disabled !== true;
  const [searchQuery, setSearchQuery] = useState("");
  const [settingsTab, setSettingsTab] = useState<"general" | "save-editor" | "credits">("general");
  // Styled tooltips are a per-machine interface preference, kept beside the UI presets.
  const [styledTooltips, setStyledTooltips] = useState(readStyledTooltipsPreference);
  const toggleStyledTooltips = useCallback((next: boolean) => { setStyledTooltips(next); writeStyledTooltipsPreference(next); }, []);
  const [toast, setToast] = useState("");
  const [toastKind, setToastKind] = useState<"status" | "objective">("status");
  const [windowMaximized, setWindowMaximized] = useState(false);
  useEffect(() => {
    let active = true;
    let receivedEvent = false;
    const desktop = window.dawnwalkerDesktop;
    const unsubscribe = desktop?.onWindowMaximizedChanged?.(value => {
      receivedEvent = true;
      if (active) setWindowMaximized(value);
    });
    void desktop?.isWindowMaximized?.().then(value => {
      if (active && !receivedEvent) setWindowMaximized(value);
    }).catch(() => {});
    return () => { active = false; unsubscribe?.(); };
  }, []);
  const [savedLocationName, setSavedLocationName] = useState("");
  const [savedLocations, setSavedLocations] = useState<readonly string[]>([]);
  const [presetName, setPresetName] = useState<PresetName>("Default Preset");
  const [savedPresets, setSavedPresets] = useState<Record<SavedPresetName, LocalUiPreset>>(readPersistedPresets);
  const [viewportSize, setViewportSize] = useState(() => ({ width: window.innerWidth, height: window.innerHeight }));
  const [interfaceZoom, setInterfaceZoom] = useState(1);
  // Fit the decorative frame to the unzoomed viewport. Shrinking its logical
  // dimensions lets browser zoom enlarge controls instead of cancelling itself.
  const stageScale = calculateScale(viewportSize.width * interfaceZoom, viewportSize.height * interfaceZoom);
  const [runtimeInfo, setRuntimeInfo] = useState<RuntimeInfo>(DISCONNECTED_RUNTIME_INFO);
  const [pendingCapabilities, setPendingCapabilities] = useState<ReadonlySet<GameplayCapability>>(() => new Set());
  const inFlightCapabilitiesRef = useRef(new Set<GameplayCapability>());
  const requestSequenceRef = useRef(0);
  const currentRuntimeRef = useRef<RuntimeInfo>(DISCONNECTED_RUNTIME_INFO);
  const runtimeEpochRef = useRef(0);

  const showToast = useCallback((message: string) => { setToastKind("status"); setToast(message); }, []);
  const showObjectiveToast = useCallback((message: string) => { setToastKind("objective"); setToast(message); }, []);

  useEffect(() => {
    const handleResize = () => setViewportSize({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  useEffect(() => {
    let active = true;
    let changed = false;
    const api = window.dawnwalkerDesktop?.interfaceScale;
    const unsubscribe = api?.onChanged(percent => {
      changed = true;
      if (active) setInterfaceZoom(percent / 100);
    });
    const unsubscribeError = api?.onError(showToast);
    void api?.get().then(percent => {
      if (active && !changed) setInterfaceZoom(percent / 100);
    }).catch(() => { if (active) showToast("Could not read menu size. Reopen the menu to retry."); });
    return () => { active = false; unsubscribe?.(); unsubscribeError?.(); };
  }, [showToast]);

  useEffect(() => {
    let cancelled = false;
    let refreshPending = false;
    let refreshTimer: number | undefined;
    let previousSnapshot = "";

    const scheduleRefresh = () => {
      if (cancelled) return;
      const delay = document.hidden ? RUNTIME_REFRESH_HIDDEN_MS : RUNTIME_REFRESH_VISIBLE_MS;
      refreshTimer = window.setTimeout(() => void refreshRuntimeInfo(), delay);
    };

    const refreshRuntimeInfo = async () => {
      if (cancelled || refreshPending) return;
      refreshPending = true;
      try {
        const nextInfo = await modAdapter.getRuntimeInfo();
        if (cancelled) return;
        const previousRuntime = currentRuntimeRef.current;
        if (previousRuntime.sessionId !== nextInfo.sessionId
          || (previousRuntime.interactionEligible && !nextInfo.interactionEligible)) {
          runtimeEpochRef.current += 1;
          setSavedLocations([]);
          setMenuState(current => ({ ...current, choices: { ...current.choices, savedLocation: "" } }));
        }
        currentRuntimeRef.current = nextInfo;
        const nextSnapshot = JSON.stringify(nextInfo);
        if (!cancelled && nextSnapshot !== previousSnapshot) {
          previousSnapshot = nextSnapshot;
          setRuntimeInfo(nextInfo);
        }
      } catch (error: unknown) {
        console.warn("Dawnwalker runtime status refresh failed safely.", error);
        if (!cancelled) {
          previousSnapshot = "";
          currentRuntimeRef.current = DISCONNECTED_RUNTIME_INFO;
          runtimeEpochRef.current += 1;
          setRuntimeInfo(DISCONNECTED_RUNTIME_INFO);
          setSavedLocations([]);
          setMenuState(current => ({ ...current, choices: { ...current.choices, savedLocation: "" } }));
        }
      } finally {
        refreshPending = false;
        scheduleRefresh();
      }
    };

    const handleVisibilityChange = () => {
      if (refreshTimer !== undefined) window.clearTimeout(refreshTimer);
      refreshTimer = undefined;
      void refreshRuntimeInfo();
    };

    document.addEventListener("visibilitychange", handleVisibilityChange);
    void refreshRuntimeInfo();
    return () => {
      cancelled = true;
      if (refreshTimer !== undefined) window.clearTimeout(refreshTimer);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [modAdapter]);

  useEffect(() => {
    if (!runtimeInfo.connected || runtimeInfo.compatibilityIssue) return;
    const activeCapabilities = new Set(runtimeInfo.activeCapabilities);
    setMenuState((currentState) => {
      const synchronizedToggles = { ...currentState.toggles };
      let changed = false;
      for (const [stateKey, capability] of Object.entries(ACTIVE_TOGGLE_CAPABILITIES)) {
        const active = activeCapabilities.has(capability);
        if (synchronizedToggles[stateKey] !== active) {
          synchronizedToggles[stateKey] = active;
          changed = true;
        }
      }
      return changed ? { ...currentState, toggles: synchronizedToggles } : currentState;
    });
  }, [runtimeInfo.activeCapabilities, runtimeInfo.connected, runtimeInfo.compatibilityIssue]);

  useEffect(() => {
    if (!runtimeInfo.connected) return;
    const rawBlood = runtimeInfo.player?.bloodEnergy;
    const maximumBlood = runtimeInfo.player?.maxBloodEnergy;
    const bloodPercentage = typeof rawBlood === "number" && typeof maximumBlood === "number" && maximumBlood > 0
      ? Math.min(100, Math.max(0, (rawBlood / maximumBlood) * 100))
      : undefined;
    const traitPoints = runtimeInfo.player?.traitPoints;
    const gameSpeed = runtimeInfo.controls?.gameSpeed;
    const hudVisible = runtimeInfo.controls?.hudVisible;
    const rpgDifficulty = runtimeInfo.controls?.rpgDifficulty;
    const actionDifficulty = runtimeInfo.controls?.actionDifficulty;

    setMenuState((currentState) => {
      const nextValues = { ...currentState.values };
      const nextToggles = { ...currentState.toggles };
      const nextChoices = { ...currentState.choices };
      let changed = false;
      if (bloodPercentage !== undefined && nextValues.bloodEnergy !== bloodPercentage) {
        nextValues.bloodEnergy = bloodPercentage;
        changed = true;
      }
      if (gameSpeed !== undefined && nextValues.gameSpeed !== gameSpeed) {
        nextValues.gameSpeed = gameSpeed;
        changed = true;
      }
      if (hudVisible !== undefined && nextToggles.hudVisible !== hudVisible) {
        nextToggles.hudVisible = hudVisible;
        changed = true;
      }
      if (rpgDifficulty !== undefined && nextChoices.rpgDifficulty !== String(rpgDifficulty)) {
        nextChoices.rpgDifficulty = String(rpgDifficulty);
        changed = true;
      }
      if (actionDifficulty !== undefined && nextChoices.actionDifficulty !== String(actionDifficulty)) {
        nextChoices.actionDifficulty = String(actionDifficulty);
        changed = true;
      }
      if (traitPoints !== undefined && currentState.traitPoints !== traitPoints) {
        return { ...currentState, toggles: nextToggles, values: nextValues, choices: nextChoices, traitPoints };
      }
      return changed ? { ...currentState, toggles: nextToggles, values: nextValues, choices: nextChoices } : currentState;
    });
  }, [
    runtimeInfo.connected,
    runtimeInfo.controls?.gameSpeed,
    runtimeInfo.controls?.hudVisible,
    runtimeInfo.controls?.rpgDifficulty,
    runtimeInfo.controls?.actionDifficulty,
    runtimeInfo.player?.bloodEnergy,
    runtimeInfo.player?.maxBloodEnergy,
    runtimeInfo.player?.traitPoints,
  ]);

  useEffect(() => {
    if (!toast) return;
    const duration = toastKind === "objective" ? OBJECTIVE_TOAST_DURATION_MS : TOAST_DURATION_MS;
    const timeoutId = window.setTimeout(() => setToast(""), duration);
    return () => window.clearTimeout(timeoutId);
  }, [toast, toastKind]);

  const advertisedCapabilities = useMemo(() => new Set(runtimeInfo.capabilities), [runtimeInfo.capabilities]);
  const isCapabilityAvailable = useCallback(
    (capability: GameplayCapability) => runtimeInfo.interactionEligible
      && Boolean(runtimeInfo.sessionId)
      && advertisedCapabilities.has(capability),
    [advertisedCapabilities, runtimeInfo.interactionEligible, runtimeInfo.sessionId],
  );
  const isCapabilityPending = useCallback((capability: GameplayCapability) => pendingCapabilities.has(capability), [pendingCapabilities]);

  const dispatchGameplay = useCallback(async (capability: GameplayCapability, value?: CommandValue): Promise<DispatchOutcome> => {
    if (!runtimeInfo.interactionEligible || !runtimeInfo.sessionId || !advertisedCapabilities.has(capability)) {
      showToast(`Unavailable: the verified offline bridge has not advertised ${capability}.`);
      return { applied: false };
    }
    if (inFlightCapabilitiesRef.current.has(capability)) return { applied: false };

    inFlightCapabilitiesRef.current.add(capability);
    setPendingCapabilities(new Set(inFlightCapabilitiesRef.current));
    requestSequenceRef.current += 1;
    const requestId = `renderer-${Date.now().toString(36)}-${requestSequenceRef.current}`;
    const dispatchEpoch = runtimeEpochRef.current;

    try {
      const result = await modAdapter.dispatch(value === undefined
        ? { capability, requestId, sessionId: runtimeInfo.sessionId }
        : { capability, value, requestId, sessionId: runtimeInfo.sessionId });
      if (runtimeEpochRef.current !== dispatchEpoch || !currentRuntimeRef.current.interactionEligible
        || currentRuntimeRef.current.sessionId !== runtimeInfo.sessionId) {
        showToast("The runtime session changed before its response arrived; no UI state was changed.");
        return { applied: false, result };
      }
      if (result.capability !== capability || result.requestId !== requestId) {
        showToast("The runtime bridge returned a mismatched response; no UI state was changed.");
        return { applied: false, result };
      }
      showToast(result.message);
      return {
        applied: result.accepted && result.status === "applied",
        readback: primitiveReadback(result),
        result,
      };
    } catch (error: unknown) {
      console.warn(`Dawnwalker command ${capability} failed safely.`, error);
      showToast(`The verified offline bridge could not apply ${capability}.`);
      return { applied: false };
    } finally {
      inFlightCapabilitiesRef.current.delete(capability);
      setPendingCapabilities(new Set(inFlightCapabilitiesRef.current));
    }
  }, [advertisedCapabilities, modAdapter, runtimeInfo.interactionEligible, runtimeInfo.sessionId, showToast]);

  const setToggle = useCallback(async (key: string, _label: string, capability: GameplayCapability): Promise<boolean> => {
    const requestedValue = !menuState.toggles[key];
    const outcome = await dispatchGameplay(capability, requestedValue);
    if (!outcome.applied) return false;
    const appliedValue = booleanReadback(outcome.readback);
    if (appliedValue === undefined) {
      showToast("The toggle returned no valid readback; its displayed state was not changed.");
      return false;
    }
    setMenuState((currentState) => ({ ...currentState, toggles: { ...currentState.toggles, [key]: appliedValue } }));
    return true;
  }, [dispatchGameplay, menuState.toggles, showToast]);

  const setValue = useCallback(async (key: string, capability: GameplayCapability, requestedValue: number): Promise<boolean> => {
    const outcome = await dispatchGameplay(capability, requestedValue);
    if (!outcome.applied) return false;
    const appliedValue = numberReadback(outcome.readback);
    const minimum = capability === CONTROL_CAPABILITIES.gameSpeed ? 0.1 : 0;
    const maximum = capability === CONTROL_CAPABILITIES.gameSpeed ? 3 : 100;
    if (appliedValue === undefined || appliedValue < minimum || appliedValue > maximum) {
      showToast("The slider returned no valid readback; its displayed value was not changed.");
      return false;
    }
    setMenuState((currentState) => ({ ...currentState, values: { ...currentState.values, [key]: appliedValue } }));
    return true;
  }, [dispatchGameplay, showToast]);

  const addGold = useCallback(async (requestedDelta = menuState.values.addGoldAmount): Promise<boolean> => {
    if (!Number.isInteger(requestedDelta) || requestedDelta < 1 || requestedDelta > 10000) {
      showToast("Add Gold requires a whole-number amount from 1 to 10,000.");
      return false;
    }
    const outcome = await dispatchGameplay(CONTROL_CAPABILITIES.addGold, requestedDelta);
    if (!outcome.applied) return false;
    const gold = nonnegativeInt32Readback(outcome.readback);
    if (gold === undefined) {
      showToast("The bridge accepted Add Gold but returned an invalid balance; the UI was not changed.");
      return false;
    }
    setRuntimeInfo((currentInfo) => ({
      ...currentInfo,
      player: { ...(currentInfo.player ?? {}), gold },
    }));
    return true;
  }, [dispatchGameplay, menuState.values.addGoldAmount, showToast]);

  useEffect(() => {
    const unsubscribe = window.dawnwalkerDesktop?.onGameplayHotkey?.((action) => {
      if (action !== "add-gold") return;
      if (!importedCurrency) { void addGold(ADD_GOLD_HOTKEY_AMOUNT); return; }
      if (!importedGoldAvailable || goldSequence.current || stagedLocationSave.current) return;
      const previous = currencyAmount?.value;
      if (typeof previous !== "number" || !Number.isInteger(previous) || previous < 1 || previous > 999999) return;
      goldSequence.current = { session: importedMenu.snapshot.sessionId, previous, phase: "amount", priorOperation: importedMenu.snapshot.operation?.id, expires: Date.now() + 30000 };
      void importedMenu.dispatch({ action: "set", sectionId: "DWCurrency", itemId: "amount", value: ADD_GOLD_HOTKEY_AMOUNT });
    });
    return () => unsubscribe?.();
  }, [addGold, importedCurrency, importedGoldAvailable, importedMenu, currencyAmount]);

  const setLocalChoice = useCallback((key: string, value: string) => {
    setMenuState((currentState) => ({ ...currentState, choices: { ...currentState.choices, [key]: value } }));
  }, []);

  const setDifficultyChoice = useCallback(async (
    key: "rpgDifficulty" | "actionDifficulty",
    capability: GameplayCapability,
    requestedValue: string,
  ): Promise<boolean> => {
    const requestedDifficulty = difficultyReadback(requestedValue);
    if (requestedDifficulty === undefined) return false;
    const outcome = await dispatchGameplay(capability, Number(requestedDifficulty));
    if (!outcome.applied) return false;
    const appliedDifficulty = difficultyReadback(outcome.readback);
    if (appliedDifficulty === undefined) {
      showToast("The difficulty setter returned an invalid level; the UI was not changed.");
      return false;
    }
    setMenuState((currentState) => ({
      ...currentState,
      choices: { ...currentState.choices, [key]: appliedDifficulty },
    }));
    return true;
  }, [dispatchGameplay, showToast]);

  const resetUiView = useCallback(() => {
    setActiveNav(DEFAULT_LOCAL_UI_PRESET.activeNav);
    setSearchQuery(DEFAULT_LOCAL_UI_PRESET.searchQuery);
    setPresetName("Default Preset");
    showToast("Local UI view restored. No game commands were sent.");
  }, [showToast]);

  const saveLocalPreset = useCallback(() => {
    const targetName: SavedPresetName = presetName === "Default Preset" ? "Custom Preset" : presetName;
    const nextPresets = { ...savedPresets, [targetName]: { activeNav, searchQuery } };
    try {
      window.localStorage.setItem(PRESET_STORAGE_KEY, JSON.stringify(nextPresets));
    } catch {
      showToast("The UI preset could not be saved locally. Existing presets were preserved.");
      return;
    }
    setSavedPresets(nextPresets);
    setPresetName(targetName);
    showToast(`${targetName} saved this category and search view locally. No game commands were sent.`);
  }, [activeNav, presetName, savedPresets, searchQuery, showToast]);

  const loadLocalPreset = useCallback((selectedName: PresetName) => {
    setPresetName(selectedName);
    const selectedView = selectedName === "Default Preset" ? DEFAULT_LOCAL_UI_PRESET : savedPresets[selectedName];
    setActiveNav(selectedView.activeNav);
    setSearchQuery(selectedView.searchQuery);
    showToast(`${selectedName} loaded as a local category and search view. No game commands were sent.`);
  }, [savedPresets, showToast]);

  const normalizedSearchQuery = searchQuery.trim().toLowerCase();
  const controlMatchesSearch = (searchText: string) => !normalizedSearchQuery || searchText.includes(normalizedSearchQuery);

  const activeCategory = activeNav === "overview" ? { label: "Overview" } : activeNav === "save-editor" ? { label: "Save Editor" } : navItems.find(({ id }) => id === activeNav) ?? navItems[0];
  const activeRail = activeNav === "overview" ? "player" : activeNav === "save-editor" ? "settings" : activeNav;
  const resultCount = panelSearchEntries[activeNav].filter(controlMatchesSearch).length + importedMenu.snapshot.sections.filter((section) => !DEV_TESTING_SECTIONS.includes(section.id) && IMPORTED_MENU_CATEGORIES[section.id] === activeNav && importedSectionMatches(section, searchQuery)).length;
  const isPanelVisible = (panelId: PanelId) => activeNav === panelId && resultCount > 0;
  const capabilityState = (capability: GameplayCapability): CapabilityControlProps => ({
    capability,
    available: isCapabilityAvailable(capability),
    pending: isCapabilityPending(capability),
    unverified: Boolean(runtimeInfo.compatibilityIssue),
  });

  const chooseNavigation = (id: NavId, label: string) => {
    setActiveNav(id);
    setSearchQuery("");
    showToast(`${label} tools selected.`);
  };

  const stageStyle = {
    "--stage-scale": stageScale,
    "--interface-zoom": interfaceZoom,
    "--stage-width": `${DESIGN_WIDTH / interfaceZoom}px`,
    "--stage-height": `${DESIGN_HEIGHT / interfaceZoom}px`,
    "--content-text-scale": Math.max(1, 1 / Math.max(stageScale, 0.5)),
    "--stage-left": `${Math.max(0, (viewportSize.width - DESIGN_WIDTH / interfaceZoom * stageScale) / 2)}px`,
    "--stage-top": `${Math.max(0, (viewportSize.height - DESIGN_HEIGHT / interfaceZoom * stageScale) / 2)}px`,
  } as React.CSSProperties;

  const questJournal = useMemo(() => importedQuests ? (importedMenu.snapshot.ready ? parseQuestJournal(importedQuestPayload) : undefined) : runtimeInfo.questJournal,
    [importedQuests, importedQuestPayload, importedMenu.snapshot.ready, runtimeInfo.questJournal]);
  const questAvailable = importedQuests ? importedMenu.snapshot.ready : isCapabilityAvailable(CONTROL_CAPABILITIES.questJournal);

  const [remindersEnabled, setRemindersEnabled] = useState(false);
  const [reminderSaving, setReminderSaving] = useState(false);
  const [reminderError, setReminderError] = useState("");
  const [reminderStatus, setReminderStatus] = useState("");
  const [reminderTesting, setReminderTesting] = useState(false);
  useEffect(() => {
    const api = window.dawnwalkerDesktop?.questReminder;
    if (!api) return;
    let active = true;
    void api.get()
      .then(saved => { if (active) setRemindersEnabled(saved); })
      .catch(() => { if (active) setReminderError("Could not read the reminder setting. Reopen the menu to retry."); });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    const api = window.dawnwalkerDesktop?.questReminder;
    return api?.onReminder?.(event => {
      showObjectiveToast(event.objective);
      setReminderStatus(event.desktopAccepted ? "" : "The objective changed, but Windows did not accept the desktop notification.");
    });
  }, [showObjectiveToast]);

  const testReminder = useCallback(() => {
    const api = window.dawnwalkerDesktop?.questReminder;
    if (!api) return;
    setReminderTesting(true);
    setReminderError("");
    setReminderStatus("");
    // The main process reports whether Windows accepted the notification, so a refusal
    // is shown as a refusal instead of a button that looks like it worked.
    void api.notify("Objective reminders", "This is a test reminder from the mod menu.")
      .then(sent => setReminderStatus(sent
        ? "Sent. If no banner appears, check Windows Focus assist or Do not disturb - it still arrives in the notification centre."
        : "Windows did not accept the notification. Turn reminders on, then check the menu's notification permission in Windows Settings."))
      .catch(() => setReminderError("Could not send the test notification."))
      .finally(() => setReminderTesting(false));
  }, []);

  const toggleReminders = useCallback((next: boolean) => {
    const api = window.dawnwalkerDesktop?.questReminder;
    if (!api) return;
    setReminderSaving(true);
    setReminderError("");
    // Commit only what the store confirms it wrote, so a failed save never leaves the
    // switch showing a setting that is not in effect.
    setReminderStatus("");
    void api.set(next)
      .then(saved => setRemindersEnabled(saved))
      .catch(() => setReminderError("Could not save the reminder setting."))
      .finally(() => setReminderSaving(false));
  }, []);

  const playerStatusMessage = runtimeInfo.compatibilityIssue
    ? "The installed game build needs verification before Player controls can be used."
    : !runtimeInfo.gameRunning
      ? "Start Dawnwalker and load an offline single-player save."
      : !runtimeInfo.connected
        ? "The game is running, but the gameplay connection is not ready."
        : !runtimeInfo.interactionEligible || !runtimeInfo.sessionId
          ? "Waiting for the current game session to be verified."
          : undefined;

  return (
    <main className="viewport" data-compact={stageScale < 0.85 || interfaceZoom > 1 || undefined} data-scaled={interfaceZoom !== 1 || undefined} style={stageStyle}>
      <div className="app-stage">
        <div className="reference-art" aria-hidden="true" />
        <h1 className="sr-only">Blood of Dawnwalker Mod Menu</h1>
        <TooltipLayer enabled={styledTooltips} />

        <header className="masthead drag-region">
          <WindowDragHandle />
          <div className="window-controls no-drag">
            <button type="button" aria-label="Minimize application" onClick={() => window.dawnwalkerDesktop?.minimizeWindow()}><Minus size={18} /></button>
            <button type="button" aria-label={windowMaximized ? "Restore application" : "Maximize application"} onClick={() => window.dawnwalkerDesktop?.toggleMaximizeWindow?.()}>{windowMaximized ? <Copy size={16} /> : <Square size={16} />}</button>
            <button type="button" aria-label="Close application" className="close-window" onClick={() => window.dawnwalkerDesktop?.closeWindow()}><X size={20} /></button>
          </div>
        </header>

        <aside className="left-rail" aria-label="Menu categories">
          <nav>
            {navItems.map(({ id, label, icon: Icon }) => (
              <button
                type="button"
                 key={id}
                 className={activeRail === id ? "active" : ""}
                 aria-controls={`panel-${activeRail === id ? activeNav : id}`}
                 aria-current={activeRail === id ? "page" : undefined}
                onClick={() => chooseNavigation(id, label)}
              >
                <Icon size={29} aria-hidden="true" />
                <span>{label}</span>
              </button>
            ))}
          </nav>
          <div className="rail-sigil" aria-hidden="true" />
        </aside>

        <section className="workspace" aria-label="Dawnwalker menu controls">
          <div className="toolbar">
            <label className="search-box">
              <Search size={20} aria-hidden="true" />
              <input value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder={`Search ${activeCategory.label.toLowerCase()}…`} aria-label="Search menu options" />
              {searchQuery && <span className="search-count">{resultCount}</span>}
            </label>
            <div className="preset-controls">
              <button type="button" className="outlined-button" aria-current={activeNav === "overview" ? "page" : undefined} onClick={() => chooseNavigation("overview", "Overview")}>Overview</button>
              <button type="button" className="outlined-button" onClick={saveLocalPreset}><Save size={17} aria-hidden="true" /><span>Save UI Preset</span></button>
              <label className="select-wrap preset-select">
                <span className="sr-only">Local UI preset</span>
                <select aria-label="Local UI preset" value={presetName} onChange={(event) => loadLocalPreset(event.target.value as PresetName)}>
                  {presetNames.map((name) => <option key={name}>{name}</option>)}
                </select>
                <ChevronDown aria-hidden="true" size={15} />
              </label>
            </div>
          </div>

          <div className={`panel-grid category-view ${searchQuery ? "searching" : ""}`}>
            {resultCount === 0 && <div className="no-results"><Search size={30} /><strong>No matching {activeCategory.label} controls</strong><button type="button" onClick={() => setSearchQuery("")}>Clear search</button></div>}

            <ReferenceDashboard {...importedMenu} category={activeNav} query={searchQuery} open={(destination) => chooseNavigation(destination, destination === "player" ? "Player" : destination === "inventory" ? "Inventory" : destination === "world" ? "World" : destination === "teleport" ? "Teleport" : "Player")}>
            <Panel id="player" icon={PersonStanding} title="Player" visible={isPanelVisible("player")} emphasized={activeNav === "player"}>
              <section className="dashboard-card player-secondary-controls player-core-controls">
                <h3>Player controls</h3>
                <div className="player-secondary-grid">
              {playerStatusMessage && importedMenu.snapshot.sections.length === 0 && <div className="player-connection-status" role="status"><strong>{importedMenu.snapshot.ready ? "Core player controls unavailable" : "Player controls unavailable"}</strong><span>{importedMenu.snapshot.ready ? "The supplied player controls below are connected. The separate core controls still require verification." : playerStatusMessage}</span></div>}
              {controlMatchesSearch("god mode sprint no drain rapid stamina refill vampire form override infinite health") && <h4 className="player-control-group-heading">Survival</h4>}
              {controlMatchesSearch("god mode") && <ToggleRow label="God Mode" stateKey="godMode" icon={HeartPulse} iconTone="health" showState
                help={importedGod ? importedGodStatus ?? "Keeps health, stamina and blood energy full." : "Keeps health, stamina and blood energy full."}
                enabled={importedGod ? importedGod.value === true : menuState.toggles.godMode}
                onToggle={importedGod ? () => { void importedMenu.dispatch({ action: "set", sectionId: "DWCorePlayer", itemId: "god", value: importedGod.value !== true }); } : setToggle}
                {...(importedGod ? { capability: CONTROL_CAPABILITIES.godMode,
                  available: !importedMenu.disabled && importedGod.enabled !== false && importedGod.disabled !== true,
                  pending: importedCoreControlPending("god"),
                  unverified: false } : capabilityState(CONTROL_CAPABILITIES.godMode))} />}
              <ImportedActionFeedback feedback={importedMenu.feedback} sections={["DWCorePlayer"]} />
              {controlMatchesSearch("sprint no drain stamina cost") && <ToggleRow label="Sprint No Drain" stateKey="sprintNoDrain" icon={Footprints} iconTone="stamina" showState
                help={importedSprint ? "Locks stamina while enabled, including sprinting and other stamina-consuming actions." : undefined}
                enabled={importedSprint ? importedSprint.value === true : menuState.toggles.sprintNoDrain}
                onToggle={importedSprint ? () => { void importedMenu.dispatch({ action: "set", sectionId: "DWCorePlayer", itemId: "sprintEnabled", value: importedSprint.value !== true }); } : setToggle}
                {...(importedSprint ? { capability: CONTROL_CAPABILITIES.sprintNoDrain,
                  available: !importedMenu.disabled && importedSprint.enabled !== false && importedSprint.disabled !== true,
                  pending: importedCoreControlPending("sprintEnabled"),
                  unverified: false } : capabilityState(CONTROL_CAPABILITIES.sprintNoDrain))} />}
                <PlayerOptions {...importedMenu} query={searchQuery} only={PLAYER_RESOURCE_OPTIONS} />
                <PlayerMovementControls {...importedMenu} query={searchQuery} />
                {controlMatchesSearch("infinite blood energy blood energy") && <h4 className="player-control-group-heading">Resources</h4>}
                {controlMatchesSearch("infinite blood energy") && <ToggleRow label="Infinite Blood Energy" stateKey="infiniteBloodEnergy" showState
                  enabled={importedBlood ? importedBlood.value === true : menuState.toggles.infiniteBloodEnergy}
                  onToggle={importedBlood ? () => { void importedMenu.dispatch({ action: "set", sectionId: "DWCorePlayer", itemId: "bloodEnabled", value: importedBlood.value !== true }); } : setToggle}
                  {...(importedBlood ? { capability: CONTROL_CAPABILITIES.infiniteBloodEnergy,
                    available: !importedMenu.disabled && importedBlood.enabled !== false && importedBlood.disabled !== true,
                    pending: importedCoreControlPending("bloodEnabled"),
                    unverified: false } : capabilityState(CONTROL_CAPABILITIES.infiniteBloodEnergy))} />}
                <PlayerOptions {...importedMenu} query={searchQuery} only={PLAYER_BLOOD_OPTIONS} />
                {/* The ability switches and the item controls the reference list asks for.
                    Activation charges and ability cooldowns moved here from the Combat
                    block below, so the same section is never drawn twice. */}
                <PlayerReferenceControls {...importedMenu} query={searchQuery} />
                </div>
              </section>
              {/* Always part of the Player layout, like Player controls: with nothing
                  connected it still shows the progression placeholders. */}
              <section className="dashboard-card player-level-controls" aria-label="Player level">
                <h3>✿ Player level</h3>
                {importedLevel && <><div className="player-level-fields">
                  <div className="control-row">
                    <span>Current level: <strong>{typeof levelCurrent === "number" ? levelCurrent : "Not read"}</strong></span>
                  </div>
                  <div className="control-row select-row">
                    <label htmlFor="player-level-target">Target level</label>
                    <span className="select-wrap"><select id="player-level-target" value={typeof levelTarget?.value === "number" ? levelTarget.value : ""} disabled={importedMenu.disabled || !levelTarget?.options?.length}
                      onChange={(event) => void importedMenu.dispatch({ action: "set", sectionId: "DWCoreLevel", itemId: "target", value: Number(event.target.value) })}>
                      <option value="" disabled>Select a level</option>
                      {levelTarget?.options?.map((option) => typeof option !== "string" && typeof option.value === "number" ? <option key={option.value} value={option.value}>{option.value}</option> : null)}
                    </select><ChevronDown size={14} /></span>
                  </div>
                </div>
                <div className="player-level-actions" role="group" aria-label="Player level actions">
                  <button className="small-button" disabled={importedMenu.disabled} onClick={() => void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreLevel", itemId: "refresh" })}>Read player level</button>
                  <button className="small-button" disabled={importedMenu.disabled || !levelTargetValid} onClick={() => void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreLevel", itemId: "apply" })}>Apply level</button>
                </div>
                <p role="status">{importedLevel.items.find((item) => item.id === "status")?.label}</p>
                <ImportedActionFeedback feedback={importedMenu.feedback} sections={["DWCoreLevel"]} /></>}
                {/* The panel's heading and connection notice span the row, so they come
                    first: everything after them is one uninterrupted run of equal cells
                    rather than a short row, a divider, and then the cards. */}
                <div className="player-level-progression">
                  <ImportedMenuPanel corruptionAdvancedOnly category="player" group="player" {...importedMenu} query={searchQuery} onlySections={PLAYER_PROGRESSION_SECTIONS} />
                  {controlMatchesSearch("corruption level mutation") && <PlayerOptions {...importedMenu} query="Corruption" />}
                  {controlMatchesSearch("experience multiplier xp reward") && <PlayerOptions {...importedMenu} query="Experience Multiplier" />}
                </div>
              </section>
              {/* DWXPMultiplier is the Experience Multiplier row in the level card above. */}
              <ImportedMenuPanel category="player" group="player" {...importedMenu} query={searchQuery} excludeSections={["DWPlayer", "DWRespec", "DWXPMultiplier", ...PLAYER_PROGRESSION_SECTIONS]} showToolbar={false} />
              {(COMBAT_SEARCH_TERMS.some(controlMatchesSearch) || importedMenu.snapshot.sections.some((section) => COMBAT_SECTION_IDS.includes(section.id) && importedSectionMatches(section, searchQuery))) && <section className="category-section player-combat-section" aria-labelledby="player-combat-heading" data-search-label="combat assists blood energy difficulty cooldown parry">
                <header className="category-section-heading">
                  <Swords size={18} aria-hidden="true" />
                  <h3 id="player-combat-heading">Combat</h3>
                </header>
                {/* Activation Charges and Ability Cooldowns now render in Player controls
                    above, so the Combat group must not draw them a second time. */}
                <ImportedMenuPanel category="player" group="combat" excludeSections={["DWActivationControl", "DWCooldownControl", "DWCombatDiscovery"]} {...importedMenu} query={searchQuery} />
                {controlMatchesSearch("attack speed sprint block dodge stamina focus range smell zoom target visibility") && !importedMenu.snapshot.ready && <section className="feature-tools" aria-label="Combat connection status">
                  <h3>Combat connection</h3>
                  <p className="feature-status">Start Dawnwalker and load a supported save. Verified controls appear only after the installed build, runtime payload, and current player session are confirmed.</p>
                </section>}

                {controlMatchesSearch("rpg difficulty") && <label className="control-row" data-search-label="rpg difficulty" data-control-state={(importedRpg ? !importedMenu.disabled && importedRpg.enabled === true : isCapabilityAvailable(CONTROL_CAPABILITIES.rpgDifficulty)) ? "available" : "locked"}>
                  <span>RPG Difficulty</span>
                  <span className="select-wrap">
                    <select aria-label="RPG Difficulty" data-capability={CONTROL_CAPABILITIES.rpgDifficulty} value={importedRpg ? (importedRpg.enabled === true ? String(importedRpg.value) : "") : menuState.choices.rpgDifficulty} disabled={!(importedRpg ? !importedMenu.disabled && importedRpg.enabled === true : isCapabilityAvailable(CONTROL_CAPABILITIES.rpgDifficulty)) || isCapabilityPending(CONTROL_CAPABILITIES.rpgDifficulty)} title={capabilityControlTitle(CONTROL_CAPABILITIES.rpgDifficulty, (importedRpg ? !importedMenu.disabled && importedRpg.enabled === true : isCapabilityAvailable(CONTROL_CAPABILITIES.rpgDifficulty)), isCapabilityPending(CONTROL_CAPABILITIES.rpgDifficulty))} onChange={(event) => importedRpg ? void importedMenu.dispatch({ action: "set", sectionId: "DWCoreDifficulty", itemId: "rpg", value: Number(event.target.value) }) : void setDifficultyChoice("rpgDifficulty", CONTROL_CAPABILITIES.rpgDifficulty, event.target.value)}>
                      <option value="" disabled>Awaiting readback</option><option value="0">Story</option><option value="1">Normal</option><option value="2">Immersive</option><option value="3">Nightmare</option>
                    </select>
                    <ChevronDown aria-hidden="true" size={14} />
                  </span>
                </label>}
                {controlMatchesSearch("action difficulty") && <label className="control-row" data-search-label="action difficulty" data-control-state={(importedAction ? !importedMenu.disabled && importedAction.enabled === true : isCapabilityAvailable(CONTROL_CAPABILITIES.actionDifficulty)) ? "available" : "locked"}>
                  <span>Action Difficulty</span>
                  <span className="select-wrap">
                    <select aria-label="Action Difficulty" data-capability={CONTROL_CAPABILITIES.actionDifficulty} value={importedAction ? (importedAction.enabled === true ? String(importedAction.value) : "") : menuState.choices.actionDifficulty} disabled={!(importedAction ? !importedMenu.disabled && importedAction.enabled === true : isCapabilityAvailable(CONTROL_CAPABILITIES.actionDifficulty)) || isCapabilityPending(CONTROL_CAPABILITIES.actionDifficulty)} title={capabilityControlTitle(CONTROL_CAPABILITIES.actionDifficulty, (importedAction ? !importedMenu.disabled && importedAction.enabled === true : isCapabilityAvailable(CONTROL_CAPABILITIES.actionDifficulty)), isCapabilityPending(CONTROL_CAPABILITIES.actionDifficulty))} onChange={(event) => importedAction ? void importedMenu.dispatch({ action: "set", sectionId: "DWCoreDifficulty", itemId: "action", value: Number(event.target.value) }) : void setDifficultyChoice("actionDifficulty", CONTROL_CAPABILITIES.actionDifficulty, event.target.value)}>
                      <option value="" disabled>Awaiting readback</option><option value="0">Story</option><option value="1">Normal</option><option value="2">Immersive</option><option value="3">Nightmare</option>
                    </select>
                    <ChevronDown aria-hidden="true" size={14} />
                  </span>
                </label>}
                <ImportedActionFeedback feedback={importedMenu.feedback} sections={["DWCoreDifficulty"]} />
              {importedDifficulty && (controlMatchesSearch("rpg difficulty") || controlMatchesSearch("action difficulty")) && <div className="control-row split-action">
                  <span>{importedDifficulty.items.find((item) => item.id === "status")?.label}</span>
                  <button className="small-button" disabled={importedMenu.disabled} onClick={() => void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreDifficulty", itemId: "refresh" })}>Read difficulty</button>
                  <button className="small-button" disabled={importedMenu.disabled} onClick={() => void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreDifficulty", itemId: "restore" })}>Restore difficulty</button>
                </div>}
                {(controlMatchesSearch("rpg difficulty") || controlMatchesSearch("action difficulty")) && <CapabilityNotice compact title="Two-axis development pilot">
                  These are separate runtime-only Action and RPG overrides. They never change or confirm the game&apos;s broad difficulty preset, and the bridge retains both original axes for same-world rollback.
                </CapabilityNotice>}
                {controlMatchesSearch("focus ability cooldowns") && <CapabilityNotice compact title={importedMenu.snapshot.ready ? "Ability cooldown control" : "Cooldown replacement under live validation"}>
                  {importedMenu.snapshot.ready ? "The supplied menu's Ability Cooldowns group provides quick cooldown resets. Normal charge, blood, item costs and eligibility still apply. The separate Focus debug control remains unavailable." : "The game's Focus debug switch is a nonfunctional shipping stub. The supplied menu's Ability Cooldowns control requires its runtime connection; the separate core cooldown route remains gated until its effects and restoration are verified."}
                </CapabilityNotice>}
                {controlMatchesSearch("extended parry window perfect parry set by caller magnitude") && importedMenu.snapshot.sections.some((section) => section.id === "DWParryWindow") && <PlayerParryWindow {...importedMenu} />}
                {controlMatchesSearch("extended parry window perfect parry set by caller magnitude") && !importedMenu.snapshot.sections.some((section) => section.id === "DWParryWindow") && <CapabilityNotice compact title="Extended Parry Window unavailable">
                  The exact player effect and exact-handle rollback route are reflected, but the effect requires a Stats.CustomModifier set-by-caller magnitude that no captured caller or asset supplies. The separate 1.0 baseline and 1.2 vampire setting do not prove that payload, so this control stays unavailable.
                </CapabilityNotice>}
              </section>}


            </Panel>

            <Panel id="inventory" icon={Backpack} title="Inventory" visible={isPanelVisible("inventory")} emphasized={activeNav === "inventory"}>
              <ImportedMenuPanel category="inventory" group="inventory" {...importedMenu} query={searchQuery} />
            </Panel>

            <Panel id="world" icon={Globe2} title="World" visible={isPanelVisible("world")} emphasized={activeNav === "world"}>

              <ImportedMenuPanel category="world" {...importedMenu} query={searchQuery} />
              {controlMatchesSearch("story days deadline time configuration") && <StoryDaySettings />}
              {controlMatchesSearch("game speed") && <section className="reference-feature-card world-speed-card" aria-label="Game speed"><h3>Game speed</h3><SliderRow label="Game Speed" value={importedSpeed && typeof importedSpeed.value === "number" ? importedSpeed.value : menuState.values.gameSpeed} min={0.1} max={3} step={0.1} suffix="×"
                onCommit={importedSpeed ? async (value) => {
                  await importedMenu.dispatch({ action: "set", sectionId: "DWCoreWorld", itemId: "speed", value });
                  // The native snapshot supplies the committed value; a queued
                  // dispatch alone is not successful game-speed readback.
                  return false;
                } : (value) => setValue("gameSpeed", CONTROL_CAPABILITIES.gameSpeed, value)}
                {...(importedSpeed ? { capability: CONTROL_CAPABILITIES.gameSpeed, available: importedSpeedAvailable,
                  pending: importedMenu.pending, unverified: !importedMenu.snapshot.ready || !importedWorldStatus?.startsWith("Game speed:") }
                  : { ...capabilityState(CONTROL_CAPABILITIES.gameSpeed), unverified: !runtimeInfo.connected || Boolean(runtimeInfo.compatibilityIssue) })} />
              {importedWorld && controlMatchesSearch("game speed") && <div className="control-row split-action">
                <span>{importedWorldStatus}</span>
                <button className="small-button" disabled={importedMenu.disabled} onClick={() => void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreWorld", itemId: "refresh" })}>Refresh speed and location</button>
                <button className="small-button" disabled={importedMenu.disabled} onClick={() => void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreWorld", itemId: "restore" })}>Restore game speed</button>
              </div>}
              <ImportedActionFeedback feedback={importedMenu.feedback} sections={["DWCoreWorld"]} /></section>}
              {controlMatchesSearch("world state time weather quest phase") && <CapabilityNotice title={importedMenu.snapshot.ready ? "Time segment safeguards" : "World state safety"}>
                {importedMenu.snapshot.ready ? "Use the supplied menu's Time Segments group for confirmed clock changes. Advancing can progress timed quests; rewinding is limited to the current day or phase and does not undo events. Weather controls remain unavailable." : "The supplied menu's Time Segments controls require its runtime connection. Time changes can advance quests and story progression; weather controls remain unavailable."}
              </CapabilityNotice>}
            </Panel>

            <Panel id="teleport" icon={Sparkles} title="Teleport" visible={isPanelVisible("teleport")} emphasized={activeNav === "teleport"}>
              <ImportedMenuPanel category="teleport" {...importedMenu} query={searchQuery} />
              <section className="saved-location-tools reference-feature-card" aria-label="Custom saved locations"><h3>Saved locations</h3>
              {controlMatchesSearch("save location") && <div className="control-row split-action" data-search-label="save location"><span>Save Location</span><input className="text-field" aria-label="Saved location name" data-capability={CONTROL_CAPABILITIES.saveLocation} value={savedLocationName} disabled={importedTeleport ? importedMenu.disabled || locationPending : !isCapabilityAvailable(CONTROL_CAPABILITIES.saveLocation) || isCapabilityPending(CONTROL_CAPABILITIES.saveLocation)} onChange={(event) => setSavedLocationName(event.target.value)} placeholder="Enter name…" /><GameplayButton className="small-button" disabled={!savedLocationName.trim()} onClick={async () => {
                const requestedName = savedLocationName.trim();
                if (importedTeleport) {
                  setLocationError("");
                  const nativeName = importedTeleport.items.find((item) => item.id === "name")?.value;
                  if (nativeName === requestedName) {
                    await importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreTeleport", itemId: "save" });
                  } else {
                    if (stagedLocationSave.current) return;
                    setLocationError(""); setLocationPending(true);
                    const staged = { session: importedMenu.snapshot.sessionId, name: requestedName, expires: Date.now() + 30000, operationId: undefined as string | undefined };
                    stagedLocationSave.current = staged;
                    const result = await importedMenu.dispatchTracked({ action: "set", sectionId: "DWCoreTeleport", itemId: "name", value: requestedName });
                    if (stagedLocationSave.current !== staged) return;
                    if (!result?.accepted || result.sessionId !== staged.session || !result.operationId) {
                      stagedLocationSave.current = null; setLocationPending(false);
                      setLocationError("The name could not be confirmed. Check the connection and try saving again.");
                    } else staged.operationId = result.operationId;
                  }
                  return;
                }
                const outcome = await dispatchGameplay(CONTROL_CAPABILITIES.saveLocation, requestedName);
                if (!outcome.applied) return;
                const storedName = locationNameReadback(outcome.readback);
                if (storedName === undefined) {
                  showToast("Save Location returned no valid name readback; no location was added to the menu.");
                  return;
                }
                setSavedLocations((current) => current.includes(storedName) ? current : [...current, storedName]);
                setLocalChoice("savedLocation", storedName);
                setSavedLocationName("");
              }} {...(importedTeleport ? { capability: CONTROL_CAPABILITIES.saveLocation, available: !importedMenu.disabled && !locationPending, pending: importedMenu.pending || locationPending } : capabilityState(CONTROL_CAPABILITIES.saveLocation))}>Save</GameplayButton></div>}
              {controlMatchesSearch("saved locations teleport") && <div className="control-row split-action" data-search-label="saved locations teleport"><span>Saved Locations</span><span className="select-wrap"><select aria-label="Saved location" data-capability={CONTROL_CAPABILITIES.teleportSavedLocation} value={importedDestination ? (typeof importedDestination.value === "string" ? importedDestination.value : "") : menuState.choices.savedLocation} disabled={importedDestination ? importedMenu.disabled || locationPending || !importedDestination.options?.length : !isCapabilityAvailable(CONTROL_CAPABILITIES.teleportSavedLocation) || isCapabilityPending(CONTROL_CAPABILITIES.teleportSavedLocation) || savedLocations.length === 0} onChange={(event) => importedDestination ? void importedMenu.dispatch({ action: "set", sectionId: "DWCoreTeleport", itemId: "destination", value: event.target.value }) : setLocalChoice("savedLocation", event.target.value)}><option value="" disabled>Select Location</option>{importedDestination ? importedDestination.options?.map((option) => typeof option === "string" ? <option key={option}>{option}</option> : <option key={String(option.value)} value={String(option.value)} disabled={option.value === false}>{option.label}</option>) : savedLocations.map((name) => <option key={name}>{name}</option>)}</select><ChevronDown size={14} /></span><GameplayButton className="small-button" disabled={importedDestination ? !destinationValid || locationPending : !menuState.choices.savedLocation} onClick={() => importedTeleport ? void importedMenu.dispatch({ action: "invoke", sectionId: "DWCoreTeleport", itemId: "teleport" }) : void dispatchGameplay(CONTROL_CAPABILITIES.teleportSavedLocation, menuState.choices.savedLocation)} {...(importedTeleport ? { capability: CONTROL_CAPABILITIES.teleportSavedLocation, available: !importedMenu.disabled, pending: importedMenu.pending } : capabilityState(CONTROL_CAPABILITIES.teleportSavedLocation))}>Teleport</GameplayButton></div>}
              {locationError && <p role="alert" className="imported-menu-action-error">{locationError}</p>}
              {importedTeleport && !importedDestination?.options?.length && <p className="location-empty">No saved locations yet. Enter a name and choose Save to capture your current position.</p>}
              {importedTeleport && <p role="status">{importedTeleport.items.find((item) => item.id === "status")?.label}</p>}
              <ImportedActionFeedback feedback={importedMenu.feedback} sections={["DWCoreTeleport"]} />
              {controlMatchesSearch("session-only locations") && <p className="location-session-note">Saved positions last for the current player session.</p>}
              </section>
            </Panel>

            <Panel id="visuals" icon={Eye} title="Visuals" visible={isPanelVisible("visuals")} emphasized={activeNav === "visuals"}>
              {controlMatchesSearch("eye appearance color presets character preview") && <EyeAppearancePanel snapshot={importedMenu.snapshot}
                active={isPanelVisible("visuals")} appearance={appearance} onPreviewChange={previewAppearance}
                onPreviewFailure={() => dispatchAppearance({ type: "failure" })} />}
              {controlMatchesSearch("hair color colour presets") && <HairColorPanel snapshot={importedMenu.snapshot}
                dispatch={dispatchAppearanceCommand} pending={importedMenu.pending} onPreviewChange={previewAppearance} />}
              {controlMatchesSearch("skin color colour tint rgb") && <SkinTintPanel snapshot={importedMenu.snapshot}
                dispatch={dispatchAppearanceCommand} pending={importedMenu.pending} onPreviewChange={previewAppearance} />}
            </Panel>

            <Panel id="quests" icon={ScrollText} title="Quests" visible={isPanelVisible("quests")} emphasized={activeNav === "quests"}>
              {controlMatchesSearch("quest journal tracked objectives progress active optional readback") && (
                <section
                  className="quest-journal"
                  aria-label="Quest Journal readback"
                  data-capability={CONTROL_CAPABILITIES.questJournal}
                  data-control-state={questAvailable ? "available" : "locked"}
                >
                  <ImportedActionFeedback feedback={importedMenu.feedback} sections={["DWQuestReadback"]} />
              {importedQuests && <div className="control-row split-action">
                    <span>{importedQuests.items.find((item) => item.id === "status")?.label}</span>
                    <button className="small-button" disabled={importedMenu.disabled}
                      onClick={() => void importedMenu.dispatch({ action: "invoke", sectionId: "DWQuestReadback", itemId: "refresh" })}>Refresh Quest Journal</button>
                  </div>}
                  {!questAvailable ? (
                    <CapabilityNotice title="Quest Journal unavailable">
                      The menu only displays quests when the connected offline bridge advertises the exact read-only Journal contract. It never tracks, advances, completes, or edits a quest.
                    </CapabilityNotice>
                  ) : !questJournal ? (
                    <div className="locked-readback">Awaiting a valid bounded Quest Journal snapshot…</div>
                  ) : questJournal.openQuestCount === 0 ? (
                    <div className="quest-empty">
                      <ScrollText size={30} aria-hidden="true" />
                      <strong>No open quests</strong>
                      <span>The loaded Journal returned a valid empty snapshot.</span>
                    </div>
                  ) : (
                    <>
                      <header className="quest-journal-summary">
                        <div>
                          <strong>Open Quest Journal</strong>
                          <span>Showing {questJournal.returnedQuestCount} of {questJournal.openQuestCount} open quests</span>
                        </div>
                        <em>{questJournal.truncated ? "Bounded preview" : "Complete snapshot"}</em>
                      </header>
                      <div className="quest-list">
                        {questJournal.quests.map((quest, questIndex) => (
                          <article className={`quest-entry quest-state-${quest.state}`} key={`${quest.title}-${questIndex}`}>
                            <header>
                              <div>
                                <h3>{quest.title}</h3>
                                <span className="quest-state">{QUEST_STATE_LABELS[quest.state]}</span>
                              </div>
                              {quest.tracked && <span className="quest-tracked">Tracked</span>}
                            </header>
                            {quest.objectiveCount === 0 ? (
                              <p className="quest-no-objectives">No objectives are present in this quest snapshot.</p>
                            ) : (
                              <ul className="quest-objectives">
                                {quest.objectives.map((objective, objectiveIndex) => (
                                  <li key={`${objective.text}-${objectiveIndex}`}>
                                    <span className={`objective-marker objective-state-${objective.state}`} aria-hidden="true" />
                                    <div>
                                      <p>{objective.text}</p>
                                      <span>{QUEST_STATE_LABELS[objective.state]}{objective.optional ? " · Optional" : ""}</span>
                                    </div>
                                    {objective.maxCount > 0 && (
                                      <output aria-label={`${objective.text} progress`}>
                                        {formatQuestCount(objective.currentCount)} / {formatQuestCount(objective.maxCount)}
                                      </output>
                                    )}
                                  </li>
                                ))}
                              </ul>
                            )}
                            {quest.objectivesTruncated && <p className="quest-truncated">Showing {quest.objectives.length} of {quest.objectiveCount} objectives.</p>}
                          </article>
                        ))}
                      </div>
                    </>
                  )}
                </section>
              )}
            </Panel>

            <Panel id="settings" icon={Settings} title="Settings" visible={isPanelVisible("settings") || isPanelVisible("save-editor")} emphasized={activeNav === "settings" || activeNav === "save-editor"}>
              <div className="settings-subtabs" role="tablist" aria-label="Settings sections">
                <button type="button" role="tab" id="settings-tab-general" aria-controls="settings-pane-general"
                  aria-selected={settingsTab === "general"} onClick={() => setSettingsTab("general")}><Settings size={15} />General</button>
                <button type="button" role="tab" id="settings-tab-save-editor" aria-controls="settings-pane-save-editor"
                  aria-selected={settingsTab === "save-editor"} onClick={() => setSettingsTab("save-editor")}><Save size={15} />Save Editor</button>
                <button type="button" role="tab" id="settings-tab-credits" aria-controls="settings-pane-credits"
                  aria-selected={settingsTab === "credits"} onClick={() => setSettingsTab("credits")}><Award size={15} />Credits</button>
              </div>
              <div role="tabpanel" id="settings-pane-general" aria-labelledby="settings-tab-general" hidden={settingsTab !== "general"}>
                {settingsTab === "general" && <>
                {controlMatchesSearch("tooltips hover help hints interface") && <section className="reference-feature-card tooltip-settings" aria-label="Tooltips">
                  <h3><MessageSquareText size={17} aria-hidden="true" /> Tooltips</h3>
                  <div className="control-row">
                    <span className="player-toggle-label">
                      Styled tooltips
                      <small>Show each control&apos;s explanation in the menu&apos;s own style when you hover it. Off falls back to the plain Windows tooltip.</small>
                    </span>
                    <button type="button" className={`toggle ${styledTooltips ? "toggle-on" : ""}`} role="switch" aria-label="Styled tooltips"
                      aria-checked={styledTooltips} onClick={() => toggleStyledTooltips(!styledTooltips)}><span /></button>
                  </div>
                </section>}
                <div className="settings-general-tools">
                  {controlMatchesSearch("interface scale zoom text size display") && <InterfaceScaleSettings />}
                  {controlMatchesSearch("objective reminders quest notification toast alert") && <QuestReminderSettings
                    enabled={remindersEnabled} available={Boolean(window.dawnwalkerDesktop?.questReminder)}
                    saving={reminderSaving} error={reminderError} status={reminderStatus} testing={reminderTesting}
                    onToggle={toggleReminders} onTest={testReminder} />}
                  {controlMatchesSearch("reset ui view") && <button type="button" className="wide-action settings-reset" onClick={resetUiView}><Settings size={19} />Reset UI View</button>}
                </div>
                <ImportedMenuPanel category="settings" excludeSections={DEV_TESTING_SECTIONS} {...importedMenu} query={searchQuery} />
                </>}
              </div>
              <div role="tabpanel" id="settings-pane-save-editor" aria-labelledby="settings-tab-save-editor" hidden={settingsTab !== "save-editor"}>
                {settingsTab === "save-editor" && controlMatchesSearch(SAVE_EDITOR_SEARCH_TERMS) && <SaveTools />}
              </div>
              <div role="tabpanel" id="settings-pane-credits" aria-labelledby="settings-tab-credits" hidden={settingsTab !== "credits"}>
                {settingsTab === "credits" && controlMatchesSearch("credits creators references inspired") && <FeatureCredits />}
              </div>
            </Panel>
            </ReferenceDashboard>
          </div>
        </section>

        <footer className="hotkey-bar">
          <div className="version">v0.1.0 <span /> {gameIdentityLabel(runtimeInfo)}</div>
          <div className="hotkeys">
            <span
              data-capability={CONTROL_CAPABILITIES.addGold}
              data-control-state={(importedCurrency ? importedGoldAvailable : isCapabilityAvailable(CONTROL_CAPABILITIES.addGold)) ? "available" : "locked"}
              title={importedCurrency ? (importedGoldAvailable ? "Add 10,000 gold through the connected game controls" : "Wait for the game controls to be ready") : capabilityControlTitle(CONTROL_CAPABILITIES.addGold, isCapabilityAvailable(CONTROL_CAPABILITIES.addGold), isCapabilityPending(CONTROL_CAPABILITIES.addGold))}
            ><kbd>F9</kbd>Add 10,000 Gold</span>
            <span><kbd>F10</kbd>Show / Hide Menu</span>
          </div>
        </footer>

        <div className={`toast ${toast ? "toast-visible" : ""} ${toastKind === "objective" ? "toast-objective" : ""}`}
          role={toastKind === "objective" ? "alert" : "status"} aria-live={toastKind === "objective" ? "assertive" : "polite"}>
          {toastKind === "objective" && toast && <BellRing size={16} aria-hidden="true" />}
          <span>{toast}</span>
        </div>
        <ImportedMenuConfirmation snapshot={importedMenu.snapshot} pending={importedMenu.pending} dispatch={importedMenu.dispatch} />
      </div>
    </main>
  );
}

export default App;
