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

**macOS sections** — Dashboard, Study Log, Subjects, Todos, Calendar, Squad,
Transfers, Champions League, Exams, Journal.

**Calendar.** Any task can carry a due date, set when it is added or from its edit
sheet. The Todos board sorts the soonest deadline first within a priority and marks
tasks that are late or due today. The Calendar section draws every dated task on a
month grid, counts what is overdue, due today and due in the next seven days, and
lists a selected day's tasks — tickable in place — with the undated ones kept in
their own card so nothing quietly loses a deadline.

**Bulletproof Journal.** Every mistake worth never repeating, in one place per
subject — written up by hand, with the rule that fixes it, an optional
**PNG / JPEG / PDF** photo of the working, and a revision count, so "never
revised" is visible rather than assumed. The top of the tab names the topic
costing you the most marks and groups repeats by topic; entries can be revised,
marked beaten, reopened, edited, filtered by subject or searched. Scans are
stored in `JournalAttachments/` beside the save, and deleting an entry deletes
its scan. The Dashboard shows the three mistakes that most need revising. Each open entry is also
scheduled: a new mistake comes back after a day, then three days, a week and a month. The
tab opens with a **Due for review** card, and answering *Got it* moves the entry up the
ladder while *Again* drops it back to tomorrow. The journal pays no cash or XP, so it
cannot be farmed. Each entry can also be tagged with a cause — sign error, arithmetic
slip, misread question, ran out of time — and the tab reports which causes are costing the
most marks, which is a different question from which topics are.

**Viewing the term.** The Exams tab projects each subject's final mark from the assessments
already sat, weighted by their weightings, and shows what the remaining weight has to
average to reach Band 4, 5 or 6. The Dashboard builds the week's plan from the same data —
approaching tests, mistakes waiting for a retest, and the topics with the weakest marked
averages — and every line starts a timed session on exactly that topic. A weekly report
exports the last seven days as Markdown, and ⌘K opens a command palette (⌘1–⌘9 jump
between sections).

**Contracts.** Every player has a contract running four seasons from the season they
joined, and a wage derived from their rating. Deals are not renewed automatically: expiry
at the end of a season sends the player to the free-agent pool, and the Squad tab lists
everyone expiring this season or next with the renewal cost (twelve weeks of wages), so a
squad that is never renewed does not quietly empty itself.

**Apple Calendar.** The Calendar tab can read your own calendars, with your permission,
and lay events over the month beside your study tasks. It is read-only: nothing in the app
ever writes to a calendar or a reminder list.

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
Payouts run through a 3× income rate — 30 Club Cash a minute before the subject and
activity multipliers, so ninety minutes is roughly 2,700–3,800 — because player prices
and the 95,000 academy rungs are set in the tens of thousands. A new career starts with
2,500 Club Cash.

**Career.** Real clubs and squads imported from the EA FC database, negotiated
transfers, a five-level youth academy that intakes every five matches, player
development and retirement at 40, and a full season/schedule/trophy pipeline.
The XI can also be drawn freehand: **Design shape** on the Squad tab opens a pitch of eleven
dots and every outfield player can be dragged anywhere. A dot's role is read from where it
stands — deep and wide is a full-back, deep and central a centre back, the middle band
splits into holding, central, advanced and wide, and the top band is wingers and strikers —
so any arrangement works and there is no template to stay inside. Dots settle onto a
faint grid when released, so a shape drawn quickly still lines up, and any shape can be
named and saved to a library to load again later. Slots can be added and
removed as long as the XI ends up as one goalkeeper plus ten outfield players, saving keeps
whoever already held a place, and the drawn shape is stored with the career; picking a
preset formation again hands the XI back.

Player prices are the rating curve with a 50% premium and then another 35% on top,
just over double the bare curve. The **Market prices** card on the Transfer Market tab
lets you raise every price by hand: a percentage stacks on the current prices, is saved
with the career and can never be undone — a negative or zero percentage is refused, and
the total is capped at ten times the standard. The **Appearance** window — opened from the palette button in the rail or **Appearance**
in the top bar — holds the **PALETTE** menu: seven styles (Club colours, Deep, Bright,
Pastel, Tinted mono, Slate and Ember), each a transformation of the managed club's own
colours, followed by every team in the game, so Real Madrid's colours can be worn while
managing Barcelona. The window stays open while you choose, because changing the palette
rebuilds the board so that every gradient, button fill and selected row repaints in the new
colours, and your chosen section is kept across the rebuild. Every accent is derived from
the palette — timer numerals, button fills, the selected menu row, chart hues, even the cash
and XP icons — so only warnings, injuries, player rarity and the per-subject colours you
pick yourself keep colours of their own. The same window holds a switch for a different
palette on every launch — a random style or a random team's colours, never saved back —
and a button that restores the newest save backup. With Reduce Motion switched on in
macOS, the button press animations, the readiness arc and the rolling timer digits all
stop moving. **LAYOUT** switches the board between the sidebar, an icon-only rail and a
row of sections across the top; palette and layout are saved with the career and are
independent of each other. A club never
counters below the bid it is answering: a bid within a whisker of the asking price
closes the deal at the bid rather than producing a lower "counter".

