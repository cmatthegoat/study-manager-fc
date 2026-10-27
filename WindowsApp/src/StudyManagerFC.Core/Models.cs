using System.Text.Json.Serialization;

namespace StudyManagerFC.Core;

public static class GameRules
{
    public const int ClubCashPerMinute = 10;
    public const int XpPerMinute = 6;
    public const int MinutesPerMatch = 90;
    public const int StartingCash = 600;
    public const int BenchLimit = 7;
    public const int XpPerLevel = 750;
    public const int FreeAgentPoolTarget = 84;
    public const int RetirementAge = 40;
    public const int AcademyIntakePerSeason = 3;
}

public enum PositionGroup
{
    Goalkeeper,
    Defence,
    Midfield,
    Attack
}

public static class PositionGroupExtensions
{
    public static string ShortName(this PositionGroup group) => group switch
    {
        PositionGroup.Goalkeeper => "GK",
        PositionGroup.Defence => "DEF",
        PositionGroup.Midfield => "MID",
        _ => "ATT"
    };

    public static string DisplayName(this PositionGroup group) => group switch
    {
        PositionGroup.Goalkeeper => "Goalkeeper",
        PositionGroup.Defence => "Defence",
        PositionGroup.Midfield => "Midfield",
        _ => "Attack"
    };
}

public enum PlayerPosition
{
    Goalkeeper,
    LeftBack,
    CenterBack,
    RightBack,
    DefensiveMid,
    CentralMid,
    AttackingMid,
    LeftWing,
    Striker,
    RightWing
}

public static class PlayerPositionExtensions
{
    public static readonly PlayerPosition[] All =
    [
        PlayerPosition.Goalkeeper, PlayerPosition.LeftBack, PlayerPosition.CenterBack,
        PlayerPosition.RightBack, PlayerPosition.DefensiveMid, PlayerPosition.CentralMid,
        PlayerPosition.AttackingMid, PlayerPosition.LeftWing, PlayerPosition.Striker,
        PlayerPosition.RightWing
    ];

    public static string Abbreviation(this PlayerPosition position) => position switch
    {
        PlayerPosition.Goalkeeper => "GK",
        PlayerPosition.LeftBack => "LB",
        PlayerPosition.CenterBack => "CB",
        PlayerPosition.RightBack => "RB",
        PlayerPosition.DefensiveMid => "CDM",
        PlayerPosition.CentralMid => "CM",
        PlayerPosition.AttackingMid => "CAM",
        PlayerPosition.LeftWing => "LW",
        PlayerPosition.Striker => "ST",
        _ => "RW"
    };

    public static string DisplayName(this PlayerPosition position) => position switch
    {
        PlayerPosition.Goalkeeper => "Goalkeeper",
        PlayerPosition.LeftBack => "Left Back",
        PlayerPosition.CenterBack => "Centre Back",
        PlayerPosition.RightBack => "Right Back",
        PlayerPosition.DefensiveMid => "Defensive Midfielder",
        PlayerPosition.CentralMid => "Central Midfielder",
        PlayerPosition.AttackingMid => "Attacking Midfielder",
        PlayerPosition.LeftWing => "Left Winger",
        PlayerPosition.Striker => "Striker",
        _ => "Right Winger"
    };

    public static PositionGroup Group(this PlayerPosition position) => position switch
    {
        PlayerPosition.Goalkeeper => PositionGroup.Goalkeeper,
        PlayerPosition.LeftBack or PlayerPosition.CenterBack or PlayerPosition.RightBack => PositionGroup.Defence,
        PlayerPosition.DefensiveMid or PlayerPosition.CentralMid or PlayerPosition.AttackingMid => PositionGroup.Midfield,
        _ => PositionGroup.Attack
    };

    public static double ScoringWeight(this PlayerPosition position) => position switch
    {
        PlayerPosition.Goalkeeper => 0.02,
        PlayerPosition.LeftBack or PlayerPosition.RightBack => 0.45,
        PlayerPosition.CenterBack => 0.35,
        PlayerPosition.DefensiveMid => 0.7,
        PlayerPosition.CentralMid => 1.8,
        PlayerPosition.AttackingMid => 3.2,
        PlayerPosition.LeftWing or PlayerPosition.RightWing => 4.4,
        _ => 7.0
    };

