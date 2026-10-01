import AppKit

extension NSAttributedString.Key {
    /// Marks the paragraph that holds a table; its value is a `TableBlock`.
    static let kayakomaTable = NSAttributedString.Key("app.kayakoma.table")
}

/// A table, attached to the single paragraph that holds its text.
///
/// The paragraph's text is the table as tab-separated values: cells are
/// separated by tabs and rows by line separators, so selecting and copying a
/// table gives text that pastes into a spreadsheet, and the find bar searches
/// the cells. `TableLayoutFragment` does not lay that text out as lines: it
/// places every cell in a grid and draws it there.
final class TableBlock: NSObject {
    enum Alignment: Equatable {
        case left, center, right
    }

    struct Cell {
        /// Range of the cell's text in the paragraph.
        let range: NSRange
        /// The cell's styled text, with its alignment.
        let content: NSAttributedString
    }

    let alignments: [Alignment]
    /// Header row first; every row has one cell per column.
    let rows: [[Cell]]
    /// Left edge of the table, measured like an indent.
    let indent: CGFloat
    /// Height of an empty cell's text.
    let minimumLineHeight: CGFloat
    /// Narrowest width of a column's text when the table has to be squeezed.
    let minimumContentWidth: CGFloat

    let padding: Theme.Margins
    let borders: Theme.TableBorders
    let borderColor: NSColor
    let headerBackgroundColor: NSColor
    let alternateRowBackgroundColor: NSColor?

    static let borderWidth: CGFloat = 1

    init(
        alignments: [Alignment],
        rows: [[Cell]],
        indent: CGFloat,
        minimumLineHeight: CGFloat,
        minimumContentWidth: CGFloat,
        theme: Theme
    ) {
        self.alignments = alignments
        self.rows = rows
        self.indent = indent
        self.minimumLineHeight = minimumLineHeight
        self.minimumContentWidth = minimumContentWidth
        padding = theme.tableCellPadding
        borders = theme.tableBorders
        borderColor = theme.tableBorderColor.nsColor
        headerBackgroundColor = theme.tableHeaderBackgroundColor.nsColor
        alternateRowBackgroundColor = theme.tableAlternateRowBackgroundColor?.nsColor
    }

    var columnCount: Int { alignments.count }

    /// Whether one of the cells shows the image stored under `key`.
    func containsImage(_ key: ImageStore.Key) -> Bool {
        rows.joined().contains { cell in
            var found = false
            cell.content.enumerateAttribute(.attachment, in: cell.content.fullRange) { value, _, stop in
                if (value as? ImageAttachment)?.info.key == key { found = true; stop.pointee = true }
            }
            return found
        }
    }

    // MARK: - Column widths

    /// Widths of the columns, borders and padding included, before any fitting.
    private(set) lazy var measuredWidths: (natural: [CGFloat], minimum: [CGFloat]) = {
        let extra = 2 * padding.horizontal + Self.borderWidth
        var natural = [CGFloat](repeating: extra + minimumContentWidth, count: columnCount)
        var minimum = natural
        for row in rows {
            for (column, cell) in row.enumerated() {
                // One point of slack: string measurement and TextKit may round differently.
                natural[column] = max(natural[column], ceil(Self.width(of: cell.content)) + 1 + extra)
                minimum[column] = max(minimum[column], ceil(Self.widestWord(in: cell.content)) + 1 + extra)
            }
        }
        return (natural, zip(natural, minimum).map { min($0, $1) })
    }()

