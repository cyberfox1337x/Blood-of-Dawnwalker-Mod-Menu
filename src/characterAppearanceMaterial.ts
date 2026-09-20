import { Color, Mesh, MeshStandardMaterial, type Object3D, Vector3, type WebGLRenderer, type WebGLProgramParametersWithUniforms } from "three";
import type { CharacterAppearance } from "./characterAppearanceState";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_appearance_material");

type Compile = (shader: WebGLProgramParametersWithUniforms, renderer: WebGLRenderer) => void;
type MaterialRecord = Readonly<{ material: MeshStandardMaterial; onBeforeCompile: Compile; cacheKey: () => string }>;

// The shipped GLB uses anonymous generated names, so these sets are a measured model
// contract. Limiting shader work to the parts whose texture atlases contain the named
// feature prevents clothing and painted-eye parts from entering appearance math.
const SKIN_SURFACE_NODES = new Set([
  "tripo_part_2", "tripo_part_9", "tripo_part_17", "tripo_part_20", "tripo_part_22", "tripo_part_23",
  "tripo_part_24", "tripo_part_25", "tripo_part_28", "tripo_part_29", "tripo_part_31", "tripo_part_32",
  "tripo_part_33", "tripo_part_34", "tripo_part_35", "tripo_part_36", "tripo_part_37", "tripo_part_42",
  "tripo_part_44", "tripo_part_45",
]);
const HAIR_SURFACE_NODES = new Set([
  // Atlas 2 mixes face and fur collar; darkness alone cannot distinguish its fur.
  // These five measured atlases carry the scalp, side locks and trailing hair.
  "tripo_part_8", "tripo_part_16", "tripo_part_18", "tripo_part_30", "tripo_part_38",
]);
const BROW_SURFACE_NODES = new Set(["tripo_part_2"]);

/**
 * Adds preview-only colour layers to the shipped painted model. Every layer works on
 * the sampled texel after map_fragment, so the texture's pores, strands and shading
 * remain. The bounded world-space masks correspond to the shipped model's measured
 * head, hands and pupil landmarks; clothing outside them cannot be recoloured.
 */
