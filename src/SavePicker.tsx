import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import type { SaveInspection, SaveSummary } from "../electron/saveEditor";
import { playTimeLabel, savedAtLabel, saveTypeLabel } from "./saveLabels";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_save_picker");

/** A save's gameplay numbers once decoded, or why they are missing. */
export type SummaryState = SaveSummary | "loading" | "unavailable";
export type SummaryMap = Readonly<Record<string, SummaryState | undefined>>;

// The game's own load list shows each save as its screenshot with the save type, the
// date it was written, the in-game day and the play time; the picker mirrors that so a
// save is recognised the same way here as in Dawnwalker, and adds the gameplay numbers
// the editor can change (clock, health, blood, mutation, level, coin) so the right save
// can be told apart before it is opened. A native <select> cannot show pictures, so this
// is a listbox dropdown: the closed control shows the chosen save's card, opening it
// lists every save as the same card.
function SummaryFacts({ summary }: Readonly<{ summary: SummaryState | undefined }>) {
  if (summary === undefined || summary === "loading") return <span className="save-card-stats save-card-stats-pending">Reading values…</span>;
  if (summary === "unavailable") return <span className="save-card-stats save-card-stats-pending">Values could not be read</span>;
  const number = (value: number | undefined) => value === undefined ? "—" : value.toLocaleString();
  return <dl className="save-card-stats" aria-label="Saved values">
    <div><dt>Clock</dt><dd>{summary.clockDisplay}</dd></div>
    <div><dt>Health</dt><dd>{number(summary.health)}</dd></div>
    <div><dt>Blood</dt><dd>{number(summary.blood)}</dd></div>
    <div><dt>Mutation</dt><dd>{number(summary.mutationLevel)}</dd></div>
    <div><dt>Level</dt><dd>{number(summary.level)}</dd></div>
    <div><dt>Coin</dt><dd>{summary.coin === undefined ? "no stack" : summary.coin.toLocaleString()}</dd></div>
  </dl>;
}

function SaveCard({ save, summary }: Readonly<{ save: SaveInspection; summary: SummaryState | undefined }>) {
  const day = save.metadata?.day;
  const playTime = playTimeLabel(save.metadata?.playTimeSeconds);
  return <>
    {save.thumbnail ? <img src={save.thumbnail} alt="" /> : <span className="save-card-placeholder" aria-hidden="true">No picture</span>}
    <span className="save-card-facts">
      <strong>{saveTypeLabel(save.metadata?.type, save.fileName)}</strong>
      <span>{savedAtLabel(save.metadata?.savedAt)}</span>
      <span>{day !== undefined ? `Day ${day + 1}` : ""}{day !== undefined && playTime ? " · " : ""}{playTime}</span>
      <small>{save.fileName}</small>
    </span>
    <SummaryFacts summary={summary} />
  </>;
}

export function SavePicker({ saves, summaries, selected, disabled = false, onChoose }: Readonly<{
  saves: readonly SaveInspection[]; summaries: SummaryMap; selected: string; disabled?: boolean; onChoose: (fileName: string) => void;
}>) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const root = useRef<HTMLDivElement>(null);
  const listId = useId();
  const chosen = saves.find(save => save.fileName === selected);

  // Close on outside click; the listbox has no backdrop of its own.
  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [open]);

  const toggle = () => {
    if (disabled) return;
    setActive(Math.max(0, saves.findIndex(save => save.fileName === selected)));
    setOpen(value => !value);
  };
  const pick = (fileName: string) => { setOpen(false); if (fileName !== selected) onChoose(fileName); };
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (disabled) return;
    if (event.key === "Escape" && open) { event.preventDefault(); setOpen(false); return; }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!open) { toggle(); return; }
      setActive(index => Math.min(saves.length - 1, Math.max(0, index + (event.key === "ArrowDown" ? 1 : -1))));
      return;
    }
    if ((event.key === "Enter" || event.key === " ") && open) { event.preventDefault(); const save = saves[active]; if (save) pick(save.fileName); }
  };

  return <div className="save-picker" ref={root} onKeyDown={onKeyDown}>
    <button type="button" className={`save-card save-picker-trigger${chosen ? "" : " save-picker-empty"}`} aria-haspopup="listbox" aria-expanded={open}
      aria-controls={listId} aria-label="Selected save" disabled={disabled} onClick={toggle}>
      {chosen ? <SaveCard save={chosen} summary={summaries[chosen.fileName]} /> : <span className="save-card-facts"><strong>Choose a save</strong><span>{saves.length} saves found — open the list to pick one</span></span>}
      <span className="save-picker-caret" aria-hidden="true">{open ? "▴" : "▾"}</span>
    </button>
    {open && <ul className="save-picker-list" role="listbox" id={listId} aria-label="Saves" aria-activedescendant={saves[active] ? `${listId}-${active}` : undefined}>
      {saves.map((save, index) => <li key={save.fileName} id={`${listId}-${index}`} role="option" aria-selected={save.fileName === selected}
        className={`save-card save-picker-option${index === active ? " save-picker-active" : ""}`} title={save.fileName}
        onMouseEnter={() => setActive(index)} onClick={() => pick(save.fileName)}>
        <SaveCard save={save} summary={summaries[save.fileName]} />
      </li>)}
    </ul>}
  </div>;
}
