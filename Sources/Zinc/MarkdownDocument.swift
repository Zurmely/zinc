import Foundation

struct MarkdownDocument {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet([String])
        case numbered([String])
        case quote(String)
        case code(String)
        case table(rows: [[String]])
        case image(relativePath: String, alt: String)
        case rule
    }

    let frontMatter: [String: String]
    let blocks: [Block]

    var contentTypeLabel: String {
        if blocks.contains(where: {
            if case .image = $0 { return true }
            return false
        }) {
            return "Image"
        }
        if blocks.contains(where: {
            if case .code = $0 { return true }
            return false
        }) {
            return "Code"
        }
        if blocks.contains(where: {
            if case .heading = $0 { return true }
            return false
        }) || blocks.count > 1 {
            return "Rich text"
        }
        if let first = blocks.first {
            switch first {
            case .paragraph(let text):
                if text.contains("http://") || text.contains("https://") {
                    return "Link"
                }
            default:
                break
            }
        }
        return "Text"
    }

    var firstImagePath: String? {
        for block in blocks {
            if case .image(let path, _) = block {
                return path
            }
        }
        return nil
    }

    static func parse(fileContents: String) -> MarkdownDocument {
        let (frontMatter, body) = splitFrontMatter(fileContents)
        let blocks = parseBody(body)
        return MarkdownDocument(frontMatter: frontMatter, blocks: blocks)
    }

    static func fallback(from text: String) -> MarkdownDocument {
        MarkdownDocument(frontMatter: [:], blocks: [.paragraph(text)])
    }

    private static func splitFrontMatter(_ contents: String) -> ([String: String], String) {
        let lines = contents.components(separatedBy: .newlines)
        guard lines.first == "---" else {
            return ([:], contents)
        }

        var frontMatter: [String: String] = [:]
        var index = 1
        while index < lines.count, lines[index] != "---" {
            let line = lines[index]
            if let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                frontMatter[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            index += 1
        }

        let bodyStart = index + 1
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""
        return (frontMatter, body)
    }

    private static func parseBody(_ body: String) -> [Block] {
        var blocks: [Block] = []
        let lines = body.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = trimmed.drop(while: { $0 == "#" || $0 == " " })
                blocks.append(.heading(level: min(level, 6), text: String(text)))
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if current.hasPrefix(">") {
                        let content = current.dropFirst().trimmingCharacters(in: .whitespaces)
                        quoteLines.append(content.hasPrefix(">") ? String(content.dropFirst()).trimmingCharacters(in: .whitespaces) : content)
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if current.hasPrefix("- ") || current.hasPrefix("* ") {
                        items.append(String(current.dropFirst(2)))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bullet(items))
                continue
            }

            if let firstItem = numberedListItem(from: trimmed) {
                var items: [String] = [firstItem]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if let item = numberedListItem(from: current) {
                        items.append(item)
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numbered(items))
                continue
            }

            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                var rows: [[String]] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix("|"), current.hasSuffix("|") else { break }
                    if current.contains("---") {
                        index += 1
                        continue
                    }
                    let cells = current
                        .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                        .components(separatedBy: "|")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    rows.append(cells)
                    index += 1
                }
                if !rows.isEmpty {
                    blocks.append(.table(rows: rows))
                }
                continue
            }

            if let image = parseImageLine(trimmed) {
                blocks.append(image)
                index += 1
                continue
            }

            var paragraphLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty
                    || next.hasPrefix("#")
                    || next.hasPrefix("```")
                    || next.hasPrefix(">")
                    || next.hasPrefix("- ")
                    || next.hasPrefix("* ")
                    || next.hasPrefix("|")
                    || numberedListItem(from: next) != nil
                    || parseImageLine(next) != nil
                    || next == "---" {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func numberedListItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = trimmed[..<dotIndex]
        guard Int(prefix) != nil else { return nil }
        let afterDot = trimmed.index(after: dotIndex)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        let start = trimmed.index(after: afterDot)
        guard start <= trimmed.endIndex else { return nil }
        return String(trimmed[start...])
    }

    private static func parseImageLine(_ line: String) -> Block? {
        guard line.hasPrefix("!["),
              let closeBracket = line.firstIndex(of: "]"),
              let openParen = line[closeBracket...].firstIndex(of: "("),
              let closeParen = line[openParen...].firstIndex(of: ")") else {
            return nil
        }

        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<closeBracket])
        let pathStart = line.index(after: openParen)
        let path = String(line[pathStart..<closeParen])
        return .image(relativePath: path, alt: alt)
    }
}