    /// Column widths that fit `available` points when possible.
    ///
    /// Columns keep their natural width when the table fits. Otherwise columns
    /// that fit in a fair share of the line keep their natural width, and the
    /// others keep at least their widest word, the remaining space going to
    /// them in proportion to what they lack, so long text wraps first.
    /// A word wider than an equal share of the line does not count as a
    /// minimum: it breaks, rather than squeezing the other columns. When even
    /// the minimums do not fit, columns shrink in proportion and words break,
    /// down to `floor` points; only then may the table overflow.
    static func fitColumns(natural: [CGFloat], minimum: [CGFloat], available: CGFloat, floor floorWidth: CGFloat) -> [CGFloat] {
        guard !natural.isEmpty else { return [] }
        let share = max(floorWidth, floor(available / CGFloat(natural.count)))
        let minimum = zip(natural, minimum).map { min($0, $1, max(share, floorWidth)) }
        let naturalTotal = natural.reduce(0, +)
        let minimumTotal = minimum.reduce(0, +)
        if naturalTotal <= available { return natural }
        if minimumTotal <= available {
            // Short columns first: a column that fits in a fair share of the line
            // keeps its natural width, so only the long ones wrap.
            var pinned = Set<Int>()
            var remaining = available
            var changed = true
            while changed {
                changed = false
                let free = natural.indices.filter { !pinned.contains($0) }
                guard !free.isEmpty else { break }
                let fair = remaining / CGFloat(free.count)
                for index in free where natural[index] <= fair {
                    pinned.insert(index)
                    remaining -= natural[index]
                    changed = true
                }
            }
            let free = natural.indices.filter { !pinned.contains($0) }
            let freeMinimumTotal = free.reduce(0) { $0 + minimum[$1] }
            guard freeMinimumTotal <= remaining else {
                // Pinning would starve the others: spread over every column instead.
                let share = (available - minimumTotal) / max(naturalTotal - minimumTotal, 1)
                return zip(natural, minimum).map { natural, minimum in
                    floor(minimum + (natural - minimum) * share)
                }
            }
            let freeNaturalTotal = free.reduce(0) { $0 + natural[$1] }
            let share = (remaining - freeMinimumTotal) / max(freeNaturalTotal - freeMinimumTotal, 1)
            return natural.indices.map { index in
                pinned.contains(index) ? natural[index] : floor(minimum[index] + (natural[index] - minimum[index]) * share)
            }
        }
        let scale = max(available, 0) / max(minimumTotal, 1)
        return minimum.map { max(floorWidth, floor($0 * scale)) }
    }

    private static func width(of text: NSAttributedString) -> CGFloat {
        guard text.length > 0 else { return 0 }
        return text.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width
    }

    private static func widestWord(in text: NSAttributedString) -> CGFloat {
        let string = text.string as NSString
        var widest: CGFloat = 0
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byWords) { _, range, _, _ in
            widest = max(widest, width(of: text.attributedSubstring(from: range)))
        }
        return widest
    }

    // MARK: - Geometry

    private var cachedGeometry: TableGeometry?

    /// Layout of the table when `available` points are free on its line.
    func geometry(available: CGFloat) -> TableGeometry {
        if let cachedGeometry, cachedGeometry.available == available { return cachedGeometry }
        let geometry = TableGeometry(table: self, available: available)
        cachedGeometry = geometry
        return geometry
    }
}

/// Positions of a table's columns, rows and cell text for one available width.
/// Coordinates are relative to the table's top left corner, y downwards.
final class TableGeometry {
    let available: CGFloat
    /// Left edge of each column, then the right edge of the last one.
    let columnEdges: [CGFloat]
    /// Top edge of each row, then the bottom edge of the last one.
    let rowEdges: [CGFloat]
    /// One layout per cell, by row then column.
    let cells: [[CellLayout]]

    var size: CGSize {
        CGSize(width: (columnEdges.last ?? 0) + TableBlock.borderWidth, height: (rowEdges.last ?? 0) + TableBlock.borderWidth)
    }

    init(table: TableBlock, available: CGFloat) {
        self.available = available
        let border = TableBlock.borderWidth
        let padding = table.padding
        let floorWidth = border + 2 * padding.horizontal + table.minimumContentWidth
        let widths = TableBlock.fitColumns(
            natural: table.measuredWidths.natural,
            minimum: table.measuredWidths.minimum,
            available: available - border,
            floor: floorWidth
        )
        var columnEdges: [CGFloat] = [0]
        for width in widths { columnEdges.append(columnEdges[columnEdges.count - 1] + width) }

        var rowEdges: [CGFloat] = [0]
        var cells: [[CellLayout]] = []
        for row in table.rows {
            let top = rowEdges[rowEdges.count - 1]
            var layouts: [CellLayout] = []
            var height = table.minimumLineHeight
            for (column, cell) in row.enumerated() {
                let origin = CGPoint(x: columnEdges[column] + border + padding.horizontal, y: top + border + padding.vertical)
                let layout = CellLayout(cell: cell, origin: origin, width: max(widths[column] - border - 2 * padding.horizontal, 1))
                height = max(height, layout.height)
                layouts.append(layout)
            }
            cells.append(layouts)
            rowEdges.append(top + border + 2 * padding.vertical + ceil(height))
        }
        self.columnEdges = columnEdges
        self.rowEdges = rowEdges
        self.cells = cells
    }

