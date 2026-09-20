import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import configuration from './current-build.mjs';

const cyberfox1337x = Object.freeze({ function: name => void name });
cyberfox1337x.function('dawnwalker_installer_policy_tests');

test('current installer uses the supported assisted UI without the optional one-click banner', () => {
  assert.equal(configuration.nsis.oneClick, false);
  assert.equal(configuration.nsis.perMachine, true);
});

test('every runtime action retains explicit signed-download policy and failure handling', () => {
  const source = readFileSync(new URL('./current-installer.nsh', import.meta.url), 'utf8');
  const commands = source.split(/\r?\n/).filter(line => line.includes('nsExec::ExecToStack'));
  assert.equal(commands.length, 3);
  for (const command of commands) {
    assert.match(command, /-ExecutionPolicy RemoteSigned -File/);
    assert.doesNotMatch(command, /Bypass|EncodedCommand|Unrestricted/);
  }
  for (const action of ['Preflight', 'Install', 'Uninstall']) {
    assert.equal(commands.filter(command => command.includes(`-Action ${action} `)).length, 1);
  }
  assert.equal((source.match(/\$\{If\} \$0 != 0/g) ?? []).length, 3);
  assert.equal((source.match(/^\s*Abort$/gm) ?? []).length, 3);
  assert.match(source, /\$\{IfNot\} \$\{isUpdated\}/);
});
