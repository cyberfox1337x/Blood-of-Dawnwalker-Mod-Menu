// @vitest-environment node
import { afterEach, expect, it } from "vitest";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createInterfaceScaleStore } from "./interfaceScale.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("interface_scale_tests");
const directories: string[] = [];
afterEach(async () => { await Promise.all(directories.splice(0).map(directory => rm(directory, { recursive: true, force: true }))); });
async function preferencePath() {
  const directory = await mkdtemp(join(tmpdir(), "dawnwalker-scale-test-"));
  directories.push(directory);
  return join(directory, "scale.json");
}
it("persists across launches and serializes rapid writes", async () => {
  const path = await preferencePath();
  const store = createInterfaceScaleStore(path);
  await store.load();
  expect(store.get()).toBe(100);
  await Promise.all([store.set(125), store.set(150), store.set(200)]);
  const reloaded = createInterfaceScaleStore(path);
  await reloaded.load();
  expect(reloaded.get()).toBe(200);
  await reloaded.set(100);
  await store.load();
  expect(store.get()).toBe(100);
});
it("rejects invalid requests without changing the saved preference", async () => {
  const path = await preferencePath();
  const store = createInterfaceScaleStore(path);
  await store.set(75);
  for (const invalid of [74, 201, 125.5, NaN, Infinity, "125", null]) await expect(store.set(invalid)).rejects.toThrow("75 to 200");
  await store.load();
  expect(store.get()).toBe(75);
});
it("retains current zoom on failed persistence and supports retry", async () => {
  const path = await preferencePath();
  await writeFile(path, "100");
  const store = createInterfaceScaleStore(`${path}/blocked.json`);
  await expect(store.set(150)).rejects.toThrow();
  expect(store.get()).toBe(100);
  await rm(path);
  await store.set(150);
  expect(store.get()).toBe(150);
});
