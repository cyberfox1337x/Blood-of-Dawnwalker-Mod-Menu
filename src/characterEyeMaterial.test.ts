import { describe, expect, it } from "vitest";
import { BoxGeometry, Group, Mesh, MeshStandardMaterial, Texture, WebGLRenderer } from "three";
import { createCharacterEyeMaterial } from "./characterEyeMaterial";
import { createCharacterEyes, NATURAL_EYE_COLOR } from "./characterEyeGeometry";
import { attachPaintedEyes, PaintedEyeNotFound, type PaintedEye } from "./characterLandmarkEyes";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_eye_material_tests");

describe("supplied character iris material", () => {
  it("preserves the original PBR maps while masking the replaced eye surfaces", () => {
    const source = new MeshStandardMaterial({ map: new Texture(), normalMap: new Texture(), roughnessMap: new Texture() });
    const originalCompile = source.onBeforeCompile;
    const eyes = createCharacterEyeMaterial(source);
    expect(eyes.material).not.toBe(source);
    expect(eyes.material.map).toBe(source.map);
    expect(eyes.material.normalMap).toBe(source.normalMap);
    expect(eyes.material.roughnessMap).toBe(source.roughnessMap);
    const shader = { uniforms: {}, vertexShader: "#include <common>\n#include <project_vertex>", fragmentShader: "#include <common>\n#include <map_fragment>" } as Parameters<typeof eyes.material.onBeforeCompile>[0];
    eyes.material.onBeforeCompile(shader, {} as WebGLRenderer);
    expect(shader.uniforms.characterLeftIris.value.z).toBeGreaterThan(0);
    expect(shader.uniforms.characterRightIris.value.z).toBeLessThan(0);
    expect(source.onBeforeCompile).toBe(originalCompile);
    source.dispose();
    eyes.material.dispose();
  });

  it("updates both reconstructed irises together and restores their natural color", () => {
    const eyes = createCharacterEyes();
    const shaders: Parameters<MeshStandardMaterial["onBeforeCompile"]>[0][] = [];
    eyes.group.traverse(object => {
      if (!(object instanceof Mesh)) return;
      expect(Array.from(object.geometry.attributes.position.array).every(Number.isFinite)).toBe(true);
      const material = object.material as MeshStandardMaterial;
      const shader = { uniforms: {}, vertexShader: "#include <common>\n#include <project_vertex>", fragmentShader: "#include <common>\n#include <map_fragment>" } as Parameters<typeof material.onBeforeCompile>[0];
      material.onBeforeCompile(shader, {} as WebGLRenderer);
      if (shader.uniforms.repairedIrisColor) shaders.push(shader);
    });
    expect(shaders).toHaveLength(2);
    eyes.setColor("#22cc88");
    for (const shader of shaders) expect(shader.uniforms.repairedIrisColor.value.getHexString()).toBe("22cc88");
    eyes.setColor(null);
    for (const shader of shaders) expect(shader.uniforms.repairedIrisColor.value.getHexString()).toBe(NATURAL_EYE_COLOR.slice(1));
    eyes.dispose();
  });

  it("recolours the painted irises in place and keeps neon glow iris-only", () => {
    const root = new Group();
    const originals: MeshStandardMaterial[] = [];
    for (const [name, x] of [["eye_left", -0.03], ["eye_right", 0.03]] as const) {
      const material = new MeshStandardMaterial({ map: new Texture() });
      originals.push(material);
      const mesh = new Mesh(new BoxGeometry(0.01, 0.01, 0.01), material);
      mesh.name = name;
      mesh.position.set(x, 0.9, 0.05);
      root.add(mesh);
    }
    root.updateMatrixWorld(true);
    const eyes: readonly PaintedEye[] = [
      { node: "eye_left", pupil: [-0.03, 0.9, 0.05], irisRadius: 0.003 },
      { node: "eye_right", pupil: [0.03, 0.9, 0.05], irisRadius: 0.0032 },
    ];
    const painted = attachPaintedEyes(root, eyes, [0, 0, 1]);
    expect(painted.meshes).toHaveLength(2);
    expect(painted.focus?.x).toBeCloseTo(0, 6);
    expect(painted.normal.z).toBeGreaterThan(0.99);
    // The eye parts keep their painted map; only the shader around it changes.
    painted.meshes.forEach((mesh, index) => {
      expect(mesh.material).not.toBe(originals[index]);
      expect((mesh.material as MeshStandardMaterial).map).toBe(originals[index].map);
    });
    const shaders: Parameters<MeshStandardMaterial["onBeforeCompile"]>[0][] = [];
    for (const mesh of painted.meshes) {
      const material = mesh.material as MeshStandardMaterial;
      const shader = {
        uniforms: {},
        vertexShader: "#include <common>\n#include <project_vertex>",
        fragmentShader: "#include <common>\n#include <map_fragment>\n#include <emissivemap_fragment>\n#include <opaque_fragment>",
      } as Parameters<typeof material.onBeforeCompile>[0];
      material.onBeforeCompile(shader, {} as WebGLRenderer);
      shaders.push(shader);
    }
    expect(shaders[0].uniforms.paintedPupil.value.x).toBeCloseTo(-0.03);
    expect(shaders[1].uniforms.paintedIrisRadius.value).toBeCloseTo(0.0032);
    // The window is measured in model space from the fragment's world position.
    expect(shaders[0].vertexShader).toContain("paintedWorld = (modelMatrix * vec4(transformed, 1.0)).xyz;");
    expect(shaders[0].fragmentShader).toContain("float paintedRadius = length(paintedDelta) / paintedIrisRadius;");
    // Recolour only where the texel looks like iris inside the window; emission is that
    // same mask, and the glow-only pass writes the emission alone.
    expect(shaders[0].fragmentShader).toContain("float irisMask = irisLike * irisWindow * paintedIrisEnabled;");
    expect(shaders[0].fragmentShader).toContain("diffuseColor.rgb = mix(diffuseColor.rgb, iris, irisMask);");
    expect(shaders[0].fragmentShader).toContain("totalEmissiveRadiance += neon");
    expect(shaders[0].fragmentShader).toContain("if (paintedGlowPassOnly > 0.5) gl_FragColor = vec4(neon, 1.0);");
    // No colour chosen: the painted eye is left exactly as the artist made it.
    expect(shaders[0].uniforms.paintedIrisEnabled.value).toBe(0);
    expect(painted.glowing).toBe(false);
    painted.setColor("#20f6ff", 2.2);
    expect(painted.glowing).toBe(true);
    for (const shader of shaders) {
      expect(shader.uniforms.paintedIrisEnabled.value).toBe(1);
      expect(shader.uniforms.paintedIrisColor.value.getHexString()).toBe("20f6ff");
      expect(shader.uniforms.paintedIrisGlow.value).toBe(2.2);
    }
    painted.setGlowPassOnly(true);
    for (const shader of shaders) expect(shader.uniforms.paintedGlowPassOnly.value).toBe(1);
    painted.setGlowPassOnly(false);
    painted.setColor(null);
    expect(painted.glowing).toBe(false);
    for (const shader of shaders) {
      expect(shader.uniforms.paintedIrisEnabled.value).toBe(0);
      expect(shader.uniforms.paintedIrisColor.value.getHexString()).toBe(NATURAL_EYE_COLOR.slice(1));
    }
    expect(painted.isEyeMesh(painted.meshes[0])).toBe(true);
    expect(painted.isEyeMesh(root)).toBe(false);
    painted.dispose();
    // Disposal hands the parts their original materials back.
    painted.meshes.forEach((mesh, index) => expect(mesh.material).toBe(originals[index]));
  });

  it("refuses a model without the named eye part instead of showing an uncoloured eye", () => {
    const root = new Group();
    expect(() => attachPaintedEyes(root, [{ node: "missing", pupil: [0, 0.9, 0.05], irisRadius: 0.003 }], [0, 0, 1])).toThrow(PaintedEyeNotFound);
  });
});
