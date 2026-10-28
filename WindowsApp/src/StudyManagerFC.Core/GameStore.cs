namespace StudyManagerFC.Core;

public sealed class GameException(string message) : Exception(message);

public sealed record SimulationOutcome(
    MatchReport? UserReport,
    int SimulatedCount,
    SeasonPhase PhasePlayed,
    Club? ChampionClub,
    TrophyRecord? Trophy);

public sealed record TransferListing(string Id, StarterSeed Seed, string ClubId, Club? Club);

public sealed class GameStore
{
    private readonly PersistenceStore _persistence;

    public GameState State { get; private set; }
    public bool IsTimerRunning { get; private set; }
    public int TimerElapsedSeconds { get; private set; }
    public string? SaveErrorMessage { get; private set; }
    public int LastTimerSessionMinutes { get; private set; }
    public string StoragePath => _persistence.SavePath;

    private int _timerCreditedMinutes;

    /// <summary>Raised after every committed change so views can refresh.</summary>
    public event Action? Changed;

    public GameStore(PersistenceStore? persistence = null)
    {
        _persistence = persistence ?? new PersistenceStore();
        try
        {
            State = _persistence.Load() ?? GameState.Fresh();
        }
        catch (Exception)
        {
            State = GameState.Fresh();
            SaveErrorMessage = "The previous save could not be read. A fresh career was created and the old file was preserved.";
        }
        MigrateLegacySaveIfNeeded();
    }

    /// <summary>
    /// Saves written before the 40-year retirement rule carry per-player retirement ages
    /// of 35-38, so lift every existing player to the current rule. Saves written before
    /// subtopics existed simply start with none.
    /// </summary>
    private void MigrateLegacySaveIfNeeded()
    {
        if (State.SchemaVersion >= GameState.CurrentSchemaVersion || State.ManagedClubID is null) return;
        var draft = State.Clone();
        if (draft.SchemaVersion < 2)
        {
            foreach (var player in draft.Players) player.RetirementAge = GameRules.RetirementAge;
            foreach (var player in draft.FreeAgents) player.RetirementAge = GameRules.RetirementAge;
        }
        draft.SchemaVersion = GameState.CurrentSchemaVersion;
        Commit(draft);
    }

    public bool HasCareer => State.ManagedClubID is not null;

    public Club? ManagedClub => ClubDatabase.Club(State.ManagedClubID);

    public int Level => 1 + State.Xp / GameRules.XpPerLevel;

    public int XpIntoLevel => State.Xp % GameRules.XpPerLevel;

    public double LevelProgress => XpIntoLevel / (double)GameRules.XpPerLevel;

    public int MinutesUntilMatch => Math.Max(0, GameRules.MinutesPerMatch - State.AvailableMatchMinutes);

    public double MatchReadiness => Math.Min(1.0, State.AvailableMatchMinutes / (double)GameRules.MinutesPerMatch);

    public bool LineupIsComplete => LineupSlot.All.All(slot => State.Lineup.ContainsKey(slot.Id));

    public SquadMetrics SquadMetrics => SquadMetrics.Calculate(State.Lineup, State.Players);

    public List<Player> UserStartingPlayers => MatchEngine.UserMetricsLineup(State.Players, State.Lineup);

    public List<Player> BenchPlayers => State.Bench
        .Select(id => State.Players.FirstOrDefault(player => player.Id == id))
        .Where(player => player is not null)
        .Cast<Player>()
        .ToList();

    public Dictionary<string, Player> LineupPlayersBySlot
    {
        get
        {
            var result = new Dictionary<string, Player>();
            foreach (var slot in LineupSlot.All)
            {
                if (!State.Lineup.TryGetValue(slot.Id, out var id)) continue;
                var player = State.Players.FirstOrDefault(candidate => candidate.Id == id);
                if (player is not null) result[slot.Id] = player;
            }
            return result;
        }
    }

    public SeasonState? Season => State.Season;

    public List<StandingRow> Standings => State.Season is null
        ? []
        : StandingsEngine.Standings(State.Season.Fixtures);

    public int UserLeaguePosition => ManagedClub is null ? 0 : StandingsEngine.Position(ManagedClub.Id, Standings);

    public List<Fixture> CurrentFixtures => State.Season?.CurrentFixtures ?? [];

    public Fixture? UserCurrentFixture
    {
        get
        {
            var userId = State.ManagedClubID;
            if (userId is null) return null;
            return CurrentFixtures.FirstOrDefault(fixture => fixture.HomeClubID == userId || fixture.AwayClubID == userId);
        }
    }

