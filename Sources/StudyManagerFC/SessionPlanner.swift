import Foundation

/// Where a task's length came from, so the UI can be honest about how firm the number is.
enum EstimateSource: String, Hashable {
    /// The task carries its own ETA; the difficulty table is not consulted at all.
    case given
    /// Counted from its questions at the topic's pace.
    case questions
    /// No ETA and no count: a default length for the topic's difficulty level.
    case level

    var isRough: Bool { self != .given }
}

/// One task's place in a planned session, with the minutes actually allocated to it.
struct SessionStep: Identifiable, Hashable {
    var todo: TodoItem
    var subject: StudySubject
    var topic: String?
    var level: Int
    /// The minutes this step is asked to take from the session budget.
    var minutes: Int
    /// The task's whole length, so a partial step can say what it is a slice of.
    var estimate: Int
    var source: EstimateSource
    var reason: String

    var id: UUID { todo.id }
    var isPartial: Bool { minutes < estimate }
}

struct SessionPlan {
    var budget: Int
    var steps: [SessionStep]

    var plannedMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
    var leftOverMinutes: Int { max(0, budget - plannedMinutes) }
    var isEmpty: Bool { steps.isEmpty }
}

/// Turns "I have 90 minutes" into a list of tasks to do, in order. Timing comes from the
/// difficulty table, ranking comes from deadlines, priority and how hard the work is, and a
/// task that carries its own ETA is taken at its word — the level is never applied to it.
enum SessionPlanner {
    /// Below this many minutes left there is no useful slice to hand out, so filling stops.
    static let minimumChunk = 15
    /// Changing subject mid-session costs a little time, so same-subject work is preferred.
    static let subjectSwitchPenalty = 4
    static let maximumSteps = 8

    // MARK: - Difficulty

    /// The topic's level, or its subject's default. Recent marks can move it one step either
    /// way — never further — so the pace table is always one of its five rows.
    static func level(for todo: TodoItem, subtopics: [Subtopic], sessions: [StudySession]) -> Int {
        let subject = todo.subject ?? .other
        guard let topic = matchingTopic(for: todo, subtopics: subtopics) else {
            return clampLevel(subject.baseDifficulty)
        }
        var level = topic.difficulty ?? subject.baseDifficulty
        var obtained = 0
        var total = 0
        for session in sessions {
            guard let sessionTotal = session.marksTotal, sessionTotal > 0,
                  let sessionObtained = session.marksObtained else { continue }
            let sameTopic = session.subtopicID == topic.id
                || (session.subject == topic.subject
                    && session.subtopicName?.caseInsensitiveCompare(topic.name) == .orderedSame)
            guard sameTopic else { continue }
            obtained += sessionObtained
            total += sessionTotal
        }
        if total >= 8 {
            let ratio = Double(obtained) / Double(total)
            if ratio < 0.5 { level += 1 }
            else if ratio >= 0.85 { level -= 1 }
        }
        return clampLevel(level)
    }

    static func clampLevel(_ level: Int) -> Int { min(max(level, 1), 5) }

