import Foundation

struct MatchTeam {
    let club: Club
    let rating: Double
    let scorers: [Player]
}

struct MatchSimulation {
    let report: MatchReport
    let winnerClubID: String?
}

enum MatchEngine {
    static func simulate(
        fixture: Fixture,
        home: MatchTeam,
        away: MatchTeam,
        season: Int,
        lineup: [String: UUID],
        playedAt: Date = Date()
    ) -> MatchSimulation {
        var generator = SeededGenerator(seed: StableSeed.value(for: "\(fixture.id.uuidString)-\(season)-\(fixture.phase.rawValue)"))
        let homeForm = Double.random(in: -1.2...1.2, using: &generator)
        let awayForm = Double.random(in: -1.2...1.2, using: &generator)
        let homeBoost = fixture.neutralVenue ? 0.0 : 2.0
        let difference = (home.rating + homeForm) - (away.rating + awayForm) + homeBoost

        let homeLambda = clamp(1.35 + difference * 0.075 + 0.10, lower: 0.25, upper: 4.2)
        let awayLambda = clamp(1.20 - difference * 0.065, lower: 0.20, upper: 3.8)

        var homeGoals = poisson(lambda: homeLambda, using: &generator)
        var awayGoals = poisson(lambda: awayLambda, using: &generator)
        var events: [MatchEvent] = []
        appendGoals(count: homeGoals, club: home.club, team: home, minuteRange: 1...90, isHome: true, using: &generator, to: &events)
        appendGoals(count: awayGoals, club: away.club, team: away, minuteRange: 1...90, isHome: false, using: &generator, to: &events)

        var homePenalties: Int?
        var awayPenalties: Int?

        if !fixture.phase.isKnockout || fixture.phase == .league {
            if fixture.phase == .league {
                events.sort { $0.minute < $1.minute }
                let summary = makeSummary(
                    home: home.club,
                    away: away.club,
                    homeGoals: homeGoals,
                    awayGoals: awayGoals,
                    homePenalties: nil,
                    awayPenalties: nil,
                    events: events,
                    neutral: fixture.neutralVenue
                )
                return buildSimulation(
                    fixture: fixture,
                    home: home,
                    away: away,
                    homeGoals: homeGoals,
                    awayGoals: awayGoals,
                    homePenalties: nil,
                    awayPenalties: nil,
                    events: events,
                    summary: summary,
                    playedAt: playedAt,
                    lineup: lineup
                )
            }
        } else {
            if homeGoals == awayGoals {
                let extraHome = poisson(lambda: homeLambda * 0.33, using: &generator)
                let extraAway = poisson(lambda: awayLambda * 0.33, using: &generator)
                homeGoals += extraHome
                awayGoals += extraAway
                appendGoals(count: extraHome, club: home.club, team: home, minuteRange: 91...120, isHome: true, using: &generator, to: &events)
                appendGoals(count: extraAway, club: away.club, team: away, minuteRange: 91...120, isHome: false, using: &generator, to: &events)

                if homeGoals == awayGoals {
                    let shootout = penaltyShootout(homeRating: home.rating, awayRating: away.rating, using: &generator)
                    homePenalties = shootout.home
                    awayPenalties = shootout.away
                }
            }
        }

        events.sort { $0.minute < $1.minute }
        let summary = makeSummary(
            home: home.club,
            away: away.club,
            homeGoals: homeGoals,
            awayGoals: awayGoals,
            homePenalties: homePenalties,
            awayPenalties: awayPenalties,
            events: events,
            neutral: fixture.neutralVenue
        )
        return buildSimulation(
            fixture: fixture,
            home: home,
            away: away,
            homeGoals: homeGoals,
            awayGoals: awayGoals,
            homePenalties: homePenalties,
            awayPenalties: awayPenalties,
            events: events,
            summary: summary,
            playedAt: playedAt,
            lineup: lineup
        )
    }

    static func userMetricsLineup(players: [Player], lineup: [String: UUID]) -> [Player] {
        LineupSlot.all.compactMap { slot in
            guard let id = lineup[slot.id] else { return nil }
            return players.first(where: { $0.id == id })
        }
    }

    private static func buildSimulation(
        fixture: Fixture,
        home: MatchTeam,
        away: MatchTeam,
        homeGoals: Int,
        awayGoals: Int,
        homePenalties: Int?,
        awayPenalties: Int?,
        events: [MatchEvent],
        summary: String,
        playedAt: Date,
        lineup: [String: UUID]
    ) -> MatchSimulation {
        let report = MatchReport(
            id: UUID(),
            fixtureID: fixture.id,
            phase: fixture.phase,
            round: fixture.round,
            homeClubID: home.club.id,
            awayClubID: away.club.id,
            homeGoals: homeGoals,
            awayGoals: awayGoals,
            homePenalties: homePenalties,
            awayPenalties: awayPenalties,
            events: events,
            homeRating: Int(home.rating.rounded()),
            awayRating: Int(away.rating.rounded()),
            summary: summary,
            playedAt: playedAt
        )
        return MatchSimulation(report: report, winnerClubID: report.winnerClubID)
    }

