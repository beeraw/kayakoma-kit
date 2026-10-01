import AppKit
import Markdown
import os
import Testing
@testable import KayakomaKit

/// The table paragraph and its model, built for the first table of `source`.
@MainActor
private func buildTable(_ source: String) throws -> (text: NSAttributedString, table: TableBlock) {
    let document = RenderedDocument(source: source)
    let block = try #require(document.blocks.first { $0.kind == .table })
    let text = BlockBuilder(theme: .default, baseURL: nil).build(block.markup.markup)
    let table = try #require(text.attribute(.kayakomaTable, at: 0, effectiveRange: nil) as? TableBlock)
    return (text, table)
}

@MainActor
@Test func tableAlignmentsComeFromTheDelimiterRow() throws {
    let (_, table) = try buildTable("""
    | a | b | c | d |
    |:--|:-:|--:|---|
    | 1 | 2 | 3 | 4 |
    """)
    #expect(table.alignments == [.left, .center, .right, .left])
    #expect(BlockBuilder.alignment(.center) == .center)
    #expect(BlockBuilder.alignment(nil) == .left)
}

@MainActor
@Test func tableTextIsTabSeparated() throws {
    let (text, table) = try buildTable("""
    | Name | Note |
    |------|------|
    | *one* | a \\| b |
    | | empty first |
    | short |
    """)
    #expect(text.string == "Name\tNote\u{2028}one\ta | b\u{2028}\tempty first\u{2028}short\t\n")
    // Every row has a cell per column, and each cell knows its range in the paragraph.
    #expect(table.rows.map(\.count) == [2, 2, 2, 2])
    let string = text.string as NSString
    #expect(table.rows.flatMap { $0 }.map { string.substring(with: $0.range) } == [
        "Name", "Note", "one", "a | b", "", "empty first", "short", "",
    ])
    // The header is bold, the body is not.
    let headerFont = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(headerFont.fontDescriptor.symbolicTraits.contains(.bold))
    let bodyFont = try #require(text.attribute(.font, at: table.rows[3][0].range.location, effectiveRange: nil) as? NSFont)
    #expect(!bodyFont.fontDescriptor.symbolicTraits.contains(.bold))
}

@Test func columnsKeepTheirNaturalWidthWhenTheyFit() {
    let widths = TableBlock.fitColumns(natural: [50, 80, 120], minimum: [40, 60, 70], available: 400, floor: 30)
    #expect(widths == [50, 80, 120])
}

@Test func columnsWrapToFitTheLine() {
    let widths = TableBlock.fitColumns(natural: [60, 400, 300], minimum: [60, 80, 70], available: 500, floor: 30)
    #expect(widths.reduce(0, +) <= 500)
    #expect(widths[0] == 60)
    // Space beyond the minimums goes to the columns that lack the most.
    #expect(widths[1] > widths[2])
    #expect(widths[1] >= 80 && widths[2] >= 70)
}

@Test func shortColumnsKeepTheirNaturalWidthWhileALongOneWraps() {
    // "#", "Item" ("Part 32"), "Quantity", "Note" (a long sentence) on an A4 line.
    let natural: [CGFloat] = [30, 70, 90, 2000]
    let minimum: [CGFloat] = [30, 45, 80, 100]
    let widths = TableBlock.fitColumns(natural: natural, minimum: minimum, available: 500, floor: 20)
    #expect(widths.reduce(0, +) <= 500)
    for column in 0..<3 { #expect(widths[column] >= natural[column]) }
    #expect(widths[3] < natural[3])
    #expect(widths[3] >= minimum[3])
}

@Test func aLongWordDoesNotSqueezeTheOtherColumns() {
    // The third column holds one word wider than the line: it breaks instead.
    let widths = TableBlock.fitColumns(natural: [70, 300, 600], minimum: [70, 90, 600], available: 360, floor: 30)
    #expect(widths.reduce(0, +) <= 360)
    #expect(widths[0] == 70)
    #expect(widths[1] >= 90)
}

@Test func columnsShrinkDownToTheFloor() {
    let widths = TableBlock.fitColumns(natural: [200, 200], minimum: [150, 150], available: 40, floor: 30)
    #expect(widths == [30, 30])
    #expect(TableBlock.fitColumns(natural: [], minimum: [], available: 100, floor: 30).isEmpty)
}

@MainActor
@Test func narrowTablesWrapWithoutOverlapping() throws {
    let (_, table) = try buildTable("""
    | Name | Description |
    |------|-------------|
    | Ixora | A cold world with long seasons and wide frozen plains under a thin, green-glowing atmosphere. |
    | Brell | An_identifier_far_too_long_to_fit_on_any_line_of_a_narrow_window |
    """)
    let wide = table.geometry(available: 900)
    let narrow = table.geometry(available: 200)
    let tiny = table.geometry(available: 10)
    #expect(wide.size.width <= 900)
    #expect(narrow.size.width <= 200)
    #expect(narrow.size.height > wide.size.height)
    for geometry in [wide, narrow, tiny] {
        for row in geometry.cells.indices {
            for column in geometry.cells[row].indices {
                let frame = geometry.cellFrame(row: row, column: column)
                #expect(frame.width > 0 && frame.height > 0)
                // Text fits its cell vertically; horizontally it is laid out at the cell's width.
                let cell = geometry.cells[row][column]
                #expect(cell.origin.y + cell.height <= frame.maxY)
                if column > 0 {
                    #expect(geometry.cellFrame(row: row, column: column - 1).maxX <= frame.minX)
                }
            }
        }
    }
}

@MainActor
@Test func copyingATableGivesTabSeparatedRows() throws {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.document = RenderedDocument(source: """
    Before.

    | Fruit | Count |
    |-------|------:|
    | Apple | 3 |
    | **Lime** | 12 |

    After.
    """)
    view.layoutSubtreeIfNeeded()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.kayakoma.tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }

    view.textView.selectAll(nil)
    #expect(view.textView.writeSelection(to: pasteboard, types: [.string, .rtf]))
    #expect(pasteboard.string(forType: .string) == "Before.\nFruit\tCount\nApple\t3\nLime\t12\nAfter.\n")

    // A selection inside the table copies just that part.
    let string = view.textView.string as NSString
    let start = string.range(of: "Apple").location
    view.textView.setSelectedRange(NSRange(location: start, length: string.range(of: "12").upperBound - start))
    #expect(view.textView.writeSelection(to: pasteboard, types: [.string]))
    #expect(pasteboard.string(forType: .string) == "Apple\t3\nLime\t12")
}

