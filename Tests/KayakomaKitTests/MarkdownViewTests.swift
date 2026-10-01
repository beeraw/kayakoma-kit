import AppKit
import Testing
@testable import KayakomaKit

@MainActor
@Test func unchangedBlocksAreReused() {
    let renderer = DocumentRenderer()
    let before = RenderedDocument(source: "# Title\n\nAlpha.\n\nBeta.\n\nGamma.")
    _ = renderer.update(to: before)
    #expect(renderer.buildCount == 4)

    let after = RenderedDocument(source: "# Title\n\nAlpha.\n\nBeta, edited.\n\nGamma.")
    let edit = renderer.update(to: after)
    #expect(renderer.buildCount == 5)
    // Only the edited block is replaced in the text storage.
    #expect(edit.range == renderer.range(ofBlock: 2).withLength(edit.range.length))
    #expect(edit.range.length == "Beta.\n".utf16.count)
    #expect(edit.replacement.string == "Beta, edited.\n")

    // Inserting a block rebuilds only that block, even though the others move.
    let inserted = RenderedDocument(source: "Intro.\n\n# Title\n\nAlpha.\n\nBeta, edited.\n\nGamma.")
    _ = renderer.update(to: inserted)
    #expect(renderer.buildCount == 6)

    // A theme change rebuilds everything.
    var theme = Theme.default
    theme.fontSize = 18
    renderer.theme = theme
    _ = renderer.update(to: inserted)
    #expect(renderer.buildCount == 11)
}

@MainActor
@Test func incrementalTextMatchesFullRender() {
    let first = "# Title\n\n- one\n- two\n\n> quote\n\n```\ncode\n```\n\nEnd."
    let second = "# Title\n\n- one\n- two\n- three\n\n> quote\n\n```\ncode\n```\n\nEnd!"

    let incremental = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    incremental.document = RenderedDocument(source: first)
    incremental.document = RenderedDocument(source: second)

    let fresh = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    fresh.document = RenderedDocument(source: second)

    #expect(incremental.textView.string == fresh.textView.string)
    #expect(incremental.renderer.offsets == fresh.renderer.offsets)
}

@MainActor
@Test func scrollingFollowsSourceLines() {
    let source = (1...60).map { "Paragraph number \($0), with enough words to fill a line." }.joined(separator: "\n\n")
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    view.document = RenderedDocument(source: source)
    view.layoutSubtreeIfNeeded()

    #expect(view.topVisibleSourceLine == 1)
    view.scrollToSourceLine(41)
    #expect(view.topVisibleSourceLine == 41)
    // Line 42 is the blank line after paragraph 21: it maps to that paragraph.
    view.scrollToSourceLine(42)
    #expect(view.topVisibleSourceLine == 41)
    view.scrollToSourceLine(7)
    #expect(view.topVisibleSourceLine == 7)
}

extension NSRange {
    func withLength(_ length: Int) -> NSRange { NSRange(location: location, length: length) }
}


@MainActor
@Test func changingALinkDefinitionRebuildsTheParagraphsThatUseIt() {
    let renderer = DocumentRenderer()
    let body = "# Title\n\nSee [the guide][guide] and [faq].\n\nNo links here.\n\nAn [inline](https://example.com/inline) link."
    _ = renderer.update(to: RenderedDocument(source: body + "\n\n[guide]: https://example.com/one"))
    #expect(renderer.buildCount == 4)

    // A new destination for `guide` rebuilds only the paragraph that uses it.
    var edit = renderer.update(to: RenderedDocument(source: body + "\n\n[guide]: https://example.com/two"))
    #expect(renderer.buildCount == 5)
    #expect(edit.replacement.attribute(.link, at: 4, effectiveRange: nil) as? URL == URL(string: "https://example.com/two"))

    // Defining `faq` turns the bracketed text into a link.
    edit = renderer.update(to: RenderedDocument(source: body + "\n\n[guide]: https://example.com/two\n[faq]: https://example.com/faq"))
    #expect(renderer.buildCount == 6)
    #expect(!edit.replacement.string.contains("[faq]"))

    // Unrelated edits still reuse it.
    _ = renderer.update(to: RenderedDocument(source: body.replacingOccurrences(of: "No links", with: "Still no links")
        + "\n\n[guide]: https://example.com/two\n[faq]: https://example.com/faq"))
    #expect(renderer.buildCount == 7)
}

