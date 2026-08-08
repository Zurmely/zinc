import XCTest
@testable import ZincCore

final class YamlEscapeTests: XCTestCase {
    private struct Case {
        let input: String
        let expected: String
        let label: String
    }

    private let cases: [Case] = [
        Case(input: "Safari", expected: "Safari", label: "plain app name"),
        Case(input: "", expected: "\"\"", label: "empty"),
        Case(input: "line one\nline two", expected: "\"line one\\nline two\"", label: "newline"),
        Case(input: "say \"hello\"", expected: "\"say \\\"hello\\\"\"", label: "embedded quotes"),
        Case(input: "key: value", expected: "\"key: value\"", label: "colon"),
        Case(input: "not a #comment", expected: "\"not a #comment\"", label: "hash"),
        Case(input: "- list item", expected: "\"- list item\"", label: "dash prefix"),
        Case(input: "?query", expected: "\"?query\"", label: "question prefix"),
        Case(input: "&anchor", expected: "\"&anchor\"", label: "ampersand prefix"),
        Case(input: "*star", expected: "\"*star\"", label: "asterisk prefix"),
        Case(input: "!tag", expected: "\"!tag\"", label: "exclamation prefix"),
        Case(input: "|block", expected: "\"|block\"", label: "pipe prefix"),
        Case(input: ">folded", expected: "\">folded\"", label: "greater prefix"),
        Case(input: "[array]", expected: "\"[array]\"", label: "bracket prefix"),
        Case(input: "{object}", expected: "\"{object}\"", label: "brace prefix"),
        Case(input: "@mention", expected: "\"@mention\"", label: "at prefix"),
        Case(input: "  padded  ", expected: "\"  padded  \"", label: "surrounding whitespace"),
        Case(input: "42", expected: "\"42\"", label: "integer"),
        Case(input: "3.14", expected: "\"3.14\"", label: "float"),
        Case(input: "true", expected: "\"true\"", label: "boolean true"),
        Case(input: "false", expected: "\"false\"", label: "boolean false"),
        Case(input: "tab\there", expected: "\"tab\\there\"", label: "tab"),
        Case(input: "return\rhere", expected: "\"return\\rhere\"", label: "carriage return"),
        Case(input: "back\\slash", expected: "\"back\\\\slash\"", label: "backslash"),
        Case(input: "0123", expected: "\"0123\"", label: "leading-zero numeric"),
        Case(input: "0xFF", expected: "\"0xFF\"", label: "hex"),
    ]

    func testYamlEscapeTable() {
        for testCase in cases {
            XCTAssertEqual(YamlEscape.escape(testCase.input), testCase.expected, testCase.label)
        }
    }

    func testFrontMatterWithNewlineTitleIsSingleLineYAML() {
        let title = "First line\nSecond line"
        let escaped = YamlEscape.escape(title)
        let line = "title: \(escaped)"
        XCTAssertFalse(line.contains("\n"), "front matter line must not contain raw newlines")
        XCTAssertTrue(escaped.hasPrefix("\"") && escaped.hasSuffix("\""))
    }
}
