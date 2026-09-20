import { describe, expect, it } from "vitest";
import { decodeDsav, encodeDsavContainer, type DsavCodec, type DsavDocument } from "../electron/dsavContainer";
import { encodeEditedSave, validateFieldEdit } from "../electron/saveEditing";
import { readClockMs } from "../electron/saveFields";
import { writePacked } from "../electron/recordCursor";
import { journalObjectiveKey, parseJournalPrefix, parseQuestCatalog, planQuestTracking, questTrackingOptions, readSaveJournal } from "../electron/saveJournal";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_save_journal_tests");
const assetPath = "/Game/Quest.Test";
const guid = "5570EA8B-44AC0F58-760529B1-3511EFF8";
const questGuid = "91CDA8A9-4D9C10F2-D11A3894-4EC46C58";
const zero = "00000000-00000000-00000000-00000000";
const u16 = (n: number) => { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; };
const u32 = (n: number) => { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; };
function tracked(text = "", id = zero) { const bytes = Buffer.from(text); return Buffer.concat([Buffer.from([bytes.length]), bytes, ...id.split("-").map(v => u32(parseInt(v, 16)))]); }
function prefix(state = 1, objectiveState = 1) {
  return Buffer.concat([u32(1), Buffer.from([state]), u16(1), u32(journalObjectiveKey(guid)), u16(1), Buffer.alloc(8), u16(1), u32(0), u16(1), Buffer.from([objectiveState]), writePacked(1), Buffer.from([0]), u32(0), tracked("main"), tracked()]);
}
function document(bytes = prefix()): DsavDocument {
  const header = Buffer.alloc(36); header.writeUInt16LE(134, 8); header.writeUInt16LE(5, 10);
  return { container: { header, namesOffset: 0, nodesOffset: 0, payloadBytes: bytes.length + 4, chunks: [] }, names: [assetPath], payload: Buffer.concat([Buffer.alloc(4), bytes]), nodes: [{ index: 0, name: "Journal", nextIndex: 65535, childIndex: 65535, offset: 0, size: bytes.length + 4 }] };
}
function catalog(type = 1) { return parseQuestCatalog(JSON.stringify([{ AssetPath: assetPath, Guid: questGuid, Title: "Test quest", NewType: type, Objectives: [{ Guid: guid, Name: "Active objective" }], Endings: [] }])); }

function trackingContainerFixture(): { bytes: Buffer; codec: DsavCodec } {
  const names = [assetPath, "Root", "TimeSystemImpl", "Journal"];
  const root = Buffer.concat([Buffer.from("SN"), u16(0)]);
  const time = Buffer.concat([Buffer.from("SN"), u16(1), u32(43_210)]);
  const journal = Buffer.concat([Buffer.from("SN"), u16(2), prefix()]);
  const records = Buffer.concat([root, time, journal]);
  const nameBody = Buffer.concat(names.map(name => Buffer.concat([Buffer.from([Buffer.byteLength(name)]), Buffer.from(name)])));
  const nameTable = Buffer.concat([Buffer.from("NAME"), u32(nameBody.length), nameBody, Buffer.from("NAME")]);
  const entries = [[2, 65535, 1, 36, records.length], [3, 2, 65535, 40, time.length], [4, 65535, 65535, 40 + time.length, journal.length]];
  const directory = Buffer.alloc(6 + entries.length * 16 + 4); directory.write("DWNT"); directory.writeUInt16LE(entries.length, 4);
  entries.forEach(([name, next, child, offset, size], index) => { const at = 6 + index * 16; directory.writeUInt32LE(name, at); directory.writeUInt16LE(next, at + 4); directory.writeUInt16LE(child, at + 6); directory.writeUInt32LE(offset, at + 8); directory.writeUInt32LE(size, at + 12); });
  directory.write("DWNT", directory.length - 4);
  const payload = Buffer.concat([records, nameTable, directory]);
  const header = Buffer.alloc(32); header.write("DSAV"); header.writeUInt32LE(36, 4); header.writeUInt16LE(134, 8); header.writeUInt16LE(5, 10); header.writeUInt32LE(2, 12);
  header.writeUInt32LE(36 + records.length, 16); header.writeUInt32LE(36 + records.length + nameTable.length, 20); header.writeUInt32LE(36 + payload.length, 24);
  const bytes = encodeDsavContainer({ header, namesOffset: header.readUInt32LE(16), nodesOffset: header.readUInt32LE(20), payloadBytes: payload.length, chunks: [{ encoded: payload, decodedBytes: payload.length }] });
  const codec: DsavCodec = { decompress: async chunks => chunks.map(chunk => Buffer.from(chunk.encoded)), compress: async chunks => chunks.map(chunk => ({ encoded: Buffer.from(chunk), decodedBytes: chunk.length })) };
  return { bytes, codec };
}

