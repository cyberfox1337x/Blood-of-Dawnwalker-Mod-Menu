import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { StoryDaySettings } from "./StoryDaySettings";
import type { StoryDayInspection } from "../electron/storyDaySettings";
const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("story_day_panel_tests");
afterEach(() => { cleanup(); delete window.dawnwalkerDesktop; });
const baseline: StoryDayInspection = { fullPath: "Game.ini", sha256: "a".repeat(64), exists: false, configuredDays: null,
  enabled: false, owned: false, conflict: false, gameRunning: false, buildVerified: true, restartRequired: true, verification: "Not verified in game" };
function install(snapshot = baseline) {
  const api = { inspect: vi.fn(async () => snapshot), apply: vi.fn(async (): Promise<StoryDayInspection> => ({ ...snapshot, enabled: true, owned: true, configuredDays: 91 })), restore: vi.fn(async () => baseline) };
  window.dawnwalkerDesktop = { storyDaySettings: api } as unknown as NonNullable<typeof window.dawnwalkerDesktop>;
  return api;
}
describe("persistent story configuration UI", () => {
  it("blocks changes while game runs and does not invoke apply", async () => {
    const api = install({ ...baseline, gameRunning: true }); render(<StoryDaySettings />);
    await screen.findByText(/Close Dawnwalker, then refresh/);
    expect(screen.getByRole("switch")).toBeDisabled(); expect(api.apply).not.toHaveBeenCalled();
  });
  it("keeps OFF while pending and confirms only returned configuration state", async () => {
    const api = install(); let finish!: (value: StoryDayInspection) => void;
    api.apply.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
    render(<StoryDaySettings />); await waitFor(() => expect(screen.getByRole("switch")).toBeEnabled());
    expect(screen.queryByText(/^(ON|OFF)$/)).toBeNull();
    fireEvent.click(screen.getByRole("switch"));
    expect(screen.getByRole("switch")).toHaveAttribute("aria-checked", "false");
    expect(screen.getByRole("switch")).toHaveAttribute("aria-busy", "true");
    await act(async () => finish({ ...baseline, enabled: true, owned: true, configuredDays: 91 }));
    expect(screen.getByRole("switch")).toHaveAttribute("aria-checked", "true");
    expect(screen.getByText(/Configuration status is separate/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("switch"));
    await waitFor(() => expect(api.restore).toHaveBeenCalledWith(baseline.sha256));
    await waitFor(() => expect(screen.getByRole("switch")).toHaveAttribute("aria-checked", "false"));
  });
  it("shows actual rejection adjacent and never claims configured", async () => {
    const api = install(); api.apply.mockRejectedValue(new Error("Game.ini changed. Refresh before applying."));
    render(<StoryDaySettings />); await waitFor(() => expect(screen.getByRole("switch")).toBeEnabled());
    fireEvent.click(screen.getByRole("switch"));
    expect(await screen.findByRole("alert")).toHaveTextContent("Game.ini changed");
    expect(screen.getByRole("switch")).toHaveAttribute("aria-checked", "false");
  });
});