**Academy.** Each level has its own batch: level 1 sends one 50–60 rated boy with
60–70 potential, level 2 two at 55–65/70–80, level 3 three at 60–70/75–82, level 4
four at 70–80/83–91 and level 5 four at 75–85/91–99. The rating and the ceiling are
rolled separately inside their bands, so a batch is a spread rather than a fixed
template. Each upgrade costs a flat **95,000 Club Cash** for every rung, so climbing
from level 1 to level 5 costs 380,000 in all. The academy slips one level at the
start of every new season, so holding level 5 costs repeated reinvestment. Clubs you do not manage run academies too,
simplified to the level their seeding pot earns (pot 1 level 5, pot 2 level 4, pot 3
level 3, pot 4 and below level 1), and the teenagers they graduate each summer are
the prospects that enter the market.

**Study side.** Per-subject and per-topic aggregates weighted by marks attempted,
custom topics you create yourself, priority todos with inline `p1 #Subject - Topic:`
directives, optional due dates, streaks, and assessments that reward class rank.

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
swift run StudyManagerFC --self-test         # round-trips a career in a temp dir
swift run StudyManagerFC --verify-database   # proves the bundled DB decodes
Scripts/run.sh                              # self-test, package and relaunch in one step
swift run -c release StudyManagerFC --bench   # times the market, search, saves and lookups
Scripts/package-app.sh                      # writes dist/StudyManagerFC.app
Scripts/package-dmg.sh                      # writes dist/StudyManagerFC.dmg (drag-to-Applications image)
```

The bundle in `dist/` is a snapshot, not a live build: launching it after changing
sources shows the old UI until `Scripts/package-app.sh` is run again. `swift run`
always uses the current code.

Requires Xcode 15+ / Swift 5.9 and macOS 14 (the package targets `.macOS(.v14)`).

## Save files

The career is written to `~/Library/Application Support/StudyManagerFC/career.json`.

Saves are schema-versioned and older ones migrate on load. Every save also rotates three
backups — `career-backup-1.json` through `career-backup-3.json` in the same folder — and
**Restore last backup** in the Appearance window swaps the live career for the newest one
that still decodes.

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

## Time estimates and session planning

Every open task can carry a time budget in minutes, a question count, or both. The
dashboard's **Plan by time** sheet turns "I have 90 minutes" into an ordered list of tasks
that fit, ranked by deadline, priority and difficulty.

### Minutes per mark

A topic's difficulty is one of five levels. The level sets how long a mark is expected to
take, and the table is fixed — the app never interpolates between rows, so every estimate
can be explained.

| Level | Minutes per mark |
|-------|------------------|
| 1 | 1.5 |
| 2 | 2.0 |
| 3 | 2.3 |
| 4 | 2.8 |
| 5 | 3.0 |

A question counts as one mark: ten questions on a level-5 topic are 30 minutes. Set a
topic's level from its row in Subjects (1–5, or Auto to follow the subject). Subjects
default to Ext 2 Maths 5, Ext 1 Maths 4, Physics 4, Chemistry 4, Software Engineering 3,
English Advanced 3, Other 3. Marked history can move a topic one level either way — under
50% raises it, 85% or better lowers it — but never further.

### Overriding the table

An ETA on the task always wins. When a task has one, the difficulty table is not consulted
at all — the app takes the number you gave it, whether or not a question count is present.
Type it inline when adding a task:

- `45m`, `1h30` or `1.5h` sets the ETA
- `12q` or `12 questions` sets the count
- `p1 #Ext 2 Maths - Complex Numbers: finish 4.2 12q 45m` files it, and the ETA wins

The same two fields live in the task's edit sheet. With no ETA and no count, the planner
falls back to a level default (20/25/30/35/40 minutes for levels 1–5) and marks it rough.

### How a session is filled

1. Overdue tasks first, then due today, then by how soon they fall due.
2. Priority breaks ties (P1 worth most), and harder work is weighted up because that is
   where marks are lost.
3. Same-subject work is kept together, with a four-minute penalty for switching subject.
4. A task longer than the time left becomes a slice ("25 of 60 min") rather than being
   dropped; filling stops once fewer than 15 minutes remain.

Each row starts the focus timer on exactly that task, so the plan and the clock agree.
