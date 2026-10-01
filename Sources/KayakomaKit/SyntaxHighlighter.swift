import Foundation
import os
import TreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterPHP
import TreeSitterPython
import TreeSitterRust
import TreeSitterSQL
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterXML
import TreeSitterYAML

/// Highlight queries of the grammars, as published with them; see the files
/// of `HighlightQueries/`.
enum HighlightQueries {}

/// A language whose code blocks are highlighted.
enum CodeLanguage: String, CaseIterable, Sendable {
    case bash, c, cpp, css, go, html, javascript, json, php, python, rust, sql, swift, tsx, typescript, xml, yaml

    /// Names accepted in a code block's info string, besides the language's own.
    private static let aliases: [String: CodeLanguage] = [
        "sh": .bash, "zsh": .bash, "shell": .bash,
        "c++": .cpp, "cc": .cpp, "cxx": .cpp, "h": .cpp, "hpp": .cpp,
        "htm": .html,
        "js": .javascript, "mjs": .javascript, "cjs": .javascript, "jsx": .javascript,
        "jsonc": .json,
        "golang": .go,
        "py": .python,
        "rs": .rust,
        "ts": .typescript,
        "yml": .yaml,
    ]

    /// The language named by the first word of an info string, ignoring
    /// case; `nil` when there is none or it is not known.
    init?(infoString: String?) {
        guard let name = Self.name(inInfoString: infoString)?.lowercased() else { return nil }
        guard let language = Self(rawValue: name) ?? Self.aliases[name] else { return nil }
        self = language
    }

    /// The first word of an info string, as written.
    static func name(inInfoString infoString: String?) -> String? {
        infoString?.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}

/// The kinds of token that code blocks color, each with a color in `Theme.CodeSyntaxColors`.
enum TokenRole: Int, CaseIterable, Sendable {
    case keyword, string, comment, number, type, function, variable, constant, `operator`, punctuation, tag, attribute

    /// What a highlight capture name (`function.method`, `string.special.key`…)
    /// does to its text: `.some(role)` colors it, `.some(nil)` gives it the
    /// plain code color (over an enclosing capture), `nil` leaves it as it is.
    static func forCapture(_ name: String) -> TokenRole?? {
        let parts = name.split(separator: ".")
        guard let first = parts.first else { return .none }
        let rest = parts.dropFirst().joined(separator: ".")
        switch first {
        case "comment":
            return .some(.comment)
        case "string":
            switch rest {
            case "special.key": return .some(.variable)
            case "special.symbol", "escape": return .some(.constant)
            default: return .some(.string)
            }
        case "character":
            return .some(rest == "special" ? .constant : .string)
        case "escape":
            return .some(.constant)
        case "number", "float":
            return .some(.number)
        case "boolean":
            return .some(.constant)
        case "keyword", "conditional", "repeat", "include", "exception", "storageclass",
             "import", "charset", "media", "keyframes", "supports":
            return .some(.keyword)
        case "type":
            return .some(rest == "qualifier" ? .keyword : .type)
        case "constructor", "namespace", "module":
            return .some(.type)
        case "function", "method":
            return .some(.function)
        case "variable":
            return .some(rest == "builtin" ? .constant : .variable)
        case "parameter", "field", "property":
            return .some(.variable)
        case "constant":
            return .some(.constant)
        case "label":
            return .some(.attribute)
        case "operator":
            return .some(.operator)
        case "punctuation", "delimiter":
            return .some(.punctuation)
        case "tag":
            return .some(.tag)
        case "attribute":
            return .some(.attribute)
        case "embedded", "none":
            return .some(nil)
        default:
            // `spell`, `markup.*`, `error` and captures private to a query
            // (`_name`) say nothing about color.
            return .none
        }
    }
}

/// Finds the tokens of code with Tree-sitter grammars and their highlight queries.
///
/// Thread-safe: each call parses with its own parser and query cursor, and the
/// compiled queries, which Tree-sitter never changes once built, are shared. A
/// language's query is compiled on first use.
final class SyntaxHighlighter: Sendable {
    static let shared = SyntaxHighlighter()

    /// A run of code and the role that colors it.
    struct Run: Equatable {
        let range: NSRange
        let role: TokenRole
    }

    /// Code longer than this, in UTF-16 units, is left plain rather than
    /// parsed while a block is built.
    static let maximumLength = 200_000

    /// Compiled grammars by language; `nil` records a query that failed to
    /// compile, so that it is not retried.
    private let grammars = OSAllocatedUnfairLock<[GrammarKey: Grammar?]>(initialState: [:])

