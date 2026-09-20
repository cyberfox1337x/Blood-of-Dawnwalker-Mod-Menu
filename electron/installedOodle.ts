import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { lstat, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { MAX_DSAV_CHUNK_BYTES, type DsavChunk, type DsavCodec } from "./dsavContainer.js";

const cyberfox1337x = Object.freeze({ function: (moduleName: string) => void moduleName });
cyberfox1337x.function("dawnwalker_installed_oodle");

const CODEC_SHA256 = "111a505e64a3bf1b89c05aab2dd16306bc2267a5ea3f0c9722a3b6152091ce1c";
const DEFAULT_CODEC = "C:\\Program Files\\Epic Games\\UE_5.6\\Engine\\Source\\Programs\\Shared\\EpicGames.Oodle\\Sdk\\2.9.10\\win\\redist\\oo2core_9_win64.dll";
const MAX_BATCH_BYTES = 256 * 1024 * 1024;
const MAX_ENCODED_CHUNK_BYTES = MAX_DSAV_CHUNK_BYTES * 2;

// Our adapter uses the installed runtime in place. It contains no Epic codec or SDK implementation.
// Binary stdin/stdout avoids command interpolation, JSON expansion, and per-chunk process launches.
const CODEC_HOST_SOURCE = String.raw`
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
public static class DawnwalkerCodecHost {
  private static class cyberfox1337x { public static void function(string name) { } }
  [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern IntPtr LoadLibraryEx(string path, IntPtr reserved, uint flags);
  [DllImport("kernel32", CharSet=CharSet.Ansi, SetLastError=true)]
  private static extern IntPtr GetProcAddress(IntPtr module, string name);
  [DllImport("kernel32")] private static extern bool FreeLibrary(IntPtr module);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
  private delegate long Decompress([In] byte[] input, long inputSize, [Out] byte[] output, long outputSize, int fuzzSafe, int checkCrc, int verbosity, IntPtr decodeBase, long decodeSize, IntPtr callback, IntPtr callbackUser, IntPtr scratch, long scratchSize, int threadPhase);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
  private delegate long Compress(int compressor, [In] byte[] input, long inputSize, [Out] byte[] output, int level, IntPtr options, IntPtr dictionary, IntPtr matcher, IntPtr scratch, long scratchSize);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
  private delegate long Capacity(int compressor, long inputSize);
  private static T Bind<T>(IntPtr library, string name) where T : class {
    IntPtr address = GetProcAddress(library, name);
    if (address == IntPtr.Zero) throw new InvalidDataException("Installed codec is missing a required export.");
    return Marshal.GetDelegateForFunctionPointer(address, typeof(T)) as T;
  }
  public static void Run() {
    cyberfox1337x.function("dawnwalker_native_codec_host");
    if (!Environment.Is64BitProcess) throw new InvalidDataException("A 64-bit codec host is required.");
    string path = Environment.GetEnvironmentVariable("DAWNWALKER_CODEC_PATH");
    string mode = Environment.GetEnvironmentVariable("DAWNWALKER_CODEC_MODE");
    string expected = Environment.GetEnvironmentVariable("DAWNWALKER_CODEC_SHA256");
    if (mode != "decode" && mode != "encode") throw new InvalidDataException("Invalid codec operation.");
    using (FileStream codec = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
      using (SHA256 sha = SHA256.Create()) {
        string hash = BitConverter.ToString(sha.ComputeHash(codec)).Replace("-", "").ToLowerInvariant();
        if (hash != expected) throw new InvalidDataException("Installed codec changed before loading.");
      }
      IntPtr library = LoadLibraryEx(path, IntPtr.Zero, 0x00001100);
      if (library == IntPtr.Zero) throw new InvalidDataException("Could not load the installed codec.");
      try {
        Decompress decompress = Bind<Decompress>(library, "OodleLZ_Decompress");
        Compress compress = Bind<Compress>(library, "OodleLZ_Compress");
        Capacity capacity = Bind<Capacity>(library, "OodleLZ_GetCompressedBufferSizeNeeded");
        using (BinaryReader input = new BinaryReader(Console.OpenStandardInput()))
        using (BinaryWriter output = new BinaryWriter(Console.OpenStandardOutput())) {
          int count = input.ReadInt32();
          if (count < 1 || count > 4096) throw new InvalidDataException("Invalid chunk count.");
          output.Write(count);
          long total = 0;
          for (int index = 0; index < count; index++) {
            int length = input.ReadInt32();
            int decodedLength = input.ReadInt32();
            total += length;
            if (length < 1 || length > 262144 || decodedLength < 1 || decodedLength > 131072 || total > 268435456)
              throw new InvalidDataException("Chunk length exceeds codec bounds.");
            byte[] encoded = input.ReadBytes(length);
            if (encoded.Length != length) throw new EndOfStreamException("Truncated codec input.");
            byte[] result;
            long written;
            if (mode == "decode") {
              result = new byte[decodedLength];
              written = decompress(encoded, length, result, decodedLength, 1, 0, 0, IntPtr.Zero, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, 3);
              if (written != decodedLength) throw new InvalidDataException("Codec did not decode the complete chunk.");
            } else {
              if (length != decodedLength) throw new InvalidDataException("Invalid compression input length.");
              long required = capacity(8, length);
              if (required < 1 || required > 262144) throw new InvalidDataException("Invalid compression capacity.");
              result = new byte[(int)required];
              written = compress(8, encoded, length, result, 3, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0);
              if (written < 1 || written > result.Length) throw new InvalidDataException("Codec compression failed.");
            }
            output.Write((int)written);
            output.Write(result, 0, (int)written);
          }
          if (input.BaseStream.ReadByte() != -1) throw new InvalidDataException("Unexpected trailing codec input.");
          output.Flush();
        }
      } finally { FreeLibrary(library); }
    }
  }
}`;

function serializeChunks(chunks: readonly DsavChunk[]): Buffer {
  if (!chunks.length || chunks.length > 4096) throw new Error("Invalid codec chunk count.");
  const header = Buffer.alloc(4);
  header.writeUInt32LE(chunks.length);
  const parts = [header];
  let total = 4;
  for (const chunk of chunks) {
    if (chunk.encoded.length < 1 || chunk.encoded.length > MAX_ENCODED_CHUNK_BYTES || !Number.isInteger(chunk.decodedBytes) || chunk.decodedBytes < 1 || chunk.decodedBytes > MAX_DSAV_CHUNK_BYTES) throw new Error("Invalid codec chunk size.");
    total += 8 + chunk.encoded.length;
    if (total > MAX_BATCH_BYTES) throw new Error("Codec input exceeds the size limit.");
    const sizes = Buffer.alloc(8);
    sizes.writeUInt32LE(chunk.encoded.length);
    sizes.writeUInt32LE(chunk.decodedBytes, 4);
    parts.push(sizes, chunk.encoded);
  }
  return Buffer.concat(parts);
}

function parseResults(bytes: Buffer, count: number): readonly Buffer[] {
  if (bytes.length < 4 || bytes.readUInt32LE(0) !== count) throw new Error("Codec returned an invalid chunk inventory.");
  const results: Buffer[] = [];
  let cursor = 4;
  for (let index = 0; index < count; index++) {
    if (cursor + 4 > bytes.length) throw new Error("Codec returned truncated output.");
    const size = bytes.readUInt32LE(cursor);
    cursor += 4;
    if (size < 1 || size > MAX_ENCODED_CHUNK_BYTES || cursor + size > bytes.length) throw new Error("Codec returned an invalid output length.");
    results.push(bytes.subarray(cursor, cursor + size));
    cursor += size;
  }
  if (cursor !== bytes.length) throw new Error("Codec returned unexpected trailing output.");
  return results;
}

async function verifiedCodecPath(codecPath: string): Promise<string> {
  if (process.platform !== "win32" || process.arch !== "x64") throw new Error("Save decoding requires 64-bit Windows.");
  const absolute = resolve(codecPath);
  const status = await lstat(absolute);
  if (!status.isFile() || status.isSymbolicLink() || status.size > 16 * 1024 * 1024) throw new Error("Installed save codec is not a supported ordinary file.");
  const hash = createHash("sha256").update(await readFile(absolute)).digest("hex");
  if (hash !== CODEC_SHA256) throw new Error("The installed save codec version has not been verified.");
  return absolute;
}

async function transformChunks(codecPath: string, mode: "decode" | "encode", chunks: readonly DsavChunk[]): Promise<readonly Buffer[]> {
  const input = serializeChunks(chunks);
  const verifiedPath = await verifiedCodecPath(codecPath);
  const command = `$ErrorActionPreference = 'Stop'\ntry {\nAdd-Type -TypeDefinition @'\n${CODEC_HOST_SOURCE}\n'@\n[DawnwalkerCodecHost]::Run()\n} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }`;
  const executable = join(process.env.SystemRoot ?? "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  return new Promise((resolveResult, reject) => {
    const child = spawn(executable, ["-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(command, "utf16le").toString("base64")], {
      windowsHide: true,
      env: { ...process.env, DAWNWALKER_CODEC_PATH: verifiedPath, DAWNWALKER_CODEC_MODE: mode, DAWNWALKER_CODEC_SHA256: CODEC_SHA256 },
      stdio: ["pipe", "pipe", "pipe"],
    });
    const output: Buffer[] = [];
    let outputBytes = 0;
    let errorText = "";
    let failed = false;
    const fail = (error: Error) => { if (!failed) { failed = true; child.kill(); reject(error); } };
    const timeout = setTimeout(() => fail(new Error("Save codec timed out. The save was not changed.")), 30_000);
    child.on("error", fail);
    child.stdin.on("error", error => fail(new Error(`Could not send the save to its codec: ${error.message}`)));
    child.stdout.on("data", (part: Buffer) => {
      outputBytes += part.length;
      if (outputBytes > MAX_BATCH_BYTES) { fail(new Error("Save codec output exceeded its size limit.")); return; }
      output.push(part);
    });
    child.stderr.on("data", (part: Buffer) => { errorText = (errorText + part.toString("utf8")).slice(0, 2000); });
    child.on("close", code => {
      clearTimeout(timeout);
      if (failed) return;
      if (code !== 0) { reject(new Error(`Save codec failed. ${errorText.trim() || "No complete output was returned."}`)); return; }
      try { resolveResult(parseResults(Buffer.concat(output), chunks.length)); } catch (error) { reject(error); }
    });
    child.stdin.end(input);
  });
}

export function createInstalledOodleCodec(codecPath = DEFAULT_CODEC): DsavCodec {
  return Object.freeze({
    decompress: (chunks: readonly DsavChunk[]) => transformChunks(codecPath, "decode", chunks),
    compress: async (chunks: readonly Buffer[]) => {
      const compressed = await transformChunks(codecPath, "encode", chunks.map(encoded => ({ encoded, decodedBytes: encoded.length })));
      return compressed.map((encoded, index) => ({ encoded, decodedBytes: chunks[index].length }));
    },
  });
}
