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

/// One change to a player's fitness caused by the last match, so the result screen can say
/// who went down and who came back instead of leaving it to be discovered in the squad list.
struct InjuryUpdate: Identifiable, Hashable {
    var id = UUID()
    let playerName: String
    /// Matches the player will sit out. Zero means he has recovered and can be picked again.
    let matchesOut: Int

    var isRecovery: Bool { matchesOut == 0 }
}

struct SimulationOutcome {
    let userReport: MatchReport?
    let simulatedCount: Int
    let phasePlayed: SeasonPhase
    let championClub: Club?
    let trophy: TrophyRecord?
    /// New injuries and recoveries from this matchday, in the order they happened.
    var injuries: [InjuryUpdate] = []
    /// Prospects the academy promoted into the senior squad on this matchday. Empty unless
    /// the intake fell due.
    var academyIntake: [Player] = []
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
    /// Minutes banked by a paused timer. While this is set the session has not been filed
    /// yet, so its type, subject, topic and marks can still be edited before it is logged.
    var pendingTimerMinutes: Int?

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
        self.pendingTimerMinutes = nil
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
        purgeCompletedTodos()
        TeamTheme.club = managedClub
        SubjectTheme.apply(state.subjectColors)
    }

    /// The colour a subject is drawn in, falling back to its default until it is customised.
    func subjectColorHex(_ subject: StudySubject) -> String {
        SubjectTheme.hex(for: subject)
    }

    func setSubjectColor(_ hex: String, for subject: StudySubject) {
        guard let cleaned = Self.normalisedHex(hex) else { return }
        var draft = state
        draft.subjectColors[subject.rawValue] = cleaned
        commit(draft)
    }

    /// Hands a subject back to the default palette.
    func resetSubjectColor(for subject: StudySubject) {
        guard state.subjectColors[subject.rawValue] != nil else { return }
        var draft = state
        draft.subjectColors.removeValue(forKey: subject.rawValue)
        commit(draft)
    }

    /// Accepts `#RRGGBB`, `RRGGBB` or `RRGGBBAA` from the colour well and stores the six-digit
    /// form, so the saved palette stays one predictable shape.
    private static func normalisedHex(_ hex: String) -> String? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        guard cleaned.count == 6 || cleaned.count == 8,
              cleaned.allSatisfy(\.isHexDigit) else { return nil }
        return String(cleaned.prefix(6))
    }

    /// Tasks used to stay on the board once ticked. They are now cleared on completion, so any
    /// already-ticked tasks in an existing career are removed once and counted in the tally.
    private func purgeCompletedTodos() {
        let finished = state.todos.filter(\.isCompleted)
        guard !finished.isEmpty else { return }
        var draft = state
        draft.todos.removeAll(where: \.isCompleted)
        draft.tasksCompleted += finished.count
        commit(draft)
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
            let expectedReward = GameRules.earnedCash(
                Int((Double(GameRules.clubCashPerTodo) * StudySubject.ext1Maths.cashMultiplier).rounded())
            )
            // The figure the board advertises must be the figure it pays.
            guard app.todoReward(for: .ext1Maths) == expectedReward else {
                print("SELF TEST FAIL: the advertised todo reward is not the payout")
                exit(1)
            }
            let todoID = app.state.todos[0].id

            // Completing pays the cash first, then clears the task off the board.
            let paid = app.completeTodo(todoID)
            guard paid == expectedReward,
                  app.state.clubCash == startingCash + expectedReward,
                  app.state.todos.isEmpty,
                  app.state.tasksCompleted == 1 else {
                print("SELF TEST FAIL: completing a todo did not pay \(expectedReward) cash and clear it")
                exit(1)
            }

            // A second completion of the same task must not pay again.
            guard app.completeTodo(todoID) == nil,
                  app.state.clubCash == startingCash + expectedReward,
                  app.state.tasksCompleted == 1 else {
                print("SELF TEST FAIL: todo reward could be farmed")
                exit(1)
            }

            // A task ticked in an older career is cleared on load and still counted.
            var legacyTodos = state
            legacyTodos.todos = [
                TodoItem(id: UUID(), title: "Old tick", subject: .physics, isCompleted: true, createdAt: Date(), dueDate: nil, rewardAwarded: true),
                TodoItem(id: UUID(), title: "Still open", subject: .physics, isCompleted: false, createdAt: Date(), dueDate: nil)
            ]
            let legacyTodoStore = PersistenceStore(baseDirectory: tempDir.appendingPathComponent("todos", isDirectory: true))
            try legacyTodoStore.save(legacyTodos)
            let legacyApp = AppStore(persistence: legacyTodoStore)
            guard legacyApp.state.todos.count == 1,
                  legacyApp.state.todos[0].title == "Still open",
                  legacyApp.state.tasksCompleted == 1 else {
                print("SELF TEST FAIL: a ticked task from an older save was not cleared")
                exit(1)
            }

            // Subject colours are saved per subject, ignore malformed values, and reset.
            let defaultPhysics = SubjectTheme.hex(for: .physics)
            app.setSubjectColor("#ff00aa", for: .physics)
            guard app.state.subjectColors["physics"] == "FF00AA",
                  SubjectTheme.hex(for: .physics) == "FF00AA" else {
                print("SELF TEST FAIL: a subject colour did not save")
                exit(1)
            }
            app.setSubjectColor("nonsense", for: .physics)
            guard SubjectTheme.hex(for: .physics) == "FF00AA" else {
                print("SELF TEST FAIL: a malformed colour overwrote the subject colour")
                exit(1)
            }
            app.resetSubjectColor(for: .physics)
            guard app.state.subjectColors["physics"] == nil,
                  SubjectTheme.hex(for: .physics) == defaultPhysics else {
                print("SELF TEST FAIL: resetting a subject colour did not restore the default")
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
                  reloaded.todos.count == 3,
                  !reloaded.todos.contains(where: { $0.id == todoID }),
                  reloaded.tasksCompleted == 1,
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

            // Averages: marks pool by marks attempted, and two subjects with a topic of the
            // same name stay as separate bars instead of merging.
            func marked(
                _ subject: StudySubject,
                topic: String,
                _ obtained: Int,
                _ total: Int
            ) -> StudySession {
                StudySession(
                    id: UUID(),
                    date: Date(),
                    kind: .pastPaper,
                    title: topic,
                    minutes: 60,
                    cashEarned: 0,
                    xpEarned: 0,
                    quantity: 1,
                    subject: subject,
                    marksObtained: obtained,
                    marksTotal: total,
                    subtopicName: topic
                )
            }
            let pooled = [
                marked(.ext1Maths, topic: "Vectors", 18, 20),
                marked(.ext1Maths, topic: "Calculus", 5, 10),
                marked(.physics, topic: "Vectors", 3, 4)
            ]
            let bySubject = MarksAverages.bySubject(pooled)
            guard let mathsRow = bySubject.first(where: { $0.id == StudySubject.ext1Maths.shortName }),
                  mathsRow.pieces == 2,
                  mathsRow.obtained == 23,
                  mathsRow.total == 30,
                  mathsRow.percentage == 77 else {
                print("SELF TEST FAIL: subject averages did not pool marks attempted")
                exit(1)
            }
            let byTopic = MarksAverages.byTopic(pooled)
            let vectorRow = byTopic.first { $0.label.hasPrefix("Vectors · \(StudySubject.ext1Maths.shortName)") }
            guard byTopic.count == 3,
                  Set(byTopic.map(\.label)).count == 3,
                  vectorRow?.percentage == 90 else {
                print("SELF TEST FAIL: topic averages merged same-named topics or lost a percentage (rows=\(byTopic.count) labels=\(Set(byTopic.map(\.label)).count) prefix=\(byTopic.first(where: { $0.id.hasPrefix("\(StudySubject.ext1Maths.shortName)|Vectors") })?.percentage ?? -1) short=\(StudySubject.ext1Maths.shortName))")
                exit(1)
            }

            // Formations: the XI survives a shape change, the choice persists, and a career
            // saved before formations existed still opens as a 4-3-3.
            let formationStore = PersistenceStore(baseDirectory: tempDir.appendingPathComponent("formations", isDirectory: true))
            let tactical = AppStore(persistence: formationStore)
            try tactical.startCareer(with: "barcelona")
            guard tactical.formation == .f433, tactical.state.lineup.count == 11 else {
                print("SELF TEST FAIL: a new career did not start in a full 4-3-3 (\(tactical.state.lineup.count) picked)")
                exit(1)
            }
            tactical.setFormation(.f442)
            let switchedSlots = Set(Formation.f442.slots.map(\.id))
            guard tactical.formation == .f442,
                  tactical.state.lineup.count == 11,
                  Set(tactical.state.lineup.values).count == 11,
                  tactical.state.lineup.keys.allSatisfy({ switchedSlots.contains($0) }) else {
                print("SELF TEST FAIL: switching to a 4-4-2 left the XI \(tactical.state.lineup.count) players in \(tactical.state.lineup.count == Set(tactical.state.lineup.values).count ? "valid" : "duplicate") slots")
                exit(1)
            }
            let reloadedTactics = AppStore(persistence: formationStore)
            guard reloadedTactics.formation == .f442 else {
                print("SELF TEST FAIL: the chosen formation did not persist")
                exit(1)
            }
            if let saved = try? Data(contentsOf: formationStore.saveURL),
               var object = try? JSONSerialization.jsonObject(with: saved) as? [String: Any] {
                object.removeValue(forKey: "formation")
                try JSONSerialization.data(withJSONObject: object).write(to: formationStore.saveURL)
                let oldCareer = AppStore(persistence: formationStore)
                guard oldCareer.formation == .f433, oldCareer.state.lineup.count == 11 else {
                    print("SELF TEST FAIL: a save without a formation did not fall back to a 4-3-3")
                    exit(1)
                }
            }

            // Swapping two starters keeps both men on the pitch.
            let filledSlots = tactical.lineupSlots.compactMap { slot in
                tactical.state.lineup[slot.id].map { (slot.id, $0) }
            }
            if filledSlots.count >= 2 {
                let (firstSlotID, firstPlayerID) = filledSlots[0]
                let (secondSlotID, secondPlayerID) = filledSlots[1]
                tactical.assign(playerID: firstPlayerID, to: secondSlotID)
                guard tactical.state.lineup[secondSlotID] == firstPlayerID,
                      tactical.state.lineup[firstSlotID] == secondPlayerID else {
                    print("SELF TEST FAIL: swapping two starters dropped one of them out of the XI")
                    exit(1)
                }
            }

            // Injuries: a match can rule a starter out, the report names him, and he comes
            // back when his matches are up. Forced rolls keep this deterministic.
            var fitnessPlayers = market.state.players
            var forcedLineup: [String: UUID] = [:]
            var expectedInjuries = 0
            for slot in LineupSlot.all {
                guard let id = market.state.lineup[slot.id],
                      fitnessPlayers.contains(where: { $0.id == id }) else { continue }
                forcedLineup[slot.id] = id
                expectedInjuries += 1
            }
            let forced = AppStore.applyMatchFitness(players: &fitnessPlayers, lineup: forcedLineup, roll: { 0 })
            guard forced.count == expectedInjuries,
                  forced.allSatisfy({ !$0.isRecovery && $0.matchesOut == GameRules.injuryMatches && !$0.playerName.isEmpty }),
                  fitnessPlayers.filter({ $0.isInjured }).count == expectedInjuries else {
                print("SELF TEST FAIL: a match did not injure and report the starting XI")
                exit(1)
            }
            guard let hurtIndex = fitnessPlayers.firstIndex(where: { $0.isInjured }) else {
                print("SELF TEST FAIL: injuries were applied without an isInjured flag")
                exit(1)
            }
            let hurtName = fitnessPlayers[hurtIndex].name
            fitnessPlayers[hurtIndex].matchesMissed = 1
            let healed = AppStore.applyMatchFitness(players: &fitnessPlayers, lineup: forcedLineup, roll: { 1 })
            guard healed.contains(where: { $0.playerName == hurtName && $0.isRecovery }),
                  !fitnessPlayers[hurtIndex].isInjured else {
                print("SELF TEST FAIL: an injured player did not recover after his matches out")
                exit(1)
            }

            // An academy batch has to land in the squad. The free-agent pool has no screen,
            // so a prospect parked there was never actually delivered.
            var intakeState = GameState.fresh()
            intakeState.managedClubID = "arsenal"
            let delivered = AppStore.deliverAcademyIntake(level: 3, season: 1, into: &intakeState)
            guard delivered.count == GameRules.academyIntakePerSeason,
                  intakeState.players.count == GameRules.academyIntakePerSeason,
                  intakeState.freeAgents.isEmpty,
                  delivered.allSatisfy({ $0.potential >= $0.overall && $0.age <= 18 }) else {
                print("SELF TEST FAIL: an academy intake did not reach the squad")
                exit(1)
            }

            // A club's rating is the eleven it can field, not the EA club-level field: the
            // data file carries 94 for Real Madrid while their best XI averages far less.
            if let madrid = ClubDatabase.club(for: "real-madrid"),
               let madridXI = PlayerFactory.bestXIRating(for: "real-madrid") {
                guard madrid.rating == madridXI, madrid.rating < 94, madrid.rating >= 80 else {
                    print("SELF TEST FAIL: the club rating is not the XI average (\(madrid.rating) shown, \(madridXI) from the eleven)")
                    exit(1)
                }
            }

            // Changing team keeps the whole career and starts a new season at the new club.
            let moveStore = PersistenceStore(baseDirectory: tempDir.appendingPathComponent("move", isDirectory: true))
            let mover = AppStore(persistence: moveStore)
            try mover.startCareer(with: "barcelona")
            let seasonBefore = mover.state.seasonNumber
            let xpBefore = mover.state.xp
            let cashBefore = mover.state.clubCash
            let squadBefore = Set(mover.state.players.map(\.id))
            let lineupBefore = mover.state.lineup
            _ = try mover.changeClub(to: "real-madrid")
            guard mover.state.managedClubID == "real-madrid",
                  mover.state.seasonNumber == seasonBefore + 1,
                  mover.state.season?.number == seasonBefore + 1,
                  mover.state.xp == xpBefore,
                  mover.state.clubCash == cashBefore,
                  Set(mover.state.players.map(\.id)) == squadBefore,
                  mover.state.players.allSatisfy({ $0.clubID == "real-madrid" }),
                  mover.state.lineup == lineupBefore else {
                print("SELF TEST FAIL: changing team lost career data, left old club ids or did not start a new season")
                exit(1)
            }
            guard (try? mover.changeClub(to: "real-madrid")) == nil,
                  let movedSave = try moveStore.load(),
                  movedSave.managedClubID == "real-madrid",
                  movedSave.seasonNumber == seasonBefore + 1 else {
                print("SELF TEST FAIL: the club change was not saved, or the same club could be re-selected")
                exit(1)
            }

            // A new season heals everyone: nobody carries a knock or a countdown over.
            var wounded = market.state.players
            wounded[0].isInjured = true
            wounded[0].matchesMissed = 2
            wounded[1].isInjured = false
            wounded[1].matchesMissed = 1
            let freshSeasonSquad = AppStore.healedForNewSeason(wounded)
            guard freshSeasonSquad.count == wounded.count,
                  freshSeasonSquad.allSatisfy({ !$0.isInjured && $0.matchesMissed == 0 }) else {
                print("SELF TEST FAIL: a new season did not clear injuries")
                exit(1)
            }

            // Development is one curve for everybody: a bench teenager with a large gap gains
            // every single season and still arrives at his ceiling well before he declines.
            // No season is ever a dead one, whether or not he makes the eleven.
            var growthGenerator = SeededGenerator(seed: 24_680)
            var learner = Player(
                id: UUID(),
                name: "Test Prospect",
                nationCode: "ESP",
                position: .striker,
                age: 16,
                overall: 60,
                potential: 90,
                rarity: .wonderkid,
                attributes: PlayerAttributes(pace: 60, shooting: 60, passing: 60, defending: 40, physical: 55),
                retirementAge: GameRules.retirementAge,
                joinedSeason: 1
            )
            while learner.age < 32 {
                let before = learner.overall
                learner.age += 1
                if learner.age <= GameRules.growthUntilAge {
                    learner.overall = min(
                        learner.potential,
                        learner.overall + AppStore.seasonalGain(for: learner, at: learner.age, using: &growthGenerator)
                    )
                }
                if before < learner.potential, learner.age <= GameRules.growthUntilAge, learner.overall <= before {
                    print("SELF TEST FAIL: a developing player had a season with no progress at \(learner.age)")
                    exit(1)
                }
            }
            guard learner.overall == 90 else {
                print("SELF TEST FAIL: a prospect never reached his potential (stopped at \(learner.overall) of 90 by \(learner.age))")
                exit(1)
            }

            // An outstanding season earns a permanent point for the man who produced it, at
            // every position, measured against what his role was expected to deliver.
            func performancePlayer(_ name: String, _ position: PlayerPosition, overall: Int, age: Int) -> Player {
                Player(
                    id: UUID(),
                    name: name,
                    nationCode: "ESP",
                    position: position,
                    age: age,
                    overall: overall,
                    potential: overall,
                    rarity: .gold,
                    attributes: PlayerAttributes(pace: overall, shooting: overall, passing: overall, defending: overall, physical: overall),
                    retirementAge: GameRules.retirementAge,
                    joinedSeason: 1
                )
            }
            let keeper = performancePlayer("Test Keeper", .goalkeeper, overall: 80, age: 28)
            let back = performancePlayer("Test Back", .centerBack, overall: 80, age: 28)
            let striker = performancePlayer("Test Striker", .striker, overall: 80, age: 28)
            let quiet = performancePlayer("Test Quiet", .striker, overall: 80, age: 28)
            let performanceSquad = [keeper, back, striker, quiet]
            let performanceLineup = Dictionary(uniqueKeysWithValues: performanceSquad.enumerated().map { ("slot-\($0.offset)", $0.element.id) })
            var performanceReports: [MatchReport] = []
            for round in 0..<4 {
                var events: [MatchEvent] = []
                // Six goals: the centre back turns provider twice and the striker hauls in four.
                for index in 0..<6 {
                    events.append(
                        MatchEvent(
                            id: UUID(),
                            minute: index * 10 + 5,
                            clubID: "arsenal",
                            scorer: index < 4 ? striker.name : striker.name,
                            assister: index < 2 ? back.name : nil,
                            isPenalty: false
                        )
                    )
                }
                performanceReports.append(
                    MatchReport(
                        id: UUID(),
                        fixtureID: UUID(),
                        phase: .league,
                        round: round + 1,
                        homeClubID: "arsenal",
                        awayClubID: "chelsea",
                        homeGoals: 6,
                        awayGoals: 0,
                        homePenalties: nil,
                        awayPenalties: nil,
                        events: events,
                        homeRating: 80,
                        awayRating: 75,
                        summary: "",
                        playedAt: Date()
                    )
                )
            }
            let seasonRewards = SeasonPerformance.rewards(
                players: performanceSquad,
                lineup: performanceLineup,
                reports: performanceReports,
                clubID: "arsenal"
            )
            let rewardedNames = Set(seasonRewards.map(\.name))
            guard rewardedNames.contains(striker.name),
                  rewardedNames.contains(back.name),
                  !rewardedNames.contains(quiet.name),
                  seasonRewards.allSatisfy({ $0.gain == 1 && !$0.note.isEmpty }) else {
                print("SELF TEST FAIL: an outstanding season was not rewarded by position, or a quiet one was (\(seasonRewards.map(\.name)))")
                exit(1)
            }
            // A bonus never carries a man past his potential: it fills the last point of the gap
            // and no more. Someone already at the ceiling takes nothing but is spared the
            // decline, at any age, and everyone else still ages out.
            let capped = performancePlayer("Capped Star", .striker, overall: 80, age: 24)
            var rising = performancePlayer("Rising Star", .striker, overall: 78, age: 24)
            rising.potential = 80
            let veteran = performancePlayer("Veteran Star", .striker, overall: 80, age: 36)
            let fadedVeteran = performancePlayer("Faded Veteran", .striker, overall: 80, age: 33)
            let fading = performancePlayer("Fading Pro", .striker, overall: 80, age: 36)
            var bonusGenerator = SeededGenerator(seed: 77)
            let aged = AppStore.developPlayers(
                [capped, rising, veteran, fadedVeteran, fading],
                bonuses: [capped.id: 1, rising.id: 1, veteran.id: 1, fadedVeteran.id: 1],
                using: &bonusGenerator
            ).players
            let agedByID = Dictionary(uniqueKeysWithValues: aged.map { ($0.id, $0) })
            guard let agedCapped = agedByID[capped.id],
                  let agedRising = agedByID[rising.id],
                  let agedVeteran = agedByID[veteran.id],
                  let agedFaded = agedByID[fadedVeteran.id],
                  let agedFading = agedByID[fading.id],
                  agedCapped.overall == 80,
                  agedCapped.potential == 80,
                  agedRising.overall == 80,
                  agedRising.overall <= agedRising.potential,
                  agedVeteran.overall == 80,
                  agedFaded.overall == 80,
                  agedFading.overall <= 80 else {
                print("SELF TEST FAIL: a performance bonus went past potential, or a rewarded veteran still declined")
                exit(1)
            }
            // A player with room to grow is priced for his ceiling at any age — 80 with 90
            // potential sells as an 85 — and once he is past his peak the price falls each year.
            let youngProspect = PlayerPricing.valuation(overall: 80, potential: 90, age: 20)
            let veteranProspect = PlayerPricing.valuation(overall: 80, potential: 90, age: 33)
            let maxedTeenager = PlayerPricing.valuation(overall: 85, potential: 85, age: 20)
            let peakedThirtyFour = PlayerPricing.valuation(overall: 85, potential: 85, age: 34)
            let peakedThirtyEight = PlayerPricing.valuation(overall: 85, potential: 85, age: 38)
            guard youngProspect == PlayerPricing.fee(forOverall: 85),
                  veteranProspect < youngProspect,
                  maxedTeenager == PlayerPricing.fee(forOverall: 85),
                  peakedThirtyFour < maxedTeenager,
                  peakedThirtyEight < peakedThirtyFour,
                  peakedThirtyFour > 0 else {
                print("SELF TEST FAIL: potential or age did not set the price (\(youngProspect), \(veteranProspect), \(peakedThirtyFour), \(peakedThirtyEight))")
                exit(1)
            }

            // Timer review: a paused session is filed only when confirmed, and what lands
            // is the type, subject and marks chosen in the review sheet.
            let timerStore = PersistenceStore(baseDirectory: tempDir.appendingPathComponent("timer", isDirectory: true))
            let timer = AppStore(persistence: timerStore)
            try timer.startCareer(with: "arsenal")
            let cashBeforeTimer = timer.state.clubCash
            timer.pendingTimerMinutes = 3
            timer.timerKind = .pastPaper
            timer.timerSubject = .ext1Maths
            timer.timerMarksObtained = 8
            timer.timerMarksTotal = 10
            timer.confirmTimerSession()
            let timerReward = StudyReward.calculate(kind: .pastPaper, subject: .ext1Maths, minutes: 3, marksObtained: 8, marksTotal: 10)
            guard timer.pendingTimerMinutes == nil,
                  let loggedTimer = timer.state.recentSessions.first,
                  loggedTimer.kind == .pastPaper,
                  loggedTimer.subject == .ext1Maths,
                  loggedTimer.minutes == 3,
                  loggedTimer.marksObtained == 8,
                  loggedTimer.marksTotal == 10,
                  timer.state.clubCash == cashBeforeTimer + timerReward.cash else {
                print("SELF TEST FAIL: a confirmed timer session was not logged with the reviewed details")
                exit(1)
            }
            timer.pendingTimerMinutes = 4
            timer.discardTimerSession()
            guard timer.pendingTimerMinutes == nil, timer.state.recentSessions.count == 1 else {
                print("SELF TEST FAIL: discarding a paused session still filed it")
                exit(1)
            }

            // A perfect one-mark question is not a perfect paper: the same minutes must pay
            // more for 20/20 than for 1/1, while 1/1 still beats no marks at all.
            let tinyPerfect = StudyReward.calculate(kind: .pastPaper, subject: .ext1Maths, minutes: 30, marksObtained: 1, marksTotal: 1)
            let fullPerfect = StudyReward.calculate(kind: .pastPaper, subject: .ext1Maths, minutes: 30, marksObtained: 20, marksTotal: 20)
            let unmarkedWork = StudyReward.calculate(kind: .pastPaper, subject: .ext1Maths, minutes: 30, marksObtained: nil, marksTotal: nil)
            guard tinyPerfect.cash < fullPerfect.cash, tinyPerfect.cash > unmarkedWork.cash else {
                print("SELF TEST FAIL: marks volume did not change the reward for equal minutes")
                exit(1)
            }

            print("SELF TEST OK: todo round-trip, \(expectedReward) cash reward then cleared off the board (no double-pay, old ticked tasks purged on load), p1–p4 priority + #subject - topic parsing and sorting, created topics persist, study-log deletion persists, schema 6 adopts database potentials, transfer offers list/negotiate/sell, formation switching + migration + in-XI swaps, subject/topic mark averages, per-subject colours, injury report + recovery, marking JSON parsing, XI-based club ratings, change team keeping the career, injuries cleared at a new season, equal development to full potential, performance bonuses by position, potential-based valuations, academy intakes reaching the squad, timer sessions filed only after review")
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
        if draft.schemaVersion < 7 {
            // Academy batches used to be appended to the free-agent pool, which no screen in
            // the app ever shows, so every intake silently vanished. Rebuild the batches this
            // season has already paid for and hand them to the squad.
            let userMatches = draft.season?.fixtures.filter {
                ($0.homeClubID == draft.managedClubID || $0.awayClubID == draft.managedClubID)
                    && $0.isSimulated
            }.count ?? 0
            let owed = min(userMatches / GameRules.matchesPerAcademyIntake, 8)
            if owed > 0 {
                draft.players.append(
                    contentsOf: PlayerFactory.makeAcademyIntake(
                        level: draft.academyLevel,
                        season: draft.seasonNumber,
                        count: owed * GameRules.academyIntakePerSeason
                    )
                )
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

    /// The shape the XI is being picked in. Careers saved before formations get a 4-3-3.
    var formation: Formation { state.activeFormation }

    var lineupSlots: [LineupSlot] { formation.slots }

    var lineupIsComplete: Bool {
        lineupSlots.allSatisfy { slot in
            guard let id = state.lineup[slot.id] else { return false }
            return !(state.players.first(where: { $0.id == id })?.isInjured ?? true)
        }
    }

    var squadMetrics: SquadMetrics {
        SquadMetrics.calculate(lineup: state.lineup, players: state.players, slots: lineupSlots)
    }

    var userStartingPlayers: [Player] {
        MatchEngine.userMetricsLineup(players: state.players, lineup: state.lineup, slots: lineupSlots)
    }

    var benchPlayers: [Player] {
        state.bench.compactMap { id in state.players.first(where: { $0.id == id }) }
    }

    var lineupPlayersBySlot: [String: Player] {
        var result: [String: Player] = [:]
        for slot in lineupSlots {
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
        var fee: Int { PlayerPricing.valuation(overall: record.ovr, potential: record.potential, age: record.age) }
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
        let clubRating = ClubDatabase.club(for: listing.clubID)?.rating ?? 75
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

    /// Moves the career to another club. Everything the manager has built travels with him —
    /// squad, XP and level, Club Cash, trophies, study history, todos and assessments — and
    /// only the club and the season change. The abandoned season is not aged: players grow
    /// and retire at the end of a season, and a move is not the end of one.
    func changeClub(to clubID: String) throws -> Club {
        guard hasCareer else { throw GameError.noCareer }
        guard let club = ClubDatabase.club(for: clubID) else { throw GameError.invalidClub }
        guard club.id != state.managedClubID else { throw GameError.invalidState }

        var draft = state
        draft.managedClubID = club.id
        // The squad follows the manager, so it belongs to the new club from now on. Leaving
        // the old club id on them would list them for sale by a club they no longer play for.
        for index in draft.players.indices {
            draft.players[index].clubID = club.id
        }
        draft.seasonNumber += 1
        draft.season = SeasonEngine.newSeason(number: draft.seasonNumber)
        draft.lastTransition = nil
        draft.matchesSinceAcademyIntake = 0
        // A move starts a new season, so it heals like one.
        draft.players = Self.healedForNewSeason(draft.players)
        draft.freeAgents = Self.healedForNewSeason(draft.freeAgents)
        commit(draft)
        return club
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
        GameRules.earnedCash(Int((Double(GameRules.clubCashPerTodo) * subject.cashMultiplier).rounded()))
    }

    /// Ticks a task off: pays its Club Cash and then removes it from the board, so a
    /// finished task leaves nothing behind. Returns the cash paid, or nil when the task
    /// was already gone.
    @discardableResult
    func completeTodo(_ id: UUID) -> Int? {
        guard let todo = state.todos.first(where: { $0.id == id }) else { return nil }
        var draft = state
        var paid = 0
        // Older tasks could be ticked and unticked; the reward is still only ever paid once.
        if !todo.rewardAwarded {
            paid = todoReward(for: todo.subject ?? .other)
            draft.clubCash += paid
        }
        draft.todos.removeAll { $0.id == id }
        draft.tasksCompleted += 1
        commit(draft)
        return paid
    }

    /// Points the timer at an open todo and takes its subject and topic, so the logged work lands there.
    func setTimerTodo(_ id: UUID?) {
        timerTodoID = id
        guard let id, let todo = state.todos.first(where: { $0.id == id }) else { return }
        timerSubject = todo.subject ?? .other
        timerSubtopicID = todo.subtopicID
    }

    func startTimer() {
        guard !isTimerRunning, pendingTimerMinutes == nil else { return }
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

    /// Stops the clock and banks its minutes without filing anything. The dashboard opens a
    /// review sheet so the work can be given a type, subject, topic and marks first.
    func pauseTimer() {
        guard isTimerRunning else { return }
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
        let minutes = timerCreditedMinutes
        timerCreditedMinutes = 0
        guard minutes > 0 else {
            timerElapsedSeconds = 0
            pendingTimerMinutes = nil
            timerTodoID = nil
            return
        }
        pendingTimerMinutes = minutes
    }

    /// Files the paused session using whatever was set in the review sheet. Nothing is paid
    /// while the clock runs, so switching the type at the end cannot pay the same minute twice.
    func confirmTimerSession() {
        guard let minutes = pendingTimerMinutes else { return }
        let kind = timerKind
        let marksObtained = kind.supportsMarking ? timerMarksObtained : nil
        let marksTotal = kind.supportsMarking ? timerMarksTotal : nil
        pendingTimerMinutes = nil
        lastTimerSessionMinutes = minutes
        timerElapsedSeconds = 0
        timerMarksObtained = nil
        timerMarksTotal = nil
        timerTodoID = nil
        logStudy(
            kind: kind,
            title: "",
            minutes: minutes,
            quantity: 1,
            subject: timerSubject,
            subtopicID: timerSubtopicID,
            marksObtained: marksObtained,
            marksTotal: marksTotal
        )
    }

    /// Throws a paused session away: nothing is logged and nothing is paid.
    func discardTimerSession() {
        pendingTimerMinutes = nil
        timerElapsedSeconds = 0
        timerCreditedMinutes = 0
        timerMarksObtained = nil
        timerMarksTotal = nil
        timerTodoID = nil
    }

    func resetTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
        timerElapsedSeconds = 0
        timerCreditedMinutes = 0
        pendingTimerMinutes = nil
    }

    func assign(playerID: UUID, to slotID: String) {
        guard let slot = lineupSlots.first(where: { $0.id == slotID }), player(for: playerID) != nil else { return }
        var draft = state
        let previousSlotID = draft.lineup.first(where: { $0.value == playerID })?.key
        let occupant = draft.lineup[slot.id]
        for (key, value) in draft.lineup where value == playerID {
            draft.lineup.removeValue(forKey: key)
        }
        draft.lineup[slot.id] = playerID
        draft.bench.removeAll { $0 == playerID }
        // Moving a player within the XI swaps him with whoever held the slot, so a shuffle
        // never quietly drops a starter out of the side.
        if let previousSlotID,
           previousSlotID != slot.id,
           let occupant,
           occupant != playerID,
           lineupSlots.contains(where: { $0.id == previousSlotID }) {
            draft.lineup[previousSlotID] = occupant
            draft.bench.removeAll { $0 == occupant }
        }
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
        let emptySlots = lineupSlots.filter { draft.lineup[$0.id] == nil }
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
        let result = PlayerFactory.autoLineup(players: state.players, formation: formation)
        var draft = state
        draft.lineup = result.0
        draft.bench = result.1
        commit(draft)
    }

    /// Switches the XI to another shape. Players keep their place wherever the new formation
    /// has the same slot, and the vacancies a new shape creates are filled from the players it
    /// displaced, then the bench, then the squad — so changing formation never halves your XI.
    func setFormation(_ newFormation: Formation) {
        guard newFormation != formation, state.managedClubID != nil else { return }
        var draft = state
        let playerMap = Dictionary(uniqueKeysWithValues: draft.players.map { ($0.id, $0) })
        let newSlotIDs = Set(newFormation.slots.map(\.id))

        var kept: [String: UUID] = [:]
        for slot in newFormation.slots {
            guard let id = draft.lineup[slot.id], playerMap[id] != nil else { continue }
            kept[slot.id] = id
        }

        let keptIDs = Set(kept.values)
        var displaced: [UUID] = []
        for (slotID, playerID) in draft.lineup where !newSlotIDs.contains(slotID) {
            if !keptIDs.contains(playerID), !displaced.contains(playerID) {
                displaced.append(playerID)
            }
        }

        var pool: [Player] = displaced.compactMap { playerMap[$0] }
        let poolIDs = Set(pool.map(\.id))
        for id in draft.bench where !keptIDs.contains(id) && !poolIDs.contains(id) {
            if let player = playerMap[id] { pool.append(player) }
        }
        for player in draft.players
        where !keptIDs.contains(player.id) && !pool.contains(where: { $0.id == player.id }) {
            pool.append(player)
        }

        for slot in newFormation.slots where kept[slot.id] == nil {
            guard let best = pool.max(by: { lhs, rhs in
                let left = lhs.adjustedRating(for: slot)
                let right = rhs.adjustedRating(for: slot)
                if left == right { return lhs.overall < rhs.overall }
                return left < right
            }) else { break }
            kept[slot.id] = best.id
            pool.removeAll { $0.id == best.id }
        }

        draft.formation = newFormation
        draft.lineup = kept
        draft.bench.removeAll { kept.values.contains($0) }
        // Anyone the new shape dropped takes a free bench place rather than dropping off the
        // matchday squad entirely.
        for id in displaced where !kept.values.contains(id) && draft.bench.count < GameRules.benchLimit {
            if !draft.bench.contains(id) { draft.bench.append(id) }
        }
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
        entry.cashEarned = GameRules.earnedCash(
            Int((Double(GameRules.assessmentBaseCash) * cashMultiplier * GameRules.examRewardMultiplier * rankFactor).rounded())
        )
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
        var injuries: [InjuryUpdate] = []
        var academyIntake: [Player] = []
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
                injuries.append(
                    contentsOf: Self.applyMatchFitness(
                        players: &state.players,
                        lineup: state.lineup,
                        slots: lineupSlots
                    )
                )
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
                academyIntake = Self.deliverAcademyIntake(
                    level: draft.academyLevel,
                    season: draft.seasonNumber,
                    into: &draft
                )
            }
        }
        commit(draft)

        return SimulationOutcome(
            userReport: userReport,
            simulatedCount: simulatedCount,
            phasePlayed: phasePlayed,
            championClub: ClubDatabase.club(for: season.championClubID),
            trophy: trophy,
            injuries: injuries,
            academyIntake: academyIntake
        )
    }

    /// Promotes one academy batch into the senior squad and returns the men who joined.
    /// They belong in `players`, not the free-agent pool: the pool is only a source the
    /// pack and market code draws from, and no screen ever lists its contents.
    static func deliverAcademyIntake(level: Int, season: Int, into draft: inout GameState) -> [Player] {
        let intake = PlayerFactory.makeAcademyIntake(
            level: level,
            season: season,
            count: GameRules.academyIntakePerSeason
        )
        draft.players.append(contentsOf: intake)
        return intake
    }

    /// Fitness bookkeeping for one match: existing injuries count down, then each fit starter
    /// has a chance of going down. Returns every change so the result screen can name them.
    /// `roll` is injectable so the self-test can force an injury instead of waiting on a 5% chance.
    static func applyMatchFitness(
        players: inout [Player],
        lineup: [String: UUID],
        slots: [LineupSlot] = LineupSlot.all,
        roll: () -> Double = { Double.random(in: 0..<1) }
    ) -> [InjuryUpdate] {
        var updates: [InjuryUpdate] = []
        // Count down existing injuries first, so new injuries keep their full penalty.
        for i in players.indices where players[i].matchesMissed > 0 {
            players[i].matchesMissed -= 1
            if players[i].matchesMissed == 0 {
                players[i].isInjured = false
                updates.append(InjuryUpdate(playerName: players[i].name, matchesOut: 0))
            }
        }
        for slot in slots {
            guard let playerID = lineup[slot.id],
                  let index = players.firstIndex(where: { $0.id == playerID })
            else { continue }
            if !players[index].isInjured && roll() < GameRules.injuryChance {
                players[index].isInjured = true
                players[index].matchesMissed = GameRules.injuryMatches
                updates.append(
                    InjuryUpdate(playerName: players[index].name, matchesOut: GameRules.injuryMatches)
                )
            }
        }
        return updates
    }

    /// Pre-season is long enough for every knock to clear, so a new season starts with a
    /// clean bill of health: no injured player, and nobody carrying a countdown into it.
    static func healedForNewSeason(_ players: [Player]) -> [Player] {
        players.map { player in
            guard player.isInjured || player.matchesMissed > 0 else { return player }
            var healed = player
            healed.isInjured = false
            healed.matchesMissed = 0
            return healed
        }
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
        // Men who carried the season get a point on top of the normal curve. It is measured
        // from the season that has just finished, before anyone is aged.
        let rewards = SeasonPerformance.rewards(
            players: state.players,
            lineup: state.lineup,
            reports: season.reports,
            clubID: managedClub.id
        )
        let bonuses = Dictionary(rewards.map { ($0.id, $0.gain) }, uniquingKeysWith: +)
        let squadResult = Self.developPlayers(state.players, bonuses: bonuses, using: &generator)
        let poolResult = Self.developPlayers(state.freeAgents, using: &generator)

        var draft = state
        draft.players = squadResult.players
        draft.freeAgents = poolResult.players
        draft.players = Self.healedForNewSeason(draft.players)
        draft.freeAgents = Self.healedForNewSeason(draft.freeAgents)
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
            newSeason: draft.seasonNumber,
            improvements: rewards.filter { !retiredIDs.contains($0.id) }
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
        // Minutes are only counted here. Cash, XP, match minutes and the log entry all wait
        // for the review sheet, so the type, subject, topic and marks can change right up
        // until the session is confirmed.
        timerCreditedMinutes += 1
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
        let bonus = GameRules.earnedCash(levels.count * GameRules.clubCashPerLevelUp * draft.players.count)
        draft.clubCash += bonus
        return levels
    }

    /// Shows the level-up popup for the highest level reached, with the cash bonus paid out.
    func announceLevelUps(_ levels: [Int]) {
        guard let topLevel = levels.last else { return }
        levelUpAnnouncement = LevelUpAnnouncement(
            level: topLevel,
            bonus: GameRules.earnedCash(levels.count * GameRules.clubCashPerLevelUp * state.players.count)
        )
    }

    func commit(_ draft: GameState) {
        // The palette follows the managed club, so it is set before the new state is
        // published and every view redraws in the club's colours.
        TeamTheme.club = ClubDatabase.club(for: draft.managedClubID)
        SubjectTheme.apply(draft.subjectColors)
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

    /// Ages every player by a year. Every player develops on the same curve — the eleven
    /// gets no advantage — and everybody under `GameRules.growthUntilAge` who is short of
    /// their potential improves by enough to reach it by `GameRules.potentialDeadlineAge`.
    /// Players retire once they reach their retirement age.
    static func developPlayers(
        _ players: [Player],
        bonuses: [UUID: Int] = [:],
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
            let bonus = bonuses[player.id] ?? 0
            if nextAge <= GameRules.growthUntilAge && player.overall < player.potential {
                player.overall = min(
                    player.potential,
                    player.overall + Self.seasonalGain(for: player, at: nextAge, using: &generator)
                )
            } else if nextAge >= 30 && bonus == 0 {
                // A man who carried the season does not decline with it.
                player.overall = max(45, player.overall - Int.random(in: 0...2, using: &generator))
            }
            // The bonus closes part of the gap to the ceiling but never breaches it: potential
            // is the ceiling a player was signed on, so a good season inside it is worth a
            // point and a man already standing on it takes nothing more. He still does not
            // decline, though — the season he carried is the one thing that holds his rating.
            if bonus > 0 && nextAge <= GameRules.performanceBonusMaxAge {
                player.overall = max(player.overall, min(player.potential, player.overall + bonus))
            }
            developed.append(player)
        }
        return (developed, retiredNames, retiredIDs)
    }

    /// How many points a developing player gains this season. The floor is the gap to their
    /// potential split over the seasons they have left before the deadline, so the ceiling is
    /// reached on time no matter how big the gap is. A one-point spread keeps two teenagers
    /// with the same rating from moving in lockstep, without ever allowing a dead season.
    static func seasonalGain(for player: Player, at nextAge: Int, using generator: inout SeededGenerator) -> Int {
        let gap = player.potential - player.overall
        guard gap > 0 else { return 0 }
        let seasonsLeft = max(1, GameRules.potentialDeadlineAge - nextAge)
        let baseline = Int(ceil(Double(gap) / Double(seasonsLeft)))
        let spread = nextAge <= 22 ? Int.random(in: 0...1, using: &generator) : 0
        return max(1, baseline + spread)
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
