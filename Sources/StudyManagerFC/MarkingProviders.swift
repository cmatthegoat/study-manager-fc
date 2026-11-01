import Foundation
import Security

// MARK: - Preference

/// A scan of the working, ready to be posted as a data URL. Only OpenRouter receives these:
/// the on-device model is handed the text Vision recognised instead.
struct MarkingImage: Hashable {
    var data: Data
    var mimeType: String

    var sizeDescription: String {
        let kilobytes = Double(data.count) / 1024
        return kilobytes < 1_000
            ? "\(Int(kilobytes.rounded())) KB"
            : String(format: "%.1f MB", kilobytes / 1024)
    }
}

/// Which marker the app should use. The default is automatic: the on-device model first,
/// because it costs nothing and nothing leaves the Mac, and OpenRouter only when the
/// on-device model cannot take the paper at all.
enum MarkingBackendPreference: String, CaseIterable, Identifiable {
    case automatic
    case onDevice
    case openRouter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .onDevice: "On-device only"
        case .openRouter: "OpenRouter"
        }
    }

    var summary: String {
        switch self {
        case .automatic:
            "Apple Intelligence first. OpenRouter is used only when the on-device model cannot mark the paper."
        case .onDevice:
            "Nothing ever leaves this Mac. A paper the on-device model cannot read is marked by hand."
        case .openRouter:
            "Every paper goes to OpenRouter, even when Apple Intelligence is ready."
        }
    }
}

/// The marker that actually produced a result, so the result can say where the marks came from.
enum MarkingBackendKind: String {
    case onDevice
    case openRouter

    var label: String {
        switch self {
        case .onDevice: "Apple Intelligence"
        case .openRouter: "OpenRouter"
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: "lock.shield.fill"
        case .openRouter: "cloud.fill"
        }
    }
}

/// A marked paper plus the provenance the result card shows.
struct MarkingOutcome: Hashable {
    var result: MarkingResult
    var backend: MarkingBackendKind
    /// A short human note: where the marks came from, or the token count of the pass.
    var detail: String
}

/// The chosen backend and model. Kept in UserDefaults because it is a property of this Mac,
/// not of the career. The API key is deliberately not here — see `MarkingKeychain`.
enum MarkingPreferences {
    private static let preferenceKey = "marking.backendPreference"
    private static let modelKey = "marking.openRouterModel"

    static var preference: MarkingBackendPreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: preferenceKey),
                  let value = MarkingBackendPreference(rawValue: raw) else { return .automatic }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey) }
    }

    /// The OpenRouter model slug, e.g. `google/gemini-2.5-flash`. Empty until one is chosen.
    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }
}

// MARK: - Keychain

/// The OpenRouter key sits in the login Keychain, never in a plist, the career file or the
/// repository, and it is never printed or logged.
enum MarkingKeychain {
    private static let service = "com.cmatthegoat.study-manager-fc"
    private static let account = "openrouter-api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static var hasKey: Bool {
        read()?.isEmpty == false
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// Stores a pasted key after trimming it. An empty string deletes the stored key, so
    /// clearing the field is a real way to remove it.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return false
        }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - Models

/// One model in OpenRouter's catalogue. Only the fields this app needs are decoded.
struct OpenRouterModel: Identifiable, Decodable, Hashable {
    struct Architecture: Decodable, Hashable {
        let inputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case inputModalities = "input_modalities"
        }
    }

    let id: String
    let name: String?
    let architecture: Architecture?

    /// True for models that accept images, which is what a scanned paper needs.
    var supportsImages: Bool {
        (architecture?.inputModalities ?? []).contains("image")
    }

    var displayName: String {
        name?.isEmpty == false ? name! : id
    }
}

// MARK: - Errors

enum OpenRouterError: LocalizedError {
    case missingKey
    case missingModel
    case badStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your OpenRouter API key in Marking Settings before marking with it."
        case .missingModel:
            "Choose an OpenRouter model in Marking Settings before marking with it."
        case .badStatus(let status, let message):
            OpenRouterError.message(forStatus: status, server: message)
        }
    }

    /// Plain-language text for the statuses that actually come up, so a failure explains
    /// itself instead of showing a raw HTTP code.
    static func message(forStatus status: Int, server: String) -> String {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case 401, 403:
            return "OpenRouter rejected that API key. Re-enter it in Marking Settings."
        case 402:
            return "This OpenRouter key is out of credit. Top up the account or switch back to on-device marking."
        case 404:
            return "OpenRouter does not have that model any more. Pick another one in Marking Settings."
        case 408, 504:
            return "OpenRouter timed out marking this paper. Try again, or mark it in two halves."
        case 429:
            return "OpenRouter is rate-limiting this key. Wait a moment and mark the paper again."
        case 500...599:
            return "OpenRouter had a server error\(trimmed.isEmpty ? "" : ": \(trimmed)"). Try again shortly."
        default:
            return "OpenRouter could not mark the paper (HTTP \(status))\(trimmed.isEmpty ? "." : ": \(trimmed)")"
        }
    }
}

// MARK: - Prompts

/// The wording both markers receive. Kept in one place so a paper marked on-device and a
/// paper marked in the cloud are asked for exactly the same thing.
enum MarkingPrompts {
    struct Limits {
        var guidelines: Int
        var comments: Int
        var paper: Int

