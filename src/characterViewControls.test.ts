import { describe, expect, it } from "vitest";
import { PerspectiveCamera, Vector3 } from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { configureCharacterControls, zoomCharacterView, type CharacterDragMode } from "./characterViewControls";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_view_controls_tests");

function createControls(mode: CharacterDragMode) {
  const canvas = document.createElement("canvas");
  Object.defineProperties(canvas, { clientWidth: { value: 800 }, clientHeight: { value: 600 } });
  canvas.setPointerCapture = () => undefined;
  canvas.releasePointerCapture = () => undefined;
  const camera = new PerspectiveCamera(32, 4 / 3, 0.001, 10);
  camera.position.set(0, 0, 2);
  const controls = new OrbitControls(camera, canvas);
  controls.minDistance = 0.06;
  controls.maxDistance = 3;
  configureCharacterControls(controls, mode);
  controls.update();
  return { canvas, camera, controls };
}

function drag(canvas: HTMLCanvasElement, button: number) {
  for (const [type, x] of [["pointerdown", 400], ["pointermove", 460], ["pointerup", 460]] as const) {
    const event = new MouseEvent(type, { button, clientX: x, clientY: 300, bubbles: true });
    Object.defineProperties(event, { pointerId: { value: 1 }, pointerType: { value: "mouse" } });
    (type === "pointerdown" ? canvas : canvas.ownerDocument).dispatchEvent(event);
  }
}

describe("character camera controls", () => {
  it("left-drags the complete view in Move mode without changing viewing direction", () => {
    const { canvas, camera, controls } = createControls("move");
    const before = camera.position.clone();
    drag(canvas, 0);
    expect(controls.target.length()).toBeGreaterThan(0.01);
    expect(camera.position.clone().sub(before).distanceTo(controls.target)).toBeLessThan(1e-10);
    controls.dispose();
  });

  it("orbits with left drag and still pans with right drag in Orbit mode", () => {
    const { canvas, camera, controls } = createControls("orbit");
    drag(canvas, 0);
    expect(controls.target.length()).toBe(0);
    expect(camera.position.distanceTo(new Vector3(0, 0, 2))).toBeGreaterThan(0.1);
    expect(camera.position.length()).toBeCloseTo(2);
    const before = camera.position.clone();
    drag(canvas, 2);
    expect(controls.target.length()).toBeGreaterThan(0.01);
    expect(camera.position.clone().sub(before).distanceTo(controls.target)).toBeLessThan(1e-10);
    controls.dispose();
  });

  it("zooms toward a panned target and respects the distance limits", () => {
    const { controls, camera } = createControls("move");
    controls.target.set(0.1, 0.2, 0.3);
    camera.position.copy(controls.target).add(new Vector3(0, 0, 2));
    const target = controls.target.clone();
    zoomCharacterView(controls, 0.5);
    expect(camera.position.distanceTo(target)).toBeCloseTo(1);
    zoomCharacterView(controls, 0.0001);
    expect(camera.position.distanceTo(target)).toBeCloseTo(0.06);
    zoomCharacterView(controls, 1000);
    expect(camera.position.distanceTo(target)).toBeCloseTo(3);
    expect(controls.target.equals(target)).toBe(true);
    controls.dispose();
  });
});
