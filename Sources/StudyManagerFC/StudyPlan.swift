import SwiftUI

/// One suggested session for the coming week, with the reason it is being suggested. The
/// plan is derived entirely from what the app already knows — no new data entry.
struct PlanItem: Identifiable, Hashable {
    let id: String
    let day: Date
    let subject: StudySubject
    let subtopicID: UUID?
    let topic: String
    let minutes: Int
    let reason: String

    var symbol: String {
        reason.hasPrefix("Test") ? "exclamationmark.circle" : "calendar.badge.clock"
    }
}

enum StudyPlan {
    /// A week of sessions: approaching assessments first, then mistakes waiting for a
    /// retest, then the weakest topics by marked average. Days with nothing worth doing are
    /// left out rather than filled with busywork.
    static func week(
        for state: GameState,
        sessions: [StudySession],
        from today: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlanItem] {
        let start = calendar.startOfDay(for: today)
        var items: [PlanItem] = []
        var usedSubjectsByDay: [Date: Set<StudySubject>] = [:]

        // Assessments first: a test in three days outranks a weak topic that has been weak
        // for a month, because only one of them has a deadline.
        let upcoming = state.assessments
            .filter { $0.date >= start }
            .sorted { $0.date < $1.date }

        for assessment in upcoming.prefix(6) {
            guard let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: assessment.date)).day,
                  days >= 0, days < 7 else { continue }
            let topic = state.subtopics.first { $0.subject == assessment.subject }?.name ?? assessment.subject.shortName
            items.append(
                PlanItem(
                    id: "assessment-\(assessment.id)",
                    day: calendar.startOfDay(for: assessment.date),
                    subject: assessment.subject,
                    subtopicID: nil,
                    topic: topic,
                    minutes: 45,
                    reason: days == 0 ? "Test today" : "Test in \(days) day\(days == 1 ? "" : "s")"
                )
            )
            usedSubjectsByDay[calendar.startOfDay(for: assessment.date), default: []].insert(assessment.subject)
        }

        // Then the mistakes whose retest has come round.
        let due = state.mistakes
            .filter { !$0.isResolved && $0.reviewDueAt <= today }
            .sorted { $0.reviewDueAt < $1.reviewDueAt }
        for (offset, entry) in due.prefix(4).enumerated() {
            let day = calendar.date(byAdding: .day, value: offset % 3, to: start) ?? start
            items.append(
                PlanItem(
                    id: "mistake-\(entry.id)",
                    day: calendar.startOfDay(for: day),
                    subject: entry.subject,
                    subtopicID: entry.subtopicID,
                    topic: entry.subtopicName ?? entry.subject.shortName,
                    minutes: 25,
                    reason: "Mistake to retest"
                )
            )
            usedSubjectsByDay[calendar.startOfDay(for: day), default: []].insert(entry.subject)
        }

        // Then the topics with the weakest marked average, one per day, so a week has shape.
        let weak = MarksAverages.byTopic(sessions.filter { $0.date >= calendar.date(byAdding: .day, value: -30, to: start) ?? start })
            .filter { $0.percentage < 70 }
        for (offset, row) in weak.prefix(3).enumerated() {
            let day = calendar.date(byAdding: .day, value: (offset + 1) % 5, to: start) ?? start
            guard let subject = row.subject else { continue }
            guard usedSubjectsByDay[calendar.startOfDay(for: day), default: []].contains(subject) == false else { continue }
            items.append(
                PlanItem(
                    id: "weak-\(row.id)",
                    day: calendar.startOfDay(for: day),
                    subject: subject,
                    subtopicID: state.subtopics.first { $0.subject == subject && $0.name == row.label }?.id,
                    topic: row.label,
                    minutes: 40,
                    reason: "Averaging \(row.percentage)%"
                )
            )
        }

        return items.sorted {
            $0.day == $1.day ? $0.reason < $1.reason : $0.day < $1.day
        }
    }
}

/// The plan card on the dashboard. Each row starts a timed session on exactly that topic, so
/// planning and the timer are no longer two separate habits.
struct StudyPlanCard: View {
    @Environment(AppStore.self) private var store
    @State private var showingBuilder = false

    private var items: [PlanItem] {
        StudyPlan.week(for: state, sessions: store.state.recentSessions)
    }

    private var state: GameState { store.state }

    private var today: [PlanItem] {
        let calendar = Calendar.current
        return items.filter { calendar.isDateInToday($0.day) || $0.day < calendar.startOfDay(for: Date()) }
    }

    private var later: [PlanItem] {
        let calendar = Calendar.current
        return items.filter { $0.day > calendar.startOfDay(for: Date()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                SectionHeader(
                    title: "This week's plan",
                    subtitle: items.isEmpty
                        ? "Add an assessment, a mistake or some marked work and the plan builds itself"
                        : "Built from your deadlines, your retests and your weakest topics",
                    symbol: "calendar.day.timeline.left"
                )
                Spacer(minLength: 4)
                Button {
                    showingBuilder = true
                } label: {
                    Label("Plan by time", systemImage: "clock.badge.checkmark")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.primary)
                .help("Pick how long you have and get a list of tasks that fit")
            }

            ForEach(Array(today.prefix(3))) { item in
                row(item, isToday: true)
            }

            if !later.isEmpty {
                Divider().opacity(0.2)
                ForEach(Array(later.prefix(3))) { item in
                    row(item, isToday: false)
                }
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
        .sheet(isPresented: $showingBuilder) {
            SessionBuilderView()
                .environment(store)
        }
    }

    private func row(_ item: PlanItem, isToday: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SubjectTheme.color(for: item.subject))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.topic)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(item.subject.shortName) · \(item.minutes) min · \(item.reason)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !isToday {
                Text(item.day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button("Start") {
                store.timerSubject = item.subject
                store.timerSubtopicID = item.subtopicID
                store.timerKind = .focusSession
                if !store.isTimerRunning {
                    store.startTimer()
                }
            }
            .buttonStyle(.bentoBordered)
            .bentoTint(.primary)
        }
        .padding(.vertical, 4)
    }
}
