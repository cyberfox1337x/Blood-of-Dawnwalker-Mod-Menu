const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("catalogOptions");

/** Catalog rows the game itself marks as developer leftovers: obsolete technical items,
 *  "[DB]" debug entries and the class default objects ("Default Item ... Data Asset"). They
 *  come straight out of the asset scan and are not things a player can meaningfully own. */
export function isDeveloperOption(label: string): boolean {
  const text = label.trim();
  return text.startsWith("[OBSOLETE") || text.startsWith("[DB]") || /^Default\s+Item .*Data Asset/.test(text);
}
