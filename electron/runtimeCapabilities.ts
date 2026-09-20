const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_electron_runtime_capabilities");

export const RUNTIME_CAPABILITIES = [
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

export const RUNTIME_CAPABILITY_SET: ReadonlySet<string> = new Set(RUNTIME_CAPABILITIES);
