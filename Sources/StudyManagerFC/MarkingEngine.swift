import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// One marked question inside a result.
struct MarkedQuestion: Identifiable, Codable, Hashable {
    var id = UUID()
    var question: String
    var awarded: Int
    var outOf: Int
    var reason: String

    enum CodingKeys: String, CodingKey {
        case question, awarded, outOf, reason
    }
}

/// What the marker judged, plus the arithmetic the UI and the assessment form need.
struct MarkingResult: Hashable {
    var questions: [MarkedQuestion]
    var feedback: String

    var totalAwarded: Int { questions.reduce(0) { $0 + $1.awarded } }
    var totalOutOf: Int { questions.reduce(0) { $0 + $1.outOf } }
    var percentage: Int? {
        guard totalOutOf > 0 else { return nil }
        return Int((Double(totalAwarded) / Double(totalOutOf) * 100).rounded())
    }
}

/// Everything a marking pass needs: what was set, what the student wrote, and the rubric.
struct MarkingRequest {
    var subject: StudySubject
    var title: String
    var totalMarks: Int
    var answerText: String
    var guidelinesText: String
    var comments: String
}

enum MarkingError: LocalizedError {
    case systemTooOld
    case notEnabled(String)
    case noAnswer
    case unreadableOutput
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .systemTooOld:
            "Automatic marking needs macOS 26 or later on an Apple silicon Mac."
        case .notEnabled(let reason):
            reason
        case .noAnswer:
            "Add your answer — typed, or as a PNG, JPEG or PDF — before marking."
        case .unreadableOutput:
            "The model's reply could not be read as marks. Try again, or mark this one yourself."
        case .failed(let message):
            message
        }
    }
}

/// Whether the on-device model can run at all, and why not when it can't.
enum MarkingAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
}

/// Marks past papers with Apple's on-device model. Nothing leaves the Mac: the model runs
/// locally, so no API key, no account and no cost per paper.
enum MarkingService {
    static var availability: MarkingAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                switch model.availability {
                case .unavailable(.deviceNotEligible):
                    return .unavailable("This Mac is not eligible for Apple Intelligence, so papers have to be marked by hand here.")
                case .unavailable(.appleIntelligenceNotEnabled):
                    return .unavailable("Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri to mark papers automatically.")
                case .unavailable(.modelNotReady):
                    return .unavailable("The on-device model is still downloading. Try again in a few minutes.")
                default:
                    return .unavailable("Automatic marking is unavailable right now.")
                }
            }
            return .available
        }
        return .unavailable("Automatic marking needs macOS 26 or later. On this Mac, keep marking by hand.")
        #else
        return .unavailable("This build was made without the Foundation Models framework, so papers have to be marked by hand.")
        #endif
    }

    static func mark(_ request: MarkingRequest) async throws -> MarkingResult {
        guard availability.isAvailable else {
            if case .unavailable(let reason) = availability { throw MarkingError.notEnabled(reason) }
            throw MarkingError.systemTooOld
        }
        let answer = request.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw MarkingError.noAnswer }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await runOnDevice(request, answer: answer)
        }
        #endif
        throw MarkingError.systemTooOld
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func runOnDevice(_ request: MarkingRequest, answer: String) async throws -> MarkingResult {
        // A whole paper plus a rubric can outrun the on-device context, so both sides are
        // trimmed with a note rather than silently dropped.
        let guidelines = clipped(request.guidelinesText, limit: 6_000)
        let comments = clipped(request.comments, limit: 1_500)
        let paper = clipped(answer, limit: 7_000)

        let instructions = """
        You are a strict but fair marker for an Australian NSW HSC paper in \(request.subject.displayName). \
        Mark only against the marking guidelines and comments when they are provided, and never invent criteria. \
        When no guidelines are supplied, work out the correct answer or method yourself and mark the work \
        against it: a correct answer with working earns every mark for that question, and sound working \
        still earns method marks when the final answer is wrong. Do not dock a fully correct answer. \
        Award whole marks only. Partial credit is allowed when part of the working is right.

        Reply with JSON only, in exactly this shape, with no prose before or after it:
        {"questions":[{"question":"Q1(a)","awarded":2,"outOf":3,"reason":"one sentence"}],"feedback":"two sentences of overall feedback"}
        """

        let prompt = """
        Total marks for this paper: \(request.totalMarks).

        MARKING GUIDELINES
        \(guidelines.isEmpty ? "(none supplied — solve each question yourself and mark my work against the correct answer)" : guidelines)

        MARKER'S COMMENTS
        \(comments.isEmpty ? "(none)" : comments)

        STUDENT'S ANSWER
        \(paper)

        Mark every question you can see in the answer. "outOf" is the marks available for that \
        question, taken from the guidelines when they state it. The outOf values must sum to \
        exactly \(request.totalMarks): if the guidelines do not give a share per question, divide \
        the total across the questions you found. Keep each reason to one sentence. When there are \
        no guidelines, put the correct answer in the reason so I can check your marking.
        """

        let session = LanguageModelSession(instructions: instructions)
        let response: String
        do {
            response = try await session.respond(to: prompt).content
        } catch {
            throw MarkingError.failed("The on-device model could not mark this paper: \(error.localizedDescription)")
        }
        return try parse(response)
    }
    #endif

    private static func clipped(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "\n…(truncated)"
    }

    // MARK: - Parsing

    private struct RawResult: Decodable {
        struct RawQuestion: Decodable {
            let question: String?
            let label: String?
            let awarded: Int?
            let outOf: Int?
            let out_of: Int?
            let reason: String?
        }
        let questions: [RawQuestion]?
        let feedback: String?
    }

    /// The model is asked for bare JSON, but it sometimes wraps it in a code fence or adds a
    /// sentence, so the first object in the reply is extracted and decoded on its own.
    static func parse(_ reply: String) throws -> MarkingResult {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"),
              start < end else {
            throw MarkingError.unreadableOutput
        }
        let json = String(reply[start...end])
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawResult.self, from: data) else {
            throw MarkingError.unreadableOutput
        }
        let questions: [MarkedQuestion] = (raw.questions ?? []).compactMap { item in
            let available = item.outOf ?? item.out_of ?? 0
            guard available > 0 else { return nil }
            let awarded = min(max(0, item.awarded ?? 0), available)
            let label = item.question ?? item.label ?? "Question"
            return MarkedQuestion(
                question: label,
                awarded: awarded,
                outOf: available,
                reason: (item.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !questions.isEmpty else { throw MarkingError.unreadableOutput }
        return MarkingResult(
            questions: questions,
            feedback: (raw.feedback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
