namespace StudyManagerFC.Core;

/// <summary>
/// SplitMix64, the same generator the Swift build uses for its seeded rolls.
/// </summary>
public struct SeededGenerator
{
    private ulong _state;

    public SeededGenerator(ulong seed)
    {
        _state = seed == 0 ? 0x9E3779B97F4A7C15UL : seed;
    }

    public ulong Next()
    {
        unchecked
        {
            _state += 0x9E3779B97F4A7C15UL;
            var value = _state;
            value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9UL;
            value = (value ^ (value >> 27)) * 0x94D049BB133111EBUL;
            return value ^ (value >> 31);
        }
    }

    /// <summary>Uniform double in [0, 1).</summary>
    public double NextDouble() => (Next() >> 11) * (1.0 / (1UL << 53));

    /// <summary>Uniform integer in [min, max] (inclusive).</summary>
    public int NextInt(int min, int max)
    {
        if (max <= min) return min;
        var span = (ulong)((long)max - min + 1);
        var limit = ulong.MaxValue - ulong.MaxValue % span;
        ulong roll;
        do
        {
            roll = Next();
        } while (roll >= limit);
        return min + (int)(roll % span);
    }

    public T Pick<T>(IReadOnlyList<T> items) => items[NextInt(0, items.Count - 1)];
}

public static class StableSeed
{
    public static ulong Value(string text, ulong salt = 0)
    {
        unchecked
        {
            var hash = 1469598103934665603UL;
            foreach (var b in System.Text.Encoding.UTF8.GetBytes(text))
            {
                hash ^= b;
                hash *= 1099511628211UL;
            }
            return hash ^ (salt * 0x9E3779B97F4A7C15UL);
        }
    }
}

public static class PlayerFactory
{
    public static readonly PlayerPosition[] StarterPositions =
    [
        PlayerPosition.Goalkeeper, PlayerPosition.Goalkeeper,
        PlayerPosition.LeftBack, PlayerPosition.CenterBack, PlayerPosition.CenterBack, PlayerPosition.CenterBack,
        PlayerPosition.RightBack,
        PlayerPosition.DefensiveMid, PlayerPosition.CentralMid, PlayerPosition.CentralMid, PlayerPosition.AttackingMid,
        PlayerPosition.LeftWing, PlayerPosition.LeftWing, PlayerPosition.Striker, PlayerPosition.Striker,
        PlayerPosition.RightWing,
        PlayerPosition.CenterBack, PlayerPosition.CentralMid
    ];

    private static readonly PlayerRarity[] FreeAgentRarities =
    [
        PlayerRarity.Bronze, PlayerRarity.Bronze, PlayerRarity.Bronze, PlayerRarity.Bronze,
        PlayerRarity.Bronze, PlayerRarity.Bronze, PlayerRarity.Bronze, PlayerRarity.Bronze,
        PlayerRarity.Silver, PlayerRarity.Silver, PlayerRarity.Silver, PlayerRarity.Silver,
        PlayerRarity.Silver, PlayerRarity.Silver, PlayerRarity.Silver, PlayerRarity.Silver, PlayerRarity.Silver,
        PlayerRarity.Gold, PlayerRarity.Gold, PlayerRarity.Gold, PlayerRarity.Gold, PlayerRarity.Gold, PlayerRarity.Gold,
        PlayerRarity.Wonderkid, PlayerRarity.Wonderkid,
        PlayerRarity.Icon
    ];

    public static List<Player> StarterSquad(Club club, int season)
    {
        var generator = new SeededGenerator(StableSeed.Value($"starter-{club.Id}-{season}"));
        var squad = new List<Player>();
        for (var index = 0; index < StarterPositions.Length; index++)
        {
            var position = StarterPositions[index];
            var ratingOffset = generator.NextInt(-4, 3);
            var target = Math.Min(94, Math.Max(58, club.Rating + ratingOffset - (index >= 16 ? 2 : 0)));
            var nationCode = StarterNation(club, ref generator);
            squad.Add(MakePlayer(
                target,
                position,
                nationCode,
                season,
                index >= 16 ? (18, 23) : (20, 32),
                null,
                false,
                ref generator));
        }
        return squad;
    }

    public static List<Player> AiRoster(Club club, int season)
    {
        var generator = new SeededGenerator(StableSeed.Value($"ai-{club.Id}-{season}"));
        PlayerPosition[] positions =
        [
            PlayerPosition.Goalkeeper, PlayerPosition.Goalkeeper, PlayerPosition.LeftBack, PlayerPosition.CenterBack,
            PlayerPosition.CenterBack, PlayerPosition.RightBack, PlayerPosition.DefensiveMid, PlayerPosition.CentralMid,
            PlayerPosition.CentralMid, PlayerPosition.AttackingMid, PlayerPosition.LeftWing, PlayerPosition.Striker,
            PlayerPosition.Striker, PlayerPosition.RightWing, PlayerPosition.CenterBack, PlayerPosition.CentralMid
        ];
        var roster = new List<Player>();
        for (var index = 0; index < positions.Length; index++)
        {
            var offset = generator.NextInt(-5, 3);
            var nationCode = StarterNation(club, ref generator);
            roster.Add(MakePlayer(
                Math.Min(94, Math.Max(55, club.Rating + offset - (index >= 14 ? 3 : 0))),
                positions[index],
                nationCode,
                season,
                (19, 32),
                null,
                false,
                ref generator));
        }
        return roster;
    }

