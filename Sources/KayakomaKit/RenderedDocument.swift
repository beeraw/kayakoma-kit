import Foundation
import Markdown

/// A parsed Markdown document, ready to be laid out by `MarkdownView`.
///
/// Every top-level block keeps its range in the source text so that an editor
/// can keep its source pane and its preview scrolled to the same place.
public struct RenderedDocument: Sendable {
    public struct Block: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case heading(level: Int)
            case paragraph
            case list
            case blockQuote
            case codeBlock
            case thematicBreak
            case table
            case html
            case other
        }

        public let kind: Kind
        /// Lines of the source text covered by this block, 1-based and inclusive.
        public let sourceLines: ClosedRange<Int>?
        /// Source text of the block; two blocks with the same text render the same way.
        public let sourceText: String

        /// GitHub-style anchor of a heading (`"getting-started"`), unique in the
        /// document; `nil` for other blocks.
        public let anchor: String?

        let markup: MarkupBox
        /// Key under which the renderer reuses the block's rendering: its source
        /// text, plus the resolved destinations of its links and images when it
        /// has any, since a reference-style link resolves through a definition
        /// that may live anywhere in the document.
        let reuseKey: String

        public static func == (lhs: Block, rhs: Block) -> Bool {
            lhs.kind == rhs.kind && lhs.sourceLines == rhs.sourceLines && lhs.sourceText == rhs.sourceText
                && lhs.anchor == rhs.anchor
        }
    }

    public let source: String
    public let blocks: [Block]

    public init(source: String) {
        self.source = source
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let document = Document(parsing: source)
        var slugger = HeadingSlugger()
        self.blocks = document.children.map { markup in
            let range = markup.range.map(Self.lines)
            let text: String
            if let range, range.lowerBound >= 1, range.upperBound <= lines.count {
                text = lines[(range.lowerBound - 1)...(range.upperBound - 1)].joined(separator: "\n")
            } else {
                text = markup.format()
            }
            let anchor = (markup as? Heading).map { slugger.slug(for: HeadingSlugger.text(of: $0)) }
            return Block(
                kind: Self.kind(of: markup),
                sourceLines: range,
                sourceText: text,
                anchor: anchor,
                markup: MarkupBox(markup),
                reuseKey: Self.reuseKey(text: text, markup: markup)
            )
        }
    }

    /// Index of the heading whose anchor is `anchor`, as written after `#` in a
    /// link: a leading `#` is ignored, percent escapes are decoded, case does
    /// not matter, and GitHub's `user-content-` prefix is accepted.
    public func blockIndex(forAnchor anchor: String) -> Int? {
        var name = Substring(anchor)
        if name.hasPrefix("#") { name = name.dropFirst() }
        var wanted = (String(name).removingPercentEncoding ?? String(name)).lowercased()
        if wanted.hasPrefix("user-content-") { wanted.removeFirst("user-content-".count) }
        guard !wanted.isEmpty else { return nil }
        return blocks.firstIndex { $0.anchor == wanted }
    }

    /// Index of the block that contains `line`, or of the last block before it.
    public func blockIndex(forSourceLine line: Int) -> Int? {
        var candidate: Int?
        for (index, block) in blocks.enumerated() {
            guard let lines = block.sourceLines else { continue }
            if lines.lowerBound > line { break }
            candidate = index
        }
        return candidate ?? (blocks.isEmpty ? nil : 0)
    }

    /// Lines covered by a source range. cmark sometimes ends a block at the
    /// first column of the next line; that line does not belong to the block.
    private static func lines(_ range: SourceRange) -> ClosedRange<Int> {
        let start = range.lowerBound.line
        var end = range.upperBound.line
        if range.upperBound.column == 1, end > start { end -= 1 }
        return start...end
    }

    /// The source text, followed by the destination and title of every link
    /// and image when the block has any. Inline destinations are already in
    /// the text; reference-style ones are not, and neither is whether a
    /// bracketed label resolves to a link at all.
    private static func reuseKey(text: String, markup: Markup) -> String {
        guard text.contains("[") else { return text }
        var targets: [String] = []
        func walk(_ node: Markup) {
            switch node {
            case let link as Link: targets.append("L\(link.destination ?? "")\u{1}\(link.title ?? "")")
            case let image as Markdown.Image: targets.append("I\(image.source ?? "")\u{1}\(image.title ?? "")")
            default: break
            }
            for child in node.children { walk(child) }
        }
        walk(markup)
        return targets.isEmpty ? text : text + "\u{0}" + targets.joined(separator: "\u{2}")
    }

    private static func kind(of markup: Markup) -> Block.Kind {
        switch markup {
        case let heading as Heading: .heading(level: heading.level)
        case is Paragraph: .paragraph
        case is UnorderedList, is OrderedList: .list
        case is BlockQuote: .blockQuote
        case is CodeBlock: .codeBlock
        case is ThematicBreak: .thematicBreak
        case is Markdown.Table: .table
        case is HTMLBlock: .html
        default: .other
        }
    }
}

/// Holds a node of the parsed tree. The tree is immutable once parsed, so it
/// can safely cross concurrency domains.
struct MarkupBox: @unchecked Sendable {
    let markup: Markup
    init(_ markup: Markup) { self.markup = markup }
}

/// Makes heading anchors the way GitHub does: lowercase, punctuation and
/// symbols dropped, each space turned into a hyphen, and `-1`, `-2`… appended
/// to repeated anchors.
struct HeadingSlugger {
    private var occurrences: [String: Int] = [:]

    mutating func slug(for text: String) -> String {
        let base = Self.slug(text)
        var result = base
        if occurrences[result] != nil {
            var count = occurrences[base] ?? 0
            repeat {
                count += 1
                result = "\(base)-\(count)"
            } while occurrences[result] != nil
            occurrences[base] = count
        }
        occurrences[result] = 0
        return result
    }

    /// The anchor of a text, before duplicates are numbered.
    static func slug(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if scalar == " " {
                result.append("-")
            } else if scalar == "-" {
                result.append(scalar)
            } else {
                switch scalar.properties.generalCategory {
                case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                     .nonspacingMark, .spacingMark, .enclosingMark,
                     .decimalNumber, .letterNumber, .otherNumber,
                     .connectorPunctuation:
                    result.append(scalar)
                default:
                    break
                }
            }
        }
        return String(result)
    }

    /// The text of a heading as a reader sees it: no markup, code spans and
    /// link texts included, raw HTML left out.
    static func text(of markup: Markup) -> String {
        switch markup {
        case let text as Text: text.string
        case let code as InlineCode: code.code
        case is SoftBreak, is LineBreak: " "
        case is InlineHTML: ""
        default: markup.children.map(text(of:)).joined()
        }
    }
}