    public static PlayerAttributes Bias(this PlayerPosition position) => position switch
    {
        PlayerPosition.Goalkeeper => new PlayerAttributes(-6, -18, -2, 10, 7),
        PlayerPosition.LeftBack or PlayerPosition.RightBack => new PlayerAttributes(8, -8, 2, 3, 0),
        PlayerPosition.CenterBack => new PlayerAttributes(-4, -14, -4, 12, 9),
        PlayerPosition.DefensiveMid => new PlayerAttributes(-4, -8, 5, 8, 5),
        PlayerPosition.CentralMid => new PlayerAttributes(0, 0, 10, 0, 0),
        PlayerPosition.AttackingMid => new PlayerAttributes(3, 4, 8, -10, -4),
        PlayerPosition.LeftWing or PlayerPosition.RightWing => new PlayerAttributes(10, 4, 1, -12, -6),
        _ => new PlayerAttributes(6, 12, -6, -14, 2)
    };
}

public enum PlayerRarity
{
    Bronze,
    Silver,
    Gold,
    Wonderkid,
    Icon
}

public static class PlayerRarityExtensions
{
    public static readonly PlayerRarity[] All =
        [PlayerRarity.Bronze, PlayerRarity.Silver, PlayerRarity.Gold, PlayerRarity.Wonderkid, PlayerRarity.Icon];

    public static string DisplayName(this PlayerRarity rarity) => rarity switch
    {
        PlayerRarity.Bronze => "Bronze",
        PlayerRarity.Silver => "Silver",
        PlayerRarity.Gold => "Gold",
        PlayerRarity.Wonderkid => "Wonderkid",
        _ => "Icon"
    };

    public static int SortOrder(this PlayerRarity rarity) => (int)rarity;
}

public readonly record struct PlayerAttributes(int Pace, int Shooting, int Passing, int Defending, int Physical);

/// <summary>
/// A player's price is driven by overall rating: every extra point of overall is
/// worth roughly 16% more than the one below it, so elite players cost an order of
/// magnitude more than solid squad options.
/// </summary>
public static class PlayerPricing
{
    public const int BaselineOverall = 60;
    public const int BaselineFee = 250;
    public const double GrowthPerOverall = 1.16;

    public static int Fee(int overall)
    {
        var steps = Math.Max(0, overall - BaselineOverall);
        return (int)Math.Round(BaselineFee * Math.Pow(GrowthPerOverall, steps), MidpointRounding.AwayFromZero);
    }
}

public sealed class Player
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string NationCode { get; set; } = "ENG";
    public PlayerPosition Position { get; set; } = PlayerPosition.CentralMid;
    public int Age { get; set; }
    public int Overall { get; set; }
    public int Potential { get; set; }
    public PlayerRarity Rarity { get; set; } = PlayerRarity.Silver;
    public PlayerAttributes Attributes { get; set; }
    public int RetirementAge { get; set; } = GameRules.RetirementAge;
    public int JoinedSeason { get; set; }

    public string FirstName => Name.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? Name;

    public string Initials => string.Concat(Name.Split(' ', StringSplitOptions.RemoveEmptyEntries)
        .Take(2).Select(part => part[0]));

    public string Surname => Name.Split(' ', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? Name;

    public Nation Nation => Nations.For(NationCode);

    public int MarketValue => PlayerPricing.Fee(Overall);

    public int ReleaseValue => Rarity switch
    {
        PlayerRarity.Bronze => Math.Max(20, Overall * 2),
        PlayerRarity.Silver => Math.Max(60, Overall * 3),
        PlayerRarity.Gold => Math.Max(150, Overall * 5),
        PlayerRarity.Wonderkid => Math.Max(250, Overall * 6),
        _ => Math.Max(600, Overall * 11)
    };

    public int FitScore(LineupSlot slot)
    {
        if (Position == slot.Position) return 2;
        if (Position.Group() == slot.Position.Group()) return 1;
        return 0;
    }

    public int AdjustedRating(LineupSlot slot) => FitScore(slot) switch
    {
        2 => Overall,
        1 => Overall - 2,
        _ => Overall - 7
    };

    public Player Clone()
    {
        return new Player
        {
            Id = Id,
            Name = Name,
            NationCode = NationCode,
            Position = Position,
            Age = Age,
            Overall = Overall,
            Potential = Potential,
            Rarity = Rarity,
            Attributes = Attributes,
            RetirementAge = RetirementAge,
            JoinedSeason = JoinedSeason
        };
    }
}

public sealed record StarterSeed(string Name, int Rating, PlayerPosition Position, string NationCode);

public sealed record Club(
    string Id,
    string Name,
    string ShortName,
    string Code,
    string CountryCode,
    string PrimaryHex,
    string SecondaryHex,
    int Rating)
{
    public string Country => Nations.For(CountryCode).Name;
}

