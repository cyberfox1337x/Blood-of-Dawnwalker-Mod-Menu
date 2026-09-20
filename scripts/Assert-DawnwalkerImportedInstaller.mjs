import { createRequire } from 'node:module';
import { mkdtemp, readFile, readdir, rm, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { join, resolve, sep } from 'node:path';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';
import { inspectImportedRelease } from './Assert-DawnwalkerImportedReleaseReady.mjs';
const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function('dawnwalker_imported_installer_verification');
const require = createRequire(import.meta.url);
const asar = require('@electron/asar');
const sevenZip = await require('app-builder-lib/out/toolsets/7zip.js').getPath7za();
const root = resolve('.');
const directory = resolve(process.argv[2] ?? 'release-final');
const packageManifest = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
const artifact = join(directory, `${packageManifest.build.productName}-Setup-Current-${packageManifest.version}-x64.exe`);
const hash = contents => createHash('sha256').update(contents).digest('hex').toUpperCase();
const temporaryRoot = await mkdtemp(join(tmpdir(), 'dawnwalker-imported-package-'));
async function files(path) {
  const entries = await readdir(path, { withFileTypes: true });
  const collected = [];
  for (const entry of entries) {
    if (entry.isSymbolicLink()) throw new Error('Package inventory must not contain symlinks.');
    const child = join(path, entry.name);
    if (entry.isDirectory()) collected.push(...await files(child));
    else if (entry.isFile()) collected.push(child);
  }
  return collected;
}
function extract(archive, destination) {
  const result = spawnSync(sevenZip, ['x', '-y', `-o${destination}`, archive], { windowsHide: true, encoding: 'utf8', timeout: 120000 });
  if (result.error || result.status !== 0) throw new Error(`Package extraction failed: ${result.error?.message ?? result.stderr}`);
}
try {
  assert.ok((await stat(artifact)).size > 1048576, 'Installer is missing or too small.');
  const outer = join(temporaryRoot, 'outer');
  extract(artifact, outer);
  const archives = (await files(outer)).filter(path => /app-.*\.7z$/.test(path));
  let application = outer;
  if (archives.length) {
    assert.equal(archives.length, 1, 'Expected one embedded application archive.');
    assert.ok(archives[0].endsWith('app-64.7z'), 'Expected x64 application archive.');
    application = join(temporaryRoot, 'application');
    extract(archives[0], application);
  }
  const executable = await readFile(join(application, 'Blood of Dawnwalker Mod Menu.exe'));
  assert.equal(executable.readUInt16LE(executable.readUInt32LE(0x3c) + 4), 0x8664, 'Expected x64 packaged application.');
  const resources = join(application, 'resources');
  const runtime = join(resources, 'current-runtime');
  const expectedFiles = await files(join(root, 'installer/current-runtime'));
  for (const source of expectedFiles) {
    const relative = source.slice(join(root, 'installer/current-runtime').length + 1);
    assert.deepEqual(await readFile(join(runtime, relative)), await readFile(source), `Current runtime mismatch: ${relative}`);
  }
  for (const name of ['DawnwalkerImportedRuntimeInstaller.ps1', 'DawnwalkerRuntimeInstaller.ps1']) {
    assert.deepEqual(await readFile(join(runtime, name)), await readFile(join(root, 'installer', name)), name);
  }
  const stagedManifest = JSON.parse(await readFile(join(runtime, 'payload-manifest.json'), 'utf8').then(text => text.replace(/^\uFEFF/, '')));
  const importedManifest = JSON.parse(await readFile(join(resources, 'imported-menu/manifest.json'), 'utf8'));
  assert.equal(stagedManifest.steamBuildId, importedManifest.buildId, 'Installer and desktop target different builds.');
  for (const entry of importedManifest.files) {
    assert.equal(hash(await readFile(join(resources, 'imported-menu/Mods/DawnwalkerImportedMenu', entry.path))), entry.sha256, entry.path);
  }
  assert.deepEqual((await files(join(resources, 'dawnwalker-runtime'))).map(path => path.slice(join(resources, 'dawnwalker-runtime').length + 1)), ['official-build.json'], 'Legacy payload must not ship in the current installer.');
  const archive = join(resources, 'app.asar');
  const packagedMetadata = JSON.parse(asar.extractFile(archive, 'package.json').toString('utf8'));
  for (const field of ['name', 'version', 'main', 'cyberfox1337x']) assert.equal(packagedMetadata[field], packageManifest[field], `Packaged metadata differs: ${field}`);
  const builds = [...await files(join(root, 'dist')), ...(await files(join(root, 'dist-electron'))).filter(path => path.endsWith('.js'))];
  for (const source of builds) assert.deepEqual(asar.extractFile(archive, source.slice(root.length + 1)), await readFile(source), source);
  const signatureCommand = `Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security') -ErrorAction Stop; (Get-AuthenticodeSignature -LiteralPath '${artifact.replaceAll("'", "''")}').Status`;
  const signature = spawnSync('powershell.exe', ['-NoProfile', '-EncodedCommand', Buffer.from(signatureCommand, 'utf16le').toString('base64')], { windowsHide: true, encoding: 'utf8', timeout: 30000 });
  const installerSha256 = hash(await readFile(artifact));
  const proof = JSON.parse(await readFile(join(root, 'qa/dawnwalker-imported-release-proof.json'), 'utf8'));
  const release = await inspectImportedRelease({ root, proof });
  const exactNativeRoundtrip = await inspectImportedRelease({ root, proof, installerSha256 });
  console.log(JSON.stringify({ installerPath: artifact, installerSha256, buildId: importedManifest.buildId,
    currentRuntimeFiles: expectedFiles.length + 2, desktopFiles: builds.length, importedFiles: importedManifest.files.length,
    signatureStatus: signature.status === 0 ? signature.stdout.trim() : 'Unavailable', payloadVerified: true,
    liveAcceptanceVerified: release.ready, exactCandidateNativeRoundtripVerified: exactNativeRoundtrip.ready,
    acceptanceBlockers: release.blockers, exactCandidateNativeRoundtripBlockers: exactNativeRoundtrip.blockers }, null, 2));
  assert.equal(release.ready, true, `Release acceptance failed: ${release.blockers.join(' ')}`);
} finally {
  if (!resolve(temporaryRoot).startsWith(resolve(tmpdir()) + sep)) throw new Error('Unsafe extraction cleanup path.');
  await rm(temporaryRoot, { recursive: true, force: true });
}
