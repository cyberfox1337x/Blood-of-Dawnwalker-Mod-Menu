> **Final update:** the corrected installer passed the native roundtrip and was promoted byte-for-byte to release-final. The current release gate is ready=true with no blockers, retaining explicit performance/startup limitations. See [authoritative final readiness](FINAL-RELEASE-READINESS.md). Earlier decision points below are historical.
> Latest review: the byte-restoration candidate SHA256 `980F746F4A634D36B56A828DEC0C82E8729559F7821F40B357EC08F79196B146` supersedes the earlier candidate below. Extraction parity passed with unchanged desktop application hashes. Performance and startup are now explicitly **accepted with disclosed limitations**, not benchmark passes or a fixed hang; see [qualified release decision](QUALIFIED-RELEASE-REVIEW.md). The [current gate result](qualified-release-gate.json) has only native installer roundtrip pending. Historical report text below preserves the earlier decision point.
# Current candidate readiness — September 19, 2026

**QA candidate verified; production gate remains closed with three open records:** performance, startup-stability, installer-roundtrip. The actual gate exits 1. Ten stale source/build bindings were reviewed and updated to current contents; features now pass through explicit scoped inheritance. No performance threshold or other acceptance status was changed. [Current gate output](current-candidate-gate-after-review.json), [previous 14-blocker audit](current-candidate-gate-audit.json), [preserved previous ledger](release-proof-before-reviewed-rebinding.json).

## Candidate and verified behavior

[Current NSIS candidate](../../release-current-installer-qa-read-recovery/Blood%20of%20Dawnwalker%20Mod%20Menu-Setup-Current-0.1.0-x64.exe): 202,925,660 bytes; SHA256 `526BD2038E80C2CD20B3C97965D5B3C0C5900601047E933CDEECE469DC58E16B`; unsigned. Extraction verified 82 runtime resources, 118 compiled desktop files and 74 imported payload files. Embedded app.asar SHA256 `92CC51C3FD148966E0160AA2B3C6728A677D4A7737C4854B438CAD4B42B08F71` matches the tested release-current package. [Verification](read-recovery-installer-verification.json), [hashes](read-recovery-installer-hashes.json).

Read-recovery changes passed lint/build and 635 Vitest plus 11 Node tests. Exact-build closed-game preflight passed. Latest loaded-save normal quit exited with shutdown=quit and all 50 save files unchanged. These prove eligibility and lifecycle behavior; they do not prove installation. [Tests](read-recovery-final-tests.log), [preflight](read-recovery-closed-preflight.log), [shutdown/save check](read-recovery-final-shutdown-save-check.json).

## Feature acceptance and reviewed identity

[Hash-bound feature manifest](current-feature-acceptance.json) distinguishes inherited, new and exception evidence. The unchanged 74-file gameplay payload, historical shipped-control matrix/raw sweeps, 222 current integrity checks, 118 compiled package comparisons, changed-path regressions, and packaged God Mode ON/OFF plus fresh-session autoquest/reconnect support scoped feature acceptance. Historical logs lack independent executable hashes; their provenance is the dated testing record and unchanged manifest. This is not a new full live sweep.

Three explicit user approvals in the September 18 19:50 testing record are now hash-bound: shrine world effect, repair of actual permanent blood damage, and photo camera. Their unavailable world effects remain unverified. DESIGN/refusal behavior in the historical matrix stays its documented design. No new exceptions were invented.

The ten updated identity bindings are listed with old/new hashes in the feature manifest: importedMenuContract declaration/source, importedMenuTransport source/test and compiled JS/maps, tsconfig build metadata, and App test. They match the tested recovery changes. Existing lifecycle acceptance and its evidence remain unchanged. The ledger now binds 23 feature evidence artifacts, including the manifest, rather than merely trusting an unbound narrative.

## Remaining records

| Record | Current evidence and limitation |
|---|---|
| performance | Normal foreground idle CPU 2.106183% exceeds the agent-proposed 2% benchmark. RSS 475,410,432 bytes passes decimal 500 MB. Native traces identify substantial accessibility/COM servicing without proving its caller. Background 0.732% and temporarily disabled-accessibility 0.971% are diagnostics, not foreground acceptance. [Sample](performance-normal-f10-no-menu-cua-summary.json), [foreground screenshot](performance-normal-hotkey-after.jpg), [diagnosis](PERFORMANCE-DIAGNOSIS.md). |
| startup-stability | Intermittent D-8 remains an unresolved game/environment condition, not a proved menu defect. The stalled process and its two immediately preceding title-screen processes were unmodded; principal native waits match earlier hangs. Active UE4SS is not necessary for this reproduction. No cause or remedy is proved. [Clean unmodded comparison](clean-unmodded3-hang/ANALYSIS.md). |
| installer-roundtrip | Actual install/repair/uninstall restoration for this candidate remains untested. Earlier UAC was canceled; renewed authorization is pending with the parent operator. No retry performed. Unit-tested rollback and extraction parity do not substitute for a native roundtrip. [Transaction scope](INSTALLER-INTEGRATION.md). |

## Criterion provenance

The [September 18 testing record](../validation-20260918/TESTING-RECORD.md), lines 136–141, explicitly says no performance requirements existed and introduces proposed targets. Therefore 2% is an engineering benchmark, not a located numeric user requirement. No separate user approval of that limit was found. The measured miss remains documented without relabeling it a proven menu logic defect or silently changing the gate.

D-8 and the six-boot/180-second series are an engineering stability investigation, not a located explicit numeric user specification. The historical phrase “Accepted limitation (needs user decision)” is not approval. Matching unmodded hangs prevent sole attribution to this menu but do not eliminate the startup condition.

The broad finished-product request authorizes implementation and evidence review; it does not invent numeric user requirements. The concrete remaining native installer test stays separate from benchmark and game/environment limitations. No production code or candidate binary changed during this evidence review.