@MainActor
@Test func tablesStayOnTextKit2() throws {
    // The observer block is `@Sendable`: the flag lives behind a lock rather than in a captured `var`.
    let switched = OSAllocatedUnfairLock(initialState: false)
    let observer = NotificationCenter.default.addObserver(
        forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: nil, queue: nil
    ) { _ in switched.withLock { $0 = true } }
    defer { NotificationCenter.default.removeObserver(observer) }

    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.document = RenderedDocument(source: "| a | b |\n|---|---|\n| 1 | [link](https://example.com) |\n\nText.")
    view.layoutSubtreeIfNeeded()
    let layoutManager = try #require(view.textView.textLayoutManager)
    layoutManager.ensureLayout(for: layoutManager.documentRange)
    view.textView.selectAll(nil)
    _ = view.textView.tableRects(for: view.textView.selectedRange())
    view.setFrameSize(NSSize(width: 300, height: 400))
    view.layoutSubtreeIfNeeded()
    layoutManager.ensureLayout(for: layoutManager.documentRange)

    #expect(!switched.withLock { $0 })
    #expect(view.textView.textLayoutManager != nil)
    var fragments: [NSTextLayoutFragment] = []
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) {
        fragments.append($0)
        return true
    }
    #expect(fragments.first is TableLayoutFragment)
}

@MainActor
@Test func tablesFollowTheWidthOfTheView() throws {
    let row = "| A row with a fairly long sentence in its first cell | and more words in the second one |"
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
    view.document = RenderedDocument(source: "| One | Two |\n|---|---|\n\(row)\n\nAfter.")
    view.layoutSubtreeIfNeeded()
    let layoutManager = try #require(view.textView.textLayoutManager)
    func frames() -> [CGRect] {
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var frames: [CGRect] = []
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) {
            frames.append($0.layoutFragmentFrame)
            return true
        }
        return frames
    }
    let wide = frames()
    view.setFrameSize(NSSize(width: 360, height: 400))
    view.layoutSubtreeIfNeeded()
    let narrow = frames()
    #expect(narrow[0].height > wide[0].height)
    #expect(narrow[0].width <= view.textView.textContainer!.size.width)
    // The paragraph after the table starts where the table ends.
    #expect(narrow[1].minY == narrow[0].maxY)
}

@MainActor
@Test func unchangedTablesAreReused() {
    let table = "| a | b |\n|---|---|\n| 1 | 2 |"
    let renderer = DocumentRenderer()
    _ = renderer.update(to: RenderedDocument(source: "Intro.\n\n\(table)\n\nOutro."))
    #expect(renderer.buildCount == 3)
    let edit = renderer.update(to: RenderedDocument(source: "Intro, edited.\n\n\(table)\n\nOutro."))
    #expect(renderer.buildCount == 4)
    #expect(edit.replacement.string == "Intro, edited.\n")

    // Editing a cell rebuilds the table, and only the table.
    let edited = renderer.update(to: RenderedDocument(source: "Intro, edited.\n\n\(table.replacingOccurrences(of: "2", with: "22"))\n\nOutro."))
    #expect(renderer.buildCount == 5)
    #expect(edited.replacement.string == "a\tb\u{2028}1\t22\n")
}

