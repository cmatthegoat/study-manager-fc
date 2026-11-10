import SwiftUI

struct TransfersView: View {
    @Environment(AppStore.self) private var store
    @State private var searchText = ""
    @State private var clubFilter: String?
    @State private var positionFilter: PositionGroup?
    @State private var priceFilter: PriceBand?
    @State private var sortMode: SortMode = .rating
    @State private var selectedListing: AppStore.TransferListing?
    @State private var priceRiseText = ""
    @State private var priceRiseError: String?

    private enum SortMode: String, CaseIterable, Identifiable {
        case rating
        case priceLowToHigh
        case priceHighToLow
        case name

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rating: "Rating"
            case .priceLowToHigh: "Price: low to high"
            case .priceHighToLow: "Price: high to low"
            case .name: "Name"
            }
        }
    }

    /// A price bracket on the asking price. The bands used to be fixed numbers stopping at
    /// "Over 10,000", which stopped telling one player from another once prices carried the
    /// premium and the user's own rises, so they are now built from the market itself.
    private struct PriceBand: Identifiable, Hashable {
        let id: Int
        let lower: Int?
        let upper: Int?
        let label: String

        func contains(_ price: Int) -> Bool {
            if let lower, price < lower { return false }
            if let upper, price >= upper { return false }
            return true
        }
    }

    /// Six geometric bands from the cheapest asking price to the dearest, so each holds a
    /// similar share of the market however the prices move.
    private var priceBands: [PriceBand] {
        let prices = store.transferMarket.map(\.askingPrice).sorted()
        guard let cheapest = prices.first, let dearest = prices.last, dearest > cheapest else { return [] }
        let steps = 6
        let ratio = pow(Double(dearest) / Double(cheapest), 1 / Double(steps))
        var edges: [Int] = [cheapest]
        for step in 1..<steps {
            let edge = Int((Double(cheapest) * pow(ratio, Double(step))).rounded())
            if let last = edges.last, edge > last { edges.append(edge) }
        }
        return edges.indices.map { index in
            let lower = index == 0 ? nil : edges[index]
            let upper = index + 1 < edges.count ? edges[index + 1] : nil
            let label: String
            switch (lower, upper) {
            case let (.some(low), .some(high)): label = "\(low.formatted()) – \(high.formatted())"
            case let (nil, .some(high)): label = "Under \(high.formatted())"
            case let (.some(low), nil): label = "\(low.formatted()) and up"
            case (nil, nil): label = "Any price"
            }
            return PriceBand(id: index, lower: lower, upper: upper, label: label)
        }
    }

    private var clubs: [Club] {
        ClubDatabase.all.sorted { $0.name < $1.name }
    }

    private var filteredListings: [AppStore.TransferListing] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = store.transferMarket.filter { listing in
            if let clubFilter, listing.clubID != clubFilter { return false }
            if let positionFilter, listing.record.position.group != positionFilter { return false }
            if let priceFilter, !priceFilter.contains(listing.askingPrice) { return false }
            guard !query.isEmpty else { return true }
            return listing.searchKey.contains(query)
        }
        switch sortMode {
        case .rating:
            result.sort { $0.record.ovr > $1.record.ovr }
        case .priceLowToHigh:
            result.sort { $0.askingPrice < $1.askingPrice }
        case .priceHighToLow:
            result.sort { $0.askingPrice > $1.askingPrice }
        case .name:
            result.sort { $0.name < $1.name }
        }
        return result
    }


    var body: some View {
        // Filtered once per redraw. Asking for it again in each branch rebuilt and re-sorted
        // the whole market — three times over — on every keystroke.
        let market = store.transferMarket
        let matches = market.isEmpty ? [] : filteredListings
        ScrollView {
            VStack(spacing: 22) {
                header
                academyCard
                priceControlCard
                filters
                if market.isEmpty {
                    EmptyStateView(
                        symbol: "arrow.left.arrow.right.circle",
                        title: "The market is empty",
                        message: "Start a career to see every player in the game database."
                    )
                    .surface()
                } else if matches.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "No players found",
                        message: "Try a different club, position or search."
                    )
                    .surface()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(matches.prefix(150))) { listing in
                            TransferRow(listing: listing) {
                                selectedListing = listing
                            }
                        }
                    }
                    .surface(padding: 16)

                    if matches.count > 150 {
                        Text("Showing the top 150 of \(matches.count) matching players — narrow the filters or search to see more.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $selectedListing) { listing in
            NegotiationSheet(listing: listing)
                .environment(store)
                .onDisappear { store.walkAwayFromNegotiation() }
        }
    }

    private var academyCard: some View {
        let level = store.state.academyLevel
        let cost = GameRules.academyUpgradeCost(from: level)
        let matchesLeft = GameRules.matchesPerAcademyIntake - store.state.matchesSinceAcademyIntake
        let profile = GameRules.academyIntakeProfile(level)
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUTH ACADEMY")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(1...GameRules.maxAcademyLevel, id: \.self) { step in
                        Capsule()
                            .fill(step <= level ? Color.studyGold : Color.primary.opacity(0.12))
                            .frame(width: 26, height: 6)
                    }
                }
                Text("Level \(level) of \(GameRules.maxAcademyLevel) - \(academyQualityLabel(level))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Next intake in \(matchesLeft) \(matchesLeft == 1 ? "match" : "matches"): \(profile.count) prospect\(profile.count == 1 ? "" : "s"), \(profile.overall.lowerBound)-\(profile.overall.upperBound) rated, \(profile.potential.lowerBound)-\(profile.potential.upperBound) potential.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("The academy slips one level at the start of every new season, so it needs reinvesting to stay elite.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.studyGold.opacity(0.9))
            }
            Spacer()
            if let cost {
                Button {
                    try? store.upgradeAcademy()
                } label: {
                    VStack(spacing: 2) {
                        Text("Upgrade to level \(level + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        Text("\(cost.formatted()) Club Cash")
                            .font(.system(size: 9))
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.bentoProminent)
                .bentoTint(.gold)
                .disabled(store.state.clubCash < cost)
            } else {
                Text("Maximum level")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.studyGold)
            }
        }
        .surface(padding: 16)
    }

    /// The user's own lever on the market: every player asks a bit more, permanently, and
    /// only ever upward.
    private var priceControlCard: some View {
        let rise = store.state.playerPriceRise
        let risePercent = Int((rise * 100).rounded())
        let totalPercent = Int(((1 + rise) * 100).rounded())
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MARKET PRICES")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(rise > 0
                     ? "Every player asks \(totalPercent)% of the standard price (+\(risePercent)%)."
                     : "Every player asks the standard price.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Raise every price by a percentage of your own. Raises stack on top of the last one and are saved with your career, and a price never comes back down: a negative or zero percentage is refused.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let lastRise = store.state.lastPriceRiseAt, rise > 0 {
                    Text("Last raise +\(Int((store.state.lastPriceRisePercent * 100).rounded()))% on \(lastRise.formatted(date: .abbreviated, time: .omitted)) · a 75-rated 24-year-old now asks \(PlayerPricing.valuation(overall: 75, potential: 80, age: 24).formatted()).")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.studyGold.opacity(0.9))
                }
                if let priceRiseError {
                    Text(priceRiseError)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    TextField("25", text: $priceRiseText)
                        .bentoField()
                        .frame(width: 66)
                    Text("%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Button("Raise prices", action: applyPriceRise)
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.gold)
            }
        }
        .surface(padding: 16)
    }

    /// Reads the percentage box, refuses anything that is not a rise, and leaves the stacking
    /// and the saving to the store.
    private func applyPriceRise() {
        let cleaned = priceRiseText
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let percent = Double(cleaned), percent.isFinite else {
            priceRiseError = "Enter a percentage, like 25."
            return
        }
        guard percent > 0 else {
            priceRiseError = "Only increases are allowed — prices never go down."
            return
        }
        guard percent <= 200 else {
            priceRiseError = "Raise prices by 200% at most in one go."
            return
        }
        do {
            try store.raisePlayerPrices(percent: percent)
            priceRiseText = ""
            priceRiseError = nil
        } catch {
            priceRiseError = error.localizedDescription
        }
    }

    private func academyQualityLabel(_ level: Int) -> String {
        switch level {
        case 1: "Raw talent, little potential"
        case 2: "Developing intake"
        case 3: "Promising intake"
        case 4: "Strong intake"
        default: "Elite intake, high ceilings"
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            ScreenHeader(
                eyebrow: "Transfer Market",
                title: "Every Player in the Game",
                subtitle: "Clubs own their players, so a signing has to be negotiated with the owner. The higher a player's overall, the more they cost and the harder their club bargains."
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("CLUB CASH")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(store.state.clubCash.formatted())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.studyGold)
                    .monospacedDigit()
            }
            .surface(padding: 12, cornerRadius: 14)
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search players, clubs or positions", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 320)

            BentoMenu(
                selection: $clubFilter,
                options: [BentoOption("All clubs", value: String?.none)]
                    + clubs.map { BentoOption($0.shortName, value: Optional($0.id)) },
                width: 150
            )

            BentoMenu(
                selection: $positionFilter,
                options: [BentoOption("All positions", value: PositionGroup?.none)]
                    + PositionGroup.allCases.map { BentoOption($0.displayName, value: Optional($0)) },
                width: 150
            )

            BentoMenu(
                selection: $priceFilter,
                options: [BentoOption("Any price", value: PriceBand?.none)]
                    + priceBands.map { BentoOption($0.label, value: Optional($0)) },
                width: 150
            )

            BentoMenu(
                selection: $sortMode,
                options: SortMode.allCases.map { BentoOption($0.label, value: $0) },
                width: 170
            )

            Spacer()
            Text("\(store.transferMarket.count) players available")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .surface(padding: 12)
    }
}

