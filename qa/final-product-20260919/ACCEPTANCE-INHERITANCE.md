# Scoped historical acceptance inheritance and current performance

## Preserved originals

`historical-regression/` contains byte-identical copies of the surviving September 18 session scratchpad `regress-sweep-1.log`, `regress-sweep-2.log`, `regress-sweep-3.log`, `regress-perf.log`, and original `perf_latency.py`. Their historical provenance is the September18 testing record; the raw text does not independently identify an executable hash. The original Python script is preserved evidence, not newly authored code, and is not executed: it includes gameplay setters. The fresh script only invokes read-only difficulty refresh.

The historical performance shorthand in the19:40 addendum is inaccurate: surviving raw results have medians55.0–301.8ms and p95≤391.3ms, still inside the declared400/1000ms limits. Preserve the original record and use these corrected values. Sweep3 first sends invalid boolean `True`, receives Boolean required, then correctly sends `true` and succeeds; that is a negative-input observation, not an unresolved product failure.

## Features

September18's `TESTING-RECORD.md` feature table and later regression are historical live evidence on game25232147. The current74file Lua payload stayed unchanged in the September19 continuation. The continuation record describes desktop process guards, status messages, removal of a duplicate process cache and HookEndPlay enablement; these are not a new live retest of every feature. Any inherited feature acceptance must bind the historical record/raw sweeps, current manifest and runtime integrity, September19 change scope/regression results, current compiled package parity, and this explicit limit. Relevant facts are in `../continuation-20260919/README.md`, `runtime-integrity.json`, `package-consistency.json`, and `../validation-20260918/TESTING-RECORD.md`.

Three user-approved exceptions remain independently identified: shrine-world-effect, permanent-blood-damage-repair, photo-camera. Their approval is documented in TESTING-RECORD19:50 section. Request-path verification does not establish their unavailable world effects; do not mark them working. The old warning section DWMenuWarnings remains present in native snapshots but is deliberately unmapped in src/importedMenuState.ts and excluded by ImportedMenuPanel's category filter; it is not exposed in the shipped desktop menu.

## Fresh performance — NOT fully passed

The requested read-only sample used the actual running release-current app.asar SHA256 `9E84448DF9BE2492FAC89719E478E5943AE86D3697C0CE6B0D9D8ECBD6291F2D`, gamePID29724 and connected session1789833928-529673-1 after experimental title-ready late load. This does not validate production startup. No UI/settings/gameplay setters were changed by these samplers.

- Idle60.056699seconds, four exact-package Electron processes:13.4375CPU seconds total =22.375%one core =**2.797%of8logical processors**. This **fails** the declared≤2%machine CPU target.
- Peak combined working set483,225,600bytes (483.23decimalMB /460.84MiB), below500MB.
- State size202,691bytes;60observed rewrites /60.056699seconds =0.9991/s, within≤300KB and≤1/s.
-20read-only difficulty-refresh round trips using20ms polls: median72.91ms, p95218.35ms, max225.56ms; all completed in the same session. Passes400/1000ms.

Raw sample records: `performance-current-idle.json`, `performance-current-read.json`; signed reproducible utilities `Measure-CurrentIdle.ps1`, `measure_current_read_latency.py`. CPU denominator uses measured elapsed time and8logical processors. Idle sampler's own PowerShell CPU is not included in menu CPU but sampling can perturb machine scheduling; the result is a bounded measurement, not universal performance. No fresh toggle/heavy-operation/cold-window-start measurements were made. Historical heavy-operation proof is explicitly inherited only while its implementation remains unchanged.

The performance ledger must remain open because current CPU exceeds target. Next useful work: isolate per-process CPU and poll sources, then remeasure after any scoped fix. D-8 startup and native installer roundtrip remain separate open acceptance scopes. No ledger state was edited here.
