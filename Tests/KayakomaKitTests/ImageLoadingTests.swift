import AppKit
import Testing
@testable import KayakomaKit

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kayakoma-images-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func imageSizesComeFromTheHeader() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("wide.png")
    try pngData(width: 640, height: 120, color: .systemRed).write(to: url)

    let store = ImageStore(capacity: 2)
    let info = try #require(store.info(for: url))
    #expect(info.size == CGSize(width: 640, height: 120))
    // Reading the size does not decode the pixels.
    #expect(store.cachedImage(for: info.key) == nil)
    #expect(store.image(for: info)?.size == CGSize(width: 640, height: 120))
    #expect(store.cachedImage(for: info.key) != nil)
    #expect(store.info(for: folder.appendingPathComponent("missing.png")) == nil)
}

@Test func imageCacheIsKeyedByModificationDateAndStaysSmall() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ImageStore(capacity: 2)
    var infos: [ImageStore.Info] = []
    for index in 0..<3 {
        let url = folder.appendingPathComponent("image-\(index).png")
        try pngData(width: 10, height: 10, color: .systemBlue).write(to: url)
        infos.append(try #require(store.info(for: url)))
        _ = store.image(for: infos[index])
    }
    // The least recently used image left the cache.
    #expect(store.cachedImage(for: infos[0].key) == nil)
    #expect(store.cachedImage(for: infos[2].key) != nil)

    // Rewriting a file gives it a new key.
    let url = infos[2].key.url
    try pngData(width: 20, height: 10, color: .systemBlue).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
    let edited = try #require(store.info(for: url))
    #expect(edited.key != infos[2].key)
    #expect(edited.size.width == 20)
}

@MainActor
@Test func localImagesLoadOffTheMainThread() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try pngData(width: 300, height: 200, color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        .write(to: folder.appendingPathComponent("red.png"))

    let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.appearance = NSAppearance(named: .aqua)
    view.baseURL = folder
    view.document = RenderedDocument(source: "![red](red.png)")
    let storage = try #require(view.textView.textStorage)
    let attachment = try #require(storage.attribute(.attachment, at: 0, effectiveRange: nil) as? ImageAttachment)
    // Rendering read the size only: the space is reserved, the pixels are not decoded yet.
    #expect(!attachment.isLoaded)
    #expect(attachment.info.size == CGSize(width: 300, height: 200))

    var redraws = 0
    let observer = NotificationCenter.default.addObserver(forName: .kayakomaImageDidLoad, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { redraws += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    // The first drawing asks for the pixels; they arrive a little later.
    view.layoutSubtreeIfNeeded()
    _ = render(view)
    let deadline = Date().addingTimeInterval(5)
    while redraws == 0, Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(redraws > 0)
    let bitmap = try #require(render(view))
    #expect(attachment.isLoaded)
    // The middle of the image's frame is red.
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    let inset = view.textView.textContainerInset
    let color = bitmap.colorAt(x: Int((inset.width + 150) * scale), y: Int((inset.height + 100) * scale))?.usingColorSpace(.sRGB)
    #expect((color?.redComponent ?? 0) > 0.9 && (color?.greenComponent ?? 1) < 0.2)
}

@MainActor
private func render(_ view: NSView) -> NSBitmapImageRep? {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

@Test func remoteImagesStayPlaceholders() {
    let text = BlockBuilder(theme: .default, baseURL: nil, loadsImagesSynchronously: true)
        .build(RenderedDocument(source: "![logo](https://example.com/logo.png)").blocks[0].markup.markup)
    #expect(text.attribute(.attachment, at: 0, effectiveRange: nil) is PlaceholderAttachment)
    #expect(text.string.contains("logo"))
}
