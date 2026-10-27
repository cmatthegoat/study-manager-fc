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
