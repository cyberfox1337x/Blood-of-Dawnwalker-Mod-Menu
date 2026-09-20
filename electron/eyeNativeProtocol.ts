const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_eye_native_wire_protocol");

// Inactive transport boundary for the dedicated eye dispatcher. This module
// cannot open a channel, execute a native operation, or construct a ready UI.
const REQUEST_BYTES = 32 * 1024;
const RESPONSE_BYTES = 256 * 1024;
const TOKEN = /^[a-f0-9]{32}$/;
const BOOT = /^\d{1,16}-\d{1,16}$/;
const FIELD = /^[a-zA-Z_][a-zA-Z0-9_.-]{0,191}$/;

export const HUMAN_IRIS_WIRE_KEYS = [
  "left_primary_u", "left_primary_v", "left_secondary_u", "left_secondary_v",
  "right_primary_u", "right_primary_v", "right_secondary_u", "right_secondary_v",
] as const;
export type HumanIrisWireSettings = Readonly<Record<typeof HUMAN_IRIS_WIRE_KEYS[number], number>>;

type BaseRequest = Readonly<{
  boot_id: string;
  owner_id: string;
  request_id: string;
  command_sequence: number;
}>;
type OwnedRequest = BaseRequest & Readonly<{
  lease_id: string;
  preview_nonce: string;
  identity_key: string;
  baseline_id: string;
}>;
type ViewRequest = Readonly<{
  view_revision: number;
  eye_revision: number;
  yaw_degrees: number;
  framing: "head-and-shoulders" | "eyes-close-up";
  zoom: number;
  settings: HumanIrisWireSettings;
}>;

export type EyeNativeWireRequest =
  | (BaseRequest & Readonly<{ operation: "inspect" }>)
  | (OwnedRequest & ViewRequest & Readonly<{ operation: "open" | "enqueue" }>)
  | (OwnedRequest & Readonly<{ operation: "step" | "renew" | "cancel" | "close" }>)
  | (OwnedRequest & Readonly<{ operation: "apply"; eye_revision: number; settings: HumanIrisWireSettings }>)
  | (OwnedRequest & Readonly<{ operation: "restore"; eye_revision: number }>)
  | (OwnedRequest & Readonly<{ operation: "ack"; frame_sequence: number; file_name: string }>);

function check(condition: unknown, reason: string): asserts condition {
  if (!condition) throw new Error(reason);
}
function integer(value: number, min = 0, max = 2147483647): boolean {
  return Number.isSafeInteger(value) && value >= min && value <= max;
}
function hasControl(value: string): boolean {
  return Array.from(value).some(character => character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127);
}
function plainText(value: string, max: number): boolean {
  return typeof value === "string" && value.length > 0 && Buffer.byteLength(value, "utf8") <= max
    && !hasControl(value);
}
function encode(value: string | number): string {
  return String(value).replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");
}

export function encodeEyeNativeRequest(request: EyeNativeWireRequest): string {
  check(BOOT.test(request.boot_id) && TOKEN.test(request.owner_id) && TOKEN.test(request.request_id), "Invalid eye request identity");
  check(integer(request.command_sequence, 1), "Invalid eye command sequence");
  const fields: Record<string, string | number> = {
    wire_version: 1, operation: request.operation, boot_id: request.boot_id,
    owner_id: request.owner_id, request_id: request.request_id, command_sequence: request.command_sequence,
  };
  const allowed = new Set(["operation", "boot_id", "owner_id", "request_id", "command_sequence"]);
  function add(key: string, value: string | number) { fields[key] = value; allowed.add(key); }
  if (request.operation !== "inspect") {
    check(TOKEN.test(request.lease_id) && TOKEN.test(request.preview_nonce), "Invalid eye preview lease");
    check(plainText(request.identity_key, 2048) && plainText(request.baseline_id, 2048), "Invalid eye generation identity");
    add("lease_id", request.lease_id); add("preview_nonce", request.preview_nonce);
    add("identity_key", request.identity_key); add("baseline_id", request.baseline_id);
  }
  switch (request.operation) {
    case "inspect": case "step": case "renew": case "cancel": case "close": break;
    case "open": case "enqueue":
      check(integer(request.view_revision) && Number.isFinite(request.yaw_degrees)
        && Math.abs(request.yaw_degrees) <= 69 && Number.isFinite(request.zoom) && request.zoom > 0 && request.zoom <= 10
        && ["head-and-shoulders", "eyes-close-up"].includes(request.framing), "Invalid bounded eye preview view");
      add("view_revision", request.view_revision); add("yaw_degrees", request.yaw_degrees);
      add("framing", request.framing); add("zoom", request.zoom);
      // Same canonical settings payload is used for preview and live apply.
      break;
    case "apply": case "restore": break;
    case "ack":
      check(integer(request.frame_sequence, 1, 1200), "Invalid eye frame acknowledgement sequence");
      check(request.file_name === `eye-live-${request.preview_nonce}-${String(request.frame_sequence).padStart(4, "0")}.png`,
        "Eye acknowledgement does not name its exact owned frame");
      add("frame_sequence", request.frame_sequence); add("file_name", request.file_name);
      break;
    default: throw new Error("Unknown eye operation");
  }
  if (request.operation === "open" || request.operation === "enqueue" || request.operation === "apply" || request.operation === "restore") {
    check(integer(request.eye_revision), "Invalid eye settings revision");
    add("eye_revision", request.eye_revision);
  }
  if (request.operation === "open" || request.operation === "enqueue" || request.operation === "apply") {
    check(request.settings && Object.keys(request.settings).length === HUMAN_IRIS_WIRE_KEYS.length
      && Object.keys(request.settings).every(key => (HUMAN_IRIS_WIRE_KEYS as readonly string[]).includes(key)), "Unexpected eye parameter payload");
    allowed.add("settings");
    for (const key of HUMAN_IRIS_WIRE_KEYS) {
      const value = request.settings[key];
      // Exact observed per-generation domains are additionally checked by the
      // host schema and native registry; this codec has no authority to widen them.
      check(Number.isFinite(value), "Nonfinite eye parameter");
      fields[key] = value;
    }
  }
  check(Object.keys(request).every(key => allowed.has(key)), "Unknown eye request field");
  const output = Object.entries(fields).map(([key, value]) => `${key}=${encode(value)}`).join("\n") + "\n";
  check(Buffer.byteLength(output, "utf8") <= REQUEST_BYTES, "Eye request exceeds byte limit");
  return output;
}

