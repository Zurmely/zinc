import Foundation

/// Emits YAML 1.2 double-quoted scalars for front matter string values.
public enum YamlEscape {
    private static let indicatorPrefixes: Set<Character> = [
        "-", "?", "&", "*", "!", "|", ">", "[", "{", "@", "#", "'", "\"", ":",
    ]

    public static func escape(_ value: String) -> String {
        if needsQuoting(value) {
            return "\"" + escapeDoubleQuoted(value) + "\""
        }
        return value
    }

    private static func needsQuoting(_ value: String) -> Bool {
        if value.isEmpty { return true }
        if let first = value.first, indicatorPrefixes.contains(first) { return true }
        if value.first?.isWhitespace == true || value.last?.isWhitespace == true { return true }
        if value.contains(where: { $0.isNewline || $0 < "\u{20}" }) { return true }
        if value.contains(":") || value.contains("#") || value.contains("\"") || value.contains("\\") { return true }
        if looksLikeBoolean(value) || looksLikeNumber(value) { return true }
        return false
    }

    private static func escapeDoubleQuoted(_ value: String) -> String {
        var result = ""
        for char in value {
            switch char {
            case "\\":
                result += "\\\\"
            case "\"":
                result += "\\\""
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if char < "\u{20}" {
                    let code = char.unicodeScalars.first!.value
                    result += String(format: "\\u%04x", code)
                } else {
                    result.append(char)
                }
            }
        }
        return result
    }

    private static func looksLikeBoolean(_ value: String) -> Bool {
        switch value.lowercased() {
        case "true", "false", "yes", "no", "on", "off":
            return true
        default:
            return false
        }
    }

    private static func looksLikeNumber(_ value: String) -> Bool {
        if value.hasPrefix("0") && value.count > 1 && !value.hasPrefix("0.") {
            return true
        }

        if value.hasPrefix("0x") || value.hasPrefix("-0x") || value.hasPrefix("+0x") {
            let hexStart = value.hasPrefix("-") || value.hasPrefix("+") ? 3 : 2
            let hex = String(value.dropFirst(hexStart))
            if !hex.isEmpty && hex.allSatisfy(\.isHexDigit) { return true }
        }

        let scanner = Scanner(string: value)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        if scanner.scanDouble() != nil && scanner.isAtEnd {
            return true
        }
        return false
    }
}