    /// Frame of a cell, borders excluded.
    func cellFrame(row: Int, column: Int) -> CGRect {
        let border = TableBlock.borderWidth
        return CGRect(
            x: columnEdges[column] + border,
            y: rowEdges[row] + border,
            width: columnEdges[column + 1] - columnEdges[column] - border,
            height: rowEdges[row + 1] - rowEdges[row] - border
        )
    }

    /// The cell under a point, or the nearest one when the point is outside the table.
    func cellPosition(at point: CGPoint) -> (row: Int, column: Int) {
        func index(_ value: CGFloat, in edges: [CGFloat]) -> Int {
            let count = edges.count - 1
            guard count > 0 else { return 0 }
            return ((edges.lastIndex { $0 <= value } ?? 0)).clamped(to: 0...(count - 1))
        }
        return (index(point.y, in: rowEdges), index(point.x, in: columnEdges))
    }
}

/// One cell's text, laid out by its own TextKit 2 stack at the cell's width.
///
/// A private stack draws exactly like the rest of the document (inline code
/// background, strikethrough, attachments) and answers character positions,
/// which the selection, links and the find bar need.
final class CellLayout {
    let cell: TableBlock.Cell
    /// Top left corner of the text, in table coordinates.
    let origin: CGPoint
    let height: CGFloat

    private let contentStorage = NSTextContentStorage()
    private let layoutManager = NSTextLayoutManager()
    /// Gives code spans their rounded background inside the cell.
    private let layoutDelegate = LayoutDelegate()

    init(cell: TableBlock.Cell, origin: CGPoint, width: CGFloat) {
        self.cell = cell
        self.origin = origin
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.delegate = layoutDelegate
        let container = NSTextContainer(size: CGSize(width: width, height: 0))
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        contentStorage.attributedString = cell.content
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        height = cell.content.length > 0 ? ceil(layoutManager.usageBoundsForTextContainer.height) : 0
    }

    /// Draws the text with its top left corner at `point`.
    func draw(at point: CGPoint, in context: CGContext) {
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            fragment.draw(at: CGPoint(x: point.x + frame.minX, y: point.y + frame.minY), in: context)
            return true
        }
    }

    /// Index in the cell's text of the character boundary nearest to `point`,
    /// given in the cell text's coordinates.
    func characterIndex(at point: CGPoint) -> Int {
        let length = cell.content.length
        guard length > 0 else { return 0 }
        let documentStart = layoutManager.documentRange.location
        guard let fragment = layoutManager.textLayoutFragment(for: point) else {
            return point.y < 0 ? 0 : length
        }
        let frame = fragment.layoutFragmentFrame
        let start = layoutManager.offset(from: documentStart, to: fragment.rangeInElement.location)
        let lines = fragment.textLineFragments
        guard !lines.isEmpty else { return start }
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        let line = lines.first { local.y < $0.typographicBounds.maxY } ?? lines[lines.count - 1]
        let bounds = line.typographicBounds
        let inLine = CGPoint(x: local.x - bounds.minX, y: local.y - bounds.minY)
        var index = line.characterIndex(for: inLine)
        // `characterIndex(for:)` gives the glyph under the point; move past it
        // when the point is on its trailing half.
        if index < line.characterRange.upperBound, line.fractionOfDistanceThroughGlyph(for: inLine) > 0.5 {
            index += 1
        }
        return (start + index).clamped(to: 0...length)
    }

    /// Rectangles covering a range of the cell's text, in the cell text's coordinates.
    func rects(for range: NSRange) -> [CGRect] {
        let documentStart = layoutManager.documentRange.location
        guard range.length > 0,
              let start = layoutManager.location(documentStart, offsetBy: range.location),
              let end = layoutManager.location(documentStart, offsetBy: range.upperBound),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        var rects: [CGRect] = []
        layoutManager.enumerateTextSegments(in: textRange, type: .selection, options: [.rangeNotRequired]) { _, rect, _, _ in
            rects.append(rect)
            return true
        }
        return rects
    }
}
