import SwiftUI

/// One thing ⌘K can do. Built by the shell so the palette knows about sections, the timer and
/// the appearance window without owning any of them.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let run: () -> Void
}

/// The ⌘K sheet: type a few letters, press Return, and the app does the thing.
struct CommandPaletteView: View {
    let commands: [PaletteCommand]
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [PaletteCommand] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return commands }
        return commands.filter {
            $0.title.lowercased().contains(needle) || $0.subtitle.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to a section, start the timer…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .focused($searchFocused)
                    .onSubmit { runFirst() }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            if matches.isEmpty {
                Text("Nothing matches “\(query)”.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                            Button {
                                command.run()
                                onClose()
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: command.symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Neon.accent)
                                        .frame(width: 16)
                                    Text(command.title)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    Spacer(minLength: 8)
                                    Text(command.subtitle)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(index == 0 && !query.isEmpty ? Neon.accent.opacity(0.16) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { searchFocused = true }
    }

    private func runFirst() {
        guard let first = matches.first else { return }
        first.run()
        onClose()
    }
}
