import { readFile, realpath, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, resolve, sep, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function('dawnwalker_imported_release_gate');
export const RELEASE_CHECKS = Object.freeze(['features', 'performance', 'lifecycle', 'startup-stability', 'installer-roundtrip']);
export const RELEASE_BINDINGS = Object.freeze([
  'integration/imported-menu/manifest.json', 'integration/imported-menu/official-build.json',
  'installer/current-runtime/payload-manifest.json', 'installer/DawnwalkerImportedRuntimeInstaller.ps1',
  'installer/DawnwalkerRuntimeInstaller.ps1', 'package.json', 'installer/current-installer.nsh', 'installer/current-build.mjs',
  'scripts/Assert-DawnwalkerImportedReleaseReady.mjs', 'scripts/Assert-DawnwalkerImportedInstaller.mjs',
]);
const acceptedExceptions = new Set(['shrine-world-effect', 'permanent-blood-damage-repair', 'photo-camera']);
const qualifiedChecks = new Set(['performance', 'startup-stability', 'installer-roundtrip']);
async function resolveInside(root, relativePath) {
  if (typeof relativePath !== 'string' || isAbsolute(relativePath) || relativePath.split(/[\\/]/).some(part => !part || part === '..' || part === '.' || part.includes(':'))) throw new Error('Evidence path must stay inside the repository.');
  const rootPath = await realpath(root);
  const path = await realpath(resolve(rootPath, relativePath));
  if (!path.toLowerCase().startsWith((rootPath + sep).toLowerCase())) throw new Error('Evidence symlink leaves the repository.');
  return path;
}
async function digestInside(root, relativePath) {
  return createHash('sha256').update(await readFile(await resolveInside(root, relativePath))).digest('hex').toUpperCase();
}
export async function collectReleaseBindings(root) {
  const paths = [...RELEASE_BINDINGS, 'vite.config.ts', 'tsconfig.app.json', 'electron/tsconfig.json'];
  const visit = async relative => {
    for (const entry of await readdir(resolve(root, relative), { withFileTypes: true })) {
      if (entry.isSymbolicLink()) throw new Error('Release source/build tree contains a symlink.');
      const path = `${relative}/${entry.name}`;
      if (entry.isDirectory()) await visit(path);
      else if (entry.isFile()) paths.push(path);
    }
  };
  for (const tree of ['src', 'electron', 'dist', 'dist-electron']) await visit(tree);
  return [...new Set(paths)].sort();
}
export async function inspectImportedRelease({ root, proof, requiredBindings, installerSha256 }) {
  const blockers = [];
  if (proof?.schema !== 1 || proof.buildId !== '25232147' || proof.executableSha256 !== 'CB9B7D7BD88A6754C0A9C08318AA64D5013DDFD92D5BADCAE84E1B4EA980DCFC') {
    return { ready: false, blockers: ['Current live acceptance proof is absent or targets a different game build.'] };
  }
  const validateArtifact = async (path, sha256, label) => {
    try {
      if (typeof sha256 !== 'string' || !/^[A-Fa-f0-9]{64}$/.test(sha256) || await digestInside(root, path) !== sha256.toUpperCase()) blockers.push(`${label}: artifact hash mismatch.`);
    } catch (error) { blockers.push(`${label}: ${error.message}`); }
  };
  let bindings;
  try { bindings = requiredBindings ?? await collectReleaseBindings(root); }
  catch (error) { return { ready: false, blockers: [`Source/build inventory failed: ${error.message}`] }; }
  for (const path of bindings) await validateArtifact(path, proof.bindings?.[path], path);
  const checks = Array.isArray(proof.checks) ? proof.checks : [];
  if (checks.some(check => !RELEASE_CHECKS.includes(check?.id))) blockers.push('Unknown release check.');
  for (const id of RELEASE_CHECKS) {
    const matching = checks.filter(check => check?.id === id);
    if (matching.length !== 1) { blockers.push(`${id}: a unique acceptance record is required.`); continue; }
    const check = matching[0];
    if (check.status === 'accepted-with-limitations' && qualifiedChecks.has(id)) {
      const review = check.review;
      if (review?.decision !== 'release-with-disclosed-limitations' || typeof review.rationale !== 'string' || !review.rationale.trim()) {
        blockers.push(`${id}: an explicit qualified release decision and rationale are required.`);
      } else {
        await validateArtifact(review.artifact?.path, review.artifact?.sha256, `${id} release review`);
      }
    } else if (check.status !== 'passed') {
      blockers.push(`${id}: a passed acceptance record${qualifiedChecks.has(id) ? ' or reviewed disclosed limitation' : ''} is required.`);
      continue;
    }
    const evidence = check.evidence;
    if (!Array.isArray(evidence) || evidence.length === 0) { blockers.push(`${id}: evidence is missing.`); continue; }
    for (const artifact of evidence) await validateArtifact(artifact?.path, artifact?.sha256, id);
    if (id === 'installer-roundtrip' && installerSha256) {
      let exactRoundtrip = false;
      for (const artifact of evidence) {
        try {
          const record = JSON.parse(await readFile(await resolveInside(root, artifact.path), 'utf8'));
          exactRoundtrip ||= record?.passed === true && record?.candidateSha256?.toUpperCase() === installerSha256.toUpperCase()
            && record?.installExitCode === 0 && record?.reinstallExitCode === 0 && record?.uninstallerLauncherExitCode === 0
            && Number.isInteger(record?.managedFilesPreserved) && record.managedFilesPreserved > 0
            && Array.isArray(record?.remainingUninstallerWorkerPids) && record.remainingUninstallerWorkerPids.length === 0;
        } catch { /* Non-JSON evidence cannot establish an exact native roundtrip. */ }
      }
      if (!exactRoundtrip) blockers.push('installer-roundtrip: exact candidate install, reinstall, and uninstall evidence is required.');
    }
  }
  if (!Array.isArray(proof.exceptions)) blockers.push('Explicit accepted-exception list is required (empty when none).');
  else {
    const seen = new Set();
    for (const exception of proof.exceptions) {
      if (!acceptedExceptions.has(exception?.id) || seen.has(exception.id)) { blockers.push('Unapproved or duplicate release exception.'); continue; }
      seen.add(exception.id);
      await validateArtifact(exception.approval?.path, exception.approval?.sha256, `User approval for ${exception.id}`);
    }
  }
  return { ready: blockers.length === 0, buildId: proof.buildId, blockers };
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const proofPath = resolve(root, 'qa/dawnwalker-imported-release-proof.json');
  let proof;
  try { proof = JSON.parse(await readFile(proofPath, 'utf8')); }
  catch (error) {
    console.error(`Current release proof cannot be read: ${error.message}`);
    process.exitCode = 1;
  }
  if (proof) {
    const result = await inspectImportedRelease({ root, proof });
    console.log(JSON.stringify(result, null, 2));
    if (!result.ready) process.exitCode = 1;
  }
}
