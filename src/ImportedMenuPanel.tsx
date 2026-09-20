import { useEffect, useId, useRef, useState } from "react";
import { isDeveloperOption } from "./catalogOptions";
import type { ImportedMenuItem, ImportedMenuSnapshot } from "./importedMenuContract";
import { IMPORTED_MENU_CATEGORIES, importedSectionMatches, type Dispatch, type ImportedFeedback, type ImportedPendingControl } from "./importedMenuState";
import "./ImportedMenuPanel.css";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_panel");

const LEADING_GLYPH = /^([^\p{L}\p{N}\s])\s*/u;
function GlyphLabel({ text }: { text: string | undefined }) {
  const match = text ? LEADING_GLYPH.exec(text) : null;
  if (!text || !match) return <>{text}</>;
  return <><span className="imported-menu-glyph" data-glyph={match[1]} aria-hidden="true">{match[1]}</span>{text.slice(match[0].length)}</>;
}

type ItemProps = { item: ImportedMenuItem; sectionId: string; disabled: boolean; pending?: boolean; pendingControl?: ImportedPendingControl; dispatch: Dispatch };
function NumberField({ item, sectionId, disabled, dispatch }: ItemProps) {
  const current = item.value ?? item.default ?? item.min ?? 0;
  const [draft, setDraft] = useState(String(current));
  const [editing, setEditing] = useState(false);
  const [error, setError] = useState("");
  const errorId = useId();
  const cancelled = useRef(false);
  const commit = () => {
    setEditing(false);
    if (cancelled.current || disabled) { cancelled.current = false; return; }
    const value = Number(draft);
    if (!draft.trim() || !Number.isFinite(value) || (item.min !== undefined && value < item.min) || (item.max !== undefined && value > item.max)) {
      setDraft(String(current)); setError("Value not applied. Enter a number within the shown limits."); return;
    }
    setError("");
    if (value !== current) void dispatch({ action: "set", sectionId, itemId: item.id, value });
  };
  return <div><label className="imported-menu-field"><span><GlyphLabel text={item.label} /></span><input type="number" value={editing ? draft : String(current)} min={item.min} max={item.max} step={item.step ?? 1} disabled={disabled} aria-describedby={error ? errorId : undefined} title={[item.min !== undefined ? `Minimum: ${item.min}` : "", item.max !== undefined ? `Maximum: ${item.max}` : ""].filter(Boolean).join(" · ")} onFocus={() => { setDraft(String(current)); setEditing(true); cancelled.current = false; }} onChange={(event) => { setDraft(event.target.value); setError(""); }} onBlur={commit} onKeyDown={(event) => { if (event.key === "Escape") { cancelled.current = true; setError(""); event.currentTarget.blur(); } else if (event.key === "Enter") event.currentTarget.blur(); }} /></label>{error && <p id={errorId} className="imported-menu-action-error" role="alert">{error}</p>}</div>;
}
function DropdownField({ item, sectionId, disabled, dispatch }: ItemProps) {
  const [query, setQuery] = useState("");
  const options = (item.options ?? []).map((option) => typeof option === "string" ? { label: option, value: option } : option);
  const selected = item.value ?? item.default;
  const visible = options.filter((option) => option.value === selected || (!isDeveloperOption(option.label) && option.label.toLowerCase().includes(query.toLowerCase())));
  return <div className="imported-menu-picker">
    {options.length > 12 && <input type="search" aria-label={`Search ${item.label}`} placeholder={item.placeholder ?? "Search…"} value={query} onChange={(event) => setQuery(event.target.value)} />}
    <label className="imported-menu-field"><span><GlyphLabel text={item.label} /></span><select disabled={disabled} value={visible.findIndex((option) => option.value === selected)} title={visible.find((option) => option.value === selected)?.label} onChange={(event) => { const option = visible[Number(event.target.value)]; if (option && option.value !== false) void dispatch({ action: "set", sectionId, itemId: item.id, value: option.value }); }}>
      <option value={-1} disabled>Select…</option>{visible.map((option, index) => <option key={`${index}:${option.label}`} value={index} disabled={option.value === false}>{option.label}</option>)}
    </select></label>
  </div>;
}
function MenuItem(props: ItemProps) {
  const { item, sectionId, dispatch } = props;
  const disabled = props.disabled || item.disabled === true || item.enabled === false;
  const readOnly = item.readOnly === true;
  const pending = Boolean(props.pending && (!props.pendingControl || (props.pendingControl.sectionId === sectionId && props.pendingControl.itemId === item.id)));
  const value = item.value ?? item.default;
  if (sectionId === "DWStoryTimer" && item.type === "label" && item.label?.startsWith("Extending the story day count is not offered"))
    return null;
  if (sectionId === "DWStoryTimer" && item.id === "notimecost" && item.label === "Remove trait time costs")
    return <MenuItem {...props} item={{ ...item, label: "Remove loaded interaction time costs" }} />;
  if (sectionId === "DWStorySettings" && (item.id === "days" || (item.id === "dayOwned" && value !== true))) return null;
  if (item.type === "row") return <div className="imported-menu-row">{item.items?.map((child, index) => <MenuItem key={child.id ?? index} {...props} item={child} disabled={disabled} />)}</div>;
  if (item.type === "separator") return <hr />;
  if (item.type === "label") return <p className="imported-menu-label">{item.label}</p>;
  if (item.type === "number") return <NumberField {...props} disabled={disabled || pending} />;
  if (item.type === "dropdown") return <DropdownField {...props} disabled={disabled || pending} />;
  if (item.type === "meter") {
    const percent = typeof value === "object" ? value.percent : typeof value === "number" ? value : 0;
    // data-meter lets the stylesheet colour each resource bar by identity.
    return <label className="imported-menu-field" data-meter={item.id}><span><GlyphLabel text={item.label} /></span><meter min={0} max={1} value={percent} /><output>{typeof value === "object" ? value.text ?? `${Math.round(percent * 100)}%` : `${Math.round(percent * 100)}%`}</output></label>;
  }
  if (item.type === "checkbox") return <label className="imported-menu-switch-row"><span><GlyphLabel text={item.label} /></span><span className="imported-menu-switch-control"><input type="checkbox" role="switch" aria-busy={pending} aria-readonly={readOnly} checked={value === true} disabled={disabled || pending || readOnly} onChange={(event) => { if (!disabled && !pending && !readOnly) void dispatch({ action: "set", sectionId, itemId: item.id, value: event.target.checked }); }} /><span className="imported-menu-switch-track" aria-hidden="true" />{(pending || disabled) && <strong>{pending ? "Applying…" : "Unavailable"}</strong>}</span></label>;
  if (item.type === "button") return <button type="button" data-variant={item.variant} aria-busy={pending} disabled={disabled || pending} onClick={() => void dispatch({ action: "invoke", sectionId, itemId: item.id })}>{pending ? "Applying…" : item.label}</button>;
  return null;
}

