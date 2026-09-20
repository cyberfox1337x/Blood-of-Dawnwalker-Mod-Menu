# Imported menu source

Gameplay source was supplied locally as the v3.2 Dawnwalker menu archive and preserved at `analysis/supplied-mod-v3.2`. The copies under `Scripts/Source` retain the source comments and native control logic. `GameplayMenu.lua` adapts the original `main.lua`: overlay configuration and F11/F12 registration were removed, the local state directory is injected, and the startup message identifies the headless entrypoint. Each adapted code file carries the required module signature.

`ImportedMenuFacade.lua`, `ImportedSourceLoader.lua` and `main.lua` provide the bounded local transport and owned scheduler. They do not load the supplied ModMenu rendering framework or change the existing application's Visuals. The original native inventory ItemHandle hook remains because that struct must be consumed within its hook callback lifetime.

The accompanying third-party notice applies to the supplied ModMenu framework and identifies Matthew arvidson / mattdavida and its MIT license. It is retained for provenance; it does not declare the separate supplied gameplay modules MIT licensed.

No gameplay feature is automatically enabled. An operation marked `completed` means its scheduled finite callbacks drained; original native status labels describe the actual result. A failed operation remains `running` until its finite callbacks drain, so close and subsequent commands cannot overlap it. Timed stamina refill, activation charge override, cooldown reset and parry assist remain distinct source behaviors. Hidden unsupported source God Mode is not exposed. Long-running progression operations must finish before closing, loading or saving. Closing requests OFF callbacks for enabled controls and cancels pending confirmation. Obtain the close acknowledgement before unloading: non-game-thread unload invalidates queued work synchronously and explicitly reports unverified restoration if that handshake did not finish; it cannot rely on a queued OFF call surviving UE4SS teardown.

Session-reset hooks clear cancelled pre-execution busy flags and stale inventory selections. Issued-but-unverified time, respec, and interrupted bulk-equipment operations retain restart/recovery lockouts. Internal hidden legacy values remain private to the modules and are not external command targets.

Source identity, payload hashes and catalog are recorded in the parent integration manifest. Actual game behavior still requires live verification on the pinned build; source registration and mocked tests alone are not gameplay proof.


## Dawnwalker Form Toggle 0.3.0

`Scripts/FormToggleControl.lua` adapts the user-supplied DawnwalkerFormToggle V0.3.0 (Nexus mod 213, file 589) native form, body, equipment and ability quickslot operations. Copyright (c) 2026 Dawnwalker Form Toggle contributors. MIT license: `FORM_TOGGLE_LICENSE.txt`. Original Downloads archive is unchanged. The adapter uses a menu checkbox (ON forced vampire; OFF automatic day/night), scoped ability hooks, owned cleanup and delayed form verification; it registers no extra hotkeys and does not alter the world clock. Native success and gameplay behavior require verification on the installed build.
