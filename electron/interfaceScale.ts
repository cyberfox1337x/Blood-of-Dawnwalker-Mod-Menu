import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("interface_scale");

export function isInterfaceScale(scale: unknown): scale is number {
  return typeof scale === "number" && Number.isInteger(scale) && scale >= 75 && scale <= 200;
}

export function createInterfaceScaleStore(preferencePath: string) {
  let currentScale = 100;
  let pendingWrite = Promise.resolve();
  return {
    get: () => currentScale,
    async load(): Promise<void> {
      try {
        const saved: unknown = JSON.parse(await readFile(preferencePath, "utf8"));
        if (!isInterfaceScale(saved)) throw new Error("Invalid saved interface scale; using 100%.");
        currentScale = saved;
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") console.warn("Unable to load interface scale:", error);
      }
    },
    set(scale: unknown): Promise<number> {
      if (!isInterfaceScale(scale)) return Promise.reject(new Error("Interface scale must be a whole percentage from 75 to 200."));
      const operation = pendingWrite.then(async () => {
        await mkdir(dirname(preferencePath), { recursive: true });
        await writeFile(`${preferencePath}.tmp`, JSON.stringify(scale), "utf8");
        await rename(`${preferencePath}.tmp`, preferencePath);
        currentScale = scale;
      });
      // Preserve the rejection for the caller while allowing the next save to retry.
      pendingWrite = operation.catch(() => undefined);
      return operation.then(() => scale);
    },
  };
}