public sealed record LineupSlot(string Id, string Label, PlayerPosition Position, double X, double Y)
{
    public static readonly LineupSlot[] All =
    [
        new("gk", "GK", PlayerPosition.Goalkeeper, 0.50, 0.91),
        new("lb", "LB", PlayerPosition.LeftBack, 0.13, 0.73),
        new("cb1", "CB", PlayerPosition.CenterBack, 0.37, 0.78),
        new("cb2", "CB", PlayerPosition.CenterBack, 0.63, 0.78),
        new("rb", "RB", PlayerPosition.RightBack, 0.87, 0.73),
        new("cdm", "CDM", PlayerPosition.DefensiveMid, 0.50, 0.59),
        new("cm", "CM", PlayerPosition.CentralMid, 0.24, 0.49),
        new("cam", "CAM", PlayerPosition.AttackingMid, 0.76, 0.49),
        new("lw", "LW", PlayerPosition.LeftWing, 0.16, 0.26),
        new("st", "ST", PlayerPosition.Striker, 0.50, 0.18),
        new("rw", "RW", PlayerPosition.RightWing, 0.84, 0.26)
    ];

    public static LineupSlot? Slot(string id) => Array.Find(All, slot => slot.Id == id);
}

public sealed record SquadMetrics(
    int Overall,
    int Chemistry,
    int Attack,
    int Midfield,
    int Defence,
    int TotalValue,
    int PlayerCount)
{
    public static readonly SquadMetrics Empty = new(0, 0, 0, 0, 0, 0, 0);

    public static SquadMetrics Calculate(Dictionary<string, Guid> lineup, IReadOnlyList<Player> players)
    {
        var playerMap = players.ToDictionary(player => player.Id);
        var ratings = new List<int>();
        var chemistryPoints = 0;
        var nations = new Dictionary<string, int>();
        var attack = new List<int>();
        var midfield = new List<int>();
        var defence = new List<int>();

        foreach (var slot in LineupSlot.All)
        {
            if (!lineup.TryGetValue(slot.Id, out var playerId)) continue;
            if (!playerMap.TryGetValue(playerId, out var player)) continue;

            var rating = player.AdjustedRating(slot);
            ratings.Add(rating);
            chemistryPoints += player.FitScore(slot);
            nations[player.NationCode] = nations.GetValueOrDefault(player.NationCode) + 1;
            switch (slot.Position.Group())
            {
                case PositionGroup.Goalkeeper:
                case PositionGroup.Defence:
                    defence.Add(rating);
                    break;
                case PositionGroup.Midfield:
                    midfield.Add(rating);
                    break;
                default:
                    attack.Add(rating);
                    break;
            }
        }

        if (ratings.Count == 0) return Empty;

        var sameNationLinks = nations.Values.Sum(count => Math.Max(0, count - 1));
        var positionChemistry = chemistryPoints / (double)(LineupSlot.All.Length * 2) * 70.0;
        var nationChemistry = Math.Min(30.0, sameNationLinks * 3.5);
        var chemistry = (int)Math.Round(positionChemistry + nationChemistry, MidpointRounding.AwayFromZero);
        var baseOverall = ratings.Sum() / (double)ratings.Count;
        var missingPenalty = (LineupSlot.All.Length - ratings.Count) * 2.5;
        // Overall is the raw quality of the XI only; chemistry never inflates the rating
        // used to simulate a match.
        var overall = (int)Math.Round(baseOverall - missingPenalty, MidpointRounding.AwayFromZero);

        int LineRating(List<int> values) => values.Count == 0
            ? overall - 3
            : (int)Math.Round(values.Sum() / (double)values.Count, MidpointRounding.AwayFromZero);

        return new SquadMetrics(
            Math.Max(0, overall),
            chemistry,
            LineRating(attack),
            LineRating(midfield),
            LineRating(defence),
            players.Sum(player => player.MarketValue),
            players.Count);
    }
}

public enum StudyActivityKind
{
    Homework,
    PastPaper,
    ExamQuestions,
    FocusSession
}

public static class StudyActivityKindExtensions
{
    public static readonly StudyActivityKind[] All =
        [StudyActivityKind.Homework, StudyActivityKind.PastPaper, StudyActivityKind.ExamQuestions, StudyActivityKind.FocusSession];

    public static string Title(this StudyActivityKind kind) => kind switch
    {
        StudyActivityKind.Homework => "Homework",
        StudyActivityKind.PastPaper => "Past Paper",
        StudyActivityKind.ExamQuestions => "Exam Questions",
        _ => "Focus Session"
    };

    public static string UnitTitle(this StudyActivityKind kind) => kind switch
    {
        StudyActivityKind.Homework => "Assignments",
        StudyActivityKind.PastPaper => "Papers",
        StudyActivityKind.ExamQuestions => "Questions",
        _ => "Minutes"
    };

