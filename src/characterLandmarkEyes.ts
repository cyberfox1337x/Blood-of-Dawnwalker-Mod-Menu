import { Color, Mesh, MeshStandardMaterial, type Object3D, Vector3 } from 'three';
import { NATURAL_EYE_COLOR } from './characterEyeGeometry';

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function('character_landmark_eyes');

/**
 * An eye that is painted, not modelled. The current character's eyes are two tiny
 * parts (10-19 vertices each) whose 128 px textures carry the whole eye - lids, lashes,
 * sclera, iris and pupil. Nothing built in 3D can line up with that paint, so instead
 * the iris is recoloured where it is painted: texels inside a small window around the
 * painted iris that look like iris (dark, warm) take the chosen colour, keeping the
 * painted pupil and highlight as shading. The window is a real-world radius around the
 * painted pupil's model-space position: these textures are stretched differently per
 * eye, so a UV-space window could not fit both without also catching the lid crease.
 */
export type PaintedEye = Readonly<{
  /** glTF node name of the eye part. */
  node: string;
  /** Centre of the painted pupil in model space, measured from the part's texture. */
  pupil: readonly [number, number, number];
  /** Radius of the painted iris in model units (metres); the window is a little wider. */
  irisRadius: number;
}>;

// How much wider than the painted iris the recolour window is. It only bounds the
// search; the texel test decides what inside it is iris.
const WINDOW_SCALE = 1.2;
const PUPIL_FRACTION = 0.39;

// Where the face is pointing, from the eyes themselves: the line between the two eye
// centres is the head's horizontal axis, and the face normal is perpendicular to it and
// to "up". A turned head therefore gets its close-up camera where it is looking.
export function faceNormalFromEyes(centres: readonly Vector3[], fallback: Vector3): Vector3 {
  if (centres.length < 2) return fallback.clone().normalize();
  const across = centres[1].clone().sub(centres[0]);
  if (across.lengthSq() === 0) return fallback.clone().normalize();
  const normal = new Vector3().crossVectors(new Vector3(0, 1, 0), across.normalize());
  if (normal.dot(fallback) < 0) normal.negate();
  return normal.normalize();
}

export class PaintedEyeNotFound extends Error {
  constructor(node: string) { super(`The character model has no eye part named "${node}", so its eye colour cannot be shown.`); }
}

