namespace StudyManagerFC.Core;

public sealed record MatchTeam(Club Club, double Rating, IReadOnlyList<Player> Scorers);

public sealed record MatchSimulation(MatchReport Report, string? WinnerClubId);

public static class MatchEngine
{
    public static MatchSimulation Simulate(
        Fixture fixture,
        MatchTeam home,
        MatchTeam away,
        int season,
        DateTimeOffset? playedAt = null)
    {
        var phaseKey = System.Text.Json.JsonNamingPolicy.CamelCase.ConvertName(fixture.Phase.ToString());
        var generator = new SeededGenerator(
            StableSeed.Value($"{fixture.Id.ToString().ToUpperInvariant()}-{season}-{phaseKey}"));
        var homeForm = -1.2 + generator.NextDouble() * 2.4;
        var awayForm = -1.2 + generator.NextDouble() * 2.4;
        var homeBoost = fixture.NeutralVenue ? 0.0 : 2.0;
        var difference = home.Rating + homeForm - (away.Rating + awayForm) + homeBoost;

        var homeLambda = Clamp(1.35 + difference * 0.075 + 0.10, 0.25, 4.2);
        var awayLambda = Clamp(1.20 - difference * 0.065, 0.20, 3.8);

        var homeGoals = Poisson(homeLambda, ref generator);
        var awayGoals = Poisson(awayLambda, ref generator);
        var events = new List<MatchEvent>();
        AppendGoals(homeGoals, home.Club, home, 1, 90, ref generator, events);
        AppendGoals(awayGoals, away.Club, away, 1, 90, ref generator, events);

        int? homePenalties = null;
        int? awayPenalties = null;

        if (fixture.Phase != SeasonPhase.League)
        {
            if (homeGoals == awayGoals)
            {
                var extraHome = Poisson(homeLambda * 0.33, ref generator);
                var extraAway = Poisson(awayLambda * 0.33, ref generator);
                homeGoals += extraHome;
                awayGoals += extraAway;
                AppendGoals(extraHome, home.Club, home, 91, 120, ref generator, events);
                AppendGoals(extraAway, away.Club, away, 91, 120, ref generator, events);

                if (homeGoals == awayGoals)
                {
                    var (shootoutHome, shootoutAway) = PenaltyShootout(home.Rating, away.Rating, ref generator);
                    homePenalties = shootoutHome;
                    awayPenalties = shootoutAway;
                }
            }
        }

        events.Sort((left, right) => left.Minute.CompareTo(right.Minute));
        var summary = MakeSummary(
            home.Club, away.Club, homeGoals, awayGoals, homePenalties, awayPenalties, events, fixture.NeutralVenue);

        var report = new MatchReport
        {
            Id = Guid.NewGuid(),
            FixtureID = fixture.Id,
            Phase = fixture.Phase,
            Round = fixture.Round,
            HomeClubID = home.Club.Id,
            AwayClubID = away.Club.Id,
            HomeGoals = homeGoals,
            AwayGoals = awayGoals,
            HomePenalties = homePenalties,
            AwayPenalties = awayPenalties,
            Events = events,
            HomeRating = (int)Math.Round(home.Rating, MidpointRounding.AwayFromZero),
            AwayRating = (int)Math.Round(away.Rating, MidpointRounding.AwayFromZero),
            Summary = summary,
            PlayedAt = playedAt ?? DateTimeOffset.UtcNow
        };
        return new MatchSimulation(report, report.WinnerClubID);
    }

    public static List<Player> UserMetricsLineup(IReadOnlyList<Player> players, Dictionary<string, Guid> lineup)
    {
        var result = new List<Player>();
        foreach (var slot in LineupSlot.All)
        {
            if (!lineup.TryGetValue(slot.Id, out var id)) continue;
            var player = players.FirstOrDefault(candidate => candidate.Id == id);
            if (player is not null) result.Add(player);
        }
        return result;
    }

    private static void AppendGoals(
        int count,
        Club club,
        MatchTeam team,
        int minuteMin,
        int minuteMax,
        ref SeededGenerator generator,
        List<MatchEvent> events)
    {
        for (var index = 0; index < count; index++)
        {
            var minute = generator.NextInt(minuteMin, minuteMax);
            var scorer = SelectScorer(team, club, ref generator);
            var isPenalty = generator.NextInt(0, 99) < 8;
            events.Add(new MatchEvent
            {
                Id = Guid.NewGuid(),
                Minute = minute,
                ClubID = club.Id,
                Scorer = scorer,
                IsPenalty = isPenalty
            });
        }
    }

