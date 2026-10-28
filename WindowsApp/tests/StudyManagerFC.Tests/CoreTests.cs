using System.Text.Json;
using StudyManagerFC.Core;

namespace StudyManagerFC.Tests;

public class PricingTests
{
    [Fact]
    public void FeeGrowsSteeplyWithOverall()
    {
        Assert.Equal(250, PlayerPricing.Fee(60));
        Assert.True(PlayerPricing.Fee(80) > PlayerPricing.Fee(75));
        Assert.True(PlayerPricing.Fee(90) > PlayerPricing.Fee(85) * 1.6);
        Assert.True(PlayerPricing.Fee(94) > PlayerPricing.Fee(80) * 5);
        Assert.True(PlayerPricing.Fee(58) >= 250);
    }

    [Fact]
    public void PlayerValueUsesOverallPricing()
    {
        var player = new Player { Overall = 88 };
        Assert.Equal(PlayerPricing.Fee(88), player.MarketValue);
    }
}

public class SquadMetricsTests
{
    private static List<Player> BuildSquad(bool sharedNation)
    {
        var nations = new[] { "ENG", "ESP", "FRA", "GER", "ITA", "POR", "NED", "BEL", "UKR", "CRO", "SRB" };
        var players = new List<Player>();
        for (var index = 0; index < LineupSlot.All.Length; index++)
        {
            players.Add(new Player
            {
                Id = Guid.NewGuid(),
                Name = $"Player {index}",
                NationCode = sharedNation ? "ENG" : nations[index],
                Position = LineupSlot.All[index].Position,
                Overall = 80,
                Potential = 85,
                Age = 24
            });
        }
        return players;
    }

    [Fact]
    public void OverallIsIndependentOfChemistry()
    {
        var shared = BuildSquad(true);
        var mixed = BuildSquad(false);
        var sharedLineup = LineupSlot.All.Select((slot, index) => (slot.Id, shared[index].Id)).ToDictionary(pair => pair.Item1, pair => pair.Item2);
        var mixedLineup = LineupSlot.All.Select((slot, index) => (slot.Id, mixed[index].Id)).ToDictionary(pair => pair.Item1, pair => pair.Item2);

        var sharedMetrics = SquadMetrics.Calculate(sharedLineup, shared);
        var mixedMetrics = SquadMetrics.Calculate(mixedLineup, mixed);

        Assert.Equal(80, sharedMetrics.Overall);
        Assert.Equal(80, mixedMetrics.Overall);
        Assert.True(sharedMetrics.Chemistry > mixedMetrics.Chemistry);
        Assert.Equal(100, sharedMetrics.Chemistry);
    }

    [Fact]
    public void MissingPlayersLowerOverall()
    {
        var squad = BuildSquad(true);
        var full = LineupSlot.All.ToDictionary(slot => slot.Id, slot => squad[Array.FindIndex(LineupSlot.All, s => s.Id == slot.Id)].Id);
        var partial = full.Where(pair => pair.Key != "gk").ToDictionary(pair => pair.Key, pair => pair.Value);
        Assert.True(SquadMetrics.Calculate(partial, squad).Overall < SquadMetrics.Calculate(full, squad).Overall);
    }
}

public class MatchEngineTests
{
    private static MatchTeam Team(string clubId, int rating, string playerName)
    {
        var club = ClubDatabase.Club(clubId)!;
        var player = new Player
        {
            Name = playerName,
            Position = PlayerPosition.Striker,
            Overall = rating,
            Attributes = new PlayerAttributes(80, 85, 70, 40, 70)
        };
        return new MatchTeam(club, rating, new List<Player> { player });
    }

