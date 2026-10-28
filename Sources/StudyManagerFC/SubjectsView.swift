import SwiftUI

struct SubjectsView: View {
    @Environment(AppStore.self) private var store
    
    private var overall: StudyAggregate {
        store.studyAggregate
    }
    
    private var trackedSubjectCount: Int {
        Set(store.state.subtopics.map(\.subject)).count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ScreenHeader(
                    eyebrow: "Subject Tracker",
                    title: "Modules, Marks & Averages",
                    subtitle: "Split every subject into the modules you are actually studying, then log marks as gained over attempted. Past papers earn 1.5x, exam-style questions 1.25x and homework 1x, before the subject multiplier."
                )
                
                overview

                subjectAveragesCard

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                    spacing: 18
                ) {
                    ForEach(StudySubject.allCases) { subject in
                        SubjectCard(subject: subject)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
    }
    
    /// Every subject side by side, pooled from all marked work. The per-subject cards below
    /// break their own bar down by topic.
    private var subjectAveragesCard: some View {
        let rows = MarksAverages.bySubject(store.state.recentSessions)
        let aggregate = overall
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Average by Subject",
                subtitle: "Pooled percentage across every marked piece, all work kinds together",
                symbol: "chart.bar.xaxis"
            )
            if rows.isEmpty {
                Text("Log homework, a past paper or exam questions with marks and each subject will appear here.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                MarksAverageChart(rows: rows, perRowHeight: 32)
                HStack(spacing: 18) {
                    markStat("Pieces", "\(aggregate.sessions)")
                    markStat("Overall average", aggregate.averagePercentage.map { "\($0)%" } ?? "–")
                    markStat("Marks", "\(aggregate.marksObtained)/\(aggregate.marksTotal)")
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private func markStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var overview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                MetricTile(
                    title: "Marks Attempted",
                    value: "\(overall.marksTotal)",
                    subtitle: "\(overall.marksObtained) gained across every piece",
                    symbol: "checklist",
                    tint: .studyTeal
                )
                MetricTile(
                    title: "Average Mark",
                    value: overall.averagePercentage.map { "\($0)%" } ?? "—",
                    subtitle: overall.hasMarks ? "Weighted by marks attempted" : "Log a marked piece to see this",
                    symbol: "percent",
                    tint: .studyGold
                )
                MetricTile(
                    title: "Work Completed",
                    value: "\(overall.workCount)",
                    subtitle: "\(overall.pastPapers) papers · \(overall.homework) homework · \(overall.examQuestions) questions",
                    symbol: "doc.on.doc.fill",
                    tint: .blue
                )
                MetricTile(
                    title: "Tracked Topics",
                    value: "\(store.state.subtopics.count)",
                    subtitle: "Across \(trackedSubjectCount) subject\(trackedSubjectCount == 1 ? "" : "s")",
                    symbol: "books.vertical.fill",
                    tint: .studyGreen
                )
            }
            
            if store.state.subtopics.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.studyGold)
                    Text("Start by adding the modules or topics you are working through.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color.studyGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

struct SubjectCard: View {
    @Environment(AppStore.self) private var store
    let subject: StudySubject
    
    @State private var draftTopic = ""
    @State private var draftTodo = ""
    @State private var selectedSubtopicID: UUID?
    
    private var aggregate: StudyAggregate {
        store.aggregate(for: subject)
    }
    
    private var topics: [Subtopic] {
        store.subtopics(for: subject)
    }
    
    private var todos: [TodoItem] {
        store.todos(for: subject)
    }
    
    private var averageTint: Color {
        gradeColor(for: aggregate.averagePercentage)
    }

    /// This subject's marked work, split by its own topics.
    private var topicAverages: [MarksAverageRow] {
        MarksAverages.byTopic(store.state.recentSessions.filter { $0.subject == subject })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            stats
            if !topicAverages.isEmpty {
                Divider()
                sectionLabel("MARKS BY TOPIC", count: topicAverages.count)
                MarksAverageChart(rows: topicAverages, perRowHeight: 26, showsPieceCount: false)
            }
            Divider()
            sectionLabel("TOPICS", count: topics.count)
            topicList
            addTopicRow
            Divider()
            sectionLabel("TODOS", count: todos.count)
            todoList
            addTodoRow
        }
    }
    
    var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Pill(text: "×\(multiplierText(subject.cashMultiplier)) cash", color: .studyGold, icon: "banknote")
                    Pill(text: "×\(multiplierText(subject.xpMultiplier)) XP", color: .studyTeal, icon: "bolt")
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(aggregate.averagePercentage.map { "\($0)%" } ?? "—")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(aggregate.hasMarks ? averageTint : Color.secondary)
                    .monospacedDigit()
                Text("AVERAGE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    var stats: some View {
        HStack(spacing: 0) {
            stat("STUDY TIME", durationText(aggregate.minutes))
            statDivider
            stat("WORK DONE", "\(aggregate.workCount)")
            statDivider
            stat("PAST PAPERS", "\(aggregate.pastPapers)")
            statDivider
            stat("MARKS", aggregate.hasMarks ? "\(aggregate.marksObtained)/\(aggregate.marksTotal)" : "—")
        }
    }
    
    var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 10)
    }
    
    func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 7.5, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
        }
    }
    
    private func sectionLabel(_ text: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.06), in: Capsule())
            Spacer()
        }
    }
    
    var topicList: some View {
        VStack(spacing: 7) {
            if topics.isEmpty {
                emptyHint("No topics yet — add the first module below.")
            } else {
                ForEach(topics) { topic in
                    SubtopicRow(subtopic: topic, aggregate: store.aggregate(forSubtopic: topic.id)) {
                        store.deleteSubtopic(topic.id)
                    }
                }
            }
        }
    }
    
    var todoList: some View {
        VStack(spacing: 7) {
            if todos.isEmpty {
                emptyHint("No todos yet — add a task below.")
            } else {
                ForEach(todos) { todo in
                    TodoItemRow(todo: todo)
                }
            }
        }
    }
    
    func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var addTopicRow: some View {
        HStack(spacing: 8) {
            TextField("Add a module or topic", text: $draftTopic)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTopic)
            Button(action: addTopic) {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)
            .disabled(draftTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    var addTodoRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("Add a todo (p1–p4, #Subject - Topic:)", text: $draftTodo)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTodo)
                Button(action: addTodo) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bentoProminent)
                .bentoTint(.secondary)
                .disabled(draftTodo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 6) {
                Text("SUBTOPIC")
                    .font(.system(size: 7.5, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                BentoMenu(
                    selection: $selectedSubtopicID,
                    options: [BentoOption("None", value: UUID?.none)]
                        + topics.map { BentoOption($0.name, value: Optional($0.id)) },
                    width: 220
                )
                Spacer()
            }
        }
    }
    
    func addTopic() {
        guard store.addSubtopic(draftTopic, to: subject) != nil else { return }
        draftTopic = ""
    }
    
    func addTodo() {
        guard store.addTodo(draftTodo, subject: subject, subtopicID: selectedSubtopicID) != nil else { return }
        draftTodo = ""
    }
}

