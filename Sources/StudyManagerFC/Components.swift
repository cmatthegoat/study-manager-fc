import SwiftUI

struct PlayerCardView: View {
    let player: Player
    var width: CGFloat = 182

    private var height: CGFloat { width * 1.39 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .fill(player.rarity.gradient)

            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: width * 0.74)
                .offset(x: width * 0.34, y: -height * 0.27)
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)
                .frame(width: width * 0.62)
                .offset(x: -width * 0.27, y: height * 0.26)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: -2) {
                        Text("\(player.overall)")
                            .font(.system(size: width * 0.22, weight: .black, design: .rounded))
                            .foregroundStyle(player.rarity.cardTextColor)
                        Text(player.position.abbreviation)
                            .font(.system(size: width * 0.067, weight: .bold, design: .rounded))
                            .foregroundStyle(player.rarity.cardSecondaryTextColor)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(player.nation.flag)
                            .font(.system(size: width * 0.095))
                        RarityTag(rarity: player.rarity, compact: true)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text(player.name)
                        .font(.system(size: width * 0.082, weight: .bold, design: .rounded))
                        .foregroundStyle(player.rarity.cardTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    HStack(spacing: 7) {
                        Text(player.nation.code)
                        Text("AGE \(player.age)")
                        Text("POT \(player.potential)")
                    }
                    .font(.system(size: width * 0.052, weight: .semibold, design: .rounded))
                    .foregroundStyle(player.rarity.cardSecondaryTextColor)

                    HStack(spacing: 0) {
                        attribute("PAC", player.attributes.pace, width: width)
                        attribute("SHO", player.attributes.shooting, width: width)
                        attribute("PAS", player.attributes.passing, width: width)
                        attribute("DEF", player.attributes.defending, width: width)
                        attribute("PHY", player.attributes.physical, width: width)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(width * 0.085)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.09, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .stroke(.white.opacity(player.rarity == .silver ? 0.2 : 0.26), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
    }

    private func attribute(_ label: String, _ value: Int, width: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: width * 0.052, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: width * 0.037, weight: .semibold, design: .rounded))
                .opacity(0.65)
        }
        .foregroundStyle(player.rarity.cardTextColor)
        .frame(maxWidth: .infinity)
    }
}

struct MiniPlayerCard: View {
    let player: Player?
    let positionLabel: String

