import AppKit
import Foundation
import Markdown
import PDFKit
import Testing
@testable import KayakomaKit

// MARK: - Languages

@Test func infoStringsResolveToLanguagesThroughTheirAliases() {
    let expected: [String: CodeLanguage] = [
        "js": .javascript, "javascript": .javascript, "mjs": .javascript, "cjs": .javascript, "jsx": .javascript,
        "ts": .typescript, "typescript": .typescript, "tsx": .tsx,
        "sh": .bash, "bash": .bash, "zsh": .bash, "shell": .bash,
        "py": .python, "python": .python,
        "rs": .rust, "rust": .rust,
        "go": .go, "golang": .go,
        "c": .c,
        "cpp": .cpp, "c++": .cpp, "cc": .cpp, "cxx": .cpp, "h": .cpp, "hpp": .cpp,
        "yml": .yaml, "yaml": .yaml,
        "html": .html, "htm": .html, "xml": .xml,
        "json": .json, "jsonc": .json,
        "sql": .sql, "php": .php, "css": .css, "swift": .swift,
    ]
    for (name, language) in expected {
        #expect(CodeLanguage(infoString: name) == language, "\(name)")
    }
    // The first word only, whatever its case.
    #expect(CodeLanguage(infoString: "Rust") == .rust)
    #expect(CodeLanguage(infoString: "PY title=\"example.py\"") == .python)
    #expect(CodeLanguage.name(inInfoString: "TypeScript {1,3}") == "TypeScript")

    for unknown: String? in [nil, "", "   ", "text", "brainfuck", "rusty", "{.rust}"] {
        #expect(CodeLanguage(infoString: unknown) == nil, "\(unknown ?? "nil")")
    }
}

@Test func everyLanguageHasAWorkingQuery() {
    let samples: [CodeLanguage: String] = [
        .bash: "echo \"hi\" # greet", .c: "int main(void) { return 0; }", .cpp: "class A { public: int x; };",
        .css: "a { color: red; }", .go: "func main() {}", .html: "<p class=\"x\">Hi</p>",
        .javascript: "const a = 1; // one", .json: "{\"a\": 1}", .php: "function f() { return 1; }",
        .python: "def f():\n    return 1", .rust: "fn main() {}", .sql: "SELECT id FROM items;",
        .swift: "let a = 1", .tsx: "const a = <div>{1}</div>;", .typescript: "let a: number = 1;",
        .xml: "<root a=\"1\"/>", .yaml: "key: value",
    ]
    for language in CodeLanguage.allCases {
        let code = samples[language] ?? ""
        #expect(!SyntaxHighlighter.shared.runs(in: code, language: language).isEmpty, "\(language)")
    }
    // PHP with its opening tag uses the grammar that also reads the HTML around it.
    #expect(role(of: "function", in: "<?php\nfunction f() {}\n", language: .php) == .keyword)
}

// MARK: - Tokens

/// The role coloring the whole of the `occurrence`-th appearance of `token`,
/// or `nil` when it is plain or split between roles.
private func role(of token: String, occurrence: Int = 0, in code: String, language: CodeLanguage) -> TokenRole? {
    let string = code as NSString
    var search = NSRange(location: 0, length: string.length)
    var found = NSRange(location: NSNotFound, length: 0)
    for _ in 0...occurrence {
        found = string.range(of: token, range: search)
        guard found.location != NSNotFound else { return nil }
        search = NSRange(location: found.upperBound, length: string.length - found.upperBound)
    }
    let runs = SyntaxHighlighter.shared.runs(in: code, language: language)
    return runs.first { NSIntersectionRange($0.range, found) == found }?.role
}

@Test func phpTokensGetTheirRoles() {
    let code = """
    // c
    function greet(string $name): string {
        return "str" . $name . 42;
    }
    """
    #expect(role(of: "// c", in: code, language: .php) == .comment)
    #expect(role(of: "function", in: code, language: .php) == .keyword)
    #expect(role(of: "greet", in: code, language: .php) == .function)
    #expect(role(of: "\"str\"", in: code, language: .php) == .string)
    #expect(role(of: "return", in: code, language: .php) == .keyword)
    #expect(role(of: "42", in: code, language: .php) == .number)
    // The sigil is an operator, the name a variable.
    #expect(role(of: "$", in: code, language: .php) == .operator)
    #expect(role(of: "name", in: code, language: .php) == .variable)
}

