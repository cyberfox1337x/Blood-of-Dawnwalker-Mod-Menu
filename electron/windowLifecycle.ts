const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("main_window_lifecycle");

type FocusableWindow = {
  isDestroyed(): boolean;
  isMinimized(): boolean;
  restore(): void;
  show(): void;
  focus(): void;
  once(event: "closed", listener: () => void): unknown;
};

export function showAndFocus(target: FocusableWindow | null): void {
  if (!target || target.isDestroyed()) return;
  if (target.isMinimized()) target.restore();
  // Window events can synchronously close the window during restore/show.
  if (target.isDestroyed()) return;
  target.show();
  if (target.isDestroyed()) return;
  target.focus();
}

export function createWindowLifecycle<Window extends FocusableWindow>() {
  let current: Window | null = null;
  let quitting = false;
  function getWindow(): Window | null {
    return quitting || !current || current.isDestroyed() ? null : current;
  }
  function track(window: Window): void {
    if (quitting) throw new Error("Cannot create a main window during shutdown.");
    current = window;
    window.once("closed", () => { if (current === window) current = null; });
  }
  return {
    getWindow,
    track,
    beginQuit: () => { quitting = true; },
    isQuitting: () => quitting,
    focusExisting: () => showAndFocus(getWindow()),
  };
}
