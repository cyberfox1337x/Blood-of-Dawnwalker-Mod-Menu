# Freebuff handoff review and stabilization

`cyberfox1337x.function("dawnwalker_freebuff_handoff_review")`

Reviewed 2026-09-06 UTC. This is a development handoff, not a gameplay release or a fresh live verification.

## Recovered history

Freebuff's **Continuing Mod Menu Development** task was found in its Documents project SQLite database, opened read-only. Task `22ee2693-51b8-4d6d-b7e8-cedffb04fd0c`, message 29, was interrupted while wrapping up a higher-rank Unblock Trait persistence probe. No project Git commits exist, so author attribution cannot be established from commits; the source and recovered tool outputs supply the history.

Freebuff completed the 0.3.21 pilot's delayed Unblock Trait verification, the FName-safe trait roster resolution, promotion, bounded Add Level/Unblock Trait probes, and the September 3 read-only and safe-reversible suites. Their original artifacts remain in `qa/pilot-evidence/`. The late interrupted probe recorded Human_CraftingOne at rank 3 and Human_ToughSkin at rank 2 after a reboot, an unknown-trait rejection, a successful temporary-driver quicksave, and restoration of the 91-file pretest tree. The final cleanup tool did remove the temporary SaveDriver and its enable lines.

That last probe did **not** record the exact reloaded slot or an executable hash for that run. Its backup labels CL-256914, while the installation has since moved to CL-257186. These historical observations must not be converted into exact-build gameplay proof. Downstream trait purchases, resource-lock endurance, and state-transition behavior remain unverified.

## Current audit

The structured record is [`dawnwalker-freebuff-handoff-audit-20260906.json`](../../qa/pilot-evidence/dawnwalker-freebuff-handoff-audit-20260906.json). It separates recovered historical observations from fresh read-only file checks.

- Dawnwalker was closed during the audit; no gameplay mutation was performed.
- All 91 live save-tree files match the higher-rank pretest manifest by path, length, and SHA-256. No restoration was repeated.
- The temporary SaveDriver directory and enable line are absent. A historical roster-enumerator comment remains; it enables nothing. Whole-file restoration of `mods.txt` is not claimed.
- Installed and source pilot Lua match SHA-256 `F7A94576037C18288142CB14172A05854E3FBC8BF1071C2BC721B70D03F8DC85`.
- **Installed Steam build 25129649 / CL-257186 differs from the reviewed 25107392 / CL-256914 contract.** Current executable: 176,196,472 bytes, SHA-256 `7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853`, valid Rebel Wolves Authenticode signature. No contract was re-pinned to it.

## Fixes completed

1. Electron transport and the pilot dispatcher now allow an eight-second Unblock Trait response window. The Lua handler can legitimately defer for forty 150 ms ticks, so the former 3.5-second Electron and five-second CLI limits could announce failure before the authoritative verdict. The Electron queue remains serialized until that verdict arrives.
2. `electron/gameBuildIdentity.ts` checks the installed Steam manifest and exact executable size/hash against the supplied official contract. It rejects missing or malformed identity files and path traversal, invalidates cached hashes on executable identity changes, and refuses a file changing during hashing. The main-process integration uses this result before runtime readback or mutation.
3. Payload preparation, runtime installer, and release gate now consistently pin the already-reviewed build 25107392 and executable `45B7C294...`. Freebuff had updated the source contract but left these enforcement constants at build 25014996. Independent enforcement pins remain explicit to prevent an edited contract from silently granting compatibility. Associated installer/release fixtures were aligned. This does **not** authorize the newly installed build.
4. The discovery payload was regenerated from its inert source: zero gameplay capabilities, 363 verified nested runtime files, exact source/payload Lua parity. The previous generated payload was preserved at `%TEMP%/dawnwalker-runtime-payload-before-handoff-20260906`. No game installation was changed.

## Verification

Initial baseline passed: lint; 95 Vitest tests in 12 files; pilot promotion; Add Item; Add Level/Unblock Trait; carry-capacity feasibility and Lua probe; Unlock All Skills planner; discovery-source Lua; packaging contract; runtime installer; release gate.

Stabilization regression checks passed:

- Electron transport received an accepted readback after 6.1 seconds while keeping the next queued command from superseding it.
- The standalone CLI received a delayed runtime rejection after 6.1 seconds, returned exit code 2, and retained the authoritative unchanged-level explanation.
- Four installed-identity tests cover a manifest update, a same-length changed executable after a cached success, missing/malformed files, and traversal.
- Electron TypeScript build and scoped lint passed.
- Actual installed-identity inspection rejected build 25129649 with the correct expected 25107392 reason.
- `prepare:runtime:qa`, `test:lua:qa`, `test:runtime-installer`, `test:release-gate`, and `test:package-contract` passed after identity alignment.

These checks prove source/transport/file-safety behavior. They do not prove gameplay effects. Final integrated renderer, full regression, and packaging checks are recorded by the parent feature-expansion handoff.

## Next safe step

Keep runtime controls unavailable on build 25129649. Inspect and document that build, establish a fresh isolated read-only loader/reflection baseline, then revalidate each intended runtime contract and restore path before promoting or advertising it. Use [`REQUESTED-RUNTIME-FEATURE-DISCOVERY.md`](REQUESTED-RUNTIME-FEATURE-DISCOVERY.md) for the bounded candidate probe. Preserve the original save and evidence artifacts throughout.