@MainActor
@Test func codeSpansGetARoundedBackgroundAndCopyAsText() throws {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    view.document = RenderedDocument(source: "Run `swift test` now.\n\nPlain paragraph.")
    view.layoutSubtreeIfNeeded()
    let storage = try #require(view.textView.textStorage)
    let code = (storage.string as NSString).range(of: "swift test")
    #expect(storage.attribute(.kayakomaInlineCode, at: code.location, effectiveRange: nil) is InlineCodeStyle)
    #expect(storage.attribute(.backgroundColor, at: code.location, effectiveRange: nil) == nil)

    let layoutManager = try #require(view.textView.textLayoutManager)
    var fragments: [NSTextLayoutFragment] = []
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) {
        fragments.append($0)
        return true
    }
    #expect(fragments.first is BlockLayoutFragment)
    #expect(!(fragments.dropFirst().first is BlockLayoutFragment))
    // The rounded background reaches beyond the glyphs, so the fragment
    // reports a wider rendering surface than its text alone.
    let block = try #require(fragments.first as? BlockLayoutFragment)
    #expect(block.renderingSurfaceBounds.height >= block.textLineFragments[0].typographicBounds.height)

    // Selecting across the span and copying gives plain text, and rich text
    // with an ordinary background.
    view.textView.setSelectedRange(NSRange(location: 0, length: code.upperBound + 2))
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("kayakoma-test-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    #expect(view.textView.writeSelection(to: pasteboard, types: [.string, .rtf]))
    #expect(pasteboard.string(forType: .string) == "Run \u{2009}swift test\u{2009} ")
    let rtf = try #require(pasteboard.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) })
    let copied = (rtf.string as NSString).range(of: "swift")
    #expect(rtf.attribute(.backgroundColor, at: copied.location, effectiveRange: nil) != nil)
}

@MainActor
@Test func linkClicksGoToTheOwnerFirst() throws {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    view.baseURL = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
    view.document = RenderedDocument(source: "See the [station guide](docs/stations.md#access) and [top](#top).")
    let storage = try #require(view.textView.textStorage)
    let index = (storage.string as NSString).range(of: "station guide").location + 2

    var clicks: [MarkdownView.LinkClick] = []
    view.onLinkClick = { click in
        clicks.append(click)
        return true
    }
    let link = try #require(storage.attribute(.link, at: index, effectiveRange: nil))
    #expect(view.textView.textView(view.textView, clickedOnLink: link, at: index))
    let click = try #require(clicks.first)
    #expect(click.url.path == "/tmp/notes/docs/stations.md")
    #expect(click.url.fragment == "access")
    #expect(click.text == "station guide")
    #expect(click.characterIndex == index)

    // Declined clicks fall back to the view's own handling.
    view.onLinkClick = { _ in false }
    let anchorIndex = (storage.string as NSString).range(of: "top").location
    let anchor = try #require(storage.attribute(.link, at: anchorIndex, effectiveRange: nil))
    #expect(view.textView.textView(view.textView, clickedOnLink: anchor, at: anchorIndex))
}

@MainActor
@Test func brokenLinksAreUnderlinedWithDashes() throws {
    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    view.baseURL = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
    var missing: Set<String> = ["/tmp/notes/tides.md"]
    view.isLinkBroken = { missing.contains($0.path) }
    view.document = RenderedDocument(source: "Read [the tides](tides.md) and [the guide](guide.md).\n\nAnother paragraph.")
    let storage = try #require(view.textView.textStorage)
    let text = storage.string as NSString
    let tides = text.range(of: "the tides").location
    let guide = text.range(of: "the guide").location
    let dashed = NSUnderlineStyle.single.union(.patternDash).rawValue
    #expect(storage.attribute(.underlineStyle, at: tides, effectiveRange: nil) as? Int == dashed)
    #expect(storage.attribute(.underlineStyle, at: guide, effectiveRange: nil) == nil)

    // A block re-rendered after an edit is marked again.
    view.document = RenderedDocument(source: "Read [the tides](tides.md) and [the guide](guide.md).\n\nAnother paragraph, edited.")
    #expect(storage.attribute(.underlineStyle, at: tides, effectiveRange: nil) as? Int == dashed)

    // The file now exists.
    missing.removeAll()
    view.revalidateLinks()
    #expect(storage.attribute(.underlineStyle, at: tides, effectiveRange: nil) == nil)
    #expect(storage.attribute(.kayakomaBrokenLink, at: tides, effectiveRange: nil) == nil)
}