@Test func rustTokensGetTheirRoles() {
    let code = """
    /// Returns the longer one.
    fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
        let size = 3;
        if x.len() > y.len() { x } else { y }
    }
    """
    #expect(role(of: "/// Returns", in: code, language: .rust) == .comment)
    #expect(role(of: "fn", in: code, language: .rust) == .keyword)
    #expect(role(of: "longest", in: code, language: .rust) == .function)
    #expect(role(of: "let", in: code, language: .rust) == .keyword)
    #expect(role(of: "3", in: code, language: .rust) == .number)
    #expect(role(of: "str", in: code, language: .rust) == .type)
    // The name of a lifetime is a label.
    #expect(role(of: "a", occurrence: 0, in: "fn f<'a>() {}", language: .rust) == .attribute)
    #expect(role(of: "len", in: code, language: .rust) == .function)
}

@Test func cssPropertiesAndValuesGetTheirRoles() {
    let code = """
    .card > h2 {
      color: #ff0000;
      margin: 12px auto;
      font-family: "Inter", sans-serif;
    }
    @media (min-width: 600px) { .card { display: none; } }
    """
    #expect(role(of: "color", in: code, language: .css) == .variable)
    #expect(role(of: "ff0000", in: code, language: .css) == .string)
    #expect(role(of: "12", in: code, language: .css) == .number)
    #expect(role(of: "px", in: code, language: .css) == .type)
    #expect(role(of: "\"Inter\"", in: code, language: .css) == .string)
    #expect(role(of: "h2", in: code, language: .css) == .tag)
    #expect(role(of: "@media", in: code, language: .css) == .keyword)
    #expect(role(of: ":", in: code, language: .css) == .punctuation)
}

@Test func jsonKeysAndStringsGetDifferentRoles() {
    let code = #"{ "name": "Ixora", "moons": 2, "ringed": true, "notes": null }"#
    #expect(role(of: "\"name\"", in: code, language: .json) == .variable)
    #expect(role(of: "\"Ixora\"", in: code, language: .json) == .string)
    #expect(role(of: "2", in: code, language: .json) == .number)
    #expect(role(of: "true", in: code, language: .json) == .constant)
    #expect(role(of: "null", in: code, language: .json) == .constant)
}

@Test func otherLanguagesGetTheirMainRoles() {
    #expect(role(of: "def", in: "def area(r):\n    return 3.14 * r", language: .python) == .keyword)
    #expect(role(of: "area", in: "def area(r):\n    return 3.14 * r", language: .python) == .function)
    #expect(role(of: "func", in: "package main\n\nfunc main() {}", language: .go) == .keyword)
    #expect(role(of: "struct", in: "struct Point { let x: Int }", language: .swift) == .keyword)
    #expect(role(of: "Int", in: "struct Point { let x: Int }", language: .swift) == .type)
    #expect(role(of: "interface", in: "interface Shape { area(): number }", language: .typescript) == .keyword)
    #expect(role(of: "number", in: "interface Shape { area(): number }", language: .typescript) == .type)
    #expect(role(of: "SELECT", in: "SELECT name FROM planets WHERE moons > 2;", language: .sql) == .keyword)
    #expect(role(of: "2", in: "SELECT name FROM planets WHERE moons > 2;", language: .sql) == .number)
    #expect(role(of: "div", in: "<div class=\"card\">Hi</div>", language: .html) == .tag)
    #expect(role(of: "class", in: "<div class=\"card\">Hi</div>", language: .html) == .attribute)
    #expect(role(of: "moon", in: "<moon radius=\"1.5\">Kell</moon>", language: .xml) == .tag)
    #expect(role(of: "radius", in: "<moon radius=\"1.5\">Kell</moon>", language: .xml) == .attribute)
    #expect(role(of: "name", in: "name: Ixora\nmoons: 2", language: .yaml) == .variable)
    #expect(role(of: "Ixora", in: "name: Ixora\nmoons: 2", language: .yaml) == .string)
    #expect(role(of: "echo", in: "echo \"$HOME\"", language: .bash) == .function)
    #expect(role(of: "#include", in: "#include <stdio.h>\nint main(void) { return 0; }", language: .c) == .keyword)
    #expect(role(of: "template", in: "template <typename T> T max(T a);", language: .cpp) == .keyword)
}