    private static func matchingTopic(for todo: TodoItem, subtopics: [Subtopic]) -> Subtopic? {
        if let id = todo.subtopicID, let topic = subtopics.first(where: { $0.id == id }) {
            return topic
        }
        guard let name = todo.subtopicName else { return nil }
        return subtopics.first {
            $0.subject == (todo.subject ?? .other)
                && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    // MARK: - Estimates

    /// How long a task is expected to take. An ETA on the task wins outright; otherwise its
    /// questions are priced at the topic's minutes per mark; otherwise the level's default is
    /// used and flagged as rough.
    static func estimate(
        for todo: TodoItem,
        subtopics: [Subtopic],
        sessions: [StudySession]
    ) -> (minutes: Int, source: EstimateSource, level: Int) {
        let level = level(for: todo, subtopics: subtopics, sessions: sessions)
        if let given = todo.estimateMinutes, given > 0 {
            return (given, .given, level)
        }
        if let questions = todo.questionCount, questions > 0 {
            let minutes = Int((Double(questions) * DifficultyLevel.pace(for: level)).rounded())
            return (max(5, minutes), .questions, level)
        }
        return (DifficultyLevel.defaultMinutes(level), .level, level)
    }

    /// A one-line explanation of an estimate for the board and the plan.
    static func workloadText(minutes: Int, source: EstimateSource, questions: Int?, level: Int) -> String {
        switch source {
        case .given:
            "ETA \(minutes) min"
        case .questions:
            "\(questions ?? 0) Q × \(DifficultyLevel.paceText(level)) = \(minutes) min"
        case .level:
            "L\(level) default · \(minutes) min"
        }
    }

    /// What a task row shows without opening anything: its questions and its length.
    static func chipText(for todo: TodoItem, subtopics: [Subtopic], sessions: [StudySession]) -> String {
        let estimate = estimate(for: todo, subtopics: subtopics, sessions: sessions)
        let length = estimate.source.isRough ? "~\(estimate.minutes) min" : "\(estimate.minutes) min"
        if let questions = todo.questionCount, questions > 0 {
            return "\(questions) Q · \(length)"
        }
        return "\(length) · L\(estimate.level)"
    }

    // MARK: - Ranking

    /// How much a task wants this session. Deadlines dominate, priority comes next, and harder
    /// work is worth more of the time because it is where the marks are lost.
    static func score(
        for todo: TodoItem,
        level: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        var score = 0.0
        if let due = todo.dueDay {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: due).day ?? 0
            if days < 0 { score += 120 }
            else if days == 0 { score += 90 }
            else if days <= 14 { score += 70 - Double(days) * 4 }
            else { score += 15 }
        }
        switch todo.priority ?? 0 {
        case 1: score += 40
        case 2: score += 28
        case 3: score += 16
        case 4: score += 8
        default: break
        }
        score += Double(level) * 4
        let age = calendar.dateComponents([.day], from: todo.createdAt, to: now).day ?? 0
        if age >= 7 { score += 4 }
        return score
    }

    static func reason(
        for todo: TodoItem,
        level: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        var parts: [String] = []
        if let due = todo.dueDay {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: due).day ?? 0
            if days < 0 { parts.append("Overdue") }
            else if days == 0 { parts.append("Due today") }
            else if days == 1 { parts.append("Due tomorrow") }
            else if days <= 14 { parts.append("Due in \(days) days") }
            else { parts.append("Due \(due.formatted(.dateTime.day().month(.abbreviated)))") }
        } else {
            parts.append("No deadline")
        }
        if let priority = todo.priority { parts.append("P\(priority)") }
        parts.append("L\(level)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Planning

    static func plan(
        budget: Int,
        state: GameState,
        sessions: [StudySession],
        excluding excluded: Set<UUID> = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SessionPlan {
        let budget = max(0, budget)
        guard budget >= minimumChunk else { return SessionPlan(budget: budget, steps: []) }

        var candidates: [(todo: TodoItem, minutes: Int, source: EstimateSource, level: Int, score: Double)] = []
        for todo in state.todos where !todo.isCompleted && !excluded.contains(todo.id) {
            let estimate = estimate(for: todo, subtopics: state.subtopics, sessions: sessions)
            candidates.append((
                todo,
                estimate.minutes,
                estimate.source,
                estimate.level,
                score(for: todo, level: estimate.level, now: now, calendar: calendar)
            ))
        }
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.minutes != rhs.minutes { return lhs.minutes < rhs.minutes }
            return lhs.todo.createdAt < rhs.todo.createdAt
        }

        var remaining = budget
        var steps: [SessionStep] = []
        var lastSubject: StudySubject?

        for candidate in candidates {
            guard remaining >= minimumChunk, steps.count < maximumSteps else { break }
            let switching = lastSubject != nil && lastSubject != candidate.todo.subject
            let penalty = switching ? subjectSwitchPenalty : 0
            let available = remaining - penalty

            if candidate.minutes <= available {
                remaining -= candidate.minutes + penalty
                lastSubject = candidate.todo.subject
                steps.append(makeStep(candidate, minutes: candidate.minutes, now: now, calendar: calendar))
            } else if available >= minimumChunk {
                // Too big for what is left: start it with the time there is rather than
                // skipping the most urgent task of the session.
                let slice = available
                remaining = 0
                lastSubject = candidate.todo.subject
                steps.append(makeStep(candidate, minutes: slice, now: now, calendar: calendar))
            }
        }

        // Same-subject work is kept together so the session does not bounce between subjects.
        guard let firstSubject = steps.first?.subject else {
            return SessionPlan(budget: budget, steps: [])
        }
        var ordered = steps.filter { $0.subject == firstSubject }
        ordered += steps.filter { $0.subject != firstSubject }
        return SessionPlan(budget: budget, steps: ordered)
    }

    private static func makeStep(
        _ candidate: (todo: TodoItem, minutes: Int, source: EstimateSource, level: Int, score: Double),
        minutes: Int,
        now: Date,
        calendar: Calendar
    ) -> SessionStep {
        SessionStep(
            todo: candidate.todo,
            subject: candidate.todo.subject ?? .other,
            topic: candidate.todo.subtopicName,
            level: candidate.level,
            minutes: minutes,
            estimate: candidate.minutes,
            source: candidate.source,
            reason: reason(for: candidate.todo, level: candidate.level, now: now, calendar: calendar)
        )
    }
}