    private static func appendGoals(
        count: Int,
        club: Club,
        team: MatchTeam,
        minuteRange: ClosedRange<Int>,
        isHome: Bool,
        using generator: inout SeededGenerator,
        to events: inout [MatchEvent]
    ) {
        guard count > 0 else { return }
        for _ in 0..<count {
            let minute = Int.random(in: minuteRange, using: &generator)
            let scorer = selectScorer(from: team, club: club, using: &generator)
            let isPenalty = Int.random(in: 0..<100, using: &generator) < 8
            // Penalties have no assist; most open-play goals get one from a different teammate.
            var assister: String?
            if !isPenalty, Int.random(in: 0..<100, using: &generator) < 70 {
                assister = selectAssister(from: team, excluding: scorer, using: &generator)
            }
            events.append(
                MatchEvent(
                    id: UUID(),
                    minute: minute,
                    clubID: club.id,
                    scorer: scorer,
                    assister: assister,
                    isPenalty: isPenalty
                )
            )
        }
    }

    private static func selectAssister(
        from team: MatchTeam,
        excluding scorer: String,
        using generator: inout SeededGenerator
    ) -> String? {
        let candidates = team.scorers.filter { $0.name != scorer }
        guard !candidates.isEmpty else { return nil }
        let weighted = candidates.map { player -> (Player, Double) in
            let passingFactor = 0.55 + Double(player.attributes.passing) / 100.0
            return (player, player.position.scoringWeight * passingFactor * ratingFactor(for: player))
        }
        let total = weighted.reduce(0.0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &generator)
        for (player, weight) in weighted {
            if roll < weight { return player.name }
            roll -= weight
        }
        return weighted.last?.0.name
    }

    private static func selectScorer(from team: MatchTeam, club: Club, using generator: inout SeededGenerator) -> String {
        guard !team.scorers.isEmpty else {
            let fallbackPositions = ["Forward", "Midfielder", "Winger"]
            let label = fallbackPositions.randomElement(using: &generator) ?? "Forward"
            return "\(club.shortName) \(label)"
        }
        let weighted = team.scorers.map { player -> (Player, Double) in
            let shootingFactor = 0.55 + Double(player.attributes.shooting) / 100.0
            return (player, player.position.scoringWeight * shootingFactor * ratingFactor(for: player))
        }
        let total = weighted.reduce(0.0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &generator)
        for (player, weight) in weighted {
            if roll < weight { return player.name }
            roll -= weight
        }
        return weighted.last?.0.name ?? "Unknown Scorer"
    }

    /// Better players are proportionally more likely to score or assist, so the leaderboard
    /// follows player ratings rather than an even spread across the squad.
    private static func ratingFactor(for player: Player) -> Double {
        let normalised = Double(player.overall) / 70.0
        return normalised * normalised
    }

    private static func penaltyShootout(
        homeRating: Double,
        awayRating: Double,
        using generator: inout SeededGenerator
    ) -> (home: Int, away: Int) {
        let homeChance = clamp(0.73 + (homeRating - awayRating) * 0.006, lower: 0.56, upper: 0.91)
        let awayChance = clamp(0.73 + (awayRating - homeRating) * 0.006, lower: 0.56, upper: 0.91)
        var home = 0
        var away = 0
        for _ in 0..<5 {
            if Double.random(in: 0..<1, using: &generator) < homeChance { home += 1 }
            if Double.random(in: 0..<1, using: &generator) < awayChance { away += 1 }
        }
        while home == away {
            let homeScored = Double.random(in: 0..<1, using: &generator) < homeChance
            let awayScored = Double.random(in: 0..<1, using: &generator) < awayChance
            if homeScored { home += 1 }
            if awayScored { away += 1 }
        }
        return (home, away)
    }

    private static func poisson(lambda: Double, using generator: inout SeededGenerator) -> Int {
        let limit = exp(-max(0.01, lambda))
        var product = 1.0
        var count = 0
        repeat {
            count += 1
            product *= Double.random(in: 0..<1, using: &generator)
        } while product > limit && count < 12
        return count - 1
    }

    private static func makeSummary(
        home: Club,
        away: Club,
        homeGoals: Int,
        awayGoals: Int,
        homePenalties: Int?,
        awayPenalties: Int?,
        events: [MatchEvent],
        neutral: Bool
    ) -> String {
        let venue = neutral ? "in the final" : "at \(home.name)"
        let topScorerLine: String
        var counts: [String: Int] = [:]
        for event in events {
            counts[event.scorer, default: 0] += 1
        }
        if let top = counts.max(by: { $0.value < $1.value }), top.value > 1 {
            topScorerLine = " \(top.key) scored \(top.value)."
        } else {
            topScorerLine = ""
        }

        if homeGoals == awayGoals && homePenalties == nil {
            return "\(home.name) and \(away.name) played out a \(homeGoals)-\(awayGoals) draw \(venue).\(topScorerLine)"
        }

        let winner: Club
        let winnerGoals: Int
        let loserGoals: Int
        if homeGoals > awayGoals {
            winner = home
            winnerGoals = homeGoals
            loserGoals = awayGoals
        } else if awayGoals > homeGoals {
            winner = away
            winnerGoals = awayGoals
            loserGoals = homeGoals
        } else if let homePenalties, let awayPenalties {
            if homePenalties > awayPenalties {
                winner = home
                winnerGoals = homeGoals
                loserGoals = awayGoals
            } else {
                winner = away
                winnerGoals = awayGoals
                loserGoals = homeGoals
            }
        } else {
            return "\(home.name) and \(away.name) finished level."
        }

        let loser = winner.id == home.id ? away : home
        var sentence = "\(winner.name) beat \(loser.name) \(winnerGoals)-\(loserGoals) \(venue)."
        if let homePenalties, let awayPenalties {
            sentence += " The tie was decided \(max(homePenalties, awayPenalties))-\(min(homePenalties, awayPenalties)) on penalties."
        }
        sentence += topScorerLine
        return sentence
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}
