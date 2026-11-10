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
                // Every accent, gradient and button tint in the app is read from the club's
                // palette, which lives outside SwiftUI's data flow. A view that only paints
                // a gradient therefore looks unchanged to SwiftUI and keeps the colours it
                // first drew with. Rebuilding the board whenever the palette changes forces
                // every one of those surfaces to be created again, in the new colours.
                .id(store.paletteKey)
        }
        Window("Appearance", id: appearanceWindowID) {
            AppearanceView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 320, height: 340)
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    /// Held above the board so that a palette change — which rebuilds the board — does not
    /// throw the player back to the dashboard.
    @State private var selection: MainSection = .dashboard

    var body: some View {
        if store.hasCareer {
            MainTabView(selection: $selection)
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
        }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Binding var selection: MainSection
    @State private var showingPalette = false
    @State private var showingResetConfirmation = false
    @State private var showingChangeTeam = false
    @State private var resetConfirmationsLeft = MainTabView.requiredResetConfirmations
    private static let requiredResetConfirmations = 5

    var body: some View {
        layoutBody
            .padding(12)
            .background(AppBackground(paletteKey: store.paletteKey))
            .background { shortcutButtons }
            .sheet(isPresented: $showingPalette) {
                CommandPaletteView(commands: paletteCommands) { showingPalette = false }
                    .environment(store)
            }
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

    /// ⌘K and ⌘1–⌘9. Invisible buttons are the cheapest way to give the whole board keyboard
    /// shortcuts without a menu bar entry for every section.
    private var shortcutButtons: some View {
        Group {
            Button("") { showingPalette = true }
                .keyboardShortcut("k", modifiers: .command)
            ForEach(Array(MainSection.allCases.prefix(9).enumerated()), id: \.offset) { index, section in
                Button("") { selection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var paletteCommands: [PaletteCommand] {
        var commands = MainSection.allCases.map { section in
            PaletteCommand(
                id: "section-\(section.rawValue)",
                title: "Go to \(section.title)",
                subtitle: "Section",
                symbol: section.systemImage
            ) {
                selection = section
            }
        }
        commands.append(
            PaletteCommand(
                id: "timer",
                title: store.isTimerRunning ? "Finish focus session" : "Start focus timer",
                subtitle: "Timer",
                symbol: "timer"
            ) {
                if store.isTimerRunning {
                    store.pauseTimer()
                } else {
                    store.startTimer()
                }
            }
        )
        commands.append(
            PaletteCommand(
                id: "appearance",
                title: "Open Appearance",
                subtitle: "Palette and layout",
                symbol: "paintpalette"
            ) {
                openWindow(id: appearanceWindowID)
            }
        )
        return commands
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
                appearanceButton
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

    /// Palette and layout, in the appearance window. The board is rebuilt whenever the
    /// palette changes, so the picker cannot live on it.
    private var appearanceButton: some View {
        Button {
            openWindow(id: appearanceWindowID)
        } label: {
            Label("Appearance", systemImage: "paintpalette")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.secondary)
                .glassChrome(cornerRadius: 999, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Palette and layout")
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
        }
    }
}


