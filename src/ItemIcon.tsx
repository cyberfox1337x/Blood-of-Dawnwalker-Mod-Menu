import { useState } from "react";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_item_icon");

// The game's own icon for an item or perk id, served by the desktop app from a local
// asset export (dw-asset://icon/<id>). When no export exists the request 404s and the
// picture gives way to an empty frame, so the row keeps its shape either way.
export function ItemIcon({ id, size = 36 }: Readonly<{ id: string; size?: number }>) {
  const [missing, setMissing] = useState(false);
  const desktop = typeof window !== "undefined" && Boolean(window.dawnwalkerDesktop);
  if (missing || !desktop) return <span className="item-icon item-icon-empty" style={{ width: size, height: size }} aria-hidden="true" />;
  return <img className="item-icon" width={size} height={size} alt="" src={`dw-asset://icon/${encodeURIComponent(id)}`} onError={() => setMissing(true)} />;
}
