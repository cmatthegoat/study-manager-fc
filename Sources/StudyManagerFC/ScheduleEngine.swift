import Foundation

enum ScheduleEngine {
    private struct PotPairing {
        let firstPot: Int
        let secondPot: Int
        let homePot: Int
    }

    private static let roundPlan: [[PotPairing]] = [
        [PotPairing(firstPot: 0, secondPot: 1, homePot: 0), PotPairing(firstPot: 2, secondPot: 3, homePot: 2)],
        [PotPairing(firstPot: 0, secondPot: 2, homePot: 0), PotPairing(firstPot: 1, secondPot: 3, homePot: 1)],
        [PotPairing(firstPot: 0, secondPot: 3, homePot: 3), PotPairing(firstPot: 1, secondPot: 2, homePot: 2)],
        [PotPairing(firstPot: 0, secondPot: 1, homePot: 1), PotPairing(firstPot: 2, secondPot: 3, homePot: 3)],
        [PotPairing(firstPot: 0, secondPot: 2, homePot: 0), PotPairing(firstPot: 1, secondPot: 3, homePot: 1)],
        [PotPairing(firstPot: 0, secondPot: 3, homePot: 3), PotPairing(firstPot: 1, secondPot: 2, homePot: 2)],
        [PotPairing(firstPot: 0, secondPot: 2, homePot: 2), PotPairing(firstPot: 1, secondPot: 3, homePot: 3)],
        [PotPairing(firstPot: 0, secondPot: 3, homePot: 0), PotPairing(firstPot: 1, secondPot: 2, homePot: 1)]
    ]

    static func makeLeagueFixtures(season: Int) -> [Fixture] {
        var generator = SeededGenerator(seed: StableSeed.value(for: "schedule-\(season)"))
        var pots = ClubDatabase.seededPots
        for index in pots.indices {
            pots[index].shuffle(using: &generator)
        }

        var fixtures: [Fixture] = []
        for (roundIndex, pairings) in roundPlan.enumerated() {
            for (pairIndex, pairing) in pairings.enumerated() {
                let firstPot = pots[pairing.firstPot]
                let secondPot = pots[pairing.secondPot]
                let shift = (season + roundIndex * 2 + pairIndex * 3) % 9
                for index in 0..<9 {
                    let firstClub = firstPot[index]
                    let secondClub = secondPot[(index + shift) % 9]
                    let home: Club
                    let away: Club
                    if pairing.homePot == pairing.firstPot {
                        home = firstClub
                        away = secondClub
                    } else {
                        home = secondClub
                        away = firstClub
                    }
                    fixtures.append(
                        Fixture(
                            id: UUID(),
                            homeClubID: home.id,
                            awayClubID: away.id,
                            phase: .league,
                            round: roundIndex + 1,
                            neutralVenue: false,
                            homeGoals: nil,
                            awayGoals: nil,
                            homePenalties: nil,
                            awayPenalties: nil
                        )
                    )
                }
            }
            fixtures[fixtures.count - 18..<fixtures.count].shuffle(using: &generator)
        }
        return fixtures
    }

    static func makePlayoffFixtures(standings: [StandingRow], season: Int) -> [Fixture] {
        guard standings.count == 36 else { return [] }
        var fixtures: [Fixture] = []
        for index in 0..<8 {
            let higher = standings[8 + index]
            let lower = standings[23 - index]
            fixtures.append(
                Fixture(
                    id: UUID(),
                    homeClubID: higher.club.id,
                    awayClubID: lower.club.id,
                    phase: .playoffs,
                    round: 1,
                    neutralVenue: false,
                    homeGoals: nil,
                    awayGoals: nil,
                    homePenalties: nil,
                    awayPenalties: nil
                )
            )
        }
        return fixtures
    }

