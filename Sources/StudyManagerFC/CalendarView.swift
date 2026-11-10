import SwiftUI

/// A month at a glance for every task with a due date: what is already late, what lands
/// today, and where the rest of the month piles up. Selecting a day opens its tasks below
/// the grid, so the calendar is a way to work the list rather than just look at it.
struct CalendarView: View {
    @Environment(AppStore.self) private var store

    @State private var visibleMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current

    /// Only dated tasks belong on the grid; the undated ones get their own card further down.
    private var datedTasks: [TodoItem] {
        store.todos.filter { $0.dueDate != nil && !$0.isCompleted }
    }

    private var tasksByDay: [Date: [TodoItem]] {
        var buckets: [Date: [TodoItem]] = [:]
        for todo in datedTasks {
            guard let day = todo.dueDay else { continue }
            buckets[day, default: []].append(todo)
        }
        return buckets
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var dueTodayCount: Int {
        tasksByDay[today]?.count ?? 0
    }

    /// A rolling week rather than the calendar week, so a Monday deadline still shows as
    /// coming up on a Friday.
    private var dueSoonCount: Int {
        guard let end = calendar.date(byAdding: .day, value: 7, to: today) else { return 0 }
        return datedTasks.filter { todo in
            guard let day = todo.dueDay else { return false }
            return day >= today && day < end
        }.count
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let firstOfMonth = calendar.startOfDay(for: interval.start)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        // Blank cells before the 1st, so the columns line up under their weekday.
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayRange.count {
            days.append(calendar.date(byAdding: .day, value: offset, to: firstOfMonth).map { calendar.startOfDay(for: $0) })
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    private var selectedDayTitle: String {
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var selectedDayTasks: [TodoItem] {
        tasksByDay[selectedDay] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(
                    eyebrow: "Calendar",
                    title: "Every Deadline, Month by Month",
                    subtitle: "Tasks with a due date land on this grid. Pick a day to see what it owes you, tick work off straight from the list, and spot the pile-ups before they arrive."
                )

                overview
                monthCard
                selectedDayCard
                undatedCard
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    private var overview: some View {
        HStack(spacing: 16) {
            MetricTile(
                title: "Overdue",
                value: "\(store.overdueTodos.count)",
                subtitle: "Past their due day",
                symbol: "exclamationmark.triangle.fill",
                tint: .red
            )
            MetricTile(
                title: "Due Today",
                value: "\(dueTodayCount)",
                subtitle: "On the board now",
                symbol: "calendar.badge.clock",
                tint: .studyAmber
            )
            MetricTile(
                title: "Next 7 Days",
                value: "\(dueSoonCount)",
                subtitle: "Coming up this week",
                symbol: "calendar",
                tint: .studyTeal
            )
        }
    }

    private var monthCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Previous month")

                Text(monthTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(minWidth: 150, alignment: .leading)

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Next month")

                Spacer(minLength: 0)

                if !datedTasks.isEmpty {
                    Pill(
                        text: "\(datedTasks.count) dated task\(datedTasks.count == 1 ? "" : "s")",
                        color: .studyTeal,
                        icon: "checklist"
                    )
                }
                Button("Today") {
                    visibleMonth = today
                    selectedDay = today
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Neon.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Neon.accent.opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke(Neon.accent.opacity(0.45), lineWidth: 0.75))
            }

            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Color.studyMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 6
            ) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 76)
                    }
                }
            }
        }
        .surface(padding: 18)
    }

    private func dayCell(_ day: Date) -> some View {
        let tasks = tasksByDay[day] ?? []
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasOverdue = tasks.contains(where: \.isOverdue)

        return Button {
            selectedDay = day
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 11, weight: isToday ? .black : .semibold, design: .rounded))
                        .foregroundStyle(isToday ? Color.studyGold : Color.primary)
                    Spacer(minLength: 0)
                    if hasOverdue {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.red)
                    } else if !tasks.isEmpty {
                        Text("\(tasks.count)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(tasks.prefix(2))) { todo in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(SubjectTheme.color(for: todo.subject ?? .other))
                                .frame(width: 4, height: 4)
                            Text(todo.title)
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .lineLimit(1)
                        }
                    }
                    if tasks.count > 2 {
                        Text("+\(tasks.count - 2) more")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Neon.accent.opacity(0.20) : Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? Neon.accent.opacity(0.85)
                            : (isToday ? Color.studyGold.opacity(0.55) : Color.white.opacity(0.07)),
                        lineWidth: isSelected || isToday ? 1.4 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText(for: day, tasks: tasks))
    }

    private var selectedDayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: selectedDayTitle,
                subtitle: selectedDayTasks.isEmpty
                    ? "Nothing due"
                    : "\(selectedDayTasks.count) task\(selectedDayTasks.count == 1 ? "" : "s") due on the board",
                symbol: "calendar.badge.clock"
            )

            if selectedDayTasks.isEmpty {
                Text("No tasks are due on this day. Give a task a due date from its edit sheet and it will show up here, or add one in the Todos tab.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(selectedDayTasks) { todo in
                        TodoItemRow(todo: todo)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var undatedCard: some View {
        let tasks = store.undatedTodos
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "No Due Date",
                subtitle: tasks.isEmpty
                    ? "Every open task has a deadline"
                    : "\(tasks.count) open task\(tasks.count == 1 ? "" : "s") still to schedule",
                symbol: "calendar.badge.exclamationmark"
            )

            if tasks.isEmpty {
                Text("Every open task is on the calendar.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(tasks) { todo in
                        TodoItemRow(todo: todo)
                    }
                }
                Text("Tap a task to give it a due date.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private func shiftMonth(_ months: Int) {
        guard let target = calendar.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        let month = calendar.startOfDay(for: target)
        visibleMonth = month
        // Keep the day card in step with the grid rather than showing a day from another month.
        if !calendar.isDate(selectedDay, equalTo: month, toGranularity: .month) {
            selectedDay = month
        }
    }

    private func helpText(for day: Date, tasks: [TodoItem]) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard !tasks.isEmpty else { return "\(date) — nothing due" }
        return "\(date) — \(tasks.count) task\(tasks.count == 1 ? "" : "s") due"
    }
}

struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarView()
    }
}