export function parseEyeNativeResponse(bytes: Uint8Array): Readonly<Record<string, string>> {
  check(bytes.byteLength > 0 && bytes.byteLength <= RESPONSE_BYTES, "Eye response exceeds byte limit");
  const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  check(text.endsWith("\n") && !text.includes("\r") && !text.includes("\u0000"), "Incomplete or malformed eye response");
  const lines = text.slice(0, -1).split("\n");
  check(lines.length <= 4096, "Eye response exceeds field limit");
  const output: Record<string, string> = Object.create(null) as Record<string, string>;
  for (const line of lines) {
    const split = line.indexOf("=");
    const key = line.slice(0, split);
    check(split > 0 && FIELD.test(key) && !key.split(".").some(part => ["__proto__", "constructor", "prototype"].includes(part)), "Invalid eye response field");
    check(!Object.hasOwn(output, key), "Duplicate eye response field");
    const raw = line.slice(split + 1);
    check(Buffer.byteLength(raw, "utf8") <= 16384 && !hasControl(raw), "Invalid eye response value");
    // Decode exactly once. Only the escapes emitted by the line serializer are
    // accepted; percent text such as %2525 remains literal %25 after decoding.
    check(!/%(?!25|0D|0A)/u.test(raw), "Invalid eye response escape");
    output[key] = raw.replace(/%(25|0D|0A)/gu, (_, escaped: string) => escaped === "25" ? "%" : escaped === "0D" ? "\r" : "\n");
  }
  check(output.wire_version === "1", "Unsupported eye response version");
  check(BOOT.test(output.boot_id ?? "") && TOKEN.test(output.owner_id ?? "") && TOKEN.test(output.request_id ?? ""), "Invalid eye response identity");
  check(/^[1-9]\d{0,9}$/u.test(output.command_sequence ?? "")
    && integer(Number(output.command_sequence), 1), "Invalid eye response sequence");
  return Object.freeze(output);
}

// Correlation only. A matching response is not a successful setter, fresh
// frame, verified original restore, or ready session without its native result.
export function assertEyeResponseCorrespondence(request: EyeNativeWireRequest, response: Readonly<Record<string, string>>): void {
  const expected: Record<string, string | number> = {
    wire_version: 1, operation: request.operation, boot_id: request.boot_id,
    owner_id: request.owner_id, request_id: request.request_id, command_sequence: request.command_sequence,
  };
  if (request.operation !== "inspect") {
    Object.assign(expected, { lease_id: request.lease_id, preview_nonce: request.preview_nonce,
      identity_key: request.identity_key, baseline_id: request.baseline_id });
  }
  if (request.operation === "open" || request.operation === "enqueue") expected.view_revision = request.view_revision;
  if (request.operation === "open" || request.operation === "enqueue" || request.operation === "apply" || request.operation === "restore") {
    expected.eye_revision = request.eye_revision;
  }
  if (request.operation === "ack") Object.assign(expected, { frame_sequence: request.frame_sequence, file_name: request.file_name });
  for (const [key, value] of Object.entries(expected)) {
    check(response[key] === String(value), `Eye response does not match outstanding request: ${key}`);
  }
}
