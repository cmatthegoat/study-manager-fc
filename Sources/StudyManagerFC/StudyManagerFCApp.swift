import Foundation
import SwiftUI

@main
struct StudyManagerFCApp: App {
    @State private var store = AppStore()

    init() {
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
        }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: MainSection = .dashboard
    @State private var showingResetConfirmation = false
    @State private var resetConfirmationsLeft = MainTabView.requiredResetConfirmations
    private static let requiredResetConfirmations = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SectionSwitcher(selection: $selection)
                TransferOffersButton()
                resetButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
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
                .background(Color.primary.opacity(0.05), in: Capsule())
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
                    .background(
                        selection == section ? Color.studyGreen.opacity(0.14) : Color.clear,
                        in: Capsule()
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
