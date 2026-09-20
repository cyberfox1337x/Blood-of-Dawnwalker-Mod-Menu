// cyberfox1337x.function("desktop_type_contract") — declaration files cannot execute runtime signatures.
import type { RuntimeCommand, RuntimeInfo, RuntimeResult } from "./runtimeContract";
import type { createStoryDaySettings } from "../electron/storyDaySettings";
import type { FogChange, FogInspection } from "../electron/fogSettings";
import type { createSaveEditor } from "../electron/saveEditor";
import type { GameAssetStatus, PerkMetadata } from "../electron/gameAssets";
import type { ImportedMenuTransport } from "./importedMenuContract";

export {};

declare global {
  interface Window {
    dawnwalkerDesktop?: Readonly<{
      importedMenu?: ImportedMenuTransport;
      beginWindowDrag: (screenX: number, screenY: number) => void;
      updateWindowDrag: (screenX: number, screenY: number) => void;
      endWindowDrag: () => void;
      minimizeWindow: () => void;
      toggleMaximizeWindow?: () => void;
      isWindowMaximized?: () => Promise<boolean>;
      onWindowMaximizedChanged?: (listener: (maximized: boolean) => void) => () => void;
      closeWindow: () => void;
      interfaceScale?: Readonly<{
        get: () => Promise<number>;
        set: (scale: number) => Promise<number>;
        onChanged: (listener: (scale: number) => void) => () => void;
        onError: (listener: (message: string) => void) => () => void;
      }>;
      questReminder?: Readonly<{
        get: () => Promise<boolean>;
        set: (enabled: boolean) => Promise<boolean>;
        notify: (title: string, body: string) => Promise<boolean>;
        onReminder?: (listener: (event: Readonly<{ title: string; objective: string; desktopAccepted: boolean }>) => void) => () => void;
      }>;
      onGameplayHotkey: (listener: (action: "add-gold") => void) => () => void;
      getRuntimeInfo: () => Promise<RuntimeInfo>;
      dispatch: (command: RuntimeCommand) => Promise<RuntimeResult>;
      openFeatureReference?: (id: number) => Promise<void>;
      eyeAppearance?: Readonly<{
        open: () => Promise<unknown>;
        state: () => Promise<unknown>;
        updatePreview: (request: unknown) => Promise<unknown>;
        apply: (request: unknown, address: unknown) => Promise<unknown>;
        restore: (request: unknown, address: unknown) => Promise<unknown>;
        inspect: (identity: unknown, baselineId: string) => Promise<unknown>;
        cancelQueued: (address: unknown) => Promise<unknown>;
        close: () => Promise<unknown>;
        onSession: (listener: (session: unknown) => void) => () => void;
        onFrame: (listener: (frame: unknown) => void) => () => void;
      }>;
      saveEditor?: ReturnType<typeof createSaveEditor>;
      gameAssets?: Readonly<{ status(): Promise<GameAssetStatus>; perks(): Promise<readonly PerkMetadata[]> }>;
      storyDaySettings?: ReturnType<typeof createStoryDaySettings>;
      fogSettings?: Readonly<{
        inspect: () => Promise<FogInspection>;
        apply: (change: FogChange) => Promise<FogInspection>;
        restore: (sha256: string) => Promise<FogInspection>;
      }>;
    }>;
  }
}
