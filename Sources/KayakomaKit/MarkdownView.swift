import AppKit

/// Native view that displays a Markdown document.
///
/// Rendering goes through TextKit 2: each block becomes styled paragraphs, and
/// blocks that need a background, a bar or a rule get a custom layout
/// fragment. Text can be selected and copied, never edited.
///
/// Local images are decoded off the main thread: the space they need is
/// reserved at once and a placeholder shows until they are ready. Remote
/// (`http`, `https`) images are never downloaded, as the engine makes no
/// network access; they show as a placeholder with their description.
///
/// Links to `#anchor` scroll to the heading with that GitHub-style anchor;
/// other links open with the workspace, unless `onLinkClick` handles them.
public final class MarkdownView: NSView {
    /// A click on a link, as given to `onLinkClick`.
    public struct LinkClick {
        /// The link's target, resolved against `baseURL`; `#anchor` links stay relative.
        public let url: URL
        /// The modifier keys held during the click.
        public let modifiers: NSEvent.ModifierFlags
        /// Offset of the clicked character in the view's text.
        public let characterIndex: Int
        /// The link's visible text.
        public let text: String

        public init(url: URL, modifiers: NSEvent.ModifierFlags, characterIndex: Int, text: String) {
            self.url = url
            self.modifiers = modifiers
            self.characterIndex = characterIndex
            self.text = text
        }
    }

    /// Called when a link is clicked, before the view follows it. Return
    /// `true` when the click was handled: the view then does nothing more.
    public var onLinkClick: ((LinkClick) -> Bool)?

    /// Tells which links point to nothing; those are underlined with dashes.
    /// `nil` (the default) marks no link. Call `revalidateLinks()` when the
    /// answer may have changed for links already on display.
    public var isLinkBroken: ((URL) -> Bool)? {
        didSet { revalidateLinks() }
    }

    /// The document on display. Only blocks whose source text changed are rebuilt.
    public var document: RenderedDocument? {
        didSet { render() }
    }

    /// Visual settings; changing them re-renders the whole document.
    /// Whether the view shows a vertical scroller when its document is
    /// taller than it. Turn it off for a view sized to its content: with
    /// "always show scroll bars", the scroller would otherwise take its width.
    public var showsVerticalScroller: Bool {
        get { scrollView.hasVerticalScroller }
        set { scrollView.hasVerticalScroller = newValue }
    }

    public var theme: Theme = .default {
        didSet {
            guard theme != oldValue else { return }
            renderer.theme = theme
            applyTheme()
            render()
        }
    }

    /// Directory that relative image paths and links are resolved against.
    public var baseURL: URL? {
        didSet {
            guard baseURL != oldValue else { return }
            renderer.baseURL = baseURL
            render()
        }
    }

    /// Called with `topVisibleSourceLine` when the user scrolls the view.
    public var onTopVisibleSourceLineChange: ((Int) -> Void)?

