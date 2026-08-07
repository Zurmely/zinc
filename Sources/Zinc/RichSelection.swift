import AppKit
import UniformTypeIdentifiers

struct PasteboardImage {
    let data: Data
    let fileExtension: String
}

struct RichSelection {
    let plainText: String
    let html: String?
    let images: [PasteboardImage]

    var hasContent: Bool {
        !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || html != nil
            || !images.isEmpty
    }

    /// Plain text for the clip index; falls back when the pasteboard has only rich/image content.
    var clipText: String {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if html != nil {
            return "[Rich content]"
        }
        if !images.isEmpty {
            return "[Image]"
        }
        return ""
    }

    static func read(from pasteboard: NSPasteboard) -> RichSelection? {
        let plainText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let html = readHTML(from: pasteboard)
        let images = readImages(from: pasteboard)

        let selection = RichSelection(plainText: plainText, html: html, images: images)
        return selection.hasContent ? selection : nil
    }

    private static func readHTML(from pasteboard: NSPasteboard) -> String? {
        // Prefer raw bytes decoded as UTF-8 so we don't inherit a Latin-1 misread.
        if let data = pasteboard.data(forType: .html), !data.isEmpty,
           let html = decodeHTMLData(data), !html.isEmpty {
            return html
        }

        if let html = pasteboard.string(forType: .html), !html.isEmpty {
            return html
        }

        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           let htmlData = try? attributed.data(
               from: NSRange(location: 0, length: attributed.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
           ),
           let html = String(data: htmlData, encoding: .utf8),
           !html.isEmpty {
            return html
        }

        if let rtfdData = pasteboard.data(forType: .rtfd),
           let attributed = NSAttributedString(rtfd: rtfdData, documentAttributes: nil),
           let htmlData = try? attributed.data(
               from: NSRange(location: 0, length: attributed.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
           ),
           let html = String(data: htmlData, encoding: .utf8),
           !html.isEmpty {
            return html
        }

        return nil
    }

    private static func decodeHTMLData(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16), !utf16.isEmpty {
            return utf16
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func readImages(from pasteboard: NSPasteboard) -> [PasteboardImage] {
        var images: [PasteboardImage] = []
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.image.identifier),
        ]

        for type in imageTypes {
            guard let data = pasteboard.data(forType: type), !data.isEmpty else { continue }
            let ext = type == .png ? "png" : "tiff"
            if !images.contains(where: { $0.data == data }) {
                images.append(PasteboardImage(data: data, fileExtension: ext))
            }
        }

        return images
    }
}