    /// The runs of `code` that a role colors, sorted and not overlapping; text
    /// outside them is plain. Empty when the code cannot be parsed.
    func runs(in code: String, language: CodeLanguage) -> [Run] {
        let units = Array(code.utf16)
        let length = units.count
        guard length > 0, length <= Self.maximumLength,
              let grammar = grammar(for: Self.key(for: language, code: code)),
              let parser = ts_parser_new() else { return [] }
        defer { ts_parser_delete(parser) }
        guard ts_parser_set_language(parser, grammar.language) else { return [] }
        let parsed = units.withUnsafeBytes { bytes in
            ts_parser_parse_string_encoding(
                parser, nil, bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                UInt32(bytes.count), TSInputEncodingUTF16LE
            )
        }
        guard let tree = parsed, let cursor = ts_query_cursor_new() else { return [] }
        defer {
            ts_query_cursor_delete(cursor)
            ts_tree_delete(tree)
        }

        // Every capture paints its range; the outermost ones first, so that a
        // capture inside another (an escape in a string) comes out on top, and
        // for the same range in pattern order, so that the last pattern wins,
        // as in Tree-sitter's own highlighter.
        struct Span {
            let start: Int
            let end: Int
            let pattern: Int
            let order: Int
            /// Index of the role in `TokenRole`, or -1 for plain code.
            let role: Int
        }
        var spans: [Span] = []
        let text = Grammar.Text(units: units)
        ts_query_cursor_exec(cursor, grammar.query, ts_tree_root_node(tree))
        var match = TSQueryMatch()
        while ts_query_cursor_next_match(cursor, &match) {
            let captures = UnsafeBufferPointer(start: match.captures, count: Int(match.capture_count))
            let pattern = Int(match.pattern_index)
            guard grammar.allows(pattern: pattern, captures: captures, in: text) else { continue }
            for capture in captures {
                guard let role = grammar.roles[Int(capture.index)] else { continue }
                // UTF-16 offsets: two bytes per unit.
                let start = Int(ts_node_start_byte(capture.node)) / 2
                let end = min(Int(ts_node_end_byte(capture.node)) / 2, length)
                guard start < end else { continue }
                spans.append(Span(start: start, end: end, pattern: pattern, order: spans.count, role: role?.rawValue ?? -1))
            }
        }
        spans.sort {
            let first = $0.end - $0.start, second = $1.end - $1.start
            if first != second { return first > second }
            if $0.pattern != $1.pattern { return $0.pattern < $1.pattern }
            return $0.order < $1.order
        }

        // Paint roles per UTF-16 unit, then gather equal neighbours into runs.
        var painted = [Int8](repeating: -1, count: length)
        for span in spans {
            let role = Int8(span.role)
            for index in span.start..<span.end { painted[index] = role }
        }
        var runs: [Run] = []
        var start = 0
        while start < length {
            var end = start + 1
            while end < length, painted[end] == painted[start] { end += 1 }
            if let role = TokenRole(rawValue: Int(painted[start])) {
                runs.append(Run(range: NSRange(location: start, length: end - start), role: role))
            }
            start = end
        }
        return runs
    }

    /// The grammar and query a language is parsed with. PHP is parsed without
    /// its `<?php` tag unless the code has one, as code blocks usually omit it.
    private enum GrammarKey: Hashable {
        case language(CodeLanguage)
        case phpWithTags
    }

    private static func key(for language: CodeLanguage, code: String) -> GrammarKey {
        language == .php && code.contains("<?") ? .phpWithTags : .language(language)
    }

    private func grammar(for key: GrammarKey) -> Grammar? {
        if let cached = grammars.withLock({ $0[key] }) { return cached }
        // Compiled outside the lock: two threads may both compile a query the
        // first time, which is harmless.
        let grammar = switch key {
        case .language(let language): Self.makeGrammar(language)
        case .phpWithTags: Grammar(tree_sitter_php(), HighlightQueries.php)
        }
        grammars.withLock { $0[key] = .some(grammar) }
        return grammar
    }

    private static func makeGrammar(_ language: CodeLanguage) -> Grammar? {
        switch language {
        case .bash: Grammar(tree_sitter_bash(), HighlightQueries.bash)
        case .c: Grammar(tree_sitter_c(), HighlightQueries.c)
        // As published with the grammar: the C++ query adds to the C one.
        case .cpp: Grammar(tree_sitter_cpp(), HighlightQueries.c, HighlightQueries.cpp)
        case .css: Grammar(tree_sitter_css(), HighlightQueries.css)
        case .go: Grammar(tree_sitter_go(), HighlightQueries.go)
        case .html: Grammar(tree_sitter_html(), HighlightQueries.html)
        case .javascript:
            Grammar(tree_sitter_javascript(), HighlightQueries.javascript, HighlightQueries.jsx, HighlightQueries.javascriptParameters)
        case .json: Grammar(tree_sitter_json(), HighlightQueries.json)
        case .php: Grammar(tree_sitter_php_only(), HighlightQueries.php)
        case .python: Grammar(tree_sitter_python(), HighlightQueries.python)
        case .rust: Grammar(tree_sitter_rust(), HighlightQueries.rust)
        case .sql: Grammar(tree_sitter_sql(), HighlightQueries.sql)
        case .swift: Grammar(tree_sitter_swift(), HighlightQueries.swift)
        // The TypeScript queries add to the JavaScript ones; they come last so
        // that their patterns win.
        case .tsx: Grammar(tree_sitter_tsx(), HighlightQueries.javascript, HighlightQueries.jsx, HighlightQueries.typescript)
        case .typescript: Grammar(tree_sitter_typescript(), HighlightQueries.javascript, HighlightQueries.typescript)
        case .xml: Grammar(tree_sitter_xml(), HighlightQueries.xml)
        case .yaml: Grammar(tree_sitter_yaml(), HighlightQueries.yaml)
        }
    }
}

/// A parser language and its compiled highlight query.
///
/// Immutable once built: Tree-sitter allows one query to run in several
/// cursors at once, on any thread.
private final class Grammar: @unchecked Sendable {
    let language: OpaquePointer
    let query: OpaquePointer
    /// What each capture of the query does, by capture index; see `TokenRole.forCapture`.
    let roles: [TokenRole??]
    /// The text predicates of each pattern, by pattern index.
    let predicates: [[Predicate]]

