import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The outcome of one check in a connection test.
enum MarkingCheckStatus: String, Codable, Hashable, CaseIterable {
    case passed
    case warning
    case failed
    case skipped

    var title: String {
        switch self {
        case .passed: "Passed"
        case .warning: "Check this"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }

    /// The tint used when this status is drawn in the app.
    var tint: Color {
        switch self {
        case .passed: .studyGreen
        case .warning: .studyAmber
        case .failed: .red
        case .skipped: .secondary
        }
    }

    /// The SF symbol best matching the status.
    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "circle"
        }
    }
}

/// A single line of the report: what was tested, whether it worked, and why.
struct MarkingCheck: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var status: MarkingCheckStatus
    var detail: String
}

/// The whole test, in a shape the app can render and a person can paste into a support
/// message. `verdict` is the worst status found, so one failure is never hidden by passes.
struct MarkingDiagnosticReport: Identifiable, Codable, Hashable {
    var id = UUID()
    var model: String
    var date: Date
    var seconds: Double
    var checks: [MarkingCheck]

    var verdict: MarkingCheckStatus {
        if checks.contains(where: { $0.status == .failed }) { return .failed }
        if checks.contains(where: { $0.status == .warning }) { return .warning }
        if checks.isEmpty || checks.allSatisfy({ $0.status == .skipped }) { return .skipped }
        return .passed
    }

    var headline: String {
        switch verdict {
        case .passed: "This key and model are ready to mark papers."
        case .warning: "Marking should work, with the caveats below."
        case .failed: "Not ready — fix the failures below before marking a paper."
        case .skipped: "Nothing was tested."
        }
    }

    var passedCount: Int { checks.filter { $0.status == .passed }.count }

    /// The report as JSON, for the clipboard or a bug report. Dates are ISO 8601 so it reads
    /// the same wherever it is pasted.
    func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// Tests whether a key and a model can actually mark a paper, rather than waiting for a real
/// past paper to fail. Every check answers a question the app cares about: is the key valid,
/// is there credit, is this model in the catalogue, can it read a scan, is its window big
/// enough, and does it return the exact JSON the marker expects.
enum MarkingDiagnostics {
    /// A whole paper plus its rubric is comfortably inside this many tokens.
    static let comfortableContext = 16_000
    /// Below this, a long paper will be cut off even after trimming.
    static let minimumContext = 8_000

    static func run(key: String, modelSlug: String) async -> MarkingDiagnosticReport {
        let started = Date()
        let slug = modelSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        var checks: [MarkingCheck] = []
        var keyAccepted = false
        var model: OpenRouterModel?

        // 1. Is there a key at all, and does it look like one?
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            checks.append(MarkingCheck(
                id: "key-present",
                title: "API key",
                status: .failed,
                detail: "No key is stored. Create one at openrouter.ai → Keys and paste it above."
            ))
        } else if trimmedKey.hasPrefix("sk-or-") {
            checks.append(MarkingCheck(
                id: "key-present",
                title: "API key",
                status: .passed,
                detail: "A key is stored and looks like an OpenRouter key."
            ))
        } else {
            checks.append(MarkingCheck(
                id: "key-present",
                title: "API key",
                status: .warning,
                detail: "A key is stored but does not start with sk-or-, which OpenRouter keys usually do."
            ))
        }

        // 2. Does OpenRouter accept it, and is there money on it?
        if !trimmedKey.isEmpty {
            do {
                let info = try await OpenRouterClient.keyInfo(key: trimmedKey)
                keyAccepted = true
                checks.append(keyCheck(info))
            } catch {
                checks.append(MarkingCheck(
                    id: "key-accepted",
                    title: "Key accepted",
                    status: .failed,
                    detail: error.localizedDescription
                ))
            }
        }

        // 3. Is the chosen model in the catalogue? A retired slug is the most common mistake
        // after a bad key, and it fails differently (404) than an auth problem.
        if !slug.isEmpty {
            do {
                let catalogue = try await OpenRouterClient.models()
                if let found = catalogue.first(where: { $0.id == slug }) {
                    model = found
                    checks.append(MarkingCheck(
                        id: "model-present",
                        title: "Model available",
                        status: .passed,
                        detail: "\(found.displayName) is listed by OpenRouter."
                    ))
                } else {
                    checks.append(MarkingCheck(
                        id: "model-present",
                        title: "Model available",
                        status: .failed,
                        detail: "OpenRouter does not list \"\(slug)\". Pick another model from the list above."
                    ))
                }
            } catch {
                checks.append(MarkingCheck(
                    id: "model-present",
                    title: "Model available",
                    status: .failed,
                    detail: "Could not read the model catalogue: \(error.localizedDescription)"
                ))
            }
        } else {
            checks.append(MarkingCheck(
                id: "model-present",
                title: "Model available",
                status: .failed,
                detail: "No model is chosen, so there is nothing to test."
            ))
        }