    public static bool SupportsMarking(this StudyActivityKind kind) =>
        kind is StudyActivityKind.Homework or StudyActivityKind.PastPaper or StudyActivityKind.ExamQuestions;

    /// <summary>
    /// How much a session of this kind is worth compared with homework. Past papers are
    /// the closest thing to the real exam, exam-style questions come next, and homework
    /// is the baseline.
    /// </summary>
    public static double RewardMultiplier(this StudyActivityKind kind) => kind switch
    {
        StudyActivityKind.PastPaper => 1.5,
        StudyActivityKind.ExamQuestions => 1.25,
        _ => 1.0
    };
}

public enum StudySubject
{
    Ext2Maths,
    Ext1Maths,
    Physics,
    Chemistry,
    SoftwareEngineering,
    BusinessStudies,
    EnglishAdvanced,
    Other
}

public static class StudySubjectExtensions
{
    public static readonly StudySubject[] All =
    [
        StudySubject.Ext2Maths, StudySubject.Ext1Maths, StudySubject.Physics, StudySubject.Chemistry,
        StudySubject.SoftwareEngineering, StudySubject.BusinessStudies, StudySubject.EnglishAdvanced,
        StudySubject.Other
    ];

    public static string DisplayName(this StudySubject subject) => subject switch
    {
        StudySubject.Ext2Maths => "Mathematics Extension 2",
        StudySubject.Ext1Maths => "Mathematics Extension 1",
        StudySubject.Physics => "Physics",
        StudySubject.Chemistry => "Chemistry",
        StudySubject.SoftwareEngineering => "Software Engineering",
        StudySubject.BusinessStudies => "Business Studies",
        StudySubject.EnglishAdvanced => "English Advanced",
        _ => "Other"
    };

    public static string ShortName(this StudySubject subject) => subject switch
    {
        StudySubject.Ext2Maths => "Ext 2 Maths",
        StudySubject.Ext1Maths => "Ext 1 Maths",
        StudySubject.Physics => "Physics",
        StudySubject.Chemistry => "Chemistry",
        StudySubject.SoftwareEngineering => "Software Eng",
        StudySubject.BusinessStudies => "Business",
        StudySubject.EnglishAdvanced => "English Adv",
        _ => "Other"
    };

    public static double CashMultiplier(this StudySubject subject) => subject switch
    {
        StudySubject.Ext2Maths => 1.5,
        StudySubject.Ext1Maths => 1.25,
        StudySubject.Physics => 1.25,
        StudySubject.Chemistry => 1.25,
        StudySubject.EnglishAdvanced => 2.2,
        StudySubject.SoftwareEngineering => 1.1,
        StudySubject.BusinessStudies => 0.95,
        _ => 1.0
    };

    public static double XpMultiplier(this StudySubject subject) => subject switch
    {
        StudySubject.Ext2Maths => 1.4,
        StudySubject.Ext1Maths => 1.2,
        StudySubject.Physics => 1.2,
        StudySubject.Chemistry => 1.2,
        StudySubject.EnglishAdvanced => 1.8,
        StudySubject.SoftwareEngineering => 1.1,
        StudySubject.BusinessStudies => 0.95,
        _ => 1.0
    };
}

/// <summary>
/// A module, topic or unit inside a subject, such as "Complex Numbers" for Ext 2 Maths.
/// Subtopics are created by the player, so the app never assumes a syllabus.
/// </summary>
public sealed class Subtopic
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public StudySubject Subject { get; set; }
    public string Name { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Subtopic Clone() => new()
    {
        Id = Id,
        Subject = Subject,
        Name = Name,
        CreatedAt = CreatedAt
    };
}

public sealed class StudySession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset Date { get; set; } = DateTimeOffset.UtcNow;
    public StudyActivityKind Kind { get; set; }
    public string Title { get; set; } = "";
    public int Minutes { get; set; }
    public int CashEarned { get; set; }
    public int XpEarned { get; set; }
    public int Quantity { get; set; }
    public StudySubject? Subject { get; set; }
    public int? MarksObtained { get; set; }
    public int? MarksTotal { get; set; }
    /// <summary>Identifies the subtopic this work belonged to, if any.</summary>
    public Guid? SubtopicID { get; set; }
    /// <summary>The subtopic name is stored alongside the id so history survives deleting it.</summary>
    public string? SubtopicName { get; set; }

    [JsonIgnore]
    public int? Percentage => MarksObtained.HasValue && MarksTotal is > 0
        ? (int)Math.Round(MarksObtained.Value / (double)MarksTotal.Value * 100, MidpointRounding.AwayFromZero)
        : null;

    [JsonIgnore]
    public string? MarkFraction => MarksObtained.HasValue && MarksTotal.HasValue
        ? $"{MarksObtained}/{MarksTotal}"
        : null;

    public StudySession Clone() => new()
    {
        Id = Id,
        Date = Date,
        Kind = Kind,
        Title = Title,
        Minutes = Minutes,
        CashEarned = CashEarned,
        XpEarned = XpEarned,
        Quantity = Quantity,
        Subject = Subject,
        MarksObtained = MarksObtained,
        MarksTotal = MarksTotal,
        SubtopicID = SubtopicID,
        SubtopicName = SubtopicName
    };
}

