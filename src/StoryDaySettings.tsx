import { useEffect, useRef, useState } from "react";
import type { StoryDayInspection } from "../electron/storyDaySettings";
import { formatDesktopError } from "./desktopError";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("story_day_configuration_panel");

export function StoryDaySettings() {
  const api = window.dawnwalkerDesktop?.storyDaySettings;
  const [snapshot, setSnapshot] = useState<StoryDayInspection>();
  const [busy, setBusy] = useState(Boolean(api));
  const [message, setMessage] = useState("");
  const [error, setError] = useState(false);
  const inFlight = useRef(false);
  useEffect(() => {
    let disposed = false;
    if (api) void api.inspect().then(result => { if (!disposed) setSnapshot(result); })
      .catch(cause => { if (!disposed) { setError(true); setMessage(formatDesktopError(cause, "Could not read story configuration. Refresh to retry.")); } })
      .finally(() => { if (!disposed) setBusy(false); });
    return () => { disposed = true; };
  }, [api]);
  async function operate(action: "refresh" | "apply" | "restore") {
    if (!api || busy || inFlight.current || (action !== "refresh" && !snapshot)) return;
    inFlight.current = true; setBusy(true); setError(false); setMessage("");
    try {
      const result = action === "refresh" ? await api.inspect()
        : action === "apply" ? await api.apply({ expectedSha256: snapshot!.sha256 }) : await api.restore(snapshot!.sha256);
      setSnapshot(result);
      setMessage(action === "apply" ? "90-day configuration saved and verified. Restart the game, then read the active story deadline below."
        : action === "restore" ? "Original configuration restored and verified. Restart the game to reload it." : "Configuration refreshed.");
    } catch (cause) { setError(true); setMessage(formatDesktopError(cause, "Story configuration could not be changed.")); }
    finally { inFlight.current = false; setBusy(false); }
  }
  const enabled = snapshot?.enabled === true;
  const unavailable = !api || !snapshot || busy || snapshot.gameRunning || snapshot.conflict
    || (enabled ? !snapshot.owned : !snapshot.buildVerified);
  return <section className="feature-tools story-day-configuration" aria-label="90-day configuration">
    <div className="feature-title"><h3>90-day story configuration</h3><span className="feature-badge">Restart required</span></div>
    <div className="story-day-toggle-row">
      <span>Keep the 90-day setting after restart</span>
      <span className="story-day-toggle-control"><button type="button" role="switch" aria-label="90-day configuration" aria-checked={enabled} aria-busy={busy}
        className={`toggle ${enabled ? "toggle-on" : ""}`} disabled={unavailable} onClick={() => void operate(enabled ? "restore" : "apply")}><span /></button>
      {(busy || enabled) && <strong>{busy ? "Working…" : "CONFIGURED"}</strong>}</span>
    </div>
    <p>The supplied mod uses DaysToPass=91. This edits Game.ini while the game is closed and keeps an exact original backup. Configuration status is separate from the live deadline.</p>
    {!api && <p className="feature-status">Available in the desktop app.</p>}
    {snapshot?.gameRunning && <p className="feature-status">Close Dawnwalker, then refresh to change persistent configuration. Use the live control below during play.</p>}
    {snapshot && !snapshot.buildVerified && !snapshot.owned && <p className="feature-status">The installed build must be verified before enabling this setting.</p>}
    {snapshot?.conflict && <p role="alert">Game.ini changed outside this menu. Your changes and original backup have been preserved; automatic restoration is blocked.</p>}
    {enabled && !snapshot?.owned && <p>This setting was already configured outside this menu. No original backup is owned here.</p>}
    <div className="feature-actions">
      <button type="button" disabled={!api || busy} onClick={() => void operate("refresh")}>Refresh story configuration</button>
      {snapshot?.owned && <button type="button" disabled={busy || snapshot.gameRunning || snapshot.conflict} onClick={() => void operate("restore")}>Restore original story configuration</button>}
    </div>
    {snapshot?.backupPath && <p className="file-path">Original backup: {snapshot.backupPath}</p>}
    {message && <p role={error ? "alert" : "status"}>{message}</p>}
  </section>;
}