        // 4. Is it the right kind of model for a marked paper?
        if let model {
            checks.append(contentsOf: suitability(of: model))
        }

        // 5. A real pass: the marker must return JSON in the shape the app parses.
        var textProbeWorked = false
        if keyAccepted, model != nil {
            let probeStarted = Date()
            do {
                let outcome = try await OpenRouterClient.mark(textProbe(), key: trimmedKey, model: slug)
                let issues = contractIssues(in: outcome.result, expectedTotal: 1)
                let seconds = Date().timeIntervalSince(probeStarted)
                if issues.isEmpty {
                    textProbeWorked = true
            checks.append(MarkingCheck(
                id: "text-probe",
                title: "Marks a test question",
                status: .passed,
                detail: "Returned \(outcome.result.totalAwarded)/\(outcome.result.totalOutOf) with a reason in \(seconds). \(outcome.detail)"
            ))
                } else {
                    checks.append(MarkingCheck(
                        id: "text-probe",
                        title: "Marks a test question",
                        status: .warning,
                        detail: "Replied, but the marks were not quite in the expected shape: \(issues.joined(separator: "; "))."
                    ))
                }
            } catch {
                checks.append(MarkingCheck(
                    id: "text-probe",
                    title: "Marks a test question",
                    status: .failed,
                    detail: error.localizedDescription
                ))
            }
        } else {
            checks.append(MarkingCheck(
                id: "text-probe",
                title: "Marks a test question",
                status: .skipped,
                detail: "Needs a key OpenRouter accepts and a model that exists."
            ))
        }

        // 6. Scanned work: send a rendered page and see whether it can read it. Only worth
        // trying on a model that claims image input, and only after the text pass works.
        if let model, model.supportsImages, keyAccepted, textProbeWorked {
            do {
                guard let image = probeImage() else {
                    throw MarkingError.failed("The test page could not be drawn.")
                }
                let probeStarted = Date()
                let outcome = try await OpenRouterClient.mark(imageProbe(image), key: trimmedKey, model: slug)
                let issues = contractIssues(in: outcome.result, expectedTotal: 1)
                let seconds = Date().timeIntervalSince(probeStarted)
                if issues.isEmpty {
            checks.append(MarkingCheck(
                id: "image-probe",
                title: "Reads a scanned page",
                status: .passed,
                detail: "Read the rendered question and marked it without any typed text in \(seconds)."
            ))
                } else {
                checks.append(MarkingCheck(
                    id: "image-probe",
                    title: "Reads a scanned page",
                    status: .warning,
                    detail: "The image went through but the reply was off: \(issues.joined(separator: "; ")). Try typing the answer or attaching a PDF instead."
                ))
                }
            } catch {
                checks.append(MarkingCheck(
                    id: "image-probe",
                    title: "Reads a scanned page",
                    status: .warning,
                    detail: "A scan could not be marked by this model: \(error.localizedDescription). Typed answers and PDFs still work."
                ))
            }
        } else if let model, !model.supportsImages {
            checks.append(MarkingCheck(
                id: "image-probe",
                title: "Reads a scanned page",
                status: .skipped,
                detail: "This model does not accept images, so photos of handwritten work cannot be marked."
            ))
        } else {
            checks.append(MarkingCheck(
                id: "image-probe",
                title: "Reads a scanned page",
                status: .skipped,
                detail: "Not reached: the key or the text pass has to work first."
            ))
        }

        return MarkingDiagnosticReport(
            model: slug.isEmpty ? "(none chosen)" : slug,
            date: Date(),
            seconds: Date().timeIntervalSince(started),
            checks: checks
        )
    }

    // MARK: - Checks that need no network

    /// Whether a catalogue entry can realistically mark a past paper. Pure, so the rules are
    /// testable without spending a request.
    static func suitability(of model: OpenRouterModel) -> [MarkingCheck] {
        var checks: [MarkingCheck] = []

        checks.append(MarkingCheck(
            id: "output",
            title: "Writes text replies",
            status: model.writesText ? .passed : .failed,
            detail: model.writesText
                ? "Replies are text, which is what marks and reasons are read from."
                : "This model does not return text, so no marks could be read from it."
        ))

        let context = model.contextLength ?? 0
        let contextStatus: MarkingCheckStatus
        let contextDetail: String
        if context >= comfortableContext {
            contextStatus = .passed
            contextDetail = "\(context.formatted()) tokens of context — room for a whole paper and its rubric."
        } else if context >= minimumContext {
            contextStatus = .warning
            contextDetail = "Only \(context.formatted()) tokens of context. A long paper will be trimmed before it is marked."
        } else {
            contextStatus = .failed
            contextDetail = "Only \(context.formatted()) tokens of context, which is too small for a past paper."
        }
        checks.append(MarkingCheck(id: "context", title: "Large enough window", status: contextStatus, detail: contextDetail))

        checks.append(MarkingCheck(
            id: "images",
            title: "Accepts scanned pages",
            status: model.supportsImages ? .passed : .warning,
            detail: model.supportsImages
                ? "Photos and scans of handwritten work can be marked by this model."
                : "This model is text-only, so handwriting has to be typed or supplied as a PDF for local reading."
        ))

        if let prompt = model.promptCostPerMillion, let completion = model.completionCostPerMillion {
            let perPaper = estimatedCostPerPaper(promptPerMillion: prompt, completionPerMillion: completion)
            checks.append(MarkingCheck(
                id: "price",
                title: "Costs roughly known",
                status: perPaper > 0.50 ? .warning : .passed,
                detail: String(
                    format: "$%.2f per million in, $%.2f per million out — about %@ for a six-page paper.",
                    prompt,
                    completion,
                    formattedCost(perPaper)
                )
            ))
        } else {
            checks.append(MarkingCheck(
                id: "price",
                title: "Costs roughly known",
                status: .skipped,
                detail: "OpenRouter did not publish a price for this model, so the cost of a paper is unknown."
            ))
        }

        return checks
    }

