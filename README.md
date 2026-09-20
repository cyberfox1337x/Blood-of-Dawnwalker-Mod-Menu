# Blood of Dawnwalker Mod Menu

`cyberfox1337x.function("dawnwalker_mod_menu_readme")`

[![Electron](https://img.shields.io/badge/Electron-44-47848F?logo=electron&logoColor=white)](https://www.electronjs.org/) [![React](https://img.shields.io/badge/React-19-61DAFB?logo=react&logoColor=black)](https://react.dev/) [![Vite](https://img.shields.io/badge/Vite-7-646CFF?logo=vite&logoColor=white)](https://vite.dev/) [![TypeScript](https://img.shields.io/badge/TypeScript-5.8-3178C6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/) [![Three.js](https://img.shields.io/badge/Three.js-r185-000000?logo=threedotjs&logoColor=white)](https://threejs.org/) [![Lua](https://img.shields.io/badge/Lua-UE4SS-2C2D72?logo=lua&logoColor=white)](https://github.com/UE4SS-RE/RE-UE4SS) [![Vitest](https://img.shields.io/badge/Vitest-675%20tests-6E9F18?logo=vitest&logoColor=white)](vitest.config.ts) [![Platform](https://img.shields.io/badge/Windows-x64-0078D4?logo=windows&logoColor=white)](#requirements) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**A single-player desktop mod menu for _The Blood of Dawnwalker_ (Steam, Windows x64).**

A frameless Electron + React control panel talks to a UE4SS Lua runtime inside the game over a local, session-bound bridge. Every control shows a live readback from the game and refuses an operation it cannot verify, instead of reporting a change that never happened. Nothing in the game's install is patched: no executable edits, no `.pak` files, no anti-cheat or DRM interaction. The installer is transactional: it records backups, verifies the exact game build, and restores the original files on uninstall.

| | |
| --- | --- |
| Version | **0.1.0** |
| Supported game build | Steam build **25232147**, game **1.0.5 / CL258504** |
| Platform | Windows 10/11 x64, Steam release, single-player |
| License | [MIT](LICENSE); bundled third-party components keep their own notices |

![Player tab connected to a live game session](docs/screenshots/player-controls-connected.jpg)

## Features

- **Player**: God Mode, resource locks and refills, vampire-form override, sprint, super jump, personal flight, movement speed, no-clip, Zero Weight (carry capacity), player level, blood segments.
- **Combat**: Super Damage multipliers, cooldown and activation controls, Extended Parry Window.
- **Inventory & progression**: give / set item amounts from the full 1,650-item catalog, unlimited consumables, Ignore Crafting Requirement, currencies, experience multiplier, skills, traits and perks, previewed respec.
- **World**: time of day and story-day clock, game speed, difficulty axes, saved-location teleporting, Timeless Court activities with no time cost.
- **Visuals**: eye colour with glow, natural hair and eyebrow presets, live Skin Colour RGB with exact "Restore Original Skin", plus a local 3D preview of the eye colours.
- **Quests**: automatic quest-journal readback and objective reminders.
- **Save Editor** (game closed): DwSav-faithful editing of coins, skill points, level, XP, vitals, time of day, inventory rows (add / remove / quantity) and perk ranks, with automatic byte-exact backups and one-click restore.
- **F10** minimises or restores the menu from inside the game. Controls stay disabled at the title screen or when no verified session is loaded.

Every gameplay feature is a UE4SS Lua module under [`integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts`](integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts) and was verified live on the pinned build before being enabled in the UI. Anything not proven live is either read-only or hidden.

![Skin colour applied from the Visuals tab](docs/screenshots/skin-colour-menu-applied.jpg)

## Requirements

- Windows x64 with the Steam release of _The Blood of Dawnwalker_ on the supported build above. The installer and the runtime check the executable's size and SHA-256 and refuse any other build.
- Administrator approval for the per-machine installer.
- The compatible UE4SS runtime (official experimental zDEV `v3.0.1-1111-g97b7e501`, MIT) is bundled. Do not run another UE4SS install or a second enabled copy of the menu alongside it.

## Installing the packaged menu

1. Back up your saves, close the game, and close any running copy of the menu.
2. Run `Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe` (from [Releases](../../releases) or the Nexus page) and approve the elevation prompt. Verify the SHA-256 published with the download first; the installer is **not code-signed**.
3. The installer's preflight checks the game build and that the game is closed, then deploys the managed runtime with rollback backups. If preflight refuses, fix what it reports rather than copying files by hand.
4. Open the menu, launch the game through Steam, load a save, and wait for the "connected" state. Press **F10** to switch to the menu.

Uninstall through Windows *Installed apps*. The runtime helper restores its recorded pre-installation state and refuses to finish an incomplete restoration. The tested uninstall restored all 4,081 protected runtime files exactly and preserved all 50 save files.

## Building from source

Tested with Node.js 24 / npm 11 on Windows 11. Windows PowerShell 5.1 is required for the installer suites; a `lua` interpreter on `PATH` is optional for the standalone Lua harnesses.

```bash
npm install
```

```bash
npm run build
```

```bash
npx electron-builder --win dir --config.directories.output=release-current
```

Then launch `release-current/win-unpacked/Blood of Dawnwalker Mod Menu.exe`. For a live-reload development session use `npm run dev`.

Quality gates:

```bash
npm run lint
```

```bash
npm test
```

```bash
npm run test:lua
```

`npm test` runs the Vitest renderer/main-process suites (600+ tests) plus the Node round-trip checks. `npm run test:lua` runs the UE4SS module suites against the source tree. The full installer pipeline (signature check, lint, tests, runtime payload preparation, installer suites, release gate, build, NSIS packaging and packaged-installer verification) is `npm run package:current`; it fails closed if any step does not pass.

## Repository layout

| Path | What lives there |
| --- | --- |
| `src/` | React renderer: tabs, controls, save editor UI, 3D eye preview (Three.js) |
| `electron/` | Main process and preload: bridge transport, save-file codec, structural save edits, item catalog, asset protocol |
| `integration/imported-menu/` | The UE4SS Lua mod that ships in the installer (`Mods/DawnwalkerImportedMenu`), its manifest and pinned build identity |
| `installer/` | NSIS include, `electron-builder` config, the PowerShell runtime installer, its tests, and the vendored UE4SS zip |
| `scripts/` | Build, signature, packaging-contract and release-gate scripts |
| `analysis/dawnwalker-uue4ss/` | Reverse-engineering write-ups, standalone probes and their tests (captured dumps are not committed) |
| `qa/` | The final-release readiness and validation reports referenced below (raw evidence, minidumps and save backups stay local) |
| `docs/` | Design specs, the [full status and verification history](docs/PROJECT-STATUS-HISTORY.md), [third-party notices](docs/THIRD-PARTY-NOTICES.md) |
| `Dawnwalker_RE/` | Notes from studying the game's reflection data (the multi-GB dumps themselves are not committed) |

## Credits

- **cyberfox1337x**: desktop app, installer, Lua integration and project direction.
- **UE4SS**: Narknon and contributors (MIT).
- **ue4ss-ModMenu** framework provenance: Matthew arvidson / mattdavida (MIT).
- **Dawnwalker Form Toggle** contributors: adapted form operations (MIT).
- React, Three.js, Lucide, Cinzel and Cormorant Garamond retain their included notices. See [docs/THIRD-PARTY-NOTICES.md](docs/THIRD-PARTY-NOTICES.md).

_The Blood of Dawnwalker_ and all game content remain the property of their respective owners (Rebel Wolves / Bandai Namco Entertainment). This project is an independent fan tool and is not affiliated with or endorsed by them.
