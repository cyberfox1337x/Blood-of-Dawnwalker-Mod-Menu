import { describe, expect, it } from "vitest";
import { decodeDsav, encodeDsavContainer, encodeResizedDsav, parseDsavContainer, parseDsavPayload, type DsavChunk, type DsavCodec, type DsavDocument } from "../electron/dsavContainer";
import { firstNameIndexes, writePacked } from "../electron/recordCursor";
import { readInventoryDocument, rebuildPayload, removePlayerStack, serializeInventoryDocument, setPlayerStack } from "../electron/saveStructural";
import { walkInventory } from "../electron/saveFields";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_save_structural_tests");

// A three-record save: Root, InventorySubsystem (two item types, player owner with two
// stacks and one equipment set) and a trailing record whose offset must follow any
// inventory growth. The inventory suffix is the smallest one the format allows.
const NAMES = ["Root", "InventorySubsystem", "Trailing", "ChestCommon8b", "Medicaments1"];

const u8 = (value: number) => Buffer.from([value]);
const u16 = (value: number) => { const b = Buffer.alloc(2); b.writeUInt16LE(value); return b; };
const u32 = (value: number) => { const b = Buffer.alloc(4); b.writeUInt32LE(value >>> 0); return b; };

function inventoryRecord(): Buffer {
  const firstIndexOf = firstNameIndexes(NAMES);
  const suffix = Buffer.concat([
    u16(0), u16(0), // initial handle lists
    u32(0), // merchants
    u16(1), u32(0), u16(0), u16(0), // three tracked lists (first tracks handle 0)
    u16(1), u8(3), u16(1), u32(7), // keyed map: one key with one value
    Buffer.alloc(12), // trailer
  ]);
  return Buffer.concat([
    u32(531369477), // prefix word
    u32(2), writePacked(firstIndexOf.get("ChestCommon8b")!), writePacked(firstIndexOf.get("Medicaments1")!), // types
    u32(2), u32(0), u8(0), u32(1), u8(0), // handles: (type 0, variant 0), (type 1, variant 0)
    u32(1), // owners
    u32(1), u8(0), // player owner key 1, flag 0
    u16(2), u32(0), u32(1), // stack handles
    u16(2), u32(1), u32(3), // stack quantities
    u8(0), u32(1), u16(1), u8(5), u16(1), u32(0), // active set 0, one equipment set: key 5 -> handle 0
    u16(1), u32(1), // references: handle 1
    suffix,
  ]);
}

function buildSave(): { bytes: Buffer; codec: DsavCodec } {
  const inventory = inventoryRecord();
  const inventoryNode = Buffer.concat([Buffer.from("SN"), u16(1), inventory]);
  const trailingNode = Buffer.concat([Buffer.from("SN"), u16(2), u32(0xabad1dea)]);
  const root = Buffer.concat([Buffer.from("SN"), u16(0)]);
  const records = Buffer.concat([root, inventoryNode, trailingNode]);
  const nameBody = Buffer.concat(NAMES.map(name => Buffer.concat([u8(name.length), Buffer.from(name)])));
  const nameTable = Buffer.concat([Buffer.from("NAME"), u32(nameBody.length), nameBody, Buffer.from("NAME")]);
  const entries: [number, number, number, number, number][] = [
    [1, 65535, 1, 36, records.length],
    [2, 2, 65535, 36 + root.length, inventoryNode.length],
    [3, 65535, 65535, 36 + root.length + inventoryNode.length, trailingNode.length],
  ];
  const directory = Buffer.alloc(6 + entries.length * 16 + 4);
  directory.write("DWNT"); directory.writeUInt16LE(entries.length, 4);
  entries.forEach(([name, next, child, offset, size], index) => {
    const start = 6 + index * 16;
    directory.writeUInt32LE(name, start); directory.writeUInt16LE(next, start + 4); directory.writeUInt16LE(child, start + 6);
    directory.writeUInt32LE(offset, start + 8); directory.writeUInt32LE(size, start + 12);
  });
  directory.write("DWNT", directory.length - 4);
  const payload = Buffer.concat([records, nameTable, directory]);
  const header = Buffer.alloc(32);
  header.write("DSAV"); header.writeUInt32LE(36, 4); header.writeUInt16LE(134, 8); header.writeUInt16LE(5, 10); header.writeUInt32LE(2, 12);
  header.writeUInt32LE(36 + records.length, 16); header.writeUInt32LE(36 + records.length + nameTable.length, 20); header.writeUInt32LE(36 + payload.length, 24);
  const chunks = [{ encoded: Buffer.from(payload), decodedBytes: payload.length }];
  const bytes = encodeDsavContainer({ header, namesOffset: header.readUInt32LE(16), nodesOffset: header.readUInt32LE(20), payloadBytes: payload.length, chunks });
  const codec: DsavCodec = {
    decompress: async (input: readonly DsavChunk[]) => input.map(chunk => Buffer.from(chunk.encoded)),
    compress: async (input: readonly Buffer[]) => input.map(encoded => ({ encoded: Buffer.from(encoded), decodedBytes: encoded.length })),
  };
  return { bytes, codec };
}