describe("Journal tracking", () => {
  it("uses four-word GUIDs and rejects unsupported spellings", () => {
    // Independent Python uint64 reference calculation from JournalGuid.cs.
    expect(journalObjectiveKey(guid)).toBe(1593513456);
    expect(journalObjectiveKey(guid)).toBe(journalObjectiveKey(guid.toLowerCase()));
    expect(() => journalObjectiveKey("5570EA8B-44AC-0F58-7605-29B13511EFF8")).toThrow(/GUID/);
  });
  it("parses exact records and preserves all bytes before TrackedOther", () => {
    const doc = document(); const parsed = parseJournalPrefix(prefix(), doc.names);
    const options = questTrackingOptions(doc, catalog());
    expect(options.options).toHaveLength(1);
    const result = planQuestTracking(doc, { assetPath, objectiveGuid: guid, expectedMain: parsed.trackedMain, expectedOther: parsed.trackedOther }, catalog());
    expect(result.prefix.subarray(0, parsed.otherOffset)).toEqual(prefix().subarray(0, parsed.otherOffset));
    const rebuilt = parseJournalPrefix(result.prefix, doc.names);
    expect(rebuilt.trackedMain).toEqual(parsed.trackedMain);
    expect(rebuilt.trackedOther).toEqual({ instanceId: `Test${questGuid.replaceAll("-", "")}`, objectiveGuid: guid });
    expect(result.changed).toBe(true);
  });
  it("rejects corrupt counts, trailing bytes and invalid UTF-8", () => {
    const bytes = prefix(); bytes.writeUInt32LE(4097);
    expect(() => parseJournalPrefix(bytes, [assetPath])).toThrow(/count/);
    expect(() => parseJournalPrefix(Buffer.concat([prefix(), Buffer.from([0])]), [assetPath])).toThrow(/trailing/);
    const bad = Buffer.concat([u32(0), u32(0), Buffer.from([1, 255]), Buffer.alloc(16), tracked()]);
    expect(() => parseJournalPrefix(bad, [])).toThrow(/UTF/);
    const mismatched = prefix(); mismatched.writeUInt16LE(2, 11);
    expect(() => parseJournalPrefix(mismatched, [assetPath])).toThrow(/array lengths/);
    const negative = prefix(); negative.writeBigInt64LE(-1n, 13);
    expect(() => parseJournalPrefix(negative, [assetPath])).toThrow(/timestamp/);
  });
  it("refuses inactive objectives, closed quests, MainGoal and stale previews", () => {
    const parsed = parseJournalPrefix(prefix(), [assetPath]);
    const request = { assetPath, objectiveGuid: guid, expectedMain: parsed.trackedMain, expectedOther: parsed.trackedOther };
    expect(() => planQuestTracking(document(prefix(2)), request, catalog())).toThrow(/active quest/);
    expect(() => planQuestTracking(document(prefix(1, 2)), request, catalog())).toThrow(/not active/);
    expect(() => planQuestTracking(document(), request, catalog(0))).toThrow(/Story or NanoPOI/);
    expect(() => planQuestTracking(document(), { ...request, expectedOther: { instanceId: "stale", objectiveGuid: zero } }, catalog())).toThrow(/preview/);
    expect(questTrackingOptions(document(prefix(1, 2)), catalog()).options).toEqual([]);
    const unsupported = document(); unsupported.container.header.writeUInt16LE(6, 10);
    expect(() => planQuestTracking(unsupported, request, catalog())).toThrow(/DSAV/);
  });
  it("rejects duplicate catalog identities and objective key aliases", () => {
    const row = { AssetPath: assetPath, Guid: questGuid, Objectives: [{ Guid: guid }, { Guid: guid.toLowerCase() }], Endings: [] };
    expect(() => parseQuestCatalog(JSON.stringify([row]))).toThrow(/objective identity/);
    row.Objectives.pop();
    expect(() => parseQuestCatalog(JSON.stringify([row, row]))).toThrow(/identity/);
  });
  it("validates serializable tracking requests and rejects malformed expected pairs", () => {
    const parsed = parseJournalPrefix(prefix(), [assetPath]);
    const questTracking = { assetPath, objectiveGuid: guid, expectedMain: parsed.trackedMain, expectedOther: parsed.trackedOther };
    expect(validateFieldEdit(JSON.parse(JSON.stringify({ questTracking })))).toEqual({ questTracking });
    expect(() => validateFieldEdit({ questTracking: { ...questTracking, expectedMain: null } })).toThrow();
    expect(() => validateFieldEdit({ questTracking: { ...questTracking, expectedOther: { instanceId: 4, objectiveGuid: guid } } })).toThrow();
    expect(() => validateFieldEdit({ questTracking: { ...questTracking, expectedOther: { instanceId: "ok", objectiveGuid: "malformed" } } })).toThrow();
  });
  it("rewrites tracking through the complete container pipeline without changing the main goal or clock", async () => {
    const { bytes, codec } = trackingContainerFixture();
    const before = await decodeDsav(bytes, codec); const original = readSaveJournal(before)!;
    expect(readClockMs(before)).toBe(43_210);
    const questTracking = { assetPath, objectiveGuid: guid, expectedMain: original.trackedMain, expectedOther: original.trackedOther };
    const result = await encodeEditedSave(bytes, { questTracking, questCatalog: catalog() }, codec);
    const after = await decodeDsav(result.encoded, codec); const journal = readSaveJournal(after)!;
    expect(journal.trackedOther).toEqual({ instanceId: `Test${questGuid.replaceAll("-", "")}`, objectiveGuid: guid });
    expect(journal.trackedMain).toEqual(original.trackedMain);
    expect(journal.quests).toEqual(original.quests);
    expect(readClockMs(after)).toBe(43_210);
    expect(journal.prefix.subarray(0, journal.otherOffset)).toEqual(original.prefix.subarray(0, original.otherOffset));
  });
});
