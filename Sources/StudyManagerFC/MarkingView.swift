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
    /// Which marker produced the result, and what it cost, so a cloud pass is never mistaken
    /// for an on-device one.
    @State private var resultBackend: MarkingBackendKind?
    @State private var resultDetail: String?
    /// Scans posted to a cloud model. The on-device marker uses the recognised text instead.
    @State private var answerImages: [MarkingImage] = []
    @State private var settingsExpanded = false
    /// The marker in use, shared with the settings card and the quick menu beside Mark Paper.
    @State private var marker: MarkingBackendPreference = MarkingPreferences.preference
    @State private var savedMessage: String?
    /// Set once the dropped marks have been copied into the Bulletproof Journal, so the same
    /// result cannot be filed twice by pressing the button again.
    @State private var journalMessage: String?
    /// True when the last pass ran with no rubric, so the result can say the marking was its own.
    @State private var markedWithoutGuidelines = false

    private var availability: MarkingAvailability { MarkingService.availability }

    private var guidelinesAreEmpty: Bool {
        guidelines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAnswer: Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !answerImages.isEmpty
    }

    private var canMark: Bool {
        MarkingService.isReady
            && !isMarking
            && hasAnswer
            && (Int(totalMarks) ?? 0) > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(
                    eyebrow: "AI Marking",
                    title: "Mark a Past Paper",
                    subtitle: "Add your work — typed, or as photos, scans or PDFs of the pages. Handwritten work is marked from the page images themselves, so a clear photo of your iPad export is enough. Guidelines are optional: attach a rubric for strict marking, or leave it out and the model solves each question itself."
                )

                availabilityCard
                MarkingSettingsCard(isExpanded: $settingsExpanded, preference: $marker)

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
            allowedContentTypes: [.png, .jpeg, .pdf, .heic],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result, into: .guidelines)
        }
        .fileImporter(
            isPresented: $isImportingAnswer,
            allowedContentTypes: [.png, .jpeg, .pdf, .heic],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result, into: .answer)
        }
        .onChange(of: marker) { _, newValue in
            // Persisted here rather than in the settings card, which may be collapsed.
            MarkingPreferences.preference = newValue
        }
    }

    private enum ImportTarget: Equatable { case guidelines, answer }

    // MARK: - Availability

    /// The marker label shown while a paper is about to be sent.
    private var activeMarker: MarkingBackendKind {
        switch marker {
        case .onDevice: return .onDevice
        case .openRouter: return .openRouter
        case .automatic: return availability.isAvailable ? .onDevice : .openRouter
        }
    }

    private var availabilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: MarkingService.isReady ? activeMarker.symbol : "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MarkingService.isReady ? Color.studyGreen : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(MarkingService.isReady
                     ? "\(activeMarker.label) is ready to mark"
                     : "Marking is not ready")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(MarkingService.readinessNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Pill(
                text: MarkingService.isReady ? activeMarker.label.uppercased() : "NO MARKER",
                color: MarkingService.isReady ? .studyTeal : .studyAmber,
                icon: MarkingService.isReady ? "sparkles" : "exclamationmark"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
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
                    Label("Add photos / scan / PDF", systemImage: "paperclip")
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
                        Text("Type your answers, or attach photos, scans or PDFs of the pages. Handwriting is read from the images, so attach even when there is no text — a PDF exported from an iPad works page by page.")
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
                    Label("Add photos / scan / PDF", systemImage: "paperclip")
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

            if !answerImages.isEmpty {
                HStack(spacing: 8) {
                    Pill(
                        text: "\(answerImages.count) page\(answerImages.count == 1 ? "" : "s") attached to read · \(totalImageSize)",
                        color: .studyViolet,
                        icon: "photo.on.rectangle"
                    )
                    Button("Remove scans") { answerImages.removeAll() }
                        .buttonStyle(.bentoBordered)
                        .bentoTint(.white)
                        .font(.system(size: 9, weight: .semibold))
                }
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
                // The marker is a per-paper decision as much as a setting, so it sits right
                // beside the button that sends the paper.
                BentoMenu(
                    selection: $marker,
                    options: MarkingBackendPreference.allCases.map {
                        BentoOption($0.title, value: $0, subtitle: $0.summary,
                                   symbol: $0 == .onDevice ? "lock.shield" : ($0 == .openRouter ? "cloud" : "wand.and.stars"))
                    },
                    width: 168
                )
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
                if let resultBackend {
                    Pill(
                        text: resultBackend.label.uppercased(),
                        color: resultBackend == .onDevice ? .studyTeal : .studyViolet,
                        icon: resultBackend.symbol
                    )
                }
                Button("Mark again") {
                    self.result = nil
                    resultBackend = nil
                    resultDetail = nil
                    journalMessage = nil
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.white)
            }

            if let resultDetail {
                Text(resultDetail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
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

            journalRow(result)

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

    /// Every question that lost marks becomes a journal entry, described with the marker's
    /// own reason. The fix is left for the student, because the rule to remember is theirs.
    private func journalRow(_ result: MarkingResult) -> some View {
        let dropped = result.questions.filter { $0.awarded < $0.outOf }
        return HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.studyViolet)
            VStack(alignment: .leading, spacing: 2) {
                Text(dropped.isEmpty
                     ? "Full marks — nothing to journal"
                     : "\(dropped.count) dropped \(dropped.count == 1 ? "mark" : "marks") worth keeping")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(journalMessage ?? "File the dropped marks in the Bulletproof Journal so the same error is revised before the next paper.")
                    .font(.system(size: 9))
                    .foregroundStyle(journalMessage == nil ? Color.secondary : Color.studyGreen)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Send to Journal") { journal(result) }
                .buttonStyle(.bentoBordered)
                .bentoTint(.secondary)
                .font(.system(size: 10, weight: .semibold))
                .disabled(dropped.isEmpty || journalMessage != nil)
        }
        .padding(11)
        .background(Color.studyViolet.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.studyViolet.opacity(0.25), lineWidth: 1)
        )
    }

    /// The paper as it should read in the journal: the title the user typed, or the subject's
    /// name plus the date, so an entry is never just "Q4".
    private var paperTitleForJournal: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "\(subject.shortName) paper, \(Date().formatted(date: .abbreviated, time: .omitted))"
    }

    private func journal(_ result: MarkingResult) {
        var filed = 0
        for question in result.questions where question.awarded < question.outOf {
            let entry = MistakeEntry(
                subject: subject,
                mistake: "\(question.question): \(question.reason)",
                questionRef: question.question,
                marksLost: question.outOf - question.awarded,
                source: .aiMarked,
                sourceTitle: paperTitleForJournal
            )
            if store.addMistake(entry) != nil { filed += 1 }
        }
        journalMessage = filed == 0
            ? "Nothing could be saved."
            : "Filed \(filed) \(filed == 1 ? "entry" : "entries") — open the Journal tab to add the fixes."
    }

    // MARK: - Actions

    /// Total payload the scans will add to the request, so a huge set of photos is visible
    /// before it is uploaded.
    private var totalImageSize: String {
        let megabytes = Double(answerImages.reduce(0) { $0 + $1.data.count }) / 1_048_576
        return megabytes < 1 ? String(format: "%.0f KB", megabytes * 1024) : String(format: "%.1f MB", megabytes)
    }

    private func mark() {
        errorMessage = nil
        savedMessage = nil
        journalMessage = nil
        resultBackend = nil
        resultDetail = nil
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
            comments: comments,
            answerImages: answerImages
        )
        markedWithoutGuidelines = guidelinesAreEmpty
        isMarking = true
        Task {
            do {
                let outcome = try await MarkingService.run(request)
                await MainActor.run {
                    result = outcome.result
                    resultBackend = outcome.backend
                    resultDetail = outcome.detail
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
                var images: [MarkingImage] = []
                var imageOnlyFiles = 0
                for url in urls {
                    do {
                        // One pass reads the file: the text Vision can find and the pages
                        // themselves. Handwriting usually yields no text at all, so the
                        // page image is what actually gets marked.
                        let scanned = try await Task.detached(priority: .userInitiated) {
                            try PaperText.scan(url)
                        }.value
                        extracted.append((url.lastPathComponent, scanned.text))
                        if scanned.text.isEmpty, scanned.hasImages { imageOnlyFiles += 1 }
                        // Only the answer is worth sending as pictures: a rubric reads well
                        // as text, and photographs of it would only cost tokens.
                        if target == .answer { images.append(contentsOf: scanned.images) }
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    for (name, text) in extracted {
                        switch target {
                        case .guidelines:
                            guard !text.isEmpty else { continue }
                            guidelines += guidelines.isEmpty ? text : "\n\n\(text)"
                            if !guidelineFiles.contains(name) { guidelineFiles.append(name) }
                        case .answer:
                            // A handwritten page often has no text at all; the scan is the
                            // answer, so the file is still listed and marked.
                            if !text.isEmpty {
                                answer += answer.isEmpty ? text : "\n\n\(text)"
                            }
                            if !answerFiles.contains(name) { answerFiles.append(name) }
                        }
                    }
                    let remaining = PaperText.maximumPages - answerImages.count
                    if remaining > 0 {
                        answerImages.append(contentsOf: images.prefix(remaining))
                    }
                    let droppedPages = max(0, images.count - max(0, remaining))
                    var notes = failures
                    if imageOnlyFiles > 0 {
                        notes.append("Handwriting attached as \(imageOnlyFiles == 1 ? "a scan" : "scans") — the marker reads the page itself, not text.")
                    }
                    if droppedPages > 0 {
                        notes.append("\(droppedPages) page\(droppedPages == 1 ? "" : "s") beyond the \(PaperText.maximumPages)-page limit were not attached.")
                    }
                    importMessage = notes.isEmpty
                        ? (extracted.isEmpty ? "No readable text found in those files." : nil)
                        : notes.joined(separator: "\n")
                    isLoadingFiles = false
                }
            }
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }
}