    static func makeRoundOf16(standings: [StandingRow], playoffFixtures: [Fixture], season: Int) -> [Fixture] {
        guard standings.count == 36, playoffFixtures.count == 8 else { return [] }
        let rankByID = Dictionary(uniqueKeysWithValues: standings.enumerated().map { ($0.element.club.id, $0.offset) })
        let winners = playoffFixtures.compactMap(\.winnerClubID)
            .sorted { (rankByID[$0] ?? 99) < (rankByID[$1] ?? 99) }
        guard winners.count == 8 else { return [] }

        let topEight = standings.prefix(8)
        var fixtures: [Fixture] = []
        for index in 0..<8 {
            let home = topEight[index].club
            let awayID = winners[7 - index]
            guard let away = ClubDatabase.club(for: awayID) else { continue }
            fixtures.append(
                Fixture(
                    id: UUID(),
                    homeClubID: home.id,
                    awayClubID: away.id,
                    phase: .roundOf16,
                    round: 1,
                    neutralVenue: false,
                    homeGoals: nil,
                    awayGoals: nil,
                    homePenalties: nil,
                    awayPenalties: nil
                )
            )
        }
        return fixtures
    }

    static func makeNextKnockoutRound(from previousFixtures: [Fixture], phase: SeasonPhase, standings: [StandingRow], season: Int) -> [Fixture] {
        let winners = previousFixtures.compactMap(\.winnerClubID)
        guard winners.count == previousFixtures.count, winners.count >= 2 else { return [] }
        let rankByID = Dictionary(uniqueKeysWithValues: standings.enumerated().map { ($0.element.club.id, $0.offset) })
        var fixtures: [Fixture] = []
        var index = 0
        while index + 1 < winners.count {
            let firstID = winners[index]
            let secondID = winners[index + 1]
            let firstRank = rankByID[firstID] ?? 99
            let secondRank = rankByID[secondID] ?? 99
            let homeID = firstRank <= secondRank ? firstID : secondID
            let awayID = firstRank <= secondRank ? secondID : firstID
            fixtures.append(
                Fixture(
                    id: UUID(),
                    homeClubID: homeID,
                    awayClubID: awayID,
                    phase: phase,
                    round: 1,
                    neutralVenue: phase == .final,
                    homeGoals: nil,
                    awayGoals: nil,
                    homePenalties: nil,
                    awayPenalties: nil
                )
            )
            index += 2
        }
        return fixtures
    }
}

enum StandingsEngine {
    static func standings(fixtures: [Fixture]) -> [StandingRow] {
        var rows: [String: StandingRow] = [:]
        for club in ClubDatabase.all {
            rows[club.id] = StandingRow(
                club: club,
                played: 0,
                won: 0,
                drawn: 0,
                lost: 0,
                goalsFor: 0,
                goalsAgainst: 0,
                points: 0
            )
        }

        for fixture in fixtures where fixture.phase == .league && fixture.isSimulated {
            guard let homeGoals = fixture.homeGoals, let awayGoals = fixture.awayGoals else { continue }
            guard var home = rows[fixture.homeClubID], var away = rows[fixture.awayClubID] else { continue }
            home.played += 1
            away.played += 1
            home.goalsFor += homeGoals
            home.goalsAgainst += awayGoals
            away.goalsFor += awayGoals
            away.goalsAgainst += homeGoals
            if homeGoals > awayGoals {
                home.won += 1
                home.points += 3
                away.lost += 1
            } else if awayGoals > homeGoals {
                away.won += 1
                away.points += 3
                home.lost += 1
            } else {
                home.drawn += 1
                away.drawn += 1
                home.points += 1
                away.points += 1
            }
            rows[fixture.homeClubID] = home
            rows[fixture.awayClubID] = away
        }

        return rows.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.goalDifference != $1.goalDifference { return $0.goalDifference > $1.goalDifference }
            if $0.goalsFor != $1.goalsFor { return $0.goalsFor > $1.goalsFor }
            if $0.won != $1.won { return $0.won > $1.won }
            return $0.club.name < $1.club.name
        }
    }

    static func position(for clubID: String, in standings: [StandingRow]) -> Int {
        (standings.firstIndex(where: { $0.club.id == clubID }) ?? 35) + 1
    }
}
