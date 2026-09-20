import { describe, expect, it } from "vitest";
import { formatDesktopError } from "./desktopError";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_desktop_error_tests");

describe("desktop IPC error presentation", () => {
  it("removes the observed Electron wrapper while retaining every actionable sentence", () => {
    const body = "Close Dawnwalker before changing fog configuration. Process status must be verified.";
    expect(formatDesktopError(new Error(`Error invoking remote method 'dawnwalker:fog': Error: ${body}`), "Operation failed.")).toBe(body);
  });

  it("preserves apostrophes, quoted paths, line breaks, and recovery instructions in the error body", () => {
    const body = "Can't restore the player's save.\nKeep Dawnwalker closed. Recovery backup: C:\\User's saves\\ManualSave2.sav";
    expect(formatDesktopError(`Error: Error invoking remote method 'dawnwalker:save-editor': Error: ${body}`, "Operation failed.")).toBe(body);
  });

  it("preserves specific underlying error types and supports a wrapper without an Error label", () => {
    expect(formatDesktopError(new Error("Error invoking remote method 'dawnwalker:fog': TypeError: Invalid configuration value."), "Operation failed.")).toBe("TypeError: Invalid configuration value.");
    expect(formatDesktopError("Error invoking remote method 'dawnwalker:reference': Browser unavailable.", "Operation failed.")).toBe("Browser unavailable.");
  });

  it("leaves unrecognized errors and wrapper-like text inside the message unchanged", () => {
    for (const message of [
      "Error: Save checksum mismatch. Restore the original backup.",
      "The log contains Error invoking remote method 'dawnwalker:fog': Error: details.",
      "Error invoking remote method 'unrecognized'quote': Error: Keep this entire diagnostic.",
      "Error invoking remote method without a quoted channel: Keep this entire diagnostic.",
    ]) expect(formatDesktopError(new Error(message), "Operation failed.")).toBe(message);
  });

  it("uses the caller's actionable fallback for non-message or empty errors", () => {
    for (const cause of [undefined, null, 42, {}, new Error(""), "", "Error invoking remote method 'dawnwalker:fog': Error: "]) {
      expect(formatDesktopError(cause, "Could not inspect fog configuration. Refresh to retry.")).toBe("Could not inspect fog configuration. Refresh to retry.");
    }
  });
});
