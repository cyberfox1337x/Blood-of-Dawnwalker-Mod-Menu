const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_feature_references");

// External links are exposed through numeric IDs so renderer content cannot request an
// arbitrary URL. Community entries acknowledge the independently implemented ideas;
// bundled dependency licences continue to ship with the package.
export function resolveFeatureReference(id: unknown): string | undefined {
  return typeof id === "number" ? SUPPORTING_REFERENCES.find(entry => entry.id === id)?.url : undefined;
}

export const SUPPORTING_REFERENCES = Object.freeze([
  { id: 1000, title: "Unreal Engine 4/5 Scripting System", credit: "Integration or dependency: Narknon and UE4SS contributors", details: "Existing pinned runtime dependency, under the MIT license. Copyright (c) 2022 Narknon. License included with packaged files.", url: "https://github.com/UE4SS-RE/RE-UE4SS/tree/97b7e501" },
  { id: 1001, title: "Unreal Engine configuration documentation", credit: "Documentation reference: Epic Games", details: "Engine configuration behavior used by the independently written fog tools.", url: "https://dev.epicgames.com/documentation/en-us/unreal-engine/configuration-files-in-unreal-engine?application_version=5.5" },
  { id: 2000, title: "Su4enka Nexus profile", credit: "Feature inspiration", details: "Author profile for the eye-colour reference.", url: "https://www.nexusmods.com/profile/Su4enka" },
  { id: 2001, title: "Coen Vampire Eyes Color", credit: "Feature inspiration: Su4enka", details: "Reference for eye-colour controls.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/26" },
  { id: 2002, title: "DaraTeaGod Nexus profile", credit: "Feature inspiration", details: "Author profile for the fog reference.", url: "https://www.nexusmods.com/profile/DaraTeaGod" },
  { id: 2003, title: "Remove Fog", credit: "Feature inspiration: DaraTeaGod", details: "Reference for fog visibility controls.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/69" },
  { id: 2004, title: "nectarines Nexus profile", credit: "Feature inspiration", details: "Author profile for the stamina reference.", url: "https://www.nexusmods.com/profile/nectarines" },
  { id: 2005, title: "Stamina and Sprint Tweaks", credit: "Feature inspiration: nectarines", details: "Reference for sprint and stamina controls.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/17" },
  { id: 2006, title: "KZekai Nexus profile", credit: "Feature inspiration", details: "Author profile for the console and loader reference.", url: "https://www.nexusmods.com/profile/KZekai" },
  { id: 2007, title: "Console Enabler and Mod Loader", credit: "Feature inspiration: KZekai", details: "Reference for console and mod-loading research.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/16" },
  { id: 2008, title: "FullTimePatriot Nexus profile", credit: "Feature inspiration", details: "Author profile for the save-editor reference.", url: "https://www.nexusmods.com/profile/FullTimePatriot" },
  { id: 2009, title: "Blood of Dawnwalker Save Editor", credit: "Feature inspiration: FullTimePatriot", details: "Reference for the Save Editor workflow.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/43" },
  { id: 2010, title: "Caites Nexus profile", credit: "Feature inspiration", details: "Author profile for the Focus reference.", url: "https://www.nexusmods.com/profile/Caites" },
  { id: 2011, title: "Focus Tweaks", credit: "Feature inspiration: Caites", details: "Reference for Focus range, camera, and visibility research.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/81" },
  { id: 2012, title: "Alahria Nexus profile", credit: "Feature inspiration", details: "Author profile for the skin-colour reference.", url: "https://www.nexusmods.com/profile/Alahria" },
  { id: 2013, title: "Coen Skin Tints - Mod Setting Menu", credit: "Feature inspiration: Alahria", details: "Reference for live skin-colour controls.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/428" },
  { id: 2014, title: "bruender09 Nexus profile", credit: "Feature inspiration", details: "Author profile for the Court-activity time-cost reference.", url: "https://www.nexusmods.com/profile/bruender09" },
  { id: 2015, title: "Timeless Court Activities - No Time Cost", credit: "Feature inspiration: bruender09", details: "Reference for the Court-activity no-time-cost control.", url: "https://www.nexusmods.com/thebloodofdawnwalker/mods/558" },
]);
