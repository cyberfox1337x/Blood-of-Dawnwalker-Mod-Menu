import { useState } from "react";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_perk_icon");

const TREE_SYMBOLS: Readonly<Record<string, string>> = Object.freeze({
  CombatFocus: "⚔", Human: "✦", Shared: "◆", Vampire: "☾",
});

export function PerkIcon({ id, name, tree, iconStatus }: Readonly<{ id: string; name: string; tree: string; iconStatus?: string }>) {
  const desktop = typeof window !== "undefined" && Boolean(window.dawnwalkerDesktop);
  const hasOriginal = iconStatus === "Original game icon";
  const [failedId, setFailedId] = useState<string | null>(null);
  const failed = failedId === id;
  if (failed) {
    return <button type="button" className="item-icon perk-icon-fallback perk-icon-retry" aria-label={`Retry ${name} perk icon`} title="The verified original icon failed to load. Activate to retry." onClick={() => setFailedId(null)}>
      <span aria-hidden="true">{TREE_SYMBOLS[tree] ?? "◇"}</span>
    </button>;
  }
  if (!desktop || !hasOriginal) {
    const reason = iconStatus || "No verified original icon is available";
    return <span className="item-icon perk-icon-fallback" role="img" aria-label={`${name} symbolic ${tree} perk icon`} title={`${reason}. Symbolic ${tree} fallback shown.`}>
      <span aria-hidden="true">{TREE_SYMBOLS[tree] ?? "◇"}</span>
    </span>;
  }
  return <img className="item-icon" width={36} height={36} alt={`${name} perk icon`} src={`dw-asset://icon/${encodeURIComponent(id)}`} onError={() => setFailedId(id)} />;
}
