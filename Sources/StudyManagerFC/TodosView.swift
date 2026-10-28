import SwiftUI

struct TodosView: View {
    @Environment(AppStore.self) private var store

    @State private var draftTitle = ""
    @State private var selectedSubject: StudySubject = .other
    @State private var selectedSubtopicID: UUID?

    @State private var editingTodoID: UUID?
    @State private var editingTitle = ""
    @State private var editingSubject: StudySubject = .other
    @State private var editingSubtopicName: String?
    @State private var editingPriority: Int?

    private var openCount: Int {
        store.todos.filter { !$0.isCompleted }.count
    }

    private var doneCount: Int {
        store.todos.filter(\.isCompleted).count
    }

    private var subjectsWithTodos: Int {
        Set(store.todos.compactMap(\.subject)).count
    }

    private var selectedSubtopics: [Subtopic] {
        store.subtopics(for: selectedSubject)
    }

    /// What the typed line will actually file: inline `p1 #Subject - Topic:` directives win.
    private var preview: TodoInput {
        TodoInput.parse(draftTitle, subtopics: store.subtopics)
    }

    /// When a todo row is tapped (not the circle), opens the edit view.
    private var isEditing: Bool {
        editingTodoID != nil
    }

    private var editingTodo: TodoItem? {
        store.todos.first(where: { $0.id == editingTodoID })
    }

    private var effectiveSubject: StudySubject {
        preview.subject ?? selectedSubject
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ScreenHeader(
                    eyebrow: "Todo List",
                    title: "Every Task, Filed by Subject",
                    subtitle: "Keep everything you need to do in one place. Each task belongs to a subject and can be tied to one of that subject's topics, so nothing gets lost between modules — and ticking one off pays Club Cash scaled by that subject's multiplier."
                )

                overview
                addCard

                if store.todos.isEmpty {
                    EmptyStateView(
                        symbol: "checklist",
                        title: "No todos yet",
                        message: "Add your first task above, pick its subject and subtopic, and it will show up here."
                    )
                    .surface(padding: 20)
                } else {
                    ForEach(StudySubject.allCases) { subject in
                        let items = store.todos(for: subject)
                        if !items.isEmpty {
                            subjectSection(subject: subject, items: items)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: selectedSubject) { _, _ in
            selectedSubtopicID = nil
        }
    }

    private var overview: some View {
        HStack(spacing: 16) {
            MetricTile(
                title: "Open Tasks",
                value: "\(openCount)",
                subtitle: "Across \(subjectsWithTodos) subject\(subjectsWithTodos == 1 ? "" : "s")",
                symbol: "circle.dashed",
                tint: .studyGold
            )
            MetricTile(
                title: "Completed",
                value: "\(doneCount)",
                subtitle: "Ticked off so far",
                symbol: "checkmark.seal.fill",
                tint: .studyGreen
            )
            MetricTile(
                title: "Total Tasks",
                value: "\(store.todos.count)",
                subtitle: "On your board",
                symbol: "checklist",
                tint: .studyTeal
            )
        }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "New Task",
                subtitle: "Type p1–p4 for priority, and #Subject - Topic: to file the task inline",
                symbol: "plus.circle"
            )
            HStack(spacing: 10) {
                TextField("e.g. p1 #Ext 2 Maths - Complex Numbers: finish 4.2", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                BentoMenu(
                    selection: $selectedSubject,
                    options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) },
                    width: 150
                )
                BentoMenu(
                    selection: $selectedSubtopicID,
                    options: [BentoOption("No subtopic", value: UUID?.none)]
                        + selectedSubtopics.map { BentoOption($0.name, value: Optional($0.id)) },
                    width: 170
                )
                Button(action: add) {
                    Label("Add Task", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bentoProminent)
                .bentoTint(.primary)
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 6) {
                Pill(
                    text: "+\(store.todoReward(for: effectiveSubject)) cash when completed (×\(multiplierText(effectiveSubject.cashMultiplier)))",
                    color: .studyGold,
                    icon: "banknote"
                )
                if let subject = preview.subject {
                    Pill(text: subject.shortName, color: .studyTeal, icon: "number")
                }
                if let topic = preview.subtopicName {
                    Pill(text: topic, color: .studyTeal, icon: "tag")
                }
                if let priority = preview.priority {
                    PriorityBadge(priority: priority)
                }
            }
        }
        .surface(padding: 18)
    }

    private func subjectSection(subject: StudySubject, items: [TodoItem]) -> some View {
        let open = items.filter { !$0.isCompleted }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(subject.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("\(open) open · \(items.count) total")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Pill(
                    text: "\(store.todoReward(for: subject)) cash each",
                    color: .studyGold,
                    icon: "banknote"
                )
            }
            ForEach(items) { todo in
                if isEditing && editingTodoID == todo.id {
                    EditTodoRow(todo: todo, onSave: saveEdit, onCancel: resetEdit)
                } else {
                    TodoItemRow(todo: todo)
                }
            }
        }
        .surface(padding: 18)
    }

    private func add() {
        guard store.addTodo(draftTitle, subject: selectedSubject, subtopicID: selectedSubtopicID) != nil else { return }
        draftTitle = ""
    }

    private func startEdit(_ todo: TodoItem) {
        editingTodoID = todo.id
        editingTitle = todo.title
        editingSubject = todo.subject ?? .other
        editingSubtopicName = todo.subtopicName
        editingPriority = todo.priority
    }

    private func saveEdit() {
        guard let todoID = editingTodoID,
              let index = store.todos.firstIndex(where: { $0.id == todoID }) else {
            resetEdit()
            return
        }
        var draft = store.state
        let newSubject = editingSubject == .other ? nil : editingSubject
        draft.todos[index].title = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.todos[index].subject = newSubject
        draft.todos[index].subtopicName = editingSubtopicName
        draft.todos[index].priority = editingPriority
        store.commit(draft)
        resetEdit()
    }

    private func resetEdit() {
        editingTodoID = nil
        editingTitle = ""
        editingSubject = .other
        editingSubtopicName = nil
        editingPriority = nil
    }

    private func deleteTodo(_ id: UUID) {
        guard store.todos.contains(where: { $0.id == id }) else { return }
        var draft = store.state
        draft.todos.removeAll { $0.id == id }
        store.commit(draft)
    }
}

struct PriorityBadge: View {
    let priority: Int

    private var tint: Color {
        switch priority {
        case 1: .red
        case 2: .orange
        case 3: .studyGold
        default: .secondary
        }
    }

    var body: some View {
        Text("P\(priority)")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .help("Priority \(priority)")
    }
}

struct EditTodoRow: View {
    @Environment(AppStore.self) private var store
    let todo: TodoItem
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var subject: StudySubject = .other
    @State private var subtopicName = ""
    @State private var priority: Int? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Task title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                Section("Subject") {
                    BentoMenu(
                        selection: $subject,
                        options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) }
                    )
                }
                Section("Subtopic") {
                    TextField("Subtopic name", text: $subtopicName)
                        .textFieldStyle(.roundedBorder)
                }
                Section("Priority") {
                    BentoMenu(
                        selection: $priority,
                        options: [BentoOption("None", value: Int?.none)]
                            + [1, 2, 3, 4].map { BentoOption("P\($0)", value: Optional($0)) }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TodosView_Previews: PreviewProvider {
    static var previews: some View {
        TodosView()
    }
}