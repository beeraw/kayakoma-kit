import AppKit

/// What a paragraph needs drawn around its text, attached to the paragraph
/// under `.kayakomaDecoration`.
final class BlockDecoration: NSObject {
    /// Horizontal positions of the quote bars, outermost first, measured like indents.
    let quoteBars: [CGFloat]
    /// How many of the bars go on into the next paragraph, and so cover the gap below.
    let continuingBars: Int
    let spacingAfter: CGFloat
    /// Left edge of a code block background.
    let codeIndent: CGFloat?
    /// Language label drawn in the top right corner of a code block.
    let codeLabel: CodeLabel?
    /// Left edge of a thematic break.
    let ruleIndent: CGFloat?

    let barWidth: CGFloat
    let codePadding: CGFloat
    let codeCornerRadius: CGFloat
    let barColor: NSColor
    let codeBackgroundColor: NSColor
    let ruleColor: NSColor

    init(
        quoteBars: [CGFloat], continuingBars: Int, spacingAfter: CGFloat,
        codeIndent: CGFloat?, codeLabel: String?, ruleIndent: CGFloat?, theme: Theme
    ) {
        self.quoteBars = quoteBars
        self.continuingBars = continuingBars
        self.spacingAfter = spacingAfter
        self.codeIndent = codeIndent
        self.codeLabel = codeLabel.map { CodeLabel(text: $0, theme: theme) }
        self.ruleIndent = ruleIndent
        barWidth = theme.quoteBarWidth
        codePadding = theme.codePadding
        codeCornerRadius = theme.codeCornerRadius
        barColor = theme.quoteBarColor.nsColor
        codeBackgroundColor = theme.codeBackgroundColor.nsColor
        ruleColor = theme.ruleColor.nsColor
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BlockDecoration else { return false }
        return quoteBars == other.quoteBars && continuingBars == other.continuingBars
            && spacingAfter == other.spacingAfter && codeIndent == other.codeIndent
            && codeLabel == other.codeLabel && ruleIndent == other.ruleIndent && barWidth == other.barWidth
            && codePadding == other.codePadding && codeCornerRadius == other.codeCornerRadius
            && barColor == other.barColor && codeBackgroundColor == other.codeBackgroundColor
            && ruleColor == other.ruleColor
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(quoteBars)
        hasher.combine(continuingBars)
        hasher.combine(codeIndent)
        hasher.combine(codeLabel?.text)
        hasher.combine(ruleIndent)
        return hasher.finalize()
    }

    /// Space between the top of a code block background and its first line.
    var codeTopPadding: CGFloat {
        codePadding + (codeLabel?.extraSpace(padding: codePadding) ?? 0)
    }
}

/// The language of a code block, drawn small in its top right corner.
///
/// It is drawn as glyph outlines rather than text, so that it is never
/// selected, copied, found or extracted from a PDF with the code.
struct CodeLabel: Equatable {
    let text: String
    let font: NSFont
    let color: NSColor

    /// Space between the top edge of the background and the label's line.
    static let inset: CGFloat = 5

    init(text: String, theme: Theme) {
        self.text = text
        font = .systemFont(ofSize: max(round(theme.codeFontSize * 0.8), 8), weight: .medium)
        color = theme.secondaryTextColor.nsColor
    }

    var height: CGFloat { ceil(font.ascender - font.descender) }

    /// Space added above the first line of code so that the label never
    /// overlaps it, on top of the block's padding.
    func extraSpace(padding: CGFloat) -> CGFloat {
        max(0, Self.inset + height - padding)
    }

    /// Fills the label's outlines with its right edge at `right` and the top
    /// of its line at `top`, in the current flipped graphics context.
    func draw(right: CGFloat, top: CGFloat) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let origin = CGPoint(x: right - width, y: top + ceil(font.ascender))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            let runFont = (attributes?[.font] as? NSFont) ?? font
            for (glyph, position) in zip(glyphs, positions) {
                // Glyph outlines point up; the context's y axis points down.
                var transform = CGAffineTransform(translationX: origin.x + position.x, y: origin.y - position.y).scaledBy(x: 1, y: -1)
                if let outline = CTFontCreatePathForGlyph(runFont, glyph, &transform) {
                    path.addPath(outline)
                }
            }
        }
        color.setFill()
        NSBezierPath(cgPath: path).fill()
    }
}

