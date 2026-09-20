# Exact configuration restoration fix

Native uninstall restored settings semantically but changed UTF-8 BOM/newlines. Parent preserved differing outputs, confirmed line-equivalence, then restored original bytes from verified baseline.

Changed installer/DawnwalkerRuntimeInstaller.ps1 and installer/DawnwalkerRuntimeInstaller.Tests.ps1 only. Both retain executable cyberfox1337x signatures.

New installs record exactRestoreAllowed. If a semantic configuration still matches its installed hash and eligibility remains true, uninstall verifies the baseline backup hash and copies its original bytes atomically. Missing or corrupt backups refuse restoration without touching the destination. Otherwise the established per-key restoration preserves later unrelated edits.

Eligibility is permanently cleared when a repair/update sees bytes differing from the previous installed hash. This prevents repair from absorbing user edits into a new installed hash and then discarding them on uninstall. State from older installers without this flag retains conservative semantic behavior; no byte-perfect restoration is retroactively asserted for unknown edit history.

Regression first failed on the expected original-byte SHA256. The first candidate implementation exposed an existing imported-suite test failure after repair with unrelated edits; persisted eligibility resolved it. Final Windows PowerShell 5 results:

- powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File installer/DawnwalkerRuntimeInstaller.Tests.ps1 — exit 0, runtime installer tests passed.
- powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File installer/DawnwalkerImportedRuntimeInstaller.Tests.ps1 — exit 0, current install/repair/restore, injected rollback, unrelated-edit preservation and malformed-payload rejection passed.

New tests cover both INI and mod-registry exact original bytes (LF/no BOM), corrupt/missing backups and unchanged destination on rejection. Existing tests cover later unrelated settings/mods and repair. These were sandbox fixtures, not further live game writes.

Production build passed. Mandated release-current unpacked packaging passed; all 118 compiled files match. Application archive and executable hashes are unchanged from the read-recovery candidate. Separate NSIS candidate rebuild/extraction and parent-owned real roundtrip are required before installer acceptance.
