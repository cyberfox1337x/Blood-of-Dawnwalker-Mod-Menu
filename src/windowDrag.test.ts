import { describe, expect, it } from "vitest";
import { calculateWindowDragPosition, normalizeWindowDragPoint } from "../electron/windowDrag";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_window_drag_tests");

describe("Dawnwalker window drag position", () => {
  const initialBounds = { x: 123, y: 45, width: 1672, height: 941 };
  const workArea = { x: 0, y: 0, width: 2560, height: 1400 };

  it("moves the window by the exact screen-cursor delta", () => {
    expect(calculateWindowDragPosition(initialBounds, { x: 700, y: 80 }, { x: 860, y: 210 }, workArea)).toEqual({
      x: 283,
      y: 175,
    });
  });

  it("accepts only bounded finite numeric screen coordinates", () => {
    expect(normalizeWindowDragPoint(700.4, -80.6)).toEqual({ x: 700, y: -81 });
    expect(normalizeWindowDragPoint("700", 80)).toBeNull();
    expect(normalizeWindowDragPoint(Number.NaN, 80)).toBeNull();
    expect(normalizeWindowDragPoint(700, Number.POSITIVE_INFINITY)).toBeNull();
    expect(normalizeWindowDragPoint(1_000_001, 80)).toBeNull();
  });

  it("keeps a recoverable title area on screen", () => {
    expect(calculateWindowDragPosition(initialBounds, { x: 700, y: 80 }, { x: -5000, y: -5000 }, workArea)).toEqual({
      x: -1512,
      y: 0,
    });
    expect(calculateWindowDragPosition(initialBounds, { x: 700, y: 80 }, { x: 5000, y: 5000 }, workArea)).toEqual({
      x: 2400,
      y: 1352,
    });
  });
});