    public static List<Player> MakeFreeAgentPool(int season, int count)
    {
        var generator = new SeededGenerator(StableSeed.Value($"free-agents-{season}"));
        var pool = new List<Player>();
        for (var index = 0; index < count; index++)
        {
            var rarity = generator.Pick(FreeAgentRarities);
            var position = generator.Pick(PlayerPositionExtensions.All);
            var nation = generator.Pick(Nations.All).Code;
            pool.Add(MakePlayer(null, position, nation, season, null, rarity, false, ref generator));
        }
        return pool;
    }

    public static List<Player> MakeYouthProspects(int season, int count)
    {
        var generator = new SeededGenerator(StableSeed.Value($"youth-{season}"));
        var prospects = new List<Player>();
        for (var index = 0; index < count; index++)
        {
            var position = generator.Pick(PlayerPositionExtensions.All);
            var nation = generator.Pick(Nations.All).Code;
            var forced = generator.NextInt(0, 1) == 1 ? PlayerRarity.Wonderkid : PlayerRarity.Gold;
            prospects.Add(MakePlayer(null, position, nation, season, (16, 18), forced, true, ref generator));
        }
        return prospects;
    }

    /// <summary>
    /// Prospects promoted straight into the senior squad. They arrive as raw teenagers
    /// with high ceilings rather than ready-made first-team players.
    /// </summary>
    public static List<Player> MakeAcademyProspects(int season, int count)
    {
        var generator = new SeededGenerator(StableSeed.Value($"academy-{season}"));
        var prospects = new List<Player>();
        for (var index = 0; index < count; index++)
        {
            var position = generator.Pick(PlayerPositionExtensions.All);
            var nation = generator.Pick(Nations.All).Code;
            prospects.Add(MakePlayer(
                generator.NextInt(58, 68),
                position,
                nation,
                season,
                (16, 18),
                null,
                true,
                ref generator));
        }
        return prospects;
    }

    public static Player MakePackPlayer(PlayerRarity rarity, int season, Random? random = null)
    {
        random ??= Random.Shared;
        var seed = (ulong)random.NextInt64(1, long.MaxValue);
        var generator = new SeededGenerator(seed);
        var position = generator.Pick(PlayerPositionExtensions.All);
        var nation = generator.Pick(Nations.All).Code;
        return MakePlayer(null, position, nation, season, null, rarity, rarity == PlayerRarity.Wonderkid, ref generator);
    }

    public static Player MakePlayer(
        int? targetOverall,
        PlayerPosition position,
        string nationCode,
        int season,
        (int Min, int Max)? ageRange,
        PlayerRarity? forcedRarity,
        bool highPotential,
        ref SeededGenerator generator)
    {
        var rarity = forcedRarity ?? PlayerRarity.Silver;
        var overall = targetOverall ?? generator.NextInt(OverallRange(rarity).Min, OverallRange(rarity).Max);
        var age = ageRange.HasValue
            ? generator.NextInt(ageRange.Value.Min, ageRange.Value.Max)
            : generator.NextInt(DefaultAgeRange(rarity).Min, DefaultAgeRange(rarity).Max);
        var resolvedRarity = SkillBasedRarity(overall, age, rarity, highPotential, ref generator);
        var potential = MakePotential(overall, age, highPotential || resolvedRarity == PlayerRarity.Wonderkid, ref generator);
        var finalRarity = forcedRarity ?? resolvedRarity;
        var name = MakeName(nationCode, ref generator);
        var attributes = MakeAttributes(overall, position, ref generator);

        return new Player
        {
            Id = Guid.NewGuid(),
            Name = name,
            NationCode = nationCode,
            Position = position,
            Age = age,
            Overall = overall,
            Potential = potential,
            Rarity = finalRarity,
            Attributes = attributes,
            RetirementAge = GameRules.RetirementAge,
            JoinedSeason = season
        };
    }

