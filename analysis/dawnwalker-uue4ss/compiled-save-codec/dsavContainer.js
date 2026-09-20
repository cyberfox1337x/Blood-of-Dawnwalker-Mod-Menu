const cyberfox1337x = Object.freeze({ function: (moduleName) => void moduleName });
cyberfox1337x.function("dawnwalker_dsav_container");
const MAX_FILE_BYTES = 64 * 1024 * 1024;
const MAX_PAYLOAD_BYTES = 256 * 1024 * 1024;
const DATA_START = 36;
export const MAX_DSAV_CHUNK_BYTES = 131072;
function requireFormat(condition, reason) {
    if (!condition)
        throw new Error(`Unsupported save: ${reason}.`);
}
function hasMarker(bytes, offset, marker) {
    return offset >= 0 && offset + marker.length <= bytes.length && bytes.toString("ascii", offset, offset + marker.length) === marker;
}
export function parseDsavContainer(bytes) {
    requireFormat(bytes.length >= 64 && bytes.length <= MAX_FILE_BYTES, "file size is outside supported bounds");
    requireFormat(hasMarker(bytes, 0, "DSAV") && bytes.readUInt32LE(4) === DATA_START, "unknown DSAV header");
    requireFormat(bytes.readUInt16LE(8) === 134 && bytes.readUInt16LE(10) === 5 && bytes.readUInt32LE(12) === 2, "unverified save version or compression mode");
    const namesOffset = bytes.readUInt32LE(16);
    const nodesOffset = bytes.readUInt32LE(20);
    const decodedEnd = bytes.readUInt32LE(24);
    requireFormat(DATA_START < namesOffset && namesOffset < nodesOffset && nodesOffset < decodedEnd && decodedEnd <= MAX_PAYLOAD_BYTES + DATA_START, "invalid decoded section bounds");
    const encodedEnd = DATA_START + bytes.readUInt32LE(28);
    requireFormat(hasMarker(bytes, 32, "DSAV") && DATA_START < encodedEnd && encodedEnd <= bytes.length - 12, "invalid encoded section bounds");
    const chunks = [];
    let cursor = DATA_START;
    let payloadBytes = 0;
    while (cursor < encodedEnd) {
        requireFormat(chunks.length < 4096 && cursor + 12 <= encodedEnd && hasMarker(bytes, cursor, "CHNK"), "invalid chunk header");
        const encodedBytes = bytes.readUInt32LE(cursor + 4);
        const decodedBytes = bytes.readUInt32LE(cursor + 8);
        const stop = cursor + 12 + encodedBytes;
        requireFormat(encodedBytes > 0 && stop <= encodedEnd && decodedBytes > 0 && decodedBytes <= MAX_DSAV_CHUNK_BYTES, "invalid chunk length");
        payloadBytes += decodedBytes;
        requireFormat(payloadBytes <= MAX_PAYLOAD_BYTES, "decoded payload exceeds the size limit");
        chunks.push({ encoded: Buffer.from(bytes.subarray(cursor + 12, stop)), decodedBytes });
        cursor = stop;
    }
    requireFormat(hasMarker(bytes, cursor, "VASD") && bytes.readUInt32LE(cursor + 4) === chunks.length && chunks.length > 0, "invalid chunk directory");
    requireFormat(cursor + 12 + chunks.length * 8 === bytes.length && hasMarker(bytes, bytes.length - 4, "VASD"), "truncated directory or trailing bytes");
    for (const [index, chunk] of chunks.entries()) {
        requireFormat(bytes.readUInt32LE(cursor + 8 + index * 8) === chunk.encoded.length && bytes.readUInt32LE(cursor + 12 + index * 8) === chunk.decodedBytes, "chunk directory lengths differ");
    }
    requireFormat(payloadBytes === decodedEnd - DATA_START, "decoded size differs from the header");
    return { header: Buffer.from(bytes.subarray(0, 32)), namesOffset, nodesOffset, payloadBytes, chunks };
}
export function encodeDsavContainer(container, chunks = container.chunks) {
    requireFormat(chunks.length === container.chunks.length, "chunk partition cannot change");
    const bodyParts = [];
    const directory = Buffer.alloc(4 + chunks.length * 8);
    directory.writeUInt32LE(chunks.length);
    for (const [index, chunk] of chunks.entries()) {
        requireFormat(chunk.decodedBytes === container.chunks[index].decodedBytes && chunk.encoded.length > 0 && chunk.encoded.length <= MAX_FILE_BYTES, "chunk sizes cannot change unexpectedly");
        const header = Buffer.alloc(12);
        header.write("CHNK");
        header.writeUInt32LE(chunk.encoded.length, 4);
        header.writeUInt32LE(chunk.decodedBytes, 8);
        bodyParts.push(header, chunk.encoded);
        directory.writeUInt32LE(chunk.encoded.length, 4 + index * 8);
        directory.writeUInt32LE(chunk.decodedBytes, 8 + index * 8);
    }
    const bodyLength = bodyParts.reduce((total, part) => total + part.length, 0);
    requireFormat(bodyLength + directory.length + 44 <= MAX_FILE_BYTES, "encoded save exceeds the size limit");
    const header = Buffer.from(container.header);
    header.writeUInt32LE(bodyLength, 28);
    const encoded = Buffer.concat([header, Buffer.from("DSAV"), ...bodyParts, Buffer.from("VASD"), directory, Buffer.from("VASD")]);
    parseDsavContainer(encoded);
    return encoded;
}
function parseNames(payload, container) {
    const start = container.namesOffset - DATA_START;
    const end = container.nodesOffset - DATA_START;
    requireFormat(end - start >= 12 && hasMarker(payload, start, "NAME") && hasMarker(payload, end - 4, "NAME"), "invalid name table");
    requireFormat(start + 8 + payload.readUInt32LE(start + 4) === end - 4, "name table length differs");
    const names = [];
    const decoder = new TextDecoder("utf-8", { fatal: true });
    let cursor = start + 8;
    while (cursor < end - 4) {
        const length = payload[cursor++];
        requireFormat(length > 0 && cursor + length <= end - 4 && names.length < 65535, "invalid name length");
        const name = decoder.decode(payload.subarray(cursor, cursor + length));
        requireFormat(!name.includes("\0"), "name contains a terminator");
        names.push(name);
        cursor += length;
    }
    return names;
}
export function parseDsavPayload(container, payload) {
    requireFormat(payload.length === container.payloadBytes, "decoded payload length differs");
    const names = parseNames(payload, container);
    const start = container.nodesOffset - DATA_START;
    requireFormat(start + 10 <= payload.length && hasMarker(payload, start, "DWNT") && hasMarker(payload, payload.length - 4, "DWNT"), "invalid node directory");
    const count = payload.readUInt16LE(start + 4);
    requireFormat(count > 0 && start + 10 + count * 16 === payload.length, "node count differs from directory length");
    const nodes = [];
    for (let index = 0; index < count; index++) {
        const cursor = start + 6 + index * 16;
        const nameIndex = payload.readUInt32LE(cursor);
        const nextIndex = payload.readUInt16LE(cursor + 4);
        const childIndex = payload.readUInt16LE(cursor + 6);
        const offset = payload.readUInt32LE(cursor + 8) - DATA_START;
        const size = payload.readUInt32LE(cursor + 12);
        requireFormat(nameIndex > 0 && nameIndex <= names.length, "node refers to an invalid name");
        requireFormat(offset >= 0 && size >= 4 && offset + size <= container.namesOffset - DATA_START, "node exceeds its data region");
        requireFormat(hasMarker(payload, offset, "SN") && payload.readUInt16LE(offset + 2) === index, "node marker differs from its directory index");
        requireFormat([nextIndex, childIndex].every(link => link === 65535 || (link > index && link < count)), "invalid or cyclic node link");
        nodes.push({ index, name: names[nameIndex - 1], nextIndex, childIndex, offset, size });
    }
    requireFormat(nodes[0].name === "Root" && nodes[0].offset === 0 && nodes[0].size === container.namesOffset - DATA_START, "root does not span the record region");
    for (const node of nodes) {
        if (node.childIndex !== 65535) {
            const child = nodes[node.childIndex];
            requireFormat(child.offset > node.offset && child.offset + child.size <= node.offset + node.size, "child exceeds its parent");
        }
        if (node.nextIndex !== 65535)
            requireFormat(nodes[node.nextIndex].offset >= node.offset + node.size, "next node overlaps its predecessor");
    }
    return { container, payload, names, nodes };
}
export async function decodeDsav(bytes, codec) {
    const container = parseDsavContainer(bytes);
    const decoded = await codec.decompress(container.chunks);
    requireFormat(decoded.length === container.chunks.length && decoded.every((chunk, index) => chunk.length === container.chunks[index].decodedBytes), "codec returned unexpected chunk sizes");
    return parseDsavPayload(container, Buffer.concat(decoded));
}
// This internal format operation accepts a complete payload, never renderer-supplied offsets.
// A field editor must first prove its own schema and the exact permitted byte differences.
export async function encodeDsav(document, payload, codec) {
    parseDsavPayload(document.container, payload);
    requireFormat(payload.subarray(document.container.namesOffset - DATA_START).equals(document.payload.subarray(document.container.namesOffset - DATA_START)), "name and node directories cannot change");
    let cursor = 0;
    const changedIndexes = [];
    const changedPayloads = [];
    for (const [index, chunk] of document.container.chunks.entries()) {
        const next = payload.subarray(cursor, cursor + chunk.decodedBytes);
        if (!next.equals(document.payload.subarray(cursor, cursor + chunk.decodedBytes))) {
            changedIndexes.push(index);
            changedPayloads.push(next);
        }
        cursor += chunk.decodedBytes;
    }
    if (!changedIndexes.length)
        return encodeDsavContainer(document.container);
    const compressed = await codec.compress(changedPayloads);
    requireFormat(compressed.length === changedIndexes.length, "codec returned an unexpected chunk count");
    const chunks = [...document.container.chunks];
    changedIndexes.forEach((chunkIndex, index) => { chunks[chunkIndex] = compressed[index]; });
    const encoded = encodeDsavContainer(document.container, chunks);
    const readback = await decodeDsav(encoded, codec);
    requireFormat(readback.payload.equals(payload), "re-encoded save changed decoded bytes");
    return encoded;
}
