const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("noPakDependency_test");

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

// Every feature this menu offers is driven through the UE4SS Lua payload and the desktop
// command channel. Nothing may depend on a .pak (or IoStore .ucas/.utoc) dropped into the
// game's Content/Paks folder: a pak override changes the game for every session whether
// the menu is open or not, cannot be switched off from the menu, and breaks on every game
// update. These checks pin that rule so it cannot regress quietly.
const root = join(__dirname, "..");
const PAYLOAD_ROOTS = ["integration/imported-menu", "installer/runtime", "installer/templates"];
const GAME_CONTAINER_EXTENSIONS = [".pak", ".ucas", ".utoc"];

function walk(directory: string, out: string[] = []): string[] {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) walk(path, out); else out.push(path);
  }
  return out;
}

describe("no pak-file dependency", () => {
  it("ships no game container files in any payload the installer can deploy", () => {
    for (const payloadRoot of PAYLOAD_ROOTS) {
      const offenders = walk(join(root, payloadRoot)).filter(path => GAME_CONTAINER_EXTENSIONS.some(extension => path.toLowerCase().endsWith(extension)));
      expect(offenders.map(path => relative(root, path)), payloadRoot).toEqual([]);
    }
  });

  it("pins only Lua and text files in the imported-menu manifest", () => {
    const manifest = JSON.parse(readFileSync(join(root, "integration/imported-menu/manifest.json"), "utf-8")) as { files: { path: string }[] };
    for (const entry of manifest.files) {
      expect(GAME_CONTAINER_EXTENSIONS.some(extension => entry.path.toLowerCase().endsWith(extension)), entry.path).toBe(false);
    }
  });

  it("has no Lua that loads or looks for paks, LogicMods or the BP mod loader", () => {
    const scripts = walk(join(root, "integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts")).filter(path => path.endsWith(".lua"));
    expect(scripts.length).toBeGreaterThan(50);
    for (const script of scripts) {
      const text = readFileSync(script, "utf-8");
      expect(/LogicMods|BPModLoader|\.pak\b|Content[\\/]Paks/i.test(text), relative(root, script)).toBe(false);
    }
  });

  it("keeps the UE4SS pak loader disabled in every shipped mods.txt", () => {
    for (const path of ["installer/runtime/overrides/ue4ss/Mods/mods.txt", "installer/templates/ue4ss/Mods/mods.txt"]) {
      const text = readFileSync(join(root, path), "utf-8");
      // These files are CRLF; `\s*$` absorbs the carriage return before the line end.
      expect(text, path).toMatch(/^BPModLoaderMod\s*:\s*0\s*$/m);
      expect(text, path).not.toMatch(/^BPModLoaderMod\s*:\s*1/m);
      expect(text, path).not.toMatch(/^BPML_GenericFunctions\s*:\s*1/m);
    }
  });

  it("forbids the runtime installer from writing anywhere under the game's Paks folders", () => {
    const contract = JSON.parse(readFileSync(join(root, "installer/runtime/official-build.json"), "utf-8")) as { safety: { forbiddenWriteRootFragments: string[]; allowedWriteTargetsRelativeToWin64: string[] } };
    expect(contract.safety.forbiddenWriteRootFragments).toEqual(expect.arrayContaining(["Dawnwalker/Content/Paks", "Content/Paks", "Engine/Content/Paks"]));
    for (const target of contract.safety.allowedWriteTargetsRelativeToWin64) expect(target.toLowerCase()).not.toContain("pak");
  });
});
