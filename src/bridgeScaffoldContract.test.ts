import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_bridge_scaffold_contract_tests");

const bridgeSource = readFileSync(
  resolve(process.cwd(), "integration/uue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua"),
  "utf8",
);

describe("Dawnwalker bridge pilot", () => {
  it("uses a session-bound local protocol with fresh heartbeat and matched responses", () => {
    expect(bridgeSource).toContain('local BRIDGE_PROTOCOL = "1"');
    expect(bridgeSource).toContain('local BOOT_ID = tostring(os.time())');
    expect(bridgeSource).toContain('"heartbeat=" .. tostring(now)');
    expect(bridgeSource).toContain('fields.boot_id ~= BOOT_ID');
    expect(bridgeSource).toContain('"request_id=" .. sanitize(request_id)');
    expect(bridgeSource).toContain("LoopAsync(150, poll_command)");
  });

  it("gates the reflected pilot subset behind the EngineTick game-thread route and a live player", () => {
    expect(bridgeSource).toContain('local BRIDGE_PHASE = "pilot"');
    expect(bridgeSource).toContain("game_thread_available = EngineTickAvailable == true");
    expect(bridgeSource).toContain("if teardown_retry_pending or not game_thread_available or not player_ready then return \"\" end");
    expect(bridgeSource).toContain("EGameThreadMethod.EngineTick");
    expect(bridgeSource).toContain('"player:infinite-health"');
    expect(bridgeSource).toContain('"player:unlimited-stamina"');
    expect(bridgeSource).toContain('"player:blood-energy"');
    expect(bridgeSource).toContain('"player:add-gold"');
    expect(bridgeSource).toContain('"combat:infinite-blood-energy"');
    expect(bridgeSource).toContain('"combat:rpg-difficulty"');
    expect(bridgeSource).toContain('"combat:action-difficulty"');
    expect(bridgeSource).toContain('"quests:journal-readback"');
    expect(bridgeSource).not.toContain('"combat:no-focus-ability-cooldowns"');
    expect(bridgeSource).not.toContain("ToggleDisablingAllCooldowns_Debug");
    expect(bridgeSource).not.toContain("AreCooldownsEnabled_Debug");
    expect(bridgeSource).not.toContain('"player:humanity"');
    expect(bridgeSource).not.toContain('"npc:spawn-boat"');
    expect(bridgeSource).toContain("Capability is not advertised by the verified Dawnwalker bridge.");
  });

  it("withdraws the pickup-permission effect from the Unlimited Weight contract", () => {
    expect(bridgeSource).not.toContain("player:unlimited-weight");
    expect(bridgeSource).not.toContain("GE_EnableWeightLimitExceed");
    expect(bridgeSource).not.toContain("handle_unlimited_weight");
  });

  it("reads a bounded Quest Journal through exact reflected types without mutation APIs", () => {
    for (const contractToken of [
      'game_state:IsA("/Script/Dawnwalker.DawnwalkerGameStateBase")',
      "game_state.QuestJournal",
      'journal:IsA("/Script/Quest.Journal")',
      "journal:GetOpenedQuests(opened_out)",
      "local opened_quests = opened_out",
      "journal:GetTrackedQuest()",
      'quest:IsA("/Script/Quest.Quest")',
      "quest.Title",
      "quest.Objectives",
      "objective.Text",
      "objective.MaxCount",
      "objective.CurrentCount",
      "objective.bIsOptional",
      "MAX_QUESTS = 6",
      "MAX_OBJECTIVES_PER_QUEST = 3",
      "MAX_QUEST_READBACK_BYTES = 8192",
      "for index = 1, expected_count do",
      "objectives[index]",
      "for index = 1, expected_quest_count do",
      "opened_quests[index]",
    ]) {
      expect(bridgeSource).toContain(contractToken);
    }
    expect(bridgeSource).not.toContain("opened_out.OutQuests");
    expect(bridgeSource).not.toContain("journal.OpenedQuests");
    expect(bridgeSource).not.toContain("opened_quests:ForEach");
    expect(bridgeSource).not.toContain("objectives:ForEach");
    for (const mutationToken of ["journal:TrackQuest(", "journal:TrackQuestObjective(", "quest:DebugLogQuestIds("]) {
      expect(bridgeSource).not.toContain(mutationToken);
    }
  });

  it("adds Coin currency only through two matching reflected InventoryComponent routes", () => {
    for (const contractToken of [
      "player:GetInventoryComponent()",
      '"/Script/DogwoodInventory.InventoryComponent"',
      '"/Script/DogwoodInventory.InventorySubsystem"',
      "subsystem:GetPlayerInventoryComponent()",
      "direct_address ~= subsystem_address",
      "inventory:GetCurrencyQuantity(COIN_CURRENCY_TYPE)",
      "inventory:AddCurrency(COIN_CURRENCY_TYPE, requested)",
      "MAX_GOLD_DELTA = 10000",
      "INT32_MAX = 2147483647",
      "observed_delta = after - before",
      "rollback_inventory:AddCurrency(COIN_CURRENCY_TYPE, -observed_delta)",
    ]) {
      expect(bridgeSource).toContain(contractToken);
    }
    expect(bridgeSource).not.toContain("TryQuicksave");
    expect(bridgeSource).not.toContain("ITM_Currency_Coin");
  });

  it("uses reflected setters, readbacks, and disable restoration for each mutating pilot", () => {
    for (const contractToken of [
      "SetHealthPercent", "LockHealth", "UnlockHealth", "GetHealthPercentage",
      "SetStaminaPercent", "LockStamina", "UnlockStamina", "GetStaminaPercentage",
      "SetBloodPercent", "LockBlood", "UnlockBlood", "GetBlood", "GetBloodBarLength",
    ]) {
      expect(bridgeSource).toContain(contractToken);
    }
    expect(bridgeSource).toContain("resource_locks");
    expect(bridgeSource).toContain("resource.baseline");
    expect(bridgeSource).toContain("resource.owners[owner]");
    expect(bridgeSource).toContain("pcall(handler, fields.value)");
  });

  it("keeps Combat difficulty as two exact owner-safe axes and never uses the broad preset", () => {
    for (const contractToken of [
      '"/Script/DogwoodCombat.CombatSubsystem"',
      "subsystem:GetWorld()",
      "subsystem:GetActionDifficultyLevel()",
      "subsystem.ActionDifficultyLevel",
      "subsystem.RPGDifficultyLevel",
      "subsystem:GetActionDifficultySettings()",
      "subsystem:GetRPGDifficultySettings()",
      "settings:GetSettingAsDifficulty(setting, output)",
      "map:Contains(level)",
      "record.subsystem:SetRPGDifficulty(record.baseline_rpg)",
      "record.subsystem:SetActionDifficulty(record.baseline_action)",
      "difficulty_override",
      "restore_difficulty_override",
    ]) {
      expect(bridgeSource).toContain(contractToken);
    }
    expect(bridgeSource).not.toContain("PreviewDifficultyPreset");
    expect(bridgeSource).not.toContain("ConfirmSetting(");
    expect(bridgeSource).not.toContain('"combat:game-difficulty"');
  });

  it("keeps mutations identity-bound and runs bounded verified teardown", () => {
    for (const contractToken of [
      "get_session_identity",
      "resource_binding_matches",
      "snapshot_binding_matches",
      "restore_resource_baseline",
      "force_release_resource_owner",
      "teardown_session_state",
      "session_state_has_pending_restore",
      "retain_only_pending_active_state",
      'teardown_session_state("pending restore retry")',
      "player identity transition blocked by unresolved restore state",
      "unresolved restore state was retained instead of discarded",
      "MAX_TEARDOWN_OPERATIONS = 8",
      "ModRef.OnUnload",
      "saved_locations[identity.key]",
      "rollback_verified",
      "is_read_only_query",
    ]) {
      expect(bridgeSource).toContain(contractToken);
    }
    expect(bridgeSource).toContain('resource_locks[release.name].owners[capability] = nil');
    expect(bridgeSource).toContain('teardown_session_state("player or world identity change")');
  });

  it("carries executable cyberfox1337x boundary signatures", () => {
    for (const boundary of ["dawnwalker_mod_bridge", "bridge_bootstrap", "local_file_transport"]) {
      expect(bridgeSource).toContain(`cyberfox1337x.function_signature("${boundary}")`);
    }
  });

  it("uses the reflected lowercase FRotator pitch field for reversible teleports", () => {
    expect(bridgeSource).toContain("is_finite_number(rotation.pitch)");
    expect(bridgeSource).toContain("pitch = rotation.pitch");
    expect(bridgeSource).not.toContain("rotation.Pitch");
  });
});
