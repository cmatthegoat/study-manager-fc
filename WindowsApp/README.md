# StudyManager FC — Windows

A native Windows desktop build of StudyManager FC, sharing the macOS version's
rules, data and save file. It is an Avalonia (.NET 8) app: one window, the same
sections (Dashboard, Study Log, Subjects, Squad, Transfers, Champions League), the
same green study theme, and the same career economy. The Study Log mirrors the
macOS tab: every entry, searchable by title, subject, topic, activity, marks or
date, with subject / activity / period filters and deletion.

**For players:** the packaged build lives at
`dist/StudyManagerFC-Windows/StudyManagerFC.exe`. It is self-contained — no .NET
install is required. Double-click it and pick a club.

## What lives here

| Path | Purpose |
| --- | --- |
| `src/StudyManagerFC.Core` | All game rules: models, player generator, match/schedule/season engines, the game store, and JSON persistence. No UI dependencies, so the rules can be tested on their own. |
| `src/StudyManagerFC.Desktop` | Avalonia UI: theme and custom controls, tab shell, the pages, and the player/lineup/match-report dialogs. |
| `tests/StudyManagerFC.Tests` | xUnit tests for pricing, squad ratings, simulation, season rollover and the save file format. |
| `tools/generate-data.py` | Regenerates `src/StudyManagerFC.Core/Data.Generated.cs` (nations, clubs, club squads, name pools) from the Swift sources so both apps read the same dataset. |
| `tools/make-icon.py` | Draws `app.ico` with no image dependencies. |
| `tools/bootstrap-dotnet.sh` | Installs a private .NET 8 SDK into `.tools/dotnet`. |

## Build, test, package

```bash
WindowsApp/tools/bootstrap-dotnet.sh      # once, installs the SDK locally
dotnet test WindowsApp/tests/StudyManagerFC.Tests/StudyManagerFC.Tests.csproj
Scripts/package-windows.sh                # tests, publishes win-x64, writes the zip
```

The packaged output is `dist/StudyManagerFC-Windows/` plus
`dist/StudyManagerFC-Windows-x64.zip`.

## Save file compatibility

Both builds write the same `career.json`: camel-cased keys, ISO-8601 timestamps
without fractional seconds, string enums, upper-case UUID strings. The Windows
build stores it at `%APPDATA%\StudyManagerFC\career.json`; the macOS build uses
`~/Library/Application Support/StudyManagerFC/career.json`.

Compatibility was verified in both directions rather than assumed:

1. The Swift app created a career, added Ext 2 Maths topics and logged three
   marked sessions.
2. The C# app loaded that file with identical cash, XP, topics, marks and
   per-session rewards, added a physics topic and a marked session, and saved.
3. The Swift app reopened the file and showed all three topics, all four
   sessions and the same rewards the C# app had written.

Saves are schema-versioned (currently 3 here, 4 on the Mac). A schema-1 save from
before the 40-year retirement rule is migrated on load; a schema-2 save without
subtopics loads with no topics and keeps its sessions and marks.

**Database-era careers stay on the Mac.** The macOS build now fills squads from
the imported EA FC database and stores a `dbID`/`clubID` on each player. This
build loads such a save (it ignores the extra keys) but drops those two fields
when it writes, which would make signed players reappear on the Mac's transfer
market. Everything else — cash, XP, study history, marks, topics, fixtures —
round-trips unchanged.

## Parity notes

- **Rules are identical**, not reimplemented by eye: fees are
  `250 × 1.16^(overall − 60)`, overall never includes chemistry, academy intake
  adds three teenagers per season, players retire at 40, and development depends
  on starting-XI membership.
- **Study rewards match exactly**: `minutes × 10 cash (or 6 XP) × subject
  multiplier × activity multiplier × grade`, where activity is 1.5 for past
  papers, 1.25 for exam-style questions and 1 for homework, and grade runs from
  0.8 at 0% marks to 1.45 at 100%. Averages per subject and per topic are
  weighted by marks attempted.
- **Rendering is not pixel-identical.** The macOS app uses SF Symbols and
  SwiftUI materials; this build uses text glyphs, solid translucent surfaces and
  custom-drawn controls. Layout, palette and information hierarchy follow the
  Mac screens.
- **Match randomness** uses the same SplitMix64 generator, but .NET and Swift
  map uniform rolls onto integer ranges slightly differently. Two saves will
  stay in sync as files, and both produce the same rating-driven results, but
  replaying the same unplayed fixture on both platforms can produce a different
  scoreline.
- Packs exist in the model (and the pack economy matches) but, as in the macOS
  build, there is no pack screen in the UI.
- **The database import is macOS-only for now.** The Mac builds every squad from
  the EA FC database (real clubs, ratings, positions, ages and nationalities) and
  every signing has to be negotiated with the owning club. This build still
  generates squads and signs players for a fixed fee.

## Editing the shared data

Club squads, club ratings and name pools come from the Swift source of truth:

```bash
python3 WindowsApp/tools/generate-data.py
```

Re-run that after changing `Sources/StudyManagerFC/ClubSquads.swift`, then
rebuild.
