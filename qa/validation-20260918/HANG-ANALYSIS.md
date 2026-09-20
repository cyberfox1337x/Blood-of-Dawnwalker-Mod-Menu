# Startup freeze (D-8) — what it is, what it is not, and what to do (rewritten 2026-09-18 23:20)

The morning version of this file blamed Steam's overlay. That was wrong: the overlay frames in the
first dumps were stack residue, and the overlay is not on any thread's stack during the stall.
Everything below is from the evening's live measurements (all commands and captures are in the
session scratchpad; the key dumps are copied next to this file).

## Symptom
Black screen after launch; the mod runtime never reports; ~135 s after launch the game is dead.
The window shows nothing because the dialog Unreal opens ("Application Hang Detected — The
application has hung and will now close") is destroyed together with its owner and the game
thread then loops in `GetMessageW` forever (`MessageBoxExtInternal` at Dawnwalker.exe+0x3f8b664).

## Mechanism (from a minidump taken mid-stall, `hang-capture-20260918-222520`, with thread names)
- **GameThread**: `FlushRenderingCommands` → `WaitUntilTasksComplete` ("Waiting Task (FrameSync)")
  → `FEventWin::Wait` → `WaitForSingleObject`. Entered from a console-variable change inside the
  game's FSR/frame-generation plugin (`FFXFSRTemporalUpscaling`, "Setting the console variable …").
- **RenderThread 0**: waiting on a task-graph event ("GraphTask" / "GraphEvent").
- **RHIThread**: idle in `ReturnFromNamedThreadTask` (`WaitOnAddress`) after an RHI task that
  referenced `r.FinishCurrentFrame`.
- Nothing is inside `gameoverlayrenderer64.dll`, `steamclient64.dll` or `steam_api64.dll`.
- The 120 s figure is Unreal's `GTimeoutForBlockOnRenderFence` in `GameThreadWaitForTask`
  ("othreadtimeout" string next to the wait). With the `-nothreadtimeout` launch option the game
  thread waits **forever** (verified: 6 min, process alive, idle) — the render path is dead, not slow.
  The timeout's hang report is what opens the dialog on the game thread.

So: a **startup deadlock between the game thread and the render/RHI thread**, i.e. a race.

## When it happens (counts from today)
- Only with UE4SS loaded. UE4SS core with every Lua mod disabled reproduces it; the vanilla game
  did not stall from the same state. **Our Lua payload is not involved.**
- Injection time does not matter: UE4SS injected at +9 s and at +32 s both still produced it
  (2/3 clean at +32 s vs ~1/8 with the proxy — not enough to build on).
- Strongly tied to the **previous session ending uncleanly** (killed / crashed) after it reached the
  title screen: ~85 % of such launches froze. The launch **after a frozen one came up every time**
  (~15/15). After a graceful quit: clean (2/2). Strict hang/clean alternation under kill loops.
- Ruled out by direct test (each still froze): Steam overlay per-game OFF, overlay global OFF,
  waiting 90 s, `[Core.System] HangDuration=0` in the user Engine.ini, UE4SS `UseCache=1`,
  moving the NVIDIA `DXCache` PSO file and `D3DSCache` aside, Steam Cloud OFF, config inis
  (byte-identical across clean/frozen boots). A Steam client restart helped 5/7 times but stranded
  Steam at its login prompt once (`loginusers.vdf` lost `MostRecent/AllowAutoLogin`), so it is not
  a safe automatic action and was removed from the menu.

## What ships
- The runtime publishes `shutdown = "quit"` in its final snapshot on a real quit
  (`ImportedMenuFacade.Shutdown`, `main.lua` EndPlay reason 4). The desktop uses its absence,
  once the process is gone, to warn: *the next launch may freeze once; if it does, close the game
  and start it again* (`electron/importedMenuTransport.ts`, tests).
- After 150 s of a running game with no heartbeat the menu says it is the startup freeze and gives
  the same recovery, plus "quitting through the game's own menu avoids it".
- Tooling: `close_game.py` (WM_CLOSE, graceful) is what test scripts should use; `Stop-Process`
  is what *creates* the state.

## Practical rule for the player
Quit the game through its own menu. If the game ever crashes or is force-closed, the next launch
may sit on a black screen for two minutes and die; close it and launch again — that has worked
every time. A Steam restart is not needed.

## Still open
The underlying deadlock is inside the engine/plugins and only surfaces with UE4SS present during
startup. A menu-driven late injection of UE4SS (no proxy DLL; inject after the title screen) is the
one lever that could remove it entirely; 2/3 today, needs a proper series before it can be adopted.
Evidence folders: `hang-20260918-111629`, `hang-20260918-115553`, `boot-series-20260918-1943`,
`hang-capture-20260918-222520` (mid-stall, named threads).