export function createCharacterAppearanceMaterialController(root: Object3D) {
  const skinMultiplier = { value: new Vector3(1, 1, 1) };
  const skinEnabled = { value: 0 };
  const hairColor = { value: new Color("#17120f") };
  const hairEnabled = { value: 0 };
  const browColor = { value: new Color("#17120f") };
  const browEnabled = { value: 0 };
  const records: MaterialRecord[] = [];
  const seen = new Set<MeshStandardMaterial>();

  root.traverse(object => {
    if (!(object instanceof Mesh)) return;
    const skinSurface = SKIN_SURFACE_NODES.has(object.name);
    const hairSurface = HAIR_SURFACE_NODES.has(object.name);
    const browSurface = BROW_SURFACE_NODES.has(object.name);
    if (!skinSurface && !hairSurface && !browSurface) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    for (const candidate of materials) {
      if (!(candidate instanceof MeshStandardMaterial) || seen.has(candidate)) continue;
      seen.add(candidate);
      const material = candidate;
      const skinSurfaceUniform = { value: skinSurface ? 1 : 0 };
      const hairSurfaceUniform = { value: hairSurface ? 1 : 0 };
      const browSurfaceUniform = { value: browSurface ? 1 : 0 };
      const previousCompile = material.onBeforeCompile;
      const previousCacheKey = material.customProgramCacheKey;
      records.push({ material, onBeforeCompile: previousCompile, cacheKey: previousCacheKey });
      material.onBeforeCompile = (shader, renderer) => {
        previousCompile.call(material, shader, renderer);
        shader.uniforms.characterSkinMultiplier = skinMultiplier;
        shader.uniforms.characterSkinEnabled = skinEnabled;
        shader.uniforms.characterSkinSurface = skinSurfaceUniform;
        shader.uniforms.characterHairColor = hairColor;
        shader.uniforms.characterHairEnabled = hairEnabled;
        shader.uniforms.characterHairSurface = hairSurfaceUniform;
        shader.uniforms.characterBrowColor = browColor;
        shader.uniforms.characterBrowEnabled = browEnabled;
        shader.uniforms.characterBrowSurface = browSurfaceUniform;
        shader.vertexShader = shader.vertexShader
          .replace("#include <common>", "#include <common>\nvarying vec3 characterAppearanceWorld;")
          .replace("#include <project_vertex>", "#include <project_vertex>\ncharacterAppearanceWorld = (modelMatrix * vec4(transformed, 1.0)).xyz;");
        shader.fragmentShader = shader.fragmentShader
          .replace("#include <common>", `#include <common>
varying vec3 characterAppearanceWorld;
uniform vec3 characterSkinMultiplier;
uniform float characterSkinEnabled;
uniform float characterSkinSurface;
uniform vec3 characterHairColor;
uniform float characterHairEnabled;
uniform float characterHairSurface;
uniform vec3 characterBrowColor;
uniform float characterBrowEnabled;
uniform float characterBrowSurface;`)
          .replace("#include <map_fragment>", `#include <map_fragment>
// Skin is limited to skin-like painted texels on the measured head and hands.
float characterLuma = dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722));
float characterSkinChroma = smoothstep(0.012, 0.075, diffuseColor.r - diffuseColor.b)
  * smoothstep(0.65, 1.0, diffuseColor.r / max(diffuseColor.g, 0.001));
vec3 characterHeadLocal = (characterAppearanceWorld - vec3(-0.035, 0.925, 0.025)) / vec3(0.115, 0.145, 0.105);
float characterHeadVolume = 1.0 - smoothstep(0.92, 1.08, length(characterHeadLocal));
float characterHeadRegion = smoothstep(0.78, 0.84, characterAppearanceWorld.y) * characterHeadVolume;
float characterHandHeight = smoothstep(0.43, 0.50, characterAppearanceWorld.y)
  * (1.0 - smoothstep(0.72, 0.78, characterAppearanceWorld.y));
float characterHandSides = smoothstep(0.085, 0.125, abs(characterAppearanceWorld.x));
float characterSkinMask = max(characterHeadRegion, characterHandHeight * characterHandSides)
  * characterSkinChroma * smoothstep(0.025, 0.12, characterLuma) * characterSkinEnabled * characterSkinSurface;
diffuseColor.rgb *= mix(vec3(1.0), characterSkinMultiplier, characterSkinMask);

// Scalp hair uses dark painted strands in the head region. Texture luminance
// remains the shading term, while the selected swatch supplies the pigment.
vec3 characterBrowLeft = (characterAppearanceWorld - vec3(-0.0530, 0.9350, 0.0385)) / vec3(0.014, 0.0055, 0.008);
vec3 characterBrowRight = (characterAppearanceWorld - vec3(-0.0180, 0.9350, 0.0528)) / vec3(0.014, 0.0055, 0.008);
float characterBrowRegion = 1.0 - smoothstep(0.78, 1.0, min(length(characterBrowLeft), length(characterBrowRight)));
vec3 characterEyeLeft = (characterAppearanceWorld - vec3(-0.0530, 0.9187, 0.0385)) / vec3(0.008, 0.006, 0.008);
vec3 characterEyeRight = (characterAppearanceWorld - vec3(-0.0180, 0.9190, 0.0528)) / vec3(0.008, 0.006, 0.008);
float characterEyeRegion = 1.0 - smoothstep(0.85, 1.05, min(length(characterEyeLeft), length(characterEyeRight)));
float characterHairRegion = characterHeadVolume * characterHairSurface
  * (1.0 - max(characterBrowRegion, characterEyeRegion));
float characterHairTexel = 1.0 - smoothstep(0.10, 0.31, characterLuma);
float characterHairMask = characterHairRegion * characterHairTexel * characterHairEnabled;
vec3 characterHairShade = characterHairColor * (0.32 + characterLuma * 2.5);
diffuseColor.rgb = mix(diffuseColor.rgb, characterHairShade, characterHairMask);

// Eyebrows are independent ellipsoids measured just above the two painted pupils.
float characterBrowMask = characterBrowRegion * characterHairTexel * characterBrowEnabled * characterBrowSurface;
vec3 characterBrowShade = characterBrowColor * (0.35 + characterLuma * 2.2);
diffuseColor.rgb = mix(diffuseColor.rgb, characterBrowShade, characterBrowMask);`);
      };
      material.customProgramCacheKey = () => `${previousCacheKey.call(material)}|character-appearance-v1`;
      material.needsUpdate = true;
    }
  });

  return {
    apply(appearance: CharacterAppearance) {
      const [red, green, blue] = appearance.skinTint;
      skinMultiplier.value.set(red / 50, green / 50, blue / 50);
      skinEnabled.value = red === 50 && green === 50 && blue === 50 ? 0 : 1;
      hairEnabled.value = appearance.hairColor === null ? 0 : 1;
      if (appearance.hairColor) hairColor.value.set(appearance.hairColor);
      browEnabled.value = appearance.eyebrowColor === null ? 0 : 1;
      if (appearance.eyebrowColor) browColor.value.set(appearance.eyebrowColor);
    },
    dispose() {
      for (const record of records) {
        record.material.onBeforeCompile = record.onBeforeCompile;
        record.material.customProgramCacheKey = record.cacheKey;
        record.material.needsUpdate = true;
      }
      records.length = 0;
      seen.clear();
    },
  };
}
