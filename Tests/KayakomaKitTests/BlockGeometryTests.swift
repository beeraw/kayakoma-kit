import AppKit
import Testing
@testable import KayakomaKit

@MainActor
private func makeView(_ source: String, height: CGFloat = 300) -> MarkdownView {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: height))
    view.document = RenderedDocument(source: source)
    view.layoutSubtreeIfNeeded()
    return view
}

@MainActor
@Test func blockFramesFollowTheDocumentOrder() throws {
    let view = makeView("# Title\n\nParagraph.\n\n- one\n- two\n\n> quote\n")
    let count = try #require(view.document?.blocks.count)
    #expect(count == 4)
    let frames = try (0..<count).map { try #require(view.frame(ofBlockAt: $0)) }
    // The view is not flipped: later blocks sit lower, so their y is smaller.
    for (above, below) in zip(frames, frames.dropFirst()) {
        #expect(below.maxY <= above.minY + 0.5)
    }
    #expect(frames.allSatisfy { $0.height > 0 && view.bounds.intersects($0) })
}

@MainActor
@Test func outOfRangeBlocksHaveNoGeometry() {
    let view = makeView("One.\n\nTwo.")
    #expect(view.frame(ofBlockAt: -1) == nil)
    #expect(view.frame(ofBlockAt: 2) == nil)
    #expect(view.blockIndex(at: CGPoint(x: -5, y: 10)) == nil)
    #expect(view.blockIndex(at: CGPoint(x: 10, y: 5_000)) == nil)
    let empty = makeView("")
    #expect(empty.frame(ofBlockAt: 0) == nil)
    #expect(empty.blockIndex(at: CGPoint(x: 10, y: 10)) == nil)
}

@MainActor
@Test func blockIndexRoundTripsWithFrames() throws {
    let view = makeView("# Title\n\nParagraph.\n\n- one\n- two\n\n```\ncode\n```\n\nEnd.", height: 600)
    let count = try #require(view.document?.blocks.count)
    for index in 0..<count {
        let frame = try #require(view.frame(ofBlockAt: index))
        #expect(view.blockIndex(at: CGPoint(x: frame.midX, y: frame.midY)) == index)
    }
}

@MainActor
@Test func blockGeometryFollowsScrolling() throws {
    let source = (1...60).map { "Paragraph number \($0), with enough words to fill a line." }.joined(separator: "\n\n")
    let view = makeView(source)
    let before = try #require(view.frame(ofBlockAt: 40))
    view.scrollToSourceLine(81)
    let after = try #require(view.frame(ofBlockAt: 40))
    // The block moved up, to the top of the visible area.
    #expect(after.maxY > before.maxY)
    #expect(after.maxY > view.bounds.maxY - 40)
    #expect(view.blockIndex(at: CGPoint(x: after.midX, y: after.midY)) == 40)
    // The last block is reachable too, wherever the view is scrolled.
    let last = try #require(view.frame(ofBlockAt: 59))
    #expect(last.height > 0)
    view.scrollToSourceLine(119)
    let lastShown = try #require(view.frame(ofBlockAt: 59))
    #expect(view.bounds.intersects(lastShown))
    #expect(view.blockIndex(at: CGPoint(x: lastShown.midX, y: lastShown.midY)) == 59)
}

@MainActor
@Test func tablesHaveBlockGeometry() throws {
    let view = makeView("Before.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\nAfter.", height: 500)
    #expect(view.document?.blocks.count == 3)
    let table = try #require(view.frame(ofBlockAt: 1))
    let before = try #require(view.frame(ofBlockAt: 0))
    let after = try #require(view.frame(ofBlockAt: 2))
    #expect(table.height > before.height)
    #expect(table.maxY <= before.minY + 0.5)
    #expect(after.maxY <= table.minY + 0.5)
    #expect(view.blockIndex(at: CGPoint(x: table.midX, y: table.midY)) == 1)
}

@MainActor
@Test func selectedBlockIsReported() throws {
    let view = makeView("# Title\n\nParagraph.\n\nEnd.")
    view.textView.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(view.selectedBlockIndex == 0)
    let offset = view.renderer.offsets[2]
    view.textView.setSelectedRange(NSRange(location: offset, length: 0))
    #expect(view.selectedBlockIndex == 2)
    #expect(MarkdownView().selectedBlockIndex == nil)
}

@MainActor
@Test func aDocumentEndingWithATableCanBeScrolled() throws {
    let paragraphs = (1...150).map { "Paragraph number \($0), with enough words to fill a line." }.joined(separator: "\n\n")
    let source = paragraphs + "\n\n| Key | Value |\n|-----|-------|\n| a   | 1 |\n"
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    defer { window.close() }
    window.orderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.document = RenderedDocument(source: source)
    window.displayIfNeeded()
    let textView = view.textView
    textView.textLayoutManager.map { $0.ensureLayout(for: $0.documentRange) }
    textView.sizeToFit()
    view.scrollToSourceLine(200)
    let top = try #require(view.topVisibleSourceLine)
    #expect(abs(top - 200) <= 2)
}