    public Fixture? NextFixtureForUser
    {
        get
        {
            var current = UserCurrentFixture;
            if (current is not null) return current;
            if (State.Season is null || State.ManagedClubID is null) return null;
            var userId = State.ManagedClubID;
            return State.Season.Fixtures
                .Where(fixture => !fixture.IsSimulated && (fixture.HomeClubID == userId || fixture.AwayClubID == userId))
                .OrderBy(fixture => PhaseOrder(fixture.Phase))
                .ThenBy(fixture => fixture.Round)
                .FirstOrDefault();
        }
    }

    public bool CanSimulateCurrentStage
    {
        get
        {
            if (State.Season is null || State.Season.Phase == SeasonPhase.Complete) return false;
            if (CurrentFixtures.Count == 0) return false;
            if (UserCurrentFixture is not null)
            {
                return LineupIsComplete && State.AvailableMatchMinutes >= GameRules.MinutesPerMatch;
            }
            return true;
        }
    }

    public bool IsSeasonComplete => State.Season?.Phase == SeasonPhase.Complete;

    public Club? ChampionClub => ClubDatabase.Club(State.Season?.ChampionClubID);

    public List<MatchReport> LatestReports =>
        (State.Season?.Reports ?? []).OrderByDescending(report => report.PlayedAt).ToList();

    public MatchReport? LastReportForUser
    {
        get
        {
            if (State.ManagedClubID is null) return null;
            return LatestReports.FirstOrDefault(report =>
                report.HomeClubID == State.ManagedClubID || report.AwayClubID == State.ManagedClubID);
        }
    }

    public List<TrophyRecord> Trophies => State.Trophies.OrderByDescending(trophy => trophy.SeasonNumber).ToList();

    public int UserTitles => State.Trophies.Count(trophy => trophy.UserWasChampion);

    public int CompletedSeasons => State.Trophies.Count;

    public List<Player> TopProspects => State.FreeAgents
        .Where(player => player.Rarity == PlayerRarity.Wonderkid)
        .OrderByDescending(player => player.Potential)
        .Take(4)
        .ToList();

    public string UserTournamentStatus
    {
        get
        {
            if (State.Season is null) return "No active season";
            var season = State.Season;
            if (season.Phase == SeasonPhase.Complete)
            {
                return season.ChampionClubID == State.ManagedClubID ? "Champions of Europe" : FinalUserFinish;
            }
            if (season.Phase == SeasonPhase.League)
            {
                var fixture = UserCurrentFixture;
                if (fixture is null || ManagedClub is null) return "League phase";
                var opponentId = fixture.HomeClubID == ManagedClub.Id ? fixture.AwayClubID : fixture.HomeClubID;
                var opponent = ClubDatabase.Club(opponentId)?.ShortName ?? "Opponent";
                return fixture.HomeClubID == ManagedClub.Id ? $"Next: vs {opponent}" : $"Next: away at {opponent}";
            }
            if (UserCurrentFixture is not null) return $"{season.Phase.DisplayName()} fixture ready";
            if (season.Phase == SeasonPhase.Playoffs && UserLeaguePosition <= 8)
            {
                return "Directly qualified for the Round of 16";
            }
            return $"Spectating the {season.Phase.DisplayName()}";
        }
    }

    public string FinalUserFinish
    {
        get
        {
            if (State.Season is null || ManagedClub is null) return "—";
            return SeasonEngine.UserFinish(
                ManagedClub.Id, Standings, State.Season.Fixtures, State.Season.ChampionClubID);
        }
    }

    public string StageButtonLabel
    {
        get
        {
            if (State.Season is null) return "No Season";
            if (State.Season.Phase == SeasonPhase.Complete) return "Season Complete";
            if (State.Season.Phase == SeasonPhase.League) return $"Simulate Matchday {State.Season.NextLeagueRound}";
            return $"Simulate {State.Season.Phase.DisplayName()}";
        }
    }

    public Player? PlayerFor(Guid id) => State.Players.FirstOrDefault(player => player.Id == id);

    public List<TransferListing> TransferMarket
    {
        get
        {
            var userClubId = State.ManagedClubID;
            if (userClubId is null) return [];
            var listings = new List<TransferListing>();
            foreach (var entry in ClubSquads.All.OrderBy(pair => pair.Key, StringComparer.Ordinal))
            {
                if (entry.Key == userClubId) continue;
                foreach (var seed in entry.Value)
                {
                    listings.Add(new TransferListing(
                        $"{entry.Key}:{seed.Name}:{seed.Position}",
                        seed,
                        entry.Key,
                        ClubDatabase.Club(entry.Key)));
                }
            }
            return listings
                .OrderByDescending(listing => listing.Seed.Rating)
                .ThenBy(listing => listing.Club?.Name ?? "", StringComparer.Ordinal)
                .ThenBy(listing => listing.Seed.Name, StringComparer.Ordinal)
                .ToList();
        }
    }

