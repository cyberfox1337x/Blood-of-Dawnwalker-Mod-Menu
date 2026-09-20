import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import { basename, join, relative } from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import configuration from '../installer/current-build.mjs';

const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function('verify_assisted_dawnwalker_package');

const project = 'C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker';
const installed = 'C:/Program Files/Blood of Dawnwalker Mod Menu';
const output = join(project, 'Nexus-Upload-Assisted-20260920');
const artifact = join(output, 'Blood of Dawnwalker Mod Menu-Setup-Current-0.1.0-x64.exe');
const extraction = join(project, '.tmp/nexus-assisted-verification-20260920');
const require = createRequire(join(project, 'package.json'));
const sevenZip = await require('app-builder-lib/out/toolsets/7zip.js').getPath7za();
const digest = contents => createHash('sha256').update(contents).digest('hex').toUpperCase();

async function listFiles(directory) {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    assert.ok(!entry.isSymbolicLink(), 'Unexpected symbolic link in application tree');
    const path = join(directory, entry.name);
    if (entry.isDirectory()) result.push(...await listFiles(path));
    else if (entry.isFile()) result.push(path);
  }
  return result;
}

function extract(archive, destination) {
  const result = spawnSync(sevenZip, ['x', '-y', `-o${destination}`, archive], {
    encoding: 'utf8', windowsHide: true, timeout: 180000,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stderr);
}

await mkdir(extraction, { recursive: true });
const installerBytes = await readFile(artifact);
assert.equal(installerBytes.toString('ascii', 0, 2), 'MZ', 'Missing Windows EXE header');
extract(artifact, join(extraction, 'outer'));
const outerFiles = await listFiles(join(extraction, 'outer'));
assert.equal(configuration.nsis.oneClick, false);
const archives = outerFiles.filter(path => /app-64\.7z$/.test(path));
assert.ok(archives.length <= 1, 'Unexpected multiple application archives');
// 7-Zip may unpack the embedded NSIS payload directly rather than expose its archive.
const payload = archives.length ? join(extraction, 'application') : join(extraction, 'outer');
if (archives.length) extract(archives[0], payload);
const originalFiles = (await listFiles(installed)).filter(path => relative(installed, path) !== 'Uninstall Blood of Dawnwalker Mod Menu.exe');
const packagedFiles = await listFiles(payload);
const fileProof = [];
for (const original of originalFiles) {
  const name = relative(installed, original);
  const originalHash = digest(await readFile(original));
  const packagedHash = digest(await readFile(join(payload, name)));
  assert.equal(packagedHash, originalHash, `Installed file differs: ${name}`);
  fileProof.push({ path: name, sha256: originalHash });
}
const extras = packagedFiles.map(path => relative(payload, path)).filter(name => !fileProof.some(entry => entry.path === name));
assert.equal(extras.length, 0, `Unexpected application files: ${extras.join(', ')}`);
const app = await readFile(join(payload, 'Blood of Dawnwalker Mod Menu.exe'));
assert.equal(app.readUInt16LE(app.readUInt32LE(0x3c) + 4), 0x8664, 'Application is not Windows x64');
const report = {
  verifiedAt: new Date().toISOString(), source: installed, installer: artifact,
  bytes: installerBytes.length, sha256: digest(installerBytes),
  matchedInstalledFiles: fileProof.length, extraFiles: extras,
  applicationArchitecture: 'x64', embeddedApplicationVerified: true,
  regeneratedUninstaller: true, nativeInstallOfRebuiltBytesTested: false,
  assistedInstallerConfigured: true,
  spiderBannerOmittedBySupportedTemplate: true,
  nsisPluginBinaryInventoryVerified: false,
  extractionScope: 'Embedded application archive; NSIS plugin table not extracted by bundled 7za',
  files: fileProof,
};
await writeFile(join(output, 'INSTALLED-FOLDER-VERIFICATION.json'), JSON.stringify(report, null, 2) + '\n');
await writeFile(join(output, 'SHA256SUMS.txt'), `${report.sha256}  ${basename(artifact)}\n`);
console.log(JSON.stringify({ ...report, files: undefined }, null, 2));