/// <summary>
/// Everything a player has done for a subject or a single subtopic: time, volume of
/// work, and how the marks have actually gone.
/// </summary>
public sealed class StudyAggregate
{
    public int Sessions { get; private set; }
    public int Minutes { get; private set; }
    public int MarksObtained { get; private set; }
    public int MarksTotal { get; private set; }
    public int Homework { get; private set; }
    public int PastPapers { get; private set; }
    public int ExamQuestions { get; private set; }
    public int CashEarned { get; private set; }
    public int XpEarned { get; private set; }

    public int WorkCount => Homework + PastPapers + ExamQuestions;

    public bool HasMarks => MarksTotal > 0;

    /// <summary>Weighted average: a 50-mark paper carries more than a 5-mark homework.</summary>
    public double? AverageRatio => MarksTotal > 0 ? MarksObtained / (double)MarksTotal : null;

    public int? AveragePercentage => AverageRatio.HasValue
        ? (int)Math.Round(AverageRatio.Value * 100, MidpointRounding.AwayFromZero)
        : null;

    public void Add(StudySession session)
    {
        Sessions += 1;
        Minutes += Math.Max(0, session.Minutes);
        CashEarned += session.CashEarned;
        XpEarned += session.XpEarned;
        switch (session.Kind)
        {
            case StudyActivityKind.Homework:
                Homework += session.Quantity;
                break;
            case StudyActivityKind.PastPaper:
                PastPapers += session.Quantity;
                break;
            case StudyActivityKind.ExamQuestions:
                ExamQuestions += session.Quantity;
                break;
        }
        if (session.MarksObtained.HasValue && session.MarksTotal is > 0)
        {
            MarksObtained += Math.Min(Math.Max(0, session.MarksObtained.Value), session.MarksTotal.Value);
            MarksTotal += session.MarksTotal.Value;
        }
    }

    public static StudyAggregate Build(IEnumerable<StudySession> sessions)
    {
        var aggregate = new StudyAggregate();
        foreach (var session in sessions) aggregate.Add(session);
        return aggregate;
    }
}

/// <summary>
/// The rewards a logged session earns. Marks are entered as marks gained over marks
/// attempted; that fraction becomes a percentage, and the percentage sets how much of
/// the base reward the session is worth.
/// </summary>
public static class StudyReward
{
    /// <summary>
    /// Unmarked work earns the plain rate. Marked work scales from 0.8x at 0% up to
    /// 1.45x at 100%, so a strong paper is worth noticeably more than a weak one.
    /// </summary>
    public static double GradeFactor(double? ratio)
    {
        if (ratio is null) return 1.0;
        return 0.8 + Math.Min(1, Math.Max(0, ratio.Value)) * 0.65;
    }

    public static (int Cash, int Xp, double? Ratio) Calculate(
        StudyActivityKind kind,
        StudySubject subject,
        int minutes,
        int? marksObtained,
        int? marksTotal)
    {
        double? ratio = null;
        if (marksObtained.HasValue && marksTotal is > 0 && marksObtained.Value >= 0)
        {
            ratio = Math.Min(1, marksObtained.Value / (double)marksTotal.Value);
        }
        var grade = GradeFactor(ratio);
        var safeMinutes = Math.Max(0, minutes);
        var cash = safeMinutes * (double)GameRules.ClubCashPerMinute * subject.CashMultiplier()
                   * kind.RewardMultiplier() * grade;
        var xp = safeMinutes * (double)GameRules.XpPerMinute * subject.XpMultiplier()
                 * kind.RewardMultiplier() * grade;
        return ((int)Math.Round(cash, MidpointRounding.AwayFromZero),
            (int)Math.Round(xp, MidpointRounding.AwayFromZero),
            ratio);
    }
}