    public int TransferFee(TransferListing listing) => PlayerPricing.Fee(listing.Seed.Rating);

    /// <summary>The potential a listing would have after signing, so the market can show it up front.</summary>
    public int ProjectedPotential(TransferListing listing) =>
        PlayerFactory.TransferPlayer(listing.Seed, listing.ClubId, State.SeasonNumber).Potential;

    public void SignFromTransfer(TransferListing listing)
    {
        if (!HasCareer) throw new GameException("Choose a club before starting.");
        if (listing.ClubId == State.ManagedClubID) throw new GameException("That club is not in the competition.");
        if (State.Players.Any(player => player.Name == listing.Seed.Name && player.Position == listing.Seed.Position))
        {
            throw new GameException("That player is already in your squad.");
        }

        var fee = TransferFee(listing);
        if (State.ClubCash < fee) throw new GameException("You do not have enough Club Cash.");

        var player = PlayerFactory.TransferPlayer(listing.Seed, listing.ClubId, State.SeasonNumber);
        var draft = State.Clone();
        draft.ClubCash -= fee;
        draft.Players.Add(player);
        if (draft.Bench.Count < GameRules.BenchLimit) draft.Bench.Add(player.Id);
        Commit(draft);
    }

    public void StartCareer(string clubId)
    {
        if (State.ManagedClubID is not null) throw new GameException("The season could not advance.");
        var club = ClubDatabase.Club(clubId) ?? throw new GameException("That club is not in the competition.");
        var draft = State.Clone();
        var squad = PlayerFactory.StarterSquad(club, draft.SeasonNumber);
        var (lineup, bench) = PlayerFactory.AutoLineup(squad);
        draft.SchemaVersion = GameState.CurrentSchemaVersion;
        draft.ManagedClubID = club.Id;
        draft.Players = squad;
        draft.FreeAgents = PlayerFactory.MakeFreeAgentPool(draft.SeasonNumber, GameRules.FreeAgentPoolTarget);
        draft.Lineup = lineup;
        draft.Bench = bench;
        draft.Season = SeasonEngine.NewSeason(draft.SeasonNumber);
        draft.LastTransition = null;
        Commit(draft);
    }

    public void LogStudy(
        StudyActivityKind kind,
        string title,
        int minutes,
        int quantity,
        StudySubject subject = StudySubject.Other,
        int? marksObtained = null,
        int? marksTotal = null,
        Guid? subtopicId = null)
    {
        if (minutes <= 0) return;
        var safeQuantity = Math.Max(1, quantity);

        // Marks are entered as gained over attempted. Anything that does not form a
        // usable fraction is treated as unmarked work.
        int? resolvedObtained = null;
        int? resolvedTotal = null;
        if (kind.SupportsMarking() && marksObtained.HasValue && marksTotal is > 0 && marksObtained.Value >= 0)
        {
            resolvedObtained = Math.Min(marksObtained.Value, marksTotal.Value);
            resolvedTotal = marksTotal.Value;
        }

        var reward = StudyReward.Calculate(kind, subject, minutes, resolvedObtained, resolvedTotal);
        var cash = reward.Cash;
        var xp = reward.Xp;
        var now = DateTimeOffset.Now;

        var draft = State.Clone();
        draft.ClubCash += cash;
        draft.Xp += xp;
        draft.AvailableMatchMinutes += minutes;
        draft.Study.TotalStudyMinutes += minutes;
        draft.Study.TotalSessions += 1;
        switch (kind)
        {
            case StudyActivityKind.Homework:
                draft.Study.HomeworkCompleted += safeQuantity;
                break;
            case StudyActivityKind.PastPaper:
                draft.Study.PastPapersCompleted += safeQuantity;
                break;
            case StudyActivityKind.ExamQuestions:
                draft.Study.ExamQuestionsSolved += safeQuantity;
                break;
        }
        RegisterStudyDay(draft.Study, now);

        var resolvedSubtopic = subtopicId is null
            ? null
            : draft.Subtopics.FirstOrDefault(subtopic => subtopic.Id == subtopicId.Value);
        var trimmedTitle = title.Trim();
        var resolvedTitle = trimmedTitle.Length > 0
            ? trimmedTitle
            : resolvedSubtopic is not null
                ? $"{subject.ShortName()} - {resolvedSubtopic.Name}"
                : subject == StudySubject.Other ? kind.Title() : $"{subject.ShortName()} - {kind.Title()}";
        draft.RecentSessions.Insert(0, new StudySession
        {
            Id = Guid.NewGuid(),
            Date = now,
            Kind = kind,
            Title = resolvedTitle,
            Minutes = minutes,
            CashEarned = cash,
            XpEarned = xp,
            Quantity = safeQuantity,
            Subject = subject,
            MarksObtained = resolvedObtained,
            MarksTotal = resolvedTotal,
            SubtopicID = resolvedSubtopic?.Id,
            SubtopicName = resolvedSubtopic?.Name
        });
        Commit(draft);
    }