const INVENTORY_SECTIONS = new Set(["DWCurrency", "DWMaterials", "DWManuals", "DWKeys", "DWItems"]);
const COMBAT_SECTIONS = new Set(["DWActivationControl", "DWCooldownControl", "DWParryAssist", "DWCombatDiscovery"]);
const DIRECT_SECTIONS = new Set(["DWCombatControls", "DWFormToggle", "DWActivationControl", "DWCooldownControl", "DWParryAssist"]);
const SECTION_ORDER = ["DWCombatControls", "DWFormToggle", "DWPlayer", "DWSkills", "DWXP", "DWMutation", "DWTraitGrant", "DWUltimateControls", "DWRespec"];
export type ImportedMenuGroup = "player" | "inventory" | "combat";

/** Player separates progression from combat; equipment belongs to Inventory. */
function groupOf(sectionId: string): ImportedMenuGroup {
  if (INVENTORY_SECTIONS.has(sectionId)) return "inventory";
  if (COMBAT_SECTIONS.has(sectionId)) return "combat";
  return "player";
}

export function ImportedActionFeedback({ feedback, sections }: { feedback?: ImportedFeedback; sections: readonly string[] }) {
  return feedback && sections.includes(feedback.sectionId ?? "") ? <p className="imported-menu-action-error" role="alert">{feedback.message}</p> : null;
}

