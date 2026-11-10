import SwiftUI

/// The left rail: club identity at the top, the nine sections down the middle, and the
/// season/level card at the foot. It replaces the old top tab strip, so navigation reads
/// the way the reference dashboard does.
struct AppSidebar: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: MainSection
    /// Icon-only rail: the same navigation with the labels, theme menus and level card gone.
    var compact: Bool = false

    private var club: Club? { store.managedClub }

    /// Progress through the current level, for the card at the foot of the rail.
    private var levelProgress: Double {
        Double(store.state.xp % GameRules.xpPerLevel) / Double(GameRules.xpPerLevel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 16)

            VStack(spacing: 3) {
                ForEach(MainSection.allCases) { section in
                    navButton(section)
                }
            }

            Spacer(minLength: 12)
            if compact {
                compactLevel
            } else {
                ThemeControls()
                    .padding(.horizontal, 2)
                    .padding(.bottom, 12)
                levelCard
            }
        }
        .padding(14)
        .frame(width: compact ? 74 : 226)
        .frame(maxHeight: .infinity)
        .background {
            GlassBackdrop(cornerRadius: 24, tint: Neon.panel.opacity(0.45), showsRim: false) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Neon.panel.opacity(0.86))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Neon.border, lineWidth: 1)
        )
        .shadow(color: Neon.accent.opacity(0.16), radius: 22)
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 8)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            if let club {
                ClubBadge(club: club, size: compact ? 30 : 36)
            } else {
                Circle()
                    .fill(Neon.panel)
                    .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
            }
            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(club?.shortName.uppercased() ?? "STUDY FC")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.1)
                    Text("Season \(store.state.seasonNumber) · Lv \(store.level)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
    }

    private func navButton(_ section: MainSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                if !compact {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
            .padding(.horizontal, compact ? 0 : 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
                    shape
                        .fill(
                            LinearGradient(
                                colors: [Neon.accent.opacity(0.55), Neon.accentAlt.opacity(0.32)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(shape.stroke(Neon.accent.opacity(0.75), lineWidth: 1))
                        .shadow(color: Neon.accent.opacity(0.55), radius: 10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(section.title)
    }

    /// What survives of the foot of the rail when it is only icons: the level and its bar.
    private var compactLevel: some View {
        VStack(spacing: 6) {
            Text("Lv \(store.level)")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .monospacedDigit()
            ReadinessBar(progress: levelProgress, tint: Neon.accent, height: 4)
                .frame(width: 34)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Neon.cta, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: Neon.accent.opacity(0.5), radius: 7)
                Text("Level \(store.level)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
            }
            ReadinessBar(progress: levelProgress, tint: Neon.accent, height: 6)
            Text("\(store.state.xp % GameRules.xpPerLevel) / \(GameRules.xpPerLevel) XP to level \(store.level + 1)")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

/// Palette and layout, side by side or stacked. The palette menu offers the seven styles —
/// each a transformation of the managed club's colours — and then every team in the game,
/// so any club's colours can be worn whatever club is being managed.
struct ThemeControls: View {
    @Environment(AppStore.self) private var store
    var vertical: Bool = true
    var menuWidth: CGFloat? = nil

    private var paletteOptions: [BentoOption<PaletteChoice>] {
        var options = ThemePreset.allCases.map { preset in
            BentoOption(
                preset.displayName,
                value: PaletteChoice.style(preset),
                subtitle: preset == .club ? (store.managedClub?.name ?? "Your club") : nil
            )
        }
        options += ClubDatabase.all
            .sorted { $0.name < $1.name }
            .map { club in
                BentoOption(
                    club.name,
                    value: PaletteChoice.team(club.id),
                    subtitle: "\(club.shortName) colours",
                    symbol: "shield.fill"
                )
            }
        return options
    }

    private var paletteBinding: Binding<PaletteChoice> {
        Binding(
            get: {
                if let id = store.state.paletteClubID { return .team(id) }
                return .style(store.themePreset)
            },
            set: { choice in
                switch choice {
                case .style(let preset): store.setThemePreset(preset)
                case .team(let id): store.setPaletteClub(id)
                }
            }
        )
    }

    private var layoutBinding: Binding<ThemePreset.LayoutPreset> {
        Binding(
            get: { store.layoutPreset },
            set: { store.setLayoutPreset($0) }
        )
    }

    var body: some View {
        if vertical {
            VStack(alignment: .leading, spacing: 8) {
                paletteMenu
                layoutMenu
            }
        } else {
            HStack(spacing: 8) {
                paletteMenu
                layoutMenu
            }
        }
    }

    private var paletteMenu: some View {
        menu("PALETTE", selection: paletteBinding, options: paletteOptions)
    }

    private var layoutMenu: some View {
        menu(
            "LAYOUT",
            selection: layoutBinding,
            options: ThemePreset.LayoutPreset.allCases.map {
                BentoOption($0.displayName, value: $0)
            }
        )
    }

    private func menu<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [BentoOption<Value>]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
            BentoMenu(selection: selection, options: options, width: menuWidth)
        }
    }
}
