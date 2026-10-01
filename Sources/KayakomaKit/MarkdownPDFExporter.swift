import AppKit

/// Renders a Markdown document to PDF with the drawing code of `MarkdownView`,
/// without a view or a window: it works from an app, a Quick Look extension
/// or a command-line tool, on any thread.
///
/// - Page breaks never cut a line of text: paragraphs, lists and code blocks
///   break between lines, and tables between rows, with the header row
///   repeated at the top of the next page. A heading stays with what follows
///   it. An image that does not fit moves to the next page, and one taller
///   than a page is scaled down to fit.
/// - Text is real text, which can be selected, searched and copied. Links
///   stay clickable; links to `#anchor` jump to their heading.
/// - Colors are always those of the light appearance, whatever the system's.
/// - The page margins replace the theme's `contentMargins` and `maxLineWidth`.
/// - Images are read from files only; remote images show as placeholders.
///
/// ```swift
/// let exporter = MarkdownPDFExporter(baseURL: fileURL.deletingLastPathComponent())
/// let data = exporter.pdfData(for: RenderedDocument(source: text))
/// ```
public struct MarkdownPDFExporter: Sendable {
    public var theme: Theme
    /// Directory that relative image paths and links are resolved against.
    public var baseURL: URL?
    /// Size of a page, in points.
    public var pageSize: CGSize
    /// Space between the edges of a page and the text, in points.
    public var margins: NSEdgeInsets

    /// ISO A4, 210 × 297 mm.
    public static let a4 = CGSize(width: 595.28, height: 841.89)
    /// US Letter, 8.5 × 11 in.
    public static let letter = CGSize(width: 612, height: 792)

    public init(
        theme: Theme = .default,
        baseURL: URL? = nil,
        pageSize: CGSize = MarkdownPDFExporter.a4,
        margins: NSEdgeInsets = NSEdgeInsets(top: 56, left: 56, bottom: 56, right: 56)
    ) {
        self.theme = theme
        self.baseURL = baseURL
        self.pageSize = pageSize
        self.margins = margins
    }

    /// The document as PDF data; an empty document gives one blank page.
    public func pdfData(for document: RenderedDocument) -> Data {
        let data = NSMutableData()
        if let light = NSAppearance(named: .aqua) {
            light.performAsCurrentDrawingAppearance { render(document, into: data) }
        } else {
            render(document, into: data)
        }
        return data as Data
    }

    private func render(_ document: RenderedDocument, into data: NSMutableData) {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        var info: [CFString: Any] = [:]
        if let heading = document.blocks.first(where: { $0.anchor != nil }) {
            info[kCGPDFContextTitle] = HeadingSlugger.text(of: heading.markup.markup)
        }
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else { return }

        let content = CGRect(
            x: margins.left,
            y: margins.top,
            width: max(pageSize.width - margins.left - margins.right, 1),
            height: max(pageSize.height - margins.top - margins.bottom, 1)
        )
        let layout = PagedLayout(document: document, theme: theme, baseURL: baseURL, size: content.size)
        let background = theme.backgroundColor.nsColor
        let pageHeight = pageSize.height
        /// Flipped page coordinates to PDF default user space.
        func userSpace(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: pageHeight - rect.maxY, width: rect.width, height: rect.height)
        }

        for page in layout.pages.isEmpty ? [nil] : layout.pages.map(Optional.some) {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: pageHeight)
            context.scaleBy(x: 1, y: -1)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            background.setFill()
            CGRect(origin: .zero, size: pageSize).fill()
            let marks = page.map { layout.draw($0, in: context, at: content.origin, pageWidth: pageSize.width) } ?? PagedLayout.Marks()
            NSGraphicsContext.current = previous
            context.restoreGState()