@Test func nestedCapturesLetTheInnermostWin() {
    // An escape inside a string, and a substitution inside a template string.
    #expect(role(of: "\\n", in: #"let s = "a\nb";"#, language: .rust) == .constant)
    #expect(role(of: "\"a", in: #"let s = "a\nb";"#, language: .rust) == .string)
    let template = "const s = `total: ${count}`;"
    #expect(role(of: "`total", in: template, language: .javascript) == .string)
    #expect(role(of: "count", in: template, language: .javascript) == .variable)
}

// MARK: - Rendering

/// Resolves a color in the light or dark appearance, as `#RRGGBB`.
private func hex(_ color: NSColor?, dark: Bool = false) -> String? {
    guard let color, let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return nil }
    var result: String?
    appearance.performAsCurrentDrawingAppearance {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        result = String(format: "#%02X%02X%02X", Int(round(rgb.redComponent * 255)), Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
    }
    return result
}

private func hex(_ color: Theme.Color, dark: Bool = false) -> String? {
    hex(color.nsColor, dark: dark)
}

private func build(_ markdown: String, theme: Theme = .default) throws -> NSAttributedString {
    let document = RenderedDocument(source: markdown)
    let block = try #require(document.blocks.first)
    return BlockBuilder(theme: theme, baseURL: nil).build(block.markup.markup)
}

private func color(of token: String, in text: NSAttributedString) -> NSColor? {
    let range = (text.string as NSString).range(of: token)
    guard range.location != NSNotFound else { return nil }
    return text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
}

@Test func codeBlocksAreColoredWithTheThemeColors() throws {
    let text = try build("```rust\nfn main() {\n    let answer = \"forty-two\"; // the answer\n}\n```")
    let colors = Theme.default.codeSyntax
    for dark in [false, true] {
        #expect(hex(color(of: "fn", in: text), dark: dark) == hex(colors.keyword, dark: dark))
        #expect(hex(color(of: "\"forty-two\"", in: text), dark: dark) == hex(colors.string, dark: dark))
        #expect(hex(color(of: "// the answer", in: text), dark: dark) == hex(colors.comment, dark: dark))
        #expect(hex(color(of: "main", in: text), dark: dark) == hex(colors.function, dark: dark))
    }

    var theme = Theme.default
    theme.codeSyntax.keyword = .custom(light: "#123456", dark: "#654321")
    let custom = try build("```rs\nfn main() {}\n```", theme: theme)
    #expect(hex(color(of: "fn", in: custom)) == "#123456")
    #expect(hex(color(of: "fn", in: custom), dark: true) == "#654321")
}

@Test func unknownLanguagesRenderAsPlainCode() throws {
    var theme = Theme.default
    theme.codeLanguageLabel = false
    let plain = try build("```\nfn main() { let x = 1; }\n```", theme: theme)
    for info in ["brainfuck", "text", "rusty"] {
        let unknown = try build("```\(info)\nfn main() { let x = 1; }\n```", theme: theme)
        #expect(unknown.isEqual(to: plain), "\(info)")
    }
    // One color throughout: the text color.
    var ranges = 0
    plain.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: plain.length)) { _, _, _ in ranges += 1 }
    #expect(ranges == 1)
}

@Test func crlfLineEndingsKeepTokenRangesAligned() throws {
    let text = try build("```rust\r\nlet a = 1;\r\nlet b = \"two\";\r\n```")
    #expect(hex(color(of: "\"two\"", in: text)) == hex(Theme.default.codeSyntax.string))
    #expect(hex(color(of: "let", in: text)) == hex(Theme.default.codeSyntax.keyword))
}

private func decoration(of text: NSAttributedString) -> BlockDecoration? {
    text.attribute(.kayakomaDecoration, at: 0, effectiveRange: nil) as? BlockDecoration
}

