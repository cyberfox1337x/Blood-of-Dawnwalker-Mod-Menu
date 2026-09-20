import { Color, Vector3 } from 'three';
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function('character_reference_skin');
export const REFERENCE_SKIN_TINT = new Vector3(0.72, 0.70, 0.55);
export function applyReferenceSkinTone(color: Color) {
  const chroma = Math.max(0, Math.min(1, (color.r - color.b - 0.015) / 0.055));
  const brightness = Math.max(0, Math.min(1, (color.r - 0.025) / 0.06));
  const amount = chroma * brightness;
  color.r *= 1 + (REFERENCE_SKIN_TINT.x - 1) * amount;
  color.g *= 1 + (REFERENCE_SKIN_TINT.y - 1) * amount;
  color.b *= 1 + (REFERENCE_SKIN_TINT.z - 1) * amount;
  return color;
}