@MainActor
@Test func scrollingFollowsSourceLinesAcrossATable() {
    let before = (1...10).map { "Paragraph \($0) before the table, long enough to need some room." }.joined(separator: "\n\n")
    let rows = (1...40).map { "| row \($0) | value \($0) |" }.joined(separator: "\n")
    let after = (1...20).map { "Paragraph \($0) after the table." }.joined(separator: "\n\n")
    let source = "\(before)\n\n| Name | Value |\n|---|---|\n\(rows)\n\n\(after)"
    let document = RenderedDocument(source: source)
    let tableIndex = document.blocks.firstIndex { $0.kind == .table }!
    let tableLines = document.blocks[tableIndex].sourceLines!
    #expect(tableLines == 21...62)
    #expect(document.blockIndex(forSourceLine: 40) == tableIndex)

    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    view.document = document
    view.layoutSubtreeIfNeeded()
    view.scrollToSourceLine(21)
    #expect(view.topVisibleSourceLine == 21)
    // Inside the table, the position is interpolated over its height.
    view.scrollToSourceLine(42)
    let inside = view.topVisibleSourceLine ?? 0
    #expect(tableLines.contains(inside))
    #expect(abs(inside - 42) <= 1)
    // After the table, lines map exactly again.
    let firstAfter = tableLines.upperBound + 2
    view.scrollToSourceLine(firstAfter)
    #expect(view.topVisibleSourceLine == firstAfter)
}

// MARK: - Table borders

/// Counts the pixels of `bitmap` that are clearly red, along a horizontal
/// line (`y` fixed) or a vertical one (`x` fixed), in view points.
@MainActor
private func redPixels(in bitmap: NSBitmapImageRep, view: NSView, x: ClosedRange<Int>? = nil, y: ClosedRange<Int>? = nil, fixed: Int) -> Int {
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    func isRed(_ px: Int, _ py: Int) -> Bool {
        guard let c = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return false }
        return c.redComponent > 0.8 && c.greenComponent < 0.3 && c.blueComponent < 0.3
    }
    if let x { return x.filter { isRed(Int(CGFloat($0) * scale), Int(CGFloat(fixed) * scale)) }.count }
    return (y ?? 0...0).filter { isRed(Int(CGFloat(fixed) * scale), Int(CGFloat($0) * scale)) }.count
}

@MainActor
private func renderedTable(borders: Theme.TableBorders) throws -> (bitmap: NSBitmapImageRep, view: MarkdownView, rowEdges: [CGFloat], width: CGFloat, originY: CGFloat, originX: CGFloat) {
    var theme = Theme.default
    theme.tableBorders = borders
    theme.tableBorderColor = .custom(light: "#FF0000", dark: "#FF0000")
    theme.backgroundColor = .custom(light: "#FFFFFF", dark: "#FFFFFF")
    theme.tableHeaderBackgroundColor = .custom(light: "#FFFFFF", dark: "#FFFFFF")
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    view.appearance = NSAppearance(named: .aqua)
    view.theme = theme
    view.document = RenderedDocument(source: "| One | Two |\n|---|---|\n| a | b |\n| c | d |")
    view.layoutSubtreeIfNeeded()
    let layoutManager = try #require(view.textView.textLayoutManager)
    layoutManager.ensureLayout(for: layoutManager.documentRange)
    var fragment: TableLayoutFragment?
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) {
        fragment = $0 as? TableLayoutFragment
        return false
    }
    let table = try #require(fragment)
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let inset = view.textView.textContainerInset
    let frame = table.layoutFragmentFrame
    return (bitmap, view, table.rowEdges, table.placement.geometry.size.width, inset.height + frame.minY, inset.width + frame.minX + table.placement.origin.x)
}

@MainActor
@Test func horizontalBordersDrawRulesButNoVerticalLines() throws {
    let r = try renderedTable(borders: .horizontal)
    let left = Int(r.originX), right = Int(r.originX + r.width)
    // In the middle of the first body row, nothing is drawn, not even at the sides.
    let middleOfRow = Int(r.originY + (r.rowEdges[1] + r.rowEdges[2]) / 2)
    #expect(redPixels(in: r.bitmap, view: r.view, x: left - 2...right + 2, fixed: middleOfRow) == 0)
    // A rule under the header, between rows and under the last row, full width.
    for edge in [1, 2, 3] {
        let y = Int(r.originY + r.rowEdges[edge])
        #expect(redPixels(in: r.bitmap, view: r.view, x: left + 2...right - 2, fixed: y) > (right - left) / 2)
    }
    // No top rule.
    let top = Int(r.originY + r.rowEdges[0])
    #expect(redPixels(in: r.bitmap, view: r.view, x: left + 2...right - 2, fixed: top) == 0)
}

@MainActor
@Test func allBordersDrawTheFullGrid() throws {
    let r = try renderedTable(borders: .all)
    let middleOfRow = Int(r.originY + (r.rowEdges[1] + r.rowEdges[2]) / 2)
    // Left edge, column separator and right edge: three vertical lines.
    #expect(redPixels(in: r.bitmap, view: r.view, x: Int(r.originX) - 2...Int(r.originX + r.width) + 2, fixed: middleOfRow) >= 3)
    let top = Int(r.originY + r.rowEdges[0])
    #expect(redPixels(in: r.bitmap, view: r.view, x: Int(r.originX) + 2...Int(r.originX + r.width) - 2, fixed: top) > 0)
}
