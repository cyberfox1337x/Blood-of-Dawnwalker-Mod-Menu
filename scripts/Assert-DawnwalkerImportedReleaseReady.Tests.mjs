import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { inspectImportedRelease, collectReleaseBindings, RELEASE_BINDINGS } from './Assert-DawnwalkerImportedReleaseReady.mjs';
const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function('imported_release_gate_tests');
const hash = contents => createHash('sha256').update(contents).digest('hex').toUpperCase();
test('current gate requires real, matching artifacts and every acceptance scope', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dawnwalker-current-gate-'));
  try {
    await mkdir(join(root, 'qa'));
    const bindings = { 'manifest.json': 'runtime fixture', 'installer.ps1': 'installer fixture' };
    for (const [path, contents] of Object.entries(bindings)) await writeFile(join(root, path), contents);
    await writeFile(join(root, 'qa/evidence.txt'), 'synthetic evidence; never release proof');
    const requirements = ['features', 'performance', 'lifecycle', 'startup-stability', 'installer-roundtrip'];
    const proof = { schema: 1, buildId: '25232147', executableSha256: 'CB9B7D7BD88A6754C0A9C08318AA64D5013DDFD92D5BADCAE84E1B4EA980DCFC',
      bindings: Object.fromEntries(Object.entries(bindings).map(([path, contents]) => [path, hash(contents)])),
      checks: requirements.map(id => ({ id, status: 'passed', evidence: [{ path: 'qa/evidence.txt', sha256: hash('synthetic evidence; never release proof') }] })), exceptions: [] };
    const options = { root, proof, requiredBindings: Object.keys(bindings) };
    assert.equal((await inspectImportedRelease(options)).ready, true);
    proof.checks.find(check => check.id === 'startup-stability').status = 'open';
    assert.equal((await inspectImportedRelease(options)).ready, false);
    proof.checks.find(check => check.id === 'startup-stability').status = 'passed';
    await writeFile(join(root, 'qa/evidence.txt'), 'modified');
    assert.equal((await inspectImportedRelease(options)).ready, false);
    await writeFile(join(root, 'qa/evidence.txt'), 'synthetic evidence; never release proof');
    proof.checks[0].evidence[0].path = '../outside.txt';
    assert.equal((await inspectImportedRelease(options)).ready, false);
    proof.checks[0].evidence[0].path = 'qa/evidence.txt';
    proof.buildId = '25107392';
    assert.equal((await inspectImportedRelease(options)).ready, false);
    proof.buildId = '25232147';
    proof.bindings['installer.ps1'] = '0'.repeat(64);
    assert.equal((await inspectImportedRelease(options)).ready, false);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('source/build inventory includes new code so stale acceptance cannot survive edits', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dawnwalker-current-source-'));
  try {
    for (const tree of ['src', 'electron', 'dist', 'dist-electron']) await mkdir(join(root, tree));
    await writeFile(join(root, 'src/App.tsx'), 'before');
    const initial = await collectReleaseBindings(root);
    assert.ok(initial.includes('src/App.tsx'));
    assert.ok(RELEASE_BINDINGS.every(path => initial.includes(path)));
    assert.ok(RELEASE_BINDINGS.includes('scripts/Assert-DawnwalkerImportedInstaller.mjs'));
    await writeFile(join(root, 'dist-electron/new-runtime.js'), 'new behavior');
    const changed = await collectReleaseBindings(root);
    assert.ok(changed.includes('dist-electron/new-runtime.js'));
    assert.equal(changed.length, initial.length + 1);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('installer acceptance is bound to the exact candidate hash and successful native roundtrip', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dawnwalker-installer-acceptance-'));
  try {
    const candidateSha256 = 'A'.repeat(64);
    const roundtrip = { passed: true, candidateSha256, installExitCode: 0, reinstallExitCode: 0,
      uninstallerLauncherExitCode: 0, managedFilesPreserved: 82, remainingUninstallerWorkerPids: [] };
    await writeFile(join(root, 'roundtrip.json'), JSON.stringify(roundtrip));
    const artifact = { path: 'roundtrip.json', sha256: hash(JSON.stringify(roundtrip)) };
    const proof = { schema: 1, buildId: '25232147', executableSha256: 'CB9B7D7BD88A6754C0A9C08318AA64D5013DDFD92D5BADCAE84E1B4EA980DCFC', bindings: {}, exceptions: [],
      checks: ['features', 'performance', 'lifecycle', 'startup-stability', 'installer-roundtrip'].map(id => ({ id, status: 'passed', evidence: [artifact] })) };
    assert.equal((await inspectImportedRelease({ root, proof, requiredBindings: [], installerSha256: candidateSha256 })).ready, true);
    assert.equal((await inspectImportedRelease({ root, proof, requiredBindings: [], installerSha256: 'B'.repeat(64) })).ready, false);
    roundtrip.reinstallExitCode = 1;
    await writeFile(join(root, 'roundtrip.json'), JSON.stringify(roundtrip));
    artifact.sha256 = hash(JSON.stringify(roundtrip));
    assert.equal((await inspectImportedRelease({ root, proof, requiredBindings: [], installerSha256: candidateSha256 })).ready, false);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('qualified acceptance is limited to reviewed performance, startup, and installer conditions', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dawnwalker-qualified-gate-'));
  try {
    const contents = 'fixture review: disclosed condition remains unresolved';
    await writeFile(join(root, 'review.txt'), contents);
    const artifact = { path: 'review.txt', sha256: hash(contents) };
    const proof = { schema: 1, buildId: '25232147', executableSha256: 'CB9B7D7BD88A6754C0A9C08318AA64D5013DDFD92D5BADCAE84E1B4EA980DCFC', bindings: {}, exceptions: [],
      checks: ['features', 'performance', 'lifecycle', 'startup-stability', 'installer-roundtrip'].map(id => ({ id, status: 'passed', evidence: [artifact] })) };
    const options = { root, proof, requiredBindings: [] };
    for (const id of ['performance', 'startup-stability', 'installer-roundtrip']) {
      const check = proof.checks.find(entry => entry.id === id);
      check.status = 'accepted-with-limitations';
      check.review = { decision: 'release-with-disclosed-limitations', rationale: 'Documented condition is not a solved defect or a passed benchmark.', artifact };
    }
    assert.equal((await inspectImportedRelease(options)).ready, true);
    for (const id of ['features', 'lifecycle']) {
      const check = proof.checks.find(entry => entry.id === id);
      check.status = 'accepted-with-limitations';
      check.review = proof.checks[1].review;
      assert.equal((await inspectImportedRelease(options)).ready, false, id);
      check.status = 'passed';
    }
    const performance = proof.checks[1];
    const review = performance.review;
    for (const invalid of [undefined, { ...review, rationale: ' ' }, { ...review, decision: 'fixed' }, { ...review, artifact: { ...artifact, sha256: '0'.repeat(64) } }, { ...review, artifact: { ...artifact, path: '../review.txt' } }]) {
      performance.review = invalid;
      assert.equal((await inspectImportedRelease(options)).ready, false);
    }
    performance.review = review;
    performance.evidence = [];
    assert.equal((await inspectImportedRelease(options)).ready, false);
    performance.evidence = [artifact];
    await writeFile(join(root, 'review.txt'), 'changed review');
    assert.equal((await inspectImportedRelease(options)).ready, false);
  } finally { await rm(root, { recursive: true, force: true }); }
});
