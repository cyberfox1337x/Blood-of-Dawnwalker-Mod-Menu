const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_save_labels");

// Human wording for the facts the game's own load list shows beside each save picture.
export function savedAtLabel(savedAt: string | undefined): string {
  // Metadata dates are "YYYY.MM.DD-HH.MM.SS" (the game's own format).
  const match = savedAt && /^(\d{4})\.(\d{2})\.(\d{2})-(\d{2})\.(\d{2})/.exec(savedAt);
  return match ? `${match[1]}-${match[2]}-${match[3]} ${match[4]}:${match[5]}` : savedAt ?? "Date unknown";
}
export function playTimeLabel(seconds: number | undefined): string {
  if (seconds === undefined) return "";
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return hours ? `${hours}h ${String(minutes).padStart(2, "0")}m played` : `${minutes}m played`;
}
export function saveTypeLabel(type: string | undefined, fileName: string): string {
  const source = (type ?? "").toLowerCase();
  if (source.startsWith("quick")) return "Quick save";
  if (source.startsWith("auto")) return "Autosave";
  if (source.startsWith("manual")) return "Manual save";
  return type ? `${type} save` : fileName.replace(/\.sav$/i, "");
}
