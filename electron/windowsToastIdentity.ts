import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("windows_toast_identity");

/**
 * Windows only delivers a toast for a desktop app that owns a Start Menu shortcut
 * carrying the same AppUserModelID as the running process. An installed build gets one
 * from its installer; an unpacked build does not, and its notifications are dropped
 * silently - no error, no entry in the notification centre.
 *
 * This creates that one shortcut. It is an ordinary user Start Menu entry, written only
 * when objective reminders are switched on, and it is what makes the notification the
 * user asked for actually arrive.
 */

/** Built from a character code so no editing step can silently eat the separator. */
const BACKSLASH = String.fromCharCode(92);
/** A here-string header must be the last thing on its line, so lines stay separate. */
const chr10 = String.fromCharCode(10);

export function toastShortcutPath(appDataRoamingPath: string, productName: string): string {
  return join(appDataRoamingPath, "Microsoft", "Windows", "Start Menu", "Programs", `${productName}.lnk`);
}

function singleQuoted(value: string): string {
  // PowerShell escapes a single quote by doubling it; nothing else is special inside.
  return `'${value.replace(/'/g, "''")}'`;
}

/**
 * The script is a constant with only quoted literals substituted, so a path can never
 * be read as PowerShell syntax.
 */
export function buildShortcutScript(options: Readonly<{
  shortcutPath: string; executablePath: string; appUserModelId: string; iconLocation: string;
}>): string {
  const shortcut = singleQuoted(options.shortcutPath);
  const executable = singleQuoted(options.executablePath);
  const modelId = singleQuoted(options.appUserModelId);
  const icon = singleQuoted(options.iconLocation);
  return [
    "$ErrorActionPreference='Stop';",
    `$shortcutPath=${shortcut};$target=${executable};$modelId=${modelId};$icon=${icon};`,
    "$parent=Split-Path -Parent $shortcutPath;",
    "if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};",
    "$shell=New-Object -ComObject WScript.Shell;",
    "$link=$shell.CreateShortcut($shortcutPath);",
    "$link.TargetPath=$target;",
    `$link.WorkingDirectory=Split-Path -Parent $target;`,
    // Windows draws the taskbar button of every window with this AppUserModelID from
    // this shortcut's icon, so it must be set explicitly: a shortcut left on the
    // target's default shows whatever executable ran last - including Electron's own
    // atom when the menu was started unpacked - instead of the menu's crest.
    "$link.IconLocation=$icon;",
    "$link.Save();",
    // The AppUserModelID lives in the shortcut's property store, which WScript.Shell
    // cannot reach, so the property is set through the shell COM interfaces.
    "Add-Type -TypeDefinition @'",
    "using System;using System.Runtime.InteropServices;",
    "[StructLayout(LayoutKind.Sequential,Pack=4)]public struct PropertyKey{public Guid fmtid;public uint pid;public PropertyKey(Guid f,uint p){fmtid=f;pid=p;}}",
    "[StructLayout(LayoutKind.Explicit)]public struct PropVariant{[FieldOffset(0)]public ushort vt;[FieldOffset(8)]public IntPtr p;}",
    "[ComImport,Guid(\"886d8eeb-8cf2-4446-8d02-cdba1dbdcf99\"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]public interface IPropertyStore{",
    "void GetCount(out uint c);void GetAt(uint i,out PropertyKey k);void GetValue(ref PropertyKey k,out PropVariant v);",
    "void SetValue(ref PropertyKey k,ref PropVariant v);void Commit();}",
    "[ComImport,Guid(\"00021401-0000-0000-C000-000000000046\")]public class ShellLink{}",
    "[ComImport,Guid(\"0000010b-0000-0000-C000-000000000046\"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]public interface IPersistFile{",
    "void GetClassID(out Guid id);[PreserveSig]int IsDirty();void Load([MarshalAs(UnmanagedType.LPWStr)]string f,uint m);",
    "void Save([MarshalAs(UnmanagedType.LPWStr)]string f,[MarshalAs(UnmanagedType.Bool)]bool r);void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)]string f);void GetCurFile([MarshalAs(UnmanagedType.LPWStr)]out string f);}",
    "public static class Aumid{",
    "public static void Set(string path,string id){",
    "var link=(IPersistFile)new ShellLink();link.Load(path,2);",
    "var store=(IPropertyStore)link;",
    "var key=new PropertyKey(new Guid(\"9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3\"),5);",
    // The PROPVARIANT is filled by hand rather than through
    // InitPropVariantFromString: that helper is inline in the SDK header and is not
    // exported by propsys.dll on every Windows build. VT_LPWSTR is 31.
    "var value=new PropVariant();value.vt=31;value.p=Marshal.StringToCoTaskMemUni(id);",
    "store.SetValue(ref key,ref value);store.Commit();",
    "link.Save(path,true);Marshal.FreeCoTaskMem(value.p);}}",
    "'@;",
    "[Aumid]::Set($shortcutPath,$modelId);",
    "Write-Output 'registered'",
  ].join(chr10);
}

/**
 * Ensures the Start Menu shortcut exists with the right AppUserModelID.
 * Resolves to false rather than throwing: a missing shortcut costs the desktop
 * notification, and must never stop the menu from starting.
 */
export async function ensureToastShortcut(options: Readonly<{
  shortcutPath: string; executablePath: string; appUserModelId: string; iconLocation: string;
  /**
   * Leave a shortcut that already exists untouched. An unpacked run (``electron .``)
   * uses this so it cannot re-point an installed build's shortcut at the development
   * binary; the AppUserModelID it carries is what delivers the toast, not the target.
   */
  keepExisting?: boolean; systemRoot?: string;
}>): Promise<boolean> {
  if (process.platform !== "win32") return false;
  if (options.keepExisting && existsSync(options.shortcutPath)) return true;
  const powershell = join(options.systemRoot ?? process.env.SystemRoot ?? `C:${BACKSLASH}Windows`,
    "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const script = buildShortcutScript(options);
  return new Promise<boolean>(resolveRegistration => {
    execFile(powershell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
      "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")],
    { windowsHide: true, timeout: 20000, maxBuffer: 16384, encoding: "utf8" }, (error, stdout) => {
      if (error) {
        console.warn("Could not register the notification shortcut:", error.message);
        resolveRegistration(false);
        return;
      }
      resolveRegistration(stdout.includes("registered"));
    });
  });
}
