const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("feature_contributors");

export type FeatureContributor = Readonly<{
  id: string;
  displayName: string;
  avatar?: string;
  profileReferenceId: number;
  modReferenceId: number;
  contribution: string;
}>;

// Verified against each Nexus mod and author profile on 2026-09-19. The local
// 100 px avatars are display copies from the linked Nexus profiles; each card
// links back to its authoritative profile and reference mod.
export const FEATURE_CONTRIBUTORS: readonly FeatureContributor[] = Object.freeze([
  Object.freeze({
    id: "su4enka",
    displayName: "Su4enka",
    avatar: "./credits/nexus-su4enka.webp",
    profileReferenceId: 2000,
    modReferenceId: 2001,
    contribution: "Eye colour controls inspired by Coen Vampire Eyes Color.",
  }),
  Object.freeze({
    id: "darateagod",
    displayName: "DaraTeaGod",
    avatar: "./credits/nexus-darateagod.webp",
    profileReferenceId: 2002,
    modReferenceId: 2003,
    contribution: "Fog visibility controls informed by Remove Fog.",
  }),
  Object.freeze({
    id: "nectarines",
    displayName: "nectarines",
    avatar: "./credits/nexus-nectarines.webp",
    profileReferenceId: 2004,
    modReferenceId: 2005,
    contribution: "Sprint and stamina controls informed by Stamina and Sprint Tweaks.",
  }),
  Object.freeze({
    id: "kzekai",
    displayName: "KZekai",
    avatar: "./credits/nexus-kzekai.webp",
    profileReferenceId: 2006,
    modReferenceId: 2007,
    contribution: "Console and mod-loading research informed by Console Enabler and Mod Loader.",
  }),
  Object.freeze({
    id: "fulltimepatriot",
    displayName: "FullTimePatriot",
    avatar: "./credits/nexus-fulltimepatriot.webp",
    profileReferenceId: 2008,
    modReferenceId: 2009,
    contribution: "Save Editor workflow inspired by Blood of Dawnwalker Save Editor.",
  }),
  Object.freeze({
    id: "caites",
    displayName: "Caites",
    avatar: "./credits/nexus-caites.webp",
    profileReferenceId: 2010,
    modReferenceId: 2011,
    contribution: "Focus range, camera, and visibility research informed by Focus Tweaks.",
  }),
  Object.freeze({
    id: "alahria",
    displayName: "Alahria",
    avatar: "./credits/nexus-alahria.webp",
    profileReferenceId: 2012,
    modReferenceId: 2013,
    contribution: "Live skin colour controls inspired by Coen Skin Tints - Mod Setting Menu.",
  }),
  Object.freeze({
    id: "bruender09",
    displayName: "bruender09",
    avatar: "./credits/nexus-bruender09.webp",
    profileReferenceId: 2014,
    modReferenceId: 2015,
    contribution: "Timeless Court Activities - No Time Cost inspired by the mod of the same name.",
  }),
]);
