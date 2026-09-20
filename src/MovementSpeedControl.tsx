import { useRef, useState } from "react";
import type { ImportedMenuSnapshot } from "./importedMenuContract";
import type { Dispatch, ImportedFeedback, ImportedPendingControl } from "./importedMenuState";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("movement_speed_native_control");
type Props = { snapshot: ImportedMenuSnapshot; disabled: boolean; pending: boolean;
  pendingControl?: ImportedPendingControl; feedback?: ImportedFeedback; dispatch: Dispatch };
export function MovementSpeedControl({ snapshot, disabled, pending, pendingControl, feedback, dispatch }: Props) {
  const [draft, setDraft] = useState<number>();
  const dirty = useRef(false);
  const section = snapshot.sections.find(candidate => candidate.id === "DWSpeed");
  const field = section?.items.find(item => item.id === "multiplier");
  const valid = (value: unknown): value is number => typeof value === "number" && value >= 1 && value <= 3 && value % .5 === 0;
  const current = snapshot.ready && valid(field?.value) ? field.value : undefined;
  const busy = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued")
    && (!pendingControl || pendingControl.sectionId === "DWSpeed");
  const unavailable = disabled || !snapshot.ready || busy;
  const feedbackMessage = feedback?.sectionId === "DWSpeed" ? feedback.message : undefined;
  function commit(value: number) {
    if (!dirty.current) return;
    dirty.current = false; setDraft(undefined);
    if (!unavailable && field?.enabled !== false && field?.disabled !== true && valid(value) && value !== current) {
      void dispatch({ action: "set", sectionId: "DWSpeed", itemId: "multiplier", value });
    }
  }
  // The movement-speed-control class is the hook that keeps this row directly under
  // Fly in the Player grid; the row spans the grid so its status stays readable.
  return <div className="dashboard-option-group movement-speed-control"><label className="dashboard-row"><span>Speed Multiplier</span><span className="dashboard-slider">
    <input className="movement-speed-range" type="range" aria-label="Speed Multiplier" min={1} max={3} step={.5} value={draft ?? current ?? 1}
      disabled={unavailable || current === undefined || field?.enabled === false || field?.disabled === true} aria-busy={busy}
      onChange={event => { dirty.current = true; setDraft(Number(event.target.value)); }}
      onPointerUp={event => commit(Number(event.currentTarget.value))} onBlur={event => commit(Number(event.currentTarget.value))}
      onKeyUp={event => { if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(event.key)) commit(Number(event.currentTarget.value)); }}
      onKeyDown={event => { if (event.key === "Escape") { dirty.current = false; setDraft(undefined); } }} />
    <output>{current === undefined ? "—" : `${draft ?? current}×`}</output></span></label>
    {feedbackMessage && <p className="dashboard-option-status" role="alert">{feedbackMessage}</p>}
  </div>;
}
