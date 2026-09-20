import type { GameplayCapability } from "./runtimeContract";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_gameplay_control_map");

export const CONTROL_CAPABILITIES = Object.freeze({
  infiniteHealth: "player:infinite-health",
  unlimitedStamina: "player:unlimited-stamina",
  sprintNoDrain: "player:sprint-no-drain",
  bloodEnergy: "player:blood-energy",
  godMode: "player:god-mode",
  playerInfo: "player:player-info",
  traitPoints: "player:trait-points",
  addGold: "player:add-gold",
  addItem: "inventory:add-item",
  addLevel: "player:add-level",
  unblockTrait: "player:unblock-trait",
  infiniteBloodEnergy: "combat:infinite-blood-energy",
  rpgDifficulty: "combat:rpg-difficulty",
  actionDifficulty: "combat:action-difficulty",
  questJournal: "quests:journal-readback",
  saveLocation: "teleport:save-location",
  teleportSavedLocation: "teleport:teleport-saved-location",
  hudVisible: "visuals:hud-visible",
  gameSpeed: "world:game-speed",
  locationReadback: "world:location-readback",
} as const satisfies Readonly<Record<string, GameplayCapability>>);

export const RENDERER_GAMEPLAY_CAPABILITIES = Object.freeze(
  Object.values(CONTROL_CAPABILITIES),
) as readonly GameplayCapability[];