    [Fact]
    public void StrongerSideWinsMostMatches()
    {
        var strong = Team("real-madrid", 92, "Strong Striker");
        var weak = Team("rangers", 66, "Weak Striker");
        var strongWins = 0;
        var weakWins = 0;
        for (var index = 0; index < 300; index++)
        {
            var fixture = new Fixture
            {
                Id = Guid.NewGuid(),
                HomeClubID = strong.Club.Id,
                AwayClubID = weak.Club.Id,
                Phase = SeasonPhase.League,
                Round = 1
            };
            var result = MatchEngine.Simulate(fixture, strong, weak, 1);
            if (result.Report.HomeGoals > result.Report.AwayGoals) strongWins++;
            if (result.Report.AwayGoals > result.Report.HomeGoals) weakWins++;
            Assert.Equal(92, result.Report.HomeRating);
            Assert.Equal(66, result.Report.AwayRating);
        }
        Assert.True(strongWins > weakWins * 3, $"strong {strongWins} vs weak {weakWins}");
        Assert.True(strongWins > 180, $"strong only won {strongWins}");
    }

    [Fact]
    public void KnockoutTiesAlwaysProduceAWinner()
    {
        var home = Team("arsenal", 80, "Home Striker");
        var away = Team("chelsea", 80, "Away Striker");
        for (var index = 0; index < 100; index++)
        {
            var fixture = new Fixture
            {
                Id = Guid.NewGuid(),
                HomeClubID = home.Club.Id,
                AwayClubID = away.Club.Id,
                Phase = SeasonPhase.Final,
                Round = 1,
                NeutralVenue = true
            };
            var result = MatchEngine.Simulate(fixture, home, away, 1);
            Assert.NotNull(result.Report.WinnerClubID);
        }
    }
}

public class PlayerFactoryTests
{
    [Fact]
    public void TransferPreviewMatchesSignedPlayer()
    {
        var seed = ClubSquads.StartersFor("arsenal").First();
        var signed = PlayerFactory.TransferPlayer(seed, "arsenal", 1);
        var again = PlayerFactory.TransferPlayer(seed, "arsenal", 1);
        Assert.Equal(signed.Name, seed.Name);
        Assert.Equal(signed.Potential, again.Potential);
        Assert.Equal(signed.Overall, seed.Rating);
        Assert.True(signed.Potential >= signed.Overall);
        Assert.Equal(GameRules.RetirementAge, signed.RetirementAge);
    }

    [Fact]
    public void AcademyProspectsAreTeenagersWithCeilings()
    {
        var prospects = PlayerFactory.MakeAcademyProspects(3, GameRules.AcademyIntakePerSeason);
        Assert.Equal(GameRules.AcademyIntakePerSeason, prospects.Count);
        foreach (var prospect in prospects)
        {
            Assert.InRange(prospect.Age, 16, 18);
            Assert.InRange(prospect.Overall, 58, 68);
            Assert.True(prospect.Potential >= prospect.Overall);
            Assert.Equal(40, prospect.RetirementAge);
        }
    }

    [Fact]
    public void ExpensivePlayersAreTheStrongestListings()
    {
        var listings = new List<StarterSeed>
        {
            ClubSquads.StartersFor("real-madrid").OrderByDescending(seed => seed.Rating).First(),
            ClubSquads.StartersFor("rangers").OrderByDescending(seed => seed.Rating).First()
        };
        Assert.True(listings[0].Rating > listings[1].Rating);
        Assert.True(PlayerPricing.Fee(listings[0].Rating) > PlayerPricing.Fee(listings[1].Rating) * 3);
    }
}

