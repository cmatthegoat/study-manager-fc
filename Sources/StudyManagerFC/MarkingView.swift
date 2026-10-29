import SwiftUI
import UniformTypeIdentifiers

/// Automatic marking of past papers with Apple's on-device model. Marking guidelines and the
/// written answer can be typed, pasted, or supplied as PNG, JPEG or PDF files; the model
/// returns per-question marks which are reviewed here before they reach the assessment log.
struct MarkingView: View {
    @Environment(AppStore.self) private var store

    @State private var subject: StudySubject = .ext2Maths
    @State private var title = ""
    @State private var totalMarks = "100"
    @State private var guidelines = ""
    @State private var comments = ""
    @State private var answer = ""
    @State private var guidelineFiles: [String] = []
    @State private var answerFiles: [String] = []

    @State private var isImportingGuidelines = false
    @State private var isImportingAnswer = false
    @State private var isLoadingFiles = false
    @State private var isMarking = false
    @State private var errorMessage: String?
    @State private var importMessage: String?
    @State private var result: MarkingResult?
    @State private var savedMessage: String?
    /// True when the last pass ran with no rubric, so the result can say the marking was its own.
    @State private var markedWithoutGuidelines = false

    private var availability: MarkingAvailability { MarkingService.availability }

    private var guidelinesAreEmpty: Bool {
        guidelines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canMark: Bool {
        availability.isAvailable
            && !isMarking
            && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Int(totalMarks) ?? 0) > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(
                    eyebrow: "AI Marking",
                    title: "Mark a Past Paper",
                    subtitle: "Add your work — typed, or as PNG, JPEG or PDF files. Guidelines are optional: attach a rubric for strict marking, or leave it out and the model solves each question itself."
                )

                availabilityCard

                HStack(alignment: .top, spacing: 18) {
                    guidelinesCard
                    answerCard
                }

                detailsCard

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let result {
                    resultCard(result)
                }
            }
            .padding(28)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(
            isPresented: $isImportingGuidelines,
            allowedContentTypes: [.png, .jpeg, .pdf],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result, into: .guidelines)
        }
        .fileImporter(
            isPresented: $isImportingAnswer,
            allowedContentTypes: [.png, .jpeg, .pdf],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result, into: .answer)
        }
    }

    private enum ImportTarget { case guidelines, answer }

    // MARK: - Availability

    private var availabilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: availability.isAvailable ? "lock.shield.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(availability.isAvailable ? Color.studyGreen : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(availability.isAvailable ? "On-device marking is ready" : "On-device marking is not available")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(availability.isAvailable
                     ? "Apple Intelligence marks the paper on this Mac. Nothing is uploaded, there is no account and no cost per paper."
                     : unavailableReason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if availability.isAvailable {
                Pill(text: "APPLE INTELLIGENCE", color: .studyTeal, icon: "sparkles")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    private var unavailableReason: String {
        if case .unavailable(let reason) = availability { return reason }
        return "Automatic marking is unavailable right now."
    }

    // MARK: - Inputs

    private var guidelinesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Marking Guidelines",
                subtitle: guidelinesAreEmpty
                    ? "Optional — no rubric needed for obvious work"
                    : "The rubric, pasted or from files",
                symbol: "list.bullet.clipboard"
            )
            if guidelinesAreEmpty {
                Label(
                    "Leave this empty for maths or chemistry where the answer is clear: the model works each question out and marks your working against the correct answer.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: $guidelines)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 170)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if guidelines.isEmpty {
                        Text("Paste the marking guidelines, per-question criteria, or your teacher's notes…")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Button {
                    isImportingGuidelines = true
                } label: {
                    Label("Add PNG / JPEG / PDF", systemImage: "paperclip")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.primary)
                .disabled(isLoadingFiles)
                Spacer()
                if !guidelineFiles.isEmpty {
                    Text("\(guidelineFiles.count) file(s) read")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            if !guidelineFiles.isEmpty {
                fileChips(guidelineFiles)
            }

            TextField("Marker's comments — optional", text: $comments)
                .bentoField()
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Your Answer",
                subtitle: "Typed, or a scan of your working",
                symbol: "square.and.pencil"
            )
            TextEditor(text: $answer)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 170)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if answer.isEmpty {
                        Text("Type your answers, or attach photos or scans of the paper. Handwriting reads far better when the scan is clean and well lit.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Button {
                    isImportingAnswer = true
                } label: {
                    Label("Add PNG / JPEG / PDF", systemImage: "paperclip")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.primary)
                .disabled(isLoadingFiles)
                Spacer()
                if !answerFiles.isEmpty {
                    Text("\(answerFiles.count) file(s) read")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            if !answerFiles.isEmpty {
                fileChips(answerFiles)
            }

            if let importMessage {
                Text(importMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    private func fileChips(_ names: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Pill(text: name, color: .studyTeal, icon: "doc.text")
                }
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Paper Details", subtitle: "Used for the total and the saved assessment", symbol: "doc.text.magnifyingglass")
            HStack(spacing: 10) {
                BentoMenu(
                    selection: $subject,
                    options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) },
                    width: 160
                )
                TextField("Title, e.g. 2024 Trial Paper", text: $title)
                TextField("Total marks", text: $totalMarks)
                    .frame(width: 100)
                Spacer()
                Button {
                    mark()
                } label: {
                    Label(isMarking ? "Marking…" : "Mark Paper", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bentoProminent)
                .bentoTint(.primary)
                .disabled(!canMark)
            }
            if isMarking {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.studyGreen)
            }
            Text("Marks are a draft: the model can misread handwriting or miss a valid method. Check every line before saving.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    // MARK: - Result

    private func resultCard(_ result: MarkingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    title: "Marked",
                    subtitle: "\(result.totalAwarded) of \(result.totalOutOf) marks\(result.percentage.map { " · \($0)%" } ?? "")",
                    symbol: "checkmark.seal"
                )
                Button("Mark again") { self.result = nil }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.white)
            }

            VStack(spacing: 0) {
                ForEach(result.questions) { question in
                    HStack(alignment: .top, spacing: 10) {
                        Text(question.question)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(width: 70, alignment: .leading)
                        Text(question.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(question.awarded)/\(question.outOf)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(question.awarded == question.outOf ? Color.studyGreen : Color.studyGold)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 7)
                    if question.id != result.questions.last?.id {
                        Divider()
                    }
                }
            }

            if let entered = Int(totalMarks), entered > 0, result.totalOutOf != entered {
                Label(
                    "The model split this paper into \(result.totalOutOf) marks, not the \(entered) you entered. Check the question lines before saving.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.orange)
            }

            if !result.feedback.isEmpty {
                Text(result.feedback)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if markedWithoutGuidelines {
                Label(
                    "Marked without a rubric: the model solved the questions itself, so treat these marks as a rougher guide than a marked scheme would give.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let savedMessage {
                    Text(savedMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.studyGreen)
                }
                Spacer()
                Button("Save as Assessment") { save(result) }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    // MARK: - Actions

    private func mark() {
        errorMessage = nil
        savedMessage = nil
        guard let total = Int(totalMarks), total > 0 else {
            errorMessage = "Enter the paper's total marks."
            return
        }
        let request = MarkingRequest(
            subject: subject,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            totalMarks: total,
            answerText: answer,
            guidelinesText: guidelines,
            comments: comments
        )
        markedWithoutGuidelines = guidelinesAreEmpty
        isMarking = true
        Task {
            do {
                let marked = try await MarkingService.mark(request)
                await MainActor.run {
                    result = marked
                    isMarking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isMarking = false
                }
            }
        }
    }

    private func save(_ result: MarkingResult) {
        let assessment = Assessment(
            date: Date(),
            subject: subject,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AI marked paper" : title,
            marksObtained: result.totalAwarded,
            marksTotal: result.totalOutOf,
            weighting: 100,
            classRank: nil,
            overallRank: nil
        )
        if store.addAssessment(assessment) != nil {
            savedMessage = "Saved to Assessments."
        } else {
            errorMessage = "That assessment could not be saved."
        }
    }

    private func importFiles(_ pickerResult: Result<[URL], Error>, into target: ImportTarget) {
        switch pickerResult {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isLoadingFiles = true
            importMessage = nil
            Task {
                var extracted: [(String, String)] = []
                var failures: [String] = []
                for url in urls {
                    do {
                        let text = try await Task.detached(priority: .userInitiated) {
                            try PaperText.text(from: url)
                        }.value
                        extracted.append((url.lastPathComponent, text))
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    for (name, text) in extracted {
                        switch target {
                        case .guidelines:
                            guidelines += guidelines.isEmpty ? text : "\n\n\(text)"
                            if !guidelineFiles.contains(name) { guidelineFiles.append(name) }
                        case .answer:
                            answer += answer.isEmpty ? text : "\n\n\(text)"
                            if !answerFiles.contains(name) { answerFiles.append(name) }
                        }
                    }
                    importMessage = failures.isEmpty
                        ? (extracted.isEmpty ? "No readable text found in those files." : nil)
                        : failures.joined(separator: "\n")
                    isLoadingFiles = false
                }
            }
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }
}
