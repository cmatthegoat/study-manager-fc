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
        // A wiring check for the cloud marker: fetches OpenRouter's catalogue without a key,
        // which proves the endpoint, the decoding and the image filter all work. It never
        // sends a paper, so it costs nothing.
        if CommandLine.arguments.contains("--verify-openrouter") {
            Self.runOpenRouterCheck()
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
    /// Lists the image-capable models OpenRouter is hosting right now, then exits. The key
    /// itself is never printed — only whether one is stored.
    fileprivate static func runOpenRouterCheck() {
        var finished = false
        Task {
            do {
                let models = try await OpenRouterClient.models()
                print("openrouter image models: \(models.count)")
                for model in models.prefix(6) {
                    print("  \(model.id) — \(model.displayName)")
                }
            } catch {
                print("openrouter models failed: \(error.localizedDescription)")
            }
            print("key stored: \(MarkingKeychain.hasKey)  preference: \(MarkingPreferences.preference.rawValue)  model: \(MarkingPreferences.model.isEmpty ? "(none)" : MarkingPreferences.model)")
            print("marking ready: \(MarkingService.isReady)")

            // With a key and model stored, mark one trivial question so the whole cloud path
            // — auth, status handling, reply decoding, JSON parsing — is proven end to end.
            // The key itself is never printed. This costs a fraction of a cent.
            if let key = MarkingKeychain.read(), !key.isEmpty, !MarkingPreferences.model.isEmpty {
                do {
                    let verdict = try await OpenRouterClient.test(key: key, model: MarkingPreferences.model)
                    print("key test: \(verdict)")
                } catch {
                    print("key test failed: \(error.localizedDescription)")
                }
            } else {
                print("key test skipped: no key or model stored, so nothing was sent.")
            }
            finished = true
        }
        while !finished {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(0)
    }

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
    case calendar
    case squad
    case transfers
    case europe
    case exams
    case journal
    case marking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .log: "Study Log"
        case .subjects: "Subjects"
        case .todos: "Todos"
        case .calendar: "Calendar"
        case .squad: "Squad"
        case .transfers: "Transfers"
        case .europe: "Champions League"
        case .exams: "Exams"
        case .journal: "Journal"
        case .marking: "AI Marking"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.line.uptrend.xyaxis"
        case .log: "clock.arrow.circlepath"
        case .subjects: "books.vertical"
        case .todos: "checklist"
        case .calendar: "calendar"
        case .squad: "person.3"
        case .transfers: "arrow.left.arrow.right"
        case .europe: "trophy"
        case .exams: "doc.text.magnifyingglass"
        case .journal: "shield.lefthalf.filled"
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
        layoutBody
            .padding(12)
            .background(AppBackground(paletteKey: store.paletteKey))
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

    /// The chosen arrangement. The rail layouts keep the page actions top-right; the top bar
    /// carries them, and the theme controls, in the bar itself.
    @ViewBuilder
    private var layoutBody: some View {
        switch store.layoutPreset {
        case .sidebar, .iconRail:
            HStack(spacing: 12) {
                AppSidebar(selection: $selection, compact: store.layoutPreset == .iconRail)
                VStack(spacing: 0) {
                    pageActions
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .topBar:
            VStack(spacing: 10) {
                topBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The page-level actions sit top-right, level with each screen's title.
    private var pageActions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            TransferOffersButton()
            changeTeamButton
            resetButton
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// The top-bar layout: identity, theme controls and page actions on the first row, every
    /// section as a pill beneath, so the board reads as one wide page.
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let club = store.managedClub {
                    ClubBadge(club: club, size: 26)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text((store.managedClub?.shortName ?? "Study FC").uppercased())
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.1)
                    Text("Season \(store.state.seasonNumber) · Lv \(store.level)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ThemeControls(vertical: false, menuWidth: 132)
                TransferOffersButton()
                changeTeamButton
                resetButton
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MainSection.allCases) { section in
                        topBarButton(section)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Neon.panel.opacity(0.86))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Neon.border, lineWidth: 1)
        )
        .shadow(color: Neon.accent.opacity(0.16), radius: 18)
    }

    private func topBarButton(_ section: MainSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 5) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule().fill(
                        LinearGradient(
                            colors: [Neon.accent.opacity(0.55), Neon.accentAlt.opacity(0.32)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(Capsule().stroke(Neon.accent.opacity(0.75), lineWidth: 1))
                    .shadow(color: Neon.accent.opacity(0.5), radius: 8)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(section.title)
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
            DashboardView(onOpenLog: { selection = .log }, onOpenCalendar: { selection = .calendar })
        case .log:
            StudyLogView()
        case .subjects:
            SubjectsView()
        case .todos:
            TodosView()
        case .calendar:
            CalendarView()
        case .squad:
            SquadView()
        case .transfers:
            TransfersView()
        case .europe:
            CompetitionView()
        case .exams:
            ExamsView()
        case .journal:
            BulletproofJournalView()
        case .marking:
            MarkingView()
        }
    }
}