    private static string SelectScorer(MatchTeam team, Club club, ref SeededGenerator generator)
    {
        if (team.Scorers.Count == 0)
        {
            string[] fallbackPositions = ["Forward", "Midfielder", "Winger"];
            return $"{club.ShortName} {generator.Pick(fallbackPositions)}";
        }

        var weighted = team.Scorers
            .Select(player => (Player: player, Weight: player.Position.ScoringWeight() * (0.55 + player.Attributes.Shooting / 100.0)))
            .ToList();
        var total = weighted.Sum(entry => entry.Weight);
        var roll = generator.NextDouble() * total;
        foreach (var (player, weight) in weighted)
        {
            if (roll < weight) return player.Name;
            roll -= weight;
        }
        return weighted[^1].Player.Name;
    }

    private static (int Home, int Away) PenaltyShootout(double homeRating, double awayRating, ref SeededGenerator generator)
    {
        var homeChance = Clamp(0.73 + (homeRating - awayRating) * 0.006, 0.56, 0.91);
        var awayChance = Clamp(0.73 + (awayRating - homeRating) * 0.006, 0.56, 0.91);
        var home = 0;
        var away = 0;
        for (var index = 0; index < 5; index++)
        {
            if (generator.NextDouble() < homeChance) home++;
            if (generator.NextDouble() < awayChance) away++;
        }
        while (home == away)
        {
            var homeScored = generator.NextDouble() < homeChance;
            var awayScored = generator.NextDouble() < awayChance;
            if (homeScored) home++;
            if (awayScored) away++;
        }
        return (home, away);
    }

    private static int Poisson(double lambda, ref SeededGenerator generator)
    {
        var limit = Math.Exp(-Math.Max(0.01, lambda));
        var product = 1.0;
        var count = 0;
        do
        {
            count++;
            product *= generator.NextDouble();
        } while (product > limit && count < 12);
        return count - 1;
    }

    private static string MakeSummary(
        Club home,
        Club away,
        int homeGoals,
        int awayGoals,
        int? homePenalties,
        int? awayPenalties,
        List<MatchEvent> events,
        bool neutral)
    {
        var venue = neutral ? "in the final" : $"at {home.Name}";
        var counts = new Dictionary<string, int>();
        foreach (var matchEvent in events)
        {
            counts[matchEvent.Scorer] = counts.GetValueOrDefault(matchEvent.Scorer) + 1;
        }
        var topScorerLine = counts.Count > 0 && counts.Max(entry => entry.Value) > 1
            ? $" {counts.OrderByDescending(entry => entry.Value).First().Key} scored {counts.Max(entry => entry.Value)}."
            : "";

        if (homeGoals == awayGoals && homePenalties is null)
        {
            return $"{home.Name} and {away.Name} played out a {homeGoals}-{awayGoals} draw {venue}.{topScorerLine}";
        }

        Club winner;
        int winnerGoals;
        int loserGoals;
        if (homeGoals > awayGoals)
        {
            winner = home;
            winnerGoals = homeGoals;
            loserGoals = awayGoals;
        }
        else if (awayGoals > homeGoals)
        {
            winner = away;
            winnerGoals = awayGoals;
            loserGoals = homeGoals;
        }
        else if (homePenalties.HasValue && awayPenalties.HasValue)
        {
            if (homePenalties > awayPenalties)
            {
                winner = home;
                winnerGoals = homeGoals;
                loserGoals = awayGoals;
            }
            else
            {
                winner = away;
                winnerGoals = awayGoals;
                loserGoals = homeGoals;
            }
        }
        else
        {
            return $"{home.Name} and {away.Name} finished level.";
        }

        var loser = winner.Id == home.Id ? away : home;
        var sentence = $"{winner.Name} beat {loser.Name} {winnerGoals}-{loserGoals} {venue}.";
        if (homePenalties.HasValue && awayPenalties.HasValue)
        {
            sentence += $" The tie was decided {Math.Max(homePenalties.Value, awayPenalties.Value)}-{Math.Min(homePenalties.Value, awayPenalties.Value)} on penalties.";
        }
        return sentence + topScorerLine;
    }