type ImportedControlProps = { snapshot: ImportedMenuSnapshot; disabled: boolean; dispatch: Dispatch; feedback?: ImportedFeedback; pending?: boolean; pendingControl?: ImportedPendingControl };

const CORRUPTION_LEVEL_ITEMS = new Set(["status", "level", "setLevel", "refresh"]);
export function ImportedXPRewards({ snapshot, disabled, dispatch, feedback, pending = false, pendingControl }: ImportedControlProps) {
  const section = snapshot.sections.find(candidate => candidate.id === "DWXPRewards");
  if (!section) return null;
  const busy = pending || snapshot.operation?.status === "queued" || snapshot.operation?.status === "running";
  return <div className="imported-menu dashboard-corruption-controls" aria-label="XP reward multiplier controls"><div className="imported-menu-items">
    {section.items.filter(item => ["multiplier", "refresh", "restore", "status"].includes(item.id ?? "")).map(item => <MenuItem key={item.id} item={item} sectionId={section.id} disabled={disabled || !snapshot.ready} pending={busy} pendingControl={pendingControl} dispatch={dispatch} />)}
    <ImportedActionFeedback feedback={feedback} sections={[section.id]} />
  </div></div>;
}
/** Experience Multiplier. The quest XP multiplier (`DWXPMultiplier`) re-runs the game's own
 *  AddQuestXP call (factor - 1) more times per award, so it is the one that verifiably moves
 *  XP; the reward-table route (`DWXPRewards`) is refused by the game and stays out of the row. */
export function ImportedXPMultiplier({ snapshot, disabled, dispatch, feedback, pending = false, pendingControl }: ImportedControlProps) {
  const section = snapshot.sections.find(candidate => candidate.id === "DWXPMultiplier");
  if (!section) return null;
  const busy = pending || snapshot.operation?.status === "queued" || snapshot.operation?.status === "running";
  return <div className="imported-menu dashboard-corruption-controls" aria-label="Experience multiplier controls"><div className="imported-menu-items">
    {section.items.filter(item => ["factor", "status", "activity"].includes(item.id ?? "")).map(item => <MenuItem key={item.id} item={item} sectionId={section.id} disabled={disabled || !snapshot.ready} pending={busy} pendingControl={pendingControl} dispatch={dispatch} />)}
    <ImportedActionFeedback feedback={feedback} sections={[section.id]} />
  </div></div>;
}
export function ImportedCorruptionLevel({ snapshot, disabled, dispatch, feedback, pending = false, pendingControl }: ImportedControlProps) {
  const section = snapshot.sections.find(candidate => candidate.id === "DWMutation");
  if (!section) return null;
  const busy = pending || snapshot.operation?.status === "queued" || snapshot.operation?.status === "running";
  return <div className="imported-menu dashboard-corruption-controls" aria-label="Corruption controls"><div className="imported-menu-items">
    {section.items.filter(item => CORRUPTION_LEVEL_ITEMS.has(item.id ?? "")).map(item => <MenuItem key={item.id} item={item} sectionId={section.id} disabled={disabled || !snapshot.ready} pending={busy} pendingControl={pendingControl} dispatch={dispatch} />)}
    <ImportedActionFeedback feedback={feedback} sections={[section.id]} />
  </div></div>;
}

/** The sidebar uses the same native item renderer and pending/feedback contract. */
/** The Player Status module parks these in its status label while it has nothing to
 *  report. The meters already show "—" when disconnected, so the line is dropped; any
 *  other message it writes (such as the activation-charge safety notice) still shows. */
