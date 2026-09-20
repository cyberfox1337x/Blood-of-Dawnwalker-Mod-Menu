import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { EyeAppearance } from "./EyeAppearance";
import type { EyeAppearanceBridge, EyeOperationReceipt, EyePreviewFrame, ReadyEyeSession } from "./eyeAppearanceContract";
import { mockEyeFrame, mockEyeReadback, mockEyeReceipt, mockEyeSession, mockEyeTiming } from "./eyeAppearance.testFixtures";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_appearance_component_tests");

function harness(session: ReadyEyeSession = mockEyeSession()) {
  let listener: ((frame: EyePreviewFrame) => void) | undefined;
  let sequence = 0;
  const unsubscribe = vi.fn();
  const drawImage = vi.fn();
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation(() => ({ drawImage }) as unknown as CanvasRenderingContext2D);
  vi.stubGlobal("createImageBitmap", vi.fn(async () => ({ width: 300, height: 300, close: vi.fn() })));
  const bridge = {
    subscribeFrames: vi.fn<EyeAppearanceBridge["subscribeFrames"]>((_address, onFrame) => { listener = onFrame; return unsubscribe; }),
    updatePreview: vi.fn<EyeAppearanceBridge["updatePreview"]>(async () => undefined),
    apply: vi.fn<EyeAppearanceBridge["apply"]>(async request => mockEyeReceipt(request)),
    restore: vi.fn<EyeAppearanceBridge["restore"]>(async request => mockEyeReceipt(request, "restore")),
    inspect: vi.fn<EyeAppearanceBridge["inspect"]>(async () => mockEyeReadback(session)),
    cancelQueued: vi.fn<EyeAppearanceBridge["cancelQueued"]>(),
  };
  const showLatestFrame = async (overrides: Partial<EyePreviewFrame> = {}) => {
    await waitFor(() => expect(bridge.updatePreview).toHaveBeenCalled());
    const calls = bridge.updatePreview.mock.calls;
    const request = calls[calls.length - 1][0];
    await act(async () => { listener?.({ ...mockEyeFrame(request, ++sequence), ...overrides }); await Promise.resolve(); });
  };
  return { session, bridge, unsubscribe, drawImage, showLatestFrame };
}

afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe("isolated Eye Appearance component with mocked native adapters", () => {
  it("omits the unavailable panel and never creates native controls when a capability is missing", () => {
    const { session, bridge } = harness();
    render(<EyeAppearance session={{ ...session, evidence: { ...session.evidence, actualPlayerModel: false as never } }} bridge={bridge} />);
    expect(screen.queryByText("Eye appearance unavailable")).not.toBeInTheDocument();
    expect(document.querySelector(".eye-appearance")).toBeNull();
    expect(screen.queryByRole("group", { name: "3D character preview" })).not.toBeInTheDocument();
    expect(bridge.subscribeFrames).not.toHaveBeenCalled();
    expect(bridge.apply).not.toHaveBeenCalled();
  });

  it("limits preview rotation and zoom, provides close-up/reset, and keeps those controls out of gameplay requests", async () => {
    const { session, bridge } = harness();
    render(<EyeAppearance session={session} bridge={bridge} />);
    for (let count = 0; count < 30; count += 1) fireEvent.click(screen.getByRole("button", { name: "Rotate preview right" }));
    expect(screen.getByLabelText("Preview rotation")).toHaveTextContent("69°");
    expect(screen.getByRole("button", { name: "Rotate preview right" })).toBeDisabled();
    for (let count = 0; count < 50; count += 1) fireEvent.click(screen.getByRole("button", { name: "Rotate preview left" }));
    expect(screen.getByLabelText("Preview rotation")).toHaveTextContent("-69°");
    fireEvent.click(screen.getByRole("button", { name: "Eyes Close-Up" }));
    expect(screen.getByRole("slider", { name: "Preview zoom" })).toHaveAttribute("min", "3");
    fireEvent.change(screen.getByRole("slider", { name: "Preview zoom" }), { target: { value: "4" } });
    expect(screen.getByRole("slider", { name: "Preview zoom" })).toHaveValue("4");
    fireEvent.click(screen.getByRole("button", { name: "Reset View" }));
    expect(screen.getByLabelText("Preview rotation")).toHaveTextContent("0°");
    expect(screen.getByRole("slider", { name: "Preview zoom" })).toHaveValue("1.25");
    await waitFor(() => expect(bridge.updatePreview.mock.calls.at(-1)?.[0].view).toEqual({ yawDegrees: 0, framing: "head-and-shoulders", zoom: 1.25 }));
    expect(bridge.apply).not.toHaveBeenCalled();
    expect(bridge.restore).not.toHaveBeenCalled();
  });

  it("updates preview-only presets and supported picker colors without sending game changes", async () => {
    const { session, bridge } = harness();
    const user = userEvent.setup();
    render(<EyeAppearance session={session} bridge={bridge} />);
    await user.click(screen.getByRole("button", { name: "Test red" }));
    expect(screen.getByRole("button", { name: "Test red" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.change(screen.getByLabelText("Iris color"), { target: { value: "#808080" } });
    await waitFor(() => expect(bridge.updatePreview.mock.calls.at(-1)?.[0].eyeRevision).toBe(2));
    expect(screen.getByText("#808080")).toBeVisible();
    expect(screen.getByText("Preview Only")).toBeVisible();
    expect(bridge.apply).not.toHaveBeenCalled();
    expect(bridge.restore).not.toHaveBeenCalled();
  });

  it("accumulates rapid scaled pointer and wheel input and releases only its captured pointer", async () => {
    const { session, bridge } = harness();
    class TestPointerEvent extends MouseEvent {
      pointerId: number;
      isPrimary: boolean;
      constructor(type: string, init: PointerEventInit = {}) { super(type, init); this.pointerId = init.pointerId ?? 1; this.isPrimary = true; }
    }
    vi.stubGlobal("PointerEvent", TestPointerEvent);
    render(<EyeAppearance session={session} bridge={bridge} />);
    const viewer = screen.getByRole("group", { name: "3D character preview" });
    const capture = vi.fn();
    const release = vi.fn();
    Object.defineProperties(viewer, { setPointerCapture: { value: capture }, hasPointerCapture: { value: () => true }, releasePointerCapture: { value: release } });
    vi.spyOn(viewer, "getBoundingClientRect").mockReturnValue({ width: 300 } as DOMRect);
    fireEvent.pointerDown(viewer, { button: 0, clientX: 0, pointerId: 4 });
    act(() => {
      fireEvent.pointerMove(viewer, { clientX: 10, pointerId: 4 });
      fireEvent.pointerMove(viewer, { clientX: 20, pointerId: 4 });
      fireEvent.wheel(viewer, { deltaY: -1 });
      fireEvent.wheel(viewer, { deltaY: -1 });
    });
    expect(screen.getByLabelText("Preview rotation")).toHaveTextContent("9°");
    expect(Number((screen.getByRole("slider", { name: "Preview zoom" }) as HTMLInputElement).value)).toBeCloseTo(1.45);
    fireEvent.pointerUp(viewer, { pointerId: 4 });
    expect(capture).toHaveBeenCalledWith(4);
    expect(release).toHaveBeenCalledWith(4);
    expect(bridge.apply).not.toHaveBeenCalled();
  });

  it("requires corresponding current decoded frames and runtime receipts before Applied In Game", async () => {
    const { session, bridge, showLatestFrame, drawImage } = harness();
    const user = userEvent.setup();
    render(<EyeAppearance session={session} bridge={bridge} />);
    await user.click(screen.getByRole("switch", { name: "Live eye customization" }));
    await waitFor(() => expect(bridge.apply).toHaveBeenCalledOnce());
    expect(screen.getByText("Preview Only")).toBeVisible();
    await showLatestFrame({ renderTargetGeneration: "old-target" });
    expect(drawImage).not.toHaveBeenCalled();
    expect(screen.getByText("Preview Only")).toBeVisible();
    await showLatestFrame({ view: undefined as never });
    await showLatestFrame({ view: { yawDegrees: NaN, framing: "head-and-shoulders", zoom: 1.25 } });
    await showLatestFrame({ captureTiming: undefined as never });
    await showLatestFrame({ captureTiming: { ...mockEyeTiming(), kind: "native-call-interval", nativeClockId: "test-native-clock",
      nativeStartedMs: 10, nativeCompletedMs: 12, renderCompletedAtMs: null, hostRequestSentAtMs: Date.now() - 2000 } });
    expect(drawImage).not.toHaveBeenCalled();
    await showLatestFrame();
    await waitFor(() => expect(screen.getByText("Applied In Game")).toBeVisible());
    expect(drawImage).toHaveBeenCalledOnce();
    await user.click(screen.getByRole("button", { name: "Test red" }));
    expect(screen.getByText("Preview Only")).toBeVisible();
    await showLatestFrame();
    await waitFor(() => expect(screen.getByText("Applied In Game")).toBeVisible());
  });

  it("does not label a newer preview applied when an older request completes", async () => {
    const { session, bridge, showLatestFrame } = harness();
    let finishOld: ((receipt: EyeOperationReceipt) => void) | undefined;
    bridge.apply.mockImplementationOnce(() => new Promise(resolve => { finishOld = resolve; }))
      .mockResolvedValue({ status: "rejected", requestId: "latest-rejected", reason: "Current eye binding changed." });
    const user = userEvent.setup();
    render(<EyeAppearance session={session} bridge={bridge} />);
    await user.click(screen.getByRole("switch", { name: "Live eye customization" }));
    await user.click(screen.getByRole("button", { name: "Test blue" }));
    await showLatestFrame();
    await act(async () => { finishOld?.(mockEyeReceipt(bridge.apply.mock.calls[0][0])); await Promise.resolve(); });
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Current eye binding changed."));
    expect(screen.getByText("Preview Only")).toBeVisible();
    expect(screen.queryByText("Applied In Game")).not.toBeInTheDocument();
  });

  it("blocks duplicate activation and restores OFF after a rejected live enable", async () => {
    const { session, bridge } = harness();
    let rejectApply: ((error: Error) => void) | undefined;
    bridge.apply.mockImplementationOnce(() => new Promise((_resolve, reject) => { rejectApply = reject; }));
    render(<EyeAppearance session={session} bridge={bridge} />);
    const toggle = screen.getByRole("switch", { name: "Live eye customization" });
    fireEvent.click(toggle);
    await waitFor(() => expect(bridge.apply).toHaveBeenCalledOnce());
    expect(toggle).toBeDisabled();
    expect(toggle).toHaveAttribute("aria-busy", "true");
    fireEvent.click(toggle);
    expect(bridge.apply).toHaveBeenCalledOnce();
    await act(async () => { rejectApply?.(new Error("Eye binding changed; retry after reconnecting.")); });
    await waitFor(() => expect(toggle).not.toBeChecked());
    expect(toggle).toBeEnabled();
    expect(screen.getByRole("alert")).toHaveTextContent("Eye binding changed");
  });

  it("restores the captured baseline through the runtime action even with live updates off", async () => {
    const { session, bridge, showLatestFrame } = harness();
    const user = userEvent.setup();
    render(<EyeAppearance session={session} bridge={bridge} />);
    await user.click(screen.getByRole("button", { name: "Test blue" }));
    await user.click(screen.getByRole("button", { name: "Restore Original Eyes" }));
    await waitFor(() => expect(bridge.restore).toHaveBeenCalledOnce());
    expect(bridge.restore.mock.calls[0][0].desired).toEqual(session.original);
    expect(bridge.restore.mock.calls[0][0].baselineId).toBe(session.baselineId);
    await showLatestFrame();
    await waitFor(() => expect(screen.getByText("Applied In Game")).toBeVisible());
    expect(bridge.apply).not.toHaveBeenCalled();
  });

  it("pauses its stream and cancels queued preview work when hidden without restoring or transforming the player", async () => {
    const { session, bridge, unsubscribe } = harness();
    const view = render(<EyeAppearance session={session} bridge={bridge} />);
    await waitFor(() => expect(bridge.subscribeFrames).toHaveBeenCalledOnce());
    view.rerender(<EyeAppearance session={session} bridge={bridge} active={false} />);
    expect(unsubscribe).toHaveBeenCalledOnce();
    expect(bridge.cancelQueued).toHaveBeenCalledOnce();
    expect(screen.getByRole("button", { name: "Rotate preview left" })).toBeDisabled();
    expect(bridge.restore).not.toHaveBeenCalled();
    expect(bridge.apply).not.toHaveBeenCalled();
    expect(document.querySelector(".eye-diagnostics")).toBeNull();
  });
});