    private static double Clamp(double value, double lower, double upper) => Math.Min(upper, Math.Max(lower, value));
}

public static class ScheduleEngine
{
    private sealed record PotPairing(int FirstPot, int SecondPot, int HomePot);

    private static readonly PotPairing[][] RoundPlan =
    [
        [new(0, 1, 0), new(2, 3, 2)],
        [new(0, 2, 0), new(1, 3, 1)],
        [new(0, 3, 3), new(1, 2, 2)],
        [new(0, 1, 1), new(2, 3, 3)],
        [new(0, 2, 0), new(1, 3, 1)],
        [new(0, 3, 3), new(1, 2, 2)],
        [new(0, 2, 2), new(1, 3, 3)],
        [new(0, 3, 0), new(1, 2, 1)]
    ];

    public static List<Fixture> MakeLeagueFixtures(int season)
    {
        var generator = new SeededGenerator(StableSeed.Value($"schedule-{season}"));
        var pots = ClubDatabase.SeededPots.Select(pot => pot.ToList()).ToList();
        foreach (var pot in pots)
        {
            Shuffle(pot, ref generator);
        }

        var fixtures = new List<Fixture>();
        for (var roundIndex = 0; roundIndex < RoundPlan.Length; roundIndex++)
        {
            var pairings = RoundPlan[roundIndex];
            for (var pairIndex = 0; pairIndex < pairings.Length; pairIndex++)
            {
                var pairing = pairings[pairIndex];
                var firstPot = pots[pairing.FirstPot];
                var secondPot = pots[pairing.SecondPot];
                var shift = (season + roundIndex * 2 + pairIndex * 3) % 9;
                for (var index = 0; index < 9; index++)
                {
                    var firstClub = firstPot[index];
                    var secondClub = secondPot[(index + shift) % 9];
                    Club home;
                    Club away;
                    if (pairing.HomePot == pairing.FirstPot)
                    {
                        home = firstClub;
                        away = secondClub;
                    }
                    else
                    {
                        home = secondClub;
                        away = firstClub;
                    }
                    fixtures.Add(new Fixture
                    {
                        Id = Guid.NewGuid(),
                        HomeClubID = home.Id,
                        AwayClubID = away.Id,
                        Phase = SeasonPhase.League,
                        Round = roundIndex + 1
                    });
                }
            }

            var tail = fixtures.Skip(fixtures.Count - 18).ToList();
            var shuffled = tail.OrderBy(_ => 0).ToList();
            Shuffle(shuffled, ref generator);
            for (var index = 0; index < shuffled.Count; index++)
            {
                fixtures[fixtures.Count - 18 + index] = shuffled[index];
            }
        }
        return fixtures;
    }

    public static List<Fixture> MakePlayoffFixtures(IReadOnlyList<StandingRow> standings)
    {
        if (standings.Count != 36) return [];
        var fixtures = new List<Fixture>();
        for (var index = 0; index < 8; index++)
        {
            var higher = standings[8 + index];
            var lower = standings[23 - index];
            fixtures.Add(new Fixture
            {
                Id = Guid.NewGuid(),
                HomeClubID = higher.Club.Id,
                AwayClubID = lower.Club.Id,
                Phase = SeasonPhase.Playoffs,
                Round = 1
            });
        }
        return fixtures;
    }

    public static List<Fixture> MakeRoundOf16(IReadOnlyList<StandingRow> standings, IReadOnlyList<Fixture> playoffFixtures)
    {
        if (standings.Count != 36 || playoffFixtures.Count != 8) return [];
        var rankById = new Dictionary<string, int>();
        for (var index = 0; index < standings.Count; index++)
        {
            rankById[standings[index].Club.Id] = index;
        }
        var winners = playoffFixtures
            .Select(fixture => fixture.WinnerClubID)
            .Where(id => id is not null)
            .Cast<string>()
            .OrderBy(id => rankById.GetValueOrDefault(id, 99))
            .ToList();
        if (winners.Count != 8) return [];

        var fixtures = new List<Fixture>();
        for (var index = 0; index < 8; index++)
        {
            var home = standings[index].Club;
            var away = ClubDatabase.Club(winners[7 - index]);
            if (away is null) continue;
            fixtures.Add(new Fixture
            {
                Id = Guid.NewGuid(),
                HomeClubID = home.Id,
                AwayClubID = away.Id,
                Phase = SeasonPhase.RoundOf16,
                Round = 1
            });
        }
        return fixtures;
    }