const IDLE_PLAYER_STATUS = new Set(["Load a save to view player status", "Live player status"]);

export function ImportedPlayerStatus({ snapshot, disabled, dispatch, feedback, pending = false, pendingControl }: ImportedControlProps) {
  const section = snapshot.sections.find(candidate => candidate.id === "DWPlayer");
  if (!section) return null;
  const operationPending = pending || Boolean(pendingControl && (snapshot.operation?.status === "queued" || snapshot.operation?.status === "running"));
  const items = section.items.filter(item => !(item.id === "status" && IDLE_PLAYER_STATUS.has((item.label ?? "").trim())));
  return <div className="imported-menu dashboard-player-status" data-imported-section="DWPlayer" aria-label="Player status">
    <div className="imported-menu-items">{items.map((item, index) => <MenuItem key={item.id ?? index} item={item} sectionId={section.id} disabled={disabled || !snapshot.ready} pending={operationPending} pendingControl={pendingControl} dispatch={dispatch} />)}
      <ImportedActionFeedback feedback={feedback} sections={[section.id]} />
    </div>
  </div>;
}

export function ImportedMenuPanel({ category, snapshot, disabled, dispatch, query = "", group, feedback, pending = false, pendingControl, excludeSections = [], onlySections, showToolbar = true, corruptionAdvancedOnly = false }: ImportedControlProps & { category: string; query?: string; group?: ImportedMenuGroup; excludeSections?: readonly string[]; onlySections?: readonly string[]; showToolbar?: boolean; corruptionAdvancedOnly?: boolean }) {
  const operationPending = pending || Boolean(pendingControl && (snapshot.operation?.status === "queued" || snapshot.operation?.status === "running"));
  const sections = snapshot.sections.filter((section) => !excludeSections.includes(section.id) && (!onlySections || onlySections.includes(section.id)) && IMPORTED_MENU_CATEGORIES[section.id] === category && importedSectionMatches(section, query) && (group === undefined || groupOf(section.id) === group)).sort((first, second) => {
    const rank = (id: string) => SECTION_ORDER.includes(id) ? SECTION_ORDER.indexOf(id) : 100;
    return rank(first.id) - rank(second.id);
  });
  if (!sections.length) return null;
  return <section className="imported-menu" data-category={category} data-group={group} aria-label="Additional game controls">
    {showToolbar && <header className="imported-menu-toolbar">
    <h3 className="imported-menu-heading">{group === "inventory" ? "Items & equipment" : group === "combat" ? "Combat assists" : category === "player" ? "Player & progression" : "Game controls"}</h3>
    {/* One Refresh per page: the primary group owns the page-level refresh. */}
    {group !== "combat" && <button type="button" disabled={disabled} onClick={() => void dispatch({ action: "refresh" })}>Refresh game lists & status</button>}
    </header>}
    {/* Only a message the runtime actually sent. The disabled controls already say
        the menu is not connected, and the reminder was repeated on every group. */}
    {!snapshot.ready && snapshot.message && <p className="imported-menu-status">{snapshot.message}</p>}
    <ImportedActionFeedback feedback={feedback} sections={[""]} />
    {!feedback && snapshot.operation?.status === "failed" && snapshot.operation.message && <p className="imported-menu-status" role="alert">{snapshot.operation.message}</p>}
    <div className="imported-menu-cards">
    {sections.map((section) => {
      const visibleItems = corruptionAdvancedOnly && section.id === "DWMutation" ? section.items.filter(item => !CORRUPTION_LEVEL_ITEMS.has(item.id ?? "")) : section.items;
      const items = <div className="imported-menu-items">{visibleItems.map((item, index) => <MenuItem key={item.id ?? index} item={item} sectionId={section.id} disabled={disabled} pending={operationPending} pendingControl={pendingControl} dispatch={dispatch} />)}<ImportedActionFeedback feedback={feedback} sections={[section.id]} /></div>;
      if (DIRECT_SECTIONS.has(section.id)) {
        const status = section.items.find((item) => item.id === "status");
        const notes = section.items.filter((item) => item.type === "label" && item.id !== "status");
        return <section className="dashboard-card imported-menu-direct" key={section.id} data-imported-section={section.id} aria-label={section.title}><h4><GlyphLabel text={section.title} /></h4><div className="imported-menu-items">
          {section.items.filter((item) => item.type === "checkbox").map((item) => <MenuItem key={item.id} item={item} sectionId={section.id} disabled={disabled} pending={operationPending} pendingControl={pendingControl} dispatch={dispatch} />)}
          {status && <p className="imported-menu-toggle-status">{status.label}</p>}
          <ImportedActionFeedback feedback={feedback} sections={[section.id]} />
          {notes.map((item, index) => <MenuItem key={index} item={item} sectionId={section.id} disabled={disabled} pending={operationPending} pendingControl={pendingControl} dispatch={dispatch} />)}
        </div></section>;
      }
      return <section className="dashboard-card imported-menu-group" key={section.id} data-imported-section={section.id} aria-label={section.title}><h4><GlyphLabel text={section.title} /></h4>{items}</section>;
    })}
    </div>
  </section>;
}

