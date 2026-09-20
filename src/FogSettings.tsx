import { useEffect, useRef, useState } from "react";
import type { FogInspection } from "../electron/fogSettings";
import { formatDesktopError } from "./desktopError";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_fog_panel");

export function FogSettings() {
  const api = window.dawnwalkerDesktop?.fogSettings;
  const [snapshot, setSnapshot] = useState<FogInspection>();
  const [fog, setFog] = useState(true);
  const [volumetricFog, setVolumetricFog] = useState(true);
  const [busy, setBusy] = useState(Boolean(api));
  const [message, setMessage] = useState("");
  const [error, setError] = useState(false);
  const inFlight = useRef(false);
  function accept(result: FogInspection) {
    setSnapshot(result);
    setFog(result.configured["r.Fog"] !== "0");
    setVolumetricFog(result.configured["r.VolumetricFog"] !== "0");
  }
  useEffect(() => {
    let disposed = false;
    if (api) void api.inspect()
      .then(result => { if (!disposed) accept(result); })
      .catch(cause => { if (!disposed) { setError(true); setMessage(formatDesktopError(cause, "Could not inspect fog configuration. Refresh to retry.")); } })
      .finally(() => { if (!disposed) setBusy(false); });
    return () => { disposed = true; };
  }, [api]);
  async function operate(action: "refresh" | "apply" | "restore") {
    if (!api || busy || inFlight.current || (action !== "refresh" && !snapshot)) return;
    inFlight.current = true; setError(false); setBusy(true);
    setMessage("");
    try {
      const result = action === "refresh" ? await api.inspect()
        : action === "apply" && snapshot ? await api.apply({ expectedSha256: snapshot.sha256, fog, volumetricFog })
        : snapshot ? await api.restore(snapshot.sha256) : undefined;
      if (result) accept(result);
      setMessage(action === "apply" ? "Configuration saved and read back. Restart Dawnwalker to test its visual effect."
        : action === "restore" ? "Original configuration restored and verified. Restart Dawnwalker." : "Configuration refreshed.");
    } catch (cause) { setError(true); setMessage(formatDesktopError(cause, "Fog configuration operation failed.")); }
    finally { inFlight.current = false; setBusy(false); }
  }
  return <section className="feature-tools" aria-label="Fog configuration">
    <div className="feature-title"><h3>Fog</h3><span className="feature-badge">Restart required</span></div>
    <p>Changes Engine.ini while Dawnwalker is closed. A verified original backup is retained. <strong>Not verified in game.</strong> Local fog volumes and scripted effects may remain.</p>
    {!api ? <p className="feature-status">Available in the desktop app. No game configuration is changed in this preview.</p> : <>
      {snapshot && <>
        <p className="file-path">{snapshot.fullPath}</p>
        <div className="feature-fields">
          <label>Fog after restart<select aria-label="Fog after restart" value={String(fog)} disabled={busy} onChange={event => setFog(event.target.value === "true")}><option value="true">Enabled</option><option value="false">Disabled</option></select><small>Saved value: {snapshot.configured["r.Fog"] ?? "Engine default"}</small></label>
          <label>Volumetric fog after restart<select aria-label="Volumetric fog after restart" value={String(volumetricFog)} disabled={busy} onChange={event => setVolumetricFog(event.target.value === "true")}><option value="true">Enabled</option><option value="false">Disabled</option></select><small>Saved value: {snapshot.configured["r.VolumetricFog"] ?? "Engine default"}</small></label>
        </div>
      </>}
      <div className="feature-actions">
        <button type="button" disabled={busy} onClick={() => void operate("refresh")}>Refresh configuration</button>
        <button type="button" disabled={busy || !snapshot} onClick={() => void operate("apply")}>Back up &amp; apply configuration</button>
        <button type="button" disabled={busy || !snapshot?.owned} onClick={() => void operate("restore")}>Restore original configuration</button>
      </div>
      {snapshot?.backupPath && <p className="file-path">Original backup: {snapshot.backupPath}</p>}
    </>}
    {message && <p role={error ? "alert" : "status"} className="file-path">{message}</p>}
  </section>;
}
