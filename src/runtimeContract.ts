const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_runtime_contract");

export const GAMEPLAY_CAPABILITIES = [
  "player:infinite-health",
  "player:unlimited-stamina",
  "player:sprint-no-drain",
  "player:blood-energy",
  "player:god-mode",
  "player:player-info",
  "player:trait-points",
  "player:add-gold",
  "inventory:add-item",
  "player:add-level",
  "player:unblock-trait",
  "combat:infinite-blood-energy",
  "combat:rpg-difficulty",
  "combat:action-difficulty",
  "quests:journal-readback",
  "teleport:save-location",
  "teleport:teleport-saved-location",
  "visuals:hud-visible",
  "world:game-speed",
  "world:location-readback",
] as const;

export type GameplayCapability = (typeof GAMEPLAY_CAPABILITIES)[number];
export type RuntimeMode = "live-offline" | "disconnected";
export type CommandValue = boolean | number | string;

export type RuntimeCommand = Readonly<{
  capability: GameplayCapability;
  value?: CommandValue;
  requestId: string;
  sessionId: string;
}>;

export type RuntimeResult = Readonly<{
  accepted: boolean;
  capability: GameplayCapability;
  requestId: string;
  status: "applied" | "rejected" | "timeout";
  message: string;
  readback?: CommandValue | Readonly<Record<string, unknown>>;
}>;

export type PlayerReadback = Readonly<{
  name?: string;
  alive?: boolean;
  level?: number;
  health?: number;
  maxHealth?: number;
  stamina?: number;
  maxStamina?: number;
  bloodEnergy?: number;
  maxBloodEnergy?: number;
  traitPoints?: number;
  gold?: number;
  locationName?: string;
  x?: number;
  y?: number;
  z?: number;
}>;

export type RuntimeControlReadback = Readonly<{
  hudVisible?: boolean;
  gameSpeed?: number;
  rpgDifficulty?: number;
  actionDifficulty?: number;
}>;

export type QuestState = "active" | "success" | "failure" | "unknown";

export type QuestObjectiveReadback = Readonly<{
  text: string;
  state: QuestState;
  currentCount: number;
  maxCount: number;
  optional: boolean;
}>;

export type QuestReadback = Readonly<{
  title: string;
  state: QuestState;
  tracked: boolean;
  objectiveCount: number;
  objectivesTruncated: boolean;
  objectives: readonly QuestObjectiveReadback[];
}>;

export type QuestJournalReadback = Readonly<{
  openQuestCount: number;
  returnedQuestCount: number;
  truncated: boolean;
  quests: readonly QuestReadback[];
}>;

export type RuntimeInfo = Readonly<{
  platform: string;
  mode: RuntimeMode;
  connected: boolean;
  gameRunning: boolean;
  buildVerified: boolean;
  installedBuildId?: string;
  installedGameVersion?: Readonly<{ version: string; changelist: string }>;
  installedGameChangelist?: string;
  verifiedBuildId?: string;
  interactionEligible: boolean;
  compatibilityIssue?: string;
  bridgeVersion?: string;
  sessionId?: string;
  capabilities: readonly GameplayCapability[];
  activeCapabilities: readonly GameplayCapability[];
  player?: PlayerReadback;
  controls?: RuntimeControlReadback;
  questJournal?: QuestJournalReadback;
}>;

const gameplayCapabilitySet: ReadonlySet<string> = new Set(GAMEPLAY_CAPABILITIES);

export function isGameplayCapability(value: unknown): value is GameplayCapability {
  return typeof value === "string" && gameplayCapabilitySet.has(value);
}

export function normalizeRuntimeCapabilities(values: readonly unknown[] | undefined): readonly GameplayCapability[] {
  if (!values) return [];
  return [...new Set(values.filter(isGameplayCapability))];
}
