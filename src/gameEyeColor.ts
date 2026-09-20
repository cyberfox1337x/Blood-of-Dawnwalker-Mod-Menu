import type { ImportedMenuTransport } from "./importedMenuContract";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("game_eye_color_acknowledgement");

export const MAX_GAME_EYE_GLOW = 3;

/**
 * Apply (or restore) the eye colour in game and wait for that exact native operation.
 *
 * `glow` is the neon strength (0..3). It goes to the game's "glow" item first, and only
 * when the live section exposes one: a mod build without it (before the glow update)
 * still gets the colour, exactly as before. The colour is the second, separately
 * acknowledged request; the native side applies the glow it holds at that moment.
 */
export async function applyGameEyeColor(transport: ImportedMenuTransport, color: string | null, glow = 0,
  wait: () => Promise<void> = () => new Promise(resolve => setTimeout(resolve, 250))) {
  if (color !== null && !/^#[\da-f]{6}$/i.test(color)) throw new Error("Choose a valid eye color.");
  if (!Number.isFinite(glow) || glow < 0 || glow > MAX_GAME_EYE_GLOW) throw new Error(`Eye glow strength must be between 0 and ${MAX_GAME_EYE_GLOW}.`);
  const initial = await transport.state();
  if (!initial.ready) throw new Error(initial.message || "Load your game before applying eye color.");
  const eyeSection = initial.sections.find(section => section.id === "DWEyeColor");
  const glowSupported = Boolean(eyeSection?.items.some(item => item.id === "glow"));
  const acknowledge = async (request: Parameters<ImportedMenuTransport["dispatch"]>[0], what: string) => {
    const result = await transport.dispatch(request);
    if (!result.accepted) throw new Error(result.message);
    if (!result.operationId) throw new Error(`The game connection did not identify the ${what} request. Check the connection before retrying.`);
    for (let attempt = 0; attempt < 40; attempt += 1) {
      await wait();
      const current = await transport.state();
      if (!current.ready || current.sessionId !== initial.sessionId) throw new Error(`The game session changed while applying ${what}. Select the color again after loading.`);
      if (current.operation?.id !== result.operationId) continue;
      if (current.operation.status === "failed") throw new Error(current.operation.message || `The game could not apply ${what}.`);
      if (current.operation.status === "completed") return;
    }
    throw new Error(`${what[0].toUpperCase()}${what.slice(1)} confirmation timed out. Check the game before retrying.`);
  };
  if (color !== null && glowSupported) {
    await acknowledge({ sessionId: initial.sessionId, sectionId: "DWEyeColor", action: "set", itemId: "glow", value: Math.round(glow * 10) / 10 }, "eye glow");
  }
  await acknowledge({ sessionId: initial.sessionId, sectionId: "DWEyeColor",
    action: color === null ? "invoke" : "set", itemId: color === null ? "restore" : "color", ...(color === null ? {} : { value: color.toLowerCase() }) }, "eye color");
}
