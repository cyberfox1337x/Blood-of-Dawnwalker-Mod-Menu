import { MathUtils, MOUSE, TOUCH, Vector3 } from "three";
import type { OrbitControls } from "three/addons/controls/OrbitControls.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_view_controls");

export type CharacterDragMode = "orbit" | "move";

export function configureCharacterControls(controls: OrbitControls, mode: CharacterDragMode): void {
  controls.enablePan = true;
  controls.enableRotate = true;
  controls.enableZoom = true;
  controls.screenSpacePanning = true;
  controls.cursorStyle = "grab";
  controls.mouseButtons.LEFT = mode === "move" ? MOUSE.PAN : MOUSE.ROTATE;
  controls.mouseButtons.RIGHT = MOUSE.PAN;
  controls.touches.ONE = mode === "move" ? TOUCH.PAN : TOUCH.ROTATE;
  controls.touches.TWO = TOUCH.DOLLY_PAN;
}

export function zoomCharacterView(controls: OrbitControls, factor: number): void {
  const offset = new Vector3().subVectors(controls.object.position, controls.target);
  const distance = offset.length();
  if (distance <= 0 || !Number.isFinite(factor) || factor <= 0) return;
  offset.setLength(MathUtils.clamp(distance * factor, controls.minDistance, controls.maxDistance));
  controls.object.position.copy(controls.target).add(offset);
  controls.update();
}