            // Annotations are placed in default user space, outside the flip.
            for (name, point) in marks.anchors {
                context.addDestination(name as CFString, at: CGPoint(x: point.x, y: pageHeight - point.y))
            }
            for (url, rect) in marks.links {
                if let anchor = url.inDocumentAnchor {
                    guard let index = document.blockIndex(forAnchor: anchor), let name = document.blocks[index].anchor else { continue }
                    context.setDestination(name as CFString, for: userSpace(rect))
                } else if url.scheme != nil {
                    context.setURL(url as CFURL, for: userSpace(rect))
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
    }
}

/// A document laid out at the width of a page, cut into pages.
final class PagedLayout {
    /// What a page drew besides its content, in flipped page coordinates.
    struct Marks {
        var anchors: [(name: String, point: CGPoint)] = []
        var links: [(url: URL, rect: CGRect)] = []
    }

    private let contentStorage = NSTextContentStorage()
    private let layoutManager = NSTextLayoutManager()
    private let layoutDelegate = LayoutDelegate()
    private(set) var fragments: [NSTextLayoutFragment] = []
    /// Anchor of each heading's fragment, by fragment index.
    private var anchors: [Int: String] = [:]
    private(set) var atoms: [PageBreaker.Atom] = []
    private(set) var pages: [PageBreaker.Page] = []

    init(document: RenderedDocument, theme: Theme, baseURL: URL?, size: CGSize) {
        let builder = BlockBuilder(theme: theme, baseURL: baseURL, loadsImagesSynchronously: true)
        let text = NSMutableAttributedString()
        var anchorStarts: [Int: String] = [:]
        for block in document.blocks {
            if let anchor = block.anchor { anchorStarts[text.length] = anchor }
            text.append(builder.build(block.markup.markup))
        }

        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.delegate = layoutDelegate
        let container = PageTextContainer(size: CGSize(width: size.width, height: 0))
        container.lineFragmentPadding = 0
        // An image's line is taller than the image by its line height multiple
        // (at most 1.15 outside body text) and a little rounding.
        container.maximumAttachmentHeight = floor(size.height / max(theme.lineHeightMultiple, 1.15)) - 4
        layoutManager.textContainer = container
        contentStorage.attributedString = text
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        let start = layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            guard !fragment.rangeInElement.isEmpty else { return true }
            let offset = layoutManager.offset(from: start, to: fragment.rangeInElement.location)
            if let anchor = anchorStarts[offset] { anchors[fragments.count] = anchor }
            fragments.append(fragment)
            return true
        }

        var atoms: [PageBreaker.Atom] = []
        for (index, fragment) in fragments.enumerated() {
            let frame = fragment.layoutFragmentFrame
            if let table = fragment as? TableLayoutFragment {
                let edges = table.rowEdges
                let header = atoms.count
                for row in 0..<max(edges.count - 1, 0) {
                    var atom = PageBreaker.Atom(
                        top: frame.minY + edges[row],
                        bottom: frame.minY + edges[row + 1] + TableBlock.borderWidth,
                        part: .init(fragment: index, index: row)
                    )
                    if row == 0 {
                        atom.keepWithNext = edges.count > 2
                    } else {
                        atom.header = header
                        atom.headerHeight = edges[1] - edges[0]
                    }
                    atoms.append(atom)
                }
                continue
            }
            // The empty line TextKit adds after the document's last line break
            // shows nothing; it must not take room on a page.
            let lines = fragment.textLineFragments.enumerated().filter { $0.element.characterRange.length > 0 }
            let padding = (fragment as? BlockLayoutFragment)?.codePadding ?? (0, 0)
            let isHeading = Self.isHeading(fragment)
            for (position, (number, line)) in lines.enumerated() {
                let bounds = line.typographicBounds
                let isLast = position == lines.count - 1
                atoms.append(PageBreaker.Atom(
                    top: frame.minY + bounds.minY - (position == 0 ? padding.top : 0),
                    bottom: frame.minY + bounds.maxY + (isLast ? padding.bottom : 0),
                    part: .init(fragment: index, index: number),
                    keepWithNext: isHeading && isLast
                ))
            }
        }
        (self.atoms, pages) = PageBreaker.pages(for: atoms, height: size.height)
    }

    private static func isHeading(_ fragment: NSTextLayoutFragment) -> Bool {
        guard let paragraph = fragment.textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
              let style = paragraph.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        else { return false }
        return style.headerLevel > 0
    }

    // MARK: - Drawing

