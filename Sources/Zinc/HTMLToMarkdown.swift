import Foundation

enum HTMLToMarkdown {
    struct ImageReference {
        let originalSource: String
        let markdownSource: String
    }

    static func convert(_ html: String) -> (markdown: String, imageReferences: [ImageReference]) {
        // Parse from a Unicode string — never via UTF-8 Data. XMLDocument(data:) with a
        // `<meta charset="utf-8">` (common from Chrome/Cursor) double-encodes and produces
        // mojibake like "Â" (from NBSP) and "â€™" (from curly quotes).
        let normalized = extractHTMLDocument(html)
        let options: XMLDocument.Options = [.documentTidyHTML]
        guard let document = try? XMLDocument(xmlString: normalized, options: options),
              let root = document.rootElement() else {
            return (html, [])
        }

        var imageReferences: [ImageReference] = []
        let body = root.elements(forName: "body").first ?? root
        var markdown = convertChildren(of: body, imageReferences: &imageReferences)
        markdown = collapseBlankLines(markdown)
        return (markdown.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), imageReferences)
    }

    /// Strips CF_HTML clipboard headers (`Version:0.9` / StartHTML / …) when present.
    private static func extractHTMLDocument(_ raw: String) -> String {
        guard raw.hasPrefix("Version:") else { return raw }

        let utf8 = Array(raw.utf8)
        var startHTML: Int?
        var endHTML: Int?
        var startFragment: Int?
        var endFragment: Int?

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("StartHTML:") {
                startHTML = Int(text.dropFirst("StartHTML:".count).trimmingCharacters(in: .whitespaces))
            } else if text.hasPrefix("EndHTML:") {
                endHTML = Int(text.dropFirst("EndHTML:".count).trimmingCharacters(in: .whitespaces))
            } else if text.hasPrefix("StartFragment:") {
                startFragment = Int(text.dropFirst("StartFragment:".count).trimmingCharacters(in: .whitespaces))
            } else if text.hasPrefix("EndFragment:") {
                endFragment = Int(text.dropFirst("EndFragment:".count).trimmingCharacters(in: .whitespaces))
            } else if text.hasPrefix("<") {
                break
            }
        }

        if let start = startFragment, let end = endFragment,
           start >= 0, end > start, end <= utf8.count {
            return String(decoding: utf8[start..<end], as: UTF8.self)
        }
        if let start = startHTML, let end = endHTML,
           start >= 0, end > start, end <= utf8.count {
            return String(decoding: utf8[start..<end], as: UTF8.self)
        }
        if let index = raw.firstIndex(of: "<") {
            return String(raw[index...])
        }
        return raw
    }

    private static func convertChildren(of element: XMLElement, imageReferences: inout [ImageReference]) -> String {
        var parts: [String] = []
        for child in element.children ?? [] {
            if child.kind == .text {
                let value = child.stringValue ?? ""
                if !value.isEmpty {
                    parts.append(escapeText(value))
                }
            } else if let childElement = child as? XMLElement {
                parts.append(convertElement(childElement, imageReferences: &imageReferences))
            }
        }
        return parts.joined()
    }

    private static func convertElement(_ element: XMLElement, imageReferences: inout [ImageReference]) -> String {
        let tag = element.name?.lowercased() ?? ""
        let children = convertChildren(of: element, imageReferences: &imageReferences)

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.last!)) ?? 1
            return block("\(String(repeating: "#", count: level)) \(children.trimmingCharacters(in: .whitespacesAndNewlines))")

        case "p", "div", "section", "article", "main", "header", "footer", "figure", "figcaption":
            let trimmed = children.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "" : block(trimmed)

        case "br":
            return "\n"

        case "hr":
            return block("---")

        case "strong", "b":
            return wrapInline(children, prefix: "**", suffix: "**")

        case "em", "i":
            return wrapInline(children, prefix: "*", suffix: "*")

        case "code":
            if children.contains("\n") {
                return block("```\n\(children.trimmingCharacters(in: .whitespacesAndNewlines))\n```")
            }
            return "`\(children.trimmingCharacters(in: .whitespacesAndNewlines))`"

        case "pre":
            let code = element.elements(forName: "code").first
            let content = code.map { convertChildren(of: $0, imageReferences: &imageReferences) } ?? children
            return block("```\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))\n```")

        case "a":
            let href = element.attribute(forName: "href")?.stringValue ?? ""
            let text = children.trimmingCharacters(in: .whitespacesAndNewlines)
            if href.isEmpty {
                return text
            }
            if text.isEmpty {
                return href
            }
            return "[\(text)](\(href))"

        case "img":
            let src = element.attribute(forName: "src")?.stringValue ?? ""
            let alt = element.attribute(forName: "alt")?.stringValue ?? "image"
            if src.isEmpty {
                return ""
            }
            let ref = ImageReference(originalSource: src, markdownSource: src)
            imageReferences.append(ref)
            return "![\(escapeAlt(alt))](\(src))"

        case "blockquote":
            let lines = children
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")
            return block(lines)

        case "ul":
            return convertList(element, ordered: false, imageReferences: &imageReferences)

        case "ol":
            return convertList(element, ordered: true, imageReferences: &imageReferences)

        case "li":
            return children

        case "table":
            return convertTable(element, imageReferences: &imageReferences)

        case "thead", "tbody", "tfoot", "tr", "th", "td":
            return children

        case "span", "font", "mark", "sub", "sup", "u", "s", "del", "ins", "small", "label":
            return children

        case "head", "style", "script", "meta", "link", "title", "noscript":
            return ""

        default:
            return children
        }
    }

    private static func convertList(
        _ element: XMLElement,
        ordered: Bool,
        imageReferences: inout [ImageReference]
    ) -> String {
        var lines: [String] = []
        var index = 1
        for child in element.children ?? [] {
            guard let item = child as? XMLElement, item.name?.lowercased() == "li" else { continue }
            let content = convertChildren(of: item, imageReferences: &imageReferences)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: "\n  ")
            let marker = ordered ? "\(index)." : "-"
            lines.append("\(marker) \(content)")
            index += 1
        }
        return block(lines.joined(separator: "\n"))
    }

    private static func convertTable(_ element: XMLElement, imageReferences: inout [ImageReference]) -> String {
        var rows: [[String]] = []
        collectTableRows(from: element, into: &rows, imageReferences: &imageReferences)
        guard !rows.isEmpty else { return "" }

        let header = rows[0]
        let separator = header.map { _ in "---" }
        var lines = [formatTableRow(header), formatTableRow(separator)]
        if rows.count > 1 {
            lines.append(contentsOf: rows.dropFirst().map(formatTableRow))
        }
        return block(lines.joined(separator: "\n"))
    }

    private static func collectTableRows(
        from element: XMLElement,
        into rows: inout [[String]],
        imageReferences: inout [ImageReference]
    ) {
        let tag = element.name?.lowercased() ?? ""
        if tag == "tr" {
            let cells = element.children?.compactMap { $0 as? XMLElement }
                .filter { ["th", "td"].contains($0.name?.lowercased()) }
                .map {
                    convertChildren(of: $0, imageReferences: &imageReferences)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "|", with: "\\|")
                        .replacingOccurrences(of: "\n", with: " ")
                } ?? []
            if !cells.isEmpty {
                rows.append(cells)
            }
            return
        }

        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            collectTableRows(from: childElement, into: &rows, imageReferences: &imageReferences)
        }
    }

    private static func formatTableRow(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    private static func wrapInline(_ text: String, prefix: String, suffix: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\(prefix)\(trimmed)\(suffix)"
    }

    private static func block(_ text: String) -> String {
        "\n\n\(text)\n\n"
    }

    private static func escapeText(_ text: String) -> String {
        // Normalize NBSP to a regular space so markdown stays clean.
        var result = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let replacements: [(String, String)] = [
            ("\\", "\\\\"),
            ("*", "\\*"),
            ("_", "\\_"),
            ("`", "\\`"),
            ("[", "\\["),
            ("]", "\\]"),
            ("#", "\\#"),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    private static func escapeAlt(_ text: String) -> String {
        text.replacingOccurrences(of: "]", with: "\\]")
    }

    private static func collapseBlankLines(_ text: String) -> String {
        var result = text
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }
}
