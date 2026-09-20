# Requested runtime feature discovery

Date: 2026-09-05. Status: **Not verified in game**. This records static discovery and an offline-tested, read-only probe. It is not a runtime capability contract or permission to promote the bridge.

## Build boundary

The current session's installer verification identified Steam build **25129649**, Unreal **5.5.4 / CL-257186**, executable length **176196472**, SHA-256 **7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853**. The executable retains a valid Rebel Wolves signature. This differs from the repository contract, which permits build **25107392 / CL-256914**, executable SHA-256 **45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E**. The captured SDK and JMAP are older again: **CL-256181**, captured 2026-09-02.

No new feature probe was installed, no game launch was initiated, and no game state was changed during this discovery. An executable signature confirms publisher identity; it does not establish compatibility with old reflected contracts. Do not re-pin a contract merely to get past the mismatch.

## Exact static findings

| Requested area | Observed native contract candidates | Missing evidence |
| --- | --- | --- |
| Attack speed | `UCombatConfig.CombatModes` maps `ECombatModeType` to `UCombatMode`. `MetricsScalingSettings.AttackPlayrate` and `.StrongAttackPlayrate` are distinct from dodge, block, reactions, and root motion. | The JMAP contains only `Default__CombatMode`, with both attack rates `1`. It does not contain the concrete player mode data assets. Loaded ownership, NPC exclusion, mutable struct write semantics, attack timing, and rollback must be proved. Global time dilation is not a substitute. |
| Sprint cost | `UPlayerAttributeSet.SprintStaminaCostMultiplier`; `UMMC_SprintStaminaCost`; separate human/vampire/astral sprint effects. | No verified by-reference gameplay-attribute setter path or isolated gameplay/restore proof. The broad native stamina lock affects multiple actions and cannot provide independent sprint cost behavior. |
| Dodge cost | `UPlayerAttributeSet.DodgeStaminaCostMultiplier`; `UCombatMode.DodgeStaminaCost`; native `GetDodgeStaminaCost()`. `GE_DodgeStaminaCostMultiplier` is an infinite additive effect using `Stats.CustomModifier`. | Descriptor ABI, effect ownership/handle restoration, effective value after other modifiers, human/vampire behavior, and isolation from sprint/block remain unproved. `Default__PlayerAttributeSet.DodgeStaminaCostMultiplier` is `0`; it is not evidence of the active player's baseline. |
| Blocking cost | `UCharDevAttributeSet.OmniblockStaminaCostMultiplier`; `GE_OmniblockStaminaCostMultiplier`, with an infinite additive modifier using `Stats.CustomModifier`; `GE_Combat_StaminaCost_Omniblock`. | Omniblock is the exact observed mechanic. It is not evidence that all ordinary blocking costs use the same path. Avoid a general blocking label until gameplay confirms the scope. |
| Focus distance / smell | `UPlayerAttributeSet.{MaxFocusRange, MaxFocusSmellRange, ActiveFocusRange, ActiveFocusSmellRange}` and `ADawnwalkerPlayerCharacter.FocusModeActiveRange`. | Authoritative initialization, safe setter and active-vs-maximum relationships, aggregation, focus reentry behavior, and restoration. The native CDO maximums are `0`; reference values `4000/2000` must not be written as the player's captured originals. |
| Focus zoom / visibility | `UFocusAbilityCameraMode` exists; `UFocusableComponent.SetHighlight` and `.GetHighlightType` exist. | A camera class or highlight setter alone does not establish a player focus FOV contract, identify which targets should be highlighted, or prove safe restoration. No focus-specific zoom setting was located in the captured native SDK. |
| Eye appearance | Standard `Actor.K2_GetComponentsByClass`, `PrimitiveComponent.GetNumMaterials/GetMaterial`, and material-instance local scalar/vector parameter arrays can be inspected without setting anything. | No concrete eye material or eye parameter name exists in the captured JMAP. Eye slot ownership, inherited parameter values, color-space behavior, creation/restore of dynamic material instances, human/vampire transitions, loading, and save reloads remain unproved. A parameter containing "eye" is not visual proof. |