    /// <summary>
    /// Removes a logged session from the study log. Cash and XP already banked stay with
    /// the club — the entry itself is what disappears. Mirrors the macOS Study Log.
    /// </summary>
    public void DeleteStudySession(Guid id)
    {
        if (State.RecentSessions.All(session => session.Id != id)) return;
        var draft = State.Clone();
        draft.RecentSessions.RemoveAll(session => session.Id == id);
        Commit(draft);
    }

    // MARK: - Subtopics and subject tracking

    public IReadOnlyList<Subtopic> Subtopics => State.Subtopics;

    public List<Subtopic> SubtopicsFor(StudySubject subject) =>
        State.Subtopics.Where(subtopic => subtopic.Subject == subject).ToList();

    /// <summary>
    /// Adds a module or topic to a subject. Returns null when the name is blank or the
    /// subject already has a subtopic with that name.
    /// </summary>
    public Subtopic? AddSubtopic(string name, StudySubject subject)
    {
        if (!HasCareer) return null;
        var trimmed = name.Trim();
        if (trimmed.Length == 0) return null;
        var siblings = State.Subtopics.Where(subtopic => subtopic.Subject == subject).ToList();
        if (siblings.Any(subtopic => string.Equals(subtopic.Name, trimmed, StringComparison.OrdinalIgnoreCase))) return null;
        var subtopic = new Subtopic
        {
            Id = Guid.NewGuid(),
            Subject = subject,
            Name = trimmed,
            CreatedAt = DateTimeOffset.Now
        };
        var draft = State.Clone();
        draft.Subtopics.Add(subtopic);
        Commit(draft);
        return subtopic;
    }

    /// <summary>
    /// Removes a subtopic from the subject list. Sessions keep the name they were logged
    /// with, so subject totals and history are untouched.
    /// </summary>
    public void DeleteSubtopic(Guid id)
    {
        if (State.Subtopics.All(subtopic => subtopic.Id != id)) return;
        var draft = State.Clone();
        draft.Subtopics.RemoveAll(subtopic => subtopic.Id == id);
        Commit(draft);
    }

    public StudyAggregate Aggregate(StudySubject subject) =>
        StudyAggregate.Build(State.RecentSessions.Where(session => session.Subject == subject));

    public StudyAggregate AggregateForSubtopic(Guid id) =>
        StudyAggregate.Build(State.RecentSessions.Where(session => session.SubtopicID == id));

    public StudyAggregate StudyAggregate => StudyAggregate.Build(State.RecentSessions);

    public int MarksAttempted => StudyAggregate.MarksTotal;

    public void StartTimer()
    {
        if (IsTimerRunning) return;
        TimerElapsedSeconds = 0;
        _timerCreditedMinutes = 0;
        LastTimerSessionMinutes = 0;
        IsTimerRunning = true;
        Changed?.Invoke();
    }

    public void PauseTimer()
    {
        if (!IsTimerRunning) return;
        IsTimerRunning = false;
        var minutes = _timerCreditedMinutes;
        if (minutes > 0)
        {
            var cash = minutes * GameRules.ClubCashPerMinute;
            var xp = minutes * GameRules.XpPerMinute;
            var draft = State.Clone();
            draft.Study.TotalSessions += 1;
            draft.RecentSessions.Insert(0, new StudySession
            {
                Id = Guid.NewGuid(),
                Date = DateTimeOffset.Now,
                Kind = StudyActivityKind.FocusSession,
                Title = "Focus session",
                Minutes = minutes,
                CashEarned = cash,
                XpEarned = xp,
                Quantity = minutes
            });
            Commit(draft);
            LastTimerSessionMinutes = minutes;
        }
        TimerElapsedSeconds = 0;
        _timerCreditedMinutes = 0;
        Changed?.Invoke();
    }

