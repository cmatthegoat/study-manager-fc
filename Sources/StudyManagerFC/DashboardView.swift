import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store

    /// Set by the shell so the "recent study" card can jump to the full, searchable log.
    var onOpenLog: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(
                    eyebrow: "Season \(store.state.seasonNumber) · Level \(store.level)",
                    title: "Study Dashboard",
                    subtitle: "Every minute builds your club. Log study time to unlock the next Champions League match."
                )

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        FocusTimerCard()
                        QuickLogCard()
                        QuickTodoCard()
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        ReadinessCard()
                        StudyStatsGrid()
                    }
                    .frame(width: 350)
                }

                RecentSessionsCard(onOpenLog: onOpenLog)
            }
            .padding(28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct QuickTodoCard: View {
    @Environment(AppStore.self) private var store

    @State private var draftTitle = ""
    @State private var selectedSubject: StudySubject = .other
    @State private var selectedSubtopicID: UUID?

    private var selectedSubtopics: [Subtopic] {
        store.subtopics(for: selectedSubject)
    }

    /// What the typed line will actually file: inline `p1 #Subject - Topic:` directives win.
    private var preview: TodoInput {
        TodoInput.parse(draftTitle, subtopics: store.subtopics)
    }

    private var effectiveSubject: StudySubject {
        preview.subject ?? selectedSubject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "New Task",
                subtitle: "Type p1–p4 for priority, and #Subject - Topic: to file the task inline",
                symbol: "plus.circle"
            )

            TextField("e.g. p1 #Ext 2 Maths - Complex Numbers: finish 4.2", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)

            HStack(spacing: 10) {
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
                Spacer(minLength: 0)
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
        .surface(padding: 20)
    }

    private func add() {
        guard store.addTodo(draftTitle, subject: selectedSubject, subtopicID: selectedSubtopicID) != nil else { return }
        draftTitle = ""
    }
}

private struct FocusTimerCard: View {
    @Environment(AppStore.self) private var store
    /// The paused session's review sheet. It can also be reopened from the card if the
    /// sheet is dismissed without logging.
    @State private var showingReview = false

    private var timeText: String {
        let minutes = store.timerElapsedSeconds / 60
        let seconds = store.timerElapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var timerStatusText: String {
        if store.isTimerRunning { return "RUNNING" }
        if store.pendingTimerMinutes != nil { return "PAUSED" }
        return "READY"
    }

    private var timerStatusColor: Color {
        if store.isTimerRunning { return .studyGreen }
        if store.pendingTimerMinutes != nil { return .studyGold }
        return .secondary.opacity(0.45)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center) {
                SectionHeader(
                    title: "Focus Timer",
                    subtitle: "One minute, one step forward",
                    symbol: "timer"
                )
                HStack(spacing: 6) {
                    Circle()
                        .fill(timerStatusColor)
                        .frame(width: 7, height: 7)
                    Text(timerStatusText)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05), in: Capsule())
            }

            Text(timeText)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.studyGreen, Color.studyTeal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.studyGreen.opacity(0.35), radius: 14)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button {
                    if store.isTimerRunning {
                        // Pausing banks the minutes and opens the review sheet, so nothing
                        // is filed until the type, subject, topic and marks are right.
                        store.pauseTimer()
                    } else if store.pendingTimerMinutes != nil {
                        showingReview = true
                    } else {
                        store.startTimer()
                    }
                } label: {
                    Label(
                        store.isTimerRunning ? "Finish Session" : (store.pendingTimerMinutes != nil ? "Review & Log" : "Start Focus Timer"),
                        systemImage: store.isTimerRunning ? "pause.fill" : (store.pendingTimerMinutes != nil ? "checkmark.circle" : "play.fill")
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.bentoProminent)
                .bentoTint(.primary)

                if store.isTimerRunning || store.timerElapsedSeconds > 0 || store.pendingTimerMinutes != nil {
                    Button {
                        store.resetTimer()
                        store.discardTimerSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.vertical, 9)
                            .padding(.horizontal, 11)
                    }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.white)
                    .help("Discard this session without logging it")
                }
            }

            BentoMenu(
                selection: Binding(
                    get: { store.timerTodoID },
                    set: { store.setTimerTodo($0) }
                ),
                options: [BentoOption("No linked task", value: UUID?.none)]
                    + store.state.todos.filter { !$0.isCompleted }
                        .map { BentoOption($0.title, value: Optional($0.id)) }
            )

            HStack(spacing: 10) {
                BentoMenu(
                    selection: Binding(
                        get: { store.timerKind },
                        set: { store.timerKind = $0; store.timerMarksObtained = nil; store.timerMarksTotal = nil }
                    ),
                    options: StudyActivityKind.allCases.map { BentoOption($0.title, value: $0, symbol: $0.systemImage) },
                    width: 130
                )

                BentoMenu(
                    selection: Binding(
                        get: { store.timerSubject },
                        set: { store.timerSubject = $0; store.timerSubtopicID = nil }
                    ),
                    options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) },
                    width: 120
                )

                BentoMenu(
                    selection: Binding(
                        get: { store.timerSubtopicID },
                        set: { store.timerSubtopicID = $0 }
                    ),
                    options: [BentoOption("Whole subject", value: UUID?.none)]
                        + store.subtopics(for: store.timerSubject).map { BentoOption($0.name, value: Optional($0.id)) },
                    width: 170
                )
            }

            if store.timerKind.supportsMarking {
                HStack(spacing: 10) {
                    TextField("Gained", text: Binding(
                        get: { store.timerMarksObtained.map(String.init) ?? "" },
                        set: { store.timerMarksObtained = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    TextField("Attempted", text: Binding(
                        get: { store.timerMarksTotal.map(String.init) ?? "" },
                        set: { store.timerMarksTotal = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 18) {
                timerLegend(symbol: "banknote", text: "\(GameRules.clubCashPerMinute) cash / min")
                timerLegend(symbol: "sparkles", text: "\(GameRules.xpPerMinute) XP / min")
                timerLegend(symbol: "flag.checkered", text: "1 min toward match")
                Spacer()
            }

            if let pending = store.pendingTimerMinutes {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.studyGold)
                    Text("\(pending) minute\(pending == 1 ? "" : "s") waiting to be logged. Set the type, subject, topic and marks, then confirm.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            if store.lastTimerSessionMinutes > 0 && !store.isTimerRunning {
                Text("Last session logged: \(store.lastTimerSessionMinutes) minutes")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .surface(padding: 22)
        .onChange(of: store.pendingTimerMinutes) { _, newValue in
            if newValue != nil { showingReview = true }
        }
        .sheet(isPresented: $showingReview) {
            TimerReviewSheet()
                .environment(store)
        }
    }

    private func timerLegend(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.secondary)
    }
}

/// Shown when a timer session is finished. Everything about the entry can still change —
/// what kind of work it was, which subject and topic it belongs to, and the marks earned —
/// so a session is filed correctly in one go instead of needing a second entry.
private struct TimerReviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var marksObtained = ""
    @State private var marksTotal = ""

    private var minutes: Int { store.pendingTimerMinutes ?? 0 }

    private var marks: (obtained: Int, total: Int)? {
        guard store.timerKind.supportsMarking,
              let obtained = Int(marksObtained),
              let total = Int(marksTotal),
              total > 0,
              obtained >= 0 else { return nil }
        return (min(obtained, total), total)
    }

    private var reward: StudyReward {
        StudyReward.calculate(
            kind: store.timerKind,
            subject: store.timerSubject,
            minutes: minutes,
            marksObtained: marks?.obtained,
            marksTotal: marks?.total
        )
    }

    private var subjectTopics: [Subtopic] {
        store.subtopics(for: store.timerSubject)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "Finish Session",
                    subtitle: "Check the details, add marks, then log it",
                    symbol: "timer"
                )
                Spacer()
                Button {
                    store.discardTimerSession()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Discard this session")
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(minutes)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.studyGreen)
                    Text(minutes == 1 ? "MINUTE" : "MINUTES")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Pill(text: "+\(reward.cash.formatted()) cash", color: .studyGold, icon: "banknote")
                    Pill(text: "+\(reward.xp) XP", color: .studyTeal, icon: "sparkles")
                    if let percentage = reward.percentage {
                        Pill(text: "\(percentage)% marked", color: .studyGreen, icon: "checkmark.seal")
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 10) {
                reviewRow("Activity") {
                    BentoMenu(
                        selection: Binding(
                            get: { store.timerKind },
                            set: { store.timerKind = $0 }
                        ),
                        options: StudyActivityKind.allCases.map {
                            BentoOption($0.title, value: $0, symbol: $0.systemImage)
                        },
                        width: 200
                    )
                }
                reviewRow("Subject") {
                    BentoMenu(
                        selection: Binding(
                            get: { store.timerSubject },
                            set: { store.timerSubject = $0; store.timerSubtopicID = nil }
                        ),
                        options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) },
                        width: 200
                    )
                }
                reviewRow("Topic") {
                    BentoMenu(
                        selection: Binding(
                            get: { store.timerSubtopicID },
                            set: { store.timerSubtopicID = $0 }
                        ),
                        options: [BentoOption("Whole subject", value: UUID?.none)]
                            + subjectTopics.map { BentoOption($0.name, value: Optional($0.id)) },
                        width: 200
                    )
                }
                reviewRow("Task") {
                    BentoMenu(
                        selection: Binding(
                            get: { store.timerTodoID },
                            set: { store.setTimerTodo($0) }
                        ),
                        options: [BentoOption("No linked task", value: UUID?.none)]
                            + store.state.todos.filter { !$0.isCompleted }
                                .map { BentoOption($0.title, value: Optional($0.id)) },
                        width: 200
                    )
                }
            }

            if store.timerKind.supportsMarking {
                VStack(alignment: .leading, spacing: 7) {
                    Text("MARKS")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Gained", text: $marksObtained)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Text("out of")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField("Total", text: $marksTotal)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Spacer()
                        Text("Leave blank if this work was unmarked")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Nothing has been paid or logged yet — this minute counts the moment you confirm.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Discard") {
                    store.discardTimerSession()
                    dismiss()
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.white)

                Spacer()

                Button {
                    store.timerMarksObtained = marks?.obtained
                    store.timerMarksTotal = marks?.total
                    store.confirmTimerSession()
                    dismiss()
                } label: {
                    Label("Log Session", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bentoProminent)
                .bentoTint(.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(AppBackground())
        .onAppear {
            marksObtained = store.timerMarksObtained.map(String.init) ?? ""
            marksTotal = store.timerMarksTotal.map(String.init) ?? ""
        }
        .onChange(of: store.timerKind) { _, newKind in
            if !newKind.supportsMarking {
                marksObtained = ""
                marksTotal = ""
            }
        }
    }

    private func reviewRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

private struct QuickLogCard: View {
    @Environment(AppStore.self) private var store
    @State private var kind: StudyActivityKind = .homework
    @State private var title = ""
    @State private var minutes = 30
    @State private var quantity = 1
    @State private var subject: StudySubject = .ext1Maths
    @State private var subtopicID: UUID?
    @State private var marksObtained = ""
    @State private var marksTotal = ""

    private let kinds: [StudyActivityKind] = [.homework, .pastPaper, .examQuestions, .focusSession]

    private var subtopics: [Subtopic] {
        store.subtopics(for: subject)
    }

    private var quantityRange: ClosedRange<Int> {
        if kind == .examQuestions { return 1...100 }
        if kind == .focusSession { return 1...1 }
        return 1...10
    }

    private var showMarking: Bool {
        kind.supportsMarking
    }

    private var parsedMarks: (obtained: Int, total: Int)? {
        guard showMarking, let obtained = Int(marksObtained), let total = Int(marksTotal), total > 0, obtained >= 0 else {
            return nil
        }
        return (min(obtained, total), total)
    }

    private var reward: StudyReward {
        StudyReward.calculate(
            kind: kind,
            subject: subject,
            minutes: minutes,
            marksObtained: parsedMarks?.obtained,
            marksTotal: parsedMarks?.total
        )
    }

    private var rewardPreview: String {
        var parts: [String] = []
        if kind.rewardMultiplier != 1 {
            parts.append("\(kind.title) rate ×\(kind.rewardMultiplier.formatted(.number.precision(.fractionLength(0...2))))")
        }
        parts.append("+\(reward.cash) Club Cash")
        parts.append("+\(reward.xp) XP")
        if let percentage = reward.percentage {
            parts.append("\(percentage)% grade")
        }
        parts.append("\(minutes) min toward next match")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Log Study",
                subtitle: "Homework, past papers, or exam-style questions",
                symbol: "square.and.pencil"
            )

            Picker("Activity", selection: $kind) {
                ForEach(kinds) { activity in
                    Label(activity.title, systemImage: activity.systemImage)
                        .tag(activity)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                BentoMenu(
                    selection: $subject,
                    options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) },
                    width: 150
                )

                BentoMenu(
                    selection: $subtopicID,
                    options: [BentoOption(subtopics.isEmpty ? "No topics yet" : "Whole subject", value: UUID?.none)]
                        + subtopics.map { BentoOption($0.name, value: Optional($0.id)) },
                    width: 190,
                    isEnabled: !subtopics.isEmpty
                )

                TextField("What did you work on?", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            .onChange(of: subject) { _, _ in
                subtopicID = nil
            }

            if subtopics.isEmpty {
                Text("Add modules and topics for \(subject.shortName) in the Subjects tab to track marks per topic.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if showMarking {
                HStack(spacing: 10) {
                    Text("Marks")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Gained", text: $marksObtained)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("/")
                        .foregroundStyle(.secondary)
                    TextField("Attempted", text: $marksTotal)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    if let parsedMarks, let percentage = reward.percentage {
                        Pill(text: "\(parsedMarks.obtained)/\(parsedMarks.total) · \(percentage)%", color: .studyGreen, icon: "percent")
                    } else {
                        Text("Gained / attempted — the percentage sets your rate")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Stepper(value: $quantity, in: quantityRange) {
                    Text("\(quantity) \(kind.unitTitle.lowercased())")
                        .font(.system(size: 11))
                        .frame(minWidth: 66, alignment: .leading)
                }
                .fixedSize()

                Spacer()

                Stepper(value: $minutes, in: 5...240, step: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("\(minutes) minutes")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .fixedSize()
            }

            Text(rewardPreview)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.logStudy(
                    kind: kind,
                    title: title,
                    minutes: minutes,
                    quantity: quantity,
                    subject: subject,
                    subtopicID: subtopicID,
                    marksObtained: parsedMarks?.obtained,
                    marksTotal: parsedMarks?.total
                )
                title = ""
                quantity = 1
                marksObtained = ""
                marksTotal = ""
            } label: {
                Label("Log Study Session", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)
        }
        .surface(padding: 20)
    }
}

private struct ReadinessCard: View {
    @Environment(AppStore.self) private var store

    private var ready: Bool { store.state.availableMatchMinutes >= GameRules.minutesPerMatch }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(title: "Match Readiness", subtitle: "The 90-minute rule", symbol: "flag.checkered")
                Spacer()
                Text("\(min(store.state.availableMatchMinutes, 90)) / 90")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ready ? Color.studyGreen : Color.secondary)
            }

            BentoGaugeView(progress: store.matchReadiness, label: "READINESS")
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if ready {
                        Text("Match unlocked")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.studyGreen)
                        Text("Open the Champions League hub to simulate.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(store.minutesUntilMatch) minutes to unlock")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Logged study minutes carry across matches.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.state.availableMatchMinutes > 90 {
                    Pill(text: "BANK \(store.state.availableMatchMinutes)m", color: .studyGold, icon: "tray.full")
                }
            }

            Divider()

            if let fixture = store.nextFixtureForUser, let club = store.managedClub {
                let opponentID = fixture.homeClubID == club.id ? fixture.awayClubID : fixture.homeClubID
                let opponent = ClubDatabase.club(for: opponentID)
                HStack(spacing: 10) {
                    if let opponent { ClubBadge(club: opponent, size: 38) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT MATCH")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text("\(fixture.homeClubID == club.id ? "vs" : "away at") \(opponent?.shortName ?? "TBD")")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(fixture.phase == .league ? "Matchday \(fixture.round)" : fixture.phase.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ClubBadge(club: club, size: 38)
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(store.isSeasonComplete ? "Season complete. Your trophy cabinet is waiting." : "No fixture currently scheduled.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .surface(padding: 20)
    }
}

private struct StudyStatsGrid: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            MetricTile(
                title: "Club Cash",
                value: store.state.clubCash.formatted(),
                subtitle: "Available to spend",
                symbol: "banknote.fill",
                tint: .studyGold
            )
            MetricTile(
                title: "Level \(store.level)",
                value: "\(store.xpIntoLevel) / \(GameRules.xpPerLevel) XP",
                subtitle: "\(store.state.xp.formatted()) lifetime XP",
                symbol: "bolt.fill",
                tint: .studyTeal
            )
            MetricTile(
                title: "Total Study",
                value: "\(store.state.study.totalStudyMinutes / 60)h \(store.state.study.totalStudyMinutes % 60)m",
                subtitle: "\(store.state.study.totalSessions) sessions logged",
                symbol: "hourglass",
                tint: .studyGreen
            )
            MetricTile(
                title: "Study Streak",
                value: "\(store.state.study.currentStreak) days",
                subtitle: "Best: \(store.state.study.bestStreak) days",
                symbol: "flame.fill",
                tint: .orange
            )
            MetricTile(
                title: "Homework",
                value: "\(store.state.study.homeworkCompleted)",
                subtitle: "Assignments completed",
                symbol: "book.closed.fill",
                tint: .blue
            )
            MetricTile(
                title: "Exam Practice",
                value: "\(store.state.study.pastPapersCompleted)",
                subtitle: "\(store.state.study.examQuestionsSolved) questions solved",
                symbol: "doc.text.fill",
                tint: .purple
            )
        }
    }
}

private struct RecentSessionsCard: View {
    @Environment(AppStore.self) private var store
    var onOpenLog: (() -> Void)?

    private var total: Int { store.state.recentSessions.count }
    private var hidden: Int { max(0, total - 8) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    title: "Recent Study",
                    subtitle: hidden > 0
                        ? "Showing the latest 8 of \(total) entries"
                        : "Your latest logged sessions",
                    symbol: "clock.arrow.circlepath"
                )
                if let onOpenLog, !store.state.recentSessions.isEmpty {
                    Button {
                        onOpenLog()
                    } label: {
                        Label(hidden > 0 ? "View all \(total)" : "Open log", systemImage: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.primary)
                    .help("Search every study entry")
                }
            }
            if store.state.recentSessions.isEmpty {
                EmptyStateView(
                    symbol: "timer",
                    title: "No study logged yet",
                    message: "Start the timer or log a session above. Your first 90 minutes unlocks a Champions League match."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(store.state.recentSessions.prefix(8)) { session in
                        HStack(spacing: 12) {
                            Image(systemName: session.kind.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.studyGreen)
                                .frame(width: 30, height: 30)
                                .background(Color.studyGreen.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                HStack(spacing: 6) {
                                    Text(sessionDetail(session))
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
                            Text("\(session.minutes) min")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text("+\(session.cashEarned)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.studyGold)
                                .frame(width: 50, alignment: .trailing)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                store.deleteStudySession(session.id)
                            }
                            .tint(.red)
                        }
                        if session.id != store.state.recentSessions.prefix(8).last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
        .surface(padding: 20)
    }

    private func sessionDetail(_ session: StudySession) -> String {
        var parts: [String] = [session.kind.title]
        if let subject = session.subject {
            parts.append(subject.shortName)
        }
        if let topic = session.subtopicName {
            parts.append(topic)
        }
        parts.append(session.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}
