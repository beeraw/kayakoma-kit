import AppKit
import Testing
@testable import KayakomaKit

/// About 5,000 source lines of mixed blocks, with a table every so often.
func largeDocumentSource() -> String {
    var parts: [String] = []
    for section in 1...260 {
        parts.append("## Section \(section)")
        parts.append("A paragraph of section \(section) with *emphasis*, `code` and a [link](https://example.com).\nIt spans two source lines and wraps on screen as the text goes on and on.")
        parts.append("- first item\n- second item\n  - nested item\n- third item")
        parts.append("> A quoted remark\n> on two lines.")
        parts.append("```swift\nlet value = \(section)\nprint(value)\n// a comment\n```")
        if section % 10 == 0 {
            parts.append("| Name | Value |\n|------|------:|\n" + (1...8).map { "| row \($0) | \($0 * section) |" }.joined(separator: "\n"))
        }
        parts.append("Closing paragraph of section \(section).")
    }
    return parts.joined(separator: "\n\n")
}

/// Milliseconds taken by `body`.
@MainActor
func milliseconds(_ body: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

@MainActor
@Test func scrollSyncStaysFastOnLargeDocuments() throws {
    let source = largeDocumentSource()
    let lineCount = source.split(separator: "\n", omittingEmptySubsequences: false).count
    #expect(lineCount > 4_500)
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    view.document = RenderedDocument(source: source)
    view.layoutSubtreeIfNeeded()

    var scrolls: [Double] = []
    var reads: [Double] = []
    for line in [lineCount - 300, lineCount / 2, 30, lineCount * 3 / 4, lineCount / 4, lineCount - 100] {
        scrolls.append(milliseconds { view.scrollToSourceLine(line) })
        var top: Int?
        reads.append(milliseconds { top = view.topVisibleSourceLine })
        let block = try #require(view.document?.blockIndex(forSourceLine: line).flatMap { view.document?.blocks[$0].sourceLines })
        let expected = block.contains(line) ? line : block.lowerBound
        #expect(top.map { abs($0 - expected) <= 1 } == true, "line \(line): top \(String(describing: top)), expected \(expected)")
    }
    // A frame is 16 ms; the margin keeps slow or busy machines from failing.
    #expect(scrolls.max() ?? 0 < 50)
    #expect(reads.max() ?? 0 < 50)
    print("lines:", lineCount, "blocks:", view.document?.blocks.count ?? 0)
    print("scrollToSourceLine ms:", scrolls.map { String(format: "%.1f", $0) }.joined(separator: " "))
    print("topVisibleSourceLine ms:", reads.map { String(format: "%.1f", $0) }.joined(separator: " "))
}
