import AppKit
import Testing
@testable import KayakomaKit

// One view reused for several documents, as a viewer or an editor does when
// it switches files: every geometry query must answer from the new document.

private let longSource = (1...40).map { index in
    switch index % 5 {
    case 0: "## Section \(index)\n\nSome text with a [link](#section-\(index))."
    case 1: "| Key | Value |\n|-----|-------|\n| a\(index) | \(index) |\n| b | c |"
    case 2: "```swift\nlet value = \(index)\nprint(value)\n```"
    case 3: "- item \(index)\n- another item with `code`"
    default: "> Quoted paragraph number \(index), long enough to wrap over a line or two in the view."
    }
}.joined(separator: "\n\n")

private let shortSource = "# Short\n\nOne paragraph.\n\n- a\n- b\n"

@MainActor
private func makeWindowedView(height: CGFloat = 400) -> (MarkdownView, NSWindow) {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: height))
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    return (view, window)
}

@MainActor
private func show(_ source: String, in view: MarkdownView, window: NSWindow) {
    view.document = RenderedDocument(source: source)
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
}

/// Calls every geometry API on every block and checks the answers are consistent.
@MainActor
private func exerciseGeometry(of view: MarkdownView) throws {
    let count = view.document?.blocks.count ?? 0
    #expect(view.renderer.offsets.last == view.textView.textStorage?.length)
    for index in 0..<count {
        let frame = try #require(view.frame(ofBlockAt: index), "block \(index) of \(count)")
        #expect(frame.height > 0)
    }
    #expect(view.frame(ofBlockAt: count) == nil)
    #expect(view.frame(ofBlockAt: count + 25) == nil)
    for y in stride(from: view.bounds.minY + 1, to: view.bounds.maxY, by: 13) {
        if let index = view.blockIndex(at: CGPoint(x: view.bounds.midX, y: y)) {
            #expect(index >= 0 && index < count)
        }
    }
    // Table hit-testing, as clicks and pointer moves do.
    let textView = view.textView
    for y in stride(from: textView.visibleRect.minY, to: textView.visibleRect.maxY, by: 7) {
        let point = NSPoint(x: textView.textContainerOrigin.x + 12, y: y)
        if let hit = textView.tableFragment(at: point) {
            #expect(hit.start < textView.textStorage?.length ?? 0)
        }
        #expect(textView.characterIndex(atViewPoint: point) <= textView.textStorage?.length ?? 0)
    }
    if count > 0 {
        #expect(view.topVisibleSourceLine != nil)
    } else {
        #expect(view.topVisibleSourceLine == nil)
    }
    let length = view.textView.textStorage?.length ?? 0
    view.textView.setSelectedRange(NSRange(location: length, length: 0))
    if count > 0 {
        let selected = try #require(view.selectedBlockIndex)
        #expect(selected < count)
    }
    view.scrollToSourceLine(1)
    view.scrollToSourceLine(10_000)
    _ = view.scrollToAnchor("#section-35")
    _ = view.topVisibleSourceLine
    for index in 0..<count {
        _ = view.frame(ofBlockAt: index)
    }
}

@MainActor
@Test func replacingWithAShorterDocumentKeepsGeometryValid() throws {
    let (view, window) = makeWindowedView()
    defer { window.close() }
    show(longSource, in: view, window: window)
    try exerciseGeometry(of: view)
    // Leave the view scrolled to the end and the selection there, then swap.
    view.scrollToSourceLine(10_000)
    let length = try #require(view.textView.textStorage?.length)
    view.textView.setSelectedRange(NSRange(location: length - 1, length: 1))
    show(shortSource, in: view, window: window)
    #expect(view.document?.blocks.count == 3)
    try exerciseGeometry(of: view)
}

@MainActor
@Test func replacingWithALongerDocumentKeepsGeometryValid() throws {
    let (view, window) = makeWindowedView()
    defer { window.close() }
    show(shortSource, in: view, window: window)
    try exerciseGeometry(of: view)
    show(longSource, in: view, window: window)
    try exerciseGeometry(of: view)
    #expect(view.scrollToAnchor("#section-35"))
}

@MainActor
@Test func replacingWithAnEmptyDocumentKeepsGeometryValid() throws {
    let (view, window) = makeWindowedView()
    defer { window.close() }
    show(longSource, in: view, window: window)
    view.scrollToSourceLine(10_000)
    show("", in: view, window: window)
    try exerciseGeometry(of: view)
    #expect(view.frame(ofBlockAt: 0) == nil)
    #expect(view.blockIndex(at: CGPoint(x: 10, y: 10)) == nil)
    #expect(view.selectedBlockIndex == nil)
    view.document = nil
    try exerciseGeometry(of: view)
    show(shortSource, in: view, window: window)
    try exerciseGeometry(of: view)
}

@MainActor
@Test func alternatingDocumentsWithoutAWindowKeepsGeometryValid() throws {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let sources = [longSource, shortSource, "", longSource, "Just one line.", shortSource + "\n\n" + longSource, shortSource]
    for source in sources {
        view.document = RenderedDocument(source: source)
        view.layoutSubtreeIfNeeded()
        try exerciseGeometry(of: view)
        view.scrollToSourceLine(10_000)
    }
}

@MainActor
@Test func lastBlockFrameMatchesTheOtherBlocks() throws {
    // The last block has no blank line after it in the text, so its frame
    // must not depend on what kind of block it is.
    for tail in ["Paragraph.", "> Quote.", "```\ncode\n```", "- item", "| A |\n|---|\n| 1 |"] {
        let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.document = RenderedDocument(source: "# Title\n\n\(tail)\n\nBetween.\n\n\(tail)")
        view.layoutSubtreeIfNeeded()
        #expect(view.document?.blocks.count == 4)
        let middle = try #require(view.frame(ofBlockAt: 1))
        let last = try #require(view.frame(ofBlockAt: 3))
        #expect(abs(middle.height - last.height) < 0.5, "\(tail): \(middle.height) vs \(last.height)")
    }
}