    let scrollView = NSScrollView()
    let textView = MarkdownTextView(usingTextLayoutManager: true)
    let renderer = DocumentRenderer()
    private let layoutDelegate = LayoutDelegate()
    private var isScrollingProgrammatically = false

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = textView
        textView.textLayoutManager?.delegate = layoutDelegate
        textView.followAnchor = { [weak self] anchor in
            self?.scrollToAnchor(anchor) ?? false
        }
        textView.handleLinkClick = { [weak self] url, index in
            self?.handleLinkClick(url, at: index) ?? false
        }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(imageDidLoad),
            name: .kayakomaImageDidLoad,
            object: nil
        )
        applyTheme()
    }

    public override func layout() {
        super.layout()
        updateInsets()
    }

    // MARK: - Rendering

    private func render() {
        let edit = renderer.update(to: document ?? RenderedDocument(source: ""))
        guard let storage = textView.textStorage else { return }
        let apply = {
            storage.beginEditing()
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            storage.endEditing()
        }
        if let contentStorage = textView.textContentStorage {
            contentStorage.performEditingTransaction(apply)
        } else {
            apply()
        }
        markBrokenLinks(in: NSRange(location: edit.range.location, length: edit.replacement.length))
    }

    // MARK: - Links

    private func handleLinkClick(_ url: URL, at index: Int) -> Bool {
        guard let onLinkClick else { return false }
        var text = ""
        if let storage = textView.textStorage, index < storage.length {
            var range = NSRange()
            if storage.attribute(.link, at: index, longestEffectiveRange: &range, in: storage.fullRange) != nil {
                text = storage.attributedSubstring(from: range).string
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(["\u{2009}"]))
            }
        }
        let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        return onLinkClick(LinkClick(url: url, modifiers: modifiers, characterIndex: index, text: text))
    }

    /// Marks again every link of the document as broken or not.
    public func revalidateLinks() {
        guard let storage = textView.textStorage else { return }
        markBrokenLinks(in: storage.fullRange)
    }

    /// Dashed underline on the broken links of `range`, none on the others.
    private func markBrokenLinks(in range: NSRange) {
        guard let storage = textView.textStorage, range.length > 0 else { return }
        let clamped = NSIntersectionRange(range, storage.fullRange)
        var changes: [(NSRange, Bool)] = []
        storage.enumerateAttribute(.link, in: clamped) { value, run, _ in
            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            let broken = url.map { isLinkBroken?($0) ?? false } ?? false
            let marked = storage.attribute(.kayakomaBrokenLink, at: run.location, effectiveRange: nil) != nil
            if broken != marked || (value == nil && marked) { changes.append((run, broken && value != nil)) }
        }
        guard !changes.isEmpty else { return }
        let apply = {
            storage.beginEditing()
            for (run, broken) in changes {
                if broken {
                    storage.addAttributes([
                        .kayakomaBrokenLink: true,
                        .underlineStyle: NSUnderlineStyle.single.union(.patternDash).rawValue,
                        .underlineColor: self.theme.linkColor.nsColor,
                    ], range: run)
                } else {
                    storage.removeAttribute(.kayakomaBrokenLink, range: run)
                    storage.removeAttribute(.underlineStyle, range: run)
                    storage.removeAttribute(.underlineColor, range: run)
                }
            }
            storage.endEditing()
        }
        if let contentStorage = textView.textContentStorage {
            contentStorage.performEditingTransaction(apply)
        } else {
            apply()
        }
    }

    /// Redraws the images whose pixels just arrived. Their size was reserved,
    /// so only their lines are laid out again.
    @objc private func imageDidLoad(_ notification: Notification) {
        guard let key = notification.object as? ImageStore.Key,
              let storage = textView.textStorage,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: storage.fullRange) { value, range, _ in
            if let attachment = value as? ImageAttachment, attachment.info.key == key { ranges.append(range) }
        }
        storage.enumerateAttribute(.kayakomaTable, in: storage.fullRange) { value, range, _ in
            guard let table = value as? TableBlock, table.containsImage(key) else { return }
            ranges.append(range)
        }
        guard !ranges.isEmpty else { return }
        let start = contentManager.documentRange.location
        for range in ranges {
            guard let from = contentManager.location(start, offsetBy: range.location),
                  let to = contentManager.location(from, offsetBy: range.length),
                  let textRange = NSTextRange(location: from, end: to) else { continue }
            layoutManager.invalidateLayout(for: textRange)
        }
        layoutManager.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
    }

    private func applyTheme() {
        let background = theme.backgroundColor.nsColor
        textView.backgroundColor = background
        textView.drawsBackground = true
        scrollView.backgroundColor = background
        textView.linkTextAttributes = [
            .foregroundColor: theme.linkColor.nsColor,
            .cursor: NSCursor.pointingHand,
        ]
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        updateInsets()
    }

    /// Centres a column no wider than `maxLineWidth`, with at least the theme's margins.
    private func updateInsets() {
        let width = scrollView.contentSize.width
        let margins = theme.contentMargins
        var horizontal = margins.horizontal
        if let maxLineWidth = theme.maxLineWidth {
            horizontal = max(horizontal, floor((width - maxLineWidth) / 2))
        }
        let inset = NSSize(width: horizontal, height: margins.vertical)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
        }
    }

    // MARK: - Source positions

    /// Source line shown at the top of the visible area, interpolated inside
    /// tall blocks; `nil` when there is no document.
    public var topVisibleSourceLine: Int? {
        guard let layoutManager = textView.textLayoutManager,
              !renderer.blocks.isEmpty else { return nil }
        // One point of tolerance: the clip view snaps to whole points.
        let y = max(0, scrollView.contentView.bounds.minY - textView.textContainerOrigin.y + 1)
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y))
                ?? layoutManager.textLayoutFragment(for: layoutManager.documentRange.endLocation) else {
            return renderer.blocks.first?.sourceLines?.lowerBound
        }
        let offset = layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        guard let index = renderer.blockIndex(atOffset: offset) else { return nil }
        guard let lines = renderer.blocks[index].sourceLines else {
            return nearestSourceLine(before: index)
        }
        guard let frame = frame(ofBlock: index), frame.height > 0, lines.count > 1 else { return lines.lowerBound }
        let fraction = min(max((y - frame.minY) / frame.height, 0), 1)
        return lines.lowerBound + Int((fraction * CGFloat(lines.count)).rounded(.down)).clamped(to: 0...(lines.count - 1))
    }

    /// Scrolls so that the block holding `line` (1-based) is at the top of the
    /// visible area, interpolating inside tall blocks.
    public func scrollToSourceLine(_ line: Int) {
        guard let document, let index = document.blockIndex(forSourceLine: line),
              index < renderer.blocks.count else { return }
        isScrollingProgrammatically = true
        scroll(toBlock: index, line: line)
        isScrollingProgrammatically = false
    }

    /// Puts a block, or a source line inside it, at the top of the visible area.
    ///
    /// Only the block is laid out, not everything above it: TextKit places it
    /// from estimated heights, so the first scroll may land a little off. Once
    /// the viewport around it is laid out, positions are exact, and a second
    /// scroll corrects the first.
    @discardableResult
    private func scroll(toBlock index: Int, line: Int?) -> Bool {
        // Laying the viewport out replaces estimates with real positions and
        // moves the scroll offset to compensate: repeat until the block is
        // where it should be once its surroundings are laid out.
        for _ in 0..<4 {
            guard let y = scrollOffset(ofBlock: index, line: line) else { return false }
            if abs(scrollView.contentView.bounds.minY - y) < 0.5 { return true }
            ensureDocumentHeight(below: y)
            textView.scroll(NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        }
        return true
    }

    /// TextKit sizes the text view from estimated heights; make sure it is
    /// tall enough for an offset that layout has just shown to exist.
    private func ensureDocumentHeight(below y: CGFloat) {
        let needed = y + scrollView.contentSize.height
        if textView.frame.height < needed {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: needed))
        }
    }

    /// Vertical scroll offset that puts a block at the top of the visible
    /// area, or the given source line inside it.
    private func scrollOffset(ofBlock index: Int, line: Int?) -> CGFloat? {
        guard var frame = frame(ofBlock: index) else { return nil }
        if let line, let lines = renderer.blocks[index].sourceLines, lines.count > 1, lines.contains(line) {
            let fraction = CGFloat(line - lines.lowerBound) / CGFloat(lines.count)
            frame.origin.y += frame.height * fraction
        }
        return max(0, ceil(frame.minY + textView.textContainerOrigin.y))
    }

    /// Scrolls so that the heading with the GitHub-style anchor `anchor`
    /// (`"#getting-started"` or `"getting-started"`) is at the top of the
    /// visible area. Unlike `scrollToSourceLine(_:)`, this reports the new
    /// position through `onTopVisibleSourceLineChange`, as following a link does.
    ///
    /// - Returns: whether the document has a heading with that anchor.
    @discardableResult
    public func scrollToAnchor(_ anchor: String) -> Bool {
        guard let index = document?.blockIndex(forAnchor: anchor), index < renderer.blocks.count else { return false }
        return scroll(toBlock: index, line: nil)
    }

    // MARK: - Block geometry

    /// Frame of the top-level block at `index` (the same index as in
    /// `document.blocks`), in this view's coordinate space, so it follows the
    /// scroll position and the insets. It includes the space after the block.
    ///
    /// Only the block is laid out if it was not yet; the frame of a block far
    /// from the viewport is an estimate until its surroundings are laid out.
    /// Returns `nil` when `index` is out of range or the block has no text.
    public func frame(ofBlockAt index: Int) -> CGRect? {
        guard index >= 0, index < renderer.blocks.count, var frame = frame(ofBlock: index) else { return nil }
        let origin = textView.textContainerOrigin
        frame = frame.offsetBy(dx: origin.x, dy: origin.y)
        return convert(frame, from: textView)
    }

    /// Index of the top-level block drawn under `point`, given in this view's
    /// coordinate space; `nil` outside the view or below the last block.
    /// Horizontally, any point of a block's row counts, margins included.
    public func blockIndex(at point: CGPoint) -> Int? {
        guard bounds.contains(point), let layoutManager = textView.textLayoutManager else { return nil }
        let local = textView.convert(point, from: self)
        let origin = textView.textContainerOrigin
        let inContainer = CGPoint(x: local.x - origin.x, y: local.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: inContainer),
              inContainer.y >= fragment.layoutFragmentFrame.minY, inContainer.y < fragment.layoutFragmentFrame.maxY else { return nil }
        let offset = layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        return renderer.blockIndex(atOffset: offset)
    }

    /// Index of the top-level block that holds the start of the selection;
    /// `nil` when there is no document or the view is not up to date with it.
    public var selectedBlockIndex: Int? {
        guard renderer.offsets.last == textView.textStorage?.length else { return nil }
        return renderer.blockIndex(atOffset: textView.selectedRange().location)
    }

    /// Frame of a block in text container coordinates.
    private func frame(ofBlock index: Int) -> CGRect? {
        guard let layoutManager = textView.textLayoutManager else { return nil }
        let range = renderer.range(ofBlock: index)
        guard range.length > 0 else { return nil }
        let start = layoutManager.location(layoutManager.documentRange.location, offsetBy: range.location)
        let last = layoutManager.location(layoutManager.documentRange.location, offsetBy: range.upperBound - 1)
        guard let start, let last else { return nil }
        var top: CGRect?
        var bottom: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            top = fragment.layoutFragmentFrame
            return false
        }
        layoutManager.enumerateTextLayoutFragments(from: last, options: [.ensuresLayout]) { fragment in
            bottom = fragment.layoutFragmentFrame
            return false
        }
        guard let top, let bottom else { return nil }
        return top.union(bottom)
    }

    private func nearestSourceLine(before index: Int) -> Int? {
        renderer.blocks[...index].reversed().lazy.compactMap(\.sourceLines?.lowerBound).first
    }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        guard !isScrollingProgrammatically, let onTopVisibleSourceLineChange,
              let line = topVisibleSourceLine else { return }
        onTopVisibleSourceLineChange(line)
    }
}

