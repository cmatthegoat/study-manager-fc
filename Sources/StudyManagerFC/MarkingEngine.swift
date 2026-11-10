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
/// Scans ride along as images for cloud models that can read them; the on-device model uses
/// the text Vision extracted from the same files.
struct MarkingRequest {
    var subject: StudySubject
    var title: String
    var totalMarks: Int
    var answerText: String
    var guidelinesText: String
    var comments: String
    var answerImages: [MarkingImage] = []
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

    /// True when OpenRouter is usable: a key in the Keychain and a model chosen.
    static var openRouterReady: Bool {
        MarkingKeychain.hasKey && !MarkingPreferences.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a paper can be marked at all with the current preference and setup.
    static var isReady: Bool {
        switch MarkingPreferences.preference {
        case .automatic: availability.isAvailable || openRouterReady
        case .onDevice: availability.isAvailable
        case .openRouter: openRouterReady
        }
    }

    /// Why marking is not ready, phrased for the banner above the answer box.
    static var readinessNote: String {
        switch MarkingPreferences.preference {
        case .automatic:
            if availability.isAvailable { return "Apple Intelligence marks on this Mac. OpenRouter is the fallback if it cannot take a paper." }
            if openRouterReady { return "The on-device model is not available here, so papers are being marked through OpenRouter." }
            if case .unavailable(let reason) = availability { return reason }
            return "Automatic marking is unavailable right now."
        case .onDevice:
            if case .unavailable(let reason) = availability { return reason }
            return "Papers are marked on this Mac only. Nothing is sent to a server."
        case .openRouter:
            return openRouterReady
                ? "Every paper is sent to OpenRouter using your own key."
                : "Add an OpenRouter key and model in Marking Settings to mark through the cloud."
        }
    }

    /// Runs a marking pass with the chosen backend and reports which one answered.
    static func run(_ request: MarkingRequest) async throws -> MarkingOutcome {
        let answer = request.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty || !request.answerImages.isEmpty else { throw MarkingError.noAnswer }

        // Handwriting only exists in the page images, and Apple's on-device model is handed
        // text. So a paper with scans goes to a vision model when one is configured, and the
        // on-device marker is only used for it when there is a transcript to mark.
        let hasScans = !request.answerImages.isEmpty
        let scansNeedCloud = hasScans && openRouterReady

        switch MarkingPreferences.preference {
        case .openRouter:
            return try await runInCloud(request)
        case .onDevice:
            guard availability.isAvailable else {
                if case .unavailable(let reason) = availability { throw MarkingError.notEnabled(reason) }
                throw MarkingError.systemTooOld
            }
            if hasScans, answer.isEmpty {
                throw MarkingError.notEnabled("Handwriting can only be read by a vision model. Add an OpenRouter key and model in Marking Settings, or type the answers in yourself.")
            }
            return try await runOnDeviceOutcome(request, answer: answer, unreadScans: hasScans)
        case .automatic:
            if scansNeedCloud {
                return try await runInCloud(request)
            }
            if availability.isAvailable {
                do {
                    return try await runOnDeviceOutcome(request, answer: answer, unreadScans: hasScans)
                } catch {
                    // A paper too long for the on-device window is exactly the case the
                    // fallback exists for, so a configured OpenRouter takes it instead.
                    guard openRouterReady else { throw error }
                    return try await runInCloud(request)
                }
            }
            if hasScans, answer.isEmpty {
                throw MarkingError.notEnabled("Handwriting can only be read by a vision model. Add an OpenRouter key and model in Marking Settings, or type the answers in yourself.")
            }
            guard openRouterReady else {
                if case .unavailable(let reason) = availability { throw MarkingError.notEnabled(reason) }
                throw MarkingError.systemTooOld
            }
            return try await runInCloud(request)
        }
    }

    /// Kept for callers that only want the marks, such as the marking diagnostic.
    static func mark(_ request: MarkingRequest) async throws -> MarkingResult {
        try await run(request).result
    }

    private static func runOnDeviceOutcome(
        _ request: MarkingRequest,
        answer: String,
        unreadScans: Bool = false
    ) async throws -> MarkingOutcome {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let result = try await runOnDevice(request, answer: answer)
            return MarkingOutcome(
                result: result,
                backend: .onDevice,
                detail: unreadScans
                    ? "Marked on this Mac from the recognised text only — the on-device model cannot see the scans."
                    : "Marked on this Mac — no bytes left the machine."
            )
        }
        #endif
        throw MarkingError.systemTooOld
    }

    private static func runInCloud(_ request: MarkingRequest) async throws -> MarkingOutcome {
        guard let key = MarkingKeychain.read(), !key.isEmpty else { throw OpenRouterError.missingKey }
        let model = MarkingPreferences.model
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.missingModel
        }
        return try await OpenRouterClient.mark(request, key: key, model: model)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func runOnDevice(_ request: MarkingRequest, answer: String) async throws -> MarkingResult {
        // A whole paper plus a rubric can outrun the on-device context, so both sides are
        // trimmed with a note rather than silently dropped.
        let limits = MarkingPrompts.Limits.onDevice
        let guidelines = MarkingPrompts.clipped(request.guidelinesText, limit: limits.guidelines)
        let comments = MarkingPrompts.clipped(request.comments, limit: limits.comments)
        let paper = MarkingPrompts.clipped(answer, limit: limits.paper)

        let instructions = MarkingPrompts.instructions(subject: request.subject)
        let prompt = MarkingPrompts.userPrompt(request, guidelines: guidelines, comments: comments, paper: paper)

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
