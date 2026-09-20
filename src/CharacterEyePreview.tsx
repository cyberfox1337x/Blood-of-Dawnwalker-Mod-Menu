import { useEffect, useMemo, useRef, useState } from "react";
import { ACESFilmicToneMapping, AdditiveBlending, Box3, Color, HalfFloatType, HemisphereLight, type Material, Mesh, MeshBasicMaterial, MeshStandardMaterial, type Object3D, PerspectiveCamera, PMREMGenerator, Scene, ShaderMaterial, Vector2, Vector3, WebGLRenderer, WebGLRenderTarget } from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { FullScreenQuad } from "three/addons/postprocessing/Pass.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { MeshoptDecoder } from "three/addons/libs/meshopt_decoder.module.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { createCharacterEyeMaterial } from "./characterEyeMaterial";
import { createCharacterEyes, NATURAL_EYE_COLOR } from "./characterEyeGeometry";
import { attachPaintedEyes, type PaintedEye } from "./characterLandmarkEyes";

// What the preview may assume about the model it loads. Coen's export carried full
// PBR maps on every mesh and hand-tuned eye geometry, and the loader hard-coded both.
// The current model is a Tripo export: ~4 000 vertices in 46 parts, front along +Z,
// with every visible detail painted in its textures. Its eyes are two tiny parts whose
// 128 px textures hold the whole eye, so eye colour is applied by recolouring the
// painted iris in place (see characterLandmarkEyes.ts). The pupil positions below are
// the model-space centres of the darkest paint on each part, and the iris radius is
// where iris-like paint gives way to lid, both measured on 2026-09-11.
const CHARACTER_MODEL = {
  url: "./models/medieval-warrior.glb",
  requiresFullPbr: false,
  facing: [0, 0, 1] as const,
  // null: use the Coen-specific reconstruction (createCharacterEyes) instead.
  eyes: [
    { node: "tripo_part_40", pupil: [-0.0530, 0.9187, 0.0385] as const, irisRadius: 0.0032 },
    { node: "tripo_part_39", pupil: [-0.01798, 0.91901, 0.05278] as const, irisRadius: 0.0032 },
  ] as readonly PaintedEye[] | null,
};
import { configureCharacterControls, zoomCharacterView, type CharacterDragMode } from "./characterViewControls";
import { useCharacterPreviewActivation } from "./characterPreviewLifecycle";
import { createCharacterAppearanceMaterialController } from "./characterAppearanceMaterial";
import { NATURAL_CHARACTER_APPEARANCE, type CharacterAppearance } from "./characterAppearanceState";
import "./EyeAppearance.css";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_eye_preview");

const presets = [
  ["Blue", "#5c9bc8", 0], ["Green", "#589c60", 0], ["Hazel", "#a58a45", 0],
  ["Brown", "#805035", 0], ["Amber", "#d9952c", 0], ["Crimson", "#b52c35", 0],
  ["Neon Cyan", "#20f6ff", 2.2], ["Neon Violet", "#bd5cff", 2.2], ["Neon Lime", "#b8ff3d", 2.2],
  ["Neon Rose", "#ff3f9f", 2.2], ["Neon Gold", "#ffe45e", 1.8], ["Neon Inferno", "#ff4d28", 2.4],
] as const;
type Framing = "eyes" | "portrait" | "body";
type Viewer = { setActive: (active: boolean) => void; color: (hex: string | null, glow?: number) => void; appearance: (appearance: CharacterAppearance) => void; frame: (framing: Framing) => void; mode: (mode: CharacterDragMode) => void };

