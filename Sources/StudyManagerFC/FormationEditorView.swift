import SwiftUI

/// Draw your own shape. Eleven dots — one of them the goalkeeper, who stays put — and
/// wherever you drop one of the other ten, the role follows from that spot: a back three
/// with wing-backs, a 2-5-3 or a lopsided 4-2-4 is simply where you put them. Saving keeps
/// the XI: slots that survive keep their player, and a slot you add takes the best unused
/// player for the job.
struct FormationEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var slots: [LineupSlot]
    @State private var selectedID: String?
    @State private var errorMessage: String?
    private let startingSlots: [LineupSlot]

    init(slots: [LineupSlot]) {
        self.startingSlots = slots
        _slots = State(initialValue: slots)
    }

    private var outfieldCount: Int { slots.filter { $0.position != .goalkeeper }.count }

    private var keeperID: String? { slots.first { $0.position == .goalkeeper }?.id }

    /// How the shape reads as numbers, deep to high.
    private var shapeSummary: String {
        let groups = slots.map(\.position.group)
        let defence = groups.filter { $0 == .defence }.count
        let midfield = groups.filter { $0 == .midfield }.count
        let attack = groups.filter { $0 == .attack }.count
        return "\(defence)-\(midfield)-\(attack)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            pitch
                .frame(maxHeight: 470)
            footer
        }
        .padding(22)
        .frame(width: 660)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FORMATION DESIGNER")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Color.studyTeal)
                Text(store.isCustomFormation ? "Editing your saved shape" : "Starting from \(store.formation.displayName)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Drag any outfield player anywhere. His role comes from where he stands, so nothing is fixed to a template. The goalkeeper stays where he is.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(shapeSummary)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("DEF · MID · ATT")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pitch: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "2B7A4D"), Color(hex: "195534")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                PitchMarkings()
                ForEach(slots) { slot in
                    dot(for: slot, in: proxy.size)
                }
            }
            .coordinateSpace(name: "pitch")
        }
        .aspectRatio(0.78, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private func dot(for slot: LineupSlot, in size: CGSize) -> some View {
        let isKeeper = slot.position == .goalkeeper
        let isSelected = selectedID == slot.id
        return VStack(spacing: 1) {
            Text(slot.label)
                .font(.system(size: 9, weight: .black, design: .rounded))
            Text(store.lineupPlayersBySlot[slot.id]?.initials ?? "—")
                .font(.system(size: 7, weight: .semibold))
                .opacity(0.8)
        }
        .foregroundStyle(isSelected ? Color.studyInk : Color.white)
        .frame(width: 46, height: 46)
        .background(
            Circle().fill(isSelected ? Color.studyGold : Color.black.opacity(0.45))
        )
        .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 1.2))
        .position(x: size.width * slot.x, y: size.height * slot.y)
        .onTapGesture { selectedID = slot.id }
        .gesture(dragGesture(for: slot, in: size))
        .help(isKeeper ? "The goalkeeper stays where he is" : "Drag to move, and his role follows")
    }

    /// A drag reports its position in the pitch's own coordinate space, so the dot can be
    /// re-placed anywhere and its role re-read from the new spot.
    private func dragGesture(for slot: LineupSlot, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("pitch"))
            .onChanged { value in
                guard slot.position != .goalkeeper else { return }
                move(slot.id, to: value.location, in: size)
            }
    }

    private func move(_ id: String, to point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0,
              let index = slots.firstIndex(where: { $0.id == id }) else { return }
        let x = min(0.94, max(0.06, point.x / size.width))
        let y = min(0.97, max(0.10, point.y / size.height))
        let position = LineupSlot.role(atX: x, y: y)
        slots[index] = LineupSlot(
            id: slots[index].id,
            label: position.abbreviation,
            position: position,
            x: x,
            y: y
        )
        selectedID = id
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("An XI is the keeper plus ten outfield players. Add a dot, drag it where you want him, and remove one if the shape needs fewer bodies in a line. There is no limit on where they stand.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Add player") { addPlayer() }
                    .buttonStyle(.bentoBordered)
                    .disabled(outfieldCount >= 10)
                Button("Remove selected") { removeSelected() }
                    .buttonStyle(.bentoBordered)
                    .disabled(selectedID == nil || selectedID == keeperID)
                Spacer()
                Button("Reset") { reset() }
                    .buttonStyle(.bentoBordered)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bentoBordered)
                Button("Save shape") { save() }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.primary)
                    .disabled(outfieldCount != 10)
            }

            Text("\(outfieldCount) of 10 outfield players placed")
                .font(.system(size: 9))
                .foregroundStyle(outfieldCount == 10 ? Color.studyGreen : Color.orange)
        }
    }

    private func addPlayer() {
        guard outfieldCount < 10 else { return }
        let position = PlayerPosition.centralMid
        let slot = LineupSlot(
            id: "custom-\(UUID().uuidString.prefix(8))",
            label: position.abbreviation,
            position: position,
            x: 0.5,
            y: 0.5
        )
        slots.append(slot)
        selectedID = slot.id
        errorMessage = nil
    }

    private func removeSelected() {
        guard let selectedID,
              let slot = slots.first(where: { $0.id == selectedID }),
              slot.position != .goalkeeper else { return }
        slots.removeAll { $0.id == selectedID }
        self.selectedID = nil
        errorMessage = nil
    }

    private func reset() {
        slots = startingSlots
        selectedID = nil
        errorMessage = nil
    }

    private func save() {
        guard slots.count == 11, slots.filter({ $0.position == .goalkeeper }).count == 1 else {
            errorMessage = "An XI is the goalkeeper plus ten outfield players — \(outfieldCount) of 10 outfield are placed."
            return
        }
        do {
            try store.saveCustomFormation(slots)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
