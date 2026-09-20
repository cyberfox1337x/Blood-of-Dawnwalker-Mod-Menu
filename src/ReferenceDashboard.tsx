import { useEffect, useRef, useState, type ReactNode } from "react";
import { Backpack, Footprints, Globe2, HeartPulse, MapPin, PersonStanding, Sparkles, Swords, type LucideIcon } from "lucide-react";
import type { ImportedMenuItem, ImportedMenuSnapshot } from "./importedMenuContract";
import type { Dispatch, ImportedFeedback, ImportedPendingControl } from "./importedMenuState";
import "./ReferenceDashboard.css";
import { ImportedPlayerStatus, ImportedCorruptionLevel, ImportedXPRewards, ImportedXPMultiplier } from "./ImportedMenuPanel";
import { MovementSpeedControl } from "./MovementSpeedControl";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("reference_dashboard");

type Destination = "inventory" | "player" | "world" | "teleport";
type Props = { snapshot: ImportedMenuSnapshot; disabled: boolean; pending: boolean; pendingControl?: ImportedPendingControl; feedback?: ImportedFeedback; dispatch: Dispatch; open: (destination: Destination) => void; query: string; category?: string; children?: ReactNode; categoryFooter?: ReactNode };
function findItem(snapshot: ImportedMenuSnapshot, sectionId: string, itemId: string) {
  const scan = (items: ImportedMenuItem[]): ImportedMenuItem | undefined => {
    for (const item of items) { if (item.id === itemId) return item; const nested = item.items && scan(item.items); if (nested) return nested; }
    return undefined;
  };
  return scan(snapshot.sections.find(section => section.id === sectionId)?.items ?? []);
}
function Card({ title, icon: Icon, children, open }: { title: string; icon: LucideIcon; children: ReactNode; open?: () => void }) {
  return <section className="dashboard-card" aria-label={`${title} overview`}><header><Icon size={18} /><h2>{title}</h2>{open && <button className="dashboard-more" onClick={open} title={`Open all ${title} controls`} aria-label={`All ${title} controls`}>All controls ›</button>}</header><div className="dashboard-card-body">{children}</div></section>;
}
/** A control the game has not published yet - shown disabled so the card keeps its
 *  shape while the menu is disconnected. Every label here is backed by a real native
 *  section; controls with no runtime behind them are not rendered at all. */