private struct TransferRow: View {
    @Environment(AppStore.self) private var store
    let listing: AppStore.TransferListing
    let action: () -> Void

    private var name: String { store.playerName(for: listing) }
    private var asking: Int { store.askingPrice(for: listing) }
    private var canAfford: Bool { store.state.clubCash >= asking }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.studyGreen.opacity(0.16))
                Text("\(listing.record.ovr)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("POT \(listing.record.potential)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.studyTeal)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.studyTeal.opacity(0.12), in: Capsule())
                }
                Text("\(listing.record.position.displayName) · \(Nations.nation(for: listing.record.nat).flag) \(Nations.nation(for: listing.record.nat).code) · \(listing.record.age)y")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                if let club = listing.club {
                    ClubBadge(club: club, size: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(listing.clubName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(listing.league ?? "")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(asking.formatted())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(canAfford ? Color.studyGold : Color.secondary)
                Text(canAfford ? "asking price" : "\((asking - store.state.clubCash).formatted()) short")
                    .font(.system(size: 8, weight: canAfford ? .regular : .semibold))
                    .foregroundStyle(canAfford ? Color.secondary : Color.orange)
            }
            .frame(width: 92, alignment: .trailing)

            Button(action: action) {
                Label("Negotiate", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct NegotiationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let listing: AppStore.TransferListing

    @State private var offerText = ""

    /// Leaves the negotiation for good: the sheet is dismissed as well as the deal cleared,
    /// because walking away previously only nil'd the negotiation and left the sheet open
    /// showing a fresh asking price, which read as the talks restarting.
    private func finish() {
        store.walkAwayFromNegotiation()
        dismiss()
    }

    private var deal: AppStore.Negotiation? { store.negotiation }
    private var name: String { store.playerName(for: listing) }
    private var asking: Int { deal?.askingPrice ?? store.askingPrice(for: listing) }
    private var patience: Int { deal?.patience ?? 100 }
    private var status: AppStore.NegotiationStatus { deal?.status ?? .open }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.clubName.uppercased())
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(listing.record.position.displayName) · \(listing.record.ovr) OVR · \(listing.record.age)y · \(Nations.nation(for: listing.record.nat).flag) \(Nations.nation(for: listing.record.nat).name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ASKING")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(asking.formatted())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.studyGold)
                        .monospacedDigit()
                }
                // A sheet has no dismiss control of its own on macOS, so there is always
                // a way out even if a negotiation is in an unexpected state.
                Button {
                    finish()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close and stop negotiating")
            }

            HStack(spacing: 18) {
                stat("Market value", listing.fee.formatted())
                stat("Your cash", store.state.clubCash.formatted())
                stat("Club rating", "\(ClubDatabase.club(for: listing.clubID)?.rating ?? 0)")
            }

            patienceBar

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array((deal?.messages ?? []).suffix(4))) { message in
                    HStack {
                        if !message.fromClub { Spacer() }
                        Text(message.text)
                            .font(.system(size: 11))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                message.fromClub
                                    ? Color.primary.opacity(0.06)
                                    : Color.studyGreen.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        if message.fromClub { Spacer() }
                    }
                }
            }
            .frame(height: 150, alignment: .bottomLeading)
            .frame(maxWidth: .infinity, alignment: .leading)

            switch status {
            case .signed:
                Label("Transfer agreed for \(deal?.lastOffer?.formatted() ?? asking.formatted()) Club Cash.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.studyGreen)
                Button("Done") { finish() }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .collapsed:
                Label("Talks have collapsed. Walk away and come back with a fresh approach.", systemImage: "xmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                HStack {
                    Spacer()
                    Button("Close") { finish() }
                }
            case .open:
                HStack(spacing: 8) {
                    Text("Offer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Amount", text: $offerText)
                        .bentoField()
                        .frame(width: 100)
                    Button("Submit") {
                        if let amount = Int(offerText.replacingOccurrences(of: ",", with: "")) {
                            store.submitOffer(amount)
                            offerText = ""
                        }
                    }
                    .buttonStyle(.bentoBordered)
                    Spacer()
                    Button("Offer \(asking.formatted())") {
                        store.acceptAskingPrice()
                    }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.primary)
                    .disabled(store.state.clubCash < asking)
                    Button("Walk away") { finish() }
                }
                Text("The owner has \(patience)% patience left. Serious offers close the gap; lowballs burn it.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 620)
        .task {
            if store.negotiation == nil { store.beginNegotiation(for: listing) }
            offerText = "\(store.askingPrice(for: listing))"
        }
    }

    private var patienceBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PATIENCE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(patience)%")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ReadinessBar(
                progress: Double(patience) / 100.0,
                tint: patience > 45 ? Color.studyGreen : Color.studyGold,
                height: 8
            )
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }
}
