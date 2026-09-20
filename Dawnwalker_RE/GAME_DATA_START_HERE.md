# Game classes, functions, properties and player data

This folder contains every record available in our preserved **CL257186 / Steam build 25129649** reflection capture. The game was at its main menu when that capture was taken on **September 6, 2026**; the indexed export was assembled September 8. These files are the complete available capture, not a claim that every possible game object was loaded or every asset was extracted.

## Open these files

| Requested data | File | Captured records |
|---|---|---:|
| All captured classes | [all_classes.csv](data_exports/all_classes.csv) | 9,328 |
| All captured functions | [functions.csv](full_dump/CL257186/functions.csv) | 21,669 |
| Functions with full parameter contracts | [all_function_contracts.csv](feature_catalog/all_function_contracts.csv) | 21,669 |
| Properties and function parameters | [properties.csv](full_dump/CL257186/properties.csv) | 112,652 |
| Objects, including classes, structs and enums | [objects.csv](full_dump/CL257186/objects.csv) | 54,035 |
| Captured/default property values | [property_values.csv](full_dump/CL257186/property_values.csv) | 282,225 |
| Enum names and values | [enum_values.csv](full_dump/CL257186/enum_values.csv) | 19,022 |
| Type, ownership and inheritance links | [relationships.csv](full_dump/CL257186/relationships.csv) | 188,016 |
| Original searchable reflection database | [mod_menu.sqlite](full_dump/CL257186/mod_menu.sqlite) | All capture tables |
| Expanded feature development database | [feature_catalog.sqlite](feature_catalog/feature_catalog.sqlite) | Capture plus contracts, categories and feature leads |
| Latest player-data observation | [latest-observation.json](live_player_data/latest-observation.json) | See its timestamp and freshness status |

The standalone classes CSV contains every column from the source database's `classes` view, including exact reflected paths, parent classes, declared layout size, flags and original JSON. It is a separate export so the preserved capture and its existing hash manifest stay unchanged. The properties table includes **58,222 function parameter records**; the function-contract export attaches those parameters to their functions.

## Live player data is separate

Read [the latest observation](live_player_data/latest-observation.json) before treating any values as current. Its process observation and source-file freshness determine what was actually available. A copied bridge state file is not automatically a fresh in-game readback. If the game is closed, player data cannot be freshly captured through the running game; existing values must remain labeled historical or stale.

The reflection capture's class-default-object values are **not the current player's health, stamina, blood, position, inventory or quest state**. Captured addresses and vtable entries belong to an earlier process and must not be reused as live pointers. This handoff does not install a runtime, send bridge commands, load a save, or mutate gameplay.

## Use it to build features

- [Player-focused records](full_dump/CL257186/menu_slices/player.json) and [inventory records](full_dump/CL257186/menu_slices/inventory.json) narrow the capture to useful starting points.
- [Feature menu](feature_catalog/FEATURE_MENU.md) groups 54 declaration-backed feature proposals. They are development candidates, not 54 working controls.
- [Search guide](feature_catalog/queries.md) gives function, property, object, asset, enum and recipe searches.
- [Runtime evidence](feature_catalog/runtime_evidence.md) separates existing tested behavior from unresolved implementation work.
- [Capture provenance and limits](full_dump/README.md) documents source hashes, validation and asset scope.

From the project root, this command searches existing function metadata without contacting the game:

```powershell
python -B Dawnwalker_RE/feature_catalog/search_catalog.py "Health" --kind function --limit 20
```

Before implementing a control, verify the current executable against the capture, resolve the current player/component instance, confirm the exact argument types, establish an authoritative readback, and test restoration on an isolated save. The captured executable SHA-256 is `7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853`.

## Live read completed

See [live player readback](live_player_data/README.md). Health100%, stamina100%, blood75%, world speed1.00x and coordinates were retrieved through existing getters at 09/08/2026 23:23:07. This is a point-in-time subset, not all live player properties.
