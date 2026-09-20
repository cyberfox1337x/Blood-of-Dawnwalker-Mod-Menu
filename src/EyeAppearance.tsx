import { useCallback, useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, Focus, RotateCcw } from "lucide-react";
import {
  EyeLatestQueue, clampEyeYaw, clampEyeZoom, eyeIdentityMatches, eyeParameterKey,
  eyePickerHex, eyeReceiptMatches, eyeSettingsMatch, eyeSettingsSupported,
  eyeSettingsWithColor, eyeCaptureFresh, eyeObservationFresh, eyeViewSupported, validateEyeSession,
  type EyeAppearanceBridge, type EyeAppearanceSession, type EyeOperationReceipt,
  type EyeOperationRequest, type EyePreviewFrame, type EyePreviewRequest,
  type EyeReadback, type EyeSettings, type EyeView, type ReadyEyeSession,
} from "./eyeAppearanceContract";
import "./EyeAppearance.css";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_appearance_native_viewer_ui");

type Props = Readonly<{ session: EyeAppearanceSession; bridge?: EyeAppearanceBridge; active?: boolean }>;
type DesiredEyes = Readonly<{ settings: EyeSettings; revision: number }>;
type Operation = Readonly<{ kind: "apply" | "restore"; request: EyeOperationRequest; generation: number }>;
type VerifiedReceipt = Extract<EyeOperationReceipt, { status: "verified" }>;

function errorMessage(error: unknown): string {
  return error instanceof Error && error.message ? error.message : "The eye appearance connection did not complete the request.";
}

function defaultView(session: ReadyEyeSession): EyeView {
  return { yawDegrees: 0, framing: "head-and-shoulders", zoom: session.zoomBounds["head-and-shoulders"].initial };
}

export function EyeAppearance({ session, bridge, active = true }: Props) {
  if (session.availability !== "ready" || !bridge || !validateEyeSession(session)) {
    return null;
  }
  const identityKey = JSON.stringify([session.identity, session.previewId, session.renderTargetGeneration, session.baselineId, session.schema.id]);
  return <ReadyEyeAppearance key={identityKey} session={session} bridge={bridge} active={active} />;
}