    public void ResetTimer()
    {
        IsTimerRunning = false;
        TimerElapsedSeconds = 0;
        _timerCreditedMinutes = 0;
        Changed?.Invoke();
    }

    /// <summary>Called once a second by the desktop shell while the timer runs.</summary>
    public void TimerTick()
    {
        if (!IsTimerRunning) return;
        TimerElapsedSeconds += 1;
        if (TimerElapsedSeconds % 60 == 0) CreditTimerMinute();
        Changed?.Invoke();
    }

    private void CreditTimerMinute()
    {
        var now = DateTimeOffset.Now;
        var draft = State.Clone();
        draft.ClubCash += GameRules.ClubCashPerMinute;
        draft.Xp += GameRules.XpPerMinute;
        draft.AvailableMatchMinutes += 1;
        draft.Study.TotalStudyMinutes += 1;
        RegisterStudyDay(draft.Study, now);
        _timerCreditedMinutes += 1;
        Commit(draft);
    }

    public void Assign(Guid playerId, string slotId)
    {
        var slot = LineupSlot.Slot(slotId);
        if (slot is null || PlayerFor(playerId) is null) return;
        var draft = State.Clone();
        foreach (var key in draft.Lineup.Where(pair => pair.Value == playerId).Select(pair => pair.Key).ToList())
        {
            draft.Lineup.Remove(key);
        }
        draft.Lineup[slot.Id] = playerId;
        draft.Bench.RemoveAll(id => id == playerId);
        Commit(draft);
    }

    public void RemoveFromLineup(string slotId)
    {
        if (!State.Lineup.ContainsKey(slotId)) return;
        var draft = State.Clone();
        draft.Lineup.Remove(slotId);
        Commit(draft);
    }

    public void AddToBench(Guid playerId)
    {
        if (PlayerFor(playerId) is null) return;
        if (State.Bench.Contains(playerId)) return;
        if (State.Bench.Count >= GameRules.BenchLimit) return;
        var draft = State.Clone();
        foreach (var key in draft.Lineup.Where(pair => pair.Value == playerId).Select(pair => pair.Key).ToList())
        {
            draft.Lineup.Remove(key);
        }
        draft.Bench.Add(playerId);
        Commit(draft);
    }

    public void RemoveFromBench(Guid playerId)
    {
        if (!State.Bench.Contains(playerId)) return;
        var draft = State.Clone();
        draft.Bench.RemoveAll(id => id == playerId);
        Commit(draft);
    }

    public void AddToSquad(Guid playerId)
    {
        var player = PlayerFor(playerId);
        if (player is null) return;
        if (State.Lineup.ContainsValue(playerId) || State.Bench.Contains(playerId)) return;
        var draft = State.Clone();
        var emptySlots = LineupSlot.All.Where(slot => !draft.Lineup.ContainsKey(slot.Id)).ToList();
        var bestSlot = emptySlots.FirstOrDefault(slot => slot.Position == player.Position)
            ?? emptySlots.FirstOrDefault(slot => slot.Position.Group() == player.Position.Group())
            ?? emptySlots.FirstOrDefault();
        if (bestSlot is not null)
        {
            draft.Lineup[bestSlot.Id] = playerId;
        }
        else if (draft.Bench.Count < GameRules.BenchLimit)
        {
            draft.Bench.Add(playerId);
        }
        else
        {
            return;
        }
        Commit(draft);
    }

    public void AutoPickSquad()
    {
        var (lineup, bench) = PlayerFactory.AutoLineup(State.Players);
        var draft = State.Clone();
        draft.Lineup = lineup;
        draft.Bench = bench;
        Commit(draft);
    }

    public int ReleasePlayer(Guid playerId)
    {
        var player = PlayerFor(playerId);
        if (player is null) return 0;
        var draft = State.Clone();
        draft.Players.RemoveAll(candidate => candidate.Id == playerId);
        foreach (var key in draft.Lineup.Where(pair => pair.Value == playerId).Select(pair => pair.Key).ToList())
        {
            draft.Lineup.Remove(key);
        }
        draft.Bench.RemoveAll(id => id == playerId);
        draft.ClubCash += player.ReleaseValue;
        Commit(draft);
        return player.ReleaseValue;
    }

