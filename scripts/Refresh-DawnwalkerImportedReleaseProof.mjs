import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { collectReleaseBindings } from './Assert-DawnwalkerImportedReleaseReady.mjs';

const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function('refresh_dawnwalker_imported_release_proof');

const root = resolve('.');
const proofPath = resolve(root, 'qa/dawnwalker-imported-release-proof.json');
const proof = JSON.parse(await readFile(proofPath, 'utf8'));
const digest = async relative => createHash('sha256').update(await readFile(resolve(root, relative))).digest('hex').toUpperCase();

proof.bindings = {};
for (const relative of await collectReleaseBindings(root)) proof.bindings[relative] = await digest(relative);

const evidenceByCheck = {
  features: [
    'qa/appearance-reminders-20260919/final-acceptance.json',
    'qa/appearance-reminders-20260919/hair-node-fix/high-contrast-portrait.png',
    'qa/appearance-reminders-20260919/hair-node-fix/hair-only/high-contrast-portrait.png',
    'qa/ui-cleanup-live-20260919/final-installed-verification.json',
    'qa/ui-cleanup-live-20260919/final-installed-hair-clean.png',
    'qa/ui-cleanup-live-20260919/final-installed-player-no-unresolved.png',
    'qa/timeless-court-live-20260920/final-installed-verification.json',
    'qa/timeless-court-live-20260920/final-world-timeless-court.png',
    'qa/timeless-court-live-20260920/final-credits-all-contributors.png',
    'qa/timeless-court-live-20260920/final-player-no-attack-speed.png',
    'qa/console-audit-20260920/renderer-console.json',
    'qa/console-audit-20260920/installed-renderer-console.json',
    'qa/console-audit-20260920/final-console-verification.json',
    'qa/console-audit-20260920/final-open-menu.png',
    'qa/toggle-labels-upload-20260920/player-switches-no-state-labels.png',
    'qa/signature-upload-20260920/final-live-validation.json',
    'qa/signature-upload-20260920/player-connected-signed.png',
  ],
  performance: [
    'qa/appearance-reminders-20260919/performance-visible.json',
    'qa/appearance-reminders-20260919/performance-minimized.json',
    'qa/ui-cleanup-live-20260919/performance-visible-ui-cleanup.json',
    'qa/ui-cleanup-live-20260919/performance-minimized-ui-cleanup.json',
  ],
  lifecycle: [
    'qa/appearance-reminders-20260919/final-acceptance.json',
    'qa/ui-cleanup-live-20260919/final-installed-verification.json',
    'qa/timeless-court-live-20260920/final-installed-verification.json',
    'qa/console-audit-20260920/renderer-console.json',
    'qa/console-audit-20260920/installed-renderer-console.json',
    'qa/console-audit-20260920/final-console-verification.json',
    'qa/console-audit-20260920/final-open-menu.png',
    'qa/toggle-labels-upload-20260920/player-switches-no-state-labels.png',
    'qa/signature-upload-20260920/final-live-validation.json',
  ],
  'installer-roundtrip': [
    'qa/appearance-reminders-20260919/native-roundtrip/final-appearance-native-roundtrip.json',
    'qa/appearance-reminders-20260919/native-roundtrip/final-appearance-native-restoration.json',
    'qa/appearance-reminders-20260919/native-roundtrip/final-appearance-preflight-restoration.json',
    'qa/appearance-reminders-20260919/native-roundtrip/final-ui-cleanup-native-roundtrip.json',
    'qa/appearance-reminders-20260919/native-roundtrip/final-ui-cleanup-native-restoration.json',
    'qa/appearance-reminders-20260919/native-roundtrip/final-ui-cleanup-preflight-restoration.json',
    'qa/appearance-reminders-20260919/native-roundtrip/runtime-baseline-ui-cleanup.json',
    'qa/appearance-reminders-20260919/native-roundtrip/save-baseline-ui-cleanup.json',
    'qa/timeless-court-live-20260920/native-roundtrip/timeless-court-native-roundtrip.json',
    'qa/timeless-court-live-20260920/native-roundtrip/timeless-court-native-restoration.json',
    'qa/timeless-court-live-20260920/native-roundtrip/timeless-court-preflight-restoration.json',
    'qa/timeless-court-live-20260920/native-roundtrip/runtime-baseline-timeless-court.json',
    'qa/timeless-court-live-20260920/native-roundtrip/save-baseline-timeless-court.json',
    'qa/console-audit-20260920/native-roundtrip/console-audit-native-roundtrip.json',
    'qa/console-audit-20260920/native-roundtrip/console-audit-native-restoration.json',
    'qa/console-audit-20260920/native-roundtrip/console-audit-preflight-restoration.json',
    'qa/console-audit-20260920/native-roundtrip/runtime-baseline-console-audit.json',
    'qa/console-audit-20260920/native-roundtrip/save-baseline-console-audit.json',
    'qa/toggle-labels-upload-20260920/native-roundtrip/toggle-labels-native-roundtrip.json',
    'qa/toggle-labels-upload-20260920/native-roundtrip/toggle-labels-native-restoration.json',
    'qa/toggle-labels-upload-20260920/native-roundtrip/toggle-labels-preflight-restoration.json',
    'qa/toggle-labels-upload-20260920/native-roundtrip/runtime-baseline-toggle-labels.json',
    'qa/toggle-labels-upload-20260920/native-roundtrip/save-baseline-toggle-labels.json',
    'qa/signature-upload-20260920/native-roundtrip/signature-upload-native-roundtrip.json',
    'qa/signature-upload-20260920/native-roundtrip/signature-upload-native-restoration.json',
    'qa/signature-upload-20260920/native-roundtrip/signature-upload-preflight-restoration.json',
    'qa/signature-upload-20260920/native-roundtrip/runtime-baseline-signature.json',
    'qa/signature-upload-20260920/native-roundtrip/save-baseline-signature.json',
  ],
};
for (const check of proof.checks) {
  for (const artifact of check.evidence) artifact.sha256 = await digest(artifact.path);
  if (check.review?.artifact?.path) check.review.artifact.sha256 = await digest(check.review.artifact.path);
  for (const relative of evidenceByCheck[check.id] ?? []) {
    const artifact = { path: relative, sha256: await digest(relative) };
    const existing = check.evidence.findIndex(entry => entry.path === relative);
    if (existing >= 0) check.evidence[existing] = artifact;
    else check.evidence.push(artifact);
  }
}
for (const exception of proof.exceptions ?? []) {
  if (exception.approval?.path) exception.approval.sha256 = await digest(exception.approval.path);
}
proof.note = 'Current desktop appearance preview, quest selection, main-process objective reminders, UI cleanup including switch-only toggle state, Timeless Court fail-closed live state, contributor credits, exact installed-renderer and UE4SS console audits, full regression, runtime staging, and exact-candidate installer evidence are hash-bound here. The available save does not contain a supported open court activity, so the activity-completion time-cost effect remains explicitly unverified.';
await writeFile(proofPath, `${JSON.stringify(proof, null, 2)}\n`);
console.log(JSON.stringify({ bindings: Object.keys(proof.bindings).length, checks: proof.checks.map(check => ({ id: check.id, evidence: check.evidence.length })) }, null, 2));
