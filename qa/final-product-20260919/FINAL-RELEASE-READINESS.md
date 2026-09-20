# Final release readiness — September 19, 2026

The exact native-tested installer has been promoted to `release-final/Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe` without rebuilding. Size: 202,926,271 bytes. SHA256: `980F746F4A634D36B56A828DEC0C82E8729559F7821F40B357EC08F79196B146`. Unsigned.

`npm run verify:release:current` exits 0 with ready=true and no blockers. Features/lifecycle/installer roundtrip passed; performance/startup are explicitly accepted with disclosed limitations. The proposed CPU benchmark was not met and the startup condition is not fixed. Three historical feature-effect exceptions remain unchanged. [Gate output](final-release-gate.log), [qualified decision](QUALIFIED-RELEASE-REVIEW.md).

Native install and reinstall exited 0; 77 original ownership records were preserved. The observed uninstall worker exited and none remained. All 4,081 runtime files and 50 saves match original hashes/counts, with no remaining app, registry registration or managed state. [Native roundtrip](byte-restore-native-roundtrip.json), [exact restoration](byte-restore-native-restoration.json), [elevated runner](single-prompt-runner.json).

Independent extraction from the final copied EXE verified 82 runtime resources, 118 compiled desktop files and 74 imported payload files. Its app.asar remains the tested hash. [Final extraction](final-installer-verification.json). The extractor's liveAcceptanceVerified=false field deliberately describes that tool's extraction-only scope; separate native evidence above establishes actual roundtrip acceptance for these exact EXE bytes.

The final directory includes release-manifest.json, SHA256SUMS.txt and retained third-party notices. Notice hashes and all final checksums were verified. No new production build was performed after native verification. Nexus page/media preparation remains separate; the artifact has not been publicly uploaded or approved by host scanning.
