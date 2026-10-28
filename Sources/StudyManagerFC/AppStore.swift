import Foundation
import Observation

enum GameError: LocalizedError {
    case noCareer
    case noSeason
    case seasonComplete
    case invalidClub
    case lineupIncomplete
    case insufficientStudy(Int)
    case insufficientFunds
    case levelTooLow(Int)
    case invalidPack
    case academyMaxLevel
    case noFixtures
    case invalidState
    case playerNotFound

    var errorDescription: String? {
        switch self {
        case .noCareer: "Choose a club before starting."
        case .noSeason: "There is no active season."
        case .seasonComplete: "This season is already complete."
        case .invalidClub: "That club is not in the competition."
        case .lineupIncomplete: "Complete your starting XI before playing a match."
        case .insufficientStudy(let minutes): "You need \(minutes) more study minutes to unlock this match."
        case .insufficientFunds: "You do not have enough Club Cash."
        case .levelTooLow(let level): "Reach level \(level) to unlock this pack."
        case .invalidPack: "That pack is not available."
        case .academyMaxLevel: "Your youth academy is already at its highest level."
        case .noFixtures: "There are no fixtures ready to simulate."
        case .invalidState: "The season could not advance."
        case .playerNotFound: "That player is no longer at the club."
        }
    }
}

struct SimulationOutcome {
    let userReport: MatchReport?
    let simulatedCount: Int
    let phasePlayed: SeasonPhase
    let championClub: Club?
    let trophy: TrophyRecord?
}

struct LevelUpAnnouncement: Equatable {
    let level: Int
    let bonus: Int
}

@MainActor
@Observable
final class AppStore {
    private(set) var state: GameState
    var isTimerRunning: Bool
    var timerElapsedSeconds: Int
    var saveErrorMessage: String?
    var lastTimerSessionMinutes: Int
    /// What the focus timer is logging to. Chosen before starting; applied when paused.
    var timerSubject: StudySubject = .other
    var timerSubtopicID: UUID?
    /// Focus by default; set to homework, past paper or exam questions to log that work instead.
    var timerKind: StudyActivityKind = .focusSession
    var timerMarksObtained: Int?
    var timerMarksTotal: Int?
    /// The homework task the timer is working on. Its subject and topic are applied when chosen.
    var timerTodoID: UUID?
    /// Set when a player levels up, so the level-up popup can congratulate the user.
    var levelUpAnnouncement: LevelUpAnnouncement?

    @ObservationIgnored private let persistence: PersistenceStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var timerCreditedMinutes: Int
    /// Guards against the diagnostic self-test re-entering through its own AppStore.
    @ObservationIgnored private static var selfTestRunning = false

    init(persistence: PersistenceStore = PersistenceStore()) {
        self.persistence = persistence
        self.isTimerRunning = false
        self.timerElapsedSeconds = 0
        self.saveErrorMessage = nil
        self.lastTimerSessionMinutes = 0
        self.timerCreditedMinutes = 0

        if CommandLine.arguments.contains("--verify-save") {
            Self.verifySaveAndExit(persistence)
        }
        if CommandLine.arguments.contains("--self-test"), !Self.selfTestRunning {
            Self.runSelfTest()
        }

        do {
            state = try persistence.load() ?? GameState.fresh()
        } catch {
            state = GameState.fresh()
            saveErrorMessage = "The previous save could not be read. A fresh career was created and the old file was preserved."
        }
        migrateLegacySaveIfNeeded()
        TeamTheme.club = managedClub
    }

    /// Prints whether the saved career on disk can be decoded by the current models.
    /// Used to diagnose saves that silently fall back to a fresh career.
    private static func verifySaveAndExit(_ persistence: PersistenceStore) {
        do {
            if let state = try persistence.load() {
                print("SAVE OK club=\(state.managedClubID ?? "nil") cash=\(state.clubCash) xp=\(state.xp) players=\(state.players.count) sessions=\(state.recentSessions.count) subtopics=\(state.subtopics.count) todos=\(state.todos.count)")
            } else {
                print("NO SAVE FILE at \(persistence.saveURL.path)")
            }
        } catch {
            print("SAVE DECODE FAILED: \(error)")
        }
        exit(0)
    }

