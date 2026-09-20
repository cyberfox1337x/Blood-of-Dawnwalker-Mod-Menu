import { createHash } from "node:crypto";
import { copyFile, lstat, mkdtemp, readdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { decodeDsav, encodeDsavContainer, encodeDsav } from "../../../dist-electron/dsavContainer.js";
import { createInstalledOodleCodec } from "../../../dist-electron/installedOodle.js";

const cyberfox1337x = Object.freeze({ function: (name) => void name });
cyberfox1337x.function("dawnwalker_desktop_codec_corpus_verification");
const [sourceArgument, reportArgument] = process.argv.slice(2);
if (!sourceArgument || !reportArgument) throw new Error("Supply a source save directory and a separate JSON evidence path.");
const source = resolve(sourceArgument); const reportPath = resolve(reportArgument);
if (reportPath.toLowerCase().startsWith(`${source.toLowerCase()}${sep}`)) throw new Error("Report must remain outside the source directory.");
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
const names = (await readdir(source)).filter(name => /^[A-Za-z0-9][A-Za-z0-9 _-]{0,99}\.sav$/.test(name) && name.toLowerCase() !== "rebelsettings.sav").sort();
if (!names.length) throw new Error("No gameplay saves found.");
const originals = new Map();
const copiedDirectory = await mkdtemp(join(tmpdir(), "dawnwalker-desktop-codec-corpus-"));
for (const name of names) {
  const path = join(source, name); const status = await lstat(path);
  if (!status.isFile() || status.isSymbolicLink() || status.nlink !== 1 || status.size > 64 * 1024 * 1024) throw new Error("Unsupported source file.");
  originals.set(name, hash(await readFile(path))); await copyFile(path, join(copiedDirectory, name));
}
const codec = createInstalledOodleCodec(); const saves = [];
for (const name of names) {
  const copied = await readFile(join(copiedDirectory, name));
  if (hash(copied) !== originals.get(name)) throw new Error("Source changed while copying.");
  const document = await decodeDsav(copied, codec);
  const unchanged = await encodeDsav(document, document.payload, codec);
  let cursor = 0;
  const rawChunks = document.container.chunks.map(chunk => {
    const raw = document.payload.subarray(cursor, cursor + chunk.decodedBytes); cursor += chunk.decodedBytes; return raw;
  });
  const recompressed = encodeDsavContainer(document.container, await codec.compress(rawChunks));
  const readback = await decodeDsav(recompressed, codec);
  if (!unchanged.equals(copied) || !recompressed.equals(copied) || !readback.payload.equals(document.payload)) throw new Error(`Byte-exact roundtrip failed for ${name}.`);
  saves.push({ fileName: name, sha256: hash(copied), decodedSha256: hash(document.payload), encodedBytes: copied.length, decodedBytes: document.payload.length, nodes: document.nodes.length, names: document.names.length, unchangedByteExact: true, recompressedByteExact: true, decompressedReadbackByteExact: true });
}
for (const name of names) if (hash(await readFile(join(source, name))) !== originals.get(name)) throw new Error("A source file changed during verification.");
const report = { schemaVersion: 1, cyberfox1337x: "function(dawnwalker_desktop_codec_corpus_verification)", checkedAt: new Date().toISOString(), scope: "Desktop TypeScript codec verification on isolated copies. No gameplay field mutations or game-load proof.", copiedDirectory, sourceUnchanged: true, verifiedEditableFields: [], saves };
await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, { flag: "wx" });
console.log(JSON.stringify({ reportPath, copiedDirectory, savesVerified: saves.length, sourceUnchanged: true }));
