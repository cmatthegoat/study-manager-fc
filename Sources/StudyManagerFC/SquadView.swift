import SwiftUI

struct SquadView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = 0
    @State private var selectedSlot: LineupSlot?
    @State private var selectedPlayer: Player?
    @State private var searchText = ""
    @State private var groupFilter: PositionGroup?

    private var metrics: SquadMetrics { store.squadMetrics }

    /// Starters currently ruled out. The XI cannot be fielded until they are replaced.
    private var injuredStarters: [Player] {
        store.lineupSlots.compactMap { slot in
            guard let id = store.state.lineup[slot.id],
                  let player = store.player(for: id),
                  player.isInjured else { return nil }
            return player
        }
    }

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
                subtitle: "Cover every position, choose your shape, and give your club the best chance of European glory."
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
                        formationMenu
                        if store.lineupIsComplete {
                            Pill(text: "XI COMPLETE", color: .studyGreen, icon: "checkmark")
                        } else {
                            Pill(text: "INCOMPLETE XI", color: .orange, icon: "exclamationmark")
                        }
                        if !injuredStarters.isEmpty {
                            Pill(
                                text: "\(injuredStarters.count) INJURED",
                                color: .red,
                                icon: "cross.case.fill"
                            )
                        }
                    }
                    Spacer()
                    Text("Tap any position to change it")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                LineupPitchView(lineup: store.lineupPlayersBySlot, slots: store.lineupSlots) { slot in
                    selectedSlot = slot
                }
                .frame(maxWidth: 590)

                if !injuredStarters.isEmpty {
                    injuryBanner
                }
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
                }
                .surface(padding: 18)
            }
            .frame(width: 320)
        }
    }

    /// The shape picker. Switching keeps as much of the XI in place as the new shape allows.
    private var formationMenu: some View {
        BentoMenu(
            selection: Binding(
                get: { store.formation },
                set: { store.setFormation($0) }
            ),
            options: Formation.allCases.map {
                BentoOption($0.displayName, value: $0, subtitle: $0.blurb, symbol: "soccerball")
            },
            width: 130
        )
        .help("Change formation")
    }

    /// Names the wounded starters and how long they are out, so a blocked matchday has a
    /// visible cause on this screen rather than a puzzle in the squad list.
    private var injuryBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red)
                Text(injuredStarters.count == 1 ? "1 starter is injured" : "\(injuredStarters.count) starters are injured")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text("Tap their position to replace them")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            ForEach(injuredStarters) { player in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red.opacity(0.75))
                        .frame(width: 6, height: 6)
                    Text(player.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Spacer()
                    Pill(
                        text: "OUT \(player.matchesMissed) MATCH\(player.matchesMissed == 1 ? "" : "ES")",
                        color: .red
                    )
                }
            }
        }
        .frame(maxWidth: 590, alignment: .leading)
        .padding(14)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.28), lineWidth: 1)
        )
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

                BentoMenu(
                    selection: $groupFilter,
                    options: [BentoOption("All positions", value: PositionGroup?.none)]
                        + PositionGroup.allCases.map { BentoOption($0.displayName, value: Optional($0)) },
                    width: 150
                )

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
            if player.isInjured {
                Pill(text: "INJURED · OUT \(player.matchesMissed)", color: .red, icon: "cross.case.fill")
            } else {
                Pill(text: "AVAILABLE", color: .studyGreen, icon: "checkmark.circle.fill")
            }
            if let slotID = store.state.lineup.first(where: { $0.value == player.id })?.key,
               let slot = store.lineupSlots.first(where: { $0.id == slotID }) {
                Pill(text: "STARTING \(slot.label)", color: .studyTeal, icon: "person.fill.checkmark")
            } else if store.state.bench.contains(player.id) {
                Pill(text: "ON BENCH", color: .studyGold, icon: "chair.lounge.fill")
            } else {
                Pill(text: "RESERVE", color: .secondary, icon: "person.fill")
            }
        }
        .frame(maxWidth: .infinity)
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

    /// Where a player currently sits in the XI, if anywhere.
    private func placing(of player: Player) -> LineupSlot? {
        guard let slotID = store.state.lineup.first(where: { $0.value == player.id })?.key else { return nil }
        return store.lineupSlots.first(where: { $0.id == slotID })
    }

    /// Best first for the position being filled.
    private func ranked(_ players: [Player]) -> [Player] {
        players.sorted {
            if $0.adjustedRating(for: slot) != $1.adjustedRating(for: slot) {
                return $0.adjustedRating(for: slot) > $1.adjustedRating(for: slot)
            }
            return $0.overall > $1.overall
        }
    }

    /// Bench first: they are already on the matchday sheet and are the natural replacements.
    private var benchOptions: [Player] {
        ranked(store.state.bench.compactMap { store.player(for: $0) })
    }

    private var reserveOptions: [Player] {
        ranked(store.state.players.filter { placing(of: $0) == nil && !store.state.bench.contains($0.id) })
    }

    /// Men already in the XI are listed last, in their own colour, but stay selectable so
    /// players can be shuffled between positions.
    private var xiOptions: [Player] {
        ranked(store.lineupSlots.compactMap { store.state.lineup[$0.id] }.compactMap { store.player(for: $0) })
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
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !benchOptions.isEmpty {
                        sectionHeader("On the bench", hint: "\(benchOptions.count) ready to step in", tint: .studyGold)
                        ForEach(benchOptions) { player in
                            optionRow(player, tint: Color.studyGold.opacity(0.11))
                        }
                    }
                    if !reserveOptions.isEmpty {
                        sectionHeader("Rest of the squad", hint: "\(reserveOptions.count) in reserve", tint: .secondary)
                        ForEach(reserveOptions) { player in
                            optionRow(
                                player,
                                tint: player.position.group == slot.position.group
                                    ? Color.studyGreen.opacity(0.055)
                                    : Color.clear
                            )
                        }
                    }
                    if !xiOptions.isEmpty {
                        sectionHeader("Already in the XI", hint: "Tap to move, or swap positions", tint: .studyTeal)
                        ForEach(xiOptions) { player in
                            optionRow(player, tint: Color.studyTeal.opacity(0.16))
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 560, idealHeight: 660)
        .background(AppBackground())
    }

    private func sectionHeader(_ title: String, hint: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(tint == .secondary ? Color.secondary : tint)
            Spacer()
            Text(hint)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func optionRow(_ player: Player, tint: Color) -> some View {
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
                } else if let place = placing(of: player) {
                    Text("IN XI · \(place.label)")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.studyTeal)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(placing(of: player) == nil ? Color.clear : Color.studyTeal.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            if player.isUserListing {
                Pill(text: "LISTED", color: .studyGold)
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
        return store.lineupSlots.first(where: { $0.id == slotID })
    }

    /// The sheet is handed a snapshot, so listing changes would otherwise be invisible until
    /// it was closed and reopened. Everything that listing touches reads the live player.
    private var livePlayer: Player {
        store.state.players.first(where: { $0.id == player.id }) ?? player
    }

    private var offersForPlayer: Int {
        store.state.transferOffers.filter { $0.playerID == player.id }.count
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
                        if livePlayer.isUserListing {
                            Pill(text: "TRANSFER LISTED", color: .studyGold)
                        }
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

                        // Selling through the market beats releasing for a fraction, so listing
                        // is the primary route out of the club.
                        Button {
                            store.setPlayerListed(player.id, listed: !livePlayer.isUserListing)
                        } label: {
                            Label(
                                livePlayer.isUserListing ? "Remove from transfer list" : "Add to transfer list",
                                systemImage: livePlayer.isUserListing ? "minus.circle" : "arrow.left.arrow.right.circle"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bentoBordered)
                        .bentoTint(.gold)

                        if livePlayer.isUserListing {
                            Text(
                                offersForPlayer == 0
                                    ? "Listed for \(livePlayer.marketValue.formatted()). The first offer arrives after your next match."
                                    : "\(offersForPlayer) offer(s) waiting. Another arrives after each match."
                            )
                            .font(.system(size: 9))
                            .foregroundStyle(Color.studyGold)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