    public static List<Fixture> MakeNextKnockoutRound(
        IReadOnlyList<Fixture> previousFixtures,
        SeasonPhase phase,
        IReadOnlyList<StandingRow> standings)
    {
        var winners = previousFixtures
            .Select(fixture => fixture.WinnerClubID)
            .Where(id => id is not null)
            .Cast<string>()
            .ToList();
        if (winners.Count != previousFixtures.Count || winners.Count < 2) return [];

        var rankById = new Dictionary<string, int>();
        for (var index = 0; index < standings.Count; index++)
        {
            rankById[standings[index].Club.Id] = index;
        }

        var fixtures = new List<Fixture>();
        var cursor = 0;
        while (cursor + 1 < winners.Count)
        {
            var firstId = winners[cursor];
            var secondId = winners[cursor + 1];
            var firstRank = rankById.GetValueOrDefault(firstId, 99);
            var secondRank = rankById.GetValueOrDefault(secondId, 99);
            fixtures.Add(new Fixture
            {
                Id = Guid.NewGuid(),
                HomeClubID = firstRank <= secondRank ? firstId : secondId,
                AwayClubID = firstRank <= secondRank ? secondId : firstId,
                Phase = phase,
                Round = 1,
                NeutralVenue = phase == SeasonPhase.Final
            });
            cursor += 2;
        }
        return fixtures;
    }

    private static void Shuffle<T>(IList<T> items, ref SeededGenerator generator)
    {
        for (var index = items.Count - 1; index > 0; index--)
        {
            var swap = generator.NextInt(0, index);
            (items[index], items[swap]) = (items[swap], items[index]);
        }
    }
}

public static class StandingsEngine
{
    public static List<StandingRow> Standings(IReadOnlyList<Fixture> fixtures)
    {
        var rows = new Dictionary<string, StandingRow>();
        foreach (var club in ClubDatabase.All)
        {
            rows[club.Id] = new StandingRow(club, 0, 0, 0, 0, 0, 0, 0);
        }

        foreach (var fixture in fixtures)
        {
            if (fixture.Phase != SeasonPhase.League || !fixture.IsSimulated) continue;
            var homeGoals = fixture.HomeGoals!.Value;
            var awayGoals = fixture.AwayGoals!.Value;
            if (!rows.TryGetValue(fixture.HomeClubID, out var home)) continue;
            if (!rows.TryGetValue(fixture.AwayClubID, out var away)) continue;

            var played = home.Played + 1;
            var awayPlayed = away.Played + 1;
            var homeFor = home.GoalsFor + homeGoals;
            var homeAgainst = home.GoalsAgainst + awayGoals;
            var awayFor = away.GoalsFor + awayGoals;
            var awayAgainst = away.GoalsAgainst + homeGoals;

            if (homeGoals > awayGoals)
            {
                rows[fixture.HomeClubID] = home.With(played, home.Won + 1, home.Drawn, home.Lost, homeFor, homeAgainst, home.Points + 3);
                rows[fixture.AwayClubID] = away.With(awayPlayed, away.Won, away.Drawn, away.Lost + 1, awayFor, awayAgainst, away.Points);
            }
            else if (awayGoals > homeGoals)
            {
                rows[fixture.HomeClubID] = home.With(played, home.Won, home.Drawn, home.Lost + 1, homeFor, homeAgainst, home.Points);
                rows[fixture.AwayClubID] = away.With(awayPlayed, away.Won + 1, away.Drawn, away.Lost, awayFor, awayAgainst, away.Points + 3);
            }
            else
            {
                rows[fixture.HomeClubID] = home.With(played, home.Won, home.Drawn + 1, home.Lost, homeFor, homeAgainst, home.Points + 1);
                rows[fixture.AwayClubID] = away.With(awayPlayed, away.Won, away.Drawn + 1, away.Lost, awayFor, awayAgainst, away.Points + 1);
            }
        }

        return rows.Values
            .OrderByDescending(row => row.Points)
            .ThenByDescending(row => row.GoalDifference)
            .ThenByDescending(row => row.GoalsFor)
            .ThenByDescending(row => row.Won)
            .ThenBy(row => row.Club.Name, StringComparer.Ordinal)
            .ToList();
    }

