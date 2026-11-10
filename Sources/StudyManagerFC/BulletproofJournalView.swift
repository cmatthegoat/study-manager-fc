import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Bulletproof Journal: every mistake worth never repeating, either written up by hand or
/// pulled straight out of an AI marking pass, with an optional photo of the working. The
/// point is the summary at the top — which topics keep biting — and the revision count on
/// each entry, so the list is worked through rather than just collected.
struct BulletproofJournalView: View {
    @Environment(AppStore.self) private var store

    @State private var isAdding = false
    @State private var editing: MistakeEntry?
    @State private var filterSubject: StudySubject?
    @State private var status: StatusFilter = .open
    @State private var search = ""

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case open
        case resolved
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: "Open"
            case .resolved: "Beaten"
            case .all: "All"
            }
        }

        func matches(_ entry: MistakeEntry) -> Bool {
            switch self {
            case .open: !entry.isResolved
            case .resolved: entry.isResolved
            case .all: true
            }
        }
    }

    // MARK: - Derived data

    private var all: [MistakeEntry] { store.mistakes }

    private var openCount: Int { all.filter { !$0.isResolved }.count }
    private var resolvedCount: Int { all.filter(\.isResolved).count }

    private var filtered: [MistakeEntry] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.filter { entry in
            status.matches(entry)
                && (filterSubject == nil || entry.subject == filterSubject)
                && (needle.isEmpty || matches(entry, needle: needle))
        }
    }

    private func matches(_ entry: MistakeEntry, needle: String) -> Bool {
        let haystack = [
            entry.mistake,
            entry.fix,
            entry.questionRef,
            entry.subtopicName ?? "",
            entry.sourceTitle ?? "",
            entry.subject.displayName
        ].joined(separator: " ").lowercased()
        return haystack.contains(needle)
    }

    /// Open mistakes grouped by topic, biggest pile first. A topic sitting at two or more is
    /// a pattern rather than bad luck, which is what this card is for.
    private var repeats: [RepeatGroup] {
        var byKey: [String: RepeatGroup] = [:]
        for entry in all where !entry.isResolved {
            let topic = entry.subtopicName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (topic?.isEmpty == false ? topic! : "No topic set")
            let key = "\(entry.subject.rawValue)|\(label)"
            if var group = byKey[key] {
                group.count += 1
                group.marksLost += entry.marksLost ?? 0
                group.entries.append(entry)
                byKey[key] = group
            } else {
                byKey[key] = RepeatGroup(
                    subject: entry.subject,
                    topic: label,
                    count: 1,
                    marksLost: entry.marksLost ?? 0,
                    entries: [entry]
                )
            }
        }
        return byKey.values.sorted {
            $0.count == $1.count ? $0.topic < $1.topic : $0.count > $1.count
        }
    }

    private var unrevised: [MistakeEntry] {
        all.filter { !$0.isResolved && $0.reviewCount == 0 }
    }

    /// The spaced-review queue: entries whose 1/3/7/30-day retest has come round. Two
    /// answers, and the entry climbs the ladder or drops back to the bottom.
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Due for review",
                subtitle: "\(store.dueMistakeReviews.count) waiting — get them right to space them further apart",
                symbol: "arrow.triangle.2.circlepath"
            )
            ForEach(store.dueMistakeReviews.prefix(4)) { entry in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.mistake)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(2)
                        Text("\(entry.subject.shortName)\(entry.subtopicName.map { " · \($0)" } ?? "") · rung \(entry.stage + 1) of \(MistakeEntry.reviewIntervals.count)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Again") { store.reviewMistake(entry.id, recalled: false) }
                        .buttonStyle(.bentoBordered)
                        .bentoTint(.secondary)
                    Button("Got it") { store.reviewMistake(entry.id, recalled: true) }
                        .buttonStyle(.bentoProminent)
                        .bentoTint(.primary)
                }
                .padding(.vertical, 4)
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
    }

    private struct RepeatGroup: Identifiable {
        let subject: StudySubject
        let topic: String
        var count: Int
        var marksLost: Int
        var entries: [MistakeEntry]

        var id: String { "\(subject.rawValue)|\(topic)" }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(
                    eyebrow: "Bulletproof Journal",
                    title: "Mistakes Worth Keeping",
                    subtitle: "Every error you write up or the marker flags, kept in one place per subject. Revise each one until it stops coming back."
                )

                summaryCard
                if !store.dueMistakeReviews.isEmpty { reviewCard }
                if !repeats.isEmpty { repeatsCard }

                if isAdding {
                    MistakeEditorCard(
                        existing: nil,
                        onSave: { entry in
                            store.addMistake(entry)
                            isAdding = false
                        },
                        onCancel: { isAdding = false }
                    )
                } else {
                    addPrompt
                }

                filtersCard
                listCard
            }
            .padding(28)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { entry in
            MistakeEditorCard(
                existing: entry,
                onSave: { updated in
                    store.updateMistake(updated)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
            .frame(width: 620)
            .padding(24)
            .background(AppBackground(paletteKey: store.paletteKey))
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Where You Stand",
                subtitle: "A mistake you have written down and revised is a mark you get back",
                symbol: "shield.lefthalf.filled"
            )
            HStack(spacing: 14) {
                MetricTile(
                    title: "Open",
                    value: "\(openCount)",
                    subtitle: "not yet beaten",
                    symbol: "exclamationmark.triangle.fill",
                    tint: .studyAmber
                )
                MetricTile(
                    title: "Beaten",
                    value: "\(resolvedCount)",
                    subtitle: "closed for good",
                    symbol: "checkmark.seal.fill",
                    tint: .studyGreen
                )
                MetricTile(
                    title: "Unrevised",
                    value: "\(unrevised.count)",
                    subtitle: "never re-read",
                    symbol: "book.closed.fill",
                    tint: .studyViolet
                )
                MetricTile(
                    title: "Repeats",
                    value: "\(repeats.filter { $0.count > 1 }.count)",
                    subtitle: "topics hit twice or more",
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .studyTeal
                )
            }

            if let worst = repeats.first, worst.count > 1 {
                Label(
                    "\(worst.topic) in \(worst.subject.shortName) accounts for \(worst.count) of your open mistakes. Take that topic into the next focus session and mark it beaten.",
                    systemImage: "scope"
                )
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            } else if all.isEmpty {
                Text("Nothing logged yet. Any mistake you make — in a past paper, a homework set or an AI-marked paper — belongs here rather than in your head.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private var repeatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Repeated Errors",
                subtitle: "Same topic twice or more, most frequent first",
                symbol: "repeat"
            )
            VStack(spacing: 0) {
                ForEach(repeats.prefix(8)) { group in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(SubjectTheme.color(for: group.subject))
                            .frame(width: 8, height: 8)
                            .shadow(color: SubjectTheme.color(for: group.subject).opacity(0.7), radius: 5)
                        Text(group.topic)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Pill(text: group.subject.shortName, color: SubjectTheme.color(for: group.subject))
                        Spacer(minLength: 0)
                        if group.marksLost > 0 {
                            Text("\(group.marksLost) marks")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text("\(group.count)×")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(group.count > 1 ? Color.studyAmber : Color.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    if group.id != repeats.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    // MARK: - Add

    private var addPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Neon.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Log a mistake")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Describe what went wrong and the rule that fixes it — attach a photo of the working if that is quicker.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isAdding = true
            } label: {
                Label("New Entry", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.bentoProminent)
            .bentoTint(.primary)
        }
        .surface(padding: 16)
    }

    // MARK: - Filters

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Find an Entry", subtitle: "\(filtered.count) shown", symbol: "line.3.horizontal.decrease.circle")
            HStack(spacing: 10) {
                BentoMenu(
                    selection: $filterSubject,
                    options: [BentoOption("All subjects", value: StudySubject?.none)]
                        + StudySubject.allCases.map { BentoOption($0.shortName, value: StudySubject?.some($0)) },
                    width: 170
                )
                Picker("Status", selection: $status) {
                    ForEach(StatusFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                TextField("Search mistakes, fixes or topics", text: $search)
                    .bentoField()
                    .frame(maxWidth: 320)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 16)
    }

    // MARK: - List

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Journal", subtitle: "Newest first", symbol: "list.bullet.rectangle")
            if filtered.isEmpty {
                EmptyStateView(
                    symbol: "shield.checkerboard",
                    title: all.isEmpty ? "No mistakes logged" : "Nothing matches",
                    message: all.isEmpty
                        ? "Mark a paper with AI Marking and every dropped mark can be sent straight here, or write an entry up yourself."
                        : "Widen the subject or status filter, or clear the search."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(filtered) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
    }

    private func entryRow(_ entry: MistakeEntry) -> some View {
        let tint = SubjectTheme.color(for: entry.subject)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .shadow(color: tint.opacity(0.7), radius: 5)
                Text(entry.subject.shortName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if let topic = entry.subtopicName, !topic.isEmpty {
                    Pill(text: topic, color: tint, icon: "tag")
                }
                if !entry.questionRef.isEmpty {
                    Pill(text: entry.questionRef, color: .studyTeal, icon: "number")
                }
                if let lost = entry.marksLost, lost > 0 {
                    Pill(text: "−\(lost)", color: .studyAmber, icon: "minus.circle")
                }
                if entry.isResolved {
                    Pill(text: "Beaten", color: .studyGreen, icon: "checkmark.seal")
                }
                Spacer(minLength: 0)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Text(entry.mistake)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if !entry.fix.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.studyGreen)
                        .padding(.top, 2)
                    Text(entry.fix)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Pill(
                    text: entry.source.title,
                    color: entry.source == .aiMarked ? .studyViolet : .studyMuted,
                    icon: entry.source.symbol
                )
                if let paper = entry.sourceTitle, !paper.isEmpty {
                    Text("from \(paper)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if entry.reviewCount > 0 {
                    Text("revised \(entry.reviewCount)×")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if !entry.isResolved {
                    Text("never revised")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.studyAmber)
                }
                Spacer(minLength: 0)
                if let attachment = entry.attachment {
                    Button("Open scan") {
                        NSWorkspace.shared.open(store.journalAttachmentURL(attachment))
                    }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.white)
                }
                Button("Revise") {
                    store.reviewMistake(entry.id)
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.secondary)
                Button(entry.isResolved ? "Reopen" : "Beaten") {
                    store.setMistakeResolved(entry.id, resolved: !entry.isResolved)
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(entry.isResolved ? .white : .primary)
                Button("Edit") { editing = entry }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.white)
                Button(role: .destructive) {
                    if let attachment = entry.attachment {
                        JournalImageCache.forget(attachment)
                    }
                    store.deleteMistake(entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.danger)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))

            if let attachment = entry.attachment, let image = attachmentPreview(attachment) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(entry.isResolved ? 0.025 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(tint.opacity(entry.isResolved ? 0.12 : 0.28), lineWidth: 1)
        )
    }

    private func attachmentPreview(_ name: String) -> NSImage? {
        JournalImageCache.image(named: name, at: store.journalAttachmentURL(name))
    }
}

/// Journal photos are read from disk once and kept in memory. Every redraw of the list — and
/// every keystroke in the editor, which redraws its preview — used to decode the PNG again.
enum JournalImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String, at url: URL) -> NSImage? {
        guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { return nil }
        let key = name as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Called when an entry is deleted or its scan replaced, so a stale picture is not shown.
    static func forget(_ name: String) {
        cache.removeObject(forKey: name as NSString)
    }
}

// MARK: - Editor

/// The one form used both to write a new entry and to edit an existing one, so a mistake
/// flagged by the marker can be corrected without retyping it.
private struct MistakeEditorCard: View {
    @Environment(AppStore.self) private var store

    let existing: MistakeEntry?
    let onSave: (MistakeEntry) -> Void
    let onCancel: () -> Void

    @State private var draft: MistakeEntry
    @State private var marksLostText: String
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var validationMessage: String?

    @State private var subject: StudySubject
    @State private var topicID: UUID?

    init(existing: MistakeEntry?, onSave: @escaping (MistakeEntry) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        let base = existing ?? MistakeEntry(subject: .ext1Maths, mistake: "")
        _draft = State(initialValue: base)
        _marksLostText = State(initialValue: base.marksLost.map(String.init) ?? "")
        _subject = State(initialValue: base.subject)
        _topicID = State(initialValue: base.subtopicID)
    }

    private var topics: [Subtopic] { store.subtopics(for: subject) }

    private var canSave: Bool {
        !draft.mistake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: existing == nil ? "New Journal Entry" : "Edit Entry",
                subtitle: "What went wrong, and the rule that stops it happening again",
                symbol: existing == nil ? "square.and.pencil" : "pencil.circle"
            )

            HStack(spacing: 10) {
                BentoMenu(
                    selection: $subject,
                    options: StudySubject.allCases.map { BentoOption($0.shortName, value: $0) },
                    width: 170
                )
                BentoMenu(
                    selection: $topicID,
                    options: [BentoOption("Whole subject", value: UUID?.none)]
                        + topics.map { BentoOption($0.name, value: UUID?.some($0.id)) },
                    width: 210
                )
                TextField("Question, e.g. Q4 or Trial 2024 Q2b", text: $draft.questionRef)
                    .bentoField()
                TextField("Marks lost", text: $marksLostText)
                    .bentoField()
                    .frame(width: 100)
            }
            .onChange(of: subject) { _, newValue in
                draft.subject = newValue
                // A topic belongs to one subject, so switching subject drops a stale pick.
                if let topicID, !store.subtopics(for: newValue).contains(where: { $0.id == topicID }) {
                    self.topicID = nil
                }
            }
            .onChange(of: topicID) { _, newValue in
                draft.subtopicID = newValue
                draft.subtopicName = store.subtopics(for: subject).first { $0.id == newValue }?.name
            }

            editorField(
                title: "The mistake",
                placeholder: "e.g. Integrated x² as x²/2 instead of x³/3 — forgot to raise the power first",
                text: $draft.mistake
            )
            editorField(
                title: "The fix",
                placeholder: "e.g. Always write the power rule out before integrating a polynomial",
                text: $draft.fix
            )

            HStack(spacing: 10) {
                Button {
                    isImporting = true
                } label: {
                    Label("Attach PNG / JPEG / PDF", systemImage: "paperclip")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bentoBordered)
                .bentoTint(.white)

                if let attachment = draft.attachment {
                    Pill(text: attachment, color: .studyTeal, icon: "doc.text")
                    Button("Remove") {
                        draft.attachment = nil
                    }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.white)
                    .font(.system(size: 10, weight: .semibold))
                }
                Spacer()
                if let importMessage {
                    Text(importMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let attachment = draft.attachment, let image = previewImage(attachment) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange)
            }

            HStack {
                if existing != nil {
                    Pill(text: existing?.source.title ?? "", color: .studyViolet, icon: existing?.source.symbol)
                } else {
                    Pill(text: MistakeSource.manual.title, color: .studyMuted, icon: MistakeSource.manual.symbol)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bentoBordered)
                    .bentoTint(.white)
                Button(existing == nil ? "Save Entry" : "Save Changes") { save() }
                    .buttonStyle(.bentoProminent)
                    .bentoTint(.primary)
                    .disabled(!canSave)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 18)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.png, .jpeg, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func editorField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 64)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func previewImage(_ name: String) -> NSImage? {
        JournalImageCache.image(named: name, at: store.journalAttachmentURL(name))
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                if let name = store.storeJournalAttachment(data: data, fileExtension: ext) {
                    draft.attachment = name
                    importMessage = "Attached \(url.lastPathComponent)"
                } else {
                    importMessage = "That file could not be copied into the journal."
                }
            } catch {
                importMessage = "Could not read that file: \(error.localizedDescription)"
            }
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }

    private func save() {
        guard canSave else {
            validationMessage = "Write down what went wrong before saving."
            return
        }
        var entry = draft
        entry.subject = subject
        entry.mistake = entry.mistake.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.fix = entry.fix.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.questionRef = entry.questionRef.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.marksLost = Int(marksLostText)
        onSave(entry)
    }
}