public sealed class StudyStats
{
    public int TotalStudyMinutes { get; set; }
    public int TotalSessions { get; set; }
    public int HomeworkCompleted { get; set; }
    public int PastPapersCompleted { get; set; }
    public int ExamQuestionsSolved { get; set; }
    public int CurrentStreak { get; set; }
    public int BestStreak { get; set; }
    public DateTimeOffset? LastStudyDay { get; set; }
}

public enum SeasonPhase
{
    League,
    Playoffs,
    RoundOf16,
    Quarterfinal,
    Semifinal,
    Final,
    Complete
}

public static class SeasonPhaseExtensions
{
    public static string DisplayName(this SeasonPhase phase) => phase switch
    {
        SeasonPhase.League => "League Phase",
        SeasonPhase.Playoffs => "Knockout Playoff",
        SeasonPhase.RoundOf16 => "Round of 16",
        SeasonPhase.Quarterfinal => "Quarter-final",
        SeasonPhase.Semifinal => "Semi-final",
        SeasonPhase.Final => "Final",
        _ => "Complete"
    };

    public static string ShortName(this SeasonPhase phase) => phase switch
    {
        SeasonPhase.League => "League",
        SeasonPhase.Playoffs => "Playoff",
        SeasonPhase.RoundOf16 => "R16",
        SeasonPhase.Quarterfinal => "QF",
        SeasonPhase.Semifinal => "SF",
        SeasonPhase.Final => "Final",
        _ => "Done"
    };

    public static bool IsKnockout(this SeasonPhase phase) => phase is not (SeasonPhase.League or SeasonPhase.Complete);
}

public sealed class Fixture
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string HomeClubID { get; set; } = "";
    public string AwayClubID { get; set; } = "";
    public SeasonPhase Phase { get; set; } = SeasonPhase.League;
    public int Round { get; set; }
    public bool NeutralVenue { get; set; }
    public int? HomeGoals { get; set; }
    public int? AwayGoals { get; set; }
    public int? HomePenalties { get; set; }
    public int? AwayPenalties { get; set; }

    public bool IsSimulated => HomeGoals.HasValue && AwayGoals.HasValue;

    public string? WinnerClubID
    {
        get
        {
            if (!HomeGoals.HasValue || !AwayGoals.HasValue) return null;
            if (HomeGoals > AwayGoals) return HomeClubID;
            if (AwayGoals > HomeGoals) return AwayClubID;
            if (!HomePenalties.HasValue || !AwayPenalties.HasValue) return null;
            return HomePenalties > AwayPenalties ? HomeClubID : AwayClubID;
        }
    }

    public string? LoserClubID => WinnerClubID is null ? null : WinnerClubID == HomeClubID ? AwayClubID : HomeClubID;

    public string Scoreline
    {
        get
        {
            if (!HomeGoals.HasValue || !AwayGoals.HasValue) return "vs";
            if (HomePenalties.HasValue && AwayPenalties.HasValue)
                return $"{HomeGoals}-{AwayGoals} ({HomePenalties}-{AwayPenalties} pens)";
            return $"{HomeGoals}-{AwayGoals}";
        }
    }

    public Fixture Clone() => new()
    {
        Id = Id,
        HomeClubID = HomeClubID,
        AwayClubID = AwayClubID,
        Phase = Phase,
        Round = Round,
        NeutralVenue = NeutralVenue,
        HomeGoals = HomeGoals,
        AwayGoals = AwayGoals,
        HomePenalties = HomePenalties,
        AwayPenalties = AwayPenalties
    };
}

public sealed class MatchEvent
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int Minute { get; set; }
    public string ClubID { get; set; } = "";
    public string Scorer { get; set; } = "";
    public bool IsPenalty { get; set; }
}

public sealed record ScorerTally(string Name, int Goals);

