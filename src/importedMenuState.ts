import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ImportedMenuDispatchRequest, ImportedMenuSection, ImportedMenuSnapshot, ImportedMenuTransport } from "./importedMenuContract";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("imported_menu_state");

export const IMPORTED_MENU_CATEGORIES: Readonly<Record<string, string>> = {
  DWPlayer: "player", DWCombatControls: "player", DWFormToggle: "player", DWSkills: "player", DWXP: "player", DWMutation: "player",
  DWTraitGrant: "player", DWUltimateControls: "player", DWRespec: "player", DWCurrency: "inventory",
  DWMaterials: "inventory", DWManuals: "inventory", DWKeys: "inventory", DWItems: "inventory",
  // Combat assists live in a Combat section inside Player; there is no Combat tab.
  DWActivationControl: "player", DWCooldownControl: "player", DWParryAssist: "player", DWCombatDiscovery: "player",
  DWShrines: "teleport", DWInfamyControl: "world", DWTimeControl: "world", DWStoryTimer: "world", DWStorySettings: "world",

  // Sections added after this map was first written. A section is only reachable if it
  // appears here or has a bespoke component, so every one of these was published by the
  // game and rendered nowhere - several of them verified working but unclickable.
  DWQuickslots: "inventory", DWCrafting: "inventory", DWLoadout: "inventory",
  DWCourtAlert: "world", DWClock: "world", DWTimelessCourt: "world",
  // Legacy diagnostic sections remain excluded from the menu by DEV_TESTING_SECTIONS.
  DWHubTabs: "settings", DWHubTags: "settings", DWTutorialDismiss: "settings",
  DWTraitPoints: "player", DWXPMultiplier: "player", DWBloodSegments: "player",
  // Not "visuals": that tab belongs to the native eye appearance flow, and keeping
  // imported sections out of it is a deliberate, tested invariant.
  DWPhotoCamera: "world", DWEyeColor: "player",

  // Deliberately unmapped, and to stay that way:
  // DWMenuWarnings - the user removed the Warnings & Limitations wall from Settings.
  // The *Readback, *Observation and *Test sections are developer probes, not features.
};
// Removed diagnostic panels stay excluded from General even when the runtime supplies them.
export const DEV_TESTING_SECTIONS: readonly string[] = ["DWHubTags", "DWHubTabs", "DWTutorialDismiss"];
const EMPTY_SNAPSHOT: ImportedMenuSnapshot = { schema: 1, sessionId: "", revision: 0, ready: false, sections: [] };
export type Dispatch = (request: Omit<ImportedMenuDispatchRequest, "sessionId">) => Promise<void>;
export type ImportedFeedback = { sectionId?: string; message: string };
export type ImportedPendingControl = { sectionId?: string; itemId?: string };
/** A switch flipped by the user that the game has not confirmed yet. */
type OptimisticSwitch = { sectionId: string; itemId: string; value: boolean; session: string; at: number };
// A toggle that the game never answers must not stay flipped for ever.
const OPTIMISTIC_SWITCH_TTL_MS = 8_000;

// The game answers a switch on its next tick and the menu sees it a poll later, which
// reads as lag. The requested value is shown at once and kept until the game's snapshot
// carries it (or the request fails, the session changes, or the wait runs out).
function withOptimisticSwitch(snapshot: ImportedMenuSnapshot, optimistic: OptimisticSwitch | undefined): ImportedMenuSnapshot {
  if (!optimistic || !snapshot.ready || snapshot.sessionId !== optimistic.session) return snapshot;
  return {
    ...snapshot,
    sections: snapshot.sections.map(section => section.id !== optimistic.sectionId ? section : {
      ...section,
      items: section.items.map(item => item.id === optimistic.itemId && item.type === "checkbox" ? { ...item, value: optimistic.value } : item),
    }),
  };
}

export function importedSectionMatches(section: ImportedMenuSection, query: string): boolean {
  return JSON.stringify(section).toLowerCase().includes(query.trim().toLowerCase());
}

