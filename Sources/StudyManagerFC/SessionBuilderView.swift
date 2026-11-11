import SwiftUI

/// "I have 90 minutes" → the tasks worth doing in that time, with each row able to start a
/// timer on exactly that task. Removing a row re-plans from the minutes that are left.
struct SessionBuilderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var budget = 60
    @State private var skipped: Set<UUID> = []

    private let presets = [25, 45, 60, 90, 120]

    private var plan: SessionPlan {
        SessionPlanner.plan(
            budget: budget,
            state: store.state,
            sessions: store.state.recentSessions,
            excluding: skipped
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "Plan by time",
                    subtitle: "Ranked by deadline, priority and difficulty — an ETA on a task overrides the level",
                    symbol: "clock.badge.checkmark"
                )
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    Button("\(preset) min") {
                        budget = preset
                        skipped = []
                    }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(budget == preset ? .primary : .white)
                }
                Spacer()
                Stepper("", value: $budget, in: 15...240, step: 5)
                    .labelsHidden()
                Text("\(budget) min")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Neon.sweep)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 10) {
                MetricTile(
                    title: "Planned",
                    value: "\(plan.plannedMinutes)",
                    subtitle: "minutes of \(budget)",
                    symbol: "timer",
                    tint: .studyTeal
                )
                MetricTile(
                    title: "Left over",
                    value: "\(plan.leftOverMinutes)",
                    subtitle: plan.leftOverMinutes < SessionPlanner.minimumChunk ? "nothing worth slicing" : "not yet filled",
                    symbol: "hourglass",
                    tint: .studyGold
                )
                MetricTile(
                    title: "Tasks",
                    value: "\(plan.steps.count)",
                    subtitle: "in this session",
                    symbol: "checklist",
                    tint: .studyGreen
                )
            }

            if plan.isEmpty {
                EmptyStateView(
                    symbol: "clock.badge.questionmark",
                    title: "Nothing to plan",
                    message: store.state.todos.contains(where: { !$0.isCompleted })
                        ? "Every open task is already in the session, or the budget is too small to slice one."
                        : "Add a task and it will be ranked here by its deadline, priority and difficulty."
                )
                .surface(padding: 18)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(plan.steps) { step in
                            row(step)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }

            Text("A slice means the task is longer than the time left; the timer still counts real minutes.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 640)
        .background(AppBackground(paletteKey: store.paletteKey))
    }

    private func row(_ step: SessionStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let priority = step.todo.priority {
                        PriorityBadge(priority: priority)
                    }
                    Text(step.todo.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    if step.isPartial {
                        Pill(text: "\(step.minutes) of \(step.estimate) min", color: .studyAmber, icon: "scissors")
                    }
                }
                Text(subtitle(for: step))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(step.reason)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SubjectTheme.color(for: step.subject).opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(step.minutes) min")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Neon.sweep)

            Button {
                skip(step)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(5)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Take this off the session and re-plan the remaining minutes")

            Button("Start") {
                store.setTimerTodo(step.todo.id)
                store.timerKind = .focusSession
                if !store.isTimerRunning {
                    store.startTimer()
                }
                dismiss()
            }
            .buttonStyle(.bentoBordered)
            .bentoTint(.primary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func subtitle(for step: SessionStep) -> String {
        var parts: [String] = [step.subject.shortName]
        if let topic = step.topic { parts.append(topic) }
        parts.append(SessionPlanner.workloadText(
            minutes: step.estimate,
            source: step.source,
            questions: step.todo.questionCount,
            level: step.level
        ))
        return parts.joined(separator: " · ")
    }

    private func skip(_ step: SessionStep) {
        skipped.insert(step.todo.id)
    }
}
