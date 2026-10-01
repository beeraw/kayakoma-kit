import AppKit
import Markdown

extension NSAttributedString.Key {
    /// Marks a paragraph that `BlockLayoutFragment` decorates (code background,
    /// quote bars, rule); on a table, `TableLayoutFragment` draws the quote bars.
    static let kayakomaDecoration = NSAttributedString.Key("app.kayakoma.decoration")
    /// Marks a code span; its value is an `InlineCodeStyle`, drawn by
    /// `BlockLayoutFragment` as a rounded background.
    static let kayakomaInlineCode = NSAttributedString.Key("app.kayakoma.inlineCode")
    /// Set by `MarkdownView` on links its `isLinkBroken` test marks.
    static let kayakomaBrokenLink = NSAttributedString.Key("app.kayakoma.brokenLink")
}

/// Background of a code span, drawn behind its text with rounded corners.
final class InlineCodeStyle: NSObject {
    let color: NSColor
    let cornerRadius: CGFloat

    init(theme: Theme) {
        color = theme.codeBackgroundColor.nsColor
        // Half the block radius: a code span is only a line high.
        cornerRadius = theme.codeCornerRadius / 2
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? InlineCodeStyle else { return false }
        return color == other.color && cornerRadius == other.cornerRadius
    }

    override var hash: Int { cornerRadius.hashValue }
}

/// Line separator: breaks a line without ending the paragraph, so that a code
/// block or a hard break stays inside one layout fragment.
let lineSeparator = "\u{2028}"

/// Turns one top-level block of the parsed tree into styled paragraphs.
///
/// The output depends only on the block, the theme and the base URL, which is
/// what lets `DocumentRenderer` reuse it while the block's text is unchanged.
struct BlockBuilder {
    let theme: Theme
    /// Directory that relative paths are resolved against.
    let baseURL: URL?
    /// Whether images are decoded while building, rather than when first drawn.
    let loadsImagesSynchronously: Bool

    init(theme: Theme, baseURL: URL?, loadsImagesSynchronously: Bool = false) {
        self.theme = theme
        self.loadsImagesSynchronously = loadsImagesSynchronously
        self.baseURL = baseURL.map { $0.isFileURL ? URL(fileURLWithPath: $0.path, isDirectory: true) : $0 }
    }

    func build(_ markup: Markup) -> NSAttributedString {
        var paragraphs = self.paragraphs(for: markup, in: Context(theme: theme))
        guard !paragraphs.isEmpty else { return NSAttributedString() }
        let outer = markup is Markdown.Paragraph ? theme.paragraphSpacing : theme.blockSpacing
        paragraphs[paragraphs.count - 1].spacingAfter = max(paragraphs[paragraphs.count - 1].spacingAfter, outer)
        return assemble(paragraphs)
    }

    // MARK: - Blocks

    /// Layout state inherited by nested blocks.
    struct Context {
        var indent: CGFloat = 0
        var quoteBars: [CGFloat] = []
        var tight = false
        var listDepth = 0
        var textColor: NSColor

        init(theme: Theme) {
            textColor = theme.textColor.nsColor
        }
    }

    /// One paragraph of output, before it becomes attributed text.
    struct Para {
        var content: NSMutableAttributedString
        var firstIndent: CGFloat
        var headIndent: CGFloat
        var tailIndent: CGFloat = 0
        var tabs: [NSTextTab] = []
        var spacingBefore: CGFloat = 0
        var spacingAfter: CGFloat
        var quoteBars: [CGFloat]
        var codeIndent: CGFloat?
        /// Language label of a code block.
        var codeLabel: String?
        var ruleIndent: CGFloat?
        var table: TableBlock?
        var lineHeightMultiple: CGFloat
        var trailingFont: NSFont
        /// Level of a heading, 0 for other paragraphs.
        var headerLevel = 0
    }

