import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve, sep } from "node:path";
import { describe, expect, it } from "vitest";
import { assertEyeResponseCorrespondence, encodeEyeNativeRequest, HUMAN_IRIS_WIRE_KEYS, parseEyeNativeResponse, type EyeNativeWireRequest, type HumanIrisWireSettings } from "./eyeNativeProtocol.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_native_wire_cross_language_parity");

const lua = join(process.env.LOCALAPPDATA || "", "Programs", "Lua", "bin", "lua.exe");
function removeFixture(root: string): void {
  const target = resolve(root);
  if (dirname(target) !== resolve(tmpdir()) || !target.startsWith(resolve(tmpdir()) + sep + "dawnwalker-eye-wire-parity-")) {
    throw new Error("Unexpected parity fixture cleanup path");
  }
  rmSync(target, { recursive: true });
}
describe.skipIf(!existsSync(lua))("actual Lua and Electron eye codec correspondence", () => {
  it("roundtrips every supported request without native game dependencies", () => {
    const root = mkdtempSync(join(tmpdir(), "dawnwalker-eye-wire-parity-"));
    try {
      const module = resolve("analysis/dawnwalker-uue4ss/probes/DawnwalkerEyeSessionDispatch.lua");
      const runner = join(root, "codec.lua");
      writeFileSync(runner, [
        'local cyberfox1337x = function(_) end',
        'cyberfox1337x("eye_wire_parity_fixture")',
        'local Dispatch = dofile(arg[1])',
        'local input = assert(io.open(arg[2], "rb"))',
        'local request = Dispatch.parse_request(input:read("a")); input:close()',
        'local output = assert(io.open(arg[3], "wb"))',
        'assert(output:write(Dispatch.format_response(request))); assert(output:close())',
      ].join("\n"));
      const base = { boot_id: "1788670834-420980", owner_id: "a".repeat(32), request_id: "b".repeat(32), command_sequence: 1 };
      const owned = { ...base, lease_id: "c".repeat(32), preview_nonce: "d".repeat(32), identity_key: "native%25:Coen", baseline_id: "original:Head" };
      const settings = Object.fromEntries(HUMAN_IRIS_WIRE_KEYS.map((key, index) => [key, index / 10 + 0.0000001])) as HumanIrisWireSettings;
      const view = { view_revision: 2, eye_revision: 3, yaw_degrees: -69, framing: "eyes-close-up" as const, zoom: 1.25, settings };
      const requests: EyeNativeWireRequest[] = [
        { ...base, operation: "inspect" }, { ...owned, ...view, operation: "open" },
        { ...owned, ...view, operation: "enqueue" }, { ...owned, operation: "step" },
        { ...owned, operation: "renew" }, { ...owned, operation: "cancel" },
        { ...owned, operation: "apply", eye_revision: 3, settings },
        { ...owned, operation: "restore", eye_revision: 4 },
        { ...owned, operation: "ack", frame_sequence: 1, file_name: `eye-live-${owned.preview_nonce}-0001.png` },
        { ...owned, operation: "close" },
      ];
      for (const request of requests) {
        const path = join(root, "request.txt");
        writeFileSync(path, encodeEyeNativeRequest(request));
        const outputPath = join(root, "response.txt");
        execFileSync(lua, [runner, module, path, outputPath], { windowsHide: true, timeout: 5000, maxBuffer: 256 * 1024 });
        const decoded = parseEyeNativeResponse(readFileSync(outputPath));
        assertEyeResponseCorrespondence(request, decoded);
        if ("settings" in request) for (const key of HUMAN_IRIS_WIRE_KEYS) expect(Number(decoded[key])).toBe(request.settings[key]);
        expect(decoded.operation).toBe(request.operation);
        if ("identity_key" in request) expect(decoded.identity_key).toBe(request.identity_key);
        expect(readFileSync(path, "utf8")).toBe(encodeEyeNativeRequest(request));
      }
    } finally {
      removeFixture(root);
    }
  });
});
