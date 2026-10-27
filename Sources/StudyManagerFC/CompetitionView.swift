import SwiftUI

struct CompetitionView: View {
    @Environment(AppStore.self) private var store
    @State private var report: MatchReport?
    @State private var errorMessage: String?

    private var season: SeasonState? { store.season }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                HStack(alignment: .top, spacing: 18) {
                    matchdayCard
                    seasonStatusCard
                        .frame(width: 330)
                }
                standingsCard
                scoringLeaderboardCard
                if !store.latestReports.isEmpty {
                    resultsCard
                }
                if !store.trophies.isEmpty {
                    trophyCard
                }
            }
            .padding(28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $report) { matchReport in
            MatchReportSheet(report: matchReport, userClubID: store.state.managedClubID)
                .environment(store)
        }
        .alert("Could Not Simulate", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            ScreenHeader(
                eyebrow: "Season \(store.state.seasonNumber) · \(season?.phase.displayName ?? "No Season")",
                title: "Champions League",
                subtitle: "Log study minutes to unlock each matchday, then simulate the round and chase the trophy."
            )
            Spacer()
            if let club = store.managedClub {
                ClubBadge(club: club, size: 66)
            }
        }
    }

    private var matchdayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: store.isSeasonComplete ? "Season Complete" : "Next Match",
                subtitle: matchdaySubtitle,
                symbol: "soccerball"
            )

            if store.isSeasonComplete {
                seasonCompleteContent
            } else if let fixture = store.userCurrentFixture, let club = store.managedClub, let season {
                fixtureContent(fixture: fixture, club: club, season: season)
            } else {
                spectatorContent
            }

            if !store.isSeasonComplete {
                simulateControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 20)
    }

    private var matchdaySubtitle: String {
        guard let season else { return "No active season" }
        switch season.phase {
        case .league:
            return "Matchday \(min(season.nextLeagueRound, 8)) of 8 · \(store.currentFixtures.count) matches"
        case .complete:
            return "Season \(season.number) is in the books"
        default:
            return "\(season.phase.displayName) · \(store.currentFixtures.count) matches"
        }
    }

    private func fixtureContent(fixture: Fixture, club: Club, season: SeasonState) -> some View {
        let home = ClubDatabase.club(for: fixture.homeClubID)
        let away = ClubDatabase.club(for: fixture.awayClubID)
        let isHome = fixture.homeClubID == club.id

        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                teamBlock(home, isUser: home?.id == club.id)
                VStack(spacing: 4) {
                    if fixture.isSimulated {
                        Text(fixture.scoreline)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                    } else {
                        Text("VS")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(isHome ? "HOME" : "AWAY")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color.studyGreen)
                }
                .frame(width: 96)
                teamBlock(away, isUser: away?.id == club.id)
            }
            .padding(.vertical, 6)

            HStack(spacing: 10) {
                Pill(text: season.phase.shortName.uppercased(), color: .studyGold, icon: "flag.checkered")
                Pill(
                    text: store.lineupIsComplete ? "XI READY" : "XI INCOMPLETE",
                    color: store.lineupIsComplete ? .studyGreen : .orange,
                    icon: store.lineupIsComplete ? "checkmark" : "exclamationmark"
                )
                Pill(
                    text: "\(store.squadMetrics.overall) OVR · \(store.squadMetrics.chemistry) CHEM",
                    color: .studyTeal,
                    icon: "chart.bar"
                )
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Match readiness")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("\(min(store.state.availableMatchMinutes, GameRules.minutesPerMatch)) / \(GameRules.minutesPerMatch) min")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(store.matchReadiness >= 1 ? Color.studyGreen : Color.secondary)
                }
                ReadinessBar(progress: store.matchReadiness, height: 8)
            }

            if let blocker = blockingReason {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(blocker)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var spectatorContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.studyTeal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No fixture for your club")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Simulating plays the rest of the round. Later rounds will include you if you qualify.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.studyTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let fixture = store.nextFixtureForUser, let club = store.managedClub {
                let opponentID = fixture.homeClubID == club.id ? fixture.awayClubID : fixture.homeClubID
                let opponent = ClubDatabase.club(for: opponentID)
                HStack(spacing: 10) {
                    if let opponent { ClubBadge(club: opponent, size: 30) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("NEXT UP")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text("\(fixture.homeClubID == club.id ? "vs" : "away at") \(opponent?.shortName ?? "TBD")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    Text(fixture.phase == .league ? "Matchday \(fixture.round)" : fixture.phase.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var simulateControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                simulate()
            } label: {
                Label(store.stageButtonLabel, systemImage: "flag.checkered")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)
            .disabled(!store.canSimulateCurrentStage)

            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(store.userCurrentFixture == nil
                     ? "Spectating: simulating does not use your study minutes."
                     : "Simulating your match uses \(GameRules.minutesPerMatch) study minutes.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var seasonCompleteContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let champion = store.championClub {
                    ClubBadge(club: champion, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.season?.number ?? 0) CHAMPIONS")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.studyGold)
                        Text(champion.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("You finished: \(store.finalUserFinish)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.studyGold)
                    Text("The trophy has been lifted.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                Spacer()
            }

            Button {
                startNextSeason()
            } label: {
                Label("Start Season \(store.state.seasonNumber + 1)", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)

            Text("Players age and improve, retirements open up space, and a new crop of youth prospects joins the free-agent pool.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var seasonStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Season Status", subtitle: "Your European campaign", symbol: "chart.line.uptrend.xyaxis")

            statusRow(label: "Phase", value: season?.phase.displayName ?? "—", tint: .studyGreen)
            statusRow(label: "League position", value: SeasonEngine.ordinal(store.userLeaguePosition), tint: .studyTeal)
            statusRow(
                label: "Study bank",
                value: "\(store.state.availableMatchMinutes) min",
                tint: .studyGold
            )
            statusRow(label: "Titles won", value: "\(store.userTitles)", tint: .studyGold)
            statusRow(label: "Seasons completed", value: "\(store.completedSeasons)", tint: .studyGreen)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("TOURNAMENT")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(store.userTournamentStatus)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 20)
    }

    private func statusRow(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var standingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    title: "League Phase Table",
                    subtitle: "36 clubs · 8 matches each · top 8 straight to the Round of 16",
                    symbol: "list.number"
                )
                Spacer()
                Text("Simulated \(store.season?.leagueRoundsPlayed ?? 0) / 8 matchdays")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            standingsHeader

            VStack(spacing: 2) {
                ForEach(Array(store.standings.enumerated()), id: \.element.id) { index, row in
                    standingsRow(rank: index + 1, row: row)
                }
            }

            HStack(spacing: 16) {
                legend(color: .studyGreen, text: "Round of 16")
                legend(color: .studyGold, text: "Knockout playoff")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var standingsHeader: some View {
        HStack(spacing: 8) {
            Text("#")
                .frame(width: 24, alignment: .trailing)
            Text("CLUB")
                .frame(maxWidth: .infinity, alignment: .leading)
            statHeader("P")
            statHeader("W")
            statHeader("D")
            statHeader("L")
            statHeader("GF")
            statHeader("GA")
            statHeader("GD")
            Text("PTS")
                .frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .black, design: .rounded))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
    }

    private func statHeader(_ text: String) -> some View {
        Text(text).frame(width: 26, alignment: .trailing)
    }

    private func standingsRow(rank: Int, row: StandingRow) -> some View {
        let isUser = row.club.id == store.state.managedClubID
        let zone: String? = rank <= 8 ? "R16" : rank <= 24 ? "PO" : nil

        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("\(rank)")
                    .font(.system(size: 10, weight: isUser ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
                if let zone {
                    Text(zone)
                        .font(.system(size: 6, weight: .black, design: .rounded))
                        .foregroundStyle(zone == "R16" ? Color.studyGreen : Color.studyGold)
                }
            }
            .frame(width: 24, alignment: .trailing)

            HStack(spacing: 7) {
                ClubBadge(club: row.club, size: 18)
                Text(row.club.shortName)
                    .font(.system(size: 11, weight: isUser ? .bold : .regular, design: .rounded))
                    .lineLimit(1)
                if isUser {
                    Text("YOU")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(Color.studyGreen)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statCell("\(row.played)")
            statCell("\(row.won)")
            statCell("\(row.drawn)")
            statCell("\(row.lost)")
            statCell("\(row.goalsFor)")
            statCell("\(row.goalsAgainst)")
            statCell(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
            Text("\(row.points)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isUser ? Color.studyGreen.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private func statCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 26, alignment: .trailing)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var scoringLeaderboardCard: some View {
        let rows = Array(
            store.state.scoringLedger
                .sorted {
                    let left = $0.goals + $0.assists
                    let right = $1.goals + $1.assists
                    if left != right { return left > right }
                    return $0.goals > $1.goals
                }
                .prefix(15)
        )
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Goals & Assists",
                subtitle: "Every simulated match across all seasons, combined into one leaderboard",
                symbol: "soccerball"
            )
            if rows.isEmpty {
                Text("No goals have been scored yet. Simulate a matchday to start the leaderboard.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("#").frame(width: 28, alignment: .leading)
                    Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                    Text("G").frame(width: 44, alignment: .trailing)
                    Text("A").frame(width: 44, alignment: .trailing)
                    Text("G+A").frame(width: 52, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.element) { index, record in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .frame(width: 28, alignment: .leading)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(ClubDatabase.club(for: record.clubID)?.shortName ?? "")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(record.goals)").frame(width: 44, alignment: .trailing)
                        Text("\(record.assists)").frame(width: 44, alignment: .trailing)
                        Text("\(record.goals + record.assists)")
                            .fontWeight(.bold)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Latest Results", subtitle: "Tap a result for the full match report", symbol: "doc.text.magnifyingglass")
            VStack(spacing: 8) {
                ForEach(store.latestReports.prefix(5)) { latest in
                    Button {
                        report = latest
                    } label: {
                        ReportSummaryCard(report: latest, userClubID: store.state.managedClubID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var trophyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Trophy Cabinet", subtitle: "\(store.userTitles) European title\(store.userTitles == 1 ? "" : "s")", symbol: "trophy.fill")
            VStack(spacing: 0) {
                ForEach(store.trophies) { trophy in
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(trophy.userWasChampion ? Color.studyGold : Color.secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Season \(trophy.seasonNumber) · \(trophy.championName)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("Runner-up: \(trophy.runnerUpName)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            if let name = trophy.topScorerName, let goals = trophy.topScorerGoals {
                                Text("Top scorer: \(name) (\(goals) goals)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.studyGold)
                            }
                            if let name = trophy.topAssisterName, let assists = trophy.topAssisterAssists {
                                Text("Top assists: \(name) (\(assists) assists)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.studyGreen)
                            }
                        }
                        Spacer()
                        Pill(
                            text: trophy.userFinish.uppercased(),
                            color: trophy.userWasChampion ? .studyGold : .secondary,
                            icon: trophy.userWasChampion ? "crown.fill" : nil
                        )
                    }
                    .padding(.vertical, 8)
                    if trophy.id != store.trophies.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private func teamBlock(_ club: Club?, isUser: Bool) -> some View {
        VStack(spacing: 6) {
            if let club { ClubBadge(club: club, size: 46) }
            Text(club?.shortName ?? "—")
                .font(.system(size: 12, weight: isUser ? .bold : .semibold, design: .rounded))
                .lineLimit(1)
            Text(isUser ? "YOUR CLUB" : (club?.code ?? ""))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(isUser ? Color.studyGreen : Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var blockingReason: String? {
        guard let season else { return "There is no active season." }
        if season.phase == .complete { return "The season is complete." }
        guard !store.currentFixtures.isEmpty else { return "There are no fixtures ready to simulate." }
        guard store.userCurrentFixture != nil else { return nil }
        if !store.lineupIsComplete { return "Complete your starting XI in the Squad tab to play this match." }
        if store.state.availableMatchMinutes < GameRules.minutesPerMatch {
            return "\(store.minutesUntilMatch) more study minutes needed before you can play."
        }
        return nil
    }

    private func simulate() {
        do {
            let outcome = try store.simulateCurrentStage()
            if let userReport = outcome.userReport {
                report = userReport
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startNextSeason() {
        do {
            _ = try store.startNextSeason()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
