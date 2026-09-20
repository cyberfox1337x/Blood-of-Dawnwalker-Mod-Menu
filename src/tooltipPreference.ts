const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_tooltip_preference");

export const STYLED_TOOLTIPS_STORAGE_KEY = "dawnwalker.tooltips.styled";

/** Reads the saved preference; styled tooltips are on unless the user turned them off. */
export function readStyledTooltipsPreference(): boolean {
  try { return window.localStorage.getItem(STYLED_TOOLTIPS_STORAGE_KEY) !== "off"; }
  catch { return true; }
}

export function writeStyledTooltipsPreference(enabled: boolean): void {
  try { window.localStorage.setItem(STYLED_TOOLTIPS_STORAGE_KEY, enabled ? "on" : "off"); }
  catch (error) { console.warn("Tooltip preference could not be saved:", error); }
}