    public List<Player> OpenPack(string packId, Random? random = null)
    {
        if (ManagedClub is null) throw new GameException("Choose a club before starting.");
        var pack = PackCatalog.Pack(packId) ?? throw new GameException("That pack is not available.");
        if (Level < pack.MinimumLevel) throw new GameException($"Reach level {pack.MinimumLevel} to unlock this pack.");
        if (State.ClubCash < pack.Price) throw new GameException("You do not have enough Club Cash.");

        random ??= Random.Shared;
        var draft = State.Clone();
        draft.ClubCash -= pack.Price;
        var pulled = new List<Player>();
        for (var index = 0; index < pack.PlayerCount; index++)
        {
            var rarity = pack.Id == "gold" && index == 0
                ? WeightedRarity(new Dictionary<PlayerRarity, int>
                {
                    [PlayerRarity.Gold] = 86, [PlayerRarity.Wonderkid] = 10, [PlayerRarity.Icon] = 4
                }, random)
                : WeightedRarity(pack.RarityWeights, random);
            var candidateIndex = draft.FreeAgents.FindIndex(player => player.Rarity == rarity);
            var player = candidateIndex >= 0
                ? TakeFreeAgent(draft, candidateIndex)
                : PlayerFactory.MakePackPlayer(rarity, draft.SeasonNumber, random);
            draft.Players.Add(player);
            pulled.Add(player);
        }
        Commit(draft);
        return pulled;
    }

    private static Player TakeFreeAgent(GameState draft, int index)
    {
        var player = draft.FreeAgents[index];
        draft.FreeAgents.RemoveAt(index);
        return player;
    }

    public SimulationOutcome SimulateCurrentStage()
    {
        var managedClub = ManagedClub ?? throw new GameException("Choose a club before starting.");
        var season = State.Season?.Clone() ?? throw new GameException("There is no active season.");
        if (season.Phase == SeasonPhase.Complete) throw new GameException("This season is already complete.");
        var fixturesToPlay = season.CurrentFixtures;
        if (fixturesToPlay.Count == 0) throw new GameException("There are no fixtures ready to simulate.");

        var userFixture = fixturesToPlay.FirstOrDefault(fixture =>
            fixture.HomeClubID == managedClub.Id || fixture.AwayClubID == managedClub.Id);
        if (userFixture is not null)
        {
            if (!LineupIsComplete) throw new GameException("Complete your starting XI before playing a match.");
            if (State.AvailableMatchMinutes < GameRules.MinutesPerMatch)
            {
                throw new GameException($"You need {MinutesUntilMatch} more study minutes to unlock this match.");
            }
        }

        var metrics = SquadMetrics;
        var userScorers = UserStartingPlayers;
        var phasePlayed = season.Phase;
        var updatedFixtures = season.Fixtures;
        var updatedReports = season.Reports;
        MatchReport? userReport = null;
        var simulatedCount = 0;

        foreach (var fixture in fixturesToPlay)
        {
            if (fixture.IsSimulated) continue;
            var homeClub = ClubDatabase.Club(fixture.HomeClubID);
            var awayClub = ClubDatabase.Club(fixture.AwayClubID);
            if (homeClub is null || awayClub is null) continue;

            var homeTeam = TeamProfile(homeClub, managedClub.Id, metrics, userScorers, season.Number);
            var awayTeam = TeamProfile(awayClub, managedClub.Id, metrics, userScorers, season.Number);
            var simulation = MatchEngine.Simulate(fixture, homeTeam, awayTeam, season.Number);
            var index = updatedFixtures.FindIndex(candidate => candidate.Id == fixture.Id);
            if (index >= 0)
            {
                updatedFixtures[index].HomeGoals = simulation.Report.HomeGoals;
                updatedFixtures[index].AwayGoals = simulation.Report.AwayGoals;
                updatedFixtures[index].HomePenalties = simulation.Report.HomePenalties;
                updatedFixtures[index].AwayPenalties = simulation.Report.AwayPenalties;
            }
            updatedReports.Add(simulation.Report);
            if (fixture.HomeClubID == managedClub.Id || fixture.AwayClubID == managedClub.Id)
            {
                userReport = simulation.Report;
            }
            simulatedCount++;
        }

        season.Fixtures = updatedFixtures;
        season.Reports = updatedReports;

        var standingsAfter = StandingsEngine.Standings(season.Fixtures);
        TrophyRecord? trophy = null;

        if (phasePlayed == SeasonPhase.League)
        {
            season.NextLeagueRound += 1;
            if (season.NextLeagueRound > 8)
            {
                var playoffs = ScheduleEngine.MakePlayoffFixtures(standingsAfter);
                season.Fixtures.AddRange(playoffs);
                season.Phase = SeasonPhase.Playoffs;
            }
        }
        else if (phasePlayed == SeasonPhase.Final)
        {
            var finalFixtures = season.FixturesFor(SeasonPhase.Final);
            var final = finalFixtures.FirstOrDefault();
            var winnerId = final?.WinnerClubID;
            var loserId = final?.LoserClubID;
            if (final is null || winnerId is null || loserId is null) throw new GameException("The season could not advance.");
            season.ChampionClubID = winnerId;
            season.RunnerUpClubID = loserId;
            season.Phase = SeasonPhase.Complete;
            if (!season.Archived)
            {
                trophy = SeasonEngine.MakeTrophyRecord(season, managedClub, standingsAfter);
                season.Archived = true;
            }
        }
        else
        {
            var next = SeasonEngine.NextPhase(phasePlayed);
            var nextFixtures = new List<Fixture>();
            switch (phasePlayed)
            {
                case SeasonPhase.Playoffs:
                    nextFixtures = ScheduleEngine.MakeRoundOf16(
                        standingsAfter, season.FixturesFor(SeasonPhase.Playoffs));
                    break;
                case SeasonPhase.RoundOf16:
                case SeasonPhase.Quarterfinal:
                case SeasonPhase.Semifinal:
                    nextFixtures = ScheduleEngine.MakeNextKnockoutRound(
                        season.FixturesFor(phasePlayed), next, standingsAfter);
                    break;
            }
            if (nextFixtures.Count == 0) throw new GameException("The season could not advance.");
            season.Fixtures.AddRange(nextFixtures);
            season.Phase = next;
        }

        var draft = State.Clone();
        draft.Season = season;
        if (trophy is not null) draft.Trophies.Add(trophy);
        if (userFixture is not null) draft.AvailableMatchMinutes -= GameRules.MinutesPerMatch;
        Commit(draft);

        return new SimulationOutcome(
            userReport,
            simulatedCount,
            phasePlayed,
            ClubDatabase.Club(season.ChampionClubID),
            trophy);
    }

