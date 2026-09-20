# Native player helper: dependency blocker

2026-09-08. Preparation only; no helper DLL produced or loaded.

The official UE4SS source was cloned into the isolated `vendor/RE-UE4SS` directory and checked out at the exact installed runtime commit:

`97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1`

Its required Unreal compatibility submodule is:

- Repository: `https://github.com/Re-UE4SS/UEPseudo.git`
- Relative path: `deps/first/Unreal`
- Required commit: `eb40a05f49509bdeb1ac39287032b60af585cca8`

The GitHub fetch returned **Repository not found** twice through the normal submodule retry. The available session cannot establish access to this dependency. The pinned CMake build requires it through `deps/first/CMakeLists.txt`, which calls `add_subdirectory("Unreal")`.

The other declared submodule is patternsleuth at `240a7dc065fc29b3c500bfa3db0d655755a9bceb`. No dependency version was substituted. Upstream source files were not edited.

Available local build tools include Visual Studio 18 Community, MSVC 14.51.36231, CMake, Ninja, MSBuild and Windows SDK 10.0.26100.0. Their presence does not replace the missing matching Unreal headers/library or prove binary compatibility. The existing runtime ZIP has not been replaced.

## Why implementation stopped

The helper needs the exact UE4SS Unreal reflection types to validate the setter parameter layout, copy the complete borrowed FGameplayAttribute through reflected CopyCompleteValue, initialize/destroy parameters, and execute the approved UFunction on the game thread. Recreating these types or filling missing pieces with offsets would introduce unreviewed ABI assumptions. No guessed binary or raw attribute writer was authored.

The known Lua-only alternative is also blocked: the pinned out-parameter handler requires a Lua table, while table conversion cannot preserve the descriptor's TFieldPath member. UObject.CallFunction calls the same handler. The existing read-only descriptor and failed-write cleanup fixes remain separate from this preparation.

## Next safe step

Provide authenticated access to the required official submodule or an authorized local copy of that exact commit, then resume dependency verification and a minimal compile before writing a game-loadable helper. Do not install anything from this directory yet.

Sources:

- [Official C++ mod workflow](https://docs.ue4ss.com/guides/creating-a-c%2B%2B-mod.html)
- Pinned checkout `.gitmodules`, `deps/first/CMakeLists.txt`, and `cmake/modules/VersionChecks.cmake`.
- [Pinned Lua parameter marshaller](https://github.com/UE4SS-RE/RE-UE4SS/blob/97b7e501/UE4SS/src/LuaType/LuaUObject.cpp)

No application source, runtime installation, manifest, catalog or user save was modified during this subtask.
