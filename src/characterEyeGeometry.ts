import { BufferGeometry, Color, DoubleSide, Float32BufferAttribute, Group, Mesh, MeshPhysicalMaterial, MeshStandardMaterial, SRGBColorSpace, Vector3 } from 'three';
import { applyReferenceSkinTone } from './characterSkinTone';
import { characterEyeBoundary } from './characterEyeBoundary';
import { characterIrisRegions } from './characterEyeMaterial';

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function('character_eye_geometry');
export const NATURAL_EYE_COLOR = '#805035';
const segments = 64;
const rings = 16;

function makeGeometry(positions: number[], colors: number[] | null, ringCount: number) {
  const geometry = new BufferGeometry();
  geometry.setAttribute('position', new Float32BufferAttribute(positions, 3));
  if (colors) geometry.setAttribute('color', new Float32BufferAttribute(colors, 3));
  const indices: number[] = [];
  for (let r = 0; r < ringCount - 1; r++) for (let i = 0; i < segments; i++) {
    const a = r * segments + i, b = r * segments + (i + 1) % segments;
    const c = a + segments, d = b + segments;
    indices.push(a, c, b, b, c, d);
  }
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

export function createCharacterEyes() {
  const group = new Group();
  group.name = 'Repaired eyes';
  const irisColor = { value: new Color(NATURAL_EYE_COLOR) };
  const irisGlow = { value: 0 };
  const materials: (MeshStandardMaterial | MeshPhysicalMaterial)[] = [];
  characterIrisRegions.forEach((region, eye) => {
    const center = new Vector3(...region.center);
    const globe = (theta: number, fraction: number) => {
      const horizontal = -0.0068 * Math.cos(theta) * fraction;
      const vertical = 0.00185 * Math.sin(theta) * Math.pow(Math.abs(Math.sin(theta)), 0.35) * fraction;
      const depth = center.x + 0.0012 - 0.0018 * (horizontal / 0.0068) ** 2 - 0.0003 * (vertical / 0.00165) ** 2;
      return new Vector3(depth, center.y + vertical, center.z + horizontal);
    };
    const positions: number[] = [];
    for (let r = 0; r <= rings; r++) for (let i = 0; i < segments; i++) positions.push(...globe(i * 2 * Math.PI / segments, r / rings).toArray());
    const eyeMaterial = new MeshPhysicalMaterial({ color: '#b9b1a7', roughness: 0.19, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.08, side: DoubleSide });
    eyeMaterial.onBeforeCompile = shader => {
      shader.uniforms.repairedIrisColor = irisColor;
      shader.uniforms.repairedIrisGlow = irisGlow;
      shader.uniforms.repairedEyeCenter = { value: center };
      shader.vertexShader = shader.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 repairedEyePosition;').replace('#include <project_vertex>', '#include <project_vertex>\nrepairedEyePosition = position;');
      shader.fragmentShader = shader.fragmentShader.replace('#include <common>', `#include <common>
      varying vec3 repairedEyePosition;
      uniform vec3 repairedIrisColor;
      uniform vec3 repairedEyeCenter;`).replace('#include <map_fragment>', `#include <map_fragment>
      vec2 offset = repairedEyePosition.yz - repairedEyeCenter.yz - vec2(0.00035, 0.0);
      float radius = length(offset) / 0.0032;
      float angle = atan(offset.x, offset.y);
      float fibers = 0.62 + 0.23 * sin(angle * 71.0 + radius * 19.0) + 0.13 * sin(angle * 133.0 - radius * 31.0);
      float rim = 1.0 - 0.83 * smoothstep(0.72, 1.0, radius);
      vec3 iris = repairedIrisColor * fibers * rim;
      float pupil = 1.0 - smoothstep(0.37, 0.41, radius);
      iris = mix(iris, vec3(0.003, 0.002, 0.002), pupil);
      float irisMask = 1.0 - smoothstep(0.97, 1.015, radius);
      float corner = smoothstep(0.55, 1.0, abs(offset.y) / 0.0068);
      vec3 sclera = mix(diffuseColor.rgb, vec3(0.30, 0.15, 0.12), corner * 0.22);
      float lidShadow = 0.42 + 0.58 * (1.0 - smoothstep(-0.0006, 0.0018, offset.x));
      diffuseColor.rgb = mix(sclera, iris, irisMask) * lidShadow;`).replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
      totalEmissiveRadiance += iris * irisMask * repairedIrisGlow;`);
    };
    eyeMaterial.customProgramCacheKey = () => 'repaired-eye-v1';
    const eyeball = new Mesh(makeGeometry(positions, null, rings + 1), eyeMaterial);
    eyeball.name = `Clean eye ${eye + 1}`;
    group.add(eyeball);
    materials.push(eyeMaterial);

    const lidPositions: number[] = [], lidColors: number[] = [];
    for (let r = 0; r <= 8; r++) for (let i = 0; i < segments; i++) {
      const fraction = r / 8;
      const boundary = characterEyeBoundary[eye][i];
      const inner = globe(i * 2 * Math.PI / segments, 1);
      inner.x += 0.00007;
      const outer = new Vector3(...boundary.position);
      outer.x += 0.00002;
      const point = inner.lerp(outer, fraction);
      point.x += Math.sin(fraction * Math.PI) * 0.00008;
      lidPositions.push(...point.toArray());
      const skin = new Color().setRGB(boundary.skin[0], boundary.skin[1], boundary.skin[2], SRGBColorSpace);
      const edge = new Color().setRGB(boundary.color[0], boundary.color[1], boundary.color[2], SRGBColorSpace);
      applyReferenceSkinTone(skin); applyReferenceSkinTone(edge);
      skin.lerp(edge, Math.max(0, (fraction - 0.5) * 2));
      if (r === 0) skin.multiplyScalar(Math.sin(i * 2 * Math.PI / segments) > 0 ? 0.24 : 0.72);
      lidColors.push(skin.r, skin.g, skin.b);
    }
    const lidMaterial = new MeshStandardMaterial({ vertexColors: true, roughness: 0.68, metalness: 0, side: DoubleSide, transparent: true, depthWrite: false });
    lidMaterial.onBeforeCompile = shader => {
      shader.uniforms.lidCenter = { value: center };
      shader.vertexShader = shader.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 lidPosition;').replace('#include <project_vertex>', '#include <project_vertex>\nlidPosition = position;');
      shader.fragmentShader = shader.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 lidPosition;\nuniform vec3 lidCenter;').replace('#include <alphamap_fragment>', '#include <alphamap_fragment>\nfloat edgeRadius = length((lidPosition.yz - lidCenter.yz) / vec2(0.0032, 0.0078));\ndiffuseColor.a *= 1.0 - smoothstep(0.90, 1.0, edgeRadius);');
    };
    lidMaterial.customProgramCacheKey = () => 'repaired-lid-feather-v1';
    const lids = new Mesh(makeGeometry(lidPositions, lidColors, 9), lidMaterial);
    lids.name = `Repaired eyelids ${eye + 1}`;
    group.add(lids);
    materials.push(lidMaterial);
  });
  return {
    group,
    setColor(hex: string | null, glow = 0) { irisColor.value.set(hex ?? NATURAL_EYE_COLOR); irisGlow.value = hex === null ? 0 : Math.max(0, Math.min(glow, 3)); },
    dispose() { group.traverse(object => { if (object instanceof Mesh) object.geometry.dispose(); }); materials.forEach(material => material.dispose()); },
  };
}




