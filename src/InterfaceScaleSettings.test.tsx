import { act, fireEvent, render, screen, waitFor, cleanup } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { InterfaceScaleSettings } from "./InterfaceScaleSettings";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("interface_scale_settings_tests");
afterEach(() => { cleanup(); delete window.dawnwalkerDesktop; });

function installApi(initial = 100) {
  let publish: (scale: number) => void = () => undefined;
  const unsubscribe = vi.fn();
  const api = {
    get: vi.fn(async () => initial),
    set: vi.fn(async (scale: number) => scale),
    onChanged: vi.fn((listener: (scale: number) => void) => { publish = listener; return unsubscribe; }),
    onError: vi.fn(() => unsubscribe),
  };
  window.dawnwalkerDesktop = { interfaceScale: api } as unknown as NonNullable<Window["dawnwalkerDesktop"]>;
  return { api, publish: (scale: number) => publish(scale), unsubscribe };
}

it("loads saved scale, changes it, resets it, and tracks keyboard events", async () => {
  const { api, publish, unsubscribe } = installApi(150);
  const view = render(<InterfaceScaleSettings />);
  await screen.findByText("150%");
  fireEvent.click(screen.getByLabelText("Increase menu size"));
  await screen.findByText("175%");
  expect(api.set).toHaveBeenCalledWith(175);
  fireEvent.click(screen.getByRole("button", { name: /Reset to 100/ }));
  await screen.findByText("100%");
  act(() => publish(200));
  expect(screen.getByLabelText("Increase menu size")).toBeDisabled();
  act(() => publish(75));
  expect(screen.getByLabelText("Decrease menu size")).toBeDisabled();
  view.unmount();
  expect(unsubscribe).toHaveBeenCalledTimes(2);
});

it("reports failed saves and keeps the actual size", async () => {
  const { api } = installApi();
  api.set.mockRejectedValueOnce(new Error("disk full"));
  render(<InterfaceScaleSettings />);
  await waitFor(() => expect(screen.getByLabelText("Increase menu size")).toBeEnabled());
  fireEvent.click(screen.getByLabelText("Increase menu size"));
  expect(await screen.findByRole("alert")).toHaveTextContent("Could not save");
  expect(screen.getByLabelText("Current menu size")).toHaveTextContent("100%");
  expect(screen.getByLabelText("Increase menu size")).toBeEnabled();
});