    private func paragraphs(for markup: Markup, in context: Context) -> [Para] {
        switch markup {
        case let heading as Heading:
            let style = theme.headings[level: heading.level]
            let inline = InlineStyle(size: style.size, weight: style.weight.fontWeight, color: context.textColor)
            var paragraph = makeParagraph(inlines(heading.children, inline), context: context, font: font(for: inline))
            paragraph.spacingBefore = style.spacingBefore
            paragraph.spacingAfter = theme.paragraphSpacing
            paragraph.lineHeightMultiple = 1.1
            paragraph.headerLevel = heading.level
            return [paragraph]

        case let paragraph as Markdown.Paragraph:
            let inline = InlineStyle(size: theme.fontSize, weight: .regular, color: context.textColor)
            var result = makeParagraph(inlines(paragraph.children, inline), context: context, font: font(for: inline))
            result.spacingAfter = context.tight ? theme.listItemSpacing : theme.paragraphSpacing
            return [result]

        case let list as UnorderedList:
            return listParagraphs(Array(list.listItems), ordered: nil, in: context)

        case let list as OrderedList:
            return listParagraphs(Array(list.listItems), ordered: Int(list.startIndex), in: context)

        case let quote as BlockQuote:
            var inner = context
            inner.quoteBars.append(context.indent)
            inner.indent += theme.quoteIndent
            inner.tight = false
            inner.textColor = theme.secondaryTextColor.nsColor
            return quote.children.flatMap { paragraphs(for: $0, in: inner) }

        case let code as CodeBlock:
            return [codeParagraph(code.code, infoString: code.language, background: true, context: context)]

        case let html as HTMLBlock:
            let paragraph = codeParagraph(html.rawHTML, infoString: nil, background: false, context: context)
            paragraph.content.addAttribute(.foregroundColor, value: theme.secondaryTextColor.nsColor, range: paragraph.content.fullRange)
            return [paragraph]

        case let table as Markdown.Table:
            return [tableParagraph(table, context: context)]

        case is ThematicBreak:
            let ruleFont = NSFont.systemFont(ofSize: 6)
            var paragraph = makeParagraph(
                NSMutableAttributedString(string: " ", attributes: [.font: ruleFont]),
                context: context,
                font: ruleFont
            )
            paragraph.ruleIndent = context.indent
            paragraph.spacingBefore = theme.blockSpacing / 2
            paragraph.lineHeightMultiple = 1
            return [paragraph]

        default:
            // Other block containers: render their children; leaves: their plain text.
            let children = Array(markup.children)
            if !children.isEmpty, children.allSatisfy({ $0 is BlockMarkup }) {
                return children.flatMap { paragraphs(for: $0, in: context) }
            }
            let inline = InlineStyle(size: theme.fontSize, weight: .regular, color: context.textColor)
            var result = makeParagraph(inlines(markup.children, inline), context: context, font: font(for: inline))
            result.spacingAfter = theme.paragraphSpacing
            return [result]
        }
    }

    private func makeParagraph(_ content: NSMutableAttributedString, context: Context, font: NSFont) -> Para {
        Para(
            content: content,
            firstIndent: context.indent,
            headIndent: context.indent,
            spacingAfter: theme.paragraphSpacing,
            quoteBars: context.quoteBars,
            lineHeightMultiple: theme.lineHeightMultiple,
            trailingFont: font
        )
    }