    var body: some View {
        VStack(spacing: 5) {
            if let player {
                ZStack {
                    Circle()
                        .fill(player.rarity.accentColor.opacity(player.isInjured ? 0.12 : 0.24))
                    Circle()
                        .stroke(
                            player.isInjured ? Color.red.opacity(0.9) : player.rarity.accentColor.opacity(0.8),
                            lineWidth: 1.5
                        )
                    Text("\(player.overall)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .opacity(player.isInjured ? 0.5 : 1)
                }
                .frame(width: 43, height: 43)
                Text(player.name.split(separator: " ").last.map(String.init) ?? player.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(player.isInjured ? "OUT \(player.matchesMissed)" : "POT \(player.potential)")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(player.isInjured ? Color.red : player.rarity.accentColor)
                Text(positionLabel)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ZStack {
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.white.opacity(0.52))
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(width: 43, height: 43)
                Text(positionLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Empty")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 82, height: 94)
        .background(
            player == nil ? Color.black.opacity(0.15) : Color.black.opacity(0.28),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    player?.isInjured == true ? Color.red.opacity(0.75) : .white.opacity(player == nil ? 0.16 : 0.23),
                    lineWidth: player?.isInjured == true ? 1.5 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if player?.isInjured == true {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Color.red, in: Circle())
                    .offset(x: 5, y: -5)
            }
        }
    }
}

struct PitchMarkings: View {
    var body: some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.33)
            let inset: CGFloat = 18
            let field = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            context.stroke(Path(roundedRect: field, cornerRadius: 5), with: .color(lineColor), lineWidth: 1.2)
            let halfway = Path { path in
                path.move(to: CGPoint(x: field.minX, y: field.midY))
                path.addLine(to: CGPoint(x: field.maxX, y: field.midY))
            }
            context.stroke(halfway, with: .color(lineColor), lineWidth: 1.2)
            let centreCircle = Path(ellipseIn: CGRect(
                x: field.midX - 42,
                y: field.midY - 42,
                width: 84,
                height: 84
            ))
            context.stroke(centreCircle, with: .color(lineColor), lineWidth: 1.2)
            context.fill(Path(ellipseIn: CGRect(x: field.midX - 2.5, y: field.midY - 2.5, width: 5, height: 5)), with: .color(lineColor))

            let boxWidth = field.width * 0.46
            let boxHeight = field.height * 0.15
            let topBox = CGRect(x: field.midX - boxWidth / 2, y: field.minY, width: boxWidth, height: boxHeight)
            let bottomBox = CGRect(x: field.midX - boxWidth / 2, y: field.maxY - boxHeight, width: boxWidth, height: boxHeight)
            context.stroke(Path(roundedRect: topBox, cornerRadius: 2), with: .color(lineColor), lineWidth: 1.2)
            context.stroke(Path(roundedRect: bottomBox, cornerRadius: 2), with: .color(lineColor), lineWidth: 1.2)

            let sixWidth = field.width * 0.23
            let sixHeight = field.height * 0.06
            let topSix = CGRect(x: field.midX - sixWidth / 2, y: field.minY, width: sixWidth, height: sixHeight)
            let bottomSix = CGRect(x: field.midX - sixWidth / 2, y: field.maxY - sixHeight, width: sixWidth, height: sixHeight)
            context.stroke(Path(roundedRect: topSix, cornerRadius: 2), with: .color(lineColor), lineWidth: 1)
            context.stroke(Path(roundedRect: bottomSix, cornerRadius: 2), with: .color(lineColor), lineWidth: 1)
            context.stroke(
                Path(ellipseIn: CGRect(x: field.midX - 23, y: field.minY - 23, width: 46, height: 46)).trimmedPath(from: 0.5, to: 1),
                with: .color(lineColor),
                lineWidth: 1
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: field.midX - 23, y: field.maxY - 23, width: 46, height: 46)).trimmedPath(from: 0, to: 0.5),
                with: .color(lineColor),
                lineWidth: 1
            )
        }
    }
}

struct LineupPitchView: View {
    let lineup: [String: Player]
    var slots: [LineupSlot] = LineupSlot.all
    let onSelectSlot: (LineupSlot) -> Void

