import SwiftUI

/// Every study entry ever logged, in one place. The dashboard only shows the latest
/// handful, so this screen is the full history: searchable across titles, subjects,
/// topics, activity kinds and marks, with filters for subject, kind and time period.
struct StudyLogView: View {
    @Environment(AppStore.self) private var store

    @State private var query = ""
    @State private var subjectFilter: StudySubject?
    @State private var kindFilter: StudyActivityKind?
    @State private var period: LogPeriod = .allTime

    /// Windows of time the player can narrow the log to.
    private enum LogPeriod: String, CaseIterable, Identifiable {
        case allTime
        case last7
        case last30
        case last90

        var id: String { rawValue }

        var title: String {
            switch self {
            case .allTime: "All time"
            case .last7: "Last 7 days"
            case .last30: "Last 30 days"
            case .last90: "Last 90 days"
            }
        }

        var days: Int? {
            switch self {
            case .allTime: nil
            case .last7: 7
            case .last30: 30
            case .last90: 90
            }
        }

        func contains(_ date: Date, now: Date = Date()) -> Bool {
            guard let days else { return true }
            guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return true }
            return date >= cutoff
        }
    }

    private var hasFilters: Bool {
        subjectFilter != nil || kindFilter != nil || period != .allTime
            || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtered: [StudySession] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.state.recentSessions
            .filter { subjectFilter == nil || $0.subject == subjectFilter }
            .filter { kindFilter == nil || $0.kind == kindFilter }
            .filter { period.contains($0.date) }
            .filter { trimmed.isEmpty || Self.matches($0, trimmed) }
            .sorted { $0.date > $1.date }
    }

    private var aggregate: StudyAggregate {
        StudyAggregate.build(from: filtered)
    }

    private var groupedByDay: [(day: Date, sessions: [StudySession])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [StudySession]] = [:]
        for session in filtered {
            let day = calendar.startOfDay(for: session.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(session)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(
                    eyebrow: "Study Log",
                    title: "Every Entry You've Logged",
                    subtitle: "Search your whole history by title, subject, topic, activity or marks, then narrow it by subject, kind or date."
                )

                summaryGrid
                searchCard

                if store.state.recentSessions.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "Nothing logged yet",
                        message: "Start the focus timer or quick-log a session and it will appear here, forever, searchable."
                    )
                    .surface(padding: 20)
                } else if filtered.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "No entries match",
                        message: "Try a different search term, or clear the filters to see all \(store.state.recentSessions.count) entries."
                    )
                    .surface(padding: 20)
                } else {
                    ForEach(groupedByDay, id: \.day) { group in
                        dayCard(group.day, group.sessions)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Summary

    private var summaryGrid: some View {
        let totals = aggregate
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            MetricTile(
                title: "Entries",
                value: totals.sessions.formatted(),
                subtitle: store.state.recentSessions.count == totals.sessions
                    ? "All of your history"
                    : "of \(store.state.recentSessions.count) total",
                symbol: "list.bullet.rectangle",
                tint: .studyGreen
            )
            MetricTile(
                title: "Minutes",
                value: totals.minutes.formatted(),
                subtitle: "\(totals.minutes / 60) h \(totals.minutes % 60) m studied",
                symbol: "timer",
                tint: .studyTeal
            )
            MetricTile(
                title: "Club Cash",
                value: "+\(totals.cashEarned.formatted())",
                subtitle: "Earned on these entries",
                symbol: "banknote.fill",
                tint: .studyGold
            )
            MetricTile(
                title: "XP",
                value: "+\(totals.xpEarned.formatted())",
                subtitle: totals.averagePercentage.map { "\($0)% average marks" } ?? "No marks recorded",
                symbol: "sparkles",
                tint: .purple
            )
        }
    }

    // MARK: - Search and filters

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search entries — title, subject, topic, marks…", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Picker("Subject", selection: $subjectFilter) {
                    Text("All subjects").tag(StudySubject?.none)
                    ForEach(StudySubject.allCases) { subject in
                        Text(subject.shortName).tag(StudySubject?.some(subject))
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Picker("Kind", selection: $kindFilter) {
                    Text("All activity").tag(StudyActivityKind?.none)
                    ForEach(StudyActivityKind.allCases) { kind in
                        Text(kind.title).tag(StudyActivityKind?.some(kind))
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Picker("Period", selection: $period) {
                    ForEach(LogPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                if hasFilters {
                    Button("Clear") { clearFilters() }
                        .buttonStyle(.bentoBordered)
                        .bentoTint(.white)
                }
            }

            Text("Showing \(filtered.count) of \(store.state.recentSessions.count) entries")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    private func clearFilters() {
        query = ""
        subjectFilter = nil
        kindFilter = nil
        period = .allTime
    }

    // MARK: - Day groups

    private func dayCard(_ day: Date, _ sessions: [StudySession]) -> some View {
        let minutes = sessions.reduce(0) { $0 + max(0, $1.minutes) }
        let cash = sessions.reduce(0) { $0 + $1.cashEarned }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dayTitle(day))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("\(sessions.count) entr\(sessions.count == 1 ? "y" : "ies")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(minutes) min")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.studyTeal)
                Text("+\(cash.formatted())")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.studyGold)
            }
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    row(session)
                    if session.id != sessions.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    private func row(_ session: StudySession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.studyGreen)
                .frame(width: 28, height: 28)
                .background(Color.studyGreen.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title.isEmpty ? session.kind.title : session.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Text(detail(session))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    if let fraction = session.markFraction, let percentage = session.percentage {
                        Text("\(fraction) · \(percentage)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.studyTeal)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.studyTeal.opacity(0.12), in: Capsule())
                    }
                }
            }

            Spacer()

            Text(session.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("\(session.minutes) min")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
            Text("+\(session.xpEarned) XP")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.purple)
                .frame(width: 66, alignment: .trailing)
            Text("+\(session.cashEarned)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.studyGold)
                .frame(width: 56, alignment: .trailing)
            Button {
                store.deleteStudySession(session.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete this study log")
        }
        .padding(.vertical, 8)
    }

    // MARK: - Formatting

    private func detail(_ session: StudySession) -> String {
        var parts: [String] = [session.kind.title]
        if let subject = session.subject { parts.append(subject.shortName) }
        if let topic = session.subtopicName { parts.append(topic) }
        if session.quantity > 1 { parts.append("×\(session.quantity)") }
        return parts.joined(separator: " · ")
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    /// Matches against everything a player might remember about an entry, not just its title.
    private static func matches(_ session: StudySession, _ query: String) -> Bool {
        var parts: [String] = [
            session.title,
            session.kind.title,
            "\(session.minutes) min",
            "\(session.minutes)",
            "\(session.cashEarned)",
            "\(session.xpEarned)",
            session.date.formatted(date: .complete, time: .omitted),
            session.date.formatted(date: .abbreviated, time: .omitted),
            session.date.formatted(date: .omitted, time: .shortened)
        ]
        if let subject = session.subject {
            parts.append(subject.displayName)
            parts.append(subject.shortName)
            parts.append(subject.rawValue)
        }
        if let topic = session.subtopicName { parts.append(topic) }
        if let fraction = session.markFraction { parts.append(fraction) }
        if let percentage = session.percentage { parts.append("\(percentage)%") }
        return parts.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
