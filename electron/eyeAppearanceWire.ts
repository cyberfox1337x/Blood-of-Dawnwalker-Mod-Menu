import type { EyeCoordinatorSettings, EyeCoordinatorView, EyeCoordinatorParameter, EyeCoordinatorFrame, EyeCoordinatorTiming } from "./eyeSessionCoordinator.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_appearance_wire");

// Main-safe structured-clone DTOs. No renderer imports, Blob, Electron event,
// native UObject, filesystem path or raw native report crosses this boundary.
export type EyeServiceIdentity = Readonly<{
  buildId: string; sessionId: string; worldGeneration: string; pawnId: string;
  appearanceRevision: string; form: "human"; isWolfForm: false; meshId: string; eyeMaterialGeneration: string;
}>;
export type EyeServiceAddress = Readonly<{ identity: EyeServiceIdentity; previewId: string; renderTargetGeneration: string }>;
export type EyeServicePreviewRequest = EyeServiceAddress & Readonly<{
  viewRevision: number; eyeRevision: number; view: EyeCoordinatorView; settings: EyeCoordinatorSettings;
}>;
export type EyeServiceOperationRequest = Readonly<{
  identity: EyeServiceIdentity; baselineId: string; requestId: string; eyeRevision: number; desired: EyeCoordinatorSettings;
}>;
export type EyeServiceReadback = Readonly<{
  source: "runtime-material-getter"; identity: EyeServiceIdentity; baselineId: string;
  observationTiming: EyeCoordinatorTiming; settings: EyeCoordinatorSettings;
}>;
export type EyeServiceReceipt = Readonly<{
  status: "verified"; operation: "apply" | "restore"; requestId: string; eyeRevision: number; readback: EyeServiceReadback;
}>;
export type EyeServiceFrame = EyeServiceAddress & Readonly<{
  source: "native-scene-capture"; sequence: number; viewRevision: number; eyeRevision: number;
  settings: EyeCoordinatorSettings; view: EyeCoordinatorView; captureTiming: EyeCoordinatorFrame["captureTiming"];
  width: number; height: number; pngBytes: Uint8Array;
}>;
export type EyeServiceReady = EyeServiceAddress & Readonly<{
  availability: "ready"; baselineId: string;
  schema: Readonly<{ id: string; parameters: readonly Readonly<{
    kind: "scalar"; parameter: EyeCoordinatorParameter; label: string;
    domain: Readonly<{ min: number; max: number; readbackTolerance: number }>;
  }>[]; presets: readonly Readonly<{ id: string; label: string; settings: EyeCoordinatorSettings }>[] }>;
  original: EyeCoordinatorSettings; current: EyeCoordinatorSettings;
  zoomBounds: Readonly<Record<EyeCoordinatorView["framing"], Readonly<{ min: number; max: number; initial: number; step: number }>>>;
  maxFrameAgeMs: number; maxReadbackAgeMs: number; diagnostics: readonly string[];
  evidence: Readonly<{ actualPlayerModel: true; isolatedPreviewInput: true; correspondingEyeMaterials: true; reversibleLiveSetter: true;
    supportedForms: readonly Readonly<{ form: "human"; schemaId: string; originalRestore: true }>[]; verifiedTransitions: readonly [] }>;
}>;
export type EyeServiceSession = EyeServiceReady | Readonly<{ availability: "unavailable"; reason: string; diagnostics: readonly string[] }>;