export function useImportedMenu(active: boolean, transport: ImportedMenuTransport | undefined = window.dawnwalkerDesktop?.importedMenu) {
  const [snapshot, setSnapshot] = useState(EMPTY_SNAPSHOT);
  // The runtime bumps `revision` on every label, value, option, message or operation
  // change, so this small key is exactly "did anything the menu shows change"; the
  // heartbeat is left out on purpose. Stringifying the whole 200 KB snapshot on every
  // 750 ms poll to learn the same thing was most of the renderer's idle work.
  const projectionKey = (value: ImportedMenuSnapshot) => JSON.stringify({
    sessionId: value.sessionId, revision: value.revision, ready: value.ready, message: value.message,
    operation: value.operation, confirmation: value.confirmation, messages: value.messages,
    buildId: value.buildId, sections: value.sections.length,
  });
  const renderedProjection = useRef<string | undefined>(projectionKey(EMPTY_SNAPSHOT));
  const acceptSnapshot = useCallback((next: ImportedMenuSnapshot) => {
    // Transport still validates every poll. Heartbeat-only changes do not alter controls.
    const projection = projectionKey(next);
    if (projection === renderedProjection.current) return;
    renderedProjection.current = projection;
    setSnapshot(next);
  }, []);
  const [pending, setPending] = useState(false);
  const [optimistic, setOptimistic] = useState<OptimisticSwitch>();
  const [queuedSwitch, setQueuedSwitch] = useState<{ request: Omit<ImportedMenuDispatchRequest, "sessionId">; session: string; at: number; transport: ImportedMenuTransport }>();
  const queuedSwitchRef = useRef(false);
  const [activeControl, setActiveControl] = useState<ImportedPendingControl>();
  const [message, setMessage] = useState("");
  const [feedback, setFeedback] = useState<ImportedFeedback>();
  // True while the visible feedback is the transient "still applying" notice, so it can
  // be withdrawn once nothing is applying instead of waiting for the next control press.
  const busyNotice = useRef(false);
  const lastRequest = useRef<{ session: string; sectionId?: string; operationId?: string; questRefresh?: boolean } | undefined>(undefined);
  const busy = useRef(false);
  const generation = useRef(0);
  useEffect(() => {
    if (!active || !transport) return;
    let stopped = false;
    let polling = false;
    let timer: ReturnType<typeof setTimeout>;
    // No control is visible while F10 has hidden the menu. A visibility event refreshes
    // immediately when it returns, so slower hidden polling cuts background file/IPC work
    // without making the first visible state stale.
    const pollDelay = () => document.hidden ? 10_000 : 750;
    const poll = async () => {
      if (stopped || polling) return;
      if (busy.current) { timer = setTimeout(() => void poll(), pollDelay()); return; }
      polling = true;
      const started = generation.current;
      try {
        const next = await transport.state();
        if (!stopped && started === generation.current) acceptSnapshot(next);
      } catch (error) {
        // A command's newer readback supersedes errors from an older poll too.
        if (!stopped && started === generation.current) {
          renderedProjection.current = undefined;
          setSnapshot((current) => ({ ...current, ready: false, message: error instanceof Error ? error.message : "Menu connection unavailable." }));
          setMessage(error instanceof Error ? error.message : "Menu connection unavailable.");
        }
      } finally {
        polling = false;
        if (!stopped) timer = setTimeout(() => void poll(), pollDelay());
      }
    };
    const visibilityChanged = () => {
      clearTimeout(timer);
      if (polling) return;
      if (document.hidden) timer = setTimeout(() => void poll(), pollDelay());
      else void poll();
    };
    document.addEventListener("visibilitychange", visibilityChanged);
    void poll();
    return () => { stopped = true; clearTimeout(timer); document.removeEventListener("visibilitychange", visibilityChanged); };
  }, [active, transport, acceptSnapshot]);
  const dispatchTracked = useCallback(async (request: Omit<ImportedMenuDispatchRequest, "sessionId">) => {
    if (!transport || !snapshot.ready || !snapshot.sessionId) return;
    if (queuedSwitchRef.current || busy.current || snapshot.operation?.status === "running" || snapshot.operation?.status === "queued") {
      // A read of the quest journal is safe to finish before one user switch intent.
      // Never queue behind mutations, confirmations, or an unidentified operation.
      const previous = lastRequest.current;
      const knownQuestRead = previous?.questRefresh && previous.session === snapshot.sessionId
        && (busy.current || previous.operationId === snapshot.operation?.id);
      if (!queuedSwitchRef.current && knownQuestRead && request.action === "set"
        && typeof request.value === "boolean" && request.sectionId && request.itemId && !snapshot.confirmation) {
        queuedSwitchRef.current = true;
        const at = Date.now();
        setQueuedSwitch({ request, session: snapshot.sessionId, at, transport });
        setOptimistic({ sectionId: request.sectionId, itemId: request.itemId, value: request.value, session: snapshot.sessionId, at });
        setFeedback(undefined);
        return;
      }
      // Marked so it can clear itself: this notice describes a moment, not a state.
      busyNotice.current = true;
      setFeedback({ sectionId: request.sectionId, message: "Another game change is still applying. Try this control when it finishes." });
      return;
    }
    busy.current = true;
    busyNotice.current = false;
    generation.current += 1;
    setPending(true);
    setActiveControl({ sectionId: request.sectionId, itemId: request.itemId });
    if (request.action === "set" && typeof request.value === "boolean" && request.sectionId && request.itemId) {
      setOptimistic({ sectionId: request.sectionId, itemId: request.itemId, value: request.value, session: snapshot.sessionId, at: Date.now() });
    }
    setFeedback(undefined);
    const scopedRequest = { session: snapshot.sessionId, sectionId: request.sectionId, operationId: undefined as string | undefined,
      questRefresh: request.action === "invoke" && request.sectionId === "DWQuestReadback" && request.itemId === "refresh" };
    lastRequest.current = scopedRequest;
    try {
      const result = await transport.dispatch({ ...request, sessionId: snapshot.sessionId });
      setMessage(result.message);
      if (!result.accepted) {
        lastRequest.current = undefined;
        if (!queuedSwitchRef.current) setOptimistic(undefined);
        setFeedback({ sectionId: request.sectionId, message: result.message });
      }
      const next = await transport.state();
      // New transports identify the exact command. Retain same-session fallback
      // for older adapters, but never attach a request to a previous receipt.
      const operationId = result.accepted ? result.operationId ?? (next.sessionId === scopedRequest.session
        && next.operation?.id !== snapshot.operation?.id ? next.operation?.id : undefined) : undefined;
      if (result.accepted) scopedRequest.operationId = operationId;
      acceptSnapshot(next);
      return { accepted: result.accepted, operationId, sessionId: scopedRequest.session };
    } catch (error) {
      renderedProjection.current = undefined;
      setOptimistic(undefined);
      setSnapshot((current) => ({ ...current, ready: false }));
      setMessage(error instanceof Error ? error.message : "The menu request failed.");
      setFeedback({ sectionId: request.sectionId, message: error instanceof Error ? error.message : "The menu request failed." });
    } finally { generation.current += 1; busy.current = false; setPending(false); }
  }, [snapshot.ready, snapshot.sessionId, snapshot.operation?.id, snapshot.operation?.status, snapshot.confirmation, transport, acceptSnapshot]);
  const dispatch: Dispatch = useCallback(async (request) => { await dispatchTracked(request); }, [dispatchTracked]);
  useEffect(() => {
    if (!queuedSwitch) return;
    const cancel = () => {
      queuedSwitchRef.current = false;
      setQueuedSwitch(undefined);
      setOptimistic(undefined);
      setFeedback({ sectionId: queuedSwitch.request.sectionId, message: "The queued toggle was canceled. Check the game connection and try again." });
    };
    const remaining = OPTIMISTIC_SWITCH_TTL_MS - (Date.now() - queuedSwitch.at);
    if (!active || transport !== queuedSwitch.transport || !snapshot.ready || snapshot.sessionId !== queuedSwitch.session || snapshot.confirmation || remaining <= 0) {
      cancel();
      return;
    }
    if (!busy.current && snapshot.operation?.status !== "queued" && snapshot.operation?.status !== "running") {
      queuedSwitchRef.current = false;
      setQueuedSwitch(undefined);
      void dispatchTracked(queuedSwitch.request);
      return;
    }
    const timer = setTimeout(cancel, remaining);
    return () => clearTimeout(timer);
  }, [queuedSwitch, active, transport, snapshot, pending, dispatchTracked]);
  useEffect(() => {
    const request = lastRequest.current;
    // Nothing is applying any more, so the notice saying otherwise is simply wrong.
    if (busyNotice.current && !busy.current
      && snapshot.operation?.status !== "running" && snapshot.operation?.status !== "queued") {
      busyNotice.current = false;
      setFeedback(undefined);
    }
    if (request && snapshot.sessionId && snapshot.sessionId !== request.session) { setFeedback(undefined); return; }
    if (request?.operationId && snapshot.operation?.id === request.operationId && snapshot.operation.status === "failed") {
      setFeedback({ sectionId: request.sectionId, message: snapshot.operation.message ?? "The game could not complete this action. Try again after checking the control status." });
    }
  }, [snapshot]);
  // Drop the optimistic value once the game reports it (or contradicts it after failing).
  useEffect(() => {
    if (!optimistic) return;
    const item = snapshot.sections.find(section => section.id === optimistic.sectionId)?.items.find(entry => entry.id === optimistic.itemId);
    const confirmed = !queuedSwitch && !pending && snapshot.operation?.status !== "running"
      && snapshot.operation?.status !== "queued" && item?.value === optimistic.value;
    const failed = lastRequest.current?.operationId !== undefined && snapshot.operation?.id === lastRequest.current.operationId && snapshot.operation.status === "failed";
    const expired = Date.now() - optimistic.at > OPTIMISTIC_SWITCH_TTL_MS;
    if (confirmed || failed || expired || (snapshot.sessionId && snapshot.sessionId !== optimistic.session)) { setOptimistic(undefined); return; }
    const timer = setTimeout(() => setOptimistic(current => current === optimistic ? undefined : current), OPTIMISTIC_SWITCH_TTL_MS - (Date.now() - optimistic.at));
    return () => clearTimeout(timer);
  }, [snapshot, optimistic, queuedSwitch, pending]);
  const viewSnapshot = useMemo(() => withOptimisticSwitch(snapshot, optimistic), [snapshot, optimistic]);
  const operationBusy = snapshot.operation?.status === "running" || snapshot.operation?.status === "queued";
  return { snapshot: viewSnapshot, pending: pending || Boolean(queuedSwitch), pendingControl: queuedSwitch
    ? { sectionId: queuedSwitch.request.sectionId, itemId: queuedSwitch.request.itemId }
    : pending || operationBusy ? activeControl : undefined, message, feedback, dispatch, dispatchTracked, disabled: !snapshot.ready || Boolean(snapshot.confirmation) };
}