public sealed class MatchReport
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FixtureID { get; set; }
    public SeasonPhase Phase { get; set; }
    public int Round { get; set; }
    public string HomeClubID { get; set; } = "";
    public string AwayClubID { get; set; } = "";
    public int HomeGoals { get; set; }
    public int AwayGoals { get; set; }
    public int? HomePenalties { get; set; }
    public int? AwayPenalties { get; set; }
    public List<MatchEvent> Events { get; set; } = [];
    public int HomeRating { get; set; }
    public int AwayRating { get; set; }
    public string Summary { get; set; } = "";
    public DateTimeOffset PlayedAt { get; set; } = DateTimeOffset.UtcNow;

    public string? WinnerClubID
    {
        get
        {
            if (HomeGoals > AwayGoals) return HomeClubID;
            if (AwayGoals > HomeGoals) return AwayClubID;
            if (!HomePenalties.HasValue || !AwayPenalties.HasValue) return null;
            return HomePenalties > AwayPenalties ? HomeClubID : AwayClubID;
        }
    }

    public string Scoreline => HomePenalties.HasValue && AwayPenalties.HasValue
        ? $"{HomeGoals}-{AwayGoals} ({HomePenalties}-{AwayPenalties} pens)"
        : $"{HomeGoals}-{AwayGoals}";

    public IReadOnlyList<ScorerTally> ScorersForHome => GroupedScorers(HomeClubID);

    public IReadOnlyList<ScorerTally> ScorersForAway => GroupedScorers(AwayClubID);

    private List<ScorerTally> GroupedScorers(string clubId)
    {
        var order = new List<string>();
        var counts = new Dictionary<string, int>();
        foreach (var matchEvent in Events.Where(e => e.ClubID == clubId))
        {
            if (!counts.ContainsKey(matchEvent.Scorer)) order.Add(matchEvent.Scorer);
            counts[matchEvent.Scorer] = counts.GetValueOrDefault(matchEvent.Scorer) + 1;
        }
        return order.Select(name => new ScorerTally(name, counts[name])).ToList();
    }
}

public sealed class SeasonState
{
    public int Number { get; set; }
    public SeasonPhase Phase { get; set; } = SeasonPhase.League;
    public int NextLeagueRound { get; set; } = 1;
    public List<Fixture> Fixtures { get; set; } = [];
    public List<MatchReport> Reports { get; set; } = [];
    public string? ChampionClubID { get; set; }
    public string? RunnerUpClubID { get; set; }
    public bool Archived { get; set; }

    public static SeasonState New(int number) => new() { Number = number, Phase = SeasonPhase.League, NextLeagueRound = 1 };

    public IEnumerable<Fixture> LeagueFixtures => Fixtures.Where(fixture => fixture.Phase == SeasonPhase.League);

    public List<Fixture> CurrentFixtures => Phase switch
    {
        SeasonPhase.League => Fixtures.Where(f => f.Phase == SeasonPhase.League && f.Round == NextLeagueRound).ToList(),
        SeasonPhase.Complete => [],
        _ => Fixtures.Where(f => f.Phase == Phase).ToList()
    };

    public List<Fixture> FixturesFor(SeasonPhase phase) => Fixtures.Where(f => f.Phase == phase).ToList();

    public bool IsLeagueComplete
    {
        get
        {
            var league = LeagueFixtures.ToList();
            return league.Count == 144 && league.All(f => f.IsSimulated);
        }
    }

    public int LeagueRoundsPlayed => Fixtures
        .Where(f => f.Phase == SeasonPhase.League)
        .GroupBy(f => f.Round)
        .Count(group => group.All(f => f.IsSimulated));

    public SeasonState Clone() => new()
    {
        Number = Number,
        Phase = Phase,
        NextLeagueRound = NextLeagueRound,
        Fixtures = Fixtures.Select(fixture => fixture.Clone()).ToList(),
        Reports = Reports.ToList(),
        ChampionClubID = ChampionClubID,
        RunnerUpClubID = RunnerUpClubID,
        Archived = Archived
    };
}

public sealed record StandingRow(
    Club Club,
    int Played,
    int Won,
    int Drawn,
    int Lost,
    int GoalsFor,
    int GoalsAgainst,
    int Points)
{
    public int GoalDifference => GoalsFor - GoalsAgainst;

    public StandingRow With(int played, int won, int drawn, int lost, int goalsFor, int goalsAgainst, int points) =>
        new(Club, played, won, drawn, lost, goalsFor, goalsAgainst, points);
}

public sealed class TrophyRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int SeasonNumber { get; set; }
    public string ChampionClubID { get; set; } = "";
    public string ChampionName { get; set; } = "";
    public string RunnerUpClubID { get; set; } = "";
    public string RunnerUpName { get; set; } = "";
    public string UserClubID { get; set; } = "";
    public string UserClubName { get; set; } = "";
    public string UserFinish { get; set; } = "";
    public bool UserWasChampion { get; set; }
    public DateTimeOffset CompletedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class SeasonTransition
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int CompletedSeason { get; set; }
    public string ChampionName { get; set; } = "";
    public string UserFinish { get; set; } = "";
    public List<string> Retirees { get; set; } = [];
    public int YouthAdded { get; set; }
    public int NewSeason { get; set; }
}

public sealed record PackDefinition(
    string Id,
    string Name,
    string Subtitle,
    int Price,
    int PlayerCount,
    int MinimumLevel,
    string AccentHex,
    string SystemImage,
    Dictionary<PlayerRarity, int> RarityWeights);