    public SeasonTransition StartNextSeason()
    {
        if (State.Season is null || State.Season.Phase != SeasonPhase.Complete || !State.Season.Archived)
        {
            throw new GameException("This season is already complete.");
        }
        var managedClub = ManagedClub ?? throw new GameException("Choose a club before starting.");
        var season = State.Season;
        var oldNumber = season.Number;
        var championName = ClubDatabase.Club(season.ChampionClubID)?.Name ?? "Unknown";
        var userFinish = SeasonEngine.UserFinish(
            managedClub.Id, StandingsEngine.Standings(season.Fixtures), season.Fixtures, season.ChampionClubID);

        var generator = new SeededGenerator(StableSeed.Value($"aging-{oldNumber}-{managedClub.Id}"));
        var starters = State.Lineup.Values.ToHashSet();
        var squadResult = DevelopPlayers(State.Players, starters, ref generator);
        var poolResult = DevelopPlayers(State.FreeAgents, [], ref generator);

        var draft = State.Clone();
        draft.Players = squadResult.Players;
        draft.FreeAgents = poolResult.Players;
        var retiredIds = squadResult.RetiredIds.ToHashSet();
        draft.Lineup = draft.Lineup
            .Where(pair => !retiredIds.Contains(pair.Value))
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        draft.Bench.RemoveAll(id => retiredIds.Contains(id));
        draft.SeasonNumber += 1;
        var youthCount = 10;
        draft.FreeAgents.AddRange(PlayerFactory.MakeYouthProspects(draft.SeasonNumber, youthCount));
        // The academy promotes a handful of teenagers straight into the senior squad every
        // season so ageing squads can be replenished without the transfer market.
        draft.Players.AddRange(PlayerFactory.MakeAcademyProspects(draft.SeasonNumber, GameRules.AcademyIntakePerSeason));
        if (draft.FreeAgents.Count < 48)
        {
            var extraCount = 48 - draft.FreeAgents.Count;
            draft.FreeAgents.AddRange(PlayerFactory.MakeFreeAgentPool(draft.SeasonNumber, extraCount));
            youthCount += extraCount;
        }
        draft.Season = SeasonEngine.NewSeason(draft.SeasonNumber);
        var transition = new SeasonTransition
        {
            Id = Guid.NewGuid(),
            CompletedSeason = oldNumber,
            ChampionName = championName,
            UserFinish = userFinish,
            Retirees = squadResult.RetiredNames,
            YouthAdded = youthCount,
            NewSeason = draft.SeasonNumber
        };
        draft.LastTransition = transition;
        Commit(draft);
        return transition;
    }

