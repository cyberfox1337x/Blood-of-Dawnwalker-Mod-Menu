import { describe, expect, it } from "vitest";
import { assertEyeResponseCorrespondence, encodeEyeNativeRequest, HUMAN_IRIS_WIRE_KEYS, parseEyeNativeResponse, type EyeNativeWireRequest, type HumanIrisWireSettings } from "./eyeNativeProtocol.js";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_native_wire_protocol_tests");

const token = "a".repeat(32);
const base = { boot_id: "1788669230-158239", owner_id: token, request_id: "b".repeat(32), command_sequence: 1 };
const owned = { ...base, lease_id: "c".repeat(32), preview_nonce: "d".repeat(32), identity_key: "native:current", baseline_id: "native:original" };
const settings = Object.fromEntries(HUMAN_IRIS_WIRE_KEYS.map((key, index) => [key, index / 10])) as HumanIrisWireSettings;
const view = { view_revision: 3, eye_revision: 4, yaw_degrees: -69, framing: "eyes-close-up" as const, zoom: 1, settings };
const response = "wire_version=1\nboot_id=1788669230-158239\nowner_id=" + token
  + "\nrequest_id=" + "b".repeat(32) + "\ncommand_sequence=1\n";
const bytes = (text: string) => new TextEncoder().encode(text);

describe("dedicated eye wire boundary", () => {
  it("uses exactly the same canonical scalar payload for preview and live requests", () => {
    const preview = encodeEyeNativeRequest({ ...owned, ...view, operation: "enqueue" });
    const live = encodeEyeNativeRequest({ ...owned, eye_revision: 4, settings, operation: "apply" });
    for (const key of HUMAN_IRIS_WIRE_KEYS) {
      expect(preview.split("\n").find(line => line.startsWith(key + "=")))
        .toBe(live.split("\n").find(line => line.startsWith(key + "=")));
    }
    expect(preview).toContain("yaw_degrees=-69\n");
    expect(preview).not.toContain("file_name=");
  });
  it("rejects extra commands, arbitrary native fields, invalid views and nonfinite values", () => {
    const invalid = [
      { ...base, operation: "execute-lua" },
      { ...base, operation: "inspect", native_function: "any" },
      { ...owned, ...view, operation: "open", yaw_degrees: 70 },
      { ...owned, ...view, operation: "open", zoom: Number.NaN },
      { ...owned, ...view, operation: "open", settings: { ...settings, left_primary_u: Infinity } },
      { ...owned, ...view, operation: "open", settings: { ...settings, arbitrary_parameter: 1 } },
      { ...owned, ...view, operation: "open", identity_key: "x".repeat(2049) },
    ];
    for (const request of invalid) expect(() => encodeEyeNativeRequest(request as EyeNativeWireRequest)).toThrow();
  });
  it("acknowledges only an exact owned frame and bounded sequence", () => {
    const file_name = `eye-live-${owned.preview_nonce}-0001.png`;
    expect(encodeEyeNativeRequest({ ...owned, operation: "ack", frame_sequence: 1, file_name })).toContain(`file_name=${file_name}\n`);
    for (const name of ["../" + file_name, file_name.replace("0001", "0002"), file_name.replace(owned.preview_nonce, token)]) {
      expect(() => encodeEyeNativeRequest({ ...owned, operation: "ack", frame_sequence: 1, file_name: name })).toThrow();
    }
    expect(() => encodeEyeNativeRequest({ ...owned, operation: "ack", frame_sequence: 1201, file_name })).toThrow();
  });
  it("decodes escaped text once into a prototype-free response without treating it as verified", () => {
    const parsed = parseEyeNativeResponse(bytes(response + "reason=one%0Atwo%2525\n"));
    expect(parsed.reason).toBe("one\ntwo%25");
    expect(Object.getPrototypeOf(parsed)).toBeNull();
    expect(Object.isFrozen(parsed)).toBe(true);
    expect(parsed.availability).toBeUndefined();
  });
  it("rejects duplicate, malformed, incomplete, oversized and prototype-bearing responses", () => {
    for (const text of [
      response + "command_sequence=2\n", response + "__proto__.polluted=yes\n",
      response + "native.constructor=yes\n", response + "reason=bad%FF\n",
      response.slice(0, -1), response.replaceAll("\n", "\r\n"),
      response + "reason=" + "x".repeat(16385) + "\n",
      response.replace("wire_version=1", "wire_version=2"),
      response.replace("command_sequence=1", "command_sequence=01"),
    ]) expect(() => parseEyeNativeResponse(bytes(text))).toThrow();
    expect(() => parseEyeNativeResponse(new Uint8Array(256 * 1024 + 1))).toThrow();
    expect(() => parseEyeNativeResponse(new Uint8Array([0xff, 0x0a]))).toThrow();
  });
  it("rejects a previous lease, operation, revision or request despite a nominal success field", () => {
    const request: EyeNativeWireRequest = { ...owned, operation: "apply", eye_revision: 4, settings };
    const matching = { ...Object.fromEntries(Object.entries({ ...owned, operation: "apply", eye_revision: 4 })
      .map(([key, value]) => [key, String(value)])), wire_version: "1", "result.status": "verified" };
    expect(() => assertEyeResponseCorrespondence(request, matching)).not.toThrow();
    for (const key of ["lease_id", "request_id", "operation", "eye_revision", "identity_key", "baseline_id", "command_sequence"]) {
      expect(() => assertEyeResponseCorrespondence(request, { ...matching, [key]: "different" })).toThrow();
    }
  });
});
