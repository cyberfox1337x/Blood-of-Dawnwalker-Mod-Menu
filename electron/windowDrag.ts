const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("electron_window_drag");

export type DragPoint = Readonly<{
  x: number;
  y: number;
}>;

export type DragRectangle = DragPoint & Readonly<{
  width: number;
  height: number;
}>;

const MINIMUM_VISIBLE_WIDTH = 160;
const MINIMUM_VISIBLE_TITLE_HEIGHT = 48;
const MAXIMUM_ABSOLUTE_SCREEN_COORDINATE = 1_000_000;

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

export function normalizeWindowDragPoint(screenX: unknown, screenY: unknown): DragPoint | null {
  if (typeof screenX !== "number" || typeof screenY !== "number") return null;
  if (!Number.isFinite(screenX) || !Number.isFinite(screenY)) return null;
  if (Math.abs(screenX) > MAXIMUM_ABSOLUTE_SCREEN_COORDINATE || Math.abs(screenY) > MAXIMUM_ABSOLUTE_SCREEN_COORDINATE) {
    return null;
  }
  return { x: Math.round(screenX), y: Math.round(screenY) };
}

export function calculateWindowDragPosition(
  initialBounds: DragRectangle,
  initialCursor: DragPoint,
  currentCursor: DragPoint,
  workArea: DragRectangle,
): DragPoint {
  const requestedX = initialBounds.x + currentCursor.x - initialCursor.x;
  const requestedY = initialBounds.y + currentCursor.y - initialCursor.y;
  const minimumX = workArea.x - initialBounds.width + MINIMUM_VISIBLE_WIDTH;
  const maximumX = workArea.x + workArea.width - MINIMUM_VISIBLE_WIDTH;
  const minimumY = workArea.y;
  const maximumY = workArea.y + workArea.height - MINIMUM_VISIBLE_TITLE_HEIGHT;

  return {
    x: Math.round(clamp(requestedX, minimumX, maximumX)),
    y: Math.round(clamp(requestedY, minimumY, maximumY)),
  };
}