    /// <summary>
    /// The player a transfer listing becomes once signed. Deterministic for a given
    /// club, player and season, so the market can preview potential before a fee is paid.
    /// </summary>
    public static Player TransferPlayer(StarterSeed seed, string clubId, int season)
    {
        var generator = new SeededGenerator(StableSeed.Value($"transfer-{clubId}-{seed.Name}-{season}"));
        var ageRange = seed.Rating >= 88 ? (24, 30) : seed.Rating >= 84 ? (22, 29) : (21, 28);
        var age = generator.NextInt(ageRange.Item1, ageRange.Item2);
        var rarity = seed.Rating >= 90 ? PlayerRarity.Icon
            : seed.Rating >= 86 ? PlayerRarity.Gold
            : seed.Rating >= 82 ? PlayerRarity.Silver
            : PlayerRarity.Bronze;
        var potentialBoost = generator.NextInt(2, 6);
        var potential = Math.Min(99, seed.Rating + potentialBoost);
        var bias = seed.Position.Bias();

        int Attribute(int adjustment) =>
            Math.Min(99, Math.Max(40, seed.Rating + adjustment + generator.NextInt(-3, 4)));

        return new Player
        {
            Id = Guid.NewGuid(),
            Name = seed.Name,
            NationCode = seed.NationCode,
            Position = seed.Position,
            Age = age,
            Overall = seed.Rating,
            Potential = potential,
            Rarity = rarity,
            Attributes = new PlayerAttributes(
                Attribute(bias.Pace),
                Attribute(bias.Shooting),
                Attribute(bias.Passing),
                Attribute(bias.Defending),
                Attribute(bias.Physical)),
            RetirementAge = GameRules.RetirementAge,
            JoinedSeason = season
        };
    }

    public static string MakeName(string nationCode, ref SeededGenerator generator)
    {
        var pool = NameDatabase.Pool(nationCode);
        var first = generator.Pick(pool.First);
        var last = generator.Pick(pool.Last);
        return $"{first} {last}";
    }

    public static (Dictionary<string, Guid> Lineup, List<Guid> Bench) AutoLineup(IReadOnlyList<Player> players)
    {
        var used = new HashSet<Guid>();
        var lineup = new Dictionary<string, Guid>();

        foreach (var slot in LineupSlot.All)
        {
            Player? candidate = null;
            var best = int.MinValue;
            var bestPotential = int.MinValue;
            foreach (var player in players)
            {
                if (used.Contains(player.Id)) continue;
                var rating = player.AdjustedRating(slot);
                if (rating > best || (rating == best && player.Potential > bestPotential))
                {
                    candidate = player;
                    best = rating;
                    bestPotential = player.Potential;
                }
            }

            if (candidate is null) continue;
            lineup[slot.Id] = candidate.Id;
            used.Add(candidate.Id);
        }

        var bench = players
            .Where(player => !used.Contains(player.Id))
            .OrderByDescending(player => player.Overall)
            .Take(GameRules.BenchLimit)
            .Select(player => player.Id)
            .ToList();

        return (lineup, bench);
    }

    private static string StarterNation(Club club, ref SeededGenerator generator)
    {
        if (generator.NextInt(0, 99) < 42) return club.CountryCode;
        return generator.Pick(Nations.All).Code;
    }

    private static PlayerRarity SkillBasedRarity(
        int overall,
        int age,
        PlayerRarity seedRarity,
        bool highPotential,
        ref SeededGenerator generator)
    {
        _ = generator;
        if (highPotential && age <= 20) return PlayerRarity.Wonderkid;
        if (seedRarity == PlayerRarity.Wonderkid && age <= 21) return PlayerRarity.Wonderkid;
        if (overall >= 86) return PlayerRarity.Icon;
        if (overall >= 78) return PlayerRarity.Gold;
        if (overall >= 70) return PlayerRarity.Silver;
        return PlayerRarity.Bronze;
    }

    private static (int Min, int Max) OverallRange(PlayerRarity rarity) => rarity switch
    {
        PlayerRarity.Bronze => (58, 68),
        PlayerRarity.Silver => (68, 77),
        PlayerRarity.Gold => (77, 85),
        PlayerRarity.Wonderkid => (66, 78),
        _ => (86, 93)
    };

    private static (int Min, int Max) DefaultAgeRange(PlayerRarity rarity) => rarity switch
    {
        PlayerRarity.Bronze => (19, 31),
        PlayerRarity.Silver => (20, 32),
        PlayerRarity.Gold => (21, 33),
        PlayerRarity.Wonderkid => (16, 19),
        _ => (26, 34)
    };

    private static int MakePotential(int overall, int age, bool highPotential, ref SeededGenerator generator)
    {
        var boost = highPotential ? generator.NextInt(12, 22)
            : age <= 18 ? generator.NextInt(10, 20)
            : age <= 21 ? generator.NextInt(6, 14)
            : age <= 24 ? generator.NextInt(2, 8)
            : age <= 28 ? generator.NextInt(0, 4)
            : generator.NextInt(0, 1);
        return Math.Min(99, overall + boost);
    }

    private static PlayerAttributes MakeAttributes(int overall, PlayerPosition position, ref SeededGenerator generator)
    {
        var bias = position.Bias();
        var pace = Math.Min(99, Math.Max(25, overall + bias.Pace + generator.NextInt(-5, 5)));
        var shooting = Math.Min(99, Math.Max(25, overall + bias.Shooting + generator.NextInt(-5, 5)));
        var passing = Math.Min(99, Math.Max(25, overall + bias.Passing + generator.NextInt(-5, 5)));
        var defending = Math.Min(99, Math.Max(25, overall + bias.Defending + generator.NextInt(-5, 5)));
        var physical = Math.Min(99, Math.Max(25, overall + bias.Physical + generator.NextInt(-5, 5)));
        return new PlayerAttributes(pace, shooting, passing, defending, physical);
    }
}
