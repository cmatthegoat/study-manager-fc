import SwiftUI

struct SquadView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = 0
    @State private var selectedSlot: LineupSlot?
    @State private var selectedPlayer: Player?
    @State private var searchText = ""
    @State private var groupFilter: PositionGroup?

    private var metrics: SquadMetrics { store.squadMetrics }

    private var filteredPlayers: [Player] {
        store.state.players
            .filter { player in
                groupFilter == nil || player.position.group == groupFilter
            }
            .filter { player in
                searchText.isEmpty
                    || player.name.localizedCaseInsensitiveContains(searchText)
                    || player.position.displayName.localizedCaseInsensitiveContains(searchText)
                    || player.nation.name.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.overall != $1.overall { return $0.overall > $1.overall }
                return $0.name < $1.name
            }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                metricsRow
                Picker("Squad view", selection: $tab) {
                    Text("Starting XI").tag(0)
                    Text("All Players").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)

                if tab == 0 {
                    lineupContent
                } else {
                    playersContent
                }
            }
            .padding(28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $selectedSlot) { slot in
            PlayerPickerSheet(slot: slot)
                .environment(store)
        }
        .sheet(item: $selectedPlayer) { player in
            PlayerDetailSheet(player: player)
                .environment(store)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            ScreenHeader(
                eyebrow: "\(store.managedClub?.country ?? "Europe") · \(store.managedClub?.name ?? "My Club")",
                title: "My Squad",
                subtitle: "Build chemistry, cover every position, and give your club the best chance of European glory."
            )
            Spacer()
            if let club = store.managedClub {
                ClubBadge(club: club, size: 66)
            }
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 10) {
            squadMetric("Overall", "\(metrics.overall)", "Team rating", "chart.bar.fill", .studyGreen)
            squadMetric("Chemistry", "\(metrics.chemistry)", "Position + nation links", "link", .studyTeal)
            squadMetric("Attack", "\(metrics.attack)", "Attacking line", "bolt.fill", .orange)
            squadMetric("Midfield", "\(metrics.midfield)", "Control", "arrow.triangle.branch", .blue)
            squadMetric("Defence", "\(metrics.defence)", "Back line", "shield.fill", .purple)
            squadMetric("Squad Value", "\(metrics.totalValue.formatted())", "\(metrics.playerCount) players", "banknote", .studyGold)
        }
    }

    private func squadMetric(_ title: String, _ value: String, _ subtitle: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 12, cornerRadius: 14)
    }

    private var lineupContent: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 7) {
                        Pill(text: "4-3-3", color: .studyGreen, icon: "soccerball")
                        if store.lineupIsComplete {
                            Pill(text: "XI COMPLETE", color: .studyGreen, icon: "checkmark")
                        } else {
                            Pill(text: "INCOMPLETE XI", color: .orange, icon: "exclamationmark")
                        }
                    }
                    Spacer()
                    Text("Tap any position to change it")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                LineupPitchView(lineup: store.lineupPlayersBySlot) { slot in
                    selectedSlot = slot
                }
                .frame(maxWidth: 590)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Squad Actions", subtitle: "Quick ways to shape your XI", symbol: "slider.horizontal.3")
                    Button {
                        store.autoPickSquad()
                    } label: {
                        Label("Auto-pick Best XI", systemImage: "wand.and.stars")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.primary)

                    HStack {
                        chemistryRing
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Chemistry")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("\(metrics.chemistry)/100")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .surface(padding: 18)
            }
            .frame(width: 320)
        }
    }

    private var chemistryRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: Double(metrics.chemistry) / 100.0)
                .stroke(
                    LinearGradient(colors: [.studyGreen, .studyTeal], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(metrics.chemistry)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .frame(width: 64, height: 64)
    }

    private var playersContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search players or nations", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 300)

                Picker("Position", selection: $groupFilter) {
                    Text("All positions").tag(PositionGroup?.none)
                    ForEach(PositionGroup.allCases) { group in
                        Text(group.displayName).tag(PositionGroup?.some(group))
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Spacer()
                Text("\(filteredPlayers.count) players")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if filteredPlayers.isEmpty {
                EmptyStateView(
                    symbol: "person.crop.circle.badge.questionmark",
                    title: "No players found",
                    message: "Change your filters or open a pack to add more players to the club."
                )
                .surface()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 182, maximum: 210), spacing: 16)], spacing: 18) {
                    ForEach(filteredPlayers) { player in
                        Button {
                            selectedPlayer = player
                        } label: {
                            VStack(spacing: 8) {
                                PlayerCardView(player: player)
                                squadStatus(for: player)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func squadStatus(for player: Player) -> some View {
        Group {
            if let slotID = store.state.lineup.first(where: { $0.value == player.id })?.key,
               let slot = LineupSlot.slot(for: slotID) {
                Pill(text: "STARTING \(slot.label)", color: .studyGreen, icon: "checkmark.circle.fill")
            } else if store.state.bench.contains(player.id) {
                Pill(text: "ON BENCH", color: .studyGold, icon: "chair.lounge.fill")
            } else {
                Pill(text: "RESERVE", color: .secondary, icon: "person.fill")
            }
        }
    }
}

private struct PlayerPickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: LineupSlot

    private var currentPlayer: Player? {
        guard let id = store.state.lineup[slot.id] else { return nil }
        return store.player(for: id)
    }

    private var candidates: [Player] {
        store.state.players.sorted {
            if $0.adjustedRating(for: slot) != $1.adjustedRating(for: slot) {
                return $0.adjustedRating(for: slot) > $1.adjustedRating(for: slot)
            }
            return $0.overall > $1.overall
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SELECT PLAYER")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(Color.studyGreen)
                    Text("\(slot.position.displayName) · \(slot.label)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(22)

            if let currentPlayer {
                HStack(spacing: 12) {
                    playerRowContent(currentPlayer, isCurrent: true)
                    Button("Remove from XI", role: .destructive) {
                        store.removeFromLineup(slotID: slot.id)
                        dismiss()
                    }
                    .buttonStyle(.bentoBordered)
                }
                .padding(12)
                .background(Color.red.opacity(0.065), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.horizontal, 22)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(candidates) { player in
                        Button {
                            store.assign(playerID: player.id, to: slot.id)
                            dismiss()
                        } label: {
                            HStack {
                                playerRowContent(player, isCurrent: currentPlayer?.id == player.id)
                                Spacer()
                                if currentPlayer?.id == player.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.studyGreen)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                player.position.group == slot.position.group
                                    ? Color.studyGreen.opacity(0.055)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 560, idealHeight: 660)
        .background(AppBackground())
    }

    private func playerRowContent(_ player: Player, isCurrent: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(player.rarity.accentColor.opacity(0.18))
                Text("\(player.overall)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("\(player.position.abbreviation) · \(player.nation.flag) \(player.nation.code) · Age \(player.age) · POT \(player.potential)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if player.position == slot.position {
                Pill(text: "NATURAL", color: .studyGreen)
            } else if player.position.group == slot.position.group {
                Pill(text: "FITS", color: .studyTeal)
            } else {
                Pill(text: "OUT OF POSITION", color: .orange)
            }
            if !isCurrent && store.state.bench.contains(player.id) {
                Pill(text: "BENCH", color: .secondary)
            }
            Spacer()
        }
    }
}

private struct PlayerDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let player: Player

    @State private var confirmRelease = false

    private var lineupSlot: LineupSlot? {
        guard let slotID = store.state.lineup.first(where: { $0.value == player.id })?.key else { return nil }
        return LineupSlot.slot(for: slotID)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.rarity.displayName.uppercased())
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(player.rarity.accentColor)
                    Text("Player Profile")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 24) {
                PlayerCardView(player: player, width: 230)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("\(player.nation.flag) \(player.nation.name) · \(player.position.displayName)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Pill(text: "OVR \(player.overall)", color: player.rarity.accentColor)
                        Pill(text: "POT \(player.potential)", color: .studyTeal)
                        Pill(text: "AGE \(player.age)", color: .secondary)
                    }

                    attributeBars

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Market value")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(player.marketValue.formatted())
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Release value")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(player.releaseValue.formatted())
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.studyGold)
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        if let lineupSlot {
                            Button {
                                store.removeFromLineup(slotID: lineupSlot.id)
                                dismiss()
                            } label: {
                                Label("Remove from Starting XI", systemImage: "arrow.down.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bentoBordered)
                        } else if store.state.bench.contains(player.id) {
                            Button {
                                store.removeFromBench(playerID: player.id)
                                dismiss()
                            } label: {
                                Label("Remove from Bench", systemImage: "arrow.down.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bentoBordered)
                        } else {
                            Button {
                                store.addToSquad(playerID: player.id)
                                dismiss()
                            } label: {
                                Label("Add to Squad", systemImage: "plus.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bentoProminent)
                            .bentoTint(.primary)

                            if !store.state.bench.contains(player.id) && store.state.bench.count < GameRules.benchLimit {
                                Button {
                                    store.addToBench(playerID: player.id)
                                    dismiss()
                                } label: {
                                    Label("Add to Bench", systemImage: "chair.lounge")
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bentoBordered)
                            }
                        }

                        Button(role: .destructive) {
                            confirmRelease = true
                        } label: {
                            Label("Release for \(player.releaseValue.formatted())", systemImage: "trash")
                                .font(.system(size: 10))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(minWidth: 650, idealWidth: 700, minHeight: 520)
        .background(AppBackground())
        .confirmationDialog("Release \(player.name)?", isPresented: $confirmRelease, titleVisibility: .visible) {
            Button("Release Player", role: .destructive) {
                store.releasePlayer(playerID: player.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will receive \(player.releaseValue.formatted()) Club Cash. This cannot be undone.")
        }
    }

    private var attributeBars: some View {
        VStack(spacing: 8) {
            attributeBar("Pace", player.attributes.pace)
            attributeBar("Shooting", player.attributes.shooting)
            attributeBar("Passing", player.attributes.passing)
            attributeBar("Defending", player.attributes.defending)
            attributeBar("Physical", player.attributes.physical)
        }
    }

    private func attributeBar(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.studyGreen.opacity(0.85))
                        .frame(width: proxy.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 5)
            Text("\(value)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .frame(width: 24, alignment: .trailing)
        }
    }
}
