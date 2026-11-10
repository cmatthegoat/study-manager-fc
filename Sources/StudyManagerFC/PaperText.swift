import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

/// Turns a scanned past paper, a photo of handwritten work or a PDF of marking guidelines
/// into text the on-device model can read. The model itself never sees an image: images and
/// image-only PDFs are recognised here first.
enum PaperText {
    /// Extensions offered in the file picker. HEIC is what an iPad exports photos as.
    static let allowedContentTypes: [String] = ["png", "jpg", "jpeg", "heic", "pdf"]

    /// A file read for marking: the text Vision could find, which for handwriting is often
    /// nothing at all, and the pages as images a vision model can read directly.
    struct ScannedPaper {
        var text: String
        var images: [MarkingImage]

        /// True when the file carried its own text (a typed PDF), so OCR was not the only source.
        var hasPrintedText: Bool { !text.isEmpty }
        var hasImages: Bool { !images.isEmpty }
    }

    /// Images kept for one paper. Six pages covers a whole handwritten past paper, and the
    /// cloud marker is told the work may continue past them.
    static let maximumPages = 6

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

    /// The longest edge kept when a scan is sent to a cloud model. Larger than this costs
    /// tokens without helping it read handwriting, which is legible long before 1600px.
    private static let maximumImageEdge = 1_600

    /// Re-encodes a PNG or JPEG as a compact JPEG payload for a cloud marker. PDFs return
    /// nil: their text is extracted instead, and a rasterised page would cost far more.
    static func isImage(_ url: URL) -> Bool {
        allowedContentTypes.contains(url.pathExtension.lowercased()) && url.pathExtension.lowercased() != "pdf"
    }

    /// Reads a file of handwritten work: the images, because that is what the writing is, plus
    /// any text Vision managed. Nothing is thrown when OCR finds nothing, as long as there is
    /// a page to look at — a photo of handwriting is the normal case, not a failure.
    static func scan(_ url: URL, pageLimit: Int = maximumPages) throws -> ScannedPaper {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url) else {
                throw ReadError.emptyDocument(url.lastPathComponent)
            }
            var text: [String] = []
            var images: [MarkingImage] = []
            for index in 0..<min(document.pageCount, pageLimit) {
                guard let page = document.page(at: index) else { continue }
                let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if embedded.count > 40 { text.append(embedded) }
                // Every page is rendered, even one with a text layer: a typed page still
                // sometimes carries handwritten working beside it.
                let thumbnail = page.thumbnail(of: CGSize(width: 2_000, height: 2_600), for: .mediaBox)
                if let payload = jpegPayload(from: thumbnail) { images.append(payload) }
            }
            guard !text.isEmpty || !images.isEmpty else {
                throw ReadError.emptyDocument(url.lastPathComponent)
            }
            return ScannedPaper(
                text: text.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines),
                images: images
            )
        case "png", "jpg", "jpeg", "heic":
            guard let image = NSImage(contentsOf: url) else {
                throw ReadError.emptyDocument(url.lastPathComponent)
            }
            let recognised: String
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                recognised = ((try? recogniseText(in: cgImage)) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                recognised = ""
            }
            guard let payload = imagePayload(from: url) else {
                throw ReadError.emptyDocument(url.lastPathComponent)
            }
            return ScannedPaper(text: recognised, images: [payload])
        default:
            throw ReadError.unsupportedType(url.pathExtension)
        }
    }

    /// JPEGs an `NSImage` page for the cloud marker, shrinking it to the same ceiling a photo
    /// gets so a scanned PDF costs no more than a photograph of the same page.
    private static func jpegPayload(from image: NSImage) -> MarkingImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var scaled = cgImage
        if max(cgImage.width, cgImage.height) > maximumImageEdge,
           let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]),
           let source = CGImageSourceCreateWithData(png as CFData, nil),
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceThumbnailMaxPixelSize: maximumImageEdge,
               kCGImageSourceCreateThumbnailWithTransform: true
           ] as CFDictionary) {
            scaled = thumbnail
        }
        let representation = NSBitmapImageRep(cgImage: scaled)
        guard let data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return MarkingImage(data: data, mimeType: "image/jpeg")
    }

    static func imagePayload(from url: URL) -> MarkingImage? {
        guard isImage(url) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumImageEdge,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let representation = NSBitmapImageRep(cgImage: thumbnail)
        guard let data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return MarkingImage(data: data, mimeType: "image/jpeg")
    }

    static func text(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        switch url.pathExtension.lowercased() {
        case "pdf":
            return try pdfText(from: url)
        case "png", "jpg", "jpeg", "heic":
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