    /// A code block, highlighted when its info string names a known language.
    private func codeParagraph(_ code: String, infoString: String?, background: Bool, context: Context) -> Para {
        let codeFont = monospacedFont(size: theme.codeFontSize)
        var text = code.replacingOccurrences(of: "\r\n", with: "\n")
        while text.hasSuffix("\n") { text.removeLast() }
        // A line separator is one UTF-16 unit, like the line feed it replaces,
        // so the token ranges found in `text` apply to `content`.
        let content = NSMutableAttributedString(string: text.replacingOccurrences(of: "\n", with: lineSeparator), attributes: [
            .font: codeFont,
            .foregroundColor: context.textColor,
        ])
        if let language = CodeLanguage(infoString: infoString) {
            let runs = SyntaxHighlighter.shared.runs(in: text, language: language)
            if !runs.isEmpty {
                let colors = TokenRole.allCases.map { theme.codeSyntax[$0].nsColor }
                for run in runs {
                    content.addAttribute(.foregroundColor, value: colors[run.role.rawValue], range: run.range)
                }
            }
        }
        let padding = background ? theme.codePadding : 0
        var paragraph = makeParagraph(content, context: context, font: codeFont)
        if background, theme.codeLanguageLabel, let name = CodeLanguage.name(inInfoString: infoString) {
            paragraph.codeLabel = name.lowercased()
        }
        let labelSpace = paragraph.codeLabel.map { CodeLabel(text: $0, theme: theme).extraSpace(padding: padding) } ?? 0
        paragraph.firstIndent = context.indent + padding
        paragraph.headIndent = context.indent + padding
        paragraph.tailIndent = -padding
        paragraph.spacingBefore = padding + labelSpace + 4
        paragraph.spacingAfter = padding + theme.paragraphSpacing
        paragraph.codeIndent = background ? context.indent : nil
        paragraph.lineHeightMultiple = 1.15
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: codeFont]).width
        paragraph.tabs = (1...20).map { NSTextTab(textAlignment: .left, location: context.indent + padding + CGFloat($0) * spaceWidth * 4) }
        return paragraph
    }

    // MARK: - Tables

    /// The whole table as one paragraph of tab-separated values; see `TableBlock`.
    private func tableParagraph(_ table: Markdown.Table, context: Context) -> Para {
        let headerCells = Array(table.head.cells)
        let bodyRows = table.body.rows.map { Array($0.cells) }
        let columnCount = max(table.columnAlignments.count, headerCells.count, bodyRows.map(\.count).max() ?? 0)
        let alignments = (0..<columnCount).map { column in
            Self.alignment(column < table.columnAlignments.count ? table.columnAlignments[column] : nil)
        }

        let bodyFont = font(for: InlineStyle(size: theme.fontSize, weight: .regular, color: context.textColor))
        let separatorAttributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: context.textColor]
        let text = NSMutableAttributedString()
        var rows: [[TableBlock.Cell]] = []
        let allRows: [[Markdown.Table.Cell]] = [headerCells] + bodyRows
        for (rowIndex, cells) in allRows.enumerated() {
            if rowIndex > 0 { text.append(NSAttributedString(string: lineSeparator, attributes: separatorAttributes)) }
            let weight: NSFont.Weight = rowIndex == 0 ? .semibold : .regular
            let style = InlineStyle(size: theme.fontSize, weight: weight, color: context.textColor)
            var row: [TableBlock.Cell] = []
            for column in 0..<columnCount {
                if column > 0 { text.append(NSAttributedString(string: "\t", attributes: separatorAttributes)) }
                let content = column < cells.count ? inlines(cells[column].children, style) : NSMutableAttributedString()
                // Tabs and line breaks would split the copied text into extra cells or rows.
                for separator in ["\t", "\n", lineSeparator] {
                    content.mutableString.replaceOccurrences(of: separator, with: " ", range: content.fullRange)
                }
                let range = NSRange(location: text.length, length: content.length)
                text.append(content)
                let paragraphStyle = NSMutableParagraphStyle()
                let alignment: NSTextAlignment
                switch alignments[column] {
                case .left: alignment = .left
                case .center: alignment = .center
                case .right: alignment = .right
                }
                paragraphStyle.alignment = alignment
                paragraphStyle.lineHeightMultiple = min(theme.lineHeightMultiple, 1.1)
                let styled = NSMutableAttributedString(attributedString: content)
                styled.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraphStyle, range: styled.fullRange)
                // The cell's own layout would underline links; clicks use the
                // paragraph's attributes, which keep the link.
                styled.removeAttribute(NSAttributedString.Key.link, range: styled.fullRange)
                row.append(TableBlock.Cell(range: range, content: styled))
            }
            rows.append(row)
        }

        var paragraph = makeParagraph(text, context: context, font: bodyFont)
        paragraph.spacingBefore = 4
        paragraph.spacingAfter = context.tight ? theme.listItemSpacing : theme.paragraphSpacing
        paragraph.table = TableBlock(
            alignments: alignments,
            rows: rows,
            indent: context.indent,
            minimumLineHeight: ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading),
            minimumContentWidth: theme.fontSize,
            theme: theme
        )
        return paragraph
    }

    static func alignment(_ alignment: Markdown.Table.ColumnAlignment?) -> TableBlock.Alignment {
        switch alignment {
        case .center: .center
        case .right: .right
        case .left, nil: .left
        }
    }

    // MARK: - Lists

    private static let bullets = ["•", "◦", "▪"]

    private func listParagraphs(_ items: [ListItem], ordered start: Int?, in context: Context) -> [Para] {
        let markerFont = font(for: InlineStyle(size: theme.fontSize, weight: .regular, color: context.textColor))
        let markers: [NSAttributedString] = items.enumerated().map { index, item in
            if let checkbox = item.checkbox {
                return CheckboxAttachment.string(checked: checkbox == .checked, size: theme.fontSize)
            }
            let text = start.map { "\($0 + index)." } ?? Self.bullets[context.listDepth % Self.bullets.count]
            return NSAttributedString(string: text, attributes: [.font: markerFont, .foregroundColor: context.textColor])
        }
        let markerGap: CGFloat = 7
        let widest = markers.map { $0.size().width }.max() ?? 0
        let indent = context.indent + max(theme.listIndent, ceil(widest) + markerGap + 4)
        let markerEnd = indent - markerGap
        let tight = Self.isTight(items)

        var result: [Para] = []
        for (item, marker) in zip(items, markers) {
            var inner = context
            inner.indent = indent
            inner.tight = tight
            inner.listDepth += 1
            var itemParagraphs = item.children.flatMap { paragraphs(for: $0, in: inner) }
            if itemParagraphs.isEmpty {
                var empty = makeParagraph(NSMutableAttributedString(), context: inner, font: markerFont)
                empty.spacingAfter = tight ? theme.listItemSpacing : theme.paragraphSpacing
                itemParagraphs = [empty]
            }
            let prefix = NSMutableAttributedString(string: "\t", attributes: [.font: markerFont])
            prefix.append(marker)
            prefix.append(NSAttributedString(string: "\t", attributes: [.font: markerFont]))
            itemParagraphs[0].content.insert(prefix, at: 0)
            itemParagraphs[0].firstIndent = context.indent
            itemParagraphs[0].tabs = [
                NSTextTab(textAlignment: .right, location: markerEnd),
                NSTextTab(textAlignment: .left, location: indent),
            ]
            result.append(contentsOf: itemParagraphs)
        }
        if let last = result.indices.last {
            result[last].spacingAfter = max(result[last].spacingAfter, context.tight ? theme.listItemSpacing : theme.paragraphSpacing)
        }
        return result
    }

    /// A list is loose when a blank line separates two of its items or two
    /// blocks inside an item (CommonMark's definition).
    private static func isTight(_ items: [ListItem]) -> Bool {
        func separated(_ a: Markup, _ b: Markup) -> Bool {
            guard let end = a.range?.upperBound.line, let start = b.range?.lowerBound.line else { return false }
            return start > end + 1
        }
        for (a, b) in zip(items, items.dropFirst()) where separated(a, b) { return false }
        for item in items {
            let children = Array(item.children)
            for (a, b) in zip(children, children.dropFirst()) where separated(a, b) { return false }
        }
        return true
    }

    // MARK: - Inlines

    struct InlineStyle {
        var size: CGFloat
        var weight: NSFont.Weight
        var italic = false
        var strikethrough = false
        var color: NSColor
        var link: URL?
    }

    private func inlines(_ children: some Sequence<Markup>, _ style: InlineStyle) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            result.append(inline(child, style))
        }
        return result
    }

    private func inline(_ markup: Markup, _ style: InlineStyle) -> NSAttributedString {
        switch markup {
        case let node as Text:
            return text(node.string, style)
        case is SoftBreak:
            return text(" ", style)
        case is LineBreak:
            return text(lineSeparator, style)
        case let code as InlineCode:
            var attributes = attributes(style)
            attributes[.font] = monospacedFont(size: theme.codeFontSize * style.size / theme.fontSize)
            attributes[.kayakomaInlineCode] = InlineCodeStyle(theme: theme)
            return NSAttributedString(string: "\u{2009}\(code.code)\u{2009}", attributes: attributes)
        case let emphasis as Emphasis:
            var inner = style
            inner.italic = true
            return inlines(emphasis.children, inner)
        case let strong as Strong:
            var inner = style
            inner.weight = style.weight.rawValue >= NSFont.Weight.semibold.rawValue ? .heavy : .bold
            return inlines(strong.children, inner)
        case let strike as Strikethrough:
            var inner = style
            inner.strikethrough = true
            return inlines(strike.children, inner)
        case let link as Link:
            var inner = style
            inner.link = link.destination.flatMap(resolve)
            return inlines(link.children, inner)
        case let image as Markdown.Image:
            return imageString(source: image.source, alt: image.plainText, style: style)
        case let html as InlineHTML:
            return text(html.rawHTML, style)
        case let symbol as SymbolLink:
            var attributes = attributes(style)
            attributes[.font] = monospacedFont(size: theme.codeFontSize)
            return NSAttributedString(string: symbol.destination ?? "", attributes: attributes)
        default:
            if markup.childCount > 0 {
                return inlines(markup.children, style)
            }
            return text(markup.format(), style)
        }
    }

    private func text(_ string: String, _ style: InlineStyle) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(style))
    }

    private func attributes(_ style: InlineStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style),
            .foregroundColor: style.color,
        ]
        if style.strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = style.link {
            attributes[.link] = link
            attributes[.foregroundColor] = theme.linkColor.nsColor
        }
        return attributes
    }

    /// Resolves a link destination against the base URL; fragment-only links
    /// stay relative so that the view can recognise them.
    private func resolve(_ destination: String) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return URL(string: trimmed) }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(["#", "?"])) ?? trimmed
        return URL(string: encoded, relativeTo: baseURL)?.absoluteURL ?? URL(string: encoded)
    }

    // MARK: - Images

    private func imageString(source: String?, alt: String, style: InlineStyle) -> NSAttributedString {
        if let url = localImageURL(source), let info = ImageStore.shared.info(for: url),
           let attachment = imageAttachment(info) {
            var attributes = attributes(style)
            attributes[.attachment] = attachment
            return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
        }
        let label = alt.isEmpty ? (source.map { ($0 as NSString).lastPathComponent } ?? "") : alt
        let result = NSMutableAttributedString(attachment: PlaceholderAttachment(size: style.size))
        var attributes = attributes(style)
        attributes[.foregroundColor] = theme.secondaryTextColor.nsColor
        result.addAttributes(attributes, range: result.fullRange)
        result.append(NSAttributedString(string: "\u{2009}" + label, attributes: attributes))
        return result
    }

    private func imageAttachment(_ info: ImageStore.Info) -> ImageAttachment? {
        guard loadsImagesSynchronously else {
            return ImageAttachment(info: info, image: ImageStore.shared.cachedImage(for: info.key))
        }
        return ImageStore.shared.image(for: info).map { ImageAttachment(info: info, image: $0) }
    }

    /// The file an image source points to; `nil` for remote images and for
    /// relative paths when there is no base URL.
    private func localImageURL(_ source: String?) -> URL? {
        guard let source = source?.trimmingCharacters(in: .whitespaces), !source.isEmpty else { return nil }
        if let url = URL(string: source), let scheme = url.scheme {
            return scheme == "file" ? url : nil
        }
        let path = source.removingPercentEncoding ?? source
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("~") { return nil }
        guard let baseURL, baseURL.isFileURL else { return nil }
        return URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }

    // MARK: - Fonts

    private func font(for style: InlineStyle) -> NSFont {
        let base: NSFont
        if let family = theme.fontFamily {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: family,
                .traits: [NSFontDescriptor.TraitKey.weight: style.weight.rawValue],
            ])
            base = NSFont(descriptor: descriptor, size: style.size) ?? .systemFont(ofSize: style.size, weight: style.weight)
        } else {
            base = .systemFont(ofSize: style.size, weight: style.weight)
        }
        guard style.italic else { return base }
        let italic = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: italic, size: style.size) ?? base
    }

    private func monospacedFont(size: CGFloat) -> NSFont {
        if let family = theme.codeFontFamily,
           let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Assembly

    private func assemble(_ paragraphs: [Para]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let next = index + 1 < paragraphs.count ? paragraphs[index + 1] : nil
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = paragraph.firstIndent
            style.headIndent = paragraph.headIndent
            style.tailIndent = paragraph.tailIndent
            style.tabStops = paragraph.tabs
            style.lineHeightMultiple = paragraph.lineHeightMultiple
            style.headerLevel = paragraph.headerLevel
            // Inside a block, the gap between two paragraphs is the larger of
            // the two requested spacings, and it lives on the first one.
            style.paragraphSpacingBefore = index == 0 ? paragraph.spacingBefore : 0
            style.paragraphSpacing = max(paragraph.spacingAfter, next?.spacingBefore ?? 0)
            if paragraph.table != nil {
                // TextKit still lays the table's tab-separated text out behind
                // the grid, and a taller layout than the grid pushes the next
                // paragraph down: keep its lines one point high and unwrapped.
                style.minimumLineHeight = 1
                style.maximumLineHeight = 1
                style.lineHeightMultiple = 1
                style.lineBreakMode = .byClipping
            }

            let start = result.length
            result.append(paragraph.content)
            let lastAttributes: [NSAttributedString.Key: Any] = paragraph.content.length > 0
                ? paragraph.content.attributes(at: paragraph.content.length - 1, effectiveRange: nil)
                    .filter { $0.key == .font || $0.key == .foregroundColor }
                : [.font: paragraph.trailingFont]
            result.append(NSAttributedString(string: "\n", attributes: lastAttributes))
            let range = NSRange(location: start, length: result.length - start)
            result.addAttribute(.paragraphStyle, value: style, range: range)

            if let table = paragraph.table {
                result.addAttribute(.kayakomaTable, value: table, range: range)
            }
            if !paragraph.quoteBars.isEmpty || paragraph.codeIndent != nil || paragraph.ruleIndent != nil {
                let continuing = next.map { Self.commonPrefix(paragraph.quoteBars, $0.quoteBars) } ?? 0
                let decoration = BlockDecoration(
                    quoteBars: paragraph.quoteBars,
                    continuingBars: continuing,
                    spacingAfter: style.paragraphSpacing,
                    codeIndent: paragraph.codeIndent,
                    codeLabel: paragraph.codeLabel,
                    ruleIndent: paragraph.ruleIndent,
                    theme: theme
                )
                result.addAttribute(.kayakomaDecoration, value: decoration, range: range)
            }
        }
        return result
    }

    private static func commonPrefix(_ a: [CGFloat], _ b: [CGFloat]) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }
}

extension NSAttributedString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }
}