    /// The code being highlighted, for predicates to read.
    struct Text {
        let units: [UInt16]

        func string(of node: TSNode) -> String {
            let start = Int(ts_node_start_byte(node)) / 2
            let end = min(Int(ts_node_end_byte(node)) / 2, units.count)
            guard start < end else { return "" }
            return String(decoding: units[start..<end], as: UTF16.self)
        }
    }

    /// A condition on the text of a capture, such as `(#match? @constant "^[A-Z]")`.
    /// Other predicates (`#is-not?`, `#set!`…) do not restrict highlighting.
    enum Predicate {
        case equal(capture: UInt32, to: Operand, negated: Bool)
        case match(capture: UInt32, NSRegularExpression, negated: Bool)
        case anyOf(capture: UInt32, Set<String>, negated: Bool)

        enum Operand {
            case capture(UInt32)
            case string(String)
        }
    }

    init?(_ language: OpaquePointer?, _ sources: String...) {
        guard let language else { return nil }
        let source = sources.joined(separator: "\n")
        var errorOffset: UInt32 = 0
        var error = TSQueryErrorNone
        let compiled = source.withCString { ts_query_new(language, $0, UInt32(strlen($0)), &errorOffset, &error) }
        guard let query = compiled else { return nil }
        self.language = language
        self.query = query
        roles = (0..<ts_query_capture_count(query)).map { index in
            var length: UInt32 = 0
            guard let name = ts_query_capture_name_for_id(query, index, &length) else { return .none }
            return TokenRole.forCapture(String(cString: name))
        }
        predicates = (0..<ts_query_pattern_count(query)).map { Self.predicates(of: query, pattern: $0) }
    }

    deinit {
        ts_query_delete(query)
    }

    /// Whether the text predicates of a pattern hold for a match of it.
    func allows(pattern: Int, captures: UnsafeBufferPointer<TSQueryCapture>, in text: Text) -> Bool {
        let predicates = predicates[pattern]
        guard !predicates.isEmpty else { return true }
        func texts(_ capture: UInt32) -> [String] {
            captures.filter { $0.index == capture }.map { text.string(of: $0.node) }
        }
        for predicate in predicates {
            switch predicate {
            case let .equal(capture, operand, negated):
                let other: [String] = switch operand {
                case .capture(let index): texts(index)
                case .string(let string): [string]
                }
                for value in texts(capture) where other.contains(value) == negated { return false }
            case let .match(capture, expression, negated):
                for value in texts(capture) {
                    let found = expression.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
                    if found == negated { return false }
                }
            case let .anyOf(capture, values, negated):
                for value in texts(capture) where values.contains(value) == negated { return false }
            }
        }
        return true
    }

    private static func predicates(of query: OpaquePointer, pattern: UInt32) -> [Predicate] {
        var count: UInt32 = 0
        guard let steps = ts_query_predicates_for_pattern(query, pattern, &count) else { return [] }
        func string(_ id: UInt32) -> String {
            var length: UInt32 = 0
            return ts_query_string_value_for_id(query, id, &length).map { String(cString: $0) } ?? ""
        }
        var result: [Predicate] = []
        var arguments: [TSQueryPredicateStep] = []
        for step in UnsafeBufferPointer(start: steps, count: Int(count)) {
            guard step.type == TSQueryPredicateStepTypeDone else {
                arguments.append(step)
                continue
            }
            defer { arguments.removeAll() }
            guard arguments.count >= 3, arguments[0].type == TSQueryPredicateStepTypeString,
                  arguments[1].type == TSQueryPredicateStepTypeCapture else { continue }
            let name = string(arguments[0].value_id)
            let capture = arguments[1].value_id
            let rest = arguments.dropFirst(2)
            let negated = name.hasPrefix("not-")
            switch negated ? String(name.dropFirst(4)) : name {
            case "eq?":
                let operand = rest.first!
                result.append(.equal(
                    capture: capture,
                    to: operand.type == TSQueryPredicateStepTypeCapture ? .capture(operand.value_id) : .string(string(operand.value_id)),
                    negated: negated
                ))
            case "match?":
                guard let expression = try? NSRegularExpression(pattern: string(rest.first!.value_id)) else { continue }
                result.append(.match(capture: capture, expression, negated: negated))
            case "any-of?":
                result.append(.anyOf(capture: capture, Set(rest.map { string($0.value_id) }), negated: negated))
            default:
                continue
            }
        }
        return result
    }
}
