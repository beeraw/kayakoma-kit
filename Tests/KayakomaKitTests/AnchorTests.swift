import AppKit
import Testing
@testable import KayakomaKit

@Test func headingAnchorsFollowGitHubRules() {
    #expect(HeadingSlugger.slug("Getting Started") == "getting-started")
    #expect(HeadingSlugger.slug("What's new in 2.0?") == "whats-new-in-20")
    #expect(HeadingSlugger.slug("Café & crème brûlée") == "café--crème-brûlée")
    #expect(HeadingSlugger.slug("snake_case and kebab-case") == "snake_case-and-kebab-case")
    #expect(HeadingSlugger.slug("Emoji 🎉 party") == "emoji--party")

    var slugger = HeadingSlugger()
    #expect(["Intro", "Intro", "Intro-1", "Intro"].map { slugger.slug(for: $0) } == ["intro", "intro-1", "intro-1-1", "intro-2"])
}

@Test func headingAnchorsUseTheVisibleText() {
    let document = RenderedDocument(source: """
    # The *`swift build`* [command](https://example.com)

    Text.

    ## Usage

    ## Usage
    """)
    #expect(document.blocks.map(\.anchor) == ["the-swift-build-command", nil, "usage", "usage-1"])
    #expect(document.blockIndex(forAnchor: "#usage-1") == 3)
    #expect(document.blockIndex(forAnchor: "Usage") == 2)
    #expect(document.blockIndex(forAnchor: "user-content-usage") == 2)
    #expect(document.blockIndex(forAnchor: "#the-swift-build-command") == 0)
    #expect(document.blockIndex(forAnchor: "#missing") == nil)
    #expect(document.blockIndex(forAnchor: "#") == nil)
}

@Test func onlyFragmentLinksPointInsideTheDocument() {
    #expect(URL(string: "#usage")?.inDocumentAnchor == "usage")
    #expect(URL(string: "#caf%C3%A9")?.inDocumentAnchor == "café")
    #expect(URL(string: "https://example.com/#usage")?.inDocumentAnchor == nil)
    #expect(URL(string: "other.md#usage")?.inDocumentAnchor == nil)
}

@MainActor
@Test func anchorLinksScrollToTheirHeading() throws {
    let filler = (1...40).map { "Paragraph \($0) with enough words to fill a line." }.joined(separator: "\n\n")
    let source = "[Go to the end](#the-end)\n\n\(filler)\n\n## The end\n\n\(filler)"
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let document = RenderedDocument(source: source)
    view.document = document
    view.layoutSubtreeIfNeeded()
    var reported: [Int] = []
    view.onTopVisibleSourceLineChange = { reported.append($0) }

    let heading = try #require(document.blocks.firstIndex { $0.anchor == "the-end" })
    let line = try #require(document.blocks[heading].sourceLines?.lowerBound)
    #expect(view.scrollToAnchor("#nowhere") == false)
    #expect(view.topVisibleSourceLine == 1)

    // A click on the link goes through the text view's delegate.
    let storage = try #require(view.textView.textStorage)
    let link = try #require(storage.attribute(.link, at: 0, effectiveRange: nil))
    _ = view.textView.textView(view.textView, clickedOnLink: link, at: 0)
    #expect(view.topVisibleSourceLine == line)
    #expect(reported.last == line)

    view.scrollToSourceLine(1)
    #expect(view.scrollToAnchor("the-end"))
    #expect(view.topVisibleSourceLine == line)
}
