import { useCallback, useEffect, useRef, type PointerEvent as ReactPointerEvent } from "react";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_window_drag_handle");

export function WindowDragHandle() {
  const activePointerId = useRef<number | null>(null);

  const finishDrag = useCallback(() => {
    if (activePointerId.current === null) return;
    activePointerId.current = null;
    window.dawnwalkerDesktop?.endWindowDrag();
  }, []);

  useEffect(() => {
    window.addEventListener("blur", finishDrag);
    return () => {
      window.removeEventListener("blur", finishDrag);
      finishDrag();
    };
  }, [finishDrag]);

  const beginDrag = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.button !== 0 || activePointerId.current !== null) return;
    event.preventDefault();
    activePointerId.current = event.pointerId;
    event.currentTarget.setPointerCapture?.(event.pointerId);
    window.dawnwalkerDesktop?.beginWindowDrag(event.screenX, event.screenY);
  };

  const updateDrag = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.pointerId !== activePointerId.current) return;
    if ((event.buttons & 1) === 0) {
      finishDrag();
      return;
    }
    window.dawnwalkerDesktop?.updateWindowDrag(event.screenX, event.screenY);
  };

  const endDrag = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.pointerId !== activePointerId.current) return;
    if (event.type === "pointerup") {
      window.dawnwalkerDesktop?.updateWindowDrag(event.screenX, event.screenY);
    }
    finishDrag();
    if (event.currentTarget.hasPointerCapture?.(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  return (
    <div
      className="window-drag-handle no-drag"
      aria-hidden="true"
      onPointerDown={beginDrag}
      onPointerMove={updateDrag}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onLostPointerCapture={finishDrag}
    />
  );
}
