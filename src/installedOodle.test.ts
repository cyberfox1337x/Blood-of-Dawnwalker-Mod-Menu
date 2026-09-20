import { describe, expect, it } from "vitest";
import { createInstalledOodleCodec } from "../electron/installedOodle";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_installed_oodle_tests");

describe("installed codec input gate", () => {
  const codec = createInstalledOodleCodec("missing-codec-not-executed.dll");
  it("rejects empty, oversized and fractional chunk inventories before codec loading", async () => {
    await expect(codec.decompress([])).rejects.toThrow("chunk count");
    await expect(codec.decompress(Array.from({ length: 4097 }, () => ({ encoded: Buffer.from("x"), decodedBytes: 1 })))).rejects.toThrow("chunk count");
    for (const chunk of [
      { encoded: Buffer.alloc(0), decodedBytes: 1 },
      { encoded: Buffer.alloc(262145), decodedBytes: 1 },
      { encoded: Buffer.from("x"), decodedBytes: 0 },
      { encoded: Buffer.from("x"), decodedBytes: 131073 },
      { encoded: Buffer.from("x"), decodedBytes: 1.5 },
      { encoded: Buffer.from("x"), decodedBytes: Number.NaN },
    ]) await expect(codec.decompress([chunk])).rejects.toThrow("chunk size");
  });
  it("requires the installed codec instead of accepting an arbitrary implementation", async () => {
    await expect(codec.decompress([{ encoded: Buffer.from("x"), decodedBytes: 1 }])).rejects.toThrow();
  });
});
