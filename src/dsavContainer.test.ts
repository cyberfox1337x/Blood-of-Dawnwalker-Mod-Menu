import { describe, expect, it, vi } from "vitest";
import { decodeDsav, encodeDsav, encodeDsavContainer, parseDsavContainer, parseDsavPayload, type DsavChunk, type DsavCodec } from "../electron/dsavContainer";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_dsav_container_tests");

function fixture() {
  const records = Buffer.from("534e0000534e010012345678", "hex");
  const names = Buffer.from("\x04Root\x05Probe");
  const nameTable = Buffer.alloc(12 + names.length);
  nameTable.write("NAME"); nameTable.writeUInt32LE(names.length, 4); names.copy(nameTable, 8); nameTable.write("NAME", nameTable.length - 4);
  const directory = Buffer.alloc(42);
  directory.write("DWNT"); directory.writeUInt16LE(2, 4); directory.write("DWNT", 38);
  [[1, 65535, 1, 36, 12], [2, 65535, 65535, 40, 8]].forEach(([name, next, child, offset, size], index) => {
    const start = 6 + index * 16;
    directory.writeUInt32LE(name, start); directory.writeUInt16LE(next, start + 4); directory.writeUInt16LE(child, start + 6);
    directory.writeUInt32LE(offset, start + 8); directory.writeUInt32LE(size, start + 12);
  });
  const payload = Buffer.concat([records, nameTable, directory]);
  const header = Buffer.alloc(32);
  header.write("DSAV"); header.writeUInt32LE(36, 4); header.writeUInt16LE(134, 8); header.writeUInt16LE(5, 10); header.writeUInt32LE(2, 12);
  header.writeUInt32LE(36 + records.length, 16); header.writeUInt32LE(36 + records.length + nameTable.length, 20); header.writeUInt32LE(36 + payload.length, 24);
  const chunks = [payload.subarray(0, 8), payload.subarray(8)].map(encoded => ({ encoded: Buffer.from(encoded), decodedBytes: encoded.length }));
  const bytes = encodeDsavContainer({ header, namesOffset: header.readUInt32LE(16), nodesOffset: header.readUInt32LE(20), payloadBytes: payload.length, chunks });
  const codec: DsavCodec = { decompress: vi.fn(async (input: readonly DsavChunk[]) => input.map(chunk => Buffer.from(chunk.encoded))), compress: vi.fn(async (input: readonly Buffer[]) => input.map(encoded => ({ encoded: Buffer.from(encoded), decodedBytes: encoded.length }))) };
  return { bytes, payload, codec, container: parseDsavContainer(bytes) };
}

describe("bounded DSAV codec and indexed container", () => {
  it("resolves named records and preserves every byte without recompressing unchanged chunks", async () => {
    const { bytes, codec } = fixture();
    const document = await decodeDsav(bytes, codec);
    expect(document.nodes[1]).toMatchObject({ name: "Probe", offset: 4, size: 8 });
    expect(await encodeDsav(document, document.payload, codec)).toEqual(bytes);
    expect(codec.compress).not.toHaveBeenCalled();
  });

  it("recompresses only changed chunks and independently decodes the complete result", async () => {
    const { bytes, codec } = fixture();
    const document = await decodeDsav(bytes, codec);
    const changed = Buffer.from(document.payload); changed.writeUInt32LE(45, 8);
    const encoded = await encodeDsav(document, changed, codec);
    expect(codec.compress).toHaveBeenCalledWith([changed.subarray(8)]);
    expect(parseDsavContainer(encoded).chunks[0]).toEqual(document.container.chunks[0]);
    expect((await decodeDsav(encoded, codec)).payload).toEqual(changed);
    expect(document.payload).not.toEqual(changed);
  });

  it("rejects every truncated prefix before invoking the native codec", async () => {
    const { bytes, codec } = fixture();
    for (let end = 0; end < bytes.length; end++) await expect(decodeDsav(bytes.subarray(0, end), codec)).rejects.toThrow();
    expect(codec.decompress).not.toHaveBeenCalled();
  });

  it("rejects unknown formats, versions, modes, section overflows and chunk-directory mismatches", () => {
    const { bytes } = fixture();
    for (const offset of [0, 4, 8, 10, 12, 16, 20, 24, 28, 32, 36, 40, 44, bytes.length - 24, bytes.length - 20, bytes.length - 16, bytes.length - 4]) {
      const changed = Buffer.from(bytes); changed.writeUInt32LE(0xffffffff, offset);
      expect(() => parseDsavContainer(changed), `offset ${offset}`).toThrow();
    }
    expect(() => parseDsavContainer(Buffer.concat([bytes, Buffer.from("trailing")]))).toThrow();
  });

  it("rejects malformed name tables and indexed node references", () => {
    const { container, payload } = fixture();
    const names = container.namesOffset - 36; const node = container.nodesOffset - 36 + 22;
    for (const [offset, value, length] of [[names + 4, 1, 4], [names + 8, 0, 1], [names + 9, 255, 1], [node, 3, 4], [node + 4, 1, 2], [node + 6, 1, 2], [node + 8, 35, 4], [node + 12, 99, 4], [4, 0, 1]]) {
      const changed = Buffer.from(payload); changed.writeUIntLE(value, offset, length);
      expect(() => parseDsavPayload(container, changed), `offset ${offset}`).toThrow();
    }
  });

  it("rejects valid-looking records that are unreachable from the root", () => {
    const { container, payload } = fixture(); const changed = Buffer.from(payload);
    changed.writeUInt16LE(65535, container.nodesOffset - 36 + 12);
    expect(() => parseDsavPayload(container, changed)).toThrow("unreachable records");
  });

  it("refuses edits to the name and node directories", async () => {
    const { bytes, codec } = fixture(); const document = await decodeDsav(bytes, codec);
    const changed = Buffer.from(document.payload); changed[document.container.namesOffset - 36 + 15] = 88;
    await expect(encodeDsav(document, changed, codec)).rejects.toThrow("directories cannot change");
    expect(codec.compress).not.toHaveBeenCalled();
  });

  it("refuses unexpected codec counts, lengths, partition changes, and corrupted recompression", async () => {
    const { bytes, codec, container } = fixture();
    await expect(decodeDsav(bytes, { ...codec, decompress: async () => [] })).rejects.toThrow("unexpected chunk sizes");
    await expect(decodeDsav(bytes, { ...codec, decompress: async chunks => chunks.map(() => Buffer.alloc(1)) })).rejects.toThrow("unexpected chunk sizes");
    expect(() => encodeDsavContainer(container, [])).toThrow("partition cannot change");
    const document = await decodeDsav(bytes, codec); const changed = Buffer.from(document.payload); changed[8] = 99;
    await expect(encodeDsav(document, changed, { ...codec, compress: async () => [] })).rejects.toThrow("unexpected chunk count");
    await expect(encodeDsav(document, changed, { ...codec, compress: async () => [container.chunks[1]] })).rejects.toThrow("changed decoded bytes");
    await expect(encodeDsav(document, changed, { ...codec, compress: async () => [{ encoded: Buffer.from("x"), decodedBytes: 1 }] })).rejects.toThrow("sizes cannot change");
  });
});