The old enum records `None=0`, `VampireSword=1`, `Sword=2`, `VampireHandToHand=3`, `HandToHand=4`, `Fistfight=5`, `MAX=6`. The probe reads only the five concrete values and rejects an incomplete map; it never writes a shared data asset.

The exact native attribute setter is `CombatBlueprintFunctionLibrary.SetAttributeValue(UAbilitySystemComponent* AttributeOwner, FGameplayAttribute& AttributeToSet, float AttributeValue)`. Its descriptor parameter is a reflected reference/out struct. Existing carry-capacity research already demonstrates why a guessed Lua descriptor or direct `BaseValue`/`CurrentValue` write cannot replace a proved ABI. Relevant immutable descriptor sources include `GE_DodgeStaminaCostMultiplier`, `GE_OmniblockStaminaCostMultiplier`, and `GE_Focus_Flush`; the last resets active focus attributes through gameplay effects and must not be applied as a generic range change.

## Probe and test

`probes/DawnwalkerRequestedFeaturesReadOnlyProbe.lua` is an inert module with `run(deps)` and `format_lines(result)`. It has no auto-run code, key binding, file access, setter, asset loading, or effect application. It requires the existing exact-build attestation and the game thread. It therefore rejects the newly observed build. It does not check the executable itself; the invoking installer/controller must produce that attestation from the normal identity verifier, not a hardcoded claim.

Its observations include:

- The exact playable player and world identities before and after collection.
- Separate focus, sprint, dodge, and omniblock base/current values.
- The player combat component's property/getter agreement, all five loaded combat-mode identities, attack rates, and unrelated rates for later comparison.
- Up to 32 player-owned skeletal mesh components, 32 material slots per component, and 128 local scalar/vector overrides per material. It records observed names and values without inferring which is the eye or changing material instances.

Each feature section reports its own failure. A changed player/world discards all partial observations. `mutation_authorized=false` and `gameplay_verified=false` are unconditional. Material local override arrays do not enumerate all inherited material parameters; an empty array is not proof that editing is impossible.

Validation:

```powershell
lua analysis\dawnwalker-uue4ss\tests\DawnwalkerRequestedFeaturesReadOnlyProbe.Tests.lua analysis\dawnwalker-uue4ss\probes\DawnwalkerRequestedFeaturesReadOnlyProbe.lua
```

Result: **8 passing offline test groups** covering complete observations, code-side mutation exclusion, exact identity/game-thread preflight, wrong classes/CDOs, nonfinite values, incomplete mode maps, independent section failures, config/mesh ownership, container bounds, world drift, and report encoding. Both authored Lua files include executable `cyberfox1337x.function_signature(...)` markers.

## Next safe procedure

1. Finish the current bridge and installer regression checks while maintaining the build mismatch block.
2. Capture a complete closed-game save backup and the installed loader/config baseline through the existing transactional workflow.
3. Establish inert loader compatibility on CL-257186 and capture fresh read-only metadata before accepting any old function/struct contract on that build.
4. Review this probe against that metadata, update the attestation only after review, and run it on a disposable loaded offline save through a separately reviewed game-thread driver. Preserve its report with the verified build identity and capture time.
5. For each candidate, prove its typed descriptor or material readback before any write. Define original-value capture, same-object ownership, bounded adjustment, read-after-write, inverse, and read-after-inverse requirements before adding a mutator.
6. Test repeated enable/disable, transitions, reloads, feature interaction, and visible gameplay behavior. Keep absent proof labeled **Not verified in game**, and unavailable controls out of the advertised capability set.

The runtime probe does not change files, so it requires no rollback itself. Later game tests must use the existing closed-game save restoration procedure and retain the modified test tree separately before restoring the original tree with path/length/SHA-256 equality checks.

## Current-install audit and isolated candidate, 2026-09-06 UTC