public class SeasonFlowTests
{
    private static GameStore NewStore(out string directory)
    {
        directory = Path.Combine(Path.GetTempPath(), "smfc-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        return new GameStore(new PersistenceStore(directory));
    }

    private static SimulationOutcome PlayUntilSeasonEnd(GameStore store)
    {
        SimulationOutcome? last = null;
        for (var guard = 0; guard < 60; guard++)
        {
            if (store.IsSeasonComplete) break;
            if (store.State.AvailableMatchMinutes < GameRules.MinutesPerMatch)
            {
                store.LogStudy(StudyActivityKind.PastPaper, "Grind", 240, 1, StudySubject.Ext2Maths);
            }
            last = store.SimulateCurrentStage();
        }
        Assert.True(store.IsSeasonComplete, "season never completed");
        return last!;
    }

    [Fact]
    public void SeasonCompletesAndRollsOverWithIntake()
    {
        var store = NewStore(out var directory);
        try
        {
            store.StartCareer("arsenal");
            Assert.Equal(18, store.State.Players.Count);
            Assert.Equal(144, store.State.Season!.Fixtures.Count);
            Assert.True(store.LineupIsComplete);

            PlayUntilSeasonEnd(store);
            Assert.NotNull(store.State.Season!.ChampionClubID);
            Assert.Single(store.State.Trophies);

            var veteran = store.State.Players[0];
            veteran.Age = 39;
            veteran.RetirementAge = 40;
            var veteranName = veteran.Name;

            var before = store.State.Players.Select(player => player.Id).ToHashSet();
            var transition = store.StartNextSeason();

            Assert.Equal(2, transition.NewSeason);
            Assert.Contains(veteranName, transition.Retirees);
            var intake = store.State.Players.Where(player => !before.Contains(player.Id)).ToList();
            Assert.Equal(GameRules.AcademyIntakePerSeason, intake.Count);
            Assert.All(intake, player => Assert.InRange(player.Age, 16, 18));
            Assert.Equal(144, store.State.Season!.Fixtures.Count);
            Assert.Equal(1, store.State.Season!.NextLeagueRound);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void MatchUsesOverallNotChemistry()
    {
        var store = NewStore(out var directory);
        try
        {
            store.StartCareer("arsenal");
            store.LogStudy(StudyActivityKind.Homework, "Study", 200, 1);
            store.AutoPickSquad();
            var metrics = store.SquadMetrics;
            var outcome = store.SimulateCurrentStage();
            var report = outcome.UserReport!;
            var isHome = report.HomeClubID == "arsenal";
            Assert.Equal(metrics.Overall, isHome ? report.HomeRating : report.AwayRating);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void SaveUsesTheMacFileFormat()
    {
        var store = NewStore(out var directory);
        try
        {
            store.StartCareer("liverpool");
            store.LogStudy(StudyActivityKind.PastPaper, "Trial paper", 95, 1, StudySubject.Physics, 88, 100);
            store.LogStudy(StudyActivityKind.Homework, "Essay", 60, 1, StudySubject.EnglishAdvanced);
            store.SimulateCurrentStage();

            var path = Path.Combine(directory, "career.json");
            Assert.True(File.Exists(path));
            var json = File.ReadAllText(path);

            Assert.Contains("\"schemaVersion\":3", json);
            Assert.Contains("\"managedClubID\":\"liverpool\"", json);
            Assert.Contains("\"homeGoals\":", json);
            Assert.Contains("\"availableMatchMinutes\":", json);
            Assert.Contains("\"phase\":\"league\"", json);
            Assert.Matches("\"createdAt\":\"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z\"", json);
            Assert.Matches("\"playedAt\":\"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z\"", json);
            Assert.DoesNotContain("\"SchemaVersion\"", json);
            Assert.DoesNotContain("\"Football\"", json);

            var reloaded = new GameStore(new PersistenceStore(directory));
            Assert.Equal("liverpool", reloaded.State.ManagedClubID);
            Assert.Equal(store.State.ClubCash, reloaded.State.ClubCash);
            Assert.Equal(store.State.Players.Count, reloaded.State.Players.Count);
            Assert.Equal(store.State.Season!.Fixtures.Count, reloaded.State.Season!.Fixtures.Count);
            Assert.Equal(store.State.Study.TotalStudyMinutes, reloaded.State.Study.TotalStudyMinutes);
            Assert.Equal(store.ProjectedPotential(store.TransferMarket[0]), reloaded.ProjectedPotential(reloaded.TransferMarket[0]));
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void DeletingAStudyEntryKeepsEarnedCashAndPersists()
    {
        var store = NewStore(out var directory);
        try
        {
            store.StartCareer("arsenal");
            store.LogStudy(StudyActivityKind.PastPaper, "Trial paper", 95, 1, StudySubject.Physics, 80, 100);
            store.LogStudy(StudyActivityKind.Homework, "Essay", 45, 1, StudySubject.EnglishAdvanced);
            Assert.Equal(2, store.State.RecentSessions.Count);
            var cashAfterLogging = store.State.ClubCash;
            var oldest = store.State.RecentSessions[1];

            store.DeleteStudySession(oldest.Id);

            Assert.Single(store.State.RecentSessions);
            Assert.DoesNotContain(store.State.RecentSessions, session => session.Id == oldest.Id);
            // Removing an entry is a log edit, not a refund.
            Assert.Equal(cashAfterLogging, store.State.ClubCash);

            var reloaded = new GameStore(new PersistenceStore(directory));
            Assert.Single(reloaded.State.RecentSessions);
            Assert.Equal("Essay", reloaded.State.RecentSessions[0].Title);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void LegacySaveMigratesRetirementAge()
    {
        var directory = Path.Combine(Path.GetTempPath(), "smfc-legacy-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var store = new GameStore(new PersistenceStore(directory));
            store.StartCareer("celtic");
            var state = store.State.Clone();
            state.SchemaVersion = 1;
            foreach (var player in state.Players) player.RetirementAge = 36;
            File.WriteAllText(Path.Combine(directory, "career.json"), JsonSerializer.Serialize(state, SaveJson.Options));

            var migrated = new GameStore(new PersistenceStore(directory));
            Assert.Equal(3, migrated.State.SchemaVersion);
            Assert.All(migrated.State.Players, player => Assert.Equal(40, player.RetirementAge));
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }
}

public class EconomyTests
{
    private static GameStore NewStore(out string directory)
    {
        directory = Path.Combine(Path.GetTempPath(), "smfc-money-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        return new GameStore(new PersistenceStore(directory));
    }

    [Fact]
    public void FocusTimerCreditsEveryMinute()
    {
        var store = NewStore(out var directory);
        try
        {
            store.StartCareer("porto");
            var cash = store.State.ClubCash;
            var minutes = store.State.AvailableMatchMinutes;
            store.StartTimer();
            for (var tick = 0; tick < 60; tick++) store.TimerTick();
            Assert.Equal(cash + GameRules.ClubCashPerMinute, store.State.ClubCash);
            Assert.Equal(minutes + 1, store.State.AvailableMatchMinutes);
            Assert.True(store.IsTimerRunning);
            for (var tick = 0; tick < 60; tick++) store.TimerTick();
            store.PauseTimer();
            Assert.False(store.IsTimerRunning);
            Assert.Equal(2, store.LastTimerSessionMinutes);
            Assert.Equal(cash + 2 * GameRules.ClubCashPerMinute, store.State.ClubCash);
            Assert.Single(store.State.RecentSessions);
            Assert.Equal(1, store.State.Study.TotalSessions);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void EliteSigningsNeedSeriousCash()
    {
        var store = NewStore(out var directory);
        try
        {
            store.StartCareer("porto");
            var elite = store.TransferMarket.OrderByDescending(listing => listing.Seed.Rating).First();
            var eliteFee = store.TransferFee(elite);
            Assert.True(eliteFee > store.State.ClubCash * 5);
            Assert.Throws<GameException>(() => store.SignFromTransfer(elite));
            Assert.Equal(18, store.State.Players.Count);

            store.LogStudy(StudyActivityKind.PastPaper, "Save up", 2000, 1, StudySubject.Ext2Maths);
            Assert.True(store.State.ClubCash >= eliteFee);
            store.SignFromTransfer(elite);
            Assert.Equal(19, store.State.Players.Count);
            Assert.Contains(store.State.Players, player => player.Name == elite.Seed.Name);
            Assert.Equal(store.State.ClubCash + eliteFee - eliteFee, store.State.ClubCash);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void ResetClearsCareerAndStudyHistory()
    {
        var store = NewStore(out var directory);
        try
        {
            store.StartCareer("ajax");
            store.LogStudy(StudyActivityKind.Homework, "Essay", 60, 1);
            Assert.True(store.HasCareer);
            store.ResetCareer();
            Assert.False(store.HasCareer);
            Assert.Empty(store.State.Players);
            Assert.Empty(store.State.Trophies);
            Assert.Equal(0, store.State.Study.TotalStudyMinutes);
            Assert.Equal(GameRules.StartingCash, store.State.ClubCash);
            Assert.Null(store.State.Season);
            var reloaded = new GameStore(new PersistenceStore(directory));
            Assert.False(reloaded.HasCareer);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }
}

public class SubjectTrackingTests
{
    private static GameStore NewStore(out string directory)
    {
        directory = Path.Combine(Path.GetTempPath(), "smfc-topics-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var store = new GameStore(new PersistenceStore(directory));
        store.StartCareer("arsenal");
        return store;
    }

    [Fact]
    public void PastPapersPayOneAndAHalfHomework()
    {
        var homework = StudyReward.Calculate(StudyActivityKind.Homework, StudySubject.Ext1Maths, 30, null, null);
        var paper = StudyReward.Calculate(StudyActivityKind.PastPaper, StudySubject.Ext1Maths, 30, null, null);
        var questions = StudyReward.Calculate(StudyActivityKind.ExamQuestions, StudySubject.Ext1Maths, 30, null, null);

        Assert.Equal(375, homework.Cash);
        Assert.Equal(216, homework.Xp);
        Assert.Equal(563, paper.Cash);
        Assert.Equal(324, paper.Xp);
        Assert.Equal(469, questions.Cash);
        Assert.Equal(270, questions.Xp);
    }

    [Fact]
    public void MarksBecomeAPercentageThatSetsThePayout()
    {
        var zero = StudyReward.Calculate(StudyActivityKind.PastPaper, StudySubject.Ext1Maths, 30, 0, 40);
        var half = StudyReward.Calculate(StudyActivityKind.PastPaper, StudySubject.Ext1Maths, 30, 20, 40);
        var full = StudyReward.Calculate(StudyActivityKind.PastPaper, StudySubject.Ext1Maths, 30, 40, 40);

        Assert.Equal(0, zero.Ratio);
        Assert.Equal(0.5, half.Ratio);
        Assert.Equal(1, full.Ratio);
        Assert.Equal(450, zero.Cash);
        Assert.Equal(816, full.Cash);
        Assert.True(zero.Cash < half.Cash && half.Cash < full.Cash);
        Assert.Null(StudyReward.Calculate(StudyActivityKind.PastPaper, StudySubject.Ext1Maths, 30, 20, 0).Ratio);
        Assert.Equal(1, StudyReward.Calculate(StudyActivityKind.Homework, StudySubject.Ext1Maths, 30, 50, 40).Ratio);
    }

    [Fact]
    public void SubjectMultipliersStillApply()
    {
        var ext2 = StudyReward.Calculate(StudyActivityKind.Homework, StudySubject.Ext2Maths, 30, null, null);
        var ext1 = StudyReward.Calculate(StudyActivityKind.Homework, StudySubject.Ext1Maths, 30, null, null);
        var business = StudyReward.Calculate(StudyActivityKind.Homework, StudySubject.BusinessStudies, 30, null, null);

        Assert.True(ext2.Cash > ext1.Cash);
        Assert.True(business.Cash < ext1.Cash);
        Assert.Equal(1.5, StudySubject.Ext2Maths.CashMultiplier());
        Assert.Equal(0.95, StudySubject.BusinessStudies.CashMultiplier());
        Assert.Equal(1.8, StudySubject.EnglishAdvanced.XpMultiplier());
    }

    [Fact]
    public void SubtopicsTrackMarksAndTotals()
    {
        var store = NewStore(out var directory);
        try
        {
            var complex = store.AddSubtopic(" Complex Numbers ", StudySubject.Ext2Maths);
            Assert.NotNull(complex);
            Assert.Equal("Complex Numbers", complex!.Name);
            Assert.Null(store.AddSubtopic("complex numbers", StudySubject.Ext2Maths));
            Assert.Null(store.AddSubtopic("   ", StudySubject.Ext2Maths));
            var sameNameOtherSubject = store.AddSubtopic("Complex Numbers", StudySubject.Physics);
            Assert.NotNull(sameNameOtherSubject);
            var mechanics = store.AddSubtopic("Mechanics", StudySubject.Ext2Maths)!;
            Assert.Equal(2, store.SubtopicsFor(StudySubject.Ext2Maths).Count);

            store.LogStudy(StudyActivityKind.PastPaper, "", 60, 1, StudySubject.Ext2Maths, 18, 25, complex.Id);
            store.LogStudy(StudyActivityKind.Homework, "Exercise 4B", 40, 1, StudySubject.Ext2Maths, 12, 20, complex.Id);
            store.LogStudy(StudyActivityKind.ExamQuestions, "", 25, 10, StudySubject.Ext2Maths, 14, 20, mechanics.Id);

            var complexAggregate = store.AggregateForSubtopic(complex.Id);
            Assert.Equal(30, complexAggregate.MarksObtained);
            Assert.Equal(45, complexAggregate.MarksTotal);
            Assert.Equal(67, complexAggregate.AveragePercentage);
            Assert.Equal(100, complexAggregate.Minutes);
            Assert.Equal(1, complexAggregate.PastPapers);
            Assert.Equal(1, complexAggregate.Homework);

            var subjectAggregate = store.Aggregate(StudySubject.Ext2Maths);
            Assert.Equal(125, subjectAggregate.Minutes);
            Assert.Equal(65, subjectAggregate.MarksTotal);
            Assert.Equal(12, subjectAggregate.WorkCount);
            Assert.Equal(68, subjectAggregate.AveragePercentage);
            Assert.Equal(65, store.MarksAttempted);

            Assert.Equal("Complex Numbers", store.State.RecentSessions.Last().SubtopicName);
            store.DeleteSubtopic(complex.Id);
            Assert.Single(store.SubtopicsFor(StudySubject.Ext2Maths));
            Assert.Equal(65, store.Aggregate(StudySubject.Ext2Maths).MarksTotal);
            Assert.Contains(store.State.RecentSessions, session => session.SubtopicName == "Complex Numbers");
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void HistoryIsNoLongerCappedAtThirty()
    {
        var store = NewStore(out var directory);
        try
        {
            for (var index = 0; index < 40; index++)
            {
                store.LogStudy(StudyActivityKind.Homework, "", 5, 1, StudySubject.Chemistry);
            }
            Assert.Equal(40, store.State.RecentSessions.Count);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void SubtopicsAndMarksSurviveASaveReload()
    {
        var store = NewStore(out var directory);
        try
        {
            var topic = store.AddSubtopic("Projectile Motion", StudySubject.Physics)!;
            store.LogStudy(StudyActivityKind.PastPaper, "", 90, 1, StudySubject.Physics, 55, 80, topic.Id);

            var json = File.ReadAllText(Path.Combine(directory, "career.json"));
            Assert.Contains("\"subtopics\":", json);
            Assert.Contains("\"subtopicID\":", json);
            Assert.Contains("\"subtopicName\":\"Projectile Motion\"", json);
            Assert.DoesNotContain("\"percentage\":", json);

            var reloaded = new GameStore(new PersistenceStore(directory));
            Assert.Single(reloaded.State.Subtopics);
            Assert.Equal("Projectile Motion", reloaded.State.Subtopics[0].Name);
            Assert.Equal(80, reloaded.Aggregate(StudySubject.Physics).MarksTotal);
            Assert.Equal(69, reloaded.Aggregate(StudySubject.Physics).AveragePercentage);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void SavesWithoutSubtopicsStillLoad()
    {
        var directory = Path.Combine(Path.GetTempPath(), "smfc-oldtopics-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var store = new GameStore(new PersistenceStore(directory));
            store.StartCareer("celtic");
            store.LogStudy(StudyActivityKind.Homework, "Essay", 40, 1, StudySubject.EnglishAdvanced, 16, 20);

            var path = Path.Combine(directory, "career.json");
            var node = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(path))!;
            node.AsObject().Remove("subtopics");
            node["schemaVersion"] = 2;
            File.WriteAllText(path, node.ToJsonString());

            var reloaded = new GameStore(new PersistenceStore(directory));
            Assert.Equal(3, reloaded.State.SchemaVersion);
            Assert.Empty(reloaded.State.Subtopics);
            Assert.Single(reloaded.State.RecentSessions);
            Assert.Equal(20, reloaded.Aggregate(StudySubject.EnglishAdvanced).MarksTotal);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }
}
