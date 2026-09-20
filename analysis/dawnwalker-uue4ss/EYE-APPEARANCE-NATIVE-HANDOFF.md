# Eye appearance native discovery handoff

Date: 2026-09-06 UTC. Owner: `eye_customization`. Outcome: improved executable read-only discovery and 17 passing offline Lua test groups. Real-time eye editing, presets and original-appearance restoration remain unimplemented because the actual eye material and color parameter are not yet observed. No gameplay capability, compatibility pin, installer payload, save, configuration, or live game file changed.

## Reference and native evidence

[Su4enka — Coen Vampire Eyes Color](https://www.nexusmods.com/thebloodofdawnwalker/mods/26) was reviewed directly. Version 1 replaces the Leukocoria material through a `.pak/.ucas/.utoc` package, with one color installed at a time. The page does not establish a real-time getter/setter, parameter names, form-transition behavior or exact build compatibility. The user's granted reuse permission is retained; no archive or asset was acquired or incorporated. Existing Settings attribution remains feature inspiration. No further permission request is needed for the scope already granted, but permitted archive access and technical inspection remain separate prerequisites to reuse.

The captured current-build native SDK under `qa/discovery-current-build-20260906/fresh-metadata/CXXHeaderDump` establishes these specific APIs:

| Header and line | Evidence used |
|---|---|
| `Dawnwalker.hpp:1461` | Player derives from `AHumanoidCharacter`. |
| `Dawnwalker.hpp:1487` | Player has reflected `Form`. |
| `Dawnwalker.hpp:1600` | `IsInWolfForm()` supplies a separate form observation. The two-value human/vampire enum alone does not capture wolf state. |
| `Dawnwalker.hpp:1867` and `:1872` | Appearance component and inherited `HeadMesh` reference exist. HeadMesh identity is useful context, not proof of an eye slot. |
| `Dawnwalker_enums.hpp:550` | Human = 0, Vampire = 1. |
| `Engine.hpp:4512` | Parameter identity includes Name, Association and Index. |
| `Engine.hpp:9215` | Player components can be enumerated by class. |
| `Engine.hpp:20030` and `:20038` | Material instances expose Parent and scalar/vector/texture override arrays. |
| `Engine.hpp:20056` | Constant instances have name-only read getters; they cannot preserve layer/blend parameter identity. |
| `Engine.hpp:20076` | Dynamic instances have vector/texture/scalar `ByInfo` getters. The original reflected parameter-info object can be passed without constructing a guessed struct. |
| `Engine.hpp:22486` and `:22488` | Material count and slot names are readable. |
| `Engine.hpp:23510` | Skeletal mesh asset identity is readable. |

Neither a generic setter declaration nor the material replacement description proves which actual material/parameter is safe to change. No `EyeAppearanceController.lua` was fabricated from those declarations.

## Implemented discovery behavior

Owned changes:

- `analysis/dawnwalker-uue4ss/probes/DawnwalkerVisualsReadOnlyProbe.lua`
- `analysis/dawnwalker-uue4ss/tests/DawnwalkerVisualsReadOnlyProbe.Tests.lua`
- This handoff.

The probe retains explicit game-thread and exact current-discovery-build/hash guards. It is an inert importable module: no hook, automatic execution, file write, forced asset load, material creation or material mutation. `mutation_authorized=false` and `gameplay_verified=false` remain unconditional.

For each player-owned skeletal component it records the mesh asset, slot name/index, material chain and local scalar/vector/texture overrides. It now reads effective values from the leaf material using the observed native parameter-info object for dynamic instances. A constant instance is queried only for global parameters with index -1. Missing getters and marshaling failures produce individual errors while preserving the observed override data; a zero/default value is never presented as proof of parameter semantics. Base-material defaults and parameters absent from override arrays are not enumerated by this probe.

Inherited overrides are deduplicated by kind plus full parameter identity, with the nearest source depth retained. Same-name layer/blend parameters remain distinct. Duplicate same-layer identities reject the affected material instead of choosing an arbitrary restoration baseline. A shared leaf is counted across observed player slots. A count of one does **not** prove the instance is unshared with an NPC or another system.

The capture records `HeadMesh`, whether it occurs in the validated player component list, Human/Vampire and wolf state. It rereads component membership, owner, mesh asset, slot count/names and each successful material-parent chain; any topology change discards the entire snapshot. Final player/world/form/head checks run after that topology pass. Failed material slots remain explicit failures and cannot supply a baseline.

## Tests and integration

Run from the repository root:

```powershell
lua analysis/dawnwalker-uue4ss/tests/DawnwalkerVisualsReadOnlyProbe.Tests.lua analysis/dawnwalker-uue4ss/probes/DawnwalkerVisualsReadOnlyProbe.lua
luac -p analysis/dawnwalker-uue4ss/probes/DawnwalkerVisualsReadOnlyProbe.lua
luac -p analysis/dawnwalker-uue4ss/tests/DawnwalkerVisualsReadOnlyProbe.Tests.lua
```

All 17 test groups and both syntax checks passed. Coverage includes the original build/thread/form guards plus exact native parameter-info forwarding, inherited shadowing, distinct layer identities, refusal to use name-only getters for layer parameters, native getter failure, duplicate parameter/mesh rejection, shared material references, material/parent/slot/asset/owner/head replacement and a form change during the final topology pass. Tests are isolated fixtures; no in-game execution or visual effect is claimed. Both modified Lua files retain the executable `cyberfox1337x.function_signature(...)` marker.

Recorded SHA-256:

| Artifact | SHA-256 |
|---|---|
| Probe | `6BC5925485E9837CC5CCBD61F3E8C0C68A2BE8473125693A351E574301575E42` |
| Tests | `507DA9CDF7969DAA887F5CAFB84058DE358557D364EF566240C8E7C35FF43631` |
| Current captured Engine.hpp | `8A6BD33456790126E138812266DE79319EF8FD113ED070EA45B63C31D6ABFCE9` |
| Current captured Dawnwalker.hpp | `BD9B897086D3FA7D3104788101E8F946930DD3DF7856420A327597C0D25B01D5` |
| Current captured Dawnwalker_enums.hpp | `9C7963DD70492DF1DAE155CC8A8023C8AF1DB3C338BC7BD7E3EE31F48887683F` |

Integration stays with the coordinator. After supported interactive recovery, the sole live-test owner can explicitly import and invoke `Probe.run` within the bounded current-build game-thread discovery driver, using its existing attested identity and local-player resolver, then emit `Probe.format_lines(result)`. This module was not copied into the staged discovery candidate or enabled game profile. Preserve the exact source/hash alongside each future output, native log, local player/world identity and screenshot.

## Exact remaining dependency and next safe step

Computer Use stopped this turn at browser URL verification. No desktop action, alternative download bypass or live installation was performed by this owner. The coordinator must reacquire a supported verified session before interactive work. There is no reason to hold the other feature owners on this dependency.

1. With the game closed and backup state established, the sole live owner prepares the explicit current-build read-only driver. Capture this probe on the loaded player in human and vampire states, and around wolf transition if available. Test actual Lua marshaling; current evidence is reflection plus fixtures only.
2. Identify the visible eye slot by observed player-owned mesh/material identities and visual inspection. If the authorized Su4enka archive becomes available through supported means, inspect its actual asset path and changes to narrow this search. Do not infer the path, preset RGB values or parameter name from the mod title.
3. Establish the full parameter identity, effective original color/texture, color-space/range behavior and whether a change affects only Coen. If a private dynamic instance is required, prove creation, slot binding, readback and exact original-material rebinding before exposing editing. Never mutate a shared parent asset.
4. Implement a controller only from those observations. Bind restoration state to session/world/player/mesh/slot/material generation; discard stale state on replacement and never restore an old material into a new form's slot. Human/vampire/wolf transitions require a separately captured baseline. Do not blindly reapply a preset across transitions.
5. Prove bounded adjustment, independent readback, visible effect, original restoration, repeated toggle, form changes and save reload. Only then wire the menu and promote eye capabilities. Until that evidence exists, Settings credits remain present and Eye editing remains unavailable.

Related: [team board](../../qa/TEAM-BOARD-20260906.md), [runtime discovery](REQUESTED-RUNTIME-FEATURE-DISCOVERY.md), [reference review](NEXUS-FEATURE-REFERENCES.md).
