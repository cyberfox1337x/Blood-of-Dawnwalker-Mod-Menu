import { useEffect, useState } from "react";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_tooltip_layer");

const SHOW_DELAY_MS = 220;
const VIEWPORT_MARGIN = 8;

type TooltipState = Readonly<{ text: string; left: number; top: number; placement: "below" | "above" }>;

// Every control in the menu explains itself through a `title`. The browser draws those in
// the OS style, late and off-theme, so while styled tooltips are on the text moves to
// `data-tooltip` (the native bubble never appears) and this layer draws it in the menu's
// own style near the control. Turning the setting off hands the text back to `title`.
function claimTitle(element: HTMLElement): string | undefined {
  const title = element.getAttribute("title");
  if (title !== null) {
    if (title.trim()) element.dataset.tooltip = title;
    element.removeAttribute("title");
  }
  return element.dataset.tooltip || undefined;
}

function releaseTitles(root: ParentNode): void {
  for (const element of root.querySelectorAll<HTMLElement>("[data-tooltip]")) {
    if (!element.hasAttribute("title")) element.setAttribute("title", element.dataset.tooltip ?? "");
    delete element.dataset.tooltip;
  }
}

function placeNear(element: HTMLElement, text: string): TooltipState {
  const rect = element.getBoundingClientRect();
  const width = Math.min(320, window.innerWidth - VIEWPORT_MARGIN * 2);
  let left = rect.left + rect.width / 2 - width / 2;
  left = Math.max(VIEWPORT_MARGIN, Math.min(left, window.innerWidth - width - VIEWPORT_MARGIN));
  const below = rect.bottom + 10;
  // Rough height guess keeps the bubble on screen; the CSS clamps the rest.
  const placement = below + 60 > window.innerHeight ? "above" : "below";
  const top = placement === "below" ? below : rect.top - 10;
  return { text, left, top, placement };
}

export function TooltipLayer({ enabled }: Readonly<{ enabled: boolean }>) {
  const [tooltip, setTooltip] = useState<TooltipState>();

  useEffect(() => {
    if (!enabled) { releaseTitles(document); setTooltip(undefined); return; }
    let timer: ReturnType<typeof setTimeout> | undefined;
    let current: HTMLElement | undefined;
    const hide = () => { if (timer) clearTimeout(timer); timer = undefined; current = undefined; setTooltip(undefined); };
    const show = (element: HTMLElement) => {
      const text = claimTitle(element);
      if (!text) return;
      current = element;
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => { if (current === element && element.isConnected) setTooltip(placeNear(element, text)); }, SHOW_DELAY_MS);
    };
    const onOver = (event: MouseEvent) => {
      const target = (event.target as Element | null)?.closest<HTMLElement>("[title], [data-tooltip]");
      if (!target) return;
      if (target !== current) show(target);
    };
    const onOut = (event: MouseEvent) => {
      if (!current) return;
      const next = event.relatedTarget as Node | null;
      if (next && current.contains(next)) return;
      hide();
    };
    const onFocus = (event: FocusEvent) => {
      const target = (event.target as Element | null)?.closest<HTMLElement>("[title], [data-tooltip]");
      if (target) show(target);
    };
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") hide(); };
    document.addEventListener("mouseover", onOver, true);
    document.addEventListener("mouseout", onOut, true);
    document.addEventListener("focusin", onFocus, true);
    document.addEventListener("focusout", hide, true);
    document.addEventListener("mousedown", hide, true);
    document.addEventListener("scroll", hide, true);
    document.addEventListener("keydown", onKey, true);
    window.addEventListener("blur", hide);
    return () => {
      hide();
      document.removeEventListener("mouseover", onOver, true);
      document.removeEventListener("mouseout", onOut, true);
      document.removeEventListener("focusin", onFocus, true);
      document.removeEventListener("focusout", hide, true);
      document.removeEventListener("mousedown", hide, true);
      document.removeEventListener("scroll", hide, true);
      document.removeEventListener("keydown", onKey, true);
      window.removeEventListener("blur", hide);
    };
  }, [enabled]);

  if (!enabled || !tooltip) return null;
  return <div className={`ui-tooltip ui-tooltip-${tooltip.placement}`} role="tooltip" style={{ left: tooltip.left, top: tooltip.top }}>{tooltip.text}</div>;
}
