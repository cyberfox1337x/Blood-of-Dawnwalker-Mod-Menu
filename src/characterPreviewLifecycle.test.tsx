import { useEffect } from "react";
import { act, cleanup, renderHook } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { CHARACTER_PREVIEW_RELEASE_DELAY_MS, useCharacterPreviewActivation } from "./characterPreviewLifecycle";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("character_preview_lifecycle_tests");
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
  Object.defineProperty(document, "hidden", { configurable: true, value: false });
});

it("keeps one allocation through rapid tab switches and releases it after the grace period", () => {
  vi.useFakeTimers();
  vi.spyOn(document, "hasFocus").mockReturnValue(true);
  const allocate = vi.fn(), dispose = vi.fn();
  const { rerender, unmount } = renderHook(({ active }) => {
    const activated = useCharacterPreviewActivation(active);
    useEffect(() => { if (!activated) return; allocate(); return dispose; }, [activated]);
  }, { initialProps: { active: false } });
  expect(allocate).not.toHaveBeenCalled();
  rerender({ active: true });
  for (let index = 0; index < 5; index += 1) { rerender({ active: false }); rerender({ active: true }); }
  expect(allocate).toHaveBeenCalledOnce();
  expect(dispose).not.toHaveBeenCalled();
  rerender({ active: false });
  act(() => vi.advanceTimersByTime(CHARACTER_PREVIEW_RELEASE_DELAY_MS - 1));
  expect(dispose).not.toHaveBeenCalled();
  act(() => vi.advanceTimersByTime(1));
  expect(dispose).toHaveBeenCalledOnce();
  unmount();
  expect(dispose).toHaveBeenCalledOnce();
});

it("releases immediately when F10 minimizes the window and allocates again when focused", () => {
  vi.useFakeTimers();
  vi.spyOn(document, "hasFocus").mockReturnValue(true);
  const allocate = vi.fn(), dispose = vi.fn();
  const { unmount } = renderHook(() => {
    const activated = useCharacterPreviewActivation(true);
    useEffect(() => { if (!activated) return; allocate(); return dispose; }, [activated]);
  });
  expect(allocate).toHaveBeenCalledOnce();

  act(() => window.dispatchEvent(new Event("blur")));
  expect(dispose).toHaveBeenCalledOnce();

  act(() => window.dispatchEvent(new Event("focus")));
  expect(allocate).toHaveBeenCalledTimes(2);
  unmount();
  expect(dispose).toHaveBeenCalledTimes(2);
});
