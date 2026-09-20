const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_desktop_error");

export function formatDesktopError(cause: unknown, fallback: string): string {
  const message = cause instanceof Error ? cause.message : typeof cause === "string" ? cause : fallback;
  // Remove Electron's transport label only; preserve the complete underlying error and recovery details.
  const body = message.replace(/^(?:Error: )?Error invoking remote method '[^'\r\n]+': (?:Error: )?/, "");
  return body.length ? body : fallback;
}
