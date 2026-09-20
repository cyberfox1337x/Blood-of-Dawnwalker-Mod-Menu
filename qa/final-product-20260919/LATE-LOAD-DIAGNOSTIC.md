# Title-ready late-load diagnostic

`late_load_ue4ss.py` is a diagnostic tool, not a shipped launcher or accepted startup fix. It does not change the proxy, settings, saves, or startup registration.

The operator must preserve the existing runtime backup, close the game, and temporarily disable the exact backed-up proxy under parent coordination. Launch the verified game normally and visually confirm its title screen. Use that exact process PID:

```powershell
python qa/final-product-20260919/late_load_ue4ss.py --pid <PID>
python qa/final-product-20260919/late_load_ue4ss.py --pid <PID> --execute --title-ready
```

The first command performs read-only preflight. The second loads only the hard-pinned installed UE4SS DLL into the hard-pinned Steam game build. Module presence confirms library loading only; screenshot, new session heartbeat and gameplay/quit evidence are separate acceptance requirements. The title-ready flag is an operator assertion, not automatic visual detection.

All ctypes pointer-sized API signatures are explicit. LoadLibraryW is resolved to its actual local module owner, whose path and image size must match the target module; the remote address uses its remote base plus export RVA. Thread DWORD exit code is recorded but is not treated as an x64 HMODULE. Exact module enumeration verifies completion.

On timeout, the remote thread is not terminated and its argument allocation remains alive because the target may still read it. The tool closes its own handles, returns failure and says not to retry. Close the game under parent coordination to reclaim that allocation. Completed calls free the allocation. No retry, persistence or generic DLL/process override exists.

Validation: seven Python unit tests pass; compilation passes; an actual non-game PowerShell process is refused; execution without title-ready is refused. No live injection was performed by the utility author. Both Python files carry executable cyberfox1337x function-style signatures.
