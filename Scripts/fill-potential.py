#!/usr/bin/env python3
"""Fill real EA potentials into `fc-database.json`.

Why this exists
---------------
`fc-database.json` is built from the FC 26 ratings export (`Fifa names and ovrs/`),
which carries no potential column, so every row was written with `pot` equal to `ovr`.
That makes the data claim every player is already at their ceiling.

The game's own database (`db_loc_27/data/db/fifa_ng_db.db`) does carry a `potential`
field, but its `playerid` values sit exactly one above the ratings export's IDs. The
offset is verified rather than assumed: joining `csv_id + 1` matches 12,088 of 12,097
birthdates and 11,901 nationalities, so the joined row is provably the same person
even though the two snapshots disagree on ratings by a point or two.

Rows with a verified twin take the real EA ceiling. Rows added in a later title update
have no twin, so they fall back to the same age-band ceiling the app uses for players
whose data carries none, seeded by player id so the value never changes between runs.

Usage:
    python3 Scripts/fill-potential.py            # rewrites the checked-in data file
    python3 Scripts/fill-potential.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import sys
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXTRACT = ROOT / "Scripts" / "extract-fc-database.py"
DEFAULT_DB = ROOT / "db_loc_27" / "data" / "db" / "fifa_ng_db.db"
DEFAULT_CSV = ROOT / "Fifa names and ovrs" / "EAFC26-Men.csv"
DEFAULT_FILE = ROOT / "Sources" / "StudyManagerFC" / "Resources" / "fc-database.json"

# The game database's player ids are one above the ratings export's.
ID_OFFSET = 1

# Age bands shared with PlayerFactory.potentialBoost, so a synthesised ceiling never
# promises more growth than the app's own model would.
AGE_BANDS = ((18, 10, 20), (21, 6, 14), (24, 2, 8), (28, 0, 4))


def load_extractor():
    spec = importlib.util.spec_from_file_location("extract_fc_database", EXTRACT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def synthesised_potential(overall: int, age: int, player_id: int) -> int:
    """Deterministic ceiling for a row with no twin, drawn from its id."""
    digest = hashlib.sha256(f"fc-pot-{player_id}".encode()).digest()
    roll = digest[0] / 255
    low, high = 0, 1
    for limit, band_low, band_high in AGE_BANDS:
        if age <= limit:
            low, high = band_low, band_high
            break
    boost = low + int(round(roll * (high - low)))
    return min(99, overall + boost)


def read_ratings(path: Path) -> dict[int, dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return {int(row["ID"]): row for row in csv.DictReader(handle)}


def read_database(path: Path) -> dict[int, dict[str, object]]:
    ex = load_extractor()
    db = ex.Database(path)
    players = db.read("players")
    nations = {
        ex.value(row, "nationid"): ex.text(row, "nationname")
        for row in db.read("nations").rows
    }
    rows: dict[int, dict[str, object]] = {}
    for row in players.rows:
        born = ex.DATE_EPOCH + timedelta(days=ex.value(row, "birthdate"))
        rows[ex.value(row, "playerid")] = {
            "overall": ex.value(row, "overallrating"),
            "potential": ex.value(row, "potential"),
            "born": born,
            "nation": nations.get(ex.value(row, "nationality"), ""),
        }
    return rows


def age_on(born: date, today: date) -> int:
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", default=str(DEFAULT_FILE))
    parser.add_argument("--database", default=str(DEFAULT_DB))
    parser.add_argument("--csv", default=str(DEFAULT_CSV))
    parser.add_argument("--today", default="2026-10-25", help="the date the ratings export was taken")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    today = date.fromisoformat(args.today)
    ratings = read_ratings(Path(args.csv))
    database = read_database(Path(args.database))
    data = json.loads(Path(args.file).read_text())

    matched = rejected = synthesised = 0
    for player in data["players"]:
        player_id = player["id"]
        overall = player["ovr"]
        csv_row = ratings.get(player_id)
        twin = database.get(player_id + ID_OFFSET)
        potential: int | None = None

        if twin is not None and csv_row is not None:
            # Identity is only trusted when age and nationality both agree; the two
            # snapshots differ by a title update, so ratings alone are not proof.
            twin_age = age_on(twin["born"], today)  # type: ignore[arg-type]
            age_agrees = abs(twin_age - int(csv_row["Age"])) <= 1
            nation_agrees = str(twin["nation"]).lower() == csv_row["Nation"].strip().lower()
            if age_agrees and nation_agrees:
                potential = max(overall, int(twin["potential"]))  # type: ignore[arg-type]
                matched += 1
            else:
                rejected += 1

        if potential is None:
            potential = synthesised_potential(overall, player["age"], player_id)
            synthesised += 1

        player["pot"] = min(99, potential)

    growth = sum(1 for player in data["players"] if player["pot"] > player["ovr"])
    print(f"players {len(data['players'])}: real EA potential {matched}, "
          f"synthesised {synthesised} (rejected joins {rejected})")
    print(f"players with room to grow {growth} "
          f"({growth / max(1, len(data['players'])) * 100:.1f}%)")
    if args.dry_run:
        print("dry run — nothing written")
        return 0

    out = Path(args.file)
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {out} ({out.stat().st_size / 1_048_576:.2f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
