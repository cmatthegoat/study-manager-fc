import SwiftUI

/// Contracts and wages on the squad screen. A squad that is never renewed empties itself at
/// the end of every season, so this card exists to make that visible before it happens.
struct ContractsCard: View {
    @Environment(AppStore.self) private var store
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Contracts & wages",
                subtitle: "\(store.weeklyWageBill.formatted()) a week · deals run four seasons from the one a player joins",
                symbol: "signature"
            )

            if store.expiringContracts.isEmpty {
                Text("Nobody's deal runs out this season or next. Renewals cost twelve weeks of wages.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(store.expiringContracts.prefix(5)) { player in
                        HStack(spacing: 8) {
                            Text(player.name)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Text(player.position.abbreviation)
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text("ends S\(store.contractEnd(for: player))")
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(store.contractEnd(for: player) <= store.state.seasonNumber ? Color.orange : Color.secondary)
                            Text("\(player.wage.formatted())/wk")
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 76, alignment: .trailing)
                            Button("Renew \(store.renewalCost(for: player).formatted())") {
                                if store.renewContract(player.id) {
                                    message = "\(player.name) signed for three more seasons."
                                } else {
                                    message = "Not enough Club Cash to renew \(player.name)."
                                }
                            }
                            .buttonStyle(.bentoBordered)
                            .bentoTint(.primary)
                            .disabled(store.state.clubCash < store.renewalCost(for: player))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                        )
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Neon.panel.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Neon.border, lineWidth: 1)
        )
    }
}
