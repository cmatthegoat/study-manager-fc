import Charts
import SwiftUI

struct ExamsView: View {
    @Environment(AppStore.self) private var store

    @State private var subject: StudySubject = .ext2Maths
    @State private var title = ""
    @State private var marksObtained = ""
    @State private var marksTotal = ""
    @State private var weighting = ""
    @State private var classRank = ""
    @State private var overallRank = ""
    @State private var date = Date()
    @State private var workKind: WorkKind = .homework
    /// Whether the average-marks chart pools work by subject or by topic.
    @State private var markGrouping: MarkGrouping = .subject

    /// Which kind of logged work the marks chart is showing. Assessments are charted
    /// separately above; these are the homework, past papers and exam questions logged
    /// through the timer and quick log.
    private enum WorkKind: String, CaseIterable, Identifiable {
        case homework
        case pastPaper
        case examQuestions
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .homework: "Homework"
            case .pastPaper: "Past Papers"
            case .examQuestions: "Exam Qs"
            case .all: "All Work"
            }
        }

        func matches(_ session: StudySession) -> Bool {
            switch self {
            case .homework: session.kind == .homework
            case .pastPaper: session.kind == .pastPaper
            case .examQuestions: session.kind == .examQuestions
            case .all: session.kind != .focusSession
            }
        }
    }

    /// What the average-marks chart groups by. Topics are the finer cut of the same data.
    private enum MarkGrouping: String, CaseIterable, Identifiable {
        case subject
        case topic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .subject: "Subjects"
            case .topic: "Topics"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ScreenHeader(
                    eyebrow: "Exams",
                    title: "Tests & Exams",
                    subtitle: "Log assessments. Only your class rank earns cash and XP."
                )
                addCard
                marksGraphCard
                workMarksCard
                rankGraphCard
                listCard
            }
            .padding(28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Add Assessment", subtitle: "Class rank 1 pays the full reward, each place below pays less", symbol: "doc.text.magnifyingglass")
            HStack(spacing: 10) {
                BentoMenu(
                    selection: $subject,
                    options: StudySubject.allCases.map { BentoOption($0.displayName, value: $0) },
                    width: 180
                )
                TextField("Title, e.g. Half-yearly", text: $title)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            HStack(spacing: 10) {
                TextField("Marks gained", text: $marksObtained)
                TextField("Marks total", text: $marksTotal)
                TextField("Weighting %", text: $weighting)
                TextField("Class rank", text: $classRank)
                TextField("Overall rank", text: $overallRank)
            }
            HStack {
                Spacer()
                Button("Save Assessment") { saveAssessment() }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.primary)
                    .disabled(!canSave)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var canSave: Bool {
        guard let obtained = Int(marksObtained), let total = Int(marksTotal) else { return false }
        return total > 0 && obtained >= 0 && obtained <= total && Int(classRank) != nil
    }

    private func saveAssessment() {
        guard let obtained = Int(marksObtained), let total = Int(marksTotal) else { return }
        let assessment = Assessment(
            date: date,
            subject: subject,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            marksObtained: obtained,
            marksTotal: total,
            weighting: Int(weighting) ?? 100,
            classRank: Int(classRank),
            overallRank: Int(overallRank)
        )
        if store.addAssessment(assessment) != nil {
            title = ""
            marksObtained = ""
            marksTotal = ""
            weighting = ""
            classRank = ""
            overallRank = ""
        }
    }

    private var sortedAssessments: [Assessment] {
        store.state.assessments.sorted { $0.date < $1.date }
    }

    private var marksGraphCard: some View {
        let marked = sortedAssessments.filter { $0.percentage != nil }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Marks Over Time", subtitle: "Percentage per assessment", symbol: "chart.xyaxis.line")
            if marked.isEmpty {
                Text("Log an assessment with marks to see this graph.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Chart(marked) { assessment in
                    LineMark(
                        x: .value("Date", assessment.date),
                        y: .value("Mark %", assessment.percentage ?? 0)
                    )
                    .foregroundStyle(by: .value("Subject", assessment.subject.shortName))
                    PointMark(
                        x: .value("Date", assessment.date),
                        y: .value("Mark %", assessment.percentage ?? 0)
                    )
                    .foregroundStyle(by: .value("Subject", assessment.subject.shortName))
                }
                .chartYScale(domain: 0...100)
                .chartForegroundStyleScale(
                    domain: StudySubject.allCases.map(\.shortName),
                    range: StudySubject.allCases.map { SubjectTheme.color(for: $0) }
                )
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    /// Marks from the work logged through the timer and quick log, pooled into an average per
    /// subject or per topic. Comparing averages answers "which module is weakest", which a
    /// line of dots over dates never did.
    private var workMarksCard: some View {
        let sessions = workSessions
        let aggregate = StudyAggregate.build(from: sessions)
        let rows = averageRows
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Average Marks",
                subtitle: markGrouping == .subject
                    ? "Pooled percentage for each subject across every marked piece"
                    : "Pooled percentage for each topic across every marked piece",
                symbol: "chart.bar.fill"
            )

            HStack(spacing: 12) {
                Picker("Kind", selection: $workKind) {
                    ForEach(WorkKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Group", selection: $markGrouping) {
                    ForEach(MarkGrouping.allCases) { grouping in
                        Text(grouping.title).tag(grouping)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }

            if rows.isEmpty {
                Text("Log homework, a past paper or exam questions with marks and the averages will appear here.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                MarksAverageChart(rows: rows, usesSubjectColors: markGrouping == .subject)

                HStack(spacing: 18) {
                    workStat("Pieces", "\(aggregate.sessions)")
                    workStat("Average", aggregate.averagePercentage.map { "\($0)%" } ?? "–")
                    workStat("Marks", "\(aggregate.marksObtained)/\(aggregate.marksTotal)")
                    workStat("Best", "\(sessions.compactMap(\.percentage).max() ?? 0)%")
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var workSessions: [StudySession] {
        store.state.recentSessions
            .filter { $0.percentage != nil && workKind.matches($0) }
            .sorted { $0.date < $1.date }
    }

    /// Pools the filtered pieces with the shared grouping, so this tab and the Subjects tab
    /// always agree on the numbers.
    private var averageRows: [MarksAverageRow] {
        switch markGrouping {
        case .subject: MarksAverages.bySubject(workSessions)
        case .topic: MarksAverages.byTopic(workSessions)
        }
    }

    private func workStat(_ label: String, _ value: String) -> some View {
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

    private var rankGraphCard: some View {
        let ranked = sortedAssessments.filter { $0.classRank != nil || $0.overallRank != nil }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Class & Overall Rank", subtitle: "Lower is better", symbol: "list.number")
            if ranked.isEmpty {
                Text("Enter a class or overall rank to see this graph.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(ranked) { assessment in
                        if let rank = assessment.classRank {
                            LineMark(
                                x: .value("Date", assessment.date),
                                y: .value("Rank", rank),
                                series: .value("Series", "Class rank")
                            )
                            .foregroundStyle(Color.studyGreen)
                            PointMark(
                                x: .value("Date", assessment.date),
                                y: .value("Rank", rank)
                            )
                            .foregroundStyle(Color.studyGreen)
                        }
                        if let rank = assessment.overallRank {
                            LineMark(
                                x: .value("Date", assessment.date),
                                y: .value("Rank", rank),
                                series: .value("Series", "Overall rank")
                            )
                            .foregroundStyle(Color.studyGold)
                            PointMark(
                                x: .value("Date", assessment.date),
                                y: .value("Rank", rank)
                            )
                            .foregroundStyle(Color.studyGold)
                        }
                    }
                }
                .chartYAxis { AxisMarks(preset: .automatic) }
                .chartYScale(domain: .automatic(reversed: true))
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Assessments", subtitle: "Newest first", symbol: "list.bullet")
            if store.state.assessments.isEmpty {
                Text("No assessments logged yet.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(store.state.assessments) { assessment in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assessment.title.isEmpty ? assessment.subject.shortName : assessment.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(assessment.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(assessment.subject.shortName)
                        .foregroundStyle(SubjectTheme.color(for: assessment.subject))
                    Text("\(assessment.marksObtained)/\(assessment.marksTotal)")
                    Text(assessment.percentage.map { "\($0)%" } ?? "–")
                        .fontWeight(.bold)
                    Text("Class #\(assessment.classRank.map(String.init) ?? "–")")
                    Text("+\(assessment.cashEarned) cash")
                    Text("+\(assessment.xpEarned) XP")
                    Button(role: .destructive) {
                        store.deleteAssessment(assessment.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }
}