function Placeholder({ label, kind = "toggle", icon: Icon }: { label: string; kind?: "toggle" | "slider" | "select" | "number" | "button"; icon?: LucideIcon }) {
  const help = `${label}: unavailable until the menu is connected to a loaded save`;
  if (kind === "button") return <button className="dashboard-action" disabled title={help}>{Icon && <Icon size={17} />}{label}</button>;
  return <div className="dashboard-row" title={help}><span>{label}</span>{kind === "toggle" ? <button className="toggle" role="switch" aria-label={label} aria-checked={false} disabled><span /></button> : kind === "slider" ? <span className="dashboard-slider"><input type="range" aria-label={label} disabled value={0} readOnly /><output>—</output></span> : kind === "select" ? <select aria-label={label} disabled><option>Unavailable</option></select> : <span className="dashboard-stepper"><button disabled aria-label={`Decrease ${label}`}>−</button><output>—</output><button disabled aria-label={`Increase ${label}`}>+</button></span>}</div>;
}
type PlaceholderKind = "toggle" | "slider" | "select" | "number" | "button";
const PLAYER_OPTION_PLACEHOLDERS: [string, PlaceholderKind][] = [["Rapid stamina refill", "toggle"], ["Vampire form override", "toggle"], ["Infinite Health", "toggle"], ["Super Jump", "toggle"], ["No Clip", "toggle"], ["Fly", "toggle"], ["Speed Multiplier", "slider"], ["Blood Energy", "slider"], ["Corruption", "number"], ["Experience Multiplier", "slider"]];
// Fly and the Speed Multiplier slider belong together, so all four movement controls
// render inside one labeled block. The block owns its own grid: Fly keeps the slider on
// the same row at every window size, so the slider can never be pushed onto a separate
// full-width row away from Fly again when the outer column count changes.
const PLAYER_MOVEMENT_OPTIONS = ["Super Jump", "No Clip", "Fly", "Speed Multiplier"] as const;
function BloodEnergyAmount({ item, disabled, pending, dispatch, refresh, recovery, status, hasReadback }: { item: ImportedMenuItem; disabled: boolean; pending: boolean; dispatch: Dispatch; refresh?: ImportedMenuItem; recovery?: ImportedMenuItem; status?: string; hasReadback: boolean }) {
  const [draft, setDraft] = useState<number>();
  const dirty = useRef(false);
  const current = hasReadback && typeof item.value === "number" && Number.isFinite(item.value) ? item.value : undefined;
  const unavailable = disabled || pending || item.disabled === true || item.enabled === false || current === undefined;
  function commit(value: number) {
    if (!dirty.current) return;
    dirty.current = false; setDraft(undefined);
    if (!unavailable && Number.isFinite(value) && value >= 0 && value <= 100 && value !== current) void dispatch({ action: "set", sectionId: "DWCorePlayer", itemId: "bloodPercent", value });
  }
  return <div className="dashboard-option-group"><label className="dashboard-row" title={unavailable ? status || "Read resources and turn off God Mode and Infinite Blood Energy to set the amount." : "Set the current blood amount as a percentage."}><span>Blood Energy</span><span className="dashboard-slider"><input type="range" aria-label="Blood Energy" min={0} max={100} step={1} value={draft ?? current ?? 0} disabled={unavailable} aria-busy={pending} onChange={event => { dirty.current = true; setDraft(Number(event.target.value)); }} onPointerUp={event => commit(Number(event.currentTarget.value))} onBlur={event => commit(Number(event.currentTarget.value))} onKeyUp={event => { if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(event.key)) commit(Number(event.currentTarget.value)); }} onKeyDown={event => { if (event.key === "Escape") { dirty.current = false; setDraft(undefined); } }} /><output>{current === undefined ? "—" : `${Math.round(draft ?? current)}%`}</output></span></label>
    {unavailable && refresh && <button className="dashboard-action" disabled={disabled || pending || refresh.disabled === true || refresh.enabled === false} onClick={() => void dispatch({ action: "invoke", sectionId: "DWCorePlayer", itemId: "refresh" })}>Read blood amount</button>}
    {recovery?.value === true && <button className="dashboard-action" disabled={disabled || pending || recovery.disabled === true || recovery.enabled === false} onClick={() => void dispatch({ action: "set", sectionId: "DWCorePlayer", itemId: "bloodRecovery", value: false })}>Restore Blood Energy</button>}
  </div>;
}
function MovementOption({ label, sectionId, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback"> & { label: string; sectionId: string }) {
  const control = findItem(snapshot, sectionId, "enabled");
  if (!control) return <Placeholder label={label} />;
  const refresh = findItem(snapshot, sectionId, "refresh");
  const busy = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued") && (!pendingControl || pendingControl.sectionId === sectionId);
  const unavailable = disabled || !snapshot.ready || busy;
  const enabled = snapshot.ready && control.value === true;
  const message = feedback?.sectionId === sectionId ? feedback.message : snapshot.ready ? findItem(snapshot, sectionId, "status")?.label : "Connect to read movement status.";
  return <div className="dashboard-option-group"><div className="dashboard-row"><span>{label}</span><button className={`toggle ${enabled ? "toggle-on" : ""}`} role="switch" aria-label={label} aria-checked={enabled} aria-busy={busy} disabled={unavailable || control.enabled === false || control.disabled === true} onClick={() => void dispatch({ action: "set", sectionId, itemId: "enabled", value: !enabled })}><span /></button></div>
    {label === "No Clip" && <p className="dashboard-option-status">WASD moves · Space rises · Q descends. OFF returns to the starting position.</p>}
    {refresh && <button className="dashboard-action" disabled={unavailable || refresh.disabled === true || refresh.enabled === false} onClick={() => void dispatch({ action: "invoke", sectionId, itemId: "refresh" })}>{refresh.label ?? `Verify ${label}`}</button>}
    {message && <p className="dashboard-option-status" role={feedback?.sectionId === sectionId ? "alert" : "status"}>{message}</p>}
  </div>;
}
export function PlayerOptions({ query, only, exclude, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "query" | "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback">
  // only/exclude let a caller render a control somewhere else without it appearing
  // twice. The Player panel keeps progression controls in the Player level card, the
  // movement controls in their own labeled block, and Blood Energy after that block.
  & { only?: readonly string[]; exclude?: readonly string[] }) {
  const health = findItem(snapshot, "DWCorePlayer", "healthEnabled");
  // Rapid stamina refill and Vampire form override were moved out of their own panels
  // into Player controls. CombatControls and FormToggleControl still own the
  // behaviour; both publish their checkbox into DWCorePlayer, so they render here
  // exactly like Infinite Health, and fall back to a placeholder when absent.
  const MOVED_PLAYER_TOGGLES: Readonly<Record<string, string>> = {
    "Rapid stamina refill": "staminaRefill",
    "Vampire form override": "formOverride",
  };
  const blood = findItem(snapshot, "DWCorePlayer", "bloodPercent");
  const bloodMeter = findItem(snapshot, "DWCorePlayer", "blood")?.value;
  const bloodHasReadback = snapshot.ready && (blood?.enabled !== false || (typeof bloodMeter === "object" && bloodMeter !== null && "text" in bloodMeter && typeof bloodMeter.text === "string" && bloodMeter.text !== "Unread" && bloodMeter.text !== ""));
  const bloodPending = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued") && (!pendingControl || (pendingControl.sectionId === "DWCorePlayer" && ["bloodPercent", "refresh", "bloodRecovery"].includes(pendingControl.itemId ?? "")));
  const healthPending = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued") && (!pendingControl || (pendingControl.sectionId === "DWCorePlayer" && pendingControl.itemId === "healthEnabled"));
  return <>{PLAYER_OPTION_PLACEHOLDERS.filter(([label]) => !only || only.includes(label)).filter(([label]) => !exclude?.includes(label)).filter(([label]) => !query || label.toLowerCase().includes(query.toLowerCase())).map(([label, kind]) => {
    if (label === "Corruption" && snapshot.sections.some(section => section.id === "DWMutation")) return <ImportedCorruptionLevel key={label} snapshot={snapshot} disabled={disabled} pending={pending} pendingControl={pendingControl} dispatch={dispatch} feedback={feedback} />;
    // The quest XP multiplier is the route that verifiably moves XP; the reward-table route
    // is only shown on a payload that has nothing better.
    if (label === "Experience Multiplier" && snapshot.sections.some(section => section.id === "DWXPMultiplier")) return <ImportedXPMultiplier key={label} snapshot={snapshot} disabled={disabled} pending={pending} pendingControl={pendingControl} dispatch={dispatch} feedback={feedback} />;
    if (label === "Experience Multiplier" && snapshot.sections.some(section => section.id === "DWXPRewards")) return <ImportedXPRewards key={label} snapshot={snapshot} disabled={disabled} pending={pending} pendingControl={pendingControl} dispatch={dispatch} feedback={feedback} />;
    if (label === "Speed Multiplier" && snapshot.sections.some(section => section.id === "DWSpeed")) return <MovementSpeedControl key={`${label}-${snapshot.sessionId}`} snapshot={snapshot} disabled={disabled} pending={pending} pendingControl={pendingControl} dispatch={dispatch} feedback={feedback} />;
    if (label === "No Clip" || label === "Super Jump" || label === "Fly") return <MovementOption key={label} label={label} sectionId={label === "No Clip" ? "DWNoClip" : label === "Fly" ? "DWPersonalFly" : "DWSuperJump"} snapshot={snapshot} disabled={disabled} pending={pending} pendingControl={pendingControl} dispatch={dispatch} feedback={feedback} />;
    if (label === "Blood Energy" && blood) return <BloodEnergyAmount key={`${label}-${snapshot.sessionId}`} item={blood} hasReadback={bloodHasReadback} disabled={disabled || !snapshot.ready} pending={bloodPending} dispatch={dispatch} refresh={findItem(snapshot, "DWCorePlayer", "refresh")} recovery={findItem(snapshot, "DWCorePlayer", "bloodRecovery")} status={findItem(snapshot, "DWCorePlayer", "status")?.label} />;
    const movedItemId = MOVED_PLAYER_TOGGLES[label];
    if (movedItemId) {
      const moved = findItem(snapshot, "DWCorePlayer", movedItemId);
      if (!moved) return <Placeholder key={label} label={label} kind={kind} />;
      const movedPending = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued")
        && (!pendingControl || (pendingControl.sectionId === "DWCorePlayer" && pendingControl.itemId === movedItemId));
      const movedUnavailable = disabled || !snapshot.ready || moved.disabled === true || moved.enabled === false || movedPending;
      const movedEnabled = snapshot.ready && moved.value === true;
      return <div key={label} className="dashboard-row"><span>{label}</span><button className={`toggle ${movedEnabled ? "toggle-on" : ""}`} role="switch" aria-label={label} aria-checked={movedEnabled} aria-busy={movedPending} disabled={movedUnavailable} onClick={() => { if (!movedUnavailable) void dispatch({ action: "set", sectionId: "DWCorePlayer", itemId: movedItemId, value: !movedEnabled }); }}><span /></button></div>;
    }
    if (label !== "Infinite Health" || !health) return <Placeholder key={label} label={label} kind={kind} />;
    const unavailable = disabled || !snapshot.ready || health.disabled === true || health.enabled === false || healthPending;
    const enabled = snapshot.ready && health.value === true;
    return <div key={label} className="dashboard-row"><span>{label}</span><button className={`toggle ${enabled ? "toggle-on" : ""}`} role="switch" aria-label={label} aria-checked={enabled} aria-busy={healthPending} disabled={unavailable} onClick={() => { if (!unavailable) void dispatch({ action: "set", sectionId: "DWCorePlayer", itemId: "healthEnabled", value: !enabled }); }}><span /></button></div>;
  })}</>;
}
/** The Player's movement controls, drawn as one labeled block so Fly and the Speed
 *  Multiplier slider stay together. They keep the same native sections, the same
 *  placeholders when a section is not published, and the same status/verify/restore
 *  controls as when they were loose rows in the Player options list. */
export function PlayerMovementControls({ query, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "query" | "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback">) {
  const shows = (label: string) => !query || label.toLowerCase().includes(query.toLowerCase());
  const superJump = shows("Super Jump");
  const noClip = shows("No Clip");
  const fly = shows("Fly");
  const speed = shows("Speed Multiplier");
  if (!superJump && !noClip && !fly && !speed) return null;
  const movement = { snapshot, disabled, pending, pendingControl, dispatch, feedback };
  // DWSpeed owns the multiplier and its restore; without it the slider stays a
  // disabled placeholder instead of a control that silently does nothing.
  const speedControl = snapshot.sections.some(section => section.id === "DWSpeed")
    ? <MovementSpeedControl key={snapshot.sessionId} {...movement} />
    : <Placeholder label="Speed Multiplier" kind="slider" />;
  return <section className="dashboard-option-group player-movement-controls" aria-label="Movement controls" data-search-label={PLAYER_MOVEMENT_OPTIONS.join(" ").toLowerCase()}>
    <h4 className="player-movement-heading">Movement</h4>
    <div className="player-movement-grid">
      {superJump && <MovementOption label="Super Jump" sectionId="DWSuperJump" {...movement} />}
      {noClip && <MovementOption label="No Clip" sectionId="DWNoClip" {...movement} />}
      {(fly || speed) && <div className="player-flight-row">
        {fly && <MovementOption label="Fly" sectionId="DWPersonalFly" {...movement} />}
        {speed && speedControl}
      </div>}
    </div>
  </section>;
}
/** The ability switches and item controls the Player controls card adds on top of the
 *  gameplay toggles that already live in PlayerOptions. Each one keeps its own native
 *  section, state, pending and feedback - only where it is drawn and what it is called
 *  change, which is why the source sections are excluded from the panels that used to
 *  draw them. */
const PLAYER_ABILITY_OPTIONS = ["Unlimited Activation Charge", "Instant Ability Cooldown", "Super Damage / One-Hit Kills"] as const;
const PLAYER_ITEM_OPTIONS = ["Unlimited Consumables", "Edit Item Amount", "Zero Weight", "Ignore Crafting Requirement", "Unlock All Crafting Recipes"] as const;
/** Controls the reference list asks for that this runtime has no verified native route
 *  for. They are drawn disabled and say why: several have no setter at all in the
 *  captured build, and wiring the nearest call that compiles would report a result the
 *  game never confirmed, which is worse than an honest "not yet". */
const UNVERIFIED_PLAYER_OPTIONS: Readonly<Record<string, string>> = {
  "Super Damage / One-Hit Kills": "The running mod has not published its super-damage switch. Update the payload: the switch multiplies the melee, claws and magic damage attributes through private effects on your own ability system.",
  "Unlimited Consumables": "The running mod has not published its consumables switch. Update the payload: the switch refunds each consumable right after the game takes it.",
  "Edit Item Amount": "The running mod has not published its item-amount controls. Update the payload: they raise or lower an owned stack with the game's own add and remove calls.",
  "Ignore Crafting Requirement": "The running mod has not published its free-crafting switch. Update the payload: the switch routes every craft through the game's own free-craft path.",
};
/** One native switch drawn as a Player controls row: label and help on the left, the
 *  switch on the right, exactly like the rows beside it. */
function PlayerNativeSwitch({ label, sectionId, itemId = "enabled", help, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback"> & { label: string; sectionId: string; itemId?: string; help?: string }) {
  const control = findItem(snapshot, sectionId, itemId);
  if (!control) return <Placeholder label={label} />;
  const busy = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued")
    && (!pendingControl || (pendingControl.sectionId === sectionId && pendingControl.itemId === itemId));
  const unavailable = disabled || !snapshot.ready || control.disabled === true || control.enabled === false;
  const enabled = snapshot.ready && control.value === true;
  const message = feedback?.sectionId === sectionId ? feedback.message : snapshot.ready ? findItem(snapshot, sectionId, "status")?.label : "Connect to read this control.";
  return <div className="dashboard-option-group"><div className="dashboard-row">
    <span className="player-toggle-label" title={help}><span>{label}</span>{help && <small>{help}</small>}</span>
    <span className="player-toggle-control">
      {unavailable && <span className="player-toggle-state" aria-hidden="true">Unavailable</span>}
      <button className={`toggle ${enabled ? "toggle-on" : ""}`} role="switch" aria-label={label} aria-checked={enabled} aria-busy={busy} disabled={unavailable || busy}
        onClick={() => { if (!unavailable && !busy) void dispatch({ action: "set", sectionId, itemId, value: !enabled }); }}><span /></button>
    </span>
  </div>
    {message && <p className="dashboard-option-status" role={feedback?.sectionId === sectionId ? "alert" : "status"}>{message}</p>}
  </div>;
}
/** Carry weight. The row always offers the project's read-only capacity check. When the
 *  running mod also publishes the `zeroWeight` switch (CarryCapacityEffectPilot.lua: a
 *  private GameplayEffect owned by the player's own ASC that takes the effective limit to
 *  the engine's exact-zero "no limit" sentinel, applied and removed through GAS), the row
 *  shows that switch too. An older payload without the switch keeps the check-only row. */
function PlayerCarryWeightCheck({ help, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback"> & { help?: string }) {
  const probe = findItem(snapshot, "DWWeight", "probe");
  const zeroWeight = findItem(snapshot, "DWWeight", "zeroWeight");
  // Offline the row keeps its shape - label left, action right - with the action refused,
  // so the card reads the same before and after the game connects.
  if (!probe) return <div className="dashboard-option-group"><div className="dashboard-row" title="Zero Weight: unavailable until the menu is connected to a loaded save">
    <span className="player-toggle-label"><span>Zero Weight</span></span>
    <button className="dashboard-action" disabled>Run check</button>
  </div></div>;
  const operationBusy = pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued";
  const busy = operationBusy && (!pendingControl || (pendingControl.sectionId === "DWWeight" && pendingControl.itemId === "probe"));
  const switchBusy = operationBusy && pendingControl?.sectionId === "DWWeight" && pendingControl.itemId === "zeroWeight";
  const unavailable = disabled || !snapshot.ready || probe.disabled === true || probe.enabled === false;
  const switchUnavailable = disabled || !snapshot.ready || !zeroWeight || zeroWeight.disabled === true || zeroWeight.enabled === false;
  const enabled = zeroWeight?.value === true;
  const message = feedback?.sectionId === "DWWeight" ? feedback.message : snapshot.ready ? findItem(snapshot, "DWWeight", "status")?.label : "Connect to run the carry-weight check.";
  return <div className="dashboard-option-group">
    {zeroWeight && <div className="dashboard-row">
      <span className="player-toggle-label" title="Takes the effective carry limit to exactly zero, which the game treats as no limit: nothing is refused for weight and you are never over-encumbered. Turning it off removes that exact effect and checks the original limit came back.">
        <span>Zero Weight</span><small>No carry limit while on. Requires the read-only check to pass on this session; refused otherwise.</small>
      </span>
      <button className={`toggle ${enabled ? "toggle-on" : ""}`} role="switch" aria-label="Zero Weight" aria-checked={enabled} aria-busy={switchBusy}
        disabled={switchUnavailable || switchBusy}
        onClick={() => { if (!switchUnavailable && !switchBusy) void dispatch({ action: "set", sectionId: "DWWeight", itemId: "zeroWeight", value: !enabled }); }}><span /></button>
    </div>}
    <div className="dashboard-row">
      <span className="player-toggle-label" title={help}><span>{zeroWeight ? "Carry-weight check" : "Zero Weight"}</span>{help && <small>{help}</small>}</span>
      <button className="dashboard-action" aria-busy={busy} disabled={unavailable || busy}
        onClick={() => { if (!unavailable && !busy) void dispatch({ action: "invoke", sectionId: "DWWeight", itemId: "probe" }); }}>{busy ? "Running…" : "Run check"}</button>
    </div>
    {message && <p className="dashboard-option-status" role={feedback?.sectionId === "DWWeight" ? "alert" : "status"}>{message}</p>}
  </div>;
}
/** Edit Item Amount: an owned stack, the exact count it should have, one Set. The mod's
 *  DWItemAmount section publishes the owned-item list (label "Name  xN"), holds the
 *  amount and does the verified add/remove; this row only drives those three items. */
function PlayerItemAmount({ snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback">) {
  const picker = findItem(snapshot, "DWItemAmount", "item");
  const amount = findItem(snapshot, "DWItemAmount", "amount");
  const apply = findItem(snapshot, "DWItemAmount", "apply");
  const [draft, setDraft] = useState("");
  if (!picker || !amount || !apply) return <UnverifiedOption label="Edit Item Amount" kind="number" reason={UNVERIFIED_PLAYER_OPTIONS["Edit Item Amount"]} />;
  const options = (picker.options ?? []).map(option => typeof option === "string" ? { label: option, value: option } : option).filter(option => option.value !== false);
  const selected = typeof picker.value === "string" ? picker.value : "";
  const busy = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued")
    && (!pendingControl || pendingControl.sectionId === "DWItemAmount");
  const unavailable = disabled || !snapshot.ready || apply.disabled === true || apply.enabled === false;
  const current = typeof amount.value === "number" ? amount.value : Number(amount.default ?? 1);
  const target = draft.trim() === "" ? current : Number(draft);
  const targetValid = Number.isSafeInteger(target) && target >= 0 && target <= (amount.max ?? 999);
  const message = feedback?.sectionId === "DWItemAmount" ? feedback.message : snapshot.ready ? findItem(snapshot, "DWItemAmount", "status")?.label : "Connect to edit item amounts.";
  const send = async () => {
    if (unavailable || busy || !selected || !targetValid) return;
    if (target !== current) await dispatch({ action: "set", sectionId: "DWItemAmount", itemId: "amount", value: target });
    await dispatch({ action: "invoke", sectionId: "DWItemAmount", itemId: "apply" });
    setDraft("");
  };
  return <div className="dashboard-option-group player-item-amount">
    <div className="dashboard-row">
      <span className="player-toggle-label" title="Sets an owned stack to the exact count you type: the game's own add call raises it, its remove call lowers it, and the count is read back."><span>Edit Item Amount</span><small>Pick an owned item, type the count it should have, press Set.</small></span>
      <span className="player-item-amount-controls">
        <select aria-label="Item to edit" value={selected} disabled={unavailable || busy || !options.length}
          onChange={event => { void dispatch({ action: "set", sectionId: "DWItemAmount", itemId: "item", value: event.target.value }); }}>
          <option value="">{options.length ? "Choose an owned item" : "No items listed yet"}</option>
          {options.map(option => <option key={String(option.value)} value={String(option.value)}>{option.label}</option>)}
        </select>
        <input aria-label="Edit Item Amount" inputMode="numeric" value={draft} placeholder={String(current)} disabled={unavailable || busy}
          onChange={event => setDraft(event.target.value)} onKeyDown={event => { if (event.key === "Enter") void send(); }} />
        <button className="dashboard-action" aria-busy={busy} disabled={unavailable || busy || !selected || !targetValid} onClick={() => void send()}>{busy ? "Setting…" : "Set"}</button>
        <button className="dashboard-action" disabled={unavailable || busy} title="Re-read the inventory list"
          onClick={() => { void dispatch({ action: "invoke", sectionId: "DWItemAmount", itemId: "refresh" }); }}>Refresh</button>
      </span>
    </div>
    {!targetValid && draft.trim() !== "" && <p className="dashboard-option-status" role="alert">Enter a whole number from 0 to {amount.max ?? 999}.</p>}
    {message && <p className="dashboard-option-status" role={feedback?.sectionId === "DWItemAmount" ? "alert" : "status"}>{message}</p>}
  </div>;
}
/** A requested control with no verified route, drawn disabled with the reason on the row
 *  so the card never implies it is one connected click away. */
function UnverifiedOption({ label, reason, kind = "toggle" }: { label: string; reason: string; kind?: PlaceholderKind }) {
  return <div className="dashboard-option-group"><div className="dashboard-row" title={`${label}: ${reason}`} data-control-state="locked">
    <span className="player-toggle-label"><span>{label}</span><small>{reason}</small></span>
    {kind === "toggle"
      ? <button className="toggle" role="switch" aria-label={label} aria-checked={false} disabled><span /></button>
      : <span className="dashboard-stepper"><button disabled aria-label={`Decrease ${label}`}>−</button><output>—</output><button disabled aria-label={`Increase ${label}`}>+</button></span>}
  </div></div>;
}
/** Unlocking every crafting recipe belongs with the other Player controls; the crafting
 *  section keeps its own status read and daily-supply refill, so nothing is drawn twice. */
function PlayerCraftingUnlock({ help, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback"> & { help?: string }) {
  const unlock = findItem(snapshot, "DWCrafting", "unlock");
  if (!unlock) return <Placeholder label="Unlock All Crafting Recipes" kind="button" />;
  const busy = (pending || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued")
    && (!pendingControl || (pendingControl.sectionId === "DWCrafting" && pendingControl.itemId === "unlock"));
  const unavailable = disabled || !snapshot.ready || unlock.disabled === true || unlock.enabled === false;
  const message = feedback?.sectionId === "DWCrafting" ? feedback.message : snapshot.ready ? findItem(snapshot, "DWCrafting", "status")?.label : "Connect to unlock crafting recipes.";
  return <div className="dashboard-option-group"><div className="dashboard-row">
    <span className="player-toggle-label" title={help}><span>Unlock All Crafting Recipes</span>{help && <small>{help}</small>}</span>
    <button className="dashboard-action" aria-busy={busy} disabled={unavailable || busy}
      onClick={() => { if (!unavailable && !busy) void dispatch({ action: "invoke", sectionId: "DWCrafting", itemId: "unlock" }); }}>{busy ? "Applying…" : "Unlock"}</button>
  </div>
    {message && <p className="dashboard-option-status" role={feedback?.sectionId === "DWCrafting" ? "alert" : "status"}>{message}</p>}
  </div>;
}
/** Super Damage / One-Hit Kills: the mod's `DWSuperDamage` switch (SuperDamageEffectPilot.lua:
 *  three private additive GameplayEffects on the player's melee, claws and magic damage
 *  multipliers, applied and removed through GAS) with its multiplier beside it. The
 *  multiplier is sent on its own; a live effect follows it, an idle one waits for the switch. */
function PlayerSuperDamage(props: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback">) {
  return <PlayerMultiplierSwitch sectionId="DWSuperDamage" label="Super Damage / One-Hit Kills" multiplierLabel="Damage multiplier" help="Multiplies your sword, claw and spell damage through private effects on your own ability system. x100 one-shots ordinary enemies. Fists are not covered." {...props} />;
}
/** Extended Parry Window: the same owned-effect pilot on the player's ParryWindowMultiplier
 *  (`DWParryWindow`). Rendered by the Player combat block in place of its old notice. */
export function PlayerParryWindow(props: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback">) {
  if (!findItem(props.snapshot, "DWParryWindow", "enabled")) return null;
  return <PlayerMultiplierSwitch sectionId="DWParryWindow" label="Extended Parry Window" multiplierLabel="Parry window multiplier" help="Widens the parry timing window through a private effect on your own ability system. x2 doubles it." {...props} />;
}
/** One owned-effect switch with its multiplier beside it. The multiplier is sent on its own;
 *  a live effect follows it, an idle one waits for the switch. */
function PlayerMultiplierSwitch({ sectionId, label, multiplierLabel, help, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback"> & { sectionId: string; label: string; multiplierLabel: string; help: string }) {
  const multiplier = findItem(snapshot, sectionId, "multiplier");
  const unavailable = disabled || !snapshot.ready || !multiplier || multiplier.disabled === true || multiplier.enabled === false;
  return <>
    <PlayerNativeSwitch label={label} sectionId={sectionId} help={help} snapshot={snapshot} disabled={disabled} pending={pending} pendingControl={pendingControl} dispatch={dispatch} feedback={feedback} />
    {multiplier && <div className="dashboard-row player-super-damage-multiplier">
      <span className="player-toggle-label"><span>{multiplierLabel}</span><small>Whole number from {multiplier.min ?? 2} to {multiplier.max ?? 1000}.</small></span>
      <DashboardNumber key={snapshot.sessionId} label={multiplierLabel} item={multiplier} disabled={unavailable || pending} draftChanged={() => {}} commit={value => { void dispatch({ action: "set", sectionId, itemId: "multiplier", value }); }} />
    </div>}
  </>;
}
/** The Player controls card's ability and item rows, in the order the reference lists them.
 *  A search shows only the rows it names, the same way the movement block behaves. */
export function PlayerReferenceControls({ query, snapshot, disabled, pending, pendingControl, dispatch, feedback }: Pick<Props, "query" | "snapshot" | "disabled" | "pending" | "pendingControl" | "dispatch" | "feedback">) {
  const needle = query.trim().toLowerCase();
  const matches = (label: string) => !needle || label.toLowerCase().includes(needle);
  const abilities = PLAYER_ABILITY_OPTIONS.some(matches);
  const items = PLAYER_ITEM_OPTIONS.some(matches);
  if (!abilities && !items) return null;
  const native = { snapshot, disabled, pending, pendingControl, dispatch, feedback };
  return <>
    {abilities && <>
      <h4 className="player-control-group-heading">Abilities</h4>
      {matches("Unlimited Activation Charge") && <PlayerNativeSwitch label="Unlimited Activation Charge" sectionId="DWActivationControl" help="Keeps activation charges full during combat, up to your unlocked limit." {...native} />}
      {matches("Instant Ability Cooldown") && <PlayerNativeSwitch label="Instant Ability Cooldown" sectionId="DWCooldownControl" help="Quickly clears cooldowns. Charge, blood and item costs still apply." {...native} />}
      {matches("Super Damage / One-Hit Kills") && (findItem(snapshot, "DWSuperDamage", "enabled")
        ? <PlayerSuperDamage {...native} />
        : <UnverifiedOption label="Super Damage / One-Hit Kills" reason={UNVERIFIED_PLAYER_OPTIONS["Super Damage / One-Hit Kills"]} />)}
    </>}
    {items && <>
      <h4 className="player-control-group-heading">{"Items & crafting"}</h4>
      {matches("Unlimited Consumables") && (findItem(snapshot, "DWItemAmount", "unlimitedConsumables")
        ? <PlayerNativeSwitch label="Unlimited Consumables" sectionId="DWItemAmount" itemId="unlimitedConsumables" help="Food, draughts and ointments are refunded right after each use, so the stack never shrinks. Manuals, readables, keys and quest items are never touched." {...native} />
        : <UnverifiedOption label="Unlimited Consumables" reason={UNVERIFIED_PLAYER_OPTIONS["Unlimited Consumables"]} />)}
      {matches("Edit Item Amount") && <PlayerItemAmount {...native} />}
      {matches("Zero Weight") && <PlayerCarryWeightCheck help="Carry weight is read-only until the project's own read-only capacity check passes in the running game. This runs that check and changes nothing." {...native} />}
      {matches("Ignore Crafting Requirement") && (findItem(snapshot, "DWFreeCrafting", "enabled")
        ? <PlayerNativeSwitch label="Ignore Crafting Requirement" sectionId="DWFreeCrafting" help="Crafts through the game's own free-craft path, so no ingredients are checked or spent and the Craft button stays live with an empty pouch. Recipes still need unlocking; Craft all still counts real ingredients." {...native} />
        : <UnverifiedOption label="Ignore Crafting Requirement" reason={UNVERIFIED_PLAYER_OPTIONS["Ignore Crafting Requirement"]} />)}
      {matches("Unlock All Crafting Recipes") && <PlayerCraftingUnlock help="Permanently marks every crafting recipe unlocked. It bypasses the manuals and discoveries that normally grant them and cannot be undone from this menu." {...native} />}
    </>}
  </>;
}
function DashboardNumber({ label, item, disabled, commit, draftChanged }: { label: string; item?: ImportedMenuItem; disabled: boolean; commit: (value: number) => void; draftChanged: (value: number | undefined) => void }) {
  const current = typeof item?.value === "number" ? item.value : typeof item?.default === "number" ? item.default : 0;
  const [draft, setDraft] = useState(String(current));
  const [editing, setEditing] = useState(false);
  const [error, setError] = useState("");
  const valid = (value: number) => Number.isFinite(value) && value >= (item?.min ?? 0) && value <= (item?.max ?? 2147483647);
  function apply(value: number) {
    if (!valid(value)) { setError("Enter a number within the allowed limits."); return; }
    setError(""); draftChanged(value); if (value !== current && !disabled) commit(value);
  }
  return <span className="dashboard-number"><span className="dashboard-stepper"><button aria-label={`Decrease ${label}`} disabled={disabled || !valid(current - (item?.step ?? 1))} onClick={() => apply(current - (item?.step ?? 1))}>−</button><input type="number" aria-label={label} min={item?.min ?? 0} max={item?.max ?? 2147483647} step={item?.step ?? 1} value={editing ? draft : current} disabled={disabled} aria-invalid={Boolean(error)} title={error || label} onFocus={() => { setDraft(String(current)); setEditing(true); }} onChange={event => { setDraft(event.target.value); draftChanged(Number.NaN); }} onBlur={() => { if (!editing) return; setEditing(false); if (draft.trim()) apply(Number(draft)); else { setError("Enter a number."); draftChanged(Number.NaN); } }} onKeyDown={event => { if (event.key === "Enter") event.currentTarget.blur(); if (event.key === "Escape") { setEditing(false); setDraft(String(current)); draftChanged(undefined); setError(""); } }} /><button aria-label={`Increase ${label}`} disabled={disabled || !valid(current + (item?.step ?? 1))} onClick={() => apply(current + (item?.step ?? 1))}>+</button></span>{error && <small role="alert">{error}</small>}</span>;
}
export function ReferenceDashboard(props: Props) {
  const { snapshot, open, query, category = "overview", children } = props;
  const hasPlayerStatus = snapshot.sections.some(section => section.id === "DWPlayer");
  const item = (section: string, id: string) => findItem(snapshot, section, id);
  const unavailable = (section: string, id: string) => { const control = item(section, id); return props.disabled || !snapshot.ready || !control || control.disabled === true || control.enabled === false; };
  const busy = (section: string, id: string) => props.pending && (!props.pendingControl || (props.pendingControl.sectionId === section && props.pendingControl.itemId === id));
  const send = (sectionId: string, itemId: string, value?: string | number | boolean) => { if (!unavailable(sectionId, itemId) && !busy(sectionId, itemId)) void props.dispatch({ action: value === undefined ? "invoke" : "set", sectionId, itemId, ...(value === undefined ? {} : { value }) }); };
  const toggle = (label: string, section: string, id: string) => <div className="dashboard-row"><span>{label}</span><button className={`toggle ${snapshot.ready && item(section, id)?.value === true ? "toggle-on" : ""}`} role="switch" aria-label={label} aria-checked={snapshot.ready && item(section, id)?.value === true} aria-busy={busy(section, id)} disabled={unavailable(section, id) || busy(section, id)} onClick={() => send(section, id, item(section, id)?.value !== true)}><span /></button></div>;
  const action = (label: string, section: string, id: string, Icon?: LucideIcon) => <button className="dashboard-action" disabled={unavailable(section, id) || busy(section, id)} aria-busy={busy(section, id)} onClick={() => send(section, id)}>{Icon && <Icon size={17} />}{busy(section, id) ? "Applying…" : label}</button>;
  const select = (label: string, section: string, id: string) => { const control = item(section, id); const options = (control?.options ?? []).map(option => typeof option === "string" ? { label: option, value: option } : option); const current = control?.value ?? control?.default; return <label className="dashboard-row"><span>{label}</span><select aria-label={label} disabled={unavailable(section, id) || busy(section, id)} value={options.findIndex(option => option.value === current)} onChange={event => { const option = options[Number(event.target.value)]; if (option && option.value !== false) send(section, id, option.value); }}><option value={-1} disabled>Select…</option>{options.map((option, index) => <option key={index} value={index} disabled={option.value === false}>{option.label}</option>)}</select></label>; };
  const [savedName, setSavedName] = useState("");
  const nativeName = item("DWCoreTeleport", "name")?.value;
  const [goldDraft, setGoldDraft] = useState<number>();
  const goldAmount = item("DWCurrency", "amount");
  const numberControl = () => <DashboardNumber key={snapshot.sessionId} label="Gold amount" item={goldAmount} disabled={unavailable("DWCurrency", "amount") || props.pending} draftChanged={setGoldDraft} commit={value => send("DWCurrency", "amount", value)} />;  const [speedDraft, setSpeedDraft] = useState<number>();
  useEffect(() => {
    setSavedName("");
    setGoldDraft(undefined);
    setSpeedDraft(undefined);
  }, [snapshot.sessionId]);
  const speed = item("DWCoreWorld", "speed");
  const liveSpeed = typeof speed?.value === "number" ? speed.value : 1;
  const level = item("DWCoreLevel", "current")?.value;
  const meter = (label: string, id: string, Icon: LucideIcon) => { const value = item("DWCorePlayer", id)?.value; const read = snapshot.ready && typeof value === "object" ? value : undefined; const display = id === "blood" && typeof read?.percent === "number" && Number.isFinite(read.percent) && read.text !== "Unread" && read.text !== "" ? `${Math.round(read.percent * 100)}%` : read?.text; return <div className={`dashboard-resource dashboard-resource-${id}`}><div><Icon size={14} /><span>{label}</span><output>{display ?? "—"}</output></div><meter min={0} max={1} value={read?.percent ?? 0} aria-label={label} /></div>; };
  const matches = (text: string) => category === "overview" && (!query || text.toLowerCase().includes(query.toLowerCase()));
  // Player Info and Location belong with the player: the overview and the Player tab
  // show them; every other category gets the full width for its own controls.
  const showSidebar = category === "overview" || category === "player";
  return <div id={category === "overview" ? "panel-overview" : undefined} className={`reference-dashboard ${category !== "overview" ? "reference-category" : ""}`} data-reference-category={category}>
    <div className="dashboard-layout" data-sidebar={showSidebar ? "true" : "false"}><div className="dashboard-main">
      {matches("player god mode health stamina blood humanity skills level experience speed super jump no clip") && <Card title="Player" icon={PersonStanding} open={() => open("player")}>
        {toggle("God Mode", "DWCorePlayer", "god")}<PlayerOptions {...props} query="Infinite Health" /><PlayerMovementControls {...props} query="" />{toggle("Unlimited Stamina", "DWCorePlayer", "sprintEnabled")}{toggle("Infinite Blood Energy", "DWCorePlayer", "bloodEnabled")}<PlayerOptions {...props} query="Blood Energy" /><PlayerOptions {...props} query="Corruption" />
        <div className="dashboard-row"><span>Unlock All Skills</span>{action("Unlock", "DWUltimateControls", "unlockAll")}</div>
        <div className="dashboard-row"><span>Level</span><span className="dashboard-stepper"><button disabled title="Use verified level targets below">−</button><output>{snapshot.ready && typeof level === "number" ? level : "—"}</output><button onClick={() => open("player")} aria-label="Open verified level controls" title="Open verified level targets and Apply">+</button></span></div>
        <PlayerOptions {...props} query="Experience Multiplier" />
      </Card>}
      {matches("combat infinite blood cooldown parry difficulty") && <Card title="Combat" icon={Swords} open={() => open("player")}>
        {toggle("No Cooldowns", "DWCooldownControl", "enabled")}{toggle("Auto Parry While Blocking", "DWParryAssist", "enabled")}{select("RPG Difficulty", "DWCoreDifficulty", "rpg")}
      </Card>}
      {matches("world game speed") && <Card title="World" icon={Globe2} open={() => open("world")}>
        <label className="dashboard-row"><span>Game Speed</span><span className="dashboard-slider"><input type="range" aria-label="Game Speed" min={speed?.min ?? .1} max={speed?.max ?? 3} step={speed?.step ?? .1} value={speedDraft ?? liveSpeed} disabled={unavailable("DWCoreWorld", "speed") || busy("DWCoreWorld", "speed")} onChange={event => setSpeedDraft(Number(event.target.value))} onPointerUp={() => { if (speedDraft !== undefined) send("DWCoreWorld", "speed", speedDraft); setSpeedDraft(undefined); }} onKeyUp={event => { if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(event.key) && speedDraft !== undefined) { send("DWCoreWorld", "speed", speedDraft); setSpeedDraft(undefined); } }} /><output>{snapshot.ready ? `${speedDraft ?? liveSpeed}×` : "—"}</output></span></label>
      </Card>}
      {matches("inventory gold item") && <Card title="Inventory" icon={Backpack} open={() => open("inventory")}>
        <div className="dashboard-row dashboard-gold"><span>Add Gold</span>{numberControl()}<button className="dashboard-action" disabled={unavailable("DWCurrency", "add") || props.pending || (goldDraft !== undefined && goldDraft !== (goldAmount?.value ?? goldAmount?.default))} onClick={() => send("DWCurrency", "add")}>Add</button></div>
        <div className="dashboard-inline-action">{select("Add Item", "DWItems", "item")}{action("Add", "DWItems", "give")}</div>
      </Card>}
      {matches("teleport marker save saved location") && <Card title="Teleport" icon={Sparkles} open={() => open("teleport")}>
        <button className="dashboard-action" onClick={() => open("teleport")} title="Open the installed in-game marker travel controls"><MapPin size={16} />Teleport to Marker ›</button>
        <div className="dashboard-row dashboard-save"><span>Save Location</span><input aria-label="New saved location name" placeholder="Enter name…" value={savedName} disabled={unavailable("DWCoreTeleport", "name") || props.pending} onChange={event => setSavedName(event.target.value)} onBlur={() => { if (savedName.trim() && savedName.trim() !== nativeName) send("DWCoreTeleport", "name", savedName.trim()); }} /><button disabled={unavailable("DWCoreTeleport", "save") || props.pending || !savedName.trim() || savedName.trim() !== nativeName} onClick={() => send("DWCoreTeleport", "save")} title="Enter a name, then leave the field to confirm it before saving">Save</button></div>
        <div className="dashboard-inline-action">{select("Saved Locations", "DWCoreTeleport", "destination")}{action("Teleport", "DWCoreTeleport", "teleport")}</div>
      </Card>}
      <div className="dashboard-category-content" hidden={category === "overview"}>{children}{props.categoryFooter && <div className="dashboard-category-footer">{props.categoryFooter}</div>}</div>
    </div>{showSidebar && <aside className="dashboard-sidebar">
      <Card title="Player Info" icon={PersonStanding}><div className="dashboard-identity"><PersonStanding size={42} /><div><strong>Coen</strong><span>The Dawnwalker</span>{!hasPlayerStatus && <small>Level {snapshot.ready && typeof level === "number" ? level : "—"}</small>}</div></div>{hasPlayerStatus ? <ImportedPlayerStatus {...props} /> : <>{meter("Health", "health", HeartPulse)}{meter("Stamina", "stamina", Footprints)}</>}{meter("Blood Energy", "blood", Sparkles)}<div className="dashboard-resource" aria-label="Corruption status"><div><PersonStanding size={14} /><span>Corruption</span></div><p className="dashboard-option-status">{snapshot.ready ? item("DWMutation", "status")?.label ?? "Unavailable" : "Connect to read Corruption status."}</p></div></Card>
      <Card title="Location" icon={MapPin}><div className="dashboard-location"><strong>{snapshot.ready ? "Current position" : "Not connected"}</strong><span>{snapshot.ready ? item("DWCoreWorld", "location")?.label ?? "Refresh World to read location" : "X: —   Y: —   Z: —"}</span></div></Card>
    </aside>}</div>
    {props.feedback && <p className="dashboard-feedback" role="alert">{props.feedback.message}</p>}
  </div>;
}