export function CharacterEyePreview({ active, appearance, onColorSelect, liveStatus }: Readonly<{ active: boolean; appearance?: CharacterAppearance; onColorSelect?: (color: string | null, glow: number) => void; liveStatus?: string }>) {
  const activated = useCharacterPreviewActivation(active);
  const activeRef = useRef(active);
  activeRef.current = active;
  const host = useRef<HTMLDivElement>(null);
  const viewer = useRef<Viewer | null>(null);
  const [color, setColor] = useState<string | null>(null);
  const [glow, setGlow] = useState(0);
  const displayedColor = appearance !== undefined ? appearance.eyeColor : color;
  const displayedGlow = appearance !== undefined ? appearance.eyeGlow : glow;
  const displayedAppearance = useMemo<CharacterAppearance>(() => appearance
    ?? { ...NATURAL_CHARACTER_APPEARANCE, eyeColor: color, eyeGlow: glow }, [appearance, color, glow]);
  const appearanceRef = useRef(displayedAppearance);
  appearanceRef.current = displayedAppearance;
  const [framing, setFraming] = useState<Framing>("body");
  const framingRef = useRef(framing);
  framingRef.current = framing;
  const [status, setStatus] = useState("Loading your character…");
  const [ready, setReady] = useState(false);
  const [dragMode, setDragMode] = useState<CharacterDragMode>("orbit");
  const dragModeRef = useRef(dragMode);
  dragModeRef.current = dragMode;

  useEffect(() => {
    const element = host.current;
    if (!activated || !element) return;
    setStatus("Loading your character…");
    if (typeof WebGL2RenderingContext === "undefined") {
      setStatus("The 3D preview needs WebGL 2 graphics support.");
      return;
    }
    let disposed = false;
    let renderer: WebGLRenderer;
    try { renderer = new WebGLRenderer({ antialias: true, alpha: false }); }
    catch { setStatus("The 3D preview needs WebGL graphics support."); return; }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.toneMapping = ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1;
    renderer.setClearColor(new Color("#090b0a"));
    renderer.domElement.setAttribute("aria-label", "Supplied full-body character, rotatable in 3D");
    renderer.domElement.setAttribute("aria-describedby", "character-view-help");
    renderer.domElement.tabIndex = 0;
    element.append(renderer.domElement);
    const scene = new Scene();
    const camera = new PerspectiveCamera(32, 1, 0.001, 10);
    const controls = new OrbitControls(camera, renderer.domElement);
    configureCharacterControls(controls, dragModeRef.current);
    controls.listenToKeyEvents(renderer.domElement);
    controls.minDistance = 0.06;
    controls.maxDistance = 3;
    const environment = new RoomEnvironment();
    const generator = new PMREMGenerator(renderer);
    const environmentMap = generator.fromScene(environment, 0.04);
    environment.dispose();
    generator.dispose();
    scene.environment = environmentMap.texture;
    scene.environmentIntensity = 0.8;
    scene.add(new HemisphereLight(0xffffff, 0x535448, 0.6));
    // Neon is a halo, not a brighter iris. A brightness-threshold bloom cannot tell a
    // glowing iris from the lit white of the eye next to it, so the glow is rendered
    // selectively: a pass in which every surface is black except the iris emission,
    // bloomed on its own, then added over the normal frame on screen. Skin and sclera
    // never bloom, and the iris keeps its colour.
    //
    // The normal frame itself is always drawn straight to the canvas, never through a
    // composer. Routing it through one changes the background: three writes the clear
    // colour into a render target already display-encoded, and the output pass then
    // tone-maps it, so #090b0a came out as a lighter grey-green - and in the glow pass
    // that same non-black backdrop bloomed into a wash over the whole picture. The glow
    // pass therefore clears to true black, and a plain colour never touches any of this.
    const glowPass = new EffectComposer(renderer, new WebGLRenderTarget(1, 1, { type: HalfFloatType }));
    glowPass.renderToScreen = false;
    glowPass.addPass(new RenderPass(scene, camera, undefined, new Color(0, 0, 0), 1));
    // A small threshold keeps anything that is not emission (rounding in the blackened
    // surfaces) out of the halo.
    const bloom = new UnrealBloomPass(new Vector2(1, 1), 1, 0.2, 0.05);
    glowPass.addPass(bloom);
    const glowOverlay = new FullScreenQuad(new ShaderMaterial({
      uniforms: { glowTexture: { value: glowPass.renderTarget2.texture } },
      vertexShader: "varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
      // The halo goes through the same tone mapping and display encoding as the frame
      // it lands on, so a neon colour on screen matches the swatch that chose it. The
      // bloom's widest level spreads a trace of light across the entire frame; the
      // small floor removes that, so the backdrop away from the eyes stays exactly the
      // clear colour and only the halo itself is added.
      fragmentShader: "uniform sampler2D glowTexture; varying vec2 vUv; void main() { gl_FragColor = vec4(max(texture2D(glowTexture, vUv).rgb - 0.012, 0.0), 1.0);\n#include <tonemapping_fragment>\n#include <colorspace_fragment>\n}",
      blending: AdditiveBlending,
      depthTest: false,
      depthWrite: false,
      transparent: true,
    }));
    // Everything that is not an iris is drawn with this during the glow pass.
    const unlitBlack = new MeshBasicMaterial({ color: 0x000000 });
    const blackenedMaterials = new Map<Mesh, Material | Material[]>();
    type GlowSource = { isEyeMesh: (object: Object3D) => boolean; glowing: boolean; setGlowPassOnly: (active: boolean) => void };
    const renderGlowPass = (source: GlowSource) => {
      scene.traverse(object => {
        if (!(object instanceof Mesh) || source.isEyeMesh(object)) return;
        blackenedMaterials.set(object, object.material);
        object.material = unlitBlack;
      });
      source.setGlowPassOnly(true);
      glowPass.render();
      source.setGlowPassOnly(false);
      blackenedMaterials.forEach((material, mesh) => { mesh.material = material; });
      blackenedMaterials.clear();
    };
    let glowSource: GlowSource | undefined;
    const setGlowStrength = (intensity: number) => { bloom.strength = Math.min(0.3 + intensity * 0.3, 1.5); };
    const render = () => {
      if (disposed || !activeRef.current) return;
      const glowing = Boolean(glowSource?.glowing);
      if (glowing && glowSource) renderGlowPass(glowSource);
      renderer.setRenderTarget(null);
      renderer.render(scene, camera);
      if (!glowing) return;
      // Added over the finished frame without clearing it.
      renderer.autoClear = false;
      glowOverlay.render(renderer);
      renderer.autoClear = true;
    };
    controls.addEventListener("change", render);
    const focusCanvas = () => renderer.domElement.focus({ preventScroll: true });
    const keyboardView = (event: KeyboardEvent) => {
      if (!activeRef.current || event.altKey || event.ctrlKey || event.metaKey) return;
      if (event.key === "Home") viewer.current?.frame(framingRef.current);
      else if (["+", "="].includes(event.key)) zoomCharacterView(controls, 0.9);
      else if (event.key === "-") zoomCharacterView(controls, 1.1);
      else return;
      event.preventDefault();
      event.stopPropagation();
    };
    renderer.domElement.addEventListener("pointerdown", focusCanvas);
    renderer.domElement.addEventListener("keydown", keyboardView);
    let previousWidth = 0, previousHeight = 0;
    const resize = () => {
      const { width, height } = element.getBoundingClientRect();
      if (width <= 0 || height <= 0 || (width === previousWidth && height === previousHeight)) return false;
      previousWidth = width; previousHeight = height;
      renderer.setSize(width, height, false);
      glowPass.setSize(width, height);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      render();
      return true;
    };
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    let reconstructedEyes: ReturnType<typeof createCharacterEyes> | undefined;
    let paintedEyes: ReturnType<typeof attachPaintedEyes> | undefined;
    let appearanceController: ReturnType<typeof createCharacterAppearanceMaterialController> | undefined;
    const disposeModel = (model: Scene | import("three").Group) => {
      const textures = new Set<import("three").Texture>();
      model.traverse(object => {
        if (!(object instanceof Mesh)) return;
        object.geometry.dispose();
        for (const material of Array.isArray(object.material) ? object.material : [object.material]) {
          for (const entry of Object.values(material)) if (entry && typeof entry === "object" && "isTexture" in entry) textures.add(entry as import("three").Texture);
          material.dispose();
        }
      });
      textures.forEach(texture => { texture.dispose(); const source = texture.source.data; if (typeof ImageBitmap !== "undefined" && source instanceof ImageBitmap) source.close(); });
    };
    const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
    void loader.loadAsync(CHARACTER_MODEL.url).then(gltf => {
      if (disposed) { disposeModel(gltf.scene); return; }
      let texturedMeshes = 0;
      let incompleteTextures = false;
      gltf.scene.traverse(object => {
        if (!(object instanceof Mesh)) return;
        const material = object.material;
        const complete = material instanceof MeshStandardMaterial && Boolean(material.map)
          && (!CHARACTER_MODEL.requiresFullPbr || Boolean(material.normalMap && material.roughnessMap));
        if (complete) texturedMeshes += 1; else incompleteTextures = true;
      });
      if (incompleteTextures || texturedMeshes === 0) {
        disposeModel(gltf.scene);
        throw new Error("The character's embedded textures could not be decoded.");
      }
      if (CHARACTER_MODEL.eyes === null) {
        // Coen path: his skin-tint shader and traced eyelid reconstruction.
        gltf.scene.traverse(object => {
          if (!(object instanceof Mesh) || !(object.material instanceof MeshStandardMaterial)) return;
          const eyes = createCharacterEyeMaterial(object.material);
          object.material.dispose();
          object.material = eyes.material;
        });
      }
      scene.add(gltf.scene);
      let eyeFocus: Vector3 | null = null;
      let eyeNormal: Vector3 | null = null;
      if (CHARACTER_MODEL.eyes === null) {
        reconstructedEyes = createCharacterEyes();
        reconstructedEyes.setColor(appearanceRef.current.eyeColor, appearanceRef.current.eyeGlow);
        scene.add(reconstructedEyes.group);
      } else {
        // Throws PaintedEyeNotFound if the model lacks a named eye part; the catch
        // below turns that into the status line rather than a silently uncoloured eye.
        const painted = attachPaintedEyes(gltf.scene, CHARACTER_MODEL.eyes, CHARACTER_MODEL.facing);
        paintedEyes = painted;
        glowSource = painted;
        eyeFocus = painted.focus;
        eyeNormal = painted.normal;
        painted.setColor(appearanceRef.current.eyeColor, appearanceRef.current.eyeGlow);
      }
      appearanceController = createCharacterAppearanceMaterialController(gltf.scene);
      appearanceController.apply(appearanceRef.current);
      setGlowStrength(appearanceRef.current.eyeGlow);
      const bounds = new Box3().setFromObject(gltf.scene);
      const height = bounds.max.y - bounds.min.y;
      const center = bounds.getCenter(new Vector3());
      const facing = new Vector3(...CHARACTER_MODEL.facing).normalize();
      const frame = (next: Framing) => {
        // The eye close-up looks at the measured eye midpoint along the face normal;
        // the other framings use the model's bounds, which is what they are about.
        const focus = next === "eyes" && eyeFocus ? eyeFocus.clone() : center.clone();
        if (!(next === "eyes" && eyeFocus)) focus.y = next === "body" ? center.y : bounds.max.y - height * (next === "eyes" ? 0.083 : 0.14);
        const direction = next === "eyes" && eyeNormal ? eyeNormal : facing;
        const distance = height * (next === "body" ? 1.9 : next === "eyes" ? 0.12 : 0.56);
        controls.target.copy(focus);
        camera.up.set(0, 1, 0);
        camera.position.copy(focus).add(direction.clone().multiplyScalar(distance));
        if (!controls.update()) render();
      };
      viewer.current = {
        setActive: value => { controls.enabled = value; if (value && !resize()) render(); },
        color: (hex, intensity = 0) => { (paintedEyes ?? reconstructedEyes)?.setColor(hex, intensity); setGlowStrength(hex === null ? 0 : intensity); render(); },
        appearance: next => {
          appearanceController?.apply(next);
          (paintedEyes ?? reconstructedEyes)?.setColor(next.eyeColor, next.eyeGlow);
          setGlowStrength(next.eyeColor === null ? 0 : next.eyeGlow);
          render();
        },
        frame,
        mode: next => configureCharacterControls(controls, next),
      };
      controls.enabled = activeRef.current;
      frame(framingRef.current);
      resize();
      setReady(true);
      setStatus("");
    }).catch((error: unknown) => { if (!disposed) setStatus(`Character could not be loaded: ${error instanceof Error ? error.message : "unknown loading error"}`); });
    resize();
    return () => {
      disposed = true;
      viewer.current = null;
      setReady(false);
      observer.disconnect();
      renderer.domElement.removeEventListener("pointerdown", focusCanvas);
      renderer.domElement.removeEventListener("keydown", keyboardView);
      controls.dispose();
      appearanceController?.dispose();
      if (reconstructedEyes) { scene.remove(reconstructedEyes.group); reconstructedEyes.dispose(); }
      paintedEyes?.dispose();
      disposeModel(scene);
      environmentMap.dispose();
      bloom.dispose();
      glowPass.dispose();
      (glowOverlay.material as ShaderMaterial).dispose();
      glowOverlay.dispose();
      unlitBlack.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, [activated]);

  useEffect(() => { viewer.current?.setActive(active); }, [active]);
  useEffect(() => { viewer.current?.appearance(displayedAppearance); }, [displayedAppearance]);

  const selectColor = (hex: string | null, intensity = 0) => { setColor(hex); setGlow(intensity); viewer.current?.color(hex, intensity); onColorSelect?.(hex, hex === null ? 0 : intensity); };
  // Changing the glow with a colour selected re-applies that colour at the new strength,
  // in the preview and in game; with no colour there is nothing to glow.
  const selectGlow = (intensity: number) => { setGlow(intensity); if (displayedColor !== null) { viewer.current?.color(displayedColor, intensity); onColorSelect?.(displayedColor, intensity); } };
  const frame = (next: Framing) => { setFraming(next); viewer.current?.frame(next); };
  const selectMode = (next: CharacterDragMode) => { setDragMode(next); viewer.current?.mode(next); };
  return <section className="eye-appearance character-eye-preview" aria-label="Character Eye Appearance">
    <header className="eye-heading"><div><span className="eye-kicker">Your character</span><h3>Eye Appearance</h3></div><span className="eye-application-status">{onColorSelect ? "Game + Preview" : "Preview Only"}</span></header>
    <div className="eye-workspace">
      <div className="eye-preview-panel">
        <div className="eye-preview-topline"><span>Full 3D character</span><span>{framing === "body" ? "Full body" : framing === "eyes" ? "Eyes close-up" : "Head & shoulders"}</span></div>
        <div className={`character-model-surface is-${dragMode}-mode`}><div className="character-canvas-host" ref={host} />{status && <p className="eye-frame-empty" role="status">{status}</p>}</div>
        <p id="character-view-help" className="eye-input-help">Drag to {dragMode === "move" ? "move" : "orbit"}. Right-drag moves; scroll zooms.<span className="sr-only"> Two fingers move and zoom. Arrow keys move; Ctrl + arrows orbit. + / − zoom; Home or Reset View restores framing.</span></p>
      </div>
      <div className="eye-controls-panel">
        <div className="eye-view-actions character-view-actions">{([ ["eyes", "Eyes Close-Up", "Eyes"], ["portrait", "Head & Shoulders", "Portrait"], ["body", "Full Body", "Full Body"] ] as const).map(([id, label, text]) => <button key={id} aria-label={label} disabled={!ready} aria-pressed={framing === id} onClick={() => frame(id)}>{text}</button>)}</div>
        <div className="character-manipulation-actions" role="group" aria-label="Character view controls">
          <button disabled={!ready} aria-pressed={dragMode === "orbit"} onClick={() => selectMode("orbit")}>Orbit</button>
          <button disabled={!ready} aria-pressed={dragMode === "move"} onClick={() => selectMode("move")}>Move</button>
          <button disabled={!ready} onClick={() => frame(framing)}>Reset View</button>
        </div>
        <fieldset className="eye-presets" disabled={!ready && !onColorSelect}><legend>Eye color &amp; neon glow</legend><div>{presets.map(([label, hex, intensity]) => <button key={label} aria-pressed={displayedColor === hex} data-neon={intensity > 0 ? "true" : undefined} onClick={() => selectColor(hex, intensity)}><span className="eye-color-swatch" style={{ backgroundColor: hex, boxShadow: intensity > 0 ? `0 0 ${Math.round(6 + intensity * 3)}px ${hex}` : undefined }} />{label}</button>)}</div></fieldset>
        <label className="eye-glow-field"><span>Glow strength</span><span><input type="range" aria-label="Eye glow strength" min={0} max={3} step={0.1} disabled={(!ready && !onColorSelect) || displayedColor === null} value={displayedGlow} onChange={event => selectGlow(Number(event.target.value))} /><output>{displayedGlow === 0 ? "Off" : displayedGlow.toFixed(1)}</output></span></label>
        <label className="eye-color-field"><span>Custom eye color</span><span><input type="color" aria-label="Character iris color" disabled={!ready && !onColorSelect} value={displayedColor ?? NATURAL_EYE_COLOR} onChange={event => selectColor(event.target.value)} /><output>{displayedColor?.toUpperCase() ?? "Natural brown"}</output></span></label>
        <div className="eye-restore-block"><button disabled={(!ready || displayedColor === null) && !onColorSelect} onClick={() => selectColor(null)}>Restore Original Eyes</button><p>Restores the original game eyes and the model's natural eyes.</p></div>
        <p className="eye-mode-note">{liveStatus ?? "Preview only."}</p>
      </div>
    </div>
  </section>;
}