        /// The on-device model has a small window, so a whole paper plus a rubric has to be
        /// trimmed before it is sent.
        static let onDevice = Limits(guidelines: 6_000, comments: 1_500, paper: 7_000)
        /// A cloud model takes the whole thing, with a ceiling that keeps one pass cheap.
        static let cloud = Limits(guidelines: 14_000, comments: 2_000, paper: 24_000)
    }

    static func instructions(subject: StudySubject) -> String {
        """
        You are a strict but fair marker for an Australian NSW HSC paper in \(subject.displayName). \
        Mark only against the marking guidelines and comments when they are provided, and never invent criteria. \
        When no guidelines are supplied, work out the correct answer or method yourself and mark the work \
        against it: a correct answer with working earns every mark for that question, and sound working \
        still earns method marks when the final answer is wrong. Do not dock a fully correct answer. \
        Award whole marks only. Partial credit is allowed when part of the working is right.

        Reply with JSON only, in exactly this shape, with no prose before or after it:
        {"questions":[{"question":"Q1(a)","awarded":2,"outOf":3,"reason":"one sentence"}],"feedback":"two sentences of overall feedback"}
        """
    }

    static func userPrompt(
        _ request: MarkingRequest,
        guidelines: String,
        comments: String,
        paper: String
    ) -> String {
        """
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
    }

    static func clipped(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "\n…(truncated)"
    }
}

// MARK: - Client

/// Marks a paper through OpenRouter's OpenAI-compatible API. The key arrives as a parameter
/// so this type never reads the Keychain itself, which keeps it testable and keeps the key
/// out of anything that gets logged.
enum OpenRouterClient {
    static let completionsURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

    /// Builds the exact JSON body sent to OpenRouter: the same instructions and prompt the
    /// on-device model gets, the JSON response format, and any scans as base64 data URLs.
    static func requestBody(_ request: MarkingRequest, model: String) throws -> [String: Any] {
        let slug = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { throw OpenRouterError.missingModel }

        let limits = MarkingPrompts.Limits.cloud
        let guidelines = MarkingPrompts.clipped(request.guidelinesText, limit: limits.guidelines)
        let comments = MarkingPrompts.clipped(request.comments, limit: limits.comments)
        let paper = MarkingPrompts.clipped(request.answerText, limit: limits.paper)

        var parts: [[String: Any]] = [
            [
                "type": "text",
                "text": MarkingPrompts.userPrompt(request, guidelines: guidelines, comments: comments, paper: paper)
            ]
        ]
        // The docs ask for the text first and the images after it in the same message.
        for image in request.answerImages.prefix(6) {
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"]
            ])
        }

        return [
            "model": slug,
            "temperature": 0,
            "max_tokens": 2_000,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": MarkingPrompts.instructions(subject: request.subject)],
                ["role": "user", "content": parts]
            ]
        ]
    }

    /// Marks a paper, retrying once if OpenRouter rate-limits the key.
    static func mark(_ request: MarkingRequest, key: String, model: String) async throws -> MarkingOutcome {
        let body = try requestBody(request, model: model)
        do {
            return try await send(body, key: key)
        } catch OpenRouterError.badStatus(429, _) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return try await send(body, key: key)
        }
    }

    private static func send(_ body: [String: Any], key: String) async throws -> MarkingOutcome {
        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // Attribution headers that OpenRouter uses for the app's own usage page.
        request.setValue("Study Manager FC", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/cmatthegoat/study-manager-fc", forHTTPHeaderField: "HTTP-Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MarkingError.failed("OpenRouter could not be reached: \(error.localizedDescription)")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OpenRouterError.badStatus(status, serverMessage(from: data))
        }
        guard let reply = decodeReply(from: data) else {
            throw MarkingError.unreadableOutput
        }
        let result = try MarkingService.parse(reply.content)
        return MarkingOutcome(result: result, backend: .openRouter, detail: reply.detail)
    }

    /// The catalogue, filtered to models that accept images. No key is needed for this call.
    static func models() async throws -> [OpenRouterModel] {
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OpenRouterError.badStatus(status, "")
        }
        let envelope = try JSONDecoder().decode(ModelEnvelope.self, from: data)
        return envelope.data
            .filter(\.supportsImages)
            .sorted { $0.id < $1.id }
    }

    private struct ModelEnvelope: Decodable {
        let data: [OpenRouterModel]
    }

    private struct ReplyEnvelope: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message?
            let finish_reason: String?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
        }
        let choices: [Choice]?
        let usage: Usage?
        let error: ErrorBody?

        struct ErrorBody: Decodable {
            let message: String?
            let code: Int?
        }
    }

    private static func decodeReply(from data: Data) -> (content: String, detail: String)? {
        guard let envelope = try? JSONDecoder().decode(ReplyEnvelope.self, from: data) else { return nil }
        guard let content = envelope.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var detail = "Marked in the cloud — this paper left your Mac."
        if let usage = envelope.usage,
           let prompt = usage.prompt_tokens,
           let completion = usage.completion_tokens {
            detail = "\(prompt.formatted()) prompt tokens, \(completion.formatted()) reply tokens."
        }
        return (content, detail)
    }

    /// Pulls the provider's own sentence out of a failed response, so a 402 reads like an
    /// explanation instead of a status code.
    private static func serverMessage(from data: Data) -> String {
        guard let envelope = try? JSONDecoder().decode(ReplyEnvelope.self, from: data),
              let message = envelope.error?.message else { return "" }
        return message
    }
}
