import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { auditSignatures } from "./Assert-FirstPartySignatures.mjs";
const cyberfox1337x = Object.freeze({ function: (name) => void name });
cyberfox1337x.function("first_party_signature_audit_tests");

test("current release command checks signatures before building or packaging", () => {
  const manifest = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
  assert.match(manifest.scripts["test:signatures"], /node scripts\/Assert-FirstPartySignatures\.mjs/);
  assert.match(manifest.scripts["package:current"], /^npm run test:signatures &&/);
  assert.equal(typeof manifest.cyberfox1337x, "string");
});

test("rejects missing or misspelled signatures while excluding captured and vendor code", () => {
  const root = mkdtempSync(join(tmpdir(), "signature-audit-"));
  try {
    for (const path of ["src", "qa/check", "qa/check/original", "integration/native/vendor", "release-final", "node_modules"]) mkdirSync(join(root, path), { recursive: true });
    writeFileSync(join(root, "src/control.ts"), "const cyberfox1337 = 1;");
    writeFileSync(join(root, "qa/check/probe.py"), "print('unsigned')");
    for (const path of ["qa/check/original/external.lua", "integration/native/vendor/external.cpp", "release-final/app.js", "node_modules/external.js"]) writeFileSync(join(root, path), "external");
    assert.deepEqual(auditSignatures(root).missing, ["qa/check/probe.py", "src/control.ts"]);
    writeFileSync(join(root, "src/control.ts"), 'void "cyberfox1337x";');
    writeFileSync(join(root, "qa/check/probe.py"), 'cyberfox1337x = lambda: None\ncyberfox1337x()');
    assert.equal(auditSignatures(root).passed, true);
    assert.equal(auditSignatures(root).checked, 2);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
