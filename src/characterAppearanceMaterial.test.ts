import { describe, expect, it } from "vitest";
import { BoxGeometry, Mesh, MeshStandardMaterial, Texture, type WebGLRenderer } from "three";
import { NATURAL_CHARACTER_APPEARANCE } from "./characterAppearanceState";
import { createCharacterAppearanceMaterialController } from "./characterAppearanceMaterial";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_appearance_material_tests");

function shaderFor(material: MeshStandardMaterial) {
  const shader = { uniforms: {}, vertexShader: "#include <common>\n#include <project_vertex>", fragmentShader: "#include <common>\n#include <map_fragment>" } as Parameters<MeshStandardMaterial["onBeforeCompile"]>[0];
  material.onBeforeCompile(shader, {} as WebGLRenderer);
  return shader;
}

describe("character appearance material controller", () => {
  it("composes the painted-eye callback and keeps the original texture", () => {
    const map = new Texture();
    const material = new MeshStandardMaterial({ map });
    const prior = material.onBeforeCompile;
    material.onBeforeCompile = shader => { shader.uniforms.paintedIrisColor = { value: "retained" }; };
    const painted = material.onBeforeCompile;
    const mesh = new Mesh(new BoxGeometry(), material);
    mesh.name = "tripo_part_39";
    const controller = createCharacterAppearanceMaterialController(mesh);
    const shader = shaderFor(material);
    expect(shader.uniforms.paintedIrisColor.value).toBe("retained");
    expect(shader.uniforms.characterSkinEnabled).toBeUndefined();
    expect(shader.uniforms.characterHairEnabled).toBeUndefined();
    expect(material.map).toBe(map);
    controller.dispose();
    expect(material.onBeforeCompile).toBe(painted);
    material.onBeforeCompile = prior;
  });

  it("updates independent skin, hair and eyebrow uniforms without recompiling or replacing maps", () => {
    const map = new Texture();
    const material = new MeshStandardMaterial({ map });
    const mesh = new Mesh(new BoxGeometry(), material);
    mesh.name = "tripo_part_2";
    const controller = createCharacterAppearanceMaterialController(mesh);
    const shader = shaderFor(material);
    controller.apply({ ...NATURAL_CHARACTER_APPEARANCE, skinTint: [70, 45, 30], hairColor: "#c9a35a", eyebrowColor: "#1f7a7a" });
    expect(shader.uniforms.characterSkinEnabled.value).toBe(1);
    expect(shader.uniforms.characterSkinSurface.value).toBe(1);
    expect(shader.uniforms.characterSkinMultiplier.value.toArray()).toEqual([1.4, 0.9, 0.6]);
    expect(shader.uniforms.characterHairEnabled.value).toBe(1);
    expect(shader.uniforms.characterHairSurface.value).toBe(0);
    expect(shader.uniforms.characterHairColor.value.getHexString()).toBe("c9a35a");
    expect(shader.uniforms.characterBrowEnabled.value).toBe(1);
    expect(shader.uniforms.characterBrowSurface.value).toBe(1);
    expect(shader.uniforms.characterBrowColor.value.getHexString()).toBe("1f7a7a");
    expect(material.map).toBe(map);
    controller.apply(NATURAL_CHARACTER_APPEARANCE);
    expect(shader.uniforms.characterSkinEnabled.value).toBe(0);
    expect(shader.uniforms.characterHairEnabled.value).toBe(0);
    expect(shader.uniforms.characterBrowEnabled.value).toBe(0);
    expect(shader.fragmentShader).toContain("characterSkinMask");
    expect(shader.fragmentShader).toContain("characterHairMask");
    expect(shader.fragmentShader).toContain("characterBrowMask");
    expect(shader.fragmentShader).toContain("1.0 - max(characterBrowRegion, characterEyeRegion)");
    controller.dispose();
  });

  it("does not instrument clothing and keeps hair-only parts separate from brows and skin", () => {
    const clothingMaterial = new MeshStandardMaterial({ map: new Texture() });
    const clothing = new Mesh(new BoxGeometry(), clothingMaterial);
    clothing.name = "tripo_part_6";
    const hairMaterial = new MeshStandardMaterial({ map: new Texture() });
    const hair = new Mesh(new BoxGeometry(), hairMaterial);
    hair.name = "tripo_part_38";
    clothing.add(hair);
    const controller = createCharacterAppearanceMaterialController(clothing);
    expect(shaderFor(clothingMaterial).uniforms.characterHairEnabled).toBeUndefined();
    const hairShader = shaderFor(hairMaterial);
    expect(hairShader.uniforms.characterHairSurface.value).toBe(1);
    expect(hairShader.uniforms.characterSkinSurface.value).toBe(0);
    expect(hairShader.uniforms.characterBrowSurface.value).toBe(0);
    controller.dispose();
  });

  it.each([8, 16, 18, 30, 38])("tints measured scalp and trailing hair part %i without the mixed face/fur atlas", part => {
    const material = new MeshStandardMaterial({ map: new Texture() });
    const mesh = new Mesh(new BoxGeometry(), material);
    mesh.name = `tripo_part_${part}`;
    const controller = createCharacterAppearanceMaterialController(mesh);
    controller.apply({ ...NATURAL_CHARACTER_APPEARANCE, hairColor: "#ffffff" });
    const shader = shaderFor(material);
    expect(shader.uniforms.characterHairSurface?.value).toBe(1);
    expect(shader.uniforms.characterHairEnabled?.value).toBe(1);
    expect(shader.uniforms.characterSkinSurface?.value).toBe(0);
    expect(shader.uniforms.characterBrowSurface?.value).toBe(0);
    controller.dispose();
  });

  it("applies controlled state before compilation and recreates from neutral after disposal", () => {
    const material = new MeshStandardMaterial({ map: new Texture() });
    const mesh = new Mesh(new BoxGeometry(), material);
    mesh.name = "tripo_part_38";
    const first = createCharacterAppearanceMaterialController(mesh);
    first.apply({ ...NATURAL_CHARACTER_APPEARANCE, hairColor: "#ffffff" });
    expect(shaderFor(material).uniforms.characterHairEnabled.value).toBe(1);
    first.dispose();
    const recreated = createCharacterAppearanceMaterialController(mesh);
    const shader = shaderFor(material);
    expect(shader.uniforms.characterSkinEnabled.value).toBe(0);
    expect(shader.uniforms.characterHairEnabled.value).toBe(0);
    expect(shader.uniforms.characterBrowEnabled.value).toBe(0);
    recreated.dispose();
  });
});
