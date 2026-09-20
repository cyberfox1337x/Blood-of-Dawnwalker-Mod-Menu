import { MeshStandardMaterial, Vector3 } from 'three';
import { REFERENCE_SKIN_TINT } from './characterSkinTone';
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function('character_eye_material');
export const characterIrisRegions = [
  { center: [0.07277454, 0.40916342, 0.0192400] as const },
  { center: [0.07249487, 0.40942341, -0.0188500] as const },
];
export function createCharacterEyeMaterial(source: MeshStandardMaterial) {
  const material = source.clone();
  material.onBeforeCompile = shader => { shader.uniforms.referenceSkinTint = { value: REFERENCE_SKIN_TINT };
    shader.uniforms.characterLeftIris = { value: new Vector3(...characterIrisRegions[0].center) };
    shader.uniforms.characterRightIris = { value: new Vector3(...characterIrisRegions[1].center) };
    shader.vertexShader = shader.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 characterSurfacePosition;')
      .replace('#include <project_vertex>', '#include <project_vertex>\ncharacterSurfacePosition = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    shader.fragmentShader = shader.fragmentShader.replace('#include <common>', `#include <common>
      varying vec3 characterSurfacePosition;
      uniform vec3 referenceSkinTint; uniform vec3 characterLeftIris;
      uniform vec3 characterRightIris;`).replace('#include <map_fragment>', `#include <map_fragment>
      float headSkin = smoothstep(0.325, 0.345, characterSurfacePosition.y);
      float handsSkin = (1.0 - smoothstep(0.035, 0.055, characterSurfacePosition.y)) * smoothstep(-0.11, -0.09, characterSurfacePosition.y) * smoothstep(0.115, 0.135, abs(characterSurfacePosition.z));
      float neckSkin = smoothstep(0.28, 0.30, characterSurfacePosition.y) * (1.0 - smoothstep(0.024, 0.037, abs(characterSurfacePosition.z))) * smoothstep(0.025, 0.045, characterSurfacePosition.x);
      float skinChroma = clamp((diffuseColor.r - diffuseColor.b - 0.015) / 0.055, 0.0, 1.0);
      float skinBrightness = clamp((diffuseColor.r - 0.025) / 0.06, 0.0, 1.0);
      float skinMask = max(max(headSkin, handsSkin), neckSkin) * skinChroma * skinBrightness;
      diffuseColor.rgb *= mix(vec3(1.0), referenceSkinTint, skinMask);
      vec2 leftOffset = (characterSurfacePosition.yz - characterLeftIris.yz) / vec2(0.0032, 0.0078);
      vec2 rightOffset = (characterSurfacePosition.yz - characterRightIris.yz) / vec2(0.0032, 0.0078);
      if (characterSurfacePosition.x > 0.06 && min(length(leftOffset), length(rightOffset)) < 0.89) discard;`);
  };
  material.customProgramCacheKey = () => 'supplied-character-repaired-skin-v3';
  return { material };
}