@Test func codeBlocksCarryTheirLanguageLabel() throws {
    #expect(try decoration(of: build("```Rust\nfn main() {}\n```"))?.codeLabel?.text == "rust")
    // Unknown languages show their name too; it is what the author wrote.
    #expect(try decoration(of: build("```Text\nplain\n```"))?.codeLabel?.text == "text")
    #expect(try decoration(of: build("```\nplain\n```"))?.codeLabel == nil)
    #expect(try decoration(of: build("    indented code"))?.codeLabel == nil)

    var theme = Theme.default
    theme.codeLanguageLabel = false
    #expect(try decoration(of: build("```rust\nfn main() {}\n```", theme: theme))?.codeLabel == nil)

    // The label makes room for itself above the first line.
    let labeled = try #require(decoration(of: build("```rust\nfn main() {}\n```")))
    let unlabeled = try #require(decoration(of: build("```\nfn main() {}\n```")))
    #expect(labeled.codeTopPadding > unlabeled.codeTopPadding)
    #expect(unlabeled.codeTopPadding == Theme.default.codePadding)
}

/// The code block fragments of a view's document, in order.
@MainActor
private func codeFragments(_ markdown: String) -> [BlockLayoutFragment] {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.document = RenderedDocument(source: markdown)
    view.layoutSubtreeIfNeeded()
    guard let layoutManager = view.textView.textLayoutManager else { return [] }
    var fragments: [BlockLayoutFragment] = []
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) {
        if let block = $0 as? BlockLayoutFragment, block.codePadding != nil { fragments.append(block) }
        return true
    }
    return fragments
}

@MainActor
@Test func aCodeBlockEndingTheDocumentKeepsItsHeight() throws {
    // TextKit adds an empty line after the document's last line break; the
    // background must not grow to cover it.
    let last = try #require(codeFragments("Intro.\n\n```\nlet a = 1\n```").first)
    let middle = try #require(codeFragments("Intro.\n\n```\nlet a = 1\n```\n\nEnd.").first)
    let lastBackground = try #require(last.codeBackground)
    let middleBackground = try #require(middle.codeBackground)
    #expect(lastBackground.height == middleBackground.height)
}

@MainActor
@Test func languageLabelIsNotPartOfTheCopiedText() throws {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    view.document = RenderedDocument(source: "Before.\n\n```python\nprint(1)\n```\n\nAfter.")
    view.layoutSubtreeIfNeeded()
    #expect(!view.textView.string.contains("python"))

    view.textView.selectAll(nil)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("kayakoma-test-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    #expect(view.textView.writeSelection(to: pasteboard, types: [.string]))
    let copied = try #require(pasteboard.string(forType: .string))
    #expect(copied.contains("print(1)"))
    #expect(!copied.contains("python"))

    // Drawn, but not as text, in the PDF either.
    let pdf = try #require(PDFDocument(data: MarkdownPDFExporter().pdfData(for: RenderedDocument(source: "```python\nprint(1)\n```"))))
    let pdfText = try #require(pdf.string)
    #expect(pdfText.contains("print(1)"))
    #expect(!pdfText.contains("python"))
}

@MainActor
@Test func editingAParagraphDoesNotRehighlightAnUnchangedCodeBlock() throws {
    let code = "```rust\nfn main() {\n    println!(\"hi\");\n}\n```"
    let renderer = DocumentRenderer()
    _ = renderer.update(to: RenderedDocument(source: "Intro.\n\n\(code)\n\nOutro."))
    #expect(renderer.buildCount == 3)
    let before = renderer.range(ofBlock: 1)

    let edit = renderer.update(to: RenderedDocument(source: "Intro, edited.\n\n\(code)\n\nOutro."))
    // Only the paragraph was built again; the code block kept its rendering.
    #expect(renderer.buildCount == 4)
    #expect(edit.range == NSRange(location: 0, length: "Intro.\n".utf16.count))
    #expect(!edit.replacement.string.contains("println"))
    #expect(renderer.range(ofBlock: 1).length == before.length)
}

// MARK: - Theme

@Test func codeSyntaxSettingsRoundTripThroughJSON() throws {
    var theme = Theme.default
    theme.codeSyntax.keyword = .custom(light: "#AA0000", dark: "#FF8888")
    theme.codeSyntax.operator = .system(.secondaryLabel)
    theme.codeSyntax.attribute = .custom(light: "#00000080", dark: "#FFFFFF80")
    theme.codeLanguageLabel = false

    let data = try JSONEncoder().encode(theme)
    #expect(try JSONDecoder().decode(Theme.self, from: data) == theme)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["codeLanguageLabel"] as? Bool == false)
    let syntax = try #require(object["codeSyntax"] as? [String: Any])
    #expect(syntax.keys.sorted() == [
        "attribute", "comment", "constant", "function", "keyword", "number",
        "operator", "punctuation", "string", "tag", "type", "variable",
    ])
    #expect(Theme.default.codeLanguageLabel)
}