    var body: some View {
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
                    Button {
                        onSelectSlot(slot)
                    } label: {
                        MiniPlayerCard(
                            player: lineup[slot.id],
                            positionLabel: slot.label
                        )
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: proxy.size.width * slot.x,
                        y: proxy.size.height * slot.y
                    )
                }
            }
        }
        .aspectRatio(0.78, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

struct FixtureRowView: View {
    let fixture: Fixture
    var userClubID: String?
    var showRound: Bool = false

    private var isUserMatch: Bool {
        fixture.homeClubID == userClubID || fixture.awayClubID == userClubID
    }

    var body: some View {
        HStack(spacing: 12) {
            if showRound {
                Text("R\(fixture.round)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            clubSide(fixture.homeClubID, alignment: .trailing, home: true)
            VStack(spacing: 1) {
                if fixture.isSimulated {
                    Text(fixture.scoreline)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                } else {
                    Text("vs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(fixture.phase.shortName.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 100)
            clubSide(fixture.awayClubID, alignment: .leading, home: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isUserMatch ? Color.studyGreen.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isUserMatch ? Color.studyGreen.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }

    private func clubSide(_ id: String, alignment: HorizontalAlignment, home: Bool) -> some View {
        let club = ClubDatabase.club(for: id)
        return HStack(spacing: 7) {
            if alignment == .trailing { Spacer(minLength: 0) }
            if !home, let club { ClubBadge(club: club, size: 22) }
            Text(club?.shortName ?? id)
                .font(.system(size: 11, weight: isUserMatch ? .semibold : .regular, design: .rounded))
                .lineLimit(1)
            if home, let club { ClubBadge(club: club, size: 22) }
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

struct MatchReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: MatchReport
    var userClubID: String?
    /// Fitness changes caused by this match. Empty for reports opened from history.
    var injuries: [InjuryUpdate] = []

    private var home: Club? { ClubDatabase.club(for: report.homeClubID) }
    private var away: Club? { ClubDatabase.club(for: report.awayClubID) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.phase.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Color.studyGreen)
                    Text("Match Report")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)

            ScrollView {
                VStack(spacing: 22) {
                    scoreHeader
                    Text(report.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)

                    HStack(alignment: .top, spacing: 16) {
                        scorerColumn(title: home?.name ?? "Home", scorers: report.scorersForHome, club: home)
                        scorerColumn(title: away?.name ?? "Away", scorers: report.scorersForAway, club: away)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Key Moments", subtitle: "Every goal in chronological order", symbol: "clock.arrow.circlepath")
                        if report.events.isEmpty {
                            Text("No goals were scored.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.events) { event in
                                HStack(spacing: 12) {
                                    Text("\(event.minute)'")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.studyGreen)
                                        .frame(width: 34, alignment: .trailing)
                                    Circle()
                                        .fill(ClubDatabase.club(for: event.clubID)?.primaryColor ?? .gray)
                                        .frame(width: 7, height: 7)
                                    Text(event.scorer)
                                        .font(.system(size: 12, weight: .semibold))
                                    if event.isPenalty {
                                        Pill(text: "PEN", color: .studyGold)
                                    }
                                    Spacer()
                                    Text(ClubDatabase.club(for: event.clubID)?.shortName ?? "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .surface(padding: 18)

                    HStack(spacing: 18) {
                        ratingBlock(label: "Home rating", value: report.homeRating, club: home)
                        ratingBlock(label: "Away rating", value: report.awayRating, club: away)
                    }

                    if !injuries.isEmpty {
                        injuryCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 600, idealHeight: 680)
        .background(AppBackground())
    }

    private var scoreHeader: some View {
        HStack(spacing: 22) {
            teamBlock(home, isUser: home?.id == userClubID)
            VStack(spacing: 5) {
                Text(report.scoreline.components(separatedBy: " (").first ?? report.scoreline)
                    .font(.system(size: 37, weight: .black, design: .rounded))
                if let homePenalties = report.homePenalties, let awayPenalties = report.awayPenalties {
                    Text("\(homePenalties)-\(awayPenalties) on penalties")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.studyGold)
                } else {
                    Text("FULL TIME")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 130)
            teamBlock(away, isUser: away?.id == userClubID)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .elevatedSurface()
    }

    private func teamBlock(_ club: Club?, isUser: Bool) -> some View {
        VStack(spacing: 8) {
            if let club { ClubBadge(club: club, size: 56) }
            Text(club?.shortName ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if isUser {
                Text("YOUR CLUB")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.studyGreen)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scorerColumn(title: String, scorers: [(name: String, goals: Int)], club: Club?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let club { ClubBadge(club: club, size: 20) }
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            if scorers.isEmpty {
                Text("No scorers")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(scorers.enumerated()), id: \.offset) { _, scorer in
                    HStack {
                        Text(scorer.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text("x\(scorer.goals)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 14, cornerRadius: 15)
    }

    private func ratingBlock(label: String, value: Int, club: Club?) -> some View {
        HStack(spacing: 10) {
            if let club { ClubBadge(club: club, size: 26) }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Spacer()
        }
        .surface(padding: 12, cornerRadius: 14)
    }

    /// Who went down in this match, and who is back. Previously the only way to find out was
    /// to open the squad and look, which left the next matchday a guess.
    private var injuryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Injury Report",
                subtitle: "\(injuries.filter { !$0.isRecovery }.count) out · \(injuries.filter(\.isRecovery).count) back",
                symbol: "cross.case.fill"
            )
            ForEach(injuries) { update in
                HStack(spacing: 10) {
                    Image(systemName: update.isRecovery ? "checkmark.circle.fill" : "bandage.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(update.isRecovery ? Color.studyGreen : Color.red)
                        .frame(width: 20)
                    Text(update.playerName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Pill(
                        text: update.isRecovery ? "FIT AGAIN" : "OUT \(update.matchesOut) MATCH\(update.matchesOut == 1 ? "" : "ES")",
                        color: update.isRecovery ? .studyGreen : .red,
                        icon: update.isRecovery ? "arrow.up.circle.fill" : "cross.fill"
                    )
                }
            }
            if injuries.contains(where: { !$0.isRecovery }) {
                Text("Replace injured starters in the Squad tab before the next matchday.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .surface(padding: 16)
    }
}

struct ReportSummaryCard: View {
    let report: MatchReport
    var userClubID: String?

    @State private var expanded = false

    private var home: Club? { ClubDatabase.club(for: report.homeClubID) }
    private var away: Club? { ClubDatabase.club(for: report.awayClubID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let home { ClubBadge(club: home, size: 28) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(home?.shortName ?? "—") \(report.scoreline) \(away?.shortName ?? "—")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("\(report.phase.displayName) · \(report.playedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                if let away { ClubBadge(club: away, size: 28) }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                HStack(alignment: .top, spacing: 16) {
                    miniScorers(title: home?.name ?? "Home", scorers: report.scorersForHome)
                    miniScorers(title: away?.name ?? "Away", scorers: report.scorersForAway)
                }
                .padding(.top, 2)
            } else {
                Text(report.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            report.homeClubID == userClubID || report.awayClubID == userClubID
                ? Color.studyGreen.opacity(0.075)
                : Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func miniScorers(title: String, scorers: [(name: String, goals: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            if scorers.isEmpty {
                Text("—").font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(scorers.enumerated()), id: \.offset) { _, scorer in
                    Text("\(scorer.name) \(scorer.goals > 1 ? "x\(scorer.goals)" : "")")
                        .font(.system(size: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClubSelectionCard: View {
    let club: Club
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ClubBadge(club: club, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(club.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(club.country) · Pot \(ClubDatabase.potNumber(for: club.id))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 1) {
                    Text("\(club.rating)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                    Text("OVR")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Styled dropdown

/// One row in a `BentoMenu`.
struct BentoOption<Value: Hashable>: Identifiable {
    let id: Value
    let title: String
    var subtitle: String?
    var symbol: String?

    init(_ title: String, value: Value, subtitle: String? = nil, symbol: String? = nil) {
        self.id = value
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }
}

/// The app's dropdown. A rounded, outlined trigger showing the current value with a chevron,
/// and a floating card of options where the selected row is tinted and ticked, the hovered row
/// lifts slightly, and everything is drawn in the club palette.
struct BentoMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [BentoOption<Value>]
    var placeholder: String = "Select"
    /// Fixed trigger width. The card never gets narrower than 210pt.
    var width: CGFloat? = nil
    var isEnabled: Bool = true

    @State private var isOpen = false
    @State private var hovered: Value?

    private var current: BentoOption<Value>? {
        options.first { $0.id == selection }
    }

    private var cardWidth: CGFloat {
        max(width ?? 220, 210)
    }

    var body: some View {
        Button {
            guard isEnabled else { return }
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                if let symbol = current?.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.studyGreen)
                }
                Text(current?.title ?? placeholder)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isOpen ? Color.studyGreen : Color.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(width: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(isOpen ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isOpen ? Color.studyGreen.opacity(0.7) : Color.primary.opacity(0.13),
                        lineWidth: isOpen ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            card
                .presentationBackground(.clear)
        }
    }

    private var card: some View {
        ScrollView(showsIndicators: true) {
            VStack(spacing: 2) {
                if options.isEmpty {
                    Text("No options")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                }
                ForEach(options) { option in
                    row(option)
                }
            }
            .padding(7)
        }
        .frame(width: cardWidth)
        .frame(maxHeight: 300)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.09).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 10)
        .padding(12)
    }

    private func row(_ option: BentoOption<Value>) -> some View {
        let isSelected = option.id == selection
        let isHovered = hovered == option.id

        return Button {
            selection = option.id
            isOpen = false
        } label: {
            HStack(spacing: 8) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 12)
                        .foregroundStyle(isSelected ? Color.studyGreen : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = option.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.studyGreen)
                }
            }
            .foregroundStyle(isSelected ? Color.studyGreen : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.studyGreen.opacity(0.18)
                            : (isHovered ? Color.white.opacity(0.06) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hovered = option.id
            } else if hovered == option.id {
                hovered = nil
            }
        }
    }
}