public static class PackCatalog
{
    public static readonly PackDefinition[] All =
    [
        new("bronze", "Bronze Pack", "Three squad players with a touch of senior experience.", 350, 3, 1,
            "B47142", "box", new() { [PlayerRarity.Bronze] = 82, [PlayerRarity.Silver] = 18 }),
        new("silver", "Silver Pack", "Three players. A strong pathway to a gold starter.", 900, 3, 2,
            "9BA6B2", "stack", new() { [PlayerRarity.Bronze] = 25, [PlayerRarity.Silver] = 62, [PlayerRarity.Gold] = 13 }),
        new("academy", "Academy Pack", "Three prospects. High potential, low starting ratings.", 1200, 3, 2,
            "4CD6B8", "academy", new() { [PlayerRarity.Silver] = 40, [PlayerRarity.Gold] = 30, [PlayerRarity.Wonderkid] = 30 }),
        new("gold", "Gold Pack", "Three players. At least one gold standard guaranteed.", 2200, 3, 3,
            "D8A72A", "star", new() { [PlayerRarity.Silver] = 10, [PlayerRarity.Gold] = 82, [PlayerRarity.Wonderkid] = 6, [PlayerRarity.Icon] = 2 }),
        new("icon", "Icon Pack", "One elite signing. The shortest path to a world-class XI.", 6000, 1, 5,
            "E8D38A", "crown", new() { [PlayerRarity.Gold] = 30, [PlayerRarity.Wonderkid] = 25, [PlayerRarity.Icon] = 45 })
    ];

    public static PackDefinition? Pack(string id) => Array.Find(All, pack => pack.Id == id);
}

public sealed class GameState
{
    public const int CurrentSchemaVersion = 3;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public string? ManagedClubID { get; set; }
    public int ClubCash { get; set; } = GameRules.StartingCash;
    public int Xp { get; set; }
    public int AvailableMatchMinutes { get; set; }
    public StudyStats Study { get; set; } = new();
    public List<StudySession> RecentSessions { get; set; } = [];
    public List<Subtopic> Subtopics { get; set; } = [];
    public List<Player> Players { get; set; } = [];
    public List<Player> FreeAgents { get; set; } = [];
    public Dictionary<string, Guid> Lineup { get; set; } = [];
    public List<Guid> Bench { get; set; } = [];
    public List<TrophyRecord> Trophies { get; set; } = [];
    public SeasonState? Season { get; set; }
    public int SeasonNumber { get; set; } = 1;
    public SeasonTransition? LastTransition { get; set; }

    public static GameState Fresh() => new();

    /// <summary>
    /// Deep copy used to keep the Swift build's copy-on-write mutation semantics: a failed
    /// operation must never leave the live state half-updated.
    /// </summary>
    public GameState Clone()
    {
        return new GameState
        {
            SchemaVersion = SchemaVersion,
            CreatedAt = CreatedAt,
            ManagedClubID = ManagedClubID,
            ClubCash = ClubCash,
            Xp = Xp,
            AvailableMatchMinutes = AvailableMatchMinutes,
            Study = new StudyStats
            {
                TotalStudyMinutes = Study.TotalStudyMinutes,
                TotalSessions = Study.TotalSessions,
                HomeworkCompleted = Study.HomeworkCompleted,
                PastPapersCompleted = Study.PastPapersCompleted,
                ExamQuestionsSolved = Study.ExamQuestionsSolved,
                CurrentStreak = Study.CurrentStreak,
                BestStreak = Study.BestStreak,
                LastStudyDay = Study.LastStudyDay
            },
            RecentSessions = RecentSessions.Select(session => session.Clone()).ToList(),
            Subtopics = Subtopics.Select(subtopic => subtopic.Clone()).ToList(),
            Players = Players.Select(player => player.Clone()).ToList(),
            FreeAgents = FreeAgents.Select(player => player.Clone()).ToList(),
            Lineup = new Dictionary<string, Guid>(Lineup),
            Bench = Bench.ToList(),
            Trophies = Trophies.ToList(),
            Season = Season?.Clone(),
            SeasonNumber = SeasonNumber,
            LastTransition = LastTransition is null
                ? null
                : new SeasonTransition
                {
                    Id = LastTransition.Id,
                    CompletedSeason = LastTransition.CompletedSeason,
                    ChampionName = LastTransition.ChampionName,
                    UserFinish = LastTransition.UserFinish,
                    Retirees = LastTransition.Retirees.ToList(),
                    YouthAdded = LastTransition.YouthAdded,
                    NewSeason = LastTransition.NewSeason
                }
        };
    }
}