Fresh direct checks independently agree: the Steam manifest has build `25129649`, the signed executable reports `CL-257186`, and its length/hash match the newer identity above. The production installer's `Status` reports the same mismatch. This is real installation drift, not a reason to change status text or bypass the build guard.

There are two distinct installation records. Production status reports `not-installed` because its ProgramData ownership state is absent. The analysis pilot is physically present: its installed `0.3.21-pilot` script matches the source SHA-256 `F7A94576037C18288142CB14172A05854E3FBC8BF1071C2BC721B70D03F8DC85`, its mod is enabled, and `HookEngineTick=1`. The older analysis transaction still records build `25107392`. Production ownership status is therefore not evidence that no loader exists.

At this audit, the game was closed, the installed `UE4SS.log` was empty, the game's saved-log directory had no files, and the bridge `ready.txt` contained 532 NUL bytes. Those bytes are not a heartbeat; their cause is not established. Older trait readbacks do not prove attack/focus contracts on the new build, and no fresh current-build SDK or concrete player mode capture was located in the scoped evidence search.

The primary [Faster Attacks description](https://www.nexusmods.com/thebloodofdawnwalker/mods/57?tab=description) describes two player attack rates and restoration, but provides no exact `25129649` ABI or ownership proof. The [Focus Tweaks description](https://www.nexusmods.com/thebloodofdawnwalker/mods/81?tab=description) names game version 1.0.3 rather than this executable identity. Neither page supplies the missing live contract. A scoped public-source search found no additional author repository; that is a search result, not proof that no source exists.

Computer control has since connected successfully in the coordinating session. A separate candidate now exists at [`qa/discovery-current-build-20260906`](../../qa/discovery-current-build-20260906/RUNBOOK.md), with the exact current identity, successful pinned-archive verification, and a successful installation preview. It includes only inert and restricted dump templates; all 14 hooks and every mod are disabled for the first launch. The original reviewed contract is unchanged, and preparing the candidate performed no game mutation or launch. Candidate status is **identity verified, awaiting loader smoke**; attack and focus remain unverified.

The [candidate runbook](../../qa/discovery-current-build-20260906/RUNBOOK.md) gives executable module parameters for an independent backup comparison, isolated state, inert replacement, fresh-log review, restricted metadata capture, and rollback. Its `runtime-audit.json` and `preflight.json` preserve the observations. The baseline pilot must be fully backed up and replaced before the first launch, and candidate rollback must not accidentally become permission to relaunch that old enabled pilot. No bridge-pilot promotion is included.

### First current-build inert run

The coordinating session subsequently installed isolated transaction `20260906T014437Z-2409b51d` after independently verified backups. Read-only verification matched all 342 installed files, all 14 configured hooks disabled, all 12 registered mods disabled, no action-mod directory, exact template bytes, and both loader DLLs against their bytes inside the pinned archive. No old log existed before launch.

The coordinator visibly observed the `1.0.3 (257186)` main menu, later a loaded game, and normal exit. The selected slot was not recorded, so this is not a controlled save-slot test. The preserved fresh log reaches `Event loop start`, identifies the expected executable length, records Keybinds disabled, and contains no fatal/startup-failure marker. Disabled-hook warnings are consistent with this configuration. The unresolved hash-table scan uses forced `GUObjectArray` iteration; console resolution remains unavailable. UE4SS still installs internal FName/StaticConstructObject hooks: disabling all configurable hooks does not mean zero native interception.

Post-run exact identity and stopped-process checks passed. All 95 original `Saved` files retained their length and SHA-256; one 194-byte CrashReportClient configuration file was added during startup. No `Saved/Crashes` directory or matching Windows Application error/report event was observed. This file alone does not establish a crash, and no save was restored by this review.

The log and review are preserved under [`inert-smoke-20260906T015025Z`](../../qa/discovery-current-build-20260906/inert-smoke-20260906T015025Z/review.json). This supports proceeding to the restricted asynchronous metadata profile with all configured hooks still disabled, after another stopped-build check. It does not verify a gameplay contract. Expected outputs are `ue4ss/CXXHeaderDump`, a current-version `.jmap` in the UE4SS working directory, and `ue4ss/UE4SS_ObjectDump.txt`; confirm actual paths and completion in the fresh dump log before using them.

### Fresh metadata and next read-only player candidate

The coordinator subsequently promoted only the restricted dump profile and observed the current-build main menu. C++ generation completed at `2026-09-05 22:03:23` local time in 5.006 seconds. JMAP generation completed at `22:05:01` with 54,035 objects, 5,963 vtables, and zero dumper warnings. The verified copies are in [`fresh-metadata`](../../qa/discovery-current-build-20260906/fresh-metadata/manifest.json): 2,239 headers plus the 148,503,035-byte JMAP, SHA-256 `CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6`.

The scoped comparison found all 11 relevant native headers byte-identical to the previous capture. All 1,627 selected native class/function/struct/enum records also match after excluding process addresses, native implementation pointers, instance property values, loaded-child lists, and object loading flags. The selected classes cover the existing 19 bridge capabilities, local controller/pawn and component ownership, attack mode structures, attribute descriptors, and materials. No reflected layout or function-signature drift was found in that scope. Executable implementations, Lua marshaling, live ownership, gameplay behavior, and rollback still require current-build tests.

The main-menu JMAP still contains only default combat-config/mode instances. To inspect actual player assets, [`read-only-candidate`](../../qa/discovery-current-build-20260906/read-only-candidate/README.md) now contains a separate current-build probe and bounded game-thread driver. The candidate captures player/world stability; combat/ASC owner equality; loaded attack-mode identities and rates; focus/stamina values; native `GetAllAttributes` descriptor names and owner types; and bounded material observations. It has no setter, effect application, forced asset load, or gameplay capability advertisement.

The coordinator must stage that candidate separately with only EngineTick and its read-only mod enabled. `F6` requires an exact build/metadata attestation issued from fresh verifier results, bound to the logged boot and a single-use nonce with a 120-second expiry. The driver checks the route and `IsInGameThread()` again inside the callback, rejects ProcessEvent fallback, and allows at most four reports per boot. Its issuer writes only the workspace; installation, attestation copying, game input, and rollback remain coordinated operations. Preparation changed no game file or production pin. Ten probe and eight driver offline test groups pass; the actual current-build player probe has not yet run at this milestone.

## Authoritative local evidence

- `official-build.json`: existing exact-build contract.
- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/DogwoodCombat.hpp`: `FMetricsScalingSettings` at line 312; `UCombatConfig.CombatModes` at 1362; `UCombatMode` at 1549; `UFocusAbilityCameraMode` at 1819.
- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/DogwoodStats.hpp`: omniblock attribute at 270; `UPlayerAttributeSet` and separate cost/focus attributes at 838.
- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/Dawnwalker.hpp`: inherited `CharacterAttributeSet` at 1271; player component/attribute pointers and active focus state at 1473-1485.
- `captured-dump/2026-09-02-cxx-sdk/CXXHeaderDump/Engine.hpp`: `K2_GetComponentsByClass` at 9215; `UMaterialInstance` local parameter arrays at 20026-20040; `GetNumMaterials`/`GetMaterial` at 22486/22492.
- `captured-dump/2026-09-02-jmap/Dawnwalker-5.5.4-256181+dw1-pc-256181-shipping-patch2-all-97b7e501.jmap`: enum, `Default__CombatMode`, `Default__PlayerAttributeSet`, exact setter signature, and named gameplay-effect objects.
- `CARRY-CAPACITY-FEASIBILITY.md` and `probes/DawnwalkerCarryCapacityReadOnlyProbe.lua`: descriptor ABI and read-only verification precedent.

Reference authors, current page descriptions, reuse permissions, and in-menu credits are maintained by the coordinating feature-reference work. This probe uses independently authored logic and the user's local game reflection; it incorporates no Nexus mod source or assets.
