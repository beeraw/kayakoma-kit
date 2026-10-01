import AppKit
import PDFKit
import Testing
@testable import KayakomaKit

private func pdf(_ source: String, baseURL: URL? = nil, pageSize: CGSize = MarkdownPDFExporter.a4) throws -> PDFDocument {
    let data = MarkdownPDFExporter(baseURL: baseURL, pageSize: pageSize).pdfData(for: RenderedDocument(source: source))
    return try #require(PDFDocument(data: data))
}

private func pageTexts(_ document: PDFDocument) -> [String] {
    (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
}

@Test func pdfTextIsRealText() throws {
    let document = try pdf("# Greetings\n\nA paragraph with **bold** words and `code`.\n\n- an item\n\n| Key | Value |\n|-----|-------|\n| width | 640 |")
    #expect(document.pageCount == 1)
    let text = try #require(document.page(at: 0)?.string)
    for word in ["Greetings", "paragraph", "bold", "code", "an item", "Key", "Value", "width", "640"] {
        #expect(text.contains(word), "missing \(word)")
    }
    #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Greetings")
}

@Test func emptyDocumentGivesOneBlankPage() throws {
    #expect(try pdf("").pageCount == 1)
}

@Test func pageBreaksNeverCutALine() throws {
    let source = (1...120).map { "Line number \($0) stands alone." }.joined(separator: "\n\n")
    let texts = pageTexts(try pdf(source, pageSize: CGSize(width: 400, height: 500)))
    #expect(texts.count > 3)
    for number in 1...120 {
        // Each line is drawn once, whole, on exactly one page.
        let pages = texts.filter { $0.contains("Line number \(number) stands alone.") }
        #expect(pages.count == 1, "line \(number) on \(pages.count) pages")
    }
}

@Test func longTablesBreakBetweenRowsAndRepeatTheirHeader() throws {
    let rows = (1...80).map { "| row \($0) | value \($0) |" }.joined(separator: "\n")
    let texts = pageTexts(try pdf("| Name | Amount |\n|------|--------|\n\(rows)", pageSize: CGSize(width: 400, height: 500)))
    #expect(texts.count > 2)
    for number in 1...80 {
        // Each row is drawn whole on exactly one page.
        let row = try NSRegularExpression(pattern: "row \(number)\\b[\\s\\S]*value \(number)\\b")
        let pages = texts.filter { row.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        #expect(pages.count == 1, "row \(number) on \(pages.count) pages")
    }
    for text in texts {
        #expect(text.contains("Name") && text.contains("Amount"))
    }
}

@Test func pdfUsesTheLightAppearance() throws {
    var data = Data()
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
        data = MarkdownPDFExporter().pdfData(for: RenderedDocument(source: "# Dark or light\n\nSome body text."))
    }
    let page = try #require(PDFDocument(data: data)?.page(at: 0))
    let image = page.thumbnail(of: NSSize(width: 595, height: 842), for: .mediaBox)
    let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    func brightness(_ x: Int, _ y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.brightnessComponent ?? -1
    }
    #expect(brightness(5, 5) > 0.95)
    var darkest: CGFloat = 1
    for y in stride(from: 0, to: 200, by: 1) {
        for x in stride(from: 50, to: 400, by: 2) { darkest = min(darkest, brightness(x, y)) }
    }
    #expect(darkest < 0.3)
}

@Test func pdfLinksPointOutAndInside() throws {
    let document = try pdf("# Top\n\nSee [the site](https://example.com) or [the end](#the-end).\n\n## The end\n\nDone.")
    let annotations = try #require(document.page(at: 0)?.annotations)
    #expect(annotations.contains { $0.url?.absoluteString == "https://example.com" || ($0.action as? PDFActionURL)?.url?.absoluteString == "https://example.com" })
    #expect(annotations.contains { $0.destination != nil || $0.action is PDFActionGoTo })
}

@Test func imagesThatDoNotFitMoveToTheNextPage() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kayakoma-pdf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try pngData(width: 200, height: 200, color: .systemBlue).write(to: folder.appendingPathComponent("square.png"))

    let source = (1...12).map { "Paragraph \($0)." }.joined(separator: "\n\n") + "\n\n![square](square.png)"
    let layout = PagedLayout(document: RenderedDocument(source: source), theme: .default, baseURL: folder, size: CGSize(width: 300, height: 400))
    #expect(layout.pages.count == 2)
    // The image line is alone on the second page, whole.
    #expect(layout.pages.last.map { layout.atoms[$0.atoms].map(\.height) }?.first ?? 0 >= 200)
}

@Test func tallImagesAreScaledToFitAPage() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kayakoma-pdf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try pngData(width: 200, height: 3000, color: .systemGreen).write(to: folder.appendingPathComponent("tall.png"))

    let size = CGSize(width: 300, height: 400)
    let layout = PagedLayout(document: RenderedDocument(source: "Intro.\n\n![tall](tall.png)\n\nAfter."), theme: .default, baseURL: folder, size: size)
    #expect(layout.atoms.allSatisfy { $0.height <= size.height + 0.5 })
    #expect(!layout.atoms.contains { $0.isCut })
    #expect(layout.atoms.count == 3)
    // Scaled down from 3,000 points to most of a page, not cropped.
    #expect(layout.atoms[1].height > size.height * 0.75)
}

// MARK: - Page breaker

private func atom(_ top: CGFloat, _ bottom: CGFloat, _ index: Int, keep: Bool = false) -> PageBreaker.Atom {
    PageBreaker.Atom(top: top, bottom: bottom, part: .init(fragment: 0, index: index), keepWithNext: keep)
}

@Test func pageBreakerFillsPagesWithWholeAtoms() {
    let atoms = (0..<10).map { atom(CGFloat($0) * 30, CGFloat($0) * 30 + 25, $0) }
    let (_, pages) = PageBreaker.pages(for: atoms, height: 100)
    // 4 atoms take 115 points: only 3 fit (85 points).
    #expect(pages.map(\.atoms) == [0..<3, 3..<6, 6..<9, 9..<10])
}

@Test func pageBreakerKeepsHeadingsWithTheirText() {
    let atoms = [atom(0, 40, 0), atom(50, 80, 1, keep: true), atom(90, 130, 2)]
    let (_, pages) = PageBreaker.pages(for: atoms, height: 100)
    #expect(pages.map(\.atoms) == [0..<1, 1..<3])
}

@Test func pageBreakerRepeatsTableHeaders() {
    var atoms = [atom(0, 21, 0, keep: true)]
    for row in 1...6 {
        var body = atom(CGFloat(row) * 20, CGFloat(row) * 20 + 21, row)
        body.header = 0
        body.headerHeight = 20
        atoms.append(body)
    }
    let (_, pages) = PageBreaker.pages(for: atoms, height: 70)
    #expect(pages.first?.header == nil)
    #expect(pages.dropFirst().allSatisfy { $0.header == 0 })
    #expect(pages.flatMap { Array($0.atoms) } == Array(0...6))
}

@Test func pageBreakerCutsOnlyAtomsTallerThanAPage() {
    let (atoms, pages) = PageBreaker.pages(for: [atom(0, 10, 0), atom(10, 260, 1), atom(260, 270, 2)], height: 100)
    #expect(atoms.filter(\.isCut).count == 3)
    #expect(atoms.allSatisfy { $0.height <= 100 })
    #expect(pages.count == 4)
}

func pngData(width: Int, height: Int, color: NSColor) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
