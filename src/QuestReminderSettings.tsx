import { BellRing } from "lucide-react";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("quest_reminder_settings");

/**
 * Settings control for objective reminders. The App owns the value so the reminder
 * pipeline and this switch can never disagree; this renders it and reports intent.
 */
export function QuestReminderSettings({ enabled, available, saving, error, status, testing, onToggle, onTest }: {
  enabled: boolean;
  available: boolean;
  saving: boolean;
  error: string;
  status: string;
  testing: boolean;
  onToggle: (next: boolean) => void;
  onTest: () => void;
}) {
  return (
    <section className="reference-feature-card quest-reminder-settings" aria-label="Objective reminders">
      <h3><BellRing size={17} aria-hidden="true" /> Objective reminders</h3>
      <div className="control-row">
        <span className="player-toggle-label">
          Desktop notification for the current objective
          <small>Shows the tracked quest&apos;s next step as a Windows notification when it changes, and in the menu.</small>
        </span>
        <button
          type="button"
          className={`toggle ${enabled ? "toggle-on" : ""}`}
          role="switch"
          aria-label="Objective reminders"
          aria-checked={enabled}
          aria-busy={saving}
          disabled={!available || saving}
          onClick={() => onToggle(!enabled)}
        ><span /></button>
      </div>
      <div className="control-row">
        <span className="player-toggle-label">
          Send a test notification
          <small>Proves the whole path, so a silent Windows setting cannot be mistaken for a broken menu.</small>
        </span>
        <button type="button" className="small-button" disabled={!available || !enabled || testing}
          onClick={onTest}>{testing ? "Sending…" : "Send test"}</button>
      </div>
      {status && <p className="dashboard-option-status" role="status">{status}</p>}
      {!available && <p className="dashboard-option-status">Reminders need the desktop menu; they are unavailable in this window.</p>}
      {error && <p className="dashboard-option-status" role="alert">{error}</p>}
    </section>
  );
}