    public void DismissTransition()
    {
        if (State.LastTransition is null) return;
        var draft = State.Clone();
        draft.LastTransition = null;
        Commit(draft);
    }

    public void ClearSaveError() => SaveErrorMessage = null;

    /// <summary>Wipes the career, squad, trophies and study history, returning to club selection.</summary>
    public void ResetCareer()
    {
        ResetTimer();
        LastTimerSessionMinutes = 0;
        SaveErrorMessage = null;
        Commit(GameState.Fresh());
    }

    private void Commit(GameState draft)
    {
        State = draft;
        try
        {
            _persistence.Save(draft);
        }
        catch (Exception exception)
        {
            SaveErrorMessage = $"Could not save your career: {exception.Message}";
        }
        Changed?.Invoke();
    }

    private static MatchTeam TeamProfile(
        Club club,
        string userClubId,
        SquadMetrics metrics,
        IReadOnlyList<Player> userScorers,
        int season)
    {
        if (club.Id == userClubId)
        {
            return new MatchTeam(club, metrics.Overall, userScorers);
        }
        var roster = PlayerFactory.AiRoster(club, season);
        return new MatchTeam(club, club.Rating, roster);
    }

    private static PlayerRarity WeightedRarity(Dictionary<PlayerRarity, int> weights, Random random)
    {
        var total = weights.Values.Sum();
        if (total <= 0) return PlayerRarity.Silver;
        var roll = random.Next(0, total);
        foreach (var rarity in PlayerRarityExtensions.All)
        {
            if (!weights.TryGetValue(rarity, out var weight)) continue;
            if (roll < weight) return rarity;
            roll -= weight;
        }
        return weights.Keys.First();
    }

    /// <summary>
    /// Ages every player by a year. Starters develop faster than squad players who did
    /// not feature in the XI, and players retire once they reach their retirement age.
    /// </summary>
    private static (List<Player> Players, List<string> RetiredNames, List<Guid> RetiredIds) DevelopPlayers(
        IReadOnlyList<Player> players,
        HashSet<Guid> starters,
        ref SeededGenerator generator)
    {
        var developed = new List<Player>();
        var retiredNames = new List<string>();
        var retiredIds = new List<Guid>();
        foreach (var source in players)
        {
            var player = source.Clone();
            var nextAge = player.Age + 1;
            if (nextAge >= player.RetirementAge)
            {
                retiredNames.Add(player.Name);
                retiredIds.Add(player.Id);
                continue;
            }
            player.Age = nextAge;
            var isStarter = starters.Contains(player.Id);
            if (nextAge <= 22 && player.Overall < player.Potential)
            {
                var gain = isStarter ? generator.NextInt(1, 3) : generator.NextInt(0, 2);
                player.Overall = Math.Min(player.Potential, player.Overall + gain);
            }
            else if (nextAge <= 27 && player.Overall < player.Potential)
            {
                if (isStarter)
                {
                    player.Overall = Math.Min(player.Potential, player.Overall + generator.NextInt(0, 1));
                }
                else if (generator.NextInt(0, 2) == 0)
                {
                    player.Overall = Math.Min(player.Potential, player.Overall + 1);
                }
            }
            else if (nextAge >= 30)
            {
                player.Overall = Math.Max(45, player.Overall - generator.NextInt(0, 2));
            }
            developed.Add(player);
        }
        return (developed, retiredNames, retiredIds);
    }

    private static int PhaseOrder(SeasonPhase phase) => phase switch
    {
        SeasonPhase.League => 0,
        SeasonPhase.Playoffs => 1,
        SeasonPhase.RoundOf16 => 2,
        SeasonPhase.Quarterfinal => 3,
        SeasonPhase.Semifinal => 4,
        SeasonPhase.Final => 5,
        _ => 6
    };

    private static void RegisterStudyDay(StudyStats stats, DateTimeOffset date)
    {
        var today = date.Date;
        if (stats.LastStudyDay.HasValue)
        {
            var lastDay = stats.LastStudyDay.Value.Date;
            if (lastDay == today) return;
            stats.CurrentStreak = lastDay == today.AddDays(-1) ? stats.CurrentStreak + 1 : 1;
        }
        else
        {
            stats.CurrentStreak = 1;
        }
        stats.BestStreak = Math.Max(stats.BestStreak, stats.CurrentStreak);
        stats.LastStudyDay = date;
    }
}
