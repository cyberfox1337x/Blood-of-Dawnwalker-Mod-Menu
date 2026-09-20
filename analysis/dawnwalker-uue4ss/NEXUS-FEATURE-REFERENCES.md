# Dawnwalker feature references

Reviewed 2026-09-05. Each entry distinguishes the original author's published functionality from this menu's implementation. Source-page claims are not independent gameplay verification. Settings attribution uses **Feature inspired by** for all seven entries; no referenced mod code or assets are bundled, and none is a runtime dependency of this menu.

The current installed build differs from the validated bridge contract. See [runtime discovery](REQUESTED-RUNTIME-FEATURE-DISCOVERY.md) for the exact identities, native candidates, unresolved contracts, and testing procedure. New runtime features remain unavailable until that boundary is resolved.

## Eye appearance: Su4enka

**Coen Vampire Eyes Color**, version 1, replaces vampire eye material. Eight color downloads are listed; one color may be installed at a time. Installation uses `.pak/.ucas/.utoc` packages. No loader requirement, precise game-build compatibility, or public source repository is stated. No additional contributor is named. Modification and asset reuse require permission; redistribution elsewhere is prohibited. [Description and permissions](https://www.nexusmods.com/thebloodofdawnwalker/mods/26), [files](https://www.nexusmods.com/thebloodofdawnwalker/mods/26?tab=files).

**Decision/current:** Independent runtime investigation. No presets or original packages imported. Live eye material ownership, parameter semantics, form transitions, and restoration remain unverified; eye editing is unavailable.

## Attack speed: Grimpil

**Faster Attacks - Player Attack Speed**, version 1; its single file is labeled `FasterAttacks UE4SS 0.1`. The guide describes a Lua mod requiring Dawnwalker-compatible UE4SS. Two player melee attack rates change; charged attacks, focus abilities, and weapon arts are excluded. `FasterAttacks.ini` configures it; an `.off` file restores normal behavior without restart. The page claims September Steam compatibility, without an exact build pin. Permission is required for modification/reuse; redistribution is prohibited. [Description](https://www.nexusmods.com/thebloodofdawnwalker/mods/57), [files](https://www.nexusmods.com/thebloodofdawnwalker/mods/57?tab=files).

**Decision/current:** Independent implementation path; no dependency imported. Player-only ownership, typed writes, restoration, and visible attack timing remain unproved. Global speed stays separate.

## Fog: DaraTeaGod

**Remove Fog**, version 1, supplies an `Engine.ini` adjustment. The instructions place it in the game's per-user Windows configuration directory and recommend a read-only file attribute. Other INI adjustments may be merged. One download is listed; no runtime loader, public source repository, or exact compatible build is specified. Modification/reuse requires permission; redistribution is prohibited. [Description](https://www.nexusmods.com/thebloodofdawnwalker/mods/69), [files](https://www.nexusmods.com/thebloodofdawnwalker/mods/69?tab=files).

**Decision/current:** Independently authored configuration editing for `r.Fog` and `r.VolumetricFog`, with original-file backup and restoration. Requires a game restart. The original INI is not incorporated. Visual fog removal is **Not verified in game**.

## Stamina: nectarines

**Stamina and Sprint Tweaks**, version 0.3.0, provides independent sprint and combined block/dodge asset modules without a loader. Files include the main package and sprint-only option. The page lists conflicts with sprint, omniblock, and dodge cost assets. Its changelog claims both character forms; an older “tested version” subsection still says 0.1.0. It credits Rebel Wolves and Bandai Namco Entertainment for game assets. Modification/reuse requires permission; redistribution is prohibited. [Description](https://www.nexusmods.com/thebloodofdawnwalker/mods/17), [files](https://www.nexusmods.com/thebloodofdawnwalker/mods/17?tab=files).

**Decision/current:** Independent per-action controls remain unavailable. The existing broad stamina lock does not establish separate sprint, directional blocking, omniblock, and dodge behavior.

## Console and loading: KZekai

**Console Enabler and Mod Loader**, version 0.6.3e, supplies SML, command/item documentation, and mappings. The page describes Blueprint/CME loading and `cheatmenu`, `addcoin`, `listitems`, and `additem`. Its [plain-text README](https://file-metadata.nexusmods.com/file/nexus-readmes/9719/16/Readme_SML.txt) names **KeinZantezuken** in credits, lists UE4SS as a conflict, and excludes Game Pass support. Modification/reuse requires permission; redistribution is prohibited. [Description](https://www.nexusmods.com/thebloodofdawnwalker/mods/16), [files](https://www.nexusmods.com/thebloodofdawnwalker/mods/16?tab=files), [documentation](https://www.nexusmods.com/thebloodofdawnwalker/mods/16?tab=docs).

**Decision/current:** Keep the independent UE4SS bridge; do not add conflicting SML. Credit KZekai and the README's named contributor without assuming alias identity. Console availability proves no god-mode command or inverse. Existing god mode requires current-build revalidation.

## Save tools: FullTimePatriot

**Blood of Dawnwalker Save Editor**, version 6, has one 9.9 MB application download. It advertises time, currency, health, and daytime stat-point editing, plus repair for earlier lighting problems. Requirements are listed as none. The reviewed pages provide neither a save schema nor a public source repository or exact compatible build. Modification/reuse requires permission; redistribution is prohibited. [Description](https://www.nexusmods.com/thebloodofdawnwalker/mods/43), [files](https://www.nexusmods.com/thebloodofdawnwalker/mods/43?tab=files).

**Decision/current:** Independent integrated inspection, verified backups, restore previews, and recovery. Gameplay-field editing remains unavailable because the compressed DSAV payload and reload semantics are unverified. Save-list metadata is not substituted for gameplay values.

## Focus: Caites

**Focus Tweaks**, version 1.2.1, lists a UE4SS main download and optional brighter-target asset package. It advertises doubled detection/smell distances from 4000/2000, reduced focus zoom/FOV effects, and changed target postprocessing. Dawnwalker 1.0.3 compatibility is claimed; overlapping focus assets may conflict. Dawnwalker-compatible UE4SS is required for the script. No public source repository is linked. Modification/reuse requires permission; redistribution is prohibited. [Description](https://www.nexusmods.com/thebloodofdawnwalker/mods/81), [files](https://www.nexusmods.com/thebloodofdawnwalker/mods/81?tab=files).

**Decision/current:** Independent range, smell, zoom, and visibility investigation. No original script or material imported. Each adjustment remains unavailable until its current native contract, visible effect, and restoration are proved.

## Source availability and attribution boundaries

All seven description and file-list pages were readable. Their listings and installation instructions establish advertised payload types, not archive contents. The reader's manual-download routes returned page shells without accessible archive bytes; script-main listings for attack speed and focus exposed no downloadable script text. No archive was obtained, unpacked, or executed, and no missing source implementation was inferred. No authentication or download restriction was bypassed. The SML plain-text README was available and was read directly.

SML's README links [Kein/AlpakitSO](https://github.com/Kein/AlpakitSO), a public packaging-tool repository with an MIT license and upstream Alpakit credits. That repository is not identified as the SML implementation. No packaging-tool code or assets are included or required here; its license does not grant permission to redistribute SML.

The main pages otherwise name no additional file contributor. The stamina description's game-asset credits and SML README's contributor are retained explicitly. None of these acknowledgments implies collaboration, endorsement, or permission. Before any future direct reuse, obtain permission and preserve all applicable notices; before a dependency integration, verify its exact version, local installation, conflicts, command behavior, failure handling, and rollback.

## Menu implementation evidence

- `electron/featureReferences.ts`: verified creator/title/feature mapping and original-page links for Settings.
- `electron/fogSettings.ts`: independent configuration editing, backup ownership, and restoration; restart and visual-proof limits are explicit.
- `electron/saveEditor.ts`: selected-save inspection, recoverable backup/restore flow, and a closed gameplay-field editing gate.
- [Requested runtime feature discovery](REQUESTED-RUNTIME-FEATURE-DISCOVERY.md): remaining native contracts, inert read-only probe, offline test results, and gameplay verification requirements.

Build checks and unit tests for these menu components do not validate the original third-party mods or prove the menu's visible gameplay effects.