    /// Draws a page with the top left corner of its content at `origin`, in a
    /// flipped context, and returns where its anchors and links are.
    func draw(_ page: PageBreaker.Page, in context: CGContext, at origin: CGPoint, pageWidth: CGFloat) -> Marks {
        var marks = Marks()
        var y = origin.y
        let first = atoms[page.atoms.lowerBound]
        if let header = page.header {
            let top = atoms[header].top
            drawSlice([header], top: top, bottom: top + first.headerHeight, at: CGPoint(x: origin.x, y: y),
                      pageWidth: pageWidth, in: context, marks: &marks)
            y += first.headerHeight
        }
        drawSlice(Array(page.atoms), top: first.top, bottom: atoms[page.atoms.upperBound - 1].bottom,
                  at: CGPoint(x: origin.x, y: y), pageWidth: pageWidth, in: context, marks: &marks)
        return marks
    }

    /// Draws the atoms `indices`, which lie between `top` and `bottom` in the
    /// document, with `top` at `point.y`. Backgrounds are clipped to the
    /// slice; lines are drawn whole, so that no glyph is cut.
    private func drawSlice(
        _ indices: [Int], top: CGFloat, bottom: CGFloat, at point: CGPoint,
        pageWidth: CGFloat, in context: CGContext, marks: inout Marks
    ) {
        let clip = CGRect(x: 0, y: point.y, width: pageWidth, height: bottom - top)
        var groups: [(fragment: Int, parts: [Int], cut: Bool)] = []
        for index in indices {
            let atom = atoms[index]
            if groups.last?.fragment == atom.part.fragment {
                if groups[groups.count - 1].parts.last != atom.part.index { groups[groups.count - 1].parts.append(atom.part.index) }
                groups[groups.count - 1].cut = groups[groups.count - 1].cut || atom.isCut
            } else {
                groups.append((atom.part.fragment, [atom.part.index], atom.isCut))
            }
        }

        for group in groups {
            let fragment = fragments[group.fragment]
            let frame = fragment.layoutFragmentFrame
            let at = CGPoint(x: point.x + frame.minX, y: point.y + frame.minY - top)
            let paragraph = (fragment.textElement as? NSTextParagraph)?.attributedString

            if let table = fragment as? TableLayoutFragment {
                let rows = IndexSet(group.parts)
                context.saveGState()
                context.clip(to: clip)
                table.draw(at: at, in: context, rows: rows)
                context.restoreGState()
                if let paragraph {
                    let edges = table.rowEdges
                    paragraph.enumerateAttribute(.link, in: paragraph.fullRange) { value, range, _ in
                        guard let url = value as? URL else { return }
                        for rect in table.rects(for: range) where rows.contains(where: { edges[$0] <= rect.midY && rect.midY < edges[$0 + 1] }) {
                            marks.links.append((url, rect.offsetBy(dx: at.x, dy: at.y)))
                        }
                    }
                }
                continue
            }

            if let block = fragment as? BlockLayoutFragment {
                context.saveGState()
                context.clip(to: clip)
                block.drawBackgrounds(at: at, in: context)
                context.restoreGState()
            }
            if group.cut {
                context.saveGState()
                context.clip(to: clip)
            }
            let lines = fragment.textLineFragments
            for index in group.parts where index < lines.count {
                let line = lines[index]
                let bounds = line.typographicBounds
                line.draw(at: CGPoint(x: at.x + bounds.minX, y: at.y + bounds.minY), in: context)
                if index == 0, let anchor = anchors[group.fragment] {
                    marks.anchors.append((anchor, CGPoint(x: at.x + bounds.minX, y: at.y + bounds.minY)))
                }
                line.attributedString.enumerateAttribute(.link, in: line.characterRange) { value, range, _ in
                    guard let url = value as? URL else { return }
                    let start = line.locationForCharacter(at: range.location).x
                    let end = line.locationForCharacter(at: range.upperBound).x
                    marks.links.append((url, CGRect(x: at.x + bounds.minX + start, y: at.y + bounds.minY, width: end - start, height: bounds.height)))
                }
            }
            if group.cut { context.restoreGState() }
        }
    }
}
