const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_record_cursor");

// Bounds-checked reader over one record's bytes. Every read that would run past the
// record throws with the offset, so a layout the code does not recognise stops the
// edit instead of producing a guess.
export class RecordCursor {
  position: number;
  constructor(private readonly bytes: Buffer, start: number, private readonly end: number, private readonly record: string) {
    this.position = start;
  }
  get remaining(): number { return this.end - this.position; }
  take(count: number): number {
    if (count < 0 || count > this.remaining) throw new Error(`${this.record}: record ends inside a field at 0x${this.position.toString(16)}.`);
    const at = this.position;
    this.position += count;
    return at;
  }
  u8(): number { return this.bytes[this.take(1)]; }
  u16(): number { return this.bytes.readUInt16LE(this.take(2)); }
  u32(): number { return this.bytes.readUInt32LE(this.take(4)); }
  slice(count: number): Buffer { const at = this.take(count); return Buffer.from(this.bytes.subarray(at, at + count)); }
  requireArray(count: number, stride: number): void {
    if (stride <= 0 || count > Math.floor(this.remaining / stride)) throw new Error(`${this.record}: count ${count} exceeds the remaining record at 0x${this.position.toString(16)}.`);
  }
  /** Packed u32: 7 value bits per byte, low bit set while more bytes follow. */
  packed(): number {
    let value = 0;
    for (let index = 0; index < 5; index++) {
      const byte = this.u8();
      const bits = byte >>> 1;
      if (index === 4 && bits > 15) throw new Error(`${this.record}: packed u32 overflow at 0x${(this.position - 1).toString(16)}.`);
      value = (value | (bits << (7 * index))) >>> 0;
      if ((byte & 1) === 0) return value;
    }
    throw new Error(`${this.record}: overlong packed u32 at 0x${this.position.toString(16)}.`);
  }
}

/** Inverse of RecordCursor.packed. */
export function writePacked(value: number): Buffer {
  const bytes: number[] = [];
  let rest = value >>> 0;
  do {
    const low = rest & 0x7f;
    rest >>>= 7;
    bytes.push((low << 1) | (rest !== 0 ? 1 : 0));
  } while (rest !== 0);
  return Buffer.from(bytes);
}

/** 1-based index of a name in the save's name table; the first occurrence wins, as the game's own references do. */
export function firstNameIndexes(names: readonly string[]): ReadonlyMap<string, number> {
  const map = new Map<string, number>();
  names.forEach((name, index) => { if (!map.has(name)) map.set(name, index + 1); });
  return map;
}

export function readNameReference(cursor: RecordCursor, names: readonly string[], firstIndexOf: ReadonlyMap<string, number>, record: string): string {
  const start = cursor.position;
  const reference = cursor.packed();
  if (reference === 0 || reference > names.length) throw new Error(`${record}: invalid name reference.`);
  const name = names[reference - 1];
  if (!name || name.includes("\0") || firstIndexOf.get(name) !== reference || cursor.position - start !== writePacked(reference).length) {
    throw new Error(`${record}: name reference is noncanonical or ambiguous for rewriting.`);
  }
  return name;
}
