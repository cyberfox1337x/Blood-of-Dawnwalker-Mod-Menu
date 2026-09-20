# Dawnwalker research workspace

Start with the [master technical reference](../THE_BLOOD_OF_DAWNWALKER_REVERSE_ENGINEERING_REFERENCE.md). This pass reads the installed game and existing evidence, writes isolated indexes, and analyzes copies of saves. It is a research knowledge base, not a mod installer.

**September 8 update:** [Current-build mod-menu dump](full_dump/README.md) now preserves and indexes the previously captured CL257186 main-menu JMAP, all 2,239 current headers, property offsets/flags, CDO values, scripts and vtables. Use its SQLite database for current-build reflected layouts; the older indexes below remain explicitly historical. Full captured-type delta is now available. This is the complete existing capture, not every installed asset or a fresh runtime session.

## Evidence map

| Location | Contents / scope |
|---|---|
| build_info / inventories | Current Steam/build identity, hashed executable metadata, PE imports/exports, complete loose-file inventory, container headers, sanitized config keys |
| findings/installation.md | Current identity and bounded container findings |
| unreal/knowledge.sqlite | Historical declarations, members, object records, typed relationships and source hashes |
| classes / functions | Historical class, struct, enum, property, function and enum-value CSVs |
| assets / data_tables | Partial historical object candidates; not a complete installed catalog |
| gameplay_tags/verified_effect_tags.json | Four actual tags from an existing same-build verified effect probe |
| gameplay_tags/tag_related_objects.csv | Historical candidate-name matches; not tag values |
| relationships | Inheritance, declared-property and type-reference edges; not a guessed call graph |
| saves/README.md | Current copied-save decode evidence, source preservation audit and limitations |

## Reproduce safely

Run from the project root with Python 3.12 and PowerShell7:

```powershell
pwsh -NoProfile -File Dawnwalker_RE/scripts/collect_installation.ps1
python Dawnwalker_RE/scripts/index_reflection.py
python Dawnwalker_RE/scripts/index_verified_effects.py
python Dawnwalker_RE/scripts/research_saves.py
```

Collectors write under this workspace and read original files only. Save runs create timestamped evidence; installation/reflection generated indexes refresh in place. Preserve a copy of those outputs when comparing different builds. `build_reference.py` created the first master and intentionally refuses to overwrite an existing master; future findings must merge into the existing document.

The source-header/object dump is dated September2 and associated with the earlier CL256181 discovery epoch. It is not freshly regenerated and must not be treated as current-build offset validation. Each index record retains source path and line. `unreal/source_hashes.csv` fingerprints the2205 inputs. The current-build effect evidence has its own source hash and session. Do not assume dumped C++ display-style names containing spaces are valid C++ symbols.

## Search examples

```powershell
Import-Csv Dawnwalker_RE/functions/functions.csv | Where-Object owner -eq UTimeSystemImpl
Import-Csv Dawnwalker_RE/classes/properties.csv | Where-Object owner -eq ADawnwalkerPlayerCharacter
Import-Csv Dawnwalker_RE/relationships/declarations.csv | Where-Object subject -eq ADawnwalkerPlayerCharacter
```

Open SQLite in any local SQLite browser, or use Python's standard library. Useful queries:

```sql
SELECT owner,name,signature,source,line FROM members WHERE owner='UTimeSystemImpl';
SELECT name,base,module,source,line FROM declarations WHERE name LIKE '%Inventory%';
SELECT path,class_path,source,line FROM objects WHERE kind='DataTable' LIMIT 100;
SELECT subject,relation,object FROM relationships WHERE subject='ADawnwalkerPlayerCharacter';
```

Only `kind='DataTable'` selects actual records of that reported kind; candidate CSV substring searches deliberately also include references and defaults. Totals are records/declarations, not necessarily unique assets or gameplay entities.

## Validation and next research

SQLite integrity check passes. Input declaration/member/relationship sources retain line references. Save parser13 tests pass and49 source copies match before/after hashes. Current executable/module metadata and container header collection completed. No gameplay process was running at observation time; this pass did not start one.

Next: correlate the46 decoded persistence-node names to matching serializer implementations and test selected current-build contracts with readback/rollback evidence. The [current-build reflection delta](full_dump/CL257186/type_delta_summary.json) is available; full encrypted container catalog, exact combat formulas and complete quest consequence graph remain unknown.
