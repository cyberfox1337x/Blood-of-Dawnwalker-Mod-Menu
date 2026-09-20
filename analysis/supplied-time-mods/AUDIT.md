# Supplied time mods audit

90-day ZIP contains only `90days/Game.ini`: `[/Script/Quest.QuestSettings]` then `DaysToPass=91`. The value is 91, not 90. No executable code.

Traits ZIP contains Unreal IoStore `.utoc` / `.ucas` plus a small `.pak`. Its readable directory contains 112 unique DA_Trait_*.uasset names, recorded in trait-assets.json. Extracted files are confined to this analysis directory; nothing was installed or executed. Binary property values have not been decoded or compared against vanilla assets, so an exact all-property diff is not claimed.

Current-build SDK contracts:
- Quest.hpp:474/480: UQuestSettings, DaysToPass int32. Candidate CDO /Script/Quest.Default__QuestSettings.
- DogwoodSystem.hpp:538: TimeSystemImpl.GetMainGoalDay; no reflected direct deadline setter listed.
- DogwoodCharacterDevelopment.hpp:61/67: FTraitLevel.TimeCost int32; :335/354 UTraitAsset.Levels TArray<FTraitLevel>.
- Existing ProtectedRespec.lua already reads reflected Levels through ForEach and wrapper:get().

The existing StoryTimerControl edits QuestConditionInteractionType interaction costs. Those are different objects from the supplied trait assets; it must not be presented as an exact implementation of this archive.

New StorySettingsControl adapter offers deliberate read-only refresh, an owned live DaysToPass=91 toggle requiring active deadline91 readback, and owned loaded-trait TimeCost zeroing with exact restoration. It runs no timer and performs no idle scans. Newly loaded traits require another deliberate OFF/ON cycle. Failed cleanup records remain retained; conflicting external trait costs are left untouched. The optimized game-thread batch reuses scanned rank wrappers, resolves player context before/after rather than perrank, and re-reads each asset's rank array once for verification/restore.

Persistent configuration is separate: electron/storyDaySettings.ts, main IPC/preload, and src/StoryDaySettings.tsx edit only the owned Game.ini setting with verified-build and closed-game guards. Exact baseline bytes or original absence are restored on OFF. Backups and ownership journal persist in the desktop user's configuration-backups directory. External config changes and corrupt backups block automatic restoration. %LOCALAPPDATA%/Dawnwalker/Saved/Config/Windows/Game.ini was absent before root's authorized live install.

Validation:11 isolated native Lua tests;12 facade tests/catalog28 sections/manifest25 files. Renderer/backend focused27 tests,6 App regression tests (F9/level/location), both TS projects and lint passed. Root live evidence qa/imported-menu/live-story-settings-optimized.json reports startup configured91/deadline91, live days ON/OFF readbacks, traits247zero/247restored with no external skips. Root measured end-to-end action times:refresh5430ms, daysON4129/OFF2177, traitsON3369/OFF2448; optimized run had no heartbeat loss. This proves those native readbacks, not every destructive progression purchase or absence of all resource spikes. Initial unoptimized trait action exceeded heartbeat freshness and was cleaned up; do not cite it as a passing performance result.

Root owns final config restore to original absence and normal deadline31 restart proof, full-suite/package/UI QA, performance sampling, and persistent vault capture. This agent did not execute any game mutation or install supplied archives.
`final-story-restored-roundtrip.json` completes restoration evidence: original Game.ini absence restored; restarted configured31/deadline31, live31→91→31 and247traitcosts zeroed/restored. Final report: qa/imported-menu/TIME-CONTROLS-STATUS.md.
