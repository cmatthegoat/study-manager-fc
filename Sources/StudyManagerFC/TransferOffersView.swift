import SwiftUI

/// The transfer-list inbox: a bell in the app header with a count of pending offers, and a
/// popover where each offer can be accepted, negotiated or declined. Offers arrive for
/// transfer-listed players after every match.
struct TransferOffersButton: View {
    @Environment(AppStore.self) private var store
    @State private var isShowingOffers = false

    private var offers: [TransferOffer] { store.state.transferOffers }

    var body: some View {
        Button {
            isShowingOffers = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: offers.isEmpty ? "bell" : "bell.badge.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                if !offers.isEmpty {
                    Text("\(offers.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(offers.isEmpty ? Color.secondary : Color.studyGreen)
            .glassChrome(
                cornerRadius: 999,
                tint: offers.isEmpty ? nil : Color.studyGreen.opacity(0.35),
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .help(offers.isEmpty ? "Transfer offers" : "\(offers.count) transfer offer\(offers.count == 1 ? "" : "s")")
        .popover(isPresented: $isShowingOffers, arrowEdge: .bottom) {
            TransferOffersPanel()
                .environment(store)
        }
    }
}

private struct TransferOffersPanel: View {
    @Environment(AppStore.self) private var store

    /// Negotiation happens inside the panel rather than in a sheet: a sheet presented from
    /// inside a popover is fragile on macOS, and this keeps every action one click away.
    @State private var negotiatingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let negotiatingID,
               let offer = store.state.transferOffers.first(where: { $0.id == negotiatingID }) {
                OfferNegotiationPanel(
                    offer: offer,
                    playerName: store.player(for: offer.playerID)?.name ?? "Unknown player",
                    onBack: { self.negotiatingID = nil },
                    onClosed: { self.negotiatingID = nil }
                )
            } else {
                SectionHeader(
                    title: "Transfer Offers",
                    subtitle: store.state.transferOffers.isEmpty
                        ? "List a player and offers arrive after each match"
                        : "\(store.state.transferOffers.count) waiting on you",
                    symbol: "bell.badge"
                )

                if store.state.transferOffers.isEmpty {
                    EmptyStateView(
                        symbol: "envelope.open",
                        title: "No offers yet",
                        message: "Open a player in the Squad tab and add him to the transfer list. Every match then brings a fresh offer — some good, some insulting."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.state.transferOffers) { offer in
                                TransferOfferRow(
                                    offer: offer,
                                    onNegotiate: {
                                        self.negotiatingID = offer.id
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 380)
                }
            }
        }
        .padding(18)
        .frame(width: 520)
        .animation(.easeInOut(duration: 0.15), value: negotiatingID)
    }
}

private struct TransferOfferRow: View {
    @Environment(AppStore.self) private var store
    let offer: TransferOffer
    var onNegotiate: () -> Void

    private var player: Player? { store.player(for: offer.playerID) }
    private var name: String { player?.name ?? "Unknown player" }
    private var difference: Int { offer.amount - offer.marketValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("\(offer.clubName)\(player.map { " · OVR \($0.overall) · \($0.age)y" } ?? "")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(offer.amount.formatted())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.studyGold)
                        .monospacedDigit()
                    Text(offer.isAboveValue ? "\(difference.formatted()) over value" : "\((-difference).formatted()) under value")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(offer.isAboveValue ? Color.studyGreen : Color.orange)
                }
            }

            HStack(spacing: 8) {
                Pill(text: offer.isGood ? "SERIOUS BID" : "LOWBALL", color: offer.isGood ? .studyGreen : .orange)
                if offer.isFinal {
                    Text("Final number")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Counter", action: onNegotiate)
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.primary)
                Button("Decline") { store.declineTransferOffer(offer.id) }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.danger)
                Button("Accept") { store.acceptTransferOffer(offer.id) }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.primary)
                    .disabled(player == nil)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Counter-offer view. The club has a hidden ceiling, so pushing past it costs patience and
/// eventually ends the talks; countering at or below it closes the deal immediately.
private struct OfferNegotiationPanel: View {
    @Environment(AppStore.self) private var store

    let offer: TransferOffer
    let playerName: String
    var onBack: () -> Void
    var onClosed: () -> Void

    @State private var counterText = ""
    @State private var message: String?
    @State private var isSettled = false

    private var live: TransferOffer? { store.state.transferOffers.first { $0.id == offer.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Button {
                    onBack()
                } label: {
                    Label("Offers", systemImage: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("CURRENT BID")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text((live?.amount ?? offer.amount).formatted())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.studyGold)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(offer.clubName.uppercased())
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text(playerName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Market value \(offer.marketValue.formatted()) Club Cash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let live {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("THEIR PATIENCE")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(live.patience)%")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    ReadinessBar(
                        progress: Double(live.patience) / 100.0,
                        tint: live.patience > 45 ? Color.studyGreen : Color.studyGold,
                        height: 8
                    )
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isSettled ? Color.studyGreen : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if live != nil && !isSettled {
                HStack(spacing: 8) {
                    TextField("Counter", text: $counterText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Button("Send") { sendCounter() }
                        .buttonStyle(.bentoBordered)
                        .bentoTint(.primary)
                    Spacer()
                    Button("Accept \((live?.amount ?? 0).formatted())") { accept() }
                        .buttonStyle(.bentoProminent)
                        .bentoTint(.primary)
                }
                Text("The club will not pay any price. Push too far and it walks away.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if isSettled || live == nil {
                HStack {
                    Spacer()
                    Button("Done", action: onClosed)
                        .buttonStyle(.bentoProminent)
                        .bentoTint(.primary)
                }
            }
        }
        .task {
            counterText = "\(max(offer.marketValue, offer.amount))"
            if live == nil {
                message = "This offer is no longer available."
            }
        }
    }

    private func accept() {
        guard let live else { return }
        store.acceptTransferOffer(live.id)
        isSettled = true
        message = "Sold \(playerName) to \(offer.clubName) for \(live.amount.formatted()) Club Cash."
    }

    private func sendCounter() {
        guard let amount = Int(counterText.replacingOccurrences(of: ",", with: "")) else { return }
        switch store.counterTransferOffer(offer.id, amount: amount) {
        case .accepted(let price):
            isSettled = true
            message = "\(offer.clubName) accepted \(price.formatted()) Club Cash. \(playerName) has left the club."
        case .improved(let bid):
            message = "They have raised their bid to \(bid.formatted()) — that is as high as they will go."
        case .withdrawn:
            isSettled = true
            message = "\(offer.clubName) walked away from the table."
        case .expired:
            isSettled = true
            message = "This offer is no longer available."
        }
    }
}