    /// Exercises todo rewards, todo persistence and study-log deletion against a
    /// throwaway save directory.
    private static func runSelfTest() {
        Self.selfTestRunning = true

        // The shipped data file must carry real ceilings: a file where every player is
        // already at their potential leaves the whole database unable to grow.
        let databasePlayers = FcDatabase.shared.players
        let withRoom = databasePlayers.filter { $0.pot > $0.ovr }.count
        guard databasePlayers.count > 1_000, Double(withRoom) / Double(databasePlayers.count) > 0.5 else {
            print("SELF TEST FAIL: fc-database potentials look unfilled (\(withRoom)/\(databasePlayers.count) with room to grow)")
            exit(1)
        }
        let young = databasePlayers.filter { $0.age <= 21 }
        let youngWithRoom = young.filter { $0.pot > $0.ovr }.count
        guard young.isEmpty || Double(youngWithRoom) / Double(young.count) > 0.95 else {
            print("SELF TEST FAIL: young database players cannot still grow (\(youngWithRoom)/\(young.count))")
            exit(1)
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("StudyManagerFC-self-test-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = PersistenceStore(baseDirectory: tempDir)
        let topic = Subtopic(id: UUID(), subject: .ext1Maths, name: "Vectors", createdAt: Date())
        var state = GameState.fresh()
        state.managedClubID = "barcelona"
        state.subtopics = [topic]
        state.todos = [
            TodoItem(id: UUID(), title: "Finish 2.5", subject: .ext1Maths, subtopicID: topic.id, subtopicName: topic.name, isCompleted: false, createdAt: Date(), dueDate: nil)
        ]
        let session = StudySession(id: UUID(), date: Date(), kind: .homework, title: "Test log", minutes: 30, cashEarned: 10, xpEarned: 5, quantity: 1, subject: .ext1Maths, marksObtained: nil, marksTotal: nil, subtopicID: topic.id, subtopicName: topic.name)
        state.recentSessions = [session]
        do {
            try store.save(state)
            guard let loaded = try store.load(), loaded.todos.count == 1, loaded.todos[0].subtopicName == "Vectors" else {
                print("SELF TEST FAIL: todo did not round-trip")
                exit(1)
            }

            let app = AppStore(persistence: PersistenceStore(baseDirectory: tempDir))
            let startingCash = app.state.clubCash
            let expectedReward = Int((Double(GameRules.clubCashPerTodo) * StudySubject.ext1Maths.cashMultiplier).rounded())
            let todoID = app.state.todos[0].id

            app.toggleTodo(todoID)
            guard app.state.todos[0].isCompleted, app.state.todos[0].rewardAwarded, app.state.clubCash == startingCash + expectedReward else {
                print("SELF TEST FAIL: completing a todo did not pay \(expectedReward) cash")
                exit(1)
            }

            // Re-toggling must not pay the reward twice.
            app.toggleTodo(todoID)
            app.toggleTodo(todoID)
            guard app.state.clubCash == startingCash + expectedReward else {
                print("SELF TEST FAIL: todo reward could be farmed")
                exit(1)
            }

            // Inline directives: `p2 #Ext 1 Maths - Vectors: do 3.2`
            let parsed = TodoInput.parse("p2 #Ext 1 Maths - Vectors: do 3.2", subtopics: [topic])
            guard parsed.subject == .ext1Maths, parsed.subtopicName == "Vectors", parsed.priority == 2, parsed.title == "do 3.2" else {
                print("SELF TEST FAIL: inline directives did not parse (\(parsed))")
                exit(1)
            }

            // A new topic named in the task line is created and attached.
            guard let urgent = app.addTodo("p1 #Physics - Waves: draw a ray diagram"),
                  urgent.subject == .physics,
                  urgent.priority == 1,
                  urgent.subtopicName == "Waves",
                  app.state.subtopics.contains(where: { $0.subject == .physics && $0.name == "Waves" }) else {
                print("SELF TEST FAIL: #subject - topic did not file the task")
                exit(1)
            }

            // Sorting: open tasks first, then P1, P2, P4, unmarked.
            _ = app.addTodo("p4 #Ext 1 Maths: tidy notes")
            _ = app.addTodo("p2 #Ext 1 Maths: revise proofs")
            let openPriorities = app.todos(for: .ext1Maths).filter { !$0.isCompleted }.map { $0.priority ?? 0 }
            guard openPriorities == [2, 4] else {
                print("SELF TEST FAIL: priority order was \(openPriorities)")
                exit(1)
            }

            app.deleteStudySession(session.id)
            guard let reloaded = try store.load(),
                  reloaded.todos.count == 4,
                  reloaded.todos.contains(where: { $0.id == todoID && $0.isCompleted }),
                  reloaded.todos.contains(where: { $0.priority == 1 && $0.subtopicName == "Waves" }),
                  reloaded.subtopics.contains(where: { $0.name == "Waves" }),
                  reloaded.recentSessions.isEmpty,
                  reloaded.clubCash == startingCash + expectedReward else {
                print("SELF TEST FAIL: edits did not persist")
                exit(1)
            }
            // Schema 6: an existing career adopts the data file's real potential, so a
            // player signed before the data carried ceilings can still grow.
            if let prospect = FcDatabase.shared.players.first(where: { $0.age <= 20 && $0.pot > $0.ovr }) {
                var legacy = GameState.fresh()
                legacy.schemaVersion = 5
                legacy.managedClubID = "barcelona"
                var signed = PlayerFactory.player(from: prospect, name: "Prospect", season: 1)
                signed.potential = signed.overall
                legacy.players = [signed]
                let legacyStore = PersistenceStore(baseDirectory: tempDir.appendingPathComponent("legacy", isDirectory: true))
                try legacyStore.save(legacy)
                let migrated = AppStore(persistence: legacyStore)
                guard let player = migrated.state.players.first,
                      player.potential == max(player.overall, prospect.potential),
                      player.potential > player.overall else {
                    print("SELF TEST FAIL: schema 6 did not adopt the database potential")
                    exit(1)
                }
            }

            // Transfer listing: a listed player draws an offer after a match, the offer is
            // negotiable up to a hidden ceiling, and accepting sells the player and pays out.
            let transferStore = PersistenceStore(baseDirectory: tempDir.appendingPathComponent("transfers", isDirectory: true))
            let market = AppStore(persistence: transferStore)
            try market.startCareer(with: "arsenal")
            guard let forSale = market.state.players.last else {
                print("SELF TEST FAIL: started career without players")
                exit(1)
            }
            market.setPlayerListed(forSale.id, listed: true)
            guard AppStore(persistence: transferStore).state.players.contains(where: { $0.id == forSale.id && $0.isUserListing }) else {
                print("SELF TEST FAIL: the transfer list flag did not persist")
                exit(1)
            }
            var marketDraft = market.state
            market.makeTransferOffers(into: &marketDraft)
            market.commit(marketDraft)
            guard let offer = market.state.transferOffers.first,
                  offer.playerID == forSale.id,
                  offer.ceiling >= offer.amount,
                  offer.marketValue > 0 else {
                print("SELF TEST FAIL: a listed player drew no usable offer")
                exit(1)
            }
            let cashBeforeSale = market.state.clubCash
            guard case .improved(let raised) = market.counterTransferOffer(offer.id, amount: offer.ceiling + 500),
                  raised == offer.ceiling else {
                print("SELF TEST FAIL: countering above the ceiling did not settle at the ceiling")
                exit(1)
            }
            market.acceptTransferOffer(offer.id)
            guard !market.state.players.contains(where: { $0.id == forSale.id }),
                  market.state.clubCash == cashBeforeSale + offer.ceiling,
                  market.state.transferOffers.isEmpty else {
                print("SELF TEST FAIL: accepting an offer did not sell the player for the agreed fee")
                exit(1)
            }

            // The marking parser must survive a model that wraps its JSON in a code fence or
            // a sentence, clamp a mark above the available total, and reject prose.
            let fencedReply = "Here are the marks:\n```json\n{\"questions\":[{\"question\":\"Q1\",\"awarded\":5,\"outOf\":5,\"reason\":\"ok\"},{\"question\":\"Q2\",\"awarded\":9,\"outOf\":7,\"reason\":\"over\"}],\"feedback\":\"fine\"}\n```"
            guard let parsedMarks = try? MarkingService.parse(fencedReply),
                  parsedMarks.totalOutOf == 12,
                  parsedMarks.totalAwarded == 12,
                  parsedMarks.questions.count == 2 else {
                print("SELF TEST FAIL: the marking parser mishandled fenced JSON or clamping")
                exit(1)
            }
            guard (try? MarkingService.parse("I think it deserves a pass.")) == nil else {
                print("SELF TEST FAIL: the marking parser accepted prose as marks")
                exit(1)
            }

            print("SELF TEST OK: todo round-trip, \(expectedReward) cash reward (no double-pay), p1–p4 priority + #subject - topic parsing and sorting, created topics persist, study-log deletion persists, schema 6 adopts database potentials, transfer offers list/negotiate/sell, marking JSON parsing")
            try? fm.removeItem(at: tempDir)
            exit(0)
        } catch {
            print("SELF TEST FAIL: \(error)")
            try? fm.removeItem(at: tempDir)
            exit(1)
        }
    }

    /// Saves written before the 40-year retirement rule carry per-player retirement ages
    /// of 35–38, so lift every existing player to the current rule. Saves written before
    /// subtopics existed simply start with none.
    private func migrateLegacySaveIfNeeded() {
        guard state.schemaVersion < GameState.currentSchemaVersion, state.managedClubID != nil else { return }
        var draft = state
        if draft.schemaVersion < 2 {
            for index in draft.players.indices {
                draft.players[index].retirementAge = GameRules.retirementAge
            }
            for index in draft.freeAgents.indices {
                draft.freeAgents[index].retirementAge = GameRules.retirementAge
            }
        }
        if draft.schemaVersion < 4 {
            // Saves from before the database import belong to the club that was managed
            // when they were written, and have no database id.
            for index in draft.players.indices where draft.players[index].clubID == nil {
                draft.players[index].clubID = draft.managedClubID
            }
        }
        if draft.schemaVersion < 5 {
            // Database players written before potential was derived from age carry a
            // potential equal to their overall, which stops them ever growing.
            for index in draft.players.indices {
                let player = draft.players[index]
                guard let dbID = player.dbID, player.potential <= player.overall else { continue }
                draft.players[index].potential = PlayerFactory.databasePotential(
                    overall: player.overall,
                    age: player.age,
                    databaseID: dbID
                )
            }
        }
        if draft.schemaVersion < 6 {
            // The data file used to arrive without potentials, so careers written then
            // hold a derived ceiling. The file now carries the game's own potentials for
            // most rows, so adopt those, floored at the rating a player has already reached.
            for index in draft.players.indices {
                guard let dbID = draft.players[index].dbID,
                      let record = FcDatabase.shared.player(id: dbID) else { continue }
                draft.players[index].potential = max(draft.players[index].overall, record.potential)
            }
            for index in draft.freeAgents.indices {
                guard let dbID = draft.freeAgents[index].dbID,
                      let record = FcDatabase.shared.player(id: dbID) else { continue }
                draft.freeAgents[index].potential = max(draft.freeAgents[index].overall, record.potential)
            }
        }
        draft.schemaVersion = GameState.currentSchemaVersion
        commit(draft)
    }

    var hasCareer: Bool {
        state.managedClubID != nil
    }

    var managedClub: Club? {
        ClubDatabase.club(for: state.managedClubID)
    }

    var level: Int {
        1 + state.xp / GameRules.xpPerLevel
    }

    var xpIntoLevel: Int {
        state.xp % GameRules.xpPerLevel
    }

    var levelProgress: Double {
        Double(xpIntoLevel) / Double(GameRules.xpPerLevel)
    }

    var minutesUntilMatch: Int {
        max(0, GameRules.minutesPerMatch - state.availableMatchMinutes)
    }

    var matchReadiness: Double {
        min(1.0, Double(state.availableMatchMinutes) / Double(GameRules.minutesPerMatch))
    }

    var lineupIsComplete: Bool {
        LineupSlot.all.allSatisfy { slot in
            guard let id = state.lineup[slot.id] else { return false }
            return !(state.players.first(where: { $0.id == id })?.isInjured ?? true)
        }
    }

    var squadMetrics: SquadMetrics {
        SquadMetrics.calculate(lineup: state.lineup, players: state.players)
    }

    var userStartingPlayers: [Player] {
        MatchEngine.userMetricsLineup(players: state.players, lineup: state.lineup)
    }

    var benchPlayers: [Player] {
        state.bench.compactMap { id in state.players.first(where: { $0.id == id }) }
    }

    var lineupPlayersBySlot: [String: Player] {
        var result: [String: Player] = [:]
        for slot in LineupSlot.all {
            guard let id = state.lineup[slot.id] else { continue }
            result[slot.id] = state.players.first(where: { $0.id == id })
        }
        return result
    }

    var season: SeasonState? {
        state.season
    }

    var standings: [StandingRow] {
        guard let season = state.season else { return [] }
        return StandingsEngine.standings(fixtures: season.fixtures)
    }

    var userLeaguePosition: Int {
        guard let managedClub else { return 0 }
        return StandingsEngine.position(for: managedClub.id, in: standings)
    }

    var currentFixtures: [Fixture] {
        state.season?.currentFixtures ?? []
    }

    var userCurrentFixture: Fixture? {
        guard let userID = state.managedClubID else { return nil }
        return currentFixtures.first { $0.homeClubID == userID || $0.awayClubID == userID }
    }

    var nextFixtureForUser: Fixture? {
        if let current = userCurrentFixture { return current }
        guard let season = state.season, let userID = state.managedClubID else { return nil }
        let unplayed = season.fixtures
            .filter { !$0.isSimulated && ($0.homeClubID == userID || $0.awayClubID == userID) }
        return unplayed.sorted { lhs, rhs in
            if lhs.phase == rhs.phase { return lhs.round < rhs.round }
            return phaseOrder(lhs.phase) < phaseOrder(rhs.phase)
        }.first
    }

    var currentPhaseNeedsStudy: Bool {
        userCurrentFixture != nil
    }

    var currentPhaseHasUserFixture: Bool {
        userCurrentFixture != nil
    }

    var canSimulateCurrentStage: Bool {
        guard let season = state.season, season.phase != .complete else { return false }
        guard !currentFixtures.isEmpty else { return false }
        if userCurrentFixture != nil {
            return lineupIsComplete && state.availableMatchMinutes >= GameRules.minutesPerMatch
        }
        return true
    }

    var isSeasonComplete: Bool {
        state.season?.phase == .complete
    }

    var championClub: Club? {
        ClubDatabase.club(for: state.season?.championClubID)
    }

    var lastReportForUser: MatchReport? {
        guard let userID = state.managedClubID else { return nil }
        return latestReports.first { $0.homeClubID == userID || $0.awayClubID == userID }
    }

    var latestReports: [MatchReport] {
        (state.season?.reports ?? []).sorted { $0.playedAt > $1.playedAt }
    }

    var trophies: [TrophyRecord] {
        state.trophies.sorted { $0.seasonNumber > $1.seasonNumber }
    }

    var userTitles: Int {
        state.trophies.filter(\.userWasChampion).count
    }

    var completedSeasons: Int {
        state.trophies.count
    }

    var freeAgentCounts: [PlayerRarity: Int] {
        Dictionary(grouping: state.freeAgents, by: \.rarity).mapValues(\.count)
    }

    var topProspects: [Player] {
        state.freeAgents
            .filter { $0.rarity == .wonderkid }
            .sorted { $0.potential > $1.potential }
            .prefix(4)
            .map { $0 }
    }

    var userTournamentStatus: String {
        guard let season = state.season else { return "No active season" }
        if season.phase == .complete {
            if season.championClubID == state.managedClubID { return "Champions of Europe" }
            return finalUserFinish
        }
        if season.phase == .league {
            guard let fixture = userCurrentFixture, let managedClub else { return "League phase" }
            let opponentID = fixture.homeClubID == managedClub.id ? fixture.awayClubID : fixture.homeClubID
            let opponent = ClubDatabase.club(for: opponentID)?.shortName ?? "Opponent"
            return fixture.homeClubID == managedClub.id ? "Next: vs \(opponent)" : "Next: away at \(opponent)"
        }
        if userCurrentFixture != nil {
            return "\(season.phase.displayName) fixture ready"
        }
        if season.phase == .playoffs && userLeaguePosition <= 8 {
            return "Directly qualified for the Round of 16"
        }
        return "Spectating the \(season.phase.displayName)"
    }

    var finalUserFinish: String {
        guard let season = state.season, let managedClub else { return "—" }
        return SeasonEngine.userFinish(
            userClubID: managedClub.id,
            standings: standings,
            fixtures: season.fixtures,
            championClubID: season.championClubID
        )
    }

    var stageButtonLabel: String {
        guard let season = state.season else { return "No Season" }
        if season.phase == .complete { return "Season Complete" }
        if season.phase == .league { return "Simulate Matchday \(season.nextLeagueRound)" }
        return "Simulate \(season.phase.displayName)"
    }

    func club(for id: String) -> Club? {
        ClubDatabase.club(for: id)
    }

    func player(for id: UUID) -> Player? {
        state.players.first { $0.id == id }
    }

    /// A player listed on the transfer market. Either a database player owned by another club,
    /// or a user-club player the owner has placed for sale.
    struct TransferListing: Identifiable, Hashable {
        let record: FcPlayer
        let clubID: String          // Club that owns the player (or userClubID if user-listed)
        let club: Club?
        let clubName: String
        let league: String?
        let isUserListing: Bool     // true if the user's club placed this player for sale
        let listingPrice: Int?      // price the user set; nil = askingPrice-driven negotiation

        var id: Int { record.id }
        var fee: Int { PlayerPricing.fee(forOverall: record.ovr) }
        var isUserAskingPrice: Bool { isUserListing && listingPrice != nil }

        static func == (lhs: TransferListing, rhs: TransferListing) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    enum NegotiationStatus: String {
        case open
        case signed
        case collapsed
    }

    struct NegotiationMessage: Identifiable, Hashable {
        let id = UUID()
        let fromClub: Bool
        let text: String
    }

    struct Negotiation: Identifiable {
        let id: Int
        let listing: TransferListing
        var askingPrice: Int
        var patience: Int
        var status: NegotiationStatus
        var messages: [NegotiationMessage]
        var lastOffer: Int?

        var name: String { listing.record.name ?? "" }
        var lastOfferText: String? { lastOffer.map { $0.formatted() } }
    }

    /// The market is rebuilt from the database whenever the squad changes, so a signed
    /// player disappears from it immediately.
    @ObservationIgnored private var marketCache: (clubID: String, owned: Set<Int>, listings: [TransferListing])?

    /// Players below this overall are not shown on the transfer market.
    static let minimumMarketOverall = 59

    var transferMarket: [TransferListing] {
        guard let userClubID = state.managedClubID else { return [] }
        let owned = Set(state.players.compactMap(\.dbID))
        if let cache = marketCache, cache.clubID == userClubID, cache.owned == owned {
            return cache.listings
        }
        let database = FcDatabase.shared
        var listings: [TransferListing] = []
        listings.reserveCapacity(database.players.count + state.players.count)

        // 1. Database players from other clubs (existing behavior)
        for record in database.players {
            if owned.contains(record.id) { continue }
            if record.club == userClubID { continue }
            if record.ovr < Self.minimumMarketOverall { continue }
            let owner = database.club(record.club)
            listings.append(
                TransferListing(
                    record: record,
                    clubID: record.club,
                    club: ClubDatabase.club(for: record.club),
                    clubName: owner?.name ?? record.club,
                    league: owner?.league,
                    isUserListing: false,
                    listingPrice: nil
                )
            )
        }

        // 2. User's own players listed for sale (new)
        let userPlayers = state.players.filter { $0.clubID == userClubID }
        for player in userPlayers {
            // Skip players already on a negotiation
            if negotiation?.listing.record.id == player.dbID { continue }
            guard let fcPlayer = FcDatabase.shared.player(id: player.dbID ?? 0) else { continue }
            if fcPlayer.ovr < Self.minimumMarketOverall { continue }
            listings.append(
                TransferListing(
                    record: fcPlayer,
                    clubID: userClubID,
                    club: ClubDatabase.club(for: userClubID),
                    clubName: ClubDatabase.club(for: userClubID)?.name ?? userClubID,
                    league: nil,
                    isUserListing: true,
                    listingPrice: nil  // Will be set by user or algorithm
                )
            )
        }

        listings.sort { lhs, rhs in
            if lhs.record.ovr != rhs.record.ovr { return lhs.record.ovr > rhs.record.ovr }
            // User listings come after database players (or before - choose what makes sense)
            if lhs.isUserListing != rhs.isUserListing { return lhs.isUserListing }
            if lhs.clubName != rhs.clubName { return lhs.clubName < rhs.clubName }
            return lhs.record.id < rhs.record.id
        }
        marketCache = (userClubID, owned, listings)
        return listings
    }

    /// What a club expects before it will sell: the player's value plus a premium for how
    /// important they are to that club and how big the club is.
    func askingPrice(for listing: TransferListing) -> Int {
        let value = listing.fee
        let clubRating = FcDatabase.shared.club(listing.clubID)?.rating ?? 75
        let gap = listing.record.ovr - clubRating
        let base: Double
        switch gap {
        case 4...: base = 1.55
        case 0...3: base = 1.40
        case -5 ... -1: base = 1.25
        default: base = 1.12
        }
        let prestige = clubRating >= 84 ? 0.10 : (clubRating >= 80 ? 0.05 : 0)
        return Int((Double(value) * (base + prestige)).rounded())
    }

    // MARK: - Negotiation

    private(set) var negotiation: Negotiation?

    func beginNegotiation(for listing: TransferListing) {
        guard hasCareer else { return }
        guard !state.players.contains(where: { $0.dbID == listing.record.id }) else { return }
        let asking = askingPrice(for: listing)
        negotiation = Negotiation(
            id: listing.id,
            listing: listing,
            askingPrice: asking,
            patience: 100,
            status: .open,
            messages: [
                NegotiationMessage(
                    fromClub: true,
                    text: "\(listing.clubName) will not let \(playerName(for: listing)) leave for less than \(asking.formatted()) Club Cash."
                )
            ],
            lastOffer: nil
        )
    }

    func playerName(for listing: TransferListing) -> String {
        let database = FcDatabase.shared
        return listing.record.disambiguatedName(in: database.squad(for: listing.clubID), database: database)
    }

    /// One round of haggling. The club holds firm near its asking price, softens a little
    /// for serious offers, and loses patience fast if you lowball it.
    func submitOffer(_ amount: Int) {
        guard var deal = negotiation, deal.status == .open else { return }
        let offer = max(0, amount)
        deal.lastOffer = offer

        if offer >= deal.askingPrice {
            deal.status = .signed
            deal.messages.append(NegotiationMessage(fromClub: true, text: "\(deal.listing.clubName) accept \(offer.formatted()). The paperwork is done."))
            negotiation = deal
            completeSigning(deal.listing, price: offer)
            return
        }

        let ratio = Double(offer) / Double(max(1, deal.askingPrice))
        if ratio >= 0.9 {
            deal.askingPrice = Int(Double(deal.askingPrice) * 0.96)
            deal.patience -= 10
            deal.messages.append(
                NegotiationMessage(
                    fromClub: true,
                    text: "Close. \(deal.listing.clubName) counters at \(deal.askingPrice.formatted())."
                )
            )
        } else if ratio >= 0.72 {
            deal.askingPrice = Int(Double(deal.askingPrice) * 0.97)
            deal.patience -= 24
            deal.messages.append(
                NegotiationMessage(
                    fromClub: true,
                    text: "That is short of our valuation. Meet \(deal.askingPrice.formatted()) and we can talk."
                )
            )
        } else {
            deal.patience -= 38
            deal.messages.append(
                NegotiationMessage(
                    fromClub: true,
                    text: "We are not giving \(playerName(for: deal.listing)) away. Come back with a serious number."
                )
            )
        }

        if deal.patience <= 0 {
            deal.patience = 0
            deal.status = .collapsed
            deal.messages.append(
                NegotiationMessage(
                    fromClub: true,
                    text: "\(deal.listing.clubName) have ended talks. Walk away and try again later."
                )
            )
        }
        negotiation = deal
    }

    func acceptAskingPrice() {
        guard let deal = negotiation, deal.status == .open else { return }
        submitOffer(deal.askingPrice)
    }

    func walkAwayFromNegotiation() {
        negotiation = nil
    }

    private func completeSigning(_ listing: TransferListing, price: Int) {
        guard price <= state.clubCash else {
            if var deal = negotiation {
                deal.status = .open
                deal.messages.append(NegotiationMessage(fromClub: true, text: "Your bid was accepted, but you cannot cover \(price.formatted()) Club Cash."))
                negotiation = deal
            }
            return
        }
        let name = playerName(for: listing)
        let player = PlayerFactory.player(from: listing.record, name: name, season: state.seasonNumber)
        var draft = state
        draft.clubCash -= price
        draft.players.append(player)
        if draft.bench.count < GameRules.benchLimit {
            draft.bench.append(player.id)
        }
        commit(draft)
    }

    func startCareer(with clubID: String) throws {
        guard state.managedClubID == nil else { throw GameError.invalidState }
        guard let club = ClubDatabase.club(for: clubID) else { throw GameError.invalidClub }
        var draft = state
        var squad = PlayerFactory.databaseSquad(for: club.id, season: draft.seasonNumber)
        if squad.isEmpty {
            // A club the database does not carry (it has no Red Star side) still needs a
            // squad, so fall back to the generated roster.
            squad = PlayerFactory.starterSquad(club: club, season: draft.seasonNumber)
        }
        let lineupResult = PlayerFactory.autoLineup(players: squad)
        draft.schemaVersion = GameState.currentSchemaVersion
        draft.managedClubID = club.id
        draft.players = squad
        draft.freeAgents = PlayerFactory.makeFreeAgentPool(season: draft.seasonNumber, count: GameRules.freeAgentPoolTarget)
        draft.lineup = lineupResult.0
        draft.bench = lineupResult.1
        draft.season = SeasonEngine.newSeason(number: draft.seasonNumber)
        draft.lastTransition = nil
        commit(draft)
    }

    func logStudy(
        kind: StudyActivityKind,
        title: String,
        minutes: Int,
        quantity: Int,
        subject: StudySubject = .other,
        subtopicID: UUID? = nil,
        marksObtained: Int? = nil,
        marksTotal: Int? = nil
    ) {
        guard minutes > 0 else { return }
        let safeQuantity = max(1, quantity)

        // Marks are entered as gained over attempted. Anything that does not form a
        // usable fraction is treated as unmarked work.
        var resolvedObtained: Int?
        var resolvedTotal: Int?
        if kind.supportsMarking, let obtained = marksObtained, let total = marksTotal, total > 0, obtained >= 0 {
            resolvedObtained = min(obtained, total)
            resolvedTotal = total
        }

        let reward = StudyReward.calculate(
            kind: kind,
            subject: subject,
            minutes: minutes,
            marksObtained: resolvedObtained,
            marksTotal: resolvedTotal
        )
        let cash = reward.cash
        let xp = reward.xp
        let now = Date()
        var draft = state
        draft.clubCash += cash
        let levelsGained = applyXP(xp, to: &draft)
        draft.availableMatchMinutes += minutes
        draft.study.totalStudyMinutes += minutes
        draft.study.totalSessions += 1
        switch kind {
        case .homework:
            draft.study.homeworkCompleted += safeQuantity
        case .pastPaper:
            draft.study.pastPapersCompleted += safeQuantity
        case .examQuestions:
            draft.study.examQuestionsSolved += safeQuantity
        case .focusSession:
            break
        }
        registerStudyDay(&draft.study, date: now)
        let resolvedSubtopic = subtopicID.flatMap { id in draft.subtopics.first(where: { $0.id == id }) }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if !trimmedTitle.isEmpty {
            resolvedTitle = trimmedTitle
        } else if let resolvedSubtopic {
            resolvedTitle = "\(subject.shortName) - \(resolvedSubtopic.name)"
        } else {
            resolvedTitle = subject == .other ? kind.title : "\(subject.shortName) - \(kind.title)"
        }
        let session = StudySession(
            id: UUID(),
            date: now,
            kind: kind,
            title: resolvedTitle,
            minutes: minutes,
            cashEarned: cash,
            xpEarned: xp,
            quantity: safeQuantity,
            subject: subject,
            marksObtained: resolvedObtained,
            marksTotal: resolvedTotal,
            subtopicID: resolvedSubtopic?.id,
            subtopicName: resolvedSubtopic?.name
        )
        draft.recentSessions.insert(session, at: 0)
        commit(draft)
        announceLevelUps(levelsGained)
    }

    // MARK: - Subtopics and subject tracking

    var subtopics: [Subtopic] { state.subtopics }

    func subtopics(for subject: StudySubject) -> [Subtopic] {
        state.subtopics.filter { $0.subject == subject }
    }

    /// Adds a module or topic to a subject. Returns nil when the name is blank or the
    /// subject already has a subtopic with that name.
    @discardableResult
    func addSubtopic(_ name: String, to subject: StudySubject) -> Subtopic? {
        guard hasCareer else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let siblings = state.subtopics.filter { $0.subject == subject }
        guard !siblings.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        let subtopic = Subtopic(id: UUID(), subject: subject, name: trimmed, createdAt: Date())
        var draft = state
        draft.subtopics.append(subtopic)
        commit(draft)
        return subtopic
    }

    /// Removes a subtopic from the subject list. Sessions keep the name they were logged
    /// with, so subject totals and history are untouched.
    func deleteSubtopic(_ id: UUID) {
        guard state.subtopics.contains(where: { $0.id == id }) else { return }
        var draft = state
        draft.subtopics.removeAll { $0.id == id }
        commit(draft)
    }

    /// Removes a study session from recent sessions. The session data is preserved
    /// in history but removed from the recent sessions list.
    func deleteStudySession(_ id: UUID) {
        guard state.recentSessions.contains(where: { $0.id == id }) else { return }
        var draft = state
        draft.recentSessions.removeAll { $0.id == id }
        commit(draft)
    }

    func aggregate(for subject: StudySubject) -> StudyAggregate {
        StudyAggregate.build(from: state.recentSessions.filter { $0.subject == subject })
    }

    func aggregate(forSubtopic id: UUID) -> StudyAggregate {
        StudyAggregate.build(from: state.recentSessions.filter { $0.subtopicID == id })
    }

    var studyAggregate: StudyAggregate {
        StudyAggregate.build(from: state.recentSessions)
    }

    var marksAttempted: Int {
        studyAggregate.marksTotal
    }

    var todos: [TodoItem] { state.todos }

    func todos(for subject: StudySubject) -> [TodoItem] {
        sortedTodos(state.todos.filter { $0.subject == subject })
    }

    func todos(forSubtopic id: UUID) -> [TodoItem] {
        sortedTodos(state.todos.filter { $0.subtopicID == id })
    }

    /// Open tasks first, then by priority (P1 at the top, unmarked last), then oldest first.
    private func sortedTodos(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            let left = lhs.priority ?? Int.max
            let right = rhs.priority ?? Int.max
            if left != right { return left < right }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// Adds a task, honouring inline directives: `p2 #Ext 2 Maths - Complex Numbers: finish 4.2`
    /// files the task under Ext 2 Maths and its Complex Numbers topic at priority 2.
    func addTodo(_ rawTitle: String, subject defaultSubject: StudySubject = .other, subtopicID defaultSubtopicID: UUID? = nil) -> TodoItem? {
        guard hasCareer else { return nil }
        let input = TodoInput.parse(rawTitle, subtopics: state.subtopics)
        let trimmed = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let subject = input.subject ?? defaultSubject
        let siblings = state.todos.filter { $0.subject == subject }
        guard !siblings.contains(where: { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }

        var draft = state
        var resolvedSubtopic: Subtopic?
        if let name = input.subtopicName {
            if let existing = state.subtopics.first(where: { $0.subject == subject && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                resolvedSubtopic = existing
            } else {
                // A topic named in the task line is created if the subject doesn't have it yet.
                let topic = Subtopic(id: UUID(), subject: subject, name: name, createdAt: Date())
                draft.subtopics.append(topic)
                resolvedSubtopic = topic
            }
        } else if let defaultSubtopicID,
                  let existing = state.subtopics.first(where: { $0.id == defaultSubtopicID }),
                  existing.subject == subject {
            resolvedSubtopic = existing
        }

        let todo = TodoItem(
            id: UUID(),
            title: trimmed,
            subject: subject,
            subtopicID: resolvedSubtopic?.id,
            subtopicName: resolvedSubtopic?.name,
            isCompleted: false,
            createdAt: Date(),
            dueDate: nil,
            priority: input.priority
        )
        draft.todos.append(todo)
        commit(draft)
        return todo
    }

    func deleteTodo(_ id: UUID) {
        guard state.todos.contains(where: { $0.id == id }) else { return }
        var draft = state
        draft.todos.removeAll { $0.id == id }
        commit(draft)
    }

    /// Club Cash earned for completing a todo, scaled by its subject's cash multiplier.
    func todoReward(for subject: StudySubject) -> Int {
        Int((Double(GameRules.clubCashPerTodo) * subject.cashMultiplier).rounded())
    }

    func toggleTodo(_ id: UUID) {
        guard let index = state.todos.firstIndex(where: { $0.id == id }) else { return }
        var draft = state
        draft.todos[index].isCompleted.toggle()
        // The reward is paid once per task: un-ticking does not take it back and
        // re-ticking does not pay it again.
        if draft.todos[index].isCompleted, !draft.todos[index].rewardAwarded {
            draft.clubCash += todoReward(for: draft.todos[index].subject ?? .other)
            draft.todos[index].rewardAwarded = true
        }
        commit(draft)
    }

    /// Points the timer at an open todo and takes its subject and topic, so the logged work lands there.
    func setTimerTodo(_ id: UUID?) {
        timerTodoID = id
        guard let id, let todo = state.todos.first(where: { $0.id == id }) else { return }
        timerSubject = todo.subject ?? .other
        timerSubtopicID = todo.subtopicID
    }

    func startTimer() {
        guard !isTimerRunning else { return }
        timerElapsedSeconds = 0
        timerCreditedMinutes = 0
        lastTimerSessionMinutes = 0
        isTimerRunning = true
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerTick()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func pauseTimer() {
        guard isTimerRunning else { return }
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
        let minutes = timerCreditedMinutes
        if minutes > 0, timerKind != .focusSession {
            // Homework, past papers and exam questions are logged through the normal path,
            // so they earn the same rewards and marks as a manual log.
            let kind = timerKind
            let subject = timerSubject
            let subtopic = timerSubtopicID
            let obtained = timerMarksObtained
            let total = timerMarksTotal
            timerElapsedSeconds = 0
            timerCreditedMinutes = 0
            logStudy(kind: kind, title: "", minutes: minutes, quantity: 1, subject: subject, subtopicID: subtopic, marksObtained: obtained, marksTotal: total)
            lastTimerSessionMinutes = minutes
            timerTodoID = nil
            return
        }
        if minutes > 0 {
            let cash = minutes * GameRules.clubCashPerMinute
            let xp = minutes * GameRules.xpPerMinute
            var draft = state
            draft.study.totalSessions += 1
            let topic = timerSubtopicID.flatMap { id in draft.subtopics.first(where: { $0.id == id }) }
            let session = StudySession(
                id: UUID(),
                date: Date(),
                kind: .focusSession,
                title: topic.map { "\(timerSubject.shortName) - \($0.name)" } ?? "Focus session",
                minutes: minutes,
                cashEarned: cash,
                xpEarned: xp,
                quantity: minutes,
                subject: timerSubject,
                subtopicID: topic?.id,
                subtopicName: topic?.name
            )
            draft.recentSessions.insert(session, at: 0)
            commit(draft)
            lastTimerSessionMinutes = minutes
        }
        timerElapsedSeconds = 0
        timerCreditedMinutes = 0
        timerTodoID = nil
    }

    func resetTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
        timerElapsedSeconds = 0
        timerCreditedMinutes = 0
    }

    func assign(playerID: UUID, to slotID: String) {
        guard let slot = LineupSlot.slot(for: slotID), player(for: playerID) != nil else { return }
        var draft = state
        for (key, value) in draft.lineup where value == playerID {
            draft.lineup.removeValue(forKey: key)
        }
        draft.lineup[slot.id] = playerID
        draft.bench.removeAll { $0 == playerID }
        commit(draft)
    }

    func removeFromLineup(slotID: String) {
        guard state.lineup[slotID] != nil else { return }
        var draft = state
        draft.lineup.removeValue(forKey: slotID)
        commit(draft)
    }

    func addToBench(playerID: UUID) {
        guard player(for: playerID) != nil else { return }
        if state.bench.contains(playerID) { return }
        if state.bench.count >= GameRules.benchLimit { return }
        var draft = state
        for (key, value) in draft.lineup where value == playerID {
            draft.lineup.removeValue(forKey: key)
        }
        draft.bench.append(playerID)
        commit(draft)
    }

    func removeFromBench(playerID: UUID) {
        guard state.bench.contains(playerID) else { return }
        var draft = state
        draft.bench.removeAll { $0 == playerID }
        commit(draft)
    }

    func addToSquad(playerID: UUID) {
        guard let player = player(for: playerID) else { return }
        if state.lineup.values.contains(playerID) || state.bench.contains(playerID) { return }
        var draft = state
        let emptySlots = LineupSlot.all.filter { draft.lineup[$0.id] == nil }
        let bestSlot = emptySlots
            .filter { $0.position == player.position }
            .first
            ?? emptySlots.filter { $0.position.group == player.position.group }.first
            ?? emptySlots.first
        if let bestSlot {
            draft.lineup[bestSlot.id] = playerID
        } else if draft.bench.count < GameRules.benchLimit {
            draft.bench.append(playerID)
        } else {
            return
        }
        commit(draft)
    }

    func autoPickSquad() {
        let result = PlayerFactory.autoLineup(players: state.players)
        var draft = state
        draft.lineup = result.0
        draft.bench = result.1
        commit(draft)
    }

    @discardableResult
    func releasePlayer(playerID: UUID) -> Int {
        guard let player = player(for: playerID) else { return 0 }
        var draft = state
        draft.players.removeAll { $0.id == playerID }
        for (key, value) in draft.lineup where value == playerID {
            draft.lineup.removeValue(forKey: key)
        }
        draft.bench.removeAll { $0 == playerID }
        // Releasing a listed player cancels any offer already on the table for him.
        draft.transferOffers.removeAll { $0.playerID == playerID }
        draft.clubCash += player.releaseValue
        commit(draft)
        return player.releaseValue
    }

    /// Spends Club Cash to raise the youth academy by one level.
    func upgradeAcademy() throws {
        guard managedClub != nil else { throw GameError.noCareer }
        guard let cost = GameRules.academyUpgradeCost(from: state.academyLevel) else {
            throw GameError.academyMaxLevel
        }
        guard state.clubCash >= cost else { throw GameError.insufficientFunds }
        var draft = state
        draft.clubCash -= cost
        draft.academyLevel += 1
        commit(draft)
    }

    // MARK: - Assessments

    /// Saves a test or exam. Only its class rank earns rewards; marks, weighting and
    /// overall rank are kept for the graphs. Rank is entered per assessment, so a
    /// test ranked 1st always pays the full base reward.
    @discardableResult
    func addAssessment(_ assessment: Assessment) -> Assessment? {
        guard hasCareer else { return nil }
        var entry = assessment
        let subjectMultiplier = entry.subject.xpMultiplier
        let cashMultiplier = entry.subject.cashMultiplier
        let rankFactor = GameRules.assessmentRankFactor(classRank: entry.classRank)
        entry.cashEarned = Int((Double(GameRules.assessmentBaseCash) * cashMultiplier * GameRules.examRewardMultiplier * rankFactor).rounded())
        entry.xpEarned = Int((Double(GameRules.assessmentBaseXP) * subjectMultiplier * GameRules.examRewardMultiplier * rankFactor).rounded())
        var draft = state
        draft.clubCash += entry.cashEarned
        let levelsGained = applyXP(entry.xpEarned, to: &draft)
        draft.assessments.insert(entry, at: 0)
        commit(draft)
        announceLevelUps(levelsGained)
        return entry
    }

    func deleteAssessment(_ id: UUID) {
        guard state.assessments.contains(where: { $0.id == id }) else { return }
        var draft = state
        draft.assessments.removeAll { $0.id == id }
        commit(draft)
    }

    func openPack(packID: String) throws -> [Player] {
        guard let managedClub else { throw GameError.noCareer }
        guard let pack = PackCatalog.pack(for: packID) else { throw GameError.invalidPack }
        guard level >= pack.minimumLevel else { throw GameError.levelTooLow(pack.minimumLevel) }
        guard state.clubCash >= pack.price else { throw GameError.insufficientFunds }

        var draft = state
        draft.clubCash -= pack.price
        var pulled: [Player] = []
        for index in 0..<pack.playerCount {
            let rarity: PlayerRarity
            if pack.id == "gold" && index == 0 {
                rarity = weightedRarity(from: [.gold: 86, .wonderkid: 10, .icon: 4])
            } else {
                rarity = weightedRarity(from: pack.rarityWeights)
            }
            let candidateIndex = draft.freeAgents.firstIndex(where: { $0.rarity == rarity })
            let player: Player
            if let candidateIndex {
                player = draft.freeAgents.remove(at: candidateIndex)
            } else {
                player = PlayerFactory.makePackPlayer(rarity: rarity, season: draft.seasonNumber)
            }
            draft.players.append(player)
            pulled.append(player)
        }
        _ = managedClub
        commit(draft)
        return pulled
    }

    func simulateCurrentStage() throws -> SimulationOutcome {
        guard let managedClub else { throw GameError.noCareer }
        guard var season = state.season else { throw GameError.noSeason }
        guard season.phase != .complete else { throw GameError.seasonComplete }
        let fixturesToPlay = season.currentFixtures
        guard !fixturesToPlay.isEmpty else { throw GameError.noFixtures }

        let userFixture = fixturesToPlay.first {
            $0.homeClubID == managedClub.id || $0.awayClubID == managedClub.id
        }
        if userFixture != nil {
            guard lineupIsComplete else { throw GameError.lineupIncomplete }
            guard state.availableMatchMinutes >= GameRules.minutesPerMatch else {
                throw GameError.insufficientStudy(minutesUntilMatch)
            }
        }

        let metrics = squadMetrics
        let userScorers = userStartingPlayers
        let phasePlayed = season.phase
        var updatedFixtures = season.fixtures
        var updatedReports = season.reports
        var userReport: MatchReport?
        var simulatedCount = 0
        var ledger = state.scoringLedger
        // Saves from before the ledger existed seed it from the reports already played.
        if ledger.isEmpty {
            for report in season.reports {
                ledger.record(report: report)
            }
        }

        for fixture in fixturesToPlay {
            guard !fixture.isSimulated else { continue }
            guard let homeClub = ClubDatabase.club(for: fixture.homeClubID),
                  let awayClub = ClubDatabase.club(for: fixture.awayClubID)
            else { continue }

            let homeTeam = teamProfile(
                club: homeClub,
                userClubID: managedClub.id,
                metrics: metrics,
                userScorers: userScorers,
                season: season.number
            )
            let awayTeam = teamProfile(
                club: awayClub,
                userClubID: managedClub.id,
                metrics: metrics,
                userScorers: userScorers,
                season: season.number
            )
            let simulation = MatchEngine.simulate(
                fixture: fixture,
                home: homeTeam,
                away: awayTeam,
                season: season.number,
                lineup: state.lineup
            )
            if let index = updatedFixtures.firstIndex(where: { $0.id == fixture.id }) {
                updatedFixtures[index].homeGoals = simulation.report.homeGoals
                updatedFixtures[index].awayGoals = simulation.report.awayGoals
                updatedFixtures[index].homePenalties = simulation.report.homePenalties
                updatedFixtures[index].awayPenalties = simulation.report.awayPenalties
            }
            updatedReports.append(simulation.report)
            ledger.record(report: simulation.report)
            if fixture.homeClubID == managedClub.id || fixture.awayClubID == managedClub.id {
                userReport = simulation.report
                // Count down existing injuries first, so new injuries keep their full 2-match penalty.
                for i in state.players.indices where state.players[i].matchesMissed > 0 {
                    state.players[i].matchesMissed -= 1
                    if state.players[i].matchesMissed == 0 {
                        state.players[i].isInjured = false
                    }
                }
                // Apply injuries to starting 11 (5% chance each)
                for slot in LineupSlot.all {
                    if let playerID = state.lineup[slot.id],
                       let index = state.players.firstIndex(where: { $0.id == playerID }) {
                        var player = state.players[index]
                        if !player.isInjured && Double.random(in: 0..<1) < 0.05 {
                            player.isInjured = true
                            player.matchesMissed = 2
                            state.players[index] = player
                        }
                    }
                }
            }
            simulatedCount += 1
        }

        season.fixtures = updatedFixtures
        season.reports = updatedReports

        let standingsAfter = StandingsEngine.standings(fixtures: season.fixtures)
        var trophy: TrophyRecord?

        if phasePlayed == .league {
            season.nextLeagueRound += 1
            if season.nextLeagueRound > 8 {
                let playoffs = ScheduleEngine.makePlayoffFixtures(standings: standingsAfter, season: season.number)
                season.fixtures.append(contentsOf: playoffs)
                season.phase = .playoffs
            }
        } else if phasePlayed == .final {
            let finalFixtures = season.fixtures.filter { $0.phase == .final }
            if let final = finalFixtures.first,
               let winnerID = final.winnerClubID,
               let loserID = final.loserClubID {
                season.championClubID = winnerID
                season.runnerUpClubID = loserID
                season.phase = .complete
                if !season.archived {
                    trophy = SeasonEngine.makeTrophyRecord(
                        season: season,
                        userClub: managedClub,
                        standings: standingsAfter
                    )
                    if let trophy {
                        state.trophies.append(trophy)
                    }
                    season.archived = true
                }
            } else {
                throw GameError.invalidState
            }
        } else {
            let next = SeasonEngine.nextPhase(after: phasePlayed)
            var nextFixtures: [Fixture] = []
            switch phasePlayed {
            case .playoffs:
                nextFixtures = ScheduleEngine.makeRoundOf16(
                    standings: standingsAfter,
                    playoffFixtures: season.fixtures.filter { $0.phase == .playoffs },
                    season: season.number
                )
            case .roundOf16, .quarterfinal, .semifinal:
                nextFixtures = ScheduleEngine.makeNextKnockoutRound(
                    from: season.fixtures.filter { $0.phase == phasePlayed },
                    phase: next,
                    standings: standingsAfter,
                    season: season.number
                )
            default:
                break
            }
            guard !nextFixtures.isEmpty else { throw GameError.invalidState }
            season.fixtures.append(contentsOf: nextFixtures)
            season.phase = next
        }

        var draft = state
        draft.season = season
        draft.scoringLedger = ledger
        if userFixture != nil {
            // A match is the moment rivals respond to the transfer list.
            makeTransferOffers(into: &draft)
            draft.availableMatchMinutes -= GameRules.minutesPerMatch
            draft.matchesSinceAcademyIntake += 1
            if draft.matchesSinceAcademyIntake >= GameRules.matchesPerAcademyIntake {
                draft.matchesSinceAcademyIntake = 0
                draft.freeAgents.append(
                    contentsOf: PlayerFactory.makeAcademyIntake(
                        level: draft.academyLevel,
                        season: draft.seasonNumber,
                        count: 3
                    )
                )
            }
        }
        commit(draft)

        return SimulationOutcome(
            userReport: userReport,
            simulatedCount: simulatedCount,
            phasePlayed: phasePlayed,
            championClub: ClubDatabase.club(for: season.championClubID),
            trophy: trophy
        )
    }

    func startNextSeason() throws -> SeasonTransition {
        guard let season = state.season, season.phase == .complete, season.archived else {
            throw GameError.seasonComplete
        }
        guard let managedClub else { throw GameError.noCareer }
        let oldNumber = season.number
        let championName = ClubDatabase.club(for: season.championClubID)?.name ?? "Unknown"
        let userFinish = SeasonEngine.userFinish(
            userClubID: managedClub.id,
            standings: StandingsEngine.standings(fixtures: season.fixtures),
            fixtures: season.fixtures,
            championClubID: season.championClubID
        )

        var generator = SeededGenerator(seed: StableSeed.value(for: "aging-\(oldNumber)-\(managedClub.id)"))
        let starters = Set(state.lineup.values)
        let squadResult = developPlayers(state.players, starters: starters, using: &generator)
        let poolResult = developPlayers(state.freeAgents, starters: [], using: &generator)

        var draft = state
        draft.players = squadResult.players
        draft.freeAgents = poolResult.players
        let retiredIDs = Set(squadResult.retiredIDs)
        draft.lineup = draft.lineup.filter { !retiredIDs.contains($0.value) }
        draft.bench.removeAll { retiredIDs.contains($0) }
        // A retiring player takes any outstanding offer for him with him.
        draft.transferOffers.removeAll { offer in
            !draft.players.contains { $0.id == offer.playerID }
        }
        draft.seasonNumber += 1
        var youthCount = 10
        let prospects = PlayerFactory.makeYouthProspects(season: draft.seasonNumber, count: youthCount)
        draft.freeAgents.append(contentsOf: prospects)
        // The academy promotes a handful of teenagers straight into the senior squad every
        // season so ageing squads can be replenished without the transfer market.
        draft.players.append(contentsOf: PlayerFactory.makeAcademyProspects(season: draft.seasonNumber, count: GameRules.academyIntakePerSeason))
        if draft.freeAgents.count < 48 {
            let extraCount = 48 - draft.freeAgents.count
            let extra = PlayerFactory.makeFreeAgentPool(season: draft.seasonNumber, count: extraCount)
            draft.freeAgents.append(contentsOf: extra)
            youthCount += extraCount
        }
        draft.season = SeasonEngine.newSeason(number: draft.seasonNumber)
        let transition = SeasonTransition(
            id: UUID(),
            completedSeason: oldNumber,
            championName: championName,
            userFinish: userFinish,
            retirees: squadResult.retiredNames,
            youthAdded: youthCount,
            newSeason: draft.seasonNumber
        )
        draft.lastTransition = transition
        commit(draft)
        return transition
    }

    func dismissTransition() {
        guard state.lastTransition != nil else { return }
        var draft = state
        draft.lastTransition = nil
        commit(draft)
    }

    func clearSaveError() {
        saveErrorMessage = nil
    }

    /// Wipes the career, squad, trophies and study history, returning the app to club selection.
    func resetCareer() {
        resetTimer()
        lastTimerSessionMinutes = 0
        saveErrorMessage = nil
        commit(.fresh())
    }

    var storagePath: String {
        persistence.saveURL.path
    }

    private func timerTick() {
        guard isTimerRunning else { return }
        timerElapsedSeconds += 1
        if timerElapsedSeconds % 60 == 0 {
            creditTimerMinute()
        }
    }

    private func creditTimerMinute() {
        // Non-focus work is paid in full when the timer is paused, so only count the minute here.
        guard timerKind == .focusSession else {
            timerCreditedMinutes += 1
            return
        }
        let now = Date()
        var draft = state
        draft.clubCash += GameRules.clubCashPerMinute
        let levelsGained = applyXP(GameRules.xpPerMinute, to: &draft)
        draft.availableMatchMinutes += 1
        draft.study.totalStudyMinutes += 1
        registerStudyDay(&draft.study, date: now)
        timerCreditedMinutes += 1
        commit(draft)
        announceLevelUps(levelsGained)
    }

    // MARK: - Transfer offers

    /// What a bidding club did in response to a counter offer.
    enum OfferOutcome: Equatable {
        case accepted(Int)
        case improved(Int)
        case withdrawn
        /// The offer is no longer on the table (sold, declined or already resolved).
        case expired
    }

    /// One fresh offer per transfer-listed player after every match you play. The coin flip
    /// decides quality: a good club opens around the market value and will stretch above it,
    /// a bad one opens well under and never reaches it. A pending offer is left alone, so
    /// nothing the user has not answered is replaced behind their back.
    func makeTransferOffers(into draft: inout GameState) {
        let listed = draft.players.filter(\.isUserListing)
        guard !listed.isEmpty else { return }
        let clubs = FcDatabase.shared.clubs.filter { $0.id != draft.managedClubID }
        for player in listed {
            guard !draft.transferOffers.contains(where: { $0.playerID == player.id }) else { continue }
            let value = max(1, player.marketValue)
            let good = Double.random(in: 0..<1) < GameRules.transferOfferGoodChance
            let bidShare = good ? Double.random(in: GameRules.transferOfferGoodBidRange) : Double.random(in: GameRules.transferOfferBadBidRange)
            let ceilingShare = good ? Double.random(in: GameRules.transferOfferGoodCeilingRange) : Double.random(in: GameRules.transferOfferBadCeilingRange)
            let bid = max(1, Int((Double(value) * bidShare).rounded()))
            let ceiling = max(bid, Int((Double(value) * ceilingShare).rounded()))
            draft.transferOffers.append(
                TransferOffer(
                    id: UUID(),
                    playerID: player.id,
                    clubName: clubs.randomElement()?.name ?? "A rival club",
                    amount: bid,
                    createdAt: Date(),
                    marketValue: value,
                    ceiling: ceiling,
                    patience: 100,
                    isGood: good
                )
            )
        }
    }

    /// Takes an offer: the player leaves the squad and the fee is paid to the club.
    func acceptTransferOffer(_ offerID: UUID) {
        guard let offer = state.transferOffers.first(where: { $0.id == offerID }) else { return }
        var draft = state
        sell(offer.playerID, price: offer.amount, in: &draft)
    }

    /// Answers an offer with a number of your own. The club accepts anything at or below its
    /// hidden ceiling and otherwise comes up to that ceiling while losing patience; three
    /// pushes past its limit and it walks. Asking for less than the current bid simply
    /// accepts what is already on the table.
    @discardableResult
    func counterTransferOffer(_ offerID: UUID, amount: Int) -> OfferOutcome {
        guard let index = state.transferOffers.firstIndex(where: { $0.id == offerID }) else { return .expired }
        var draft = state
        let offer = draft.transferOffers[index]
        let ask = max(0, amount)

        if ask <= offer.amount {
            sell(offer.playerID, price: offer.amount, in: &draft)
            return .accepted(offer.amount)
        }
        if ask <= offer.ceiling {
            sell(offer.playerID, price: ask, in: &draft)
            return .accepted(ask)
        }

        var pushed = offer
        pushed.patience = max(0, offer.patience - GameRules.transferOfferCounterPatienceCost)
        guard pushed.patience > 0 else {
            draft.transferOffers.removeAll { $0.id == offerID }
            commit(draft)
            return .withdrawn
        }
        pushed.amount = pushed.ceiling
        draft.transferOffers[index] = pushed
        commit(draft)
        return .improved(pushed.amount)
    }

    /// Moves a player out of the squad for an agreed fee, clearing every pending offer for
    /// him and every reference in the lineup and bench.
    private func sell(_ playerID: UUID, price: Int, in draft: inout GameState) {
        draft.clubCash += max(0, price)
        draft.players.removeAll { $0.id == playerID }
        for (key, value) in draft.lineup where value == playerID {
            draft.lineup.removeValue(forKey: key)
        }
        draft.bench.removeAll { $0 == playerID }
        draft.transferOffers.removeAll { $0.playerID == playerID }
        commit(draft)
    }

    func declineTransferOffer(_ offerID: UUID) {
        guard state.transferOffers.contains(where: { $0.id == offerID }) else { return }
        var draft = state
        draft.transferOffers.removeAll { $0.id == offerID }
        commit(draft)
    }

    /// Lists a squad player on the market so rival clubs can make offers.
    func setPlayerListed(_ playerID: UUID, listed: Bool) {
        guard state.players.contains(where: { $0.id == playerID }) else { return }
        var draft = state
        if let index = draft.players.firstIndex(where: { $0.id == playerID }) {
            draft.players[index].isUserListing = listed
        }
        if !listed {
            draft.transferOffers.removeAll { $0.playerID == playerID }
        }
        commit(draft)
    }

    /// Adds the level-up bonus to a draft, returning the levels gained so the UI can celebrate.
    private func applyXP(_ gained: Int, to draft: inout GameState) -> [Int] {
        let before = 1 + draft.xp / GameRules.xpPerLevel
        draft.xp += gained
        let after = 1 + draft.xp / GameRules.xpPerLevel
        guard after > before else { return [] }
        let levels = Array((before + 1)...after)
        let bonus = levels.count * GameRules.clubCashPerLevelUp * draft.players.count
        draft.clubCash += bonus
        return levels
    }

    /// Shows the level-up popup for the highest level reached, with the cash bonus paid out.
    func announceLevelUps(_ levels: [Int]) {
        guard let topLevel = levels.last else { return }
        levelUpAnnouncement = LevelUpAnnouncement(
            level: topLevel,
            bonus: levels.count * GameRules.clubCashPerLevelUp * state.players.count
        )
    }

    func commit(_ draft: GameState) {
        // The palette follows the managed club, so it is set before the new state is
        // published and every view redraws in the club's colours.
        TeamTheme.club = ClubDatabase.club(for: draft.managedClubID)
        state = draft
        do {
            try persistence.save(draft)
        } catch {
            saveErrorMessage = "Could not save your career: \(error.localizedDescription)"
        }
    }

    private func teamProfile(
        club: Club,
        userClubID: String,
        metrics: SquadMetrics,
        userScorers: [Player],
        season: Int
    ) -> MatchTeam {
        if club.id == userClubID {
            return MatchTeam(club: club, rating: Double(metrics.overall), scorers: userScorers)
        }
        var roster = PlayerFactory.databaseSquad(for: club.id, season: season, limit: 18)
        if roster.isEmpty {
            roster = PlayerFactory.aiRoster(club: club, season: season)
        }
        return MatchTeam(club: club, rating: Double(club.rating), scorers: roster)
    }

    private func weightedRarity(from weights: [PlayerRarity: Int]) -> PlayerRarity {
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return .silver }
        var roll = Int.random(in: 0..<total)
        for rarity in PlayerRarity.allCases {
            guard let weight = weights[rarity] else { continue }
            if roll < weight { return rarity }
            roll -= weight
        }
        return weights.keys.first ?? .silver
    }

    /// Ages every player by a year. Starters develop faster than squad players who did
    /// not feature in the XI, and players retire once they reach their retirement age.
    private func developPlayers(
        _ players: [Player],
        starters: Set<UUID>,
        using generator: inout SeededGenerator
    ) -> (players: [Player], retiredNames: [String], retiredIDs: [UUID]) {
        var developed: [Player] = []
        var retiredNames: [String] = []
        var retiredIDs: [UUID] = []
        for var player in players {
            let nextAge = player.age + 1
            if nextAge >= player.retirementAge {
                retiredNames.append(player.name)
                retiredIDs.append(player.id)
                continue
            }
            player.age = nextAge
            let isStarter = starters.contains(player.id)
            if nextAge <= 22 && player.overall < player.potential {
                let gain = isStarter
                    ? Int.random(in: 1...3, using: &generator)
                    : Int.random(in: 0...2, using: &generator)
                player.overall = min(player.potential, player.overall + gain)
            } else if nextAge <= 27 && player.overall < player.potential {
                if isStarter {
                    player.overall = min(player.potential, player.overall + Int.random(in: 0...1, using: &generator))
                } else if Int.random(in: 0..<3, using: &generator) == 0 {
                    player.overall = min(player.potential, player.overall + 1)
                }
            } else if nextAge >= 30 {
                player.overall = max(45, player.overall - Int.random(in: 0...2, using: &generator))
            }
            developed.append(player)
        }
        return (developed, retiredNames, retiredIDs)
    }

    private func phaseOrder(_ phase: SeasonPhase) -> Int {
        switch phase {
        case .league: 0
        case .playoffs: 1
        case .roundOf16: 2
        case .quarterfinal: 3
        case .semifinal: 4
        case .final: 5
        case .complete: 6
        }
    }

    private func registerStudyDay(_ stats: inout StudyStats, date: Date) {
        let calendar = Calendar.current
        if let lastDay = stats.lastStudyDay {
            if calendar.isDate(lastDay, inSameDayAs: date) {
                return
            }
            if calendar.isDateInYesterday(lastDay) {
                stats.currentStreak += 1
            } else {
                stats.currentStreak = 1
            }
        } else {
            stats.currentStreak = 1
        }
        stats.bestStreak = max(stats.bestStreak, stats.currentStreak)
        stats.lastStudyDay = date
    }
}
