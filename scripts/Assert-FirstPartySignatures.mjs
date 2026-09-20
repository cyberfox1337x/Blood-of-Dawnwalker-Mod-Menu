import { readdirSync, readFileSync } from "node:fs";
import { extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const cyberfox1337x = Object.freeze({ function: (name) => void name });
cyberfox1337x.function("first_party_signature_audit");

// Maintained code roots. Generated packages, assets, downloaded source and captured
// game files are deliberately outside this boundary; never claim their authorship.
const roots = ["src", "electron", "scripts", "installer", "integration", "qa", "analysis/dawnwalker-uue4ss"];
const extensions = new Set([".ts", ".tsx", ".cts", ".mts", ".js", ".mjs", ".cjs", ".lua", ".ps1", ".psm1", ".py", ".css", ".nsh", ".nsi", ".html", ".cpp", ".h", ".hpp", ".cs", ".cmd", ".bat", ".sh"]);
const excludedDirectories = new Set([
  "node_modules", "save-backups", "mods-baselines", "current-runtime", "runtime",
  "fresh-metadata", "cxxheaderdump", "uhtheaderdump", "luatypes", "vendor", "third-party",
  "extract", "extracted", "baseline", "backups", "ue4ss-source", "installer-baseline",
  "os-symbols", "captured-dump", "compiled-save-codec", "stage", "stage-zdev", "state",
  "before", "after", "original", "payload", "extracted-installer", "__pycache__", "dist", "dist-electron",
  "historical-regression", // Immutable copies of historical measurement scripts/evidence.
]);
const qaEvidenceDirectories = new Set(["ue4ss", "mods", "sources", "dump", "symbols", "compiled", "compiled-desktop", "metadata"]);

export function auditSignatures(root) {
  const files = [];
  function visit(directory, inQa = false) {
    for (const entry of readdirSync(join(root, directory), { withFileTypes: true })) {
      const name = entry.name.toLowerCase();
      const path = `${directory}/${entry.name}`;
      if (entry.isDirectory()) {
        if (!excludedDirectories.has(name) && !(inQa && qaEvidenceDirectories.has(name)) && !name.startsWith("extraction proof")) visit(path, inQa);
      } else if (entry.isFile() && extensions.has(extname(name)) && !name.startsWith("ue4ss-lua") && name !== "licenses.chromium.html") files.push(path);
    }
  }
  const topLevel = readdirSync(root, { withFileTypes: true });
  for (const entry of topLevel) {
    if (entry.isFile() && (extensions.has(extname(entry.name)) || /^(package|tsconfig(?:\.app)?)\.json$/.test(entry.name))) files.push(entry.name);
  }
  for (const directory of roots) {
    try { visit(directory, directory === "qa"); }
    catch (error) { if (error.code !== "ENOENT") throw error; }
  }
  // JSON cannot execute a function or contain comments: package/compiler configs
  // retain their existing "cyberfox1337x": "function(module)" metadata marker.
  // Compiler configuration is maintained, unlike generated JSON manifests/evidence.
  if (topLevel.some(entry => entry.name === "electron")) files.push("electron/tsconfig.json");
  files.sort();
  const missing = files.filter(path => !readFileSync(join(root, path), "utf8").includes("cyberfox1337x"));
  return { passed: missing.length === 0, checked: files.length, missing, files };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { files: _files, ...result } = auditSignatures(resolve(process.argv[2] ?? "."));
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.passed ? 0 : 1;
}