    public static int Position(string clubId, IReadOnlyList<StandingRow> standings)
    {
        for (var index = 0; index < standings.Count; index++)
        {
            if (standings[index].Club.Id == clubId) return index + 1;
        }
        return 36;
    }
}

public static class SeasonEngine
{
    public static SeasonState NewSeason(int number)
    {
        var season = SeasonState.New(number);
        season.Fixtures = ScheduleEngine.MakeLeagueFixtures(number);
        return season;
    }

    public static SeasonPhase NextPhase(SeasonPhase phase) => phase switch
    {
        SeasonPhase.League => SeasonPhase.Playoffs,
        SeasonPhase.Playoffs => SeasonPhase.RoundOf16,
        SeasonPhase.RoundOf16 => SeasonPhase.Quarterfinal,
        SeasonPhase.Quarterfinal => SeasonPhase.Semifinal,
        SeasonPhase.Semifinal => SeasonPhase.Final,
        _ => SeasonPhase.Complete
    };

    public static string UserFinish(
        string userClubId,
        IReadOnlyList<StandingRow> standings,
        IReadOnlyList<Fixture> fixtures,
        string? championClubId)
    {
        if (championClubId == userClubId) return "Champions";
        if (fixtures.Any(f => f.Phase == SeasonPhase.Final && (f.HomeClubID == userClubId || f.AwayClubID == userClubId) && f.IsSimulated))
            return "Runners-up";
        if (fixtures.Any(f => f.Phase == SeasonPhase.Semifinal && (f.HomeClubID == userClubId || f.AwayClubID == userClubId)))
            return "Semi-finalists";
        if (fixtures.Any(f => f.Phase == SeasonPhase.Quarterfinal && (f.HomeClubID == userClubId || f.AwayClubID == userClubId)))
            return "Quarter-finalists";
        if (fixtures.Any(f => f.Phase == SeasonPhase.RoundOf16 && (f.HomeClubID == userClubId || f.AwayClubID == userClubId)))
            return "Round of 16";
        if (fixtures.Any(f => f.Phase == SeasonPhase.Playoffs && (f.HomeClubID == userClubId || f.AwayClubID == userClubId)))
            return "Knockout playoff";
        var rank = StandingsEngine.Position(userClubId, standings);
        return $"League phase — {Ordinal(rank)}";
    }

    public static TrophyRecord? MakeTrophyRecord(SeasonState season, Club userClub, IReadOnlyList<StandingRow> standings)
    {
        var champion = ClubDatabase.Club(season.ChampionClubID);
        var runnerUp = ClubDatabase.Club(season.RunnerUpClubID);
        if (champion is null || runnerUp is null) return null;

        var finish = UserFinish(userClub.Id, standings, season.Fixtures, season.ChampionClubID);
        return new TrophyRecord
        {
            Id = Guid.NewGuid(),
            SeasonNumber = season.Number,
            ChampionClubID = champion.Id,
            ChampionName = champion.Name,
            RunnerUpClubID = runnerUp.Id,
            RunnerUpName = runnerUp.Name,
            UserClubID = userClub.Id,
            UserClubName = userClub.Name,
            UserFinish = finish,
            UserWasChampion = champion.Id == userClub.Id,
            CompletedAt = DateTimeOffset.UtcNow
        };
    }

    public static string Ordinal(int value)
    {
        var suffix = value % 100 is >= 11 and <= 13
            ? "th"
            : (value % 10) switch
            {
                1 => "st",
                2 => "nd",
                3 => "rd",
                _ => "th"
            };
        return $"{value}{suffix}";
    }
}

public static class ClubDatabaseExtensions
{
    public static int PotNumber(string clubId)
    {
        var pots = ClubDatabase.SeededPots;
        for (var index = 0; index < pots.Length; index++)
        {
            if (pots[index].Any(club => club.Id == clubId)) return index + 1;
        }
        return 4;
    }
}