export function attachPaintedEyes(root: Object3D, eyes: readonly PaintedEye[], facing: readonly [number, number, number]) {
  const irisColor = { value: new Color(NATURAL_EYE_COLOR) };
  const irisGlow = { value: 0 };
  // 1 while a colour is chosen; 0 leaves the painted eye exactly as the artist made it.
  const irisEnabled = { value: 0 };
  // 1 while the preview renders its glow-only pass: the fragment then outputs the iris
  // emission alone, so the bloom that follows is fed nothing but neon.
  const glowPassOnly = { value: 0 };
  const meshes: Mesh[] = [];
  const originals = new Map<Mesh, MeshStandardMaterial>();
  const centres = eyes.map(eye => new Vector3(...eye.pupil));
  const normal = faceNormalFromEyes(centres, new Vector3(...facing));
  // Face-plane basis for the iris pattern: across the eyes, and up within the face.
  const across = centres.length >= 2 ? centres[1].clone().sub(centres[0]).normalize() : new Vector3(1, 0, 0);
  const up = new Vector3().crossVectors(normal, across).normalize();

  for (const eye of eyes) {
    const node = root.getObjectByName(eye.node);
    if (!(node instanceof Mesh) || !(node.material instanceof MeshStandardMaterial)) throw new PaintedEyeNotFound(eye.node);
    const source = node.material;
    const material = source.clone();
    material.onBeforeCompile = shader => {
      shader.uniforms.paintedIrisColor = irisColor;
      shader.uniforms.paintedIrisGlow = irisGlow;
      shader.uniforms.paintedIrisEnabled = irisEnabled;
      shader.uniforms.paintedGlowPassOnly = glowPassOnly;
      shader.uniforms.paintedPupil = { value: new Vector3(...eye.pupil) };
      shader.uniforms.paintedIrisRadius = { value: eye.irisRadius };
      shader.uniforms.paintedAcross = { value: across };
      shader.uniforms.paintedUp = { value: up };
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 paintedWorld;')
        .replace('#include <project_vertex>', '#include <project_vertex>\npaintedWorld = (modelMatrix * vec4(transformed, 1.0)).xyz;');
      shader.fragmentShader = shader.fragmentShader
        .replace('#include <common>', `#include <common>
      varying vec3 paintedWorld;
      uniform vec3 paintedIrisColor;
      uniform float paintedIrisGlow;
      uniform float paintedIrisEnabled;
      uniform float paintedGlowPassOnly;
      uniform vec3 paintedPupil;
      uniform float paintedIrisRadius;
      uniform vec3 paintedAcross;
      uniform vec3 paintedUp;`)
        .replace('#include <map_fragment>', `#include <map_fragment>
      // diffuseColor now holds the painted texel (linear). Iris texels are dark and
      // warm; the sclera and highlight are bright and grey, skin is brighter and pinker.
      vec3 paintedDelta = paintedWorld - paintedPupil;
      vec2 paintedOffset = vec2(dot(paintedDelta, paintedAcross), dot(paintedDelta, paintedUp)) / paintedIrisRadius;
      float paintedRadius = length(paintedDelta) / paintedIrisRadius;
      float paintedLuma = dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722));
      float paintedWarm = step(diffuseColor.b, diffuseColor.r) * step(diffuseColor.b, diffuseColor.g);
      float irisLike = (1.0 - smoothstep(0.10, 0.20, paintedLuma)) * max(paintedWarm, 1.0 - smoothstep(0.015, 0.04, paintedLuma));
      float irisWindow = 1.0 - smoothstep(${WINDOW_SCALE.toFixed(2)} - 0.15, ${WINDOW_SCALE.toFixed(2)}, paintedRadius);
      float irisMask = irisLike * irisWindow * paintedIrisEnabled;
      // The painted pupil stays dark and the painted highlight stays bright: the new
      // colour is shaded by the texel's own brightness.
      float paintedShade = smoothstep(0.012, 0.06, paintedLuma);
      float paintedAngle = atan(paintedOffset.y, paintedOffset.x);
      float fibers = 0.62 + 0.23 * sin(paintedAngle * 71.0 + paintedRadius * 19.0) + 0.13 * sin(paintedAngle * 133.0 - paintedRadius * 31.0);
      float rim = 1.0 - 0.45 * smoothstep(0.7, 1.05, paintedRadius);
      float pupil = 1.0 - smoothstep(${PUPIL_FRACTION - 0.03}, ${PUPIL_FRACTION + 0.03}, paintedRadius);
      vec3 iris = paintedIrisColor * (0.55 + 0.45 * fibers) * rim * mix(0.25, 1.0, paintedShade);
      iris = mix(iris, vec3(0.003, 0.002, 0.002), pupil * 0.85);
      diffuseColor.rgb = mix(diffuseColor.rgb, iris, irisMask);`)
        .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
      // Neon emission is the recoloured iris only, so lids, lashes and sclera keep
      // their normal lighting while the iris itself glows.
      vec3 neon = paintedIrisColor * irisMask * (1.0 - pupil) * paintedShade * paintedIrisGlow;
      totalEmissiveRadiance += neon * 0.35;`)
        .replace('#include <opaque_fragment>', `#include <opaque_fragment>
      // Glow-only pass: emit the neon and nothing else.
      if (paintedGlowPassOnly > 0.5) gl_FragColor = vec4(neon, 1.0);`);
    };
    material.customProgramCacheKey = () => 'painted-eye-v2';
    originals.set(node, source);
    node.material = material;
    meshes.push(node);
  }

  const meshSet = new Set<Object3D>(meshes);
  return {
    meshes,
    normal,
    /** Midpoint of the eyes: where an eye close-up should look. */
    focus: centres.length ? centres.reduce((sum, centre) => sum.add(centre), new Vector3()).divideScalar(centres.length) : null,
    isEyeMesh(object: Object3D) { return meshSet.has(object); },
    setColor(hex: string | null, glow = 0) {
      irisEnabled.value = hex === null ? 0 : 1;
      irisColor.value.set(hex ?? NATURAL_EYE_COLOR);
      irisGlow.value = hex === null ? 0 : Math.max(0, Math.min(glow, 3));
    },
    /** Whether the irises are currently emitting; false means no glow pass is needed. */
    get glowing() { return irisGlow.value > 0; },
    /** Switch the eye materials between their normal look and the glow-only output. */
    setGlowPassOnly(active: boolean) { glowPassOnly.value = active ? 1 : 0; },
    dispose() {
      originals.forEach((source, mesh) => { (mesh.material as MeshStandardMaterial).dispose(); mesh.material = source; });
      originals.clear();
    },
  };
}
