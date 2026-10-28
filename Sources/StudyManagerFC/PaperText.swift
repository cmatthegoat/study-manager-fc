import AppKit
import Foundation
import PDFKit
import Vision

/// Turns a scanned past paper, a photo of handwritten work or a PDF of marking guidelines
/// into text the on-device model can read. The model itself never sees an image: images and
/// image-only PDFs are recognised here first.
enum PaperText {
    /// Extensions offered in the file picker: images and PDFs, as asked for.
    static let allowedContentTypes: [String] = ["png", "jpg", "jpeg", "pdf"]

    enum ReadError: LocalizedError {
        case unsupportedType(String)
        case emptyDocument(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext):
                "\(ext.uppercased()) files are not supported. Use a PNG, JPEG or PDF."
            case .emptyDocument(let name):
                "No readable text was found in \(name). Try a sharper scan or type the answer in."
            }
        }
    }

    static func text(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        switch url.pathExtension.lowercased() {
        case "pdf":
            return try pdfText(from: url)
        case "png", "jpg", "jpeg":
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ReadError.emptyDocument(url.lastPathComponent)
            }
            let text = try recogniseText(in: cgImage).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ReadError.emptyDocument(url.lastPathComponent) }
            return text
        default:
            throw ReadError.unsupportedType(url.pathExtension)
        }
    }

    /// PDFs that carry a text layer are read directly; scans fall back to OCR per page.
    private static func pdfText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ReadError.emptyDocument(url.lastPathComponent)
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if embedded.count > 40 {
                pages.append(embedded)
                continue
            }
            let image = page.thumbnail(of: CGSize(width: 2000, height: 2600), for: .mediaBox)
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let recognised = (try? recogniseText(in: cgImage)) ?? ""
                if !recognised.isEmpty { pages.append(recognised) }
            }
        }
        let text = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ReadError.emptyDocument(url.lastPathComponent) }
        return text
    }

    /// Vision's accurate recogniser, with language correction, which copes with printed
    /// text well and handwriting only as far as the scan is clean.
    private static func recogniseText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "en-GB"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