struct TodoItemRow: View {
    @Environment(AppStore.self) private var store
    let todo: TodoItem
    @State private var isShowingDetail = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                store.toggleTodo(todo.id)
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(todo.isCompleted ? Color.studyGreen : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(todo.isCompleted ? "Mark as not done" : "Mark as done")
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if let priority = todo.priority {
                        PriorityBadge(priority: priority)
                    }
                    Text(todo.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .strikethrough(todo.isCompleted, color: .secondary)
                        .foregroundStyle(todo.isCompleted ? Color.secondary : Color.primary)
                        .lineLimit(2)
                }
                if let subtopic = todo.subtopicName {
                    Text(subtopic)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            Spacer(minLength: 4)
            Button(action: { store.deleteTodo(todo.id) }) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete \(todo.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(todo.isCompleted ? 0.015 : 0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { isShowingDetail = true }
        .help("Edit task")
        .sheet(isPresented: $isShowingDetail) {
            TodoDetailSheet(todoID: todo.id)
                .environment(store)
        }
    }
}

/// Opens a task for editing: title, subject, topic and priority.
struct TodoDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let todoID: UUID

    @State private var title = ""
    @State private var subject: StudySubject = .other
    @State private var subtopicID: UUID?
    @State private var priority: Int? = nil

    private var subjectTopics: [Subtopic] {
        store.subtopics(for: subject)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Task")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Form {
                TextField("Task title", text: $title)
                LabeledContent("Subject") {
                    BentoMenu(
                        selection: $subject,
                        options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) },
                        width: 180
                    )
                    .onChange(of: subject) { _, _ in
                        if !subjectTopics.contains(where: { $0.id == subtopicID }) {
                            subtopicID = nil
                        }
                    }
                }
                LabeledContent("Topic") {
                    BentoMenu(
                        selection: $subtopicID,
                        options: [BentoOption("No topic", value: UUID?.none)]
                            + subjectTopics.map { BentoOption($0.name, value: Optional($0.id)) },
                        width: 180
                    )
                }
                LabeledContent("Priority") {
                    BentoMenu(
                        selection: $priority,
                        options: [BentoOption("None", value: Int?.none)]
                            + [1, 2, 3, 4].map { BentoOption("P\($0)", value: Optional($0)) },
                        width: 180
                    )
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.bentoProminent)
                .bentoTint(.primary)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: load)
    }

    private func load() {
        guard let todo = store.todos.first(where: { $0.id == todoID }) else { return }
        title = todo.title
        subject = todo.subject ?? .other
        subtopicID = todo.subtopicID
        priority = todo.priority
    }

    private func save() {
        guard let index = store.todos.firstIndex(where: { $0.id == todoID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var draft = store.state
        let topic = subjectTopics.first(where: { $0.id == subtopicID })
        draft.todos[index].title = trimmed
        draft.todos[index].subject = subject == .other ? nil : subject
        draft.todos[index].subtopicID = topic?.id
        draft.todos[index].subtopicName = topic?.name
        draft.todos[index].priority = priority
        store.commit(draft)
    }
}

struct SubtopicRow: View {
    let subtopic: Subtopic
    let aggregate: StudyAggregate
    let onDelete: () -> Void
    
    var tint: Color {
        gradeColor(for: aggregate.averagePercentage)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(subtopic.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                    if let percentage = aggregate.averagePercentage {
                        Text("\(percentage)%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .monospacedDigit()
                    } else {
                        Text("UNMARKED")
                            .font(.system(size: 7.5, weight: .black, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(summary)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ReadinessBar(progress: aggregate.averageRatio ?? 0, tint: tint, height: 4)
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete \(subtopic.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    var summary: String {
        var parts: [String] = []
        if aggregate.hasMarks {
            parts.append("\(aggregate.marksObtained)/\(aggregate.marksTotal) marks")
        }
        if aggregate.pastPapers > 0 {
            parts.append("\(aggregate.pastPapers) paper\(aggregate.pastPapers == 1 ? "" : "s")")
        }
        if aggregate.minutes > 0 {
            parts.append(durationText(aggregate.minutes))
        }
        return parts.isEmpty ? "No work logged" : parts.joined(separator: " · ")
    }
}

struct SubjectsView_Previews: PreviewProvider {
    static var previews: some View {
        SubjectsView()
    }
}

// MARK: - Grade color function
func gradeColor(for percentage: Int?) -> Color {
    guard let percentage else { return .secondary }
    switch percentage {
    case 85...: return .studyGreen
    case 70..<85: return .studyTeal
    case 55..<70: return .studyGold
    default: return .orange
    }
}

// MARK: - Duration text function
func durationText(_ minutes: Int) -> String {
    guard minutes > 0 else { return "0m" }
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours > 0 && remainder > 0 { return "\(hours)h \(remainder)m" }
    if hours > 0 { return "\(hours)h" }
    return "\(remainder)m"
}

// MARK: - Multiplier text function
func multiplierText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}