function ReadyEyeAppearance({ session, bridge, active }: Readonly<{ session: ReadyEyeSession; bridge: EyeAppearanceBridge; active: boolean }>) {
  const [desired, setDesired] = useState<DesiredEyes>({ settings: session.current, revision: 0 });
  const [view, setView] = useState({ value: defaultView(session), revision: 0 });
  const [live, setLive] = useState(false);
  const [frame, setFrame] = useState<EyePreviewFrame>();
  const [readback, setReadback] = useState<EyeReadback>();
  const [receipt, setReceipt] = useState<VerifiedReceipt>();
  const [pendingOperation, setPendingOperation] = useState<string>();
  const [previewError, setPreviewError] = useState("");
  const [runtimeError, setRuntimeError] = useState("");
  const [readbackError, setReadbackError] = useState("");
  const [now, setNow] = useState(Date.now);
  const canvas = useRef<HTMLCanvasElement>(null);
  const surface = useRef<HTMLDivElement>(null);
  const drag = useRef<{ pointerId: number; clientX: number } | undefined>(undefined);
  const desiredRef = useRef(desired);
  const viewRef = useRef(view);
  const liveRef = useRef(live);
  const confirmedLive = useRef(false);
  const generation = useRef(0);
  const previewQueue = useRef<EyeLatestQueue<EyePreviewRequest> | undefined>(undefined);
  const operationQueue = useRef<EyeLatestQueue<Operation> | undefined>(undefined);
  desiredRef.current = desired;
  viewRef.current = view;
  liveRef.current = live;

  const releasePointer = useCallback(() => {
    const captured = drag.current;
    drag.current = undefined;
    if (captured && surface.current?.hasPointerCapture(captured.pointerId)) surface.current.releasePointerCapture(captured.pointerId);
  }, []);

  const changeView = useCallback((next: EyeView) => {
    const bounded = { ...next, yawDegrees: clampEyeYaw(next.yawDegrees), zoom: clampEyeZoom(next.zoom, session.zoomBounds[next.framing]) };
    const nextView = { value: bounded, revision: viewRef.current.revision + 1 };
    viewRef.current = nextView;
    setView(nextView);
  }, [session.zoomBounds]);

  const resetView = useCallback(() => changeView(defaultView(session)), [changeView, session]);

  const enqueueOperation = useCallback((kind: "apply" | "restore", eyes: DesiredEyes) => {
    const request: EyeOperationRequest = {
      identity: session.identity, baselineId: session.baselineId,
      requestId: crypto.randomUUID(), eyeRevision: eyes.revision, desired: eyes.settings,
    };
    setRuntimeError("");
    setPendingOperation(request.requestId);
    setReceipt(undefined);
    operationQueue.current?.enqueue({ kind, request, generation: generation.current });
  }, [session.identity, session.baselineId]);

  const selectEyes = useCallback((settings: EyeSettings, restore = false) => {
    if (!active || !eyeSettingsSupported(settings, session.schema)) return;
    const next = { settings, revision: desiredRef.current.revision + 1 };
    desiredRef.current = next;
    setDesired(next);
    setRuntimeError("");
    if (restore || liveRef.current) enqueueOperation(restore ? "restore" : "apply", next);
  }, [active, session.schema, enqueueOperation]);

  useEffect(() => {
    if (!active) return;
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, [active]);

  useEffect(() => {
    if (!active) {
      releasePointer();
      setFrame(undefined);
      setReadback(undefined);
      setPendingOperation(undefined);
      return;
    }
    let disposed = false;
    let decodedSequence = -1;
    const address = { identity: session.identity, previewId: session.previewId, renderTargetGeneration: session.renderTargetGeneration };
    const rejectPreview = (error: unknown) => {
      if (!disposed) { setPreviewError(errorMessage(error)); setFrame(undefined); }
    };
    const frames = new EyeLatestQueue<EyePreviewFrame>(async candidate => {
      let bitmap: ImageBitmap | undefined;
      try {
        if (disposed || candidate.sequence <= decodedSequence) return;
        bitmap = await createImageBitmap(candidate.image);
        if (disposed || candidate.sequence <= decodedSequence || !eyeCaptureFresh(candidate.captureTiming, Date.now(), session.maxFrameAgeMs)) return;
        if (bitmap.width !== candidate.width || bitmap.height !== candidate.height) throw new Error("The preview frame dimensions changed during decoding.");
        const target = canvas.current;
        const context = target?.getContext("2d", { alpha: false });
        if (!target || !context) throw new Error("The native character frame could not be displayed.");
        target.width = bitmap.width;
        target.height = bitmap.height;
        context.drawImage(bitmap, 0, 0);
        decodedSequence = candidate.sequence;
        setFrame(candidate);
        setPreviewError("");
        setNow(Date.now());
      } catch (error) { rejectPreview(error); }
      finally { bitmap?.close(); }
    });
    const cameraRequests = new EyeLatestQueue<EyePreviewRequest>(async request => {
      try { await bridge.updatePreview(request); }
      catch (error) {
        if (request.viewRevision === viewRef.current.revision && request.eyeRevision === desiredRef.current.revision) rejectPreview(error);
      }
    });
    const operations = new EyeLatestQueue<Operation>(async operation => {
      if (disposed || operation.generation !== generation.current) return;
      try {
        const result = await bridge[operation.kind](operation.request);
        if (disposed || operation.generation !== generation.current || operation.request.eyeRevision !== desiredRef.current.revision) return;
        if (result.status !== "verified") throw new Error(result.reason);
        if (!eyeReceiptMatches(result, operation.request, operation.kind, session, Date.now())) {
          throw new Error("The game did not return matching, verified eye settings.");
        }
        setReceipt(result);
        if (operation.kind === "apply") confirmedLive.current = liveRef.current;
        setReadback(previous => !previous || result.readback.observationTiming.requestSequence >= previous.observationTiming.requestSequence ? result.readback : previous);
        setRuntimeError("");
      } catch (error) {
        if (!disposed && operation.generation === generation.current && operation.request.eyeRevision === desiredRef.current.revision) {
          setReceipt(undefined);
          liveRef.current = confirmedLive.current;
          setLive(confirmedLive.current);
          setRuntimeError(errorMessage(error));
        }
      } finally {
        if (!disposed) setPendingOperation(previous => previous === operation.request.requestId ? undefined : previous);
      }
    });
    previewQueue.current = cameraRequests;
    operationQueue.current = operations;
    let unsubscribe: () => void = () => undefined;
    try {
      unsubscribe = bridge.subscribeFrames(address, candidate => {
        if (disposed || candidate.source !== "native-scene-capture" || !eyeIdentityMatches(candidate.identity, session.identity)
          || candidate.previewId !== session.previewId || candidate.renderTargetGeneration !== session.renderTargetGeneration
          || !Number.isSafeInteger(candidate.sequence) || candidate.sequence < 0 || candidate.sequence <= decodedSequence
          || !Number.isSafeInteger(candidate.eyeRevision) || !Number.isSafeInteger(candidate.viewRevision)
          || candidate.eyeRevision < 0 || candidate.viewRevision < 0 || candidate.eyeRevision > desiredRef.current.revision || candidate.viewRevision > viewRef.current.revision
          || !eyeViewSupported(candidate.view, session) || !eyeSettingsSupported(candidate.settings, session.schema) || !eyeCaptureFresh(candidate.captureTiming, Date.now(), session.maxFrameAgeMs)
          || !Number.isInteger(candidate.width) || !Number.isInteger(candidate.height) || candidate.width < 1 || candidate.height < 1
          || candidate.width > 4096 || candidate.height > 4096 || !(candidate.image instanceof Blob)
          || !["image/png", "image/webp"].includes(candidate.image.type) || candidate.image.size < 1 || candidate.image.size > 16 * 1024 * 1024) return;
        frames.enqueue(candidate);
      }, rejectPreview);
    } catch (error) { rejectPreview(error); }
    let inspecting = false;
    const inspect = async () => {
      if (disposed || inspecting) return;
      inspecting = true;
      try {
        const observation = await bridge.inspect(session.identity, session.baselineId);
        if (disposed) return;
        if (observation.source !== "runtime-material-getter" || !eyeIdentityMatches(observation.identity, session.identity)
          || observation.baselineId !== session.baselineId || !eyeSettingsSupported(observation.settings, session.schema)
          || !eyeObservationFresh(observation.observationTiming, Date.now(), session.maxReadbackAgeMs)) throw new Error("The current player's eye state could not be verified.");
        setReadback(previous => !previous || observation.observationTiming.requestSequence >= previous.observationTiming.requestSequence ? observation : previous);
        setReadbackError("");
      } catch (error) {
        if (!disposed) { setReadback(undefined); setReadbackError(errorMessage(error)); }
      } finally { inspecting = false; }
    };
    void inspect();
    const inspectionTimer = window.setInterval(() => void inspect(), Math.max(250, session.maxReadbackAgeMs / 2));
    return () => {
      disposed = true;
      generation.current += 1;
      cameraRequests.close();
      operations.close();
      frames.close();
      window.clearInterval(inspectionTimer);
      unsubscribe();
      releasePointer();
      previewQueue.current = undefined;
      operationQueue.current = undefined;
      bridge.cancelQueued(address);
    };
  }, [active, bridge, session, releasePointer]);

  useEffect(() => {
    if (active) previewQueue.current?.enqueue({ identity: session.identity, previewId: session.previewId,
      renderTargetGeneration: session.renderTargetGeneration, settings: desired.settings, eyeRevision: desired.revision,
      view: view.value, viewRevision: view.revision });
  }, [active, desired, view, session.identity, session.previewId, session.renderTargetGeneration]);

  useEffect(() => {
    const element = surface.current;
    if (!active || !element) return;
    const wheel = (event: WheelEvent) => {
      if (event.ctrlKey || event.metaKey || event.deltaY === 0) return;
      event.preventDefault();
      event.stopPropagation();
      const current = viewRef.current.value;
      const bounds = session.zoomBounds[current.framing];
      changeView({ ...current, zoom: current.zoom - Math.sign(event.deltaY) * bounds.step });
    };
    element.addEventListener("wheel", wheel, { passive: false });
    return () => element.removeEventListener("wheel", wheel);
  }, [active, changeView, session.zoomBounds]);

  const frameFresh = active && frame && eyeCaptureFresh(frame.captureTiming, now, session.maxFrameAgeMs);
  const frameCurrent = frameFresh && frame.eyeRevision === desired.revision && frame.viewRevision === view.revision
    && eyeSettingsMatch(frame.settings, desired.settings, session.schema) && frame.view.framing === view.value.framing
    && Math.abs(frame.view.yawDegrees - view.value.yawDegrees) <= 0.05 && Math.abs(frame.view.zoom - view.value.zoom) <= 0.0001;
  const applied = Boolean(frameCurrent && !runtimeError && !readbackError && !pendingOperation && receipt && receipt.eyeRevision === desired.revision
    && eyeSettingsMatch(receipt.readback.settings, desired.settings, session.schema) && readback
    && eyeObservationFresh(readback.observationTiming, now, session.maxReadbackAgeMs) && eyeSettingsMatch(readback.settings, desired.settings, session.schema));
  const zoomBounds = session.zoomBounds[view.value.framing];
  const pickerDefinitions = session.schema.parameters.filter(definition => definition.kind === "vector" && definition.picker);
  const selectedPreset = session.schema.presets.find(preset => eyeSettingsMatch(preset.settings, desired.settings, session.schema));

  return <section className="eye-appearance" aria-labelledby="eye-appearance-heading">
    <header className="eye-heading">
      <div><span className="eye-kicker">Character appearance</span><h3 id="eye-appearance-heading">Eye Appearance</h3></div>
      <div className={`eye-application-status ${applied ? "is-applied" : ""}`} role="status" aria-live="polite">
        <span aria-hidden="true" />{applied ? "Applied In Game" : "Preview Only"}
      </div>
    </header>
    <div className="eye-workspace">
      <div className="eye-preview-panel">
        <div className="eye-preview-topline"><span>{session.identity.form === "vampire" ? "Vampire appearance" : "Human appearance"}</span><span>{view.value.framing === "eyes-close-up" ? "Eyes Close-Up" : "Head & shoulders"}</span></div>
        <div ref={surface} className={`eye-preview-surface ${frameCurrent ? "is-current" : "is-updating"}`} tabIndex={active ? 0 : -1}
          role="group" aria-label="3D character preview" aria-describedby="eye-preview-input-help"
          onPointerDown={event => {
            if (!active || event.button !== 0 || event.isPrimary === false) return;
            event.preventDefault();
            event.currentTarget.focus();
            drag.current = { pointerId: event.pointerId, clientX: event.clientX };
            event.currentTarget.setPointerCapture(event.pointerId);
          }}
          onPointerMove={event => {
            const captured = drag.current;
            if (!active || !captured || captured.pointerId !== event.pointerId) return;
            const width = event.currentTarget.getBoundingClientRect().width;
            if (width <= 0) return;
            event.preventDefault();
            const delta = (event.clientX - captured.clientX) / width * 138;
            captured.clientX = event.clientX;
            changeView({ ...viewRef.current.value, yawDegrees: viewRef.current.value.yawDegrees + delta });
          }}
          onPointerUp={releasePointer} onPointerCancel={releasePointer} onLostPointerCapture={() => { drag.current = undefined; }}
          onKeyDown={event => {
            if (!active || event.altKey || event.ctrlKey || event.metaKey) return;
            const current = viewRef.current.value;
            if (event.key === "ArrowLeft" || event.key === "ArrowRight") changeView({ ...current, yawDegrees: current.yawDegrees + (event.key === "ArrowLeft" ? -3 : 3) });
            else if (["+", "=", "-"].includes(event.key)) changeView({ ...current, zoom: current.zoom + (event.key === "-" ? -zoomBounds.step : zoomBounds.step) });
            else if (event.key === "Home") resetView();
            else return;
            event.preventDefault();
            event.stopPropagation();
          }}>
          <canvas ref={canvas} hidden={!frameFresh} aria-label="Current player rendered by the game" />
          {!frameFresh && <p className="eye-frame-empty">{previewError || (frame ? "Waiting for a fresh character frame…" : "Loading the character preview…")}</p>}
          {frameFresh && !frameCurrent && <span className="eye-frame-progress">Updating preview…</span>}
        </div>
        <div className="eye-rotation">
          <button type="button" aria-label="Rotate preview left" disabled={!active || view.value.yawDegrees <= -69} onClick={() => changeView({ ...view.value, yawDegrees: view.value.yawDegrees - 3 })}><ChevronLeft aria-hidden="true" size={19} /></button>
          <div><output aria-label="Preview rotation">{Math.round(view.value.yawDegrees)}°</output><span>−69° <i aria-hidden="true" /> +69°</span></div>
          <button type="button" aria-label="Rotate preview right" disabled={!active || view.value.yawDegrees >= 69} onClick={() => changeView({ ...view.value, yawDegrees: view.value.yawDegrees + 3 })}><ChevronRight aria-hidden="true" size={19} /></button>
        </div>
        <div className="eye-view-actions">
          <button type="button" aria-pressed={view.value.framing === "eyes-close-up"} disabled={!active} onClick={() => changeView({ ...view.value, framing: "eyes-close-up", zoom: session.zoomBounds["eyes-close-up"].initial })}><Focus size={15} aria-hidden="true" />Eyes Close-Up</button>
          <button type="button" disabled={!active} onClick={resetView}><RotateCcw size={14} aria-hidden="true" />Reset View</button>
        </div>
        <label className="eye-zoom"><span>Zoom</span><input type="range" aria-label="Preview zoom" disabled={!active} min={zoomBounds.min} max={zoomBounds.max} step={zoomBounds.step} value={view.value.zoom} onChange={event => changeView({ ...view.value, zoom: Number(event.target.value) })} /></label>
        <p id="eye-preview-input-help" className="eye-input-help">Drag left or right to rotate. Scroll to zoom. Arrow keys rotate; Home resets the view.</p>
      </div>
      <div className="eye-controls-panel">
        <label className="eye-live-toggle"><span><strong>Live eye customization</strong><small>Apply supported changes to the current character.</small></span>
          <input type="checkbox" role="switch" aria-label="Live eye customization" aria-busy={Boolean(pendingOperation)} checked={live} disabled={!active || Boolean(pendingOperation)} onChange={event => {
            if (!active || pendingOperation) return;
            const enabled = event.target.checked;
            liveRef.current = enabled;
            setLive(enabled);
            if (enabled) enqueueOperation("apply", desiredRef.current);
            else { confirmedLive.current = false; generation.current += 1; operationQueue.current?.clear(); setPendingOperation(undefined); setReceipt(undefined); }
          }} />
        </label>
        {!live && <p className="eye-mode-note">Changes stay in the preview. Use Restore Original Eyes to restore any changes already applied in game.</p>}
        {session.schema.presets.length > 0 && <fieldset className="eye-presets" disabled={!active}><legend>Color presets</legend>
          <div>{session.schema.presets.map(preset => {
            const swatch = pickerDefinitions.map(definition => eyePickerHex(preset.settings, definition)).find(Boolean);
            return <button type="button" key={preset.id} aria-pressed={selectedPreset?.id === preset.id} onClick={() => selectEyes(preset.settings)}>{swatch && <span className="eye-color-swatch" style={{ backgroundColor: swatch }} aria-hidden="true" />}{preset.label}</button>;
          })}</div>
        </fieldset>}
        {pickerDefinitions.map(definition => {
          const hex = eyePickerHex(desired.settings, definition);
          return <label className="eye-color-field" key={eyeParameterKey(definition.parameter)}><span>{definition.label}</span>
            {hex ? <span><input type="color" aria-label={`${definition.label} color`} disabled={!active} value={hex} onChange={event => {
              const settings = eyeSettingsWithColor(desiredRef.current.settings, definition, event.target.value);
              if (settings) selectEyes(settings);
            }} /><output>{hex.toUpperCase()}</output></span> : <small>This setting is outside the supported color picker range.</small>}
          </label>;
        })}
        <div className="eye-restore-block"><button type="button" className="eye-restore-button" disabled={!active || Boolean(pendingOperation)} onClick={() => selectEyes(session.original, true)}><RotateCcw size={15} aria-hidden="true" />Restore Original Eyes</button>
          <p>Restore the original eyes captured for this character and form.</p></div>
        {pendingOperation && <p className="eye-pending" role="status">Verifying the eye change in game…</p>}
        {(runtimeError || previewError || readbackError) && <p className="eye-error" role="alert">{runtimeError || previewError || readbackError}</p>}
        <p className="eye-creator-note">Original eye-mod creator: Su4enka. Source and credits in Settings.</p>
      </div>
    </div>
  </section>;
}
