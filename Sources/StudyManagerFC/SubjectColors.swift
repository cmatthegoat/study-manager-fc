import AppKit
import SwiftUI

/// Per-subject colours, chosen by the player. Colours are saved as hex strings so the career
/// file stays readable, and every subject keeps a default until it is customised.
enum SubjectTheme {
    /// Defaults picked to stay distinct from each other on the dark canvas and from the
    /// club accents the rest of the interface wears.
    static let defaults: [StudySubject: String] = [
        .ext2Maths: "A78BFA",
        .ext1Maths: "60A5FA",
        .physics: "22D3EE",
        .chemistry: "34D399",
        .softwareEngineering: "FBBF24",
        .englishAdvanced: "F472B6",
        .other: "94A3B8"
    ]

    /// The live palette. `AppStore` mirrors the save into this so views — and Swift Charts
    /// style scales, which are built outside any view body — can read a colour without the
    /// store being threaded through every call.
    static var overrides: [String: String] = [:]

    static func hex(for subject: StudySubject) -> String {
        overrides[subject.rawValue] ?? defaults[subject] ?? "94A3B8"
    }

    static func color(for subject: StudySubject) -> Color {
        Color(hex: hex(for: subject))
    }

    static func color(for subject: StudySubject?) -> Color {
        guard let subject else { return Color(hex: "94A3B8") }
        return color(for: subject)
    }

    /// Reads the saved overrides, ignoring anything whose subject has since been retired.
    static func apply(_ saved: [String: String]) {
        overrides = saved.filter { StudySubject(rawValue: $0.key) != nil }
    }

    /// Swatches offered in the picker, plus a system colour well for anything else.
    static let swatches: [String] = [
        "A78BFA", "8B5CF6", "C084FC",
        "60A5FA", "38BDF8", "22D3EE",
        "34D399", "4ADE80", "A3E635",
        "FBBF24", "FB923C", "F87171",
        "F472B6", "FCA5A5", "94A3B8"
    ]
}

extension Color {
    /// `RRGGBB` for saving a colour picked in the system well.
    var hexString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}

/// A subject's swatch grid: the presets, a system colour well for anything else, and a way
/// back to the default.
struct SubjectColorPicker: View {
    @Environment(AppStore.self) private var store
    let subject: StudySubject

    /// Bound to the colour well; seeded from the subject's current colour when it opens.
    @State private var custom = Color.white

    private var currentHex: String {
        store.subjectColorHex(subject)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(SubjectTheme.color(for: subject))
                    .frame(width: 8, height: 8)
                    .shadow(color: SubjectTheme.color(for: subject).opacity(0.7), radius: 5)
                Text("\(subject.shortName) colour")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(22), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(SubjectTheme.swatches, id: \.self) { hex in
                    let isSelected = currentHex.caseInsensitiveCompare(hex) == .orderedSame
                    Button {
                        store.setSubjectColor(hex, for: subject)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(
                                    Color.white.opacity(isSelected ? 0.95 : 0.16),
                                    lineWidth: isSelected ? 1.6 : 0.5
                                )
                            )
                            .shadow(color: Color(hex: hex).opacity(isSelected ? 0.8 : 0), radius: 6)
                    }
                    .buttonStyle(.plain)
                    .help("#\(hex)")
                }
            }

            Divider()

            HStack(spacing: 8) {
                ColorPicker("Custom", selection: $custom, supportsOpacity: false)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .onChange(of: custom) { _, newValue in
                        guard let hex = newValue.hexString,
                              hex.caseInsensitiveCompare(currentHex) != .orderedSame else { return }
                        store.setSubjectColor(hex, for: subject)
                    }
                Spacer()
                Button("Default") {
                    store.resetSubjectColor(for: subject)
                    custom = SubjectTheme.color(for: subject)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .disabled(store.state.subjectColors[subject.rawValue] == nil)
            }
        }
        .padding(14)
        .frame(width: 190)
        .onAppear { custom = SubjectTheme.color(for: subject) }
    }
}
