import Foundation
import SwiftUI

@main
struct StudyManagerFCApp: App {
    @State private var store = AppStore()

    init() {
        // A diagnostic for the marking pipeline: availability, an optional file to OCR, and a
        // small paper marked with the real on-device model.
        if let flag = CommandLine.arguments.firstIndex(of: "--verify-marking") {
            let path = CommandLine.arguments.count > flag + 1 ? CommandLine.arguments[flag + 1] : nil
            Self.runMarkingCheck(path: path)
        }
        // A packaging check: the game database lives beside the app, and this proves the
        // shipped bundle can find and decode it without opening a window.
        if CommandLine.arguments.contains("--verify-database") {
            let database = FcDatabase.shared
            // A bundle carrying a data file whose potentials are all equal to the overalls
            // is stale: transfers and squad ceilings then look frozen.
            let filled = database.players.filter { $0.pot > $0.ovr }.count
            print("clubs=\(database.clubs.count) players=\(database.players.count) loaded=\(database.isLoaded) potentials-filled=\(filled)")
            exit(database.isLoaded ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

extension StudyManagerFCApp {
    /// Runs the marking diagnostic and exits. Waiting on the model needs the main run loop
    /// alive, so this pumps it rather than blocking on a semaphore.
    fileprivate static func runMarkingCheck(path: String?) {
        print("marking availability: \(MarkingService.availability)")
        if let path {
            do {
                let text = try PaperText.text(from: URL(fileURLWithPath: path))
                let preview = text.prefix(160).replacingOccurrences(of: "\n", with: " ")
                print("ocr chars: \(text.count)")
                print("ocr preview: \(preview)")
            } catch {
                print("ocr failed: \(error.localizedDescription)")
            }
        }
        guard MarkingService.availability.isAvailable else { exit(3) }

        let answer = "Q1: 2x = 10, so x = 5. Q2: the derivative of x^2 + 7x at x = 1 is 2x + 7, so the gradient is 9."
        let request = MarkingRequest(
            subject: .ext1Maths,
            title: "Diagnostic paper",
            totalMarks: 10,
            answerText: answer,
            guidelinesText: "Q1 (5 marks): correct value of x with working. Q2 (5 marks): correct gradient of 9.",
            comments: ""
        )
        // The same work with no rubric at all, to prove guidelines are optional end to end.
        let unguided = MarkingRequest(
            subject: .ext1Maths,
            title: "Diagnostic paper (no rubric)",
            totalMarks: 10,
            answerText: answer,
            guidelinesText: "",
            comments: ""
        )
        var finished = false
        Task {
            do {
                let result = try await MarkingService.mark(request)
                print("marked with rubric: \(result.totalAwarded)/\(result.totalOutOf) across \(result.questions.count) questions")
                for question in result.questions {
                    print("  \(question.question): \(question.awarded)/\(question.outOf) — \(question.reason)")
                }
                print("feedback: \(result.feedback)")

                let unrubricked = try await MarkingService.mark(unguided)
                print("marked WITHOUT rubric: \(unrubricked.totalAwarded)/\(unrubricked.totalOutOf) across \(unrubricked.questions.count) questions")
                for question in unrubricked.questions {
                    print("  \(question.question): \(question.awarded)/\(question.outOf) — \(question.reason)")
                }
                print("feedback: \(unrubricked.feedback)")
            } catch {
                print("mark failed: \(error.localizedDescription)")
            }
            finished = true
        }
        while !finished {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.hasCareer {
            MainTabView()
        } else {
            ClubSelectionView()
        }
    }
}

enum MainSection: String, CaseIterable, Identifiable {
    case dashboard
    case log
    case subjects
    case todos
    case squad
    case transfers
    case europe
    case exams
    case marking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .log: "Study Log"
        case .subjects: "Subjects"
        case .todos: "Todos"
        case .squad: "Squad"
        case .transfers: "Transfers"
        case .europe: "Champions League"
        case .exams: "Exams"
        case .marking: "AI Marking"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.line.uptrend.xyaxis"
        case .log: "clock.arrow.circlepath"
        case .subjects: "books.vertical"
        case .todos: "checklist"
        case .squad: "person.3"
        case .transfers: "arrow.left.arrow.right"
        case .europe: "trophy"
        case .exams: "doc.text.magnifyingglass"
        case .marking: "wand.and.stars"
        }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: MainSection = .dashboard
    @State private var showingResetConfirmation = false
    @State private var showingChangeTeam = false
    @State private var resetConfirmationsLeft = MainTabView.requiredResetConfirmations
    private static let requiredResetConfirmations = 5

    var body: some View {
        VStack(spacing: 0) {
            // A floating glass command bar rather than a full-width strip with a rule under
            // it: the sections, offers, change team and reset all live on one lit panel.
            HStack(spacing: 8) {
                SectionSwitcher(selection: $selection)
                TransferOffersButton()
                changeTeamButton
                resetButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassChrome(cornerRadius: 20)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
        .sheet(isPresented: $showingChangeTeam) {
            ChangeTeamSheet()
                .environment(store)
        }
        .alert(
            "Level up!",
            isPresented: Binding(
                get: { store.levelUpAnnouncement != nil },
                set: { if !$0 { store.levelUpAnnouncement = nil } }
            )
        ) {
            Button("Keep going") { store.levelUpAnnouncement = nil }
        } message: {
            if let announcement = store.levelUpAnnouncement {
                Text("Your squad reached level \(announcement.level). Every player earns \(GameRules.clubCashPerLevelUp.formatted()) Club Cash, which is \(announcement.bonus.formatted()) in total.")
            }
        }
        .alert("Reset all progress?", isPresented: $showingResetConfirmation) {
            Button("Reset Everything", role: .destructive) {
                resetConfirmationsLeft -= 1
                if resetConfirmationsLeft == 0 {
                    store.resetCareer()
                } else {
                    // Re-present after the alert finishes dismissing so the next confirmation shows.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingResetConfirmation = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                resetConfirmationsLeft = MainTabView.requiredResetConfirmations
            }
        } message: {
            Text("This permanently deletes your club, squad, trophies, Club Cash and study history, then returns you to club selection. Confirm \(resetConfirmationsLeft) more time\(resetConfirmationsLeft == 1 ? "" : "s") to continue.")
        }
    }

    /// Changing club keeps the career and starts a new season, so it lives beside Reset in
    /// the top bar — out of the way, but always one click from anywhere in the app.
    private var changeTeamButton: some View {
        Button {
            showingChangeTeam = true
        } label: {
            Label("Change Team", systemImage: "arrow.left.arrow.right.circle")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.secondary)
                .glassChrome(cornerRadius: 999, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Change club and start a new season")
    }

    private var resetButton: some View {
        Button {
            resetConfirmationsLeft = MainTabView.requiredResetConfirmations
            showingResetConfirmation = true
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.secondary)
                .glassChrome(cornerRadius: 999, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Reset all progress")
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .dashboard:
            DashboardView(onOpenLog: { selection = .log })
        case .log:
            StudyLogView()
        case .subjects:
            SubjectsView()
        case .todos:
            TodosView()
        case .squad:
            SquadView()
        case .transfers:
            TransfersView()
        case .europe:
            CompetitionView()
        case .exams:
            ExamsView()
        case .marking:
            MarkingView()
        }
    }
}

private struct SectionSwitcher: View {
    @Binding var selection: MainSection

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(section.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(selection == section ? Color.studyGreen : Color.secondary)
                    .glassChrome(
                        cornerRadius: 999,
                        tint: selection == section ? Color.studyGreen.opacity(0.35) : nil,
                        interactive: selection == section
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(section.title)
            }
            Spacer()
        }
    }
}
