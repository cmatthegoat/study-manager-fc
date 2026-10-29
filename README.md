# Study Manager FC

A study tracker dressed as a football manager. Log study time to earn Club Cash,
XP and match minutes; spend the minutes to unlock Champions League fixtures; manage
a squad, a transfer market and a youth academy while your subjects, topics, todos
and exam results feed straight into the club's economy.

A macOS app: SwiftUI on Swift Package Manager, targeting macOS 14 and up.

The Windows (Avalonia) build used to live here as a parallel app sharing the same
rules and save file. It now lives in its own repository, so this one is Mac-only;
the last revision here that contained it is `7d973ec`.

## What's in it

**macOS sections** — Dashboard, Study Log, Subjects, Todos, Squad, Transfers,
Champions League, Exams, AI Marking.

**Automatic marking.** The AI Marking tab marks a past paper against a rubric with
Apple's on-device model, so nothing is uploaded, there is no account and no cost
per paper. Guidelines and your written answer can be typed, pasted, or added as
**PNG, JPEG or PDF** files; images and scanned PDFs are read with Vision OCR
first, because the model only accepts text. Results come back per question with a
reason, are shown as a draft for review, and are saved into the assessment log
with one button. It needs macOS 26 or later on an Apple silicon Mac with Apple
Intelligence switched on; the tab explains what is missing otherwise, and the
macOS 14 minimum still builds and runs everything else.

**Marks charts.** The Exams tab charts assessments *and* the work you log through
the timer: homework, past papers and exam-style questions each have marks over
time, with a segmented switch between the three and an all-work view, plus pieces,
average, marks and best-score figures.

**Transfer list.** Open a player in the Squad tab and add him to the transfer
list instead of releasing him for a fraction of his value. After every match you
play, each listed player without a pending offer draws one: a coin flip decides
whether it is a serious bid (around or above his market value) or a lowball. The
bell in the header lists them, and each offer can be accepted, declined, or
countered — the buying club has a hidden ceiling and loses patience if you keep
pushing past it, so overplaying a negotiation ends the talks.

**Study Log.** Every session ever logged, in one place. The dashboard shows only
the latest eight; the Study Log has the full history with a search field that
matches titles, subjects, topics, activity kinds, marks and dates, plus subject,
activity and time-period filters, day-by-day grouping and per-day totals.

**The loop.** Every logged session pays `minutes × rate × subject multiplier ×
activity multiplier × grade`, and adds the same minutes to your match readiness.
Past papers are worth 1.5× homework, exam-style questions 1.25×, and marks scale
the reward from 0.8× at 0% to 1.45× at 100%. Ninety minutes unlocks a fixture.

**Career.** Real clubs and squads imported from the EA FC database, negotiated
transfers, a five-level youth academy that intakes every five matches, player
development and retirement at 40, and a full season/schedule/trophy pipeline.

**Study side.** Per-subject and per-topic aggregates weighted by marks attempted,
custom topics you create yourself, priority todos with inline `p1 #Subject - Topic:`
directives, streaks, and assessments that reward class rank.

**Team colours.** The whole palette follows the club you manage — Barcelona runs
garnet and blue, Real Madrid white and gold — driven by `TeamTheme` in
`Sources/StudyManagerFC/Theme.swift`. Club colours are re-valued in HSV so they
stay legible on the near-black canvas.

## Build and run

### macOS

```bash
swift build
swift run StudyManagerFC
```

Useful entry points:

```bash
swift run StudyManagerFC --self-test        # round-trips a career in a temp dir
swift run StudyManagerFC --verify-database  # proves the bundled DB decodes
Scripts/package-app.sh                      # writes dist/StudyManagerFC.app
Scripts/package-dmg.sh                      # writes dist/StudyManagerFC.dmg (drag-to-Applications image)
```

Requires Xcode 15+ / Swift 5.9 and macOS 14 (the package targets `.macOS(.v14)`).
Automatic marking needs macOS 26 or later on an Apple silicon Mac with Apple
Intelligence enabled; everything else runs on macOS 14.

## Save files

The career is written to `~/Library/Application Support/StudyManagerFC/career.json`.

Saves are schema-versioned and older ones migrate on load.

## Player database

`Sources/StudyManagerFC/Resources/fc-database.json` (2.0 MB, checked in) holds
every club and player: id, overall, potential, position, nationality, age, club
and name.

It is regenerated with:

```bash
python3 Scripts/extract-fc-database.py --out Sources/StudyManagerFC/Resources/fc-database.json
```

**The source game files are not in this repository.** The extractor reads EA's
`t3db` format from `db_loc_27/`, and the names/overall export lives in
`Fifa names and ovrs/`. Both directories are gitignored — they are third-party
data, and the repo should stay free of them. Without them you can still build and
run the app; you just can't regenerate the JSON.

The ratings export carries no potential column, but the game database does. After
extracting, fill it in from there:

```bash
python3 Scripts/fill-potential.py
```

The game database numbers its players one above the ratings export, so the script
joins on `id + 1` and only accepts a match when the player's age *and*
nationality agree — 11,892 of the 17,873 rows are verified that way and take the
game's own ceiling. Rows with no twin (players added in a later title update) get
a ceiling from the same age bands the generated players use, seeded by player id
so the value never changes. As a result 14,269 rows (79.8%) now have room to grow
and only genuinely maxed players sit at their overall.

Careers saved before this carry a derived ceiling; schema 6 migrates them to the
data file's real potential, floored at the rating they have already reached.

## Repository layout

```
Package.swift              SwiftPM manifest (macOS app)
Sources/StudyManagerFC/    Swift app: models, engines, store, views, theme, data
Scripts/                   extract-fc-database.py, fill-potential.py, package-app.sh, package-dmg.sh
```

Large and generated paths are ignored by `.gitignore`: `.build/`, `dist/`,
`.tools/`, `**/bin/`, `**/obj/`, `db_loc_27/`, `Fifa names and ovrs/`.

## License

Add a license before publishing — none is included yet.