/// Read-only text view: opens links with the workspace and copies code blocks
/// with real line breaks.
final class MarkdownTextView: NSTextView, NSTextViewDelegate {
    /// Scrolls to the heading of an in-document link; set by `MarkdownView`.
    var followAnchor: ((String) -> Bool)?
    /// Offers a clicked link to the view's owner first; set by `MarkdownView`.
    var handleLinkClick: ((URL, Int) -> Bool)?

    /// A vertically resizable text view takes back a height it did not choose:
    /// when the document ends with a table, AppKit keeps the view at its
    /// minimum height whatever is asked, and the preview then cannot scroll at
    /// all. The heights `MarkdownView` asks for come from laid-out positions,
    /// so they are applied as given.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard isVerticallyResizable, frame.height < newSize.height else { return }
        isVerticallyResizable = false
        super.setFrameSize(newSize)
        isVerticallyResizable = true
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url else { return true }
        if handleLinkClick?(url, charIndex) == true { return true }
        if let anchor = url.inDocumentAnchor {
            _ = followAnchor?(anchor)
        } else if url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    // MARK: Tables

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return }
        let focused = window?.isKeyWindow == true && window?.firstResponder === self
        (focused ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedTextBackgroundColor).setFill()
        for range in ranges {
            for selected in tableRects(for: range) where selected.intersects(rect) {
                selected.fill()
            }
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let touchesTable = (selectedRanges + ranges).contains { intersectsTable($0.rangeValue) }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if touchesTable { needsDisplay = true }
    }

    /// Clicks on a table select its text and follow its links; elsewhere,
    /// the text view handles them.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = tableFragment(at: point) else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        let granularity: NSSelectionGranularity = switch event.clickCount {
        case 1: .selectByCharacter
        case 2: .selectByWord
        default: .selectByParagraph
        }
        let index = hit.start + hit.fragment.characterIndex(at: hit.local)
        let link = hit.fragment.character(at: hit.local).flatMap { character -> (Any, Int)? in
            let position = hit.start + character
            return textStorage?.attribute(.link, at: position, effectiveRange: nil).map { ($0, position) }
        }
        let anchor = event.modifierFlags.contains(.shift) ? selectedRange() : NSRange(location: index, length: 0)
        func select(to index: Int) {
            let current = selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: granularity)
            let anchored = selectionRange(forProposedRange: anchor, granularity: granularity)
            setSelectedRange(NSUnionRange(anchored, current), affinity: .downstream, stillSelecting: true)
        }
        select(to: index)
        var dragged = false
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            dragged = true
            autoscroll(with: next)
            select(to: characterIndex(atViewPoint: convert(next.locationInWindow, from: nil)))
        }
        setSelectedRanges(selectedRanges, affinity: .downstream, stillSelecting: false)
        if !dragged, event.clickCount == 1, let (value, position) = link {
            setSelectedRange(NSRange(location: position, length: 0))
            clicked(onLink: value, at: position)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if let hit = tableFragment(at: point), let character = hit.fragment.character(at: hit.local),
           textStorage?.attribute(.link, at: hit.start + character, effectiveRange: nil) != nil {
            NSCursor.pointingHand.set()
        }
    }

    // NSTextFinderClient methods that NSTextView implements without declaring
    // them; the find bar asks them where to highlight a match.

    @objc(rectsForCharacterRange:)
    func findRects(forCharacterRange range: NSRange) -> [NSValue]? {
        if intersectsTable(range) {
            return tableRects(for: range).map { NSValue(rect: $0) }
        }
        typealias Function = @convention(c) (AnyObject, Selector, NSRange) -> [NSValue]?
        let selector = #selector(findRects(forCharacterRange:))
        guard let implementation = class_getMethodImplementation(NSTextView.self, selector) else { return nil }
        return unsafeBitCast(implementation, to: Function.self)(self, selector, range)
    }

    @objc(drawCharactersInRange:forContentView:)
    func findDrawCharacters(in range: NSRange, forContentView view: NSView) {
        if intersectsTable(range), let context = NSGraphicsContext.current?.cgContext {
            textStorage?.enumerateAttribute(.kayakomaTable, in: NSIntersectionRange(range, textStorage?.fullRange ?? range)) { value, run, _ in
                guard value != nil, let (fragment, start) = tableFragment(atCharacter: run.location) else { return }
                let origin = fragment.layoutFragmentFrame.origin
                let container = textContainerOrigin
                fragment.drawText(
                    in: NSRange(location: run.location - start, length: run.length),
                    at: CGPoint(x: origin.x + container.x, y: origin.y + container.y),
                    in: context
                )
            }
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, NSRange, NSView) -> Void
        let selector = #selector(findDrawCharacters(in:forContentView:))
        guard let implementation = class_getMethodImplementation(NSTextView.self, selector) else { return }
        unsafeBitCast(implementation, to: Function.self)(self, selector, range, view)
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let storage = textStorage else { return false }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return false }
        let selection = NSMutableAttributedString()
        for range in ranges {
            selection.append(storage.attributedSubstring(from: range))
        }
        selection.mutableString.replaceOccurrences(of: lineSeparator, with: "\n", range: NSRange(location: 0, length: selection.length))
        // A table's text carries a one-point line height that only serves its
        // hidden layout; pasted elsewhere, it takes the default style.
        selection.enumerateAttribute(.kayakomaTable, in: selection.fullRange) { value, range, _ in
            if value != nil { selection.removeAttribute(.paragraphStyle, range: range) }
        }
        selection.removeAttribute(.kayakomaTable, range: selection.fullRange)
        selection.removeAttribute(.kayakomaDecoration, range: selection.fullRange)
        // Pasted elsewhere, a code span keeps a plain background.
        selection.enumerateAttribute(.kayakomaInlineCode, in: selection.fullRange) { value, range, _ in
            guard let style = value as? InlineCodeStyle else { return }
            selection.addAttribute(.backgroundColor, value: style.color, range: range)
        }
        selection.removeAttribute(.kayakomaInlineCode, range: selection.fullRange)
        pboard.clearContents()
        var written = pboard.setString(selection.string, forType: .string)
        if types.contains(.rtf),
           let rtf = selection.rtf(from: selection.fullRange, documentAttributes: [:]) {
            written = pboard.setData(rtf, forType: .rtf) || written
        }
        return written
    }
}

