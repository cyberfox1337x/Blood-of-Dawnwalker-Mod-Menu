import { useEffect, useRef, useState } from "react";
import { Minus, Plus, RotateCcw } from "lucide-react";
import "./InterfaceScaleSettings.css";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("interface_scale_settings");

export function InterfaceScaleSettings() {
  const api = window.dawnwalkerDesktop?.interfaceScale;
  const [scale, setScale] = useState(100);
  const [error, setError] = useState("");
  const [ready, setReady] = useState(false);
  const [saving, setSaving] = useState(false);
  const active = useRef(false);
  const pending = useRef(false);

  useEffect(() => {
    active.current = true;
    let changed = false;
    const unsubscribe = api?.onChanged(next => { changed = true; setScale(next); setError(""); });
    const unsubscribeError = api?.onError(setError);
    void api?.get().then(next => {
      if (active.current) { if (!changed) setScale(next); setReady(true); }
    }).catch(() => { if (active.current) setError("Could not read menu scale. Reopen the menu to retry."); });
    return () => { active.current = false; unsubscribe?.(); unsubscribeError?.(); };
  }, [api]);

  async function saveScale(next: number) {
    if (!api || pending.current) return;
    pending.current = true;
    setSaving(true);
    setError("");
    try {
      const saved = await api.set(next);
      if (active.current) setScale(saved);
    } catch {
      if (active.current) setError("Could not save menu scale. Check that the menu's settings folder is writable.");
    } finally {
      pending.current = false;
      if (active.current) setSaving(false);
    }
  }

  return <section className="feature-tools interface-scale" aria-label="Menu size">
    <h3>Menu size</h3>
    <p>Enlarge text and controls for high-resolution displays. Maximize the window for more space.</p>
    <div className="feature-actions" aria-busy={saving}>
      <button type="button" aria-label="Decrease menu size" disabled={!ready || saving || scale <= 75} onClick={() => void saveScale(Math.max(75, scale - 25))}><Minus size={16} /></button>
      <output aria-label="Current menu size" aria-live="polite">{scale}%</output>
      <button type="button" aria-label="Increase menu size" disabled={!ready || saving || scale >= 200} onClick={() => void saveScale(Math.min(200, scale + 25))}><Plus size={16} /></button>
      <button type="button" disabled={!ready || saving || scale === 100} onClick={() => void saveScale(100)}><RotateCcw size={16} /> Reset to 100%</button>
    </div>
    <p>Ctrl + Plus / Minus to resize · Ctrl + 0 to reset. Your size is saved automatically.</p>
    {!api && <p>Menu size is available in the desktop application.</p>}
    {error && <p role="alert">{error}</p>}
  </section>;
}
