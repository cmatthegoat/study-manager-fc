import Foundation

enum SeasonEngine {
    static func newSeason(number: Int) -> SeasonState {
        var season = SeasonState.new(number: number)
        season.fixtures = ScheduleEngine.makeLeagueFixtures(season: number)
        return season
    }

    static func nextPhase(after phase: SeasonPhase) -> SeasonPhase {
        switch phase {
        case .league: .playoffs
        case .playoffs: .roundOf16
        case .roundOf16: .quarterfinal
        case .quarterfinal: .semifinal
        case .semifinal: .final
        case .final, .complete: .complete
        }
    }

    static func userFinish(
        userClubID: String,
        standings: [StandingRow],
        fixtures: [Fixture],
        championClubID: String?
    ) -> String {
        if championClubID == userClubID { return "Champions" }
        if let final = fixtures.first(where: { $0.phase == .final && ($0.homeClubID == userClubID || $0.awayClubID == userClubID) }), final.isSimulated {
            return "Runners-up"
        }
        if fixtures.contains(where: { $0.phase == .semifinal && ($0.homeClubID == userClubID || $0.awayClubID == userClubID) }) {
            return "Semi-finalists"
        }
        if fixtures.contains(where: { $0.phase == .quarterfinal && ($0.homeClubID == userClubID || $0.awayClubID == userClubID) }) {
            return "Quarter-finalists"
        }
        if fixtures.contains(where: { $0.phase == .roundOf16 && ($0.homeClubID == userClubID || $0.awayClubID == userClubID) }) {
            return "Round of 16"
        }
        if fixtures.contains(where: { $0.phase == .playoffs && ($0.homeClubID == userClubID || $0.awayClubID == userClubID) }) {
            return "Knockout playoff"
        }
        let rank = StandingsEngine.position(for: userClubID, in: standings)
        return "League phase — \(ordinal(rank))"
    }

    /// Top goalscorer and top assister across one season's simulated matches.
    static func individualAwards(for season: SeasonState) -> (scorer: PlayerScoringRecord?, assister: PlayerScoringRecord?) {
        var ledger: [PlayerScoringRecord] = []
        ledger.record(reports: season.reports)
        let scorer = ledger.filter { $0.goals > 0 }.max { $0.goals < $1.goals }
        let assister = ledger.filter { $0.assists > 0 }.max { $0.assists < $1.assists }
        return (scorer, assister)
    }

    static func makeTrophyRecord(
        season: SeasonState,
        userClub: Club,
        standings: [StandingRow]
    ) -> TrophyRecord? {
        guard let championID = season.championClubID,
              let champion = ClubDatabase.club(for: championID),
              let runnerUpID = season.runnerUpClubID,
              let runnerUp = ClubDatabase.club(for: runnerUpID)
        else { return nil }

        let finish = userFinish(
            userClubID: userClub.id,
            standings: standings,
            fixtures: season.fixtures,
            championClubID: season.championClubID
        )
        let awards = individualAwards(for: season)
        return TrophyRecord(
            id: UUID(),
            seasonNumber: season.number,
            championClubID: champion.id,
            championName: champion.name,
            runnerUpClubID: runnerUp.id,
            runnerUpName: runnerUp.name,
            userClubID: userClub.id,
            userClubName: userClub.name,
            userFinish: finish,
            userWasChampion: champion.id == userClub.id,
            completedAt: Date(),
            topScorerName: awards.scorer?.name,
            topScorerClubName: awards.scorer.flatMap { ClubDatabase.club(for: $0.clubID)?.name },
            topScorerGoals: awards.scorer?.goals,
            topAssisterName: awards.assister?.name,
            topAssisterClubName: awards.assister.flatMap { ClubDatabase.club(for: $0.clubID)?.name },
            topAssisterAssists: awards.assister?.assists
        )
    }

    static func ordinal(_ value: Int) -> String {
        let suffix: String
        if value % 100 >= 11 && value % 100 <= 13 {
            suffix = "th"
        } else {
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(value)\(suffix)"
    }
}