export function ImportedMenuConfirmation({ snapshot, pending, dispatch }: { snapshot: ImportedMenuSnapshot; pending: boolean; dispatch: Dispatch }) {
  const confirmation = snapshot.confirmation;
  const cancelButton = useRef<HTMLButtonElement>(null);
  const dialog = useRef<HTMLElement>(null);
  const lastControl = useRef<HTMLElement | null>(null);
  const token = confirmation?.token;
  useEffect(() => {
    const rememberControl = (event: FocusEvent) => {
      if (!dialog.current && event.target instanceof HTMLElement && event.target !== document.body) lastControl.current = event.target;
    };
    document.addEventListener("focusin", rememberControl);
    return () => document.removeEventListener("focusin", rememberControl);
  }, []);
  useEffect(() => {
    if (!token) return;
    // The requesting button can lose focus when it becomes pending/disabled.
    const previous = lastControl.current ?? (document.activeElement instanceof HTMLElement ? document.activeElement : null);
    const containFocus = (event: FocusEvent) => {
      if (dialog.current && !dialog.current.contains(event.target as Node)) dialog.current.focus();
    };
    if (cancelButton.current?.disabled) dialog.current?.focus();
    else cancelButton.current?.focus();
    document.addEventListener("focusin", containFocus);
    return () => {
      document.removeEventListener("focusin", containFocus);
      if (previous?.isConnected) previous.focus();
    };
  }, [token]);
  if (!confirmation) return null;
  const respond = (confirmed: boolean) => void dispatch({ action: "confirm", confirmationToken: confirmation.token, confirmed });
  return <div className="imported-menu-dialog-backdrop"><section ref={dialog} tabIndex={-1} role="dialog" aria-modal="true" aria-labelledby="imported-confirm-title" aria-describedby="imported-confirm-message" className="imported-menu-dialog" onKeyDown={(event) => {
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); if (!pending && snapshot.ready) respond(false); }
    if (event.key === "Tab") {
      const buttons = event.currentTarget.querySelectorAll<HTMLButtonElement>("button:not(:disabled)");
      const first = buttons[0], last = buttons[buttons.length - 1];
      if (!first) { event.preventDefault(); event.currentTarget.focus(); }
      else if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog.current)) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && (document.activeElement === last || document.activeElement === dialog.current)) { event.preventDefault(); first.focus(); }
    }
  }}><h2 id="imported-confirm-title">{confirmation.title}</h2><p id="imported-confirm-message">{confirmation.message}</p><footer><button ref={cancelButton} disabled={pending || !snapshot.ready} onClick={() => respond(false)}>{confirmation.cancelLabel ?? "Cancel"}</button><button disabled={pending || !snapshot.ready} onClick={() => respond(true)}>{confirmation.confirmLabel ?? "Confirm"}</button></footer></section></div>;
}
