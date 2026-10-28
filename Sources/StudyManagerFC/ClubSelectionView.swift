import SwiftUI

struct ClubSelectionView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedClubID: String?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 265, maximum: 340), spacing: 16)]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    VStack(spacing: 18) {
                        ForEach(Array(ClubDatabase.seededPots.enumerated()), id: \.offset) { index, clubs in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("POT \(index + 1)")
                                        .font(.system(size: 10, weight: .black, design: .rounded))
                                        .tracking(1.4)
                                        .foregroundStyle(Color.studyGold)
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 1)
                                }
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(clubs) { club in
                                        ClubSelectionCard(club: club) {
                                            selectedClubID = club.id
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(
                                                    selectedClubID == club.id ? Color.studyGreen : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 1060)

                    selectionFooter
                        .frame(maxWidth: 1060)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
            }
        }
        .alert("Could Not Start Career", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.studyGreen, Color.studyTeal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 2)
                    .padding(8)
                Image(systemName: "soccerball")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 82, height: 82)
            .shadow(color: Color.studyGreen.opacity(0.35), radius: 20, y: 8)

            VStack(spacing: 7) {
                Text("STUDYMANAGER FC")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(3.2)
                    .foregroundStyle(Color.studyGreen)
                Text("Choose your club")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Take charge of one of Europe's 36 elite sides. Study to unlock matchdays, open packs, and build a squad capable of lifting the Champions League.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 610)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    private var selectionFooter: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedClubID.flatMap(ClubDatabase.club(for:))?.name ?? "No club selected")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("You begin with an academy squad and 600 Club Cash. Your first 90 minutes of study unlocks Matchday 1.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                guard let selectedClubID else { return }
                do {
                    try store.startCareer(with: selectedClubID)
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Start Career")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)
            .disabled(selectedClubID == nil)
            .keyboardShortcut(.defaultAction)
        }
        .elevatedSurface(padding: 18)
    }
}

/// Opened from the top bar. A move keeps the whole career — squad, level, cash, trophies and
/// study history — and starts a new season at the chosen club.
struct ChangeTeamSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClubID: String?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 330), spacing: 12)]

    private var currentClub: Club? { store.managedClub }
    private var selectedClub: Club? { selectedClubID.flatMap(ClubDatabase.club(for:)) }
    private var seasonIsUnfinished: Bool { store.season?.phase != .complete }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(ClubDatabase.seededPots.enumerated()), id: \.offset) { index, clubs in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 10) {
                                Text("POT \(index + 1)")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .tracking(1.4)
                                    .foregroundStyle(Color.studyGold)
                                Rectangle()
                                    .fill(Color.primary.opacity(0.07))
                                    .frame(height: 1)
                            }
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(clubs) { club in
                                    ClubSelectionCard(club: club) {
                                        selectedClubID = club.id
                                    }
                                    .opacity(club.id == currentClub?.id ? 0.4 : 1)
                                    .disabled(club.id == currentClub?.id)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(
                                                selectedClubID == club.id ? Color.studyGreen : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 900, height: 660)
        .background(AppBackground())
        .alert("Could Not Change Team", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let currentClub {
                ClubBadge(club: currentClub, size: 42)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("CHANGE TEAM")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Color.studyGold)
                Text(currentClub.map { "Leave \($0.name) for another club" } ?? "Change team")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Season \(store.state.seasonNumber) is replaced by a new season at your new club.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedClub.map { "Move to \($0.name)" } ?? "Pick a new club")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Your squad, level and XP, Club Cash, trophies and study history all come with you. Squad players are not aged by the move.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if selectedClub != nil, seasonIsUnfinished {
                    Text("Season \(store.state.seasonNumber) is abandoned and will not be recorded as a trophy. Season \(store.state.seasonNumber + 1) begins immediately.")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.studyGold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                guard let selectedClub else { return }
                do {
                    _ = try store.changeClub(to: selectedClub.id)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Start Season \(store.state.seasonNumber + 1)")
                    Image(systemName: "arrow.right.circle.fill")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)
            .disabled(selectedClub == nil)
        }
        .padding(18)
        .elevatedSurface(padding: 0)
        .padding(16)
    }
}