    /// A six-page paper: roughly 9,000 input tokens of text plus one scan (~1,600), and 600
    /// tokens of replies. Deliberately a rough figure, quoted as "about".
    static func estimatedCostPerPaper(promptPerMillion: Double, completionPerMillion: Double) -> Double {
        let inputTokens = 10_600.0
        let outputTokens = 600.0
        return (inputTokens / 1_000_000) * promptPerMillion + (outputTokens / 1_000_000) * completionPerMillion
    }

    static func formattedCost(_ amount: Double) -> String {
        if amount < 0.01 { return String(format: "%.3f USD", amount) }
        return String(format: "%.2f USD", amount)
    }

    /// Everything the parser needs to trust a marking result. Returned as sentences so the
    /// report can quote them directly.
    static func contractIssues(in result: MarkingResult, expectedTotal: Int) -> [String] {
        var issues: [String] = []
        if result.questions.isEmpty {
            issues.append("no questions came back")
        }
        for question in result.questions {
            if question.outOf <= 0 {
                issues.append("\(question.question) had no marks available")
            }
            if question.awarded < 0 || question.awarded > question.outOf {
                issues.append("\(question.question) was awarded \(question.awarded) out of \(question.outOf)")
            }
            if question.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(question.question) came back without a reason")
            }
        }
        if result.totalOutOf != expectedTotal {
            issues.append("marks available summed to \(result.totalOutOf), not \(expectedTotal)")
        }
        if result.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("there was no overall feedback")
        }
        return issues
    }

    // MARK: - Probes

    /// One trivial question, so a pass costs a fraction of a cent.
    static func textProbe() -> MarkingRequest {
        MarkingRequest(
            subject: .other,
            title: "Connection test",
            totalMarks: 1,
            answerText: "Q1: 2 + 2 = 4",
            guidelinesText: "Q1 (1 mark): the correct answer is 4.",
            comments: ""
        )
    }

    /// The same question with no typed answer at all, so only the scan can carry it.
    static func imageProbe(_ image: MarkingImage) -> MarkingRequest {
        MarkingRequest(
            subject: .other,
            title: "Scan test",
            totalMarks: 1,
            answerText: "",
            guidelinesText: "Q1 (1 mark): the correct answer is 4.",
            comments: "",
            answerImages: [image]
        )
    }

    /// Draws a printed page with a one-mark question on it. Printed rather than handwritten
    /// on purpose: a model that cannot read clean print certainly cannot read a photo of a
    /// past paper, and this keeps the test about the connection rather than about Vision.
    /// CoreText is used rather than AppKit drawing so this is safe off the main thread.
    static func probeImage() -> MarkingImage? {
        let width = 900
        let height = 260
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica" as CFString, 34, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
        ]
        let text = NSAttributedString(
            string: "Q1 (1 mark): What is 2 + 2?\n\nMy answer: 2 + 2 = 4",
            attributes: attributes
        )
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(x: 30, y: 26, width: 840, height: 208), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return MarkingImage(data: data as Data, mimeType: "image/jpeg")
    }

    // MARK: - Key detail

    private static func keyCheck(_ info: OpenRouterKeyInfo) -> MarkingCheck {
        var notes: [String] = []
        if let remaining = info.limitRemaining {
            notes.append(String(format: "%.2f USD left on this key", remaining))
        } else {
            notes.append("no spending cap on this key")
        }
        if let usage = info.usage {
            notes.append(String(format: "%.2f USD used so far", usage))
        }
        if info.isFreeTier {
            notes.append("free tier: paid models will be refused until credit is added")
        }

        let detail = "OpenRouter accepted the key: " + notes.joined(separator: ", ") + "."
        let status: MarkingCheckStatus = info.hasPaidCredit ? (info.isFreeTier ? .warning : .passed) : .warning
        return MarkingCheck(id: "key-accepted", title: "Key accepted", status: status, detail: detail)
    }
}
