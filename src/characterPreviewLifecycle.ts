import { useEffect, useState } from "react";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_preview_activation");

export const CHARACTER_PREVIEW_RELEASE_DELAY_MS = 15_000;

/** Lazily create the viewer, retain it across quick tab switches, and release it for gameplay. */
export function useCharacterPreviewActivation(active: boolean): boolean {
  const [windowActive, setWindowActive] = useState(() => !document.hidden && document.hasFocus());
  const [activated, setActivated] = useState(active && !document.hidden && document.hasFocus());
  useEffect(() => {
    const focused = () => setWindowActive(!document.hidden);
    const blurred = () => setWindowActive(false);
    const visibilityChanged = () => setWindowActive(!document.hidden && document.hasFocus());
    window.addEventListener("focus", focused);
    window.addEventListener("blur", blurred);
    document.addEventListener("visibilitychange", visibilityChanged);
    return () => {
      window.removeEventListener("focus", focused);
      window.removeEventListener("blur", blurred);
      document.removeEventListener("visibilitychange", visibilityChanged);
    };
  }, []);
  useEffect(() => {
    let releaseTimer: number | undefined;
    if (active && windowActive) setActivated(true);
    else if (!windowActive) setActivated(false);
    else releaseTimer = window.setTimeout(() => setActivated(false), CHARACTER_PREVIEW_RELEASE_DELAY_MS);
    return () => {
      if (releaseTimer !== undefined) window.clearTimeout(releaseTimer);
    };
  }, [active, windowActive]);
  return activated;
}