@Test func partialCodeSyntaxKeepsTheOtherDefaultColors() throws {
    let theme = try JSONDecoder().decode(Theme.self, from: Data(##"{ "codeSyntax": { "string": { "light": "#116329" } } }"##.utf8))
    var expected = Theme.default
    expected.codeSyntax.string = .custom(light: "#116329", dark: "#116329")
    #expect(theme == expected)
    #expect(try JSONDecoder().decode(Theme.self, from: Data(##"{ "codeLanguageLabel": false }"##.utf8)).codeLanguageLabel == false)
}

@Test func invalidCodeSyntaxKeysAreRejectedWithTheirPath() throws {
    func message(_ json: String) -> String? {
        do {
            _ = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
            return nil
        } catch let DecodingError.dataCorrupted(context) {
            return context.debugDescription
        } catch {
            return "\(error)"
        }
    }
    let key = try #require(message(##"{ "codeSyntax": { "keywrd": "label" } }"##))
    #expect(key.contains("\"keywrd\"") && key.contains("codeSyntax"))
    let color = try #require(message(##"{ "codeSyntax": { "comment": { "light": "#GGGGGG" } } }"##))
    #expect(color.contains("codeSyntax.comment.light"))
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Theme.CodeSyntaxColors.self, from: Data(##"{ "keyword": "label" }"##.utf8))
    }
}

// MARK: - Performance

/// About 500 lines of invented code, ten lines repeated with new names.
private func longCode(_ language: CodeLanguage) -> String {
    (1...50).map { index in
        switch language {
        case .php:
            """
            // Computes the orbit of moon \(index).
            function orbit\(index)(array $moons, float $scale = 1.5): array {
                $result = [];
                foreach ($moons as $name => $radius) {
                    if ($radius > \(index)) { $result[$name] = $radius * $scale; }
                    else { $result[$name] = "small moon \\n"; }
                }
                return array_filter($result, fn($value) => $value !== null);
            }

            """
        default:
            """
            /// Computes the orbit of moon \(index).
            pub fn orbit\(index)<'a>(moons: &'a [Moon], scale: f64) -> Vec<&'a str> {
                let mut result = Vec::new();
                for moon in moons.iter().filter(|m| m.radius > \(index).0) {
                    if moon.name.len() > 3 { result.push(moon.name.as_str()); }
                    else { println!("small moon {}", moon.name); }
                }
                result.sort_by(|a, b| b.cmp(a));
                result
            }
            """
        }
    }.joined(separator: "\n")
}

@MainActor
@Test func highlightingStaysFastOnLongBlocks() throws {
    for language in [CodeLanguage.rust, .php] {
        let code = longCode(language)
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(lines >= 500)
        let markdown = "```\(language.rawValue)\n\(code)\n```"
        let block = try #require(RenderedDocument(source: markdown).blocks.first)
        let builder = BlockBuilder(theme: .default, baseURL: nil)

        // The first use of a language compiles its query.
        let cold = milliseconds { _ = SyntaxHighlighter.shared.runs(in: code, language: language) }
        var runs: [Double] = []
        var builds: [Double] = []
        var plain: [Double] = []
        for _ in 0..<5 {
            runs.append(milliseconds { _ = SyntaxHighlighter.shared.runs(in: code, language: language) })
            builds.append(milliseconds { _ = builder.build(block.markup.markup) })
            plain.append(milliseconds { _ = builder.build(RenderedDocument(source: "```\n\(code)\n```").blocks[0].markup.markup) })
        }
        let median = { (values: [Double]) in values.sorted()[values.count / 2] }
        print(String(format: "%@ %d lines: first highlight %.1f ms, highlight %.1f ms, block build %.1f ms (plain block %.1f ms)",
                     language.rawValue, lines, cold, median(runs), median(builds), median(plain)))
        // Generous bounds: debug builds on a busy machine are several times slower.
        #expect(median(builds) < 250)
    }
}