function rebuild(document: DsavDocument, change: (inventory: NonNullable<ReturnType<typeof readInventoryDocument>>) => void) {
  const inventory = readInventoryDocument(document)!;
  change(inventory);
  const names = [...document.names];
  const nameIndex = (name: string) => { const at = names.indexOf(name); if (at >= 0) return at + 1; names.push(name); return names.length; };
  const record = serializeInventoryDocument(inventory, nameIndex);
  const rebuilt = rebuildPayload(document, new Map([["InventorySubsystem", record]]), names);
  const container = { ...document.container, namesOffset: rebuilt.namesOffset, nodesOffset: rebuilt.nodesOffset, payloadBytes: rebuilt.payload.length };
  return { rebuilt, document: parseDsavPayload(container, rebuilt.payload) };
}

describe("structural inventory rewrite", () => {
  it("parses the record to its exact end and serialises it back byte for byte", async () => {
    const { bytes, codec } = buildSave();
    const document = await decodeDsav(bytes, codec);
    const inventory = readInventoryDocument(document)!;
    expect(inventory.types).toEqual(["ChestCommon8b", "Medicaments1"]);
    expect(inventory.owners[0].stacks).toEqual([{ handle: 0, quantity: 1 }, { handle: 1, quantity: 3 }]);
    const firstIndexOf = firstNameIndexes(document.names);
    expect(serializeInventoryDocument(inventory, name => firstIndexOf.get(name)!)).toEqual(inventoryRecord());
    const identity = rebuildPayload(document, new Map([["InventorySubsystem", inventoryRecord()]]), document.names);
    expect(identity.payload).toEqual(document.payload);
  });

  it("adds an item the save never listed by appending its name, type, handle and stack, and shifts later records", async () => {
    const { bytes, codec } = buildSave();
    const document = await decodeDsav(bytes, codec);
    const { rebuilt, document: after } = rebuild(document, inventory => setPlayerStack(inventory, "SwordLongCommon2", 2));
    expect(after.names).toEqual([...NAMES, "SwordLongCommon2"]);
    const walk = walkInventory(after);
    expect(walk.stacks.map(stack => `${stack.name}x${stack.value}`)).toEqual(["ChestCommon8bx1", "Medicaments1x3", "SwordLongCommon2x2"]);
    expect(walk.catalog.map(entry => entry.name)).toEqual(["ChestCommon8b", "Medicaments1", "SwordLongCommon2"]);
    const trailing = after.nodes.find(node => node.name === "Trailing")!;
    expect(after.payload.readUInt32LE(trailing.offset + 4)).toBe(0xabad1dea);
    const encoded = await encodeResizedDsav(document, rebuilt.payload, rebuilt.namesOffset, rebuilt.nodesOffset, codec);
    const readback = await decodeDsav(encoded, codec);
    expect(readback.payload).toEqual(rebuilt.payload);
    expect(parseDsavContainer(encoded).namesOffset).toBe(rebuilt.namesOffset);
  });

  it("removes a stack together with its equipment slot and reference, and refuses a nonexistent item id path", async () => {
    const { bytes, codec } = buildSave();
    const document = await decodeDsav(bytes, codec);
    const { document: after } = rebuild(document, inventory => removePlayerStack(inventory, 0));
    const inventory = readInventoryDocument(after)!;
    expect(inventory.owners[0].stacks).toEqual([{ handle: 1, quantity: 3 }]);
    expect(inventory.owners[0].equipment[0][0].handle).toBe(0xffffffff);
    expect(walkInventory(after).stacks.map(stack => stack.name)).toEqual(["Medicaments1"]);
    expect(() => setPlayerStack(readInventoryDocument(document)!, "/Game/_Dawnwalker/Inventory/Items/ITM_Foo", 1)).toThrow(/ItemId/);
  });

  it("stops on a record whose player stack points at a handle that does not exist", async () => {
    const { bytes, codec } = buildSave();
    const document = await decodeDsav(bytes, codec);
    const node = document.nodes.find(entry => entry.name === "InventorySubsystem")!;
    const broken = Buffer.from(document.payload);
    // prefix word, type count, two 1-byte type refs, handle count, two 5-byte handles, owner
    // count, owner key, flag, stack count -> the first stack handle sits 35 bytes in.
    broken.writeUInt32LE(99, node.offset + 4 + 35);
    const brokenDocument = parseDsavPayload(document.container, broken);
    expect(() => readInventoryDocument(brokenDocument)).toThrow(/outside the handle dictionary/);
  });
});