/// Layout fragment that draws a paragraph's decoration and the rounded
/// backgrounds of its code spans behind its text.
final class BlockLayoutFragment: NSTextLayoutFragment {
    let decoration: BlockDecoration?

    /// A code span of the paragraph: its range in the paragraph, style and font.
    private struct InlineCode {
        let range: NSRange
        let style: InlineCodeStyle
        let font: NSFont
    }

    /// The paragraph's code spans, read once: once the text storage is
    /// edited, an outdated fragment can still be asked for its bounds, and
    /// its paragraph's text may then no longer be readable.
    private let inlineCode: [InlineCode]

    init(textElement: NSTextElement, range: NSTextRange?, decoration: BlockDecoration?) {
        self.decoration = decoration
        var inlineCode: [InlineCode] = []
        if let string = (textElement as? NSTextParagraph)?.attributedString {
            string.enumerateAttribute(.kayakomaInlineCode, in: string.fullRange) { value, range, _ in
                guard let style = value as? InlineCodeStyle else { return }
                let font = string.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                    ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                inlineCode.append(InlineCode(range: range, style: style, font: font))
            }
        }
        self.inlineCode = inlineCode
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var renderingSurfaceBounds: CGRect {
        shapes().reduce(super.renderingSurfaceBounds) { $0.union($1.rect) }
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        drawBackgrounds(at: point, in: context)
        super.draw(at: point, in: context)
    }

    /// Draws everything but the text: code backgrounds, quote bars, rules.
    func drawBackgrounds(at point: CGPoint, in context: CGContext) {
        let shapes = shapes()
        guard !shapes.isEmpty else { return }
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        for shape in shapes {
            let rect = shape.rect.offsetBy(dx: point.x, dy: point.y)
            shape.color.setFill()
            if shape.radius > 0 {
                NSBezierPath(roundedRect: rect, xRadius: shape.radius, yRadius: shape.radius).fill()
            } else {
                rect.fill()
            }
            if let label = shape.label {
                label.draw(right: rect.maxX - (decoration?.codePadding ?? 0), top: rect.minY + CodeLabel.inset)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Vertical extent of the code block background above and below the
    /// text, so that a page break does not cut the padding (and the language
    /// label) off its first or last line.
    var codePadding: (top: CGFloat, bottom: CGFloat)? {
        guard let decoration, decoration.codeIndent != nil else { return nil }
        return (decoration.codeTopPadding, decoration.codePadding)
    }

    private struct Shape {
        let rect: CGRect
        let color: NSColor
        let radius: CGFloat
        /// Label drawn in the shape's top right corner.
        var label: CodeLabel?
        var isCodeBackground = false
    }

    /// The code block background, in the fragment's coordinates.
    var codeBackground: CGRect? {
        blockShapes().first(where: \.isCodeBackground)?.rect
    }

    /// Shapes to fill, in the fragment's coordinate space, back to front.
    private func shapes() -> [Shape] {
        blockShapes() + inlineCodeShapes()
    }

    private func blockShapes() -> [Shape] {
        // The paragraph that ends the document is followed by the empty line
        // TextKit adds after the last line break; it shows nothing.
        guard let decoration, let first = textLineFragments.first,
              let last = textLineFragments.last(where: { $0.characterRange.length > 0 }) ?? textLineFragments.last
        else { return [] }
        let textTop = first.typographicBounds.minY
        let textBottom = last.typographicBounds.maxY
        let container = textLayoutManager?.textContainer
        let padding = container?.lineFragmentPadding ?? 0
        let containerWidth = container?.size.width ?? layoutFragmentFrame.width
        let origin = layoutFragmentFrame.minX
        /// Converts an indent into the fragment's horizontal coordinates.
        func x(_ indent: CGFloat) -> CGFloat { padding + indent - origin }
        let right = containerWidth - padding - origin

        var shapes: [Shape] = []
        for (index, bar) in decoration.quoteBars.enumerated() {
            let bottom = textBottom + (index < decoration.continuingBars ? decoration.spacingAfter : 0)
            shapes.append(Shape(
                rect: CGRect(x: x(bar), y: textTop, width: decoration.barWidth, height: bottom - textTop),
                color: decoration.barColor,
                radius: 0
            ))
        }
        if let indent = decoration.codeIndent {
            let top = decoration.codeTopPadding
            let bottom = decoration.codePadding
            shapes.append(Shape(
                rect: CGRect(x: x(indent), y: textTop - top, width: right - x(indent), height: textBottom - textTop + top + bottom),
                color: decoration.codeBackgroundColor,
                radius: decoration.codeCornerRadius,
                label: decoration.codeLabel,
                isCodeBackground: true
            ))
        }
        if let indent = decoration.ruleIndent {
            let middle = round((textTop + textBottom) / 2)
            shapes.append(Shape(
                rect: CGRect(x: x(indent), y: middle, width: right - x(indent), height: 1),
                color: decoration.ruleColor,
                radius: 0
            ))
        }
        return shapes
    }

    /// One rounded rectangle per code span and line, from the line's
    /// baseline and the span's font, so that it hugs the text whatever the
    /// line height.
    private func inlineCodeShapes() -> [Shape] {
        var shapes: [Shape] = []
        for span in inlineCode {
            let style = span.style
            let font = span.font
            for line in textLineFragments {
                guard let overlap = span.range.intersection(line.characterRange), overlap.length > 0 else { continue }
                let bounds = line.typographicBounds
                let start = line.locationForCharacter(at: overlap.location).x
                let end = line.locationForCharacter(at: overlap.upperBound).x
                let baseline = bounds.minY + line.glyphOrigin.y
                let top = floor(baseline - font.ascender - 1)
                let bottom = ceil(baseline - font.descender + 1)
                let rect = CGRect(x: bounds.minX + start, y: top, width: end - start, height: bottom - top)
                guard rect.width > 0 else { continue }
                shapes.append(Shape(rect: rect, color: style.color, radius: min(style.cornerRadius, rect.height / 3)))
            }
        }
        return shapes
    }
}

/// Layout fragment of a table: places the cells of a `TableBlock` in a grid
/// and draws them, instead of laying the paragraph's text out in lines.
///
/// The fragment reports the grid's height as its frame, so the paragraphs
/// below are placed after it, and it has no line fragments: TextKit therefore
/// neither draws the tab-separated text nor highlights it. `MarkdownTextView`
/// maps clicks, selection and find results through `characterIndex(at:)` and
/// `rects(for:)` instead.
final class TableLayoutFragment: NSTextLayoutFragment {
    let table: TableBlock
    let decoration: BlockDecoration?
    /// The paragraph's style, read once: once the text storage is edited, an
    /// outdated fragment can still be asked for its frame, and its paragraph's
    /// text may then no longer be readable.
    private let paragraphStyle: NSParagraphStyle?

    init(textElement: NSTextElement, range: NSTextRange?, table: TableBlock, decoration: BlockDecoration?) {
        self.table = table
        self.decoration = decoration
        let text = (textElement as? NSTextParagraph)?.attributedString
        paragraphStyle = text.flatMap { $0.length > 0 ? $0.attribute(.paragraphStyle, at: 0, effectiveRange: nil) : nil } as? NSParagraphStyle
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: Layout

    /// Where the table sits in the fragment, and its geometry at the current width.
    struct Placement {
        let origin: CGPoint
        let geometry: TableGeometry
        let spacingAfter: CGFloat
    }

    var placement: Placement {
        let container = textLayoutManager?.textContainer
        let padding = container?.lineFragmentPadding ?? 0
        let containerWidth = container?.size.width ?? 0
        let origin = super.layoutFragmentFrame.minX
        let style = paragraphStyle
        let left = padding + table.indent - origin
        let available = max(containerWidth - padding - origin - left, 0)
        return Placement(
            origin: CGPoint(x: left, y: style?.paragraphSpacingBefore ?? 0),
            geometry: table.geometry(available: floor(available)),
            spacingAfter: style?.paragraphSpacing ?? 0
        )
    }

    override var layoutFragmentFrame: CGRect {
        let frame = super.layoutFragmentFrame
        let placement = placement
        let size = placement.geometry.size
        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: placement.origin.x + size.width,
            height: placement.origin.y + size.height + placement.spacingAfter
        )
    }

    override var renderingSurfaceBounds: CGRect {
        let placement = placement
        var bounds = CGRect(origin: placement.origin, size: placement.geometry.size)
        if let bar = decoration?.quoteBars.first {
            bounds = bounds.union(CGRect(x: bar - table.indent + placement.origin.x, y: 0, width: 1, height: 1))
        }
        return bounds.insetBy(dx: -1, dy: -1).union(CGRect(origin: .zero, size: layoutFragmentFrame.size))
    }

    override var textLineFragments: [NSTextLineFragment] {
        []
    }

    // MARK: Drawing

    override func draw(at point: CGPoint, in context: CGContext) {
        draw(at: point, in: context, rows: nil)
    }

    /// Top edge of each row, then the bottom edge of the last one, in the
    /// fragment's coordinates; every edge is a border `TableBlock.borderWidth` high.
    var rowEdges: [CGFloat] {
        let placement = placement
        return placement.geometry.rowEdges.map { $0 + placement.origin.y }
    }

    /// Draws the table, or only some of its rows (header row is 0) where a
    /// page break splits it: their backgrounds, text and borders (in the
    /// `all` style, the vertical borders between them too). Quote bars are drawn in full.
    func draw(at point: CGPoint, in context: CGContext, rows selected: IndexSet?) {
        let placement = placement
        let geometry = placement.geometry
        let origin = CGPoint(x: point.x + placement.origin.x, y: point.y + placement.origin.y)
        let size = geometry.size
        let border = TableBlock.borderWidth
        let rows = selected ?? IndexSet(geometry.cells.indices)
        guard let firstRow = rows.first, let lastRow = rows.last else { return }
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        if let decoration {
            decoration.barColor.setFill()
            for (index, bar) in decoration.quoteBars.enumerated() {
                let x = origin.x + bar - table.indent
                let bottom = size.height + (index < decoration.continuingBars ? placement.spacingAfter : 0)
                CGRect(x: x, y: origin.y, width: decoration.barWidth, height: bottom).fill()
            }
        }

        // Backgrounds.
        for row in rows {
            let color: NSColor? = row == 0 ? table.headerBackgroundColor
                : (row % 2 == 0 ? table.alternateRowBackgroundColor : nil)
            guard let color else { continue }
            color.setFill()
            // With a full grid the background sits inside the box; with horizontal
            // rules only, it spans the width and starts under the previous rule.
            let grid = table.borders == .all
            let top = geometry.rowEdges[row] + (grid || row > 0 ? border : 0)
            let inset = grid ? border : 0
            CGRect(x: origin.x + inset, y: origin.y + top, width: size.width - 2 * inset, height: geometry.rowEdges[row + 1] - top)
                .fill(using: .sourceOver)
        }

        // Text, clipped to its cell so that nothing can spill into a neighbour.
        for row in rows {
            for (column, cell) in geometry.cells[row].enumerated() where cell.cell.content.length > 0 {
                let frame = geometry.cellFrame(row: row, column: column).offsetBy(dx: origin.x, dy: origin.y)
                context.saveGState()
                context.clip(to: frame)
                cell.draw(at: CGPoint(x: origin.x + cell.origin.x, y: origin.y + cell.origin.y), in: context)
                context.restoreGState()
            }
        }

        // Borders: filled rectangles on whole points stay sharp.
        table.borderColor.setFill()
        if table.borders == .horizontal {
            // A rule under each drawn row; the top edge and the sides stay empty.
            for row in rows {
                CGRect(x: origin.x, y: origin.y + geometry.rowEdges[row + 1], width: size.width, height: border)
                    .fill(using: .sourceOver)
            }
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        let top = geometry.rowEdges[firstRow]
        let bottom = geometry.rowEdges[lastRow + 1] + border
        for x in geometry.columnEdges {
            CGRect(x: origin.x + x, y: origin.y + top, width: border, height: bottom - top).fill(using: .sourceOver)
        }
        let horizontal = Set(rows.flatMap { [$0, $0 + 1] }).sorted()
        for y in horizontal.map({ geometry.rowEdges[$0] }) {
            // Vertical lines already cover the crossings; skip them so that
            // translucent colours do not darken there.
            for column in geometry.columnEdges.indices.dropLast() {
                let left = geometry.columnEdges[column] + border
                let right = geometry.columnEdges[column + 1]
                CGRect(x: origin.x + left, y: origin.y + y, width: right - left, height: border).fill(using: .sourceOver)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Characters

    /// Index in the paragraph of the character boundary nearest to `point`,
    /// given in the fragment's coordinates.
    func characterIndex(at point: CGPoint) -> Int {
        let placement = placement
        let geometry = placement.geometry
        let local = CGPoint(x: point.x - placement.origin.x, y: point.y - placement.origin.y)
        let (row, column) = geometry.cellPosition(at: local)
        guard row < geometry.cells.count, column < geometry.cells[row].count else { return 0 }
        let cell = geometry.cells[row][column]
        let index = cell.characterIndex(at: CGPoint(x: local.x - cell.origin.x, y: local.y - cell.origin.y))
        return cell.cell.range.location + index
    }

    /// Whether a point, in the fragment's coordinates, is on the table itself.
    func containsTable(_ point: CGPoint) -> Bool {
        let placement = placement
        return CGRect(origin: placement.origin, size: placement.geometry.size).contains(point)
    }

    /// Index in the paragraph of the character drawn under `point`, if any.
    func character(at point: CGPoint) -> Int? {
        let index = characterIndex(at: point)
        for candidate in [index, index - 1] where candidate >= 0 {
            if rects(for: NSRange(location: candidate, length: 1)).contains(where: { $0.contains(point) }) {
                return candidate
            }
        }
        return nil
    }

    /// Draws the text of a range of the paragraph, and nothing else, with the
    /// fragment's top left corner at `point`; the find indicator uses it.
    func drawText(in range: NSRange, at point: CGPoint, in context: CGContext) {
        let placement = placement
        for cells in placement.geometry.cells {
            for cell in cells {
                guard let overlap = cell.cell.range.intersection(range), overlap.length > 0 else { continue }
                let origin = CGPoint(x: point.x + placement.origin.x + cell.origin.x, y: point.y + placement.origin.y + cell.origin.y)
                let local = NSRange(location: overlap.location - cell.cell.range.location, length: overlap.length)
                context.saveGState()
                context.clip(to: cell.rects(for: local).map { $0.offsetBy(dx: origin.x, dy: origin.y) })
                cell.draw(at: origin, in: context)
                context.restoreGState()
            }
        }
    }

    /// Rectangles covering a range of the paragraph, in the fragment's coordinates.
    /// Tabs and row separators between selected cells are not drawn.
    func rects(for range: NSRange) -> [CGRect] {
        let placement = placement
        var rects: [CGRect] = []
        for cells in placement.geometry.cells {
            for cell in cells {
                guard let overlap = cell.cell.range.intersection(range), overlap.length > 0 else { continue }
                let local = NSRange(location: overlap.location - cell.cell.range.location, length: overlap.length)
                for rect in cell.rects(for: local) {
                    rects.append(rect.offsetBy(dx: placement.origin.x + cell.origin.x, dy: placement.origin.y + cell.origin.y))
                }
            }
        }
        return rects
    }
}

/// Gives decorated paragraphs a `BlockLayoutFragment` and tables a `TableLayoutFragment`.
final class LayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 {
            let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
            let decoration = attributes[.kayakomaDecoration] as? BlockDecoration
            if let table = attributes[.kayakomaTable] as? TableBlock {
                return TableLayoutFragment(textElement: textElement, range: textElement.elementRange, table: table, decoration: decoration)
            }
            if decoration != nil || Self.hasInlineCode(paragraph.attributedString) {
                return BlockLayoutFragment(textElement: textElement, range: textElement.elementRange, decoration: decoration)
            }
        }
        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }

    private static func hasInlineCode(_ string: NSAttributedString) -> Bool {
        var found = false
        string.enumerateAttribute(.kayakomaInlineCode, in: string.fullRange) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }
}
