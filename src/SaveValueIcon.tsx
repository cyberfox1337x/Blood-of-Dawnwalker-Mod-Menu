const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_save_value_icon");

export type SaveValueIconName =
  | "coin" | "skillPoints" | "level" | "progressPoints" | "spentSkillPoints"
  | "health" | "blood" | "bloodRestoration" | "mutationLevel" | "corruptionCharge" | "clock";

// Small line glyphs for the stat sheet, drawn in the theme's parchment/blood palette so
// each value reads at a glance: coins, a perk star, level chevrons, an XP bar, a spent
// ledger, heart, blood drop, drop with a plus, a fang moon, a corruption flame, a clock.
const GLYPHS: Readonly<Record<SaveValueIconName, string>> = {
  coin: '<ellipse cx="12" cy="8" rx="7" ry="3"/><path d="M5 8v4c0 1.7 3.1 3 7 3s7-1.3 7-3V8"/><path d="M5 12v4c0 1.7 3.1 3 7 3s7-1.3 7-3v-4"/>',
  skillPoints: '<path d="M12 3l2.6 5.6 6.1.7-4.5 4.2 1.2 6L12 16.6 6.6 19.5l1.2-6L3.3 9.3l6.1-.7z"/>',
  level: '<path d="M5 15l7-7 7 7"/><path d="M5 20l7-7 7 7"/>',
  progressPoints: '<rect x="3" y="9" width="18" height="6" rx="2"/><path d="M3 12h11" stroke-width="3"/>',
  spentSkillPoints: '<path d="M6 4h12v16H6z"/><path d="M9 9l1.5 1.5L13 8"/><path d="M9 14l1.5 1.5L13 13"/><path d="M14 9h2M14 14h2"/>',
  health: '<path d="M12 20s-7-4.4-7-9.5A4 4 0 0 1 12 8a4 4 0 0 1 7 2.5C19 15.6 12 20 12 20z"/>',
  blood: '<path d="M12 3s6 7 6 11a6 6 0 0 1-12 0c0-4 6-11 6-11z"/>',
  bloodRestoration: '<path d="M12 3s6 7 6 11a6 6 0 0 1-12 0c0-4 6-11 6-11z"/><path d="M12 11v6M9 14h6"/>',
  mutationLevel: '<path d="M16 3a8 8 0 1 0 5 13A7 7 0 0 1 16 3z"/><path d="M9 14l1 4 1-4M13 14l1 4 1-4"/>',
  corruptionCharge: '<path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-5 1-9z"/>',
  clock: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4l3 2"/>',
};

export function SaveValueIcon({ name }: Readonly<{ name: SaveValueIconName }>) {
  return <svg className={`save-value-icon save-value-icon-${name}`} viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"
    fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"
    dangerouslySetInnerHTML={{ __html: GLYPHS[name] }} />;
}