// MARK: - Tables

/// A table's layout fragment has no line fragments, so TextKit neither
/// highlights the selection in it nor maps clicks to its characters. The text
/// view does both through the fragment.
extension MarkdownTextView {
    /// The table fragment holding the character at `index`, and the offset of its paragraph.
    func tableFragment(atCharacter index: Int) -> (fragment: TableLayoutFragment, start: Int)? {
        guard let storage = textStorage, index >= 0, index < storage.length,
              storage.attribute(.kayakomaTable, at: index, effectiveRange: nil) != nil,
              let layoutManager = textLayoutManager,
              let location = layoutManager.location(layoutManager.documentRange.location, offsetBy: index),
              let fragment = layoutManager.textLayoutFragment(for: location) as? TableLayoutFragment else { return nil }
        let start = layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        return (fragment, start)
    }

    /// The table under a point of the view: its fragment, the paragraph's
    /// offset, and the point in the fragment's coordinates.
    func tableFragment(at point: NSPoint) -> (fragment: TableLayoutFragment, start: Int, local: CGPoint)? {
        guard let layoutManager = textLayoutManager else { return nil }
        let origin = textContainerOrigin
        let inContainer = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: inContainer) as? TableLayoutFragment else { return nil }
        let frame = fragment.layoutFragmentFrame
        let local = CGPoint(x: inContainer.x - frame.minX, y: inContainer.y - frame.minY)
        guard fragment.containsTable(local) else { return nil }
        let start = layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        return (fragment, start, local)
    }

    /// Rectangles, in view coordinates, of the parts of `range` that are in tables.
    func tableRects(for range: NSRange) -> [NSRect] {
        guard let storage = textStorage else { return [] }
        let clamped = NSIntersectionRange(range, storage.fullRange)
        guard clamped.length > 0 else { return [] }
        var rects: [NSRect] = []
        storage.enumerateAttribute(.kayakomaTable, in: clamped) { value, run, _ in
            guard value != nil, let (fragment, start) = tableFragment(atCharacter: run.location) else { return }
            let origin = fragment.layoutFragmentFrame.origin
            let container = textContainerOrigin
            for rect in fragment.rects(for: NSRange(location: run.location - start, length: run.length)) {
                rects.append(rect.offsetBy(dx: origin.x + container.x, dy: origin.y + container.y))
            }
        }
        return rects
    }

    func intersectsTable(_ range: NSRange) -> Bool {
        guard let storage = textStorage else { return false }
        let clamped = NSIntersectionRange(range, storage.fullRange)
        guard clamped.length > 0 else { return false }
        var found = false
        storage.enumerateAttribute(.kayakomaTable, in: clamped) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }

    /// Character boundary nearest to a point of the view, tables included.
    func characterIndex(atViewPoint point: NSPoint) -> Int {
        if let hit = tableFragment(at: point) {
            return hit.start + hit.fragment.characterIndex(at: hit.local)
        }
        return characterIndexForInsertion(at: point)
    }
}

extension URL {
    /// The anchor of a fragment-only link such as `#usage`, which points
    /// inside the document; `nil` for any other link.
    var inDocumentAnchor: String? {
        guard scheme == nil, host == nil, path.isEmpty, let fragment = fragment(percentEncoded: false), !fragment.isEmpty else { return nil }
        return fragment
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
