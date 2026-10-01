import AppKit
import ImageIO

extension Notification.Name {
    /// Posted on the main thread when `ImageStore` has decoded an image that
    /// an attachment asked for; the object is the `ImageStore.Key`.
    static let kayakomaImageDidLoad = Notification.Name("app.kayakoma.imageDidLoad")
}

/// Local images shared by every document: their size, read from the file's
/// header, and a small cache of decoded images, keyed by file URL and
/// modification date so that an edited file is read again.
///
/// Only files are read. Remote (`http`, `https`) images are never fetched:
/// the engine makes no network access, for privacy and because a Quick Look
/// extension's sandbox would not allow it; they show as placeholders.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    struct Key: Hashable, Sendable {
        let url: URL
        let modificationDate: Date?
    }

    /// What is known about a file before it is decoded.
    struct Info: Sendable {
        let key: Key
        /// Size in points, as `NSImage` would report it.
        let size: CGSize
    }

    /// Decoded images beyond this many pixels on their longest side are scaled down.
    static let maximumPixelSize = 4096

    private let lock = NSLock()
    private var infos: [Key: Info] = [:]
    private var images: [Key: NSImage] = [:]
    /// Most recently used last.
    private var order: [Key] = []
    private var loading: Set<Key> = []
    private let capacity: Int

    init(capacity: Int = 32) {
        self.capacity = capacity
    }

    /// The size of the image at `url`, from its header; `nil` when the file
    /// is missing or is not an image. Vector images (PDF, SVG) are decoded
    /// here, as their size needs the whole file.
    func info(for url: URL) -> Info? {
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let key = Key(url: url, modificationDate: date)
        if let info = lock.withLock({ infos[key] }) { return info }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let info: Info
        if let size = Self.headerSize(of: url) {
            info = Info(key: key, size: size)
        } else if let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0, image.size.height > 0 {
            info = Info(key: key, size: image.size)
            store(image, for: key)
        } else {
            return nil
        }
        lock.withLock { infos[key] = info }
        return info
    }

    /// The decoded image if it is in the cache.
    func cachedImage(for key: Key) -> NSImage? {
        lock.withLock {
            guard let image = images[key] else { return nil }
            touch(key)
            return image
        }
    }

    /// The decoded image, decoding it on the calling thread if needed.
    func image(for info: Info) -> NSImage? {
        if let image = cachedImage(for: info.key) { return image }
        guard let image = Self.decode(info) else { return nil }
        store(image, for: info.key)
        return image
    }

    /// Decodes the image in the background unless it is cached or already
    /// loading, then posts `kayakomaImageDidLoad` on the main thread.
    func load(_ info: Info) {
        let start = lock.withLock { () -> Bool in
            guard images[info.key] == nil, !loading.contains(info.key) else { return false }
            loading.insert(info.key)
            return true
        }
        guard start else { return }
        Task.detached(priority: .userInitiated) { [self] in
            let image = Self.decode(info)
            lock.withLock { _ = loading.remove(info.key) }
            guard let image else { return }
            store(image, for: info.key)
            await MainActor.run {
                NotificationCenter.default.post(name: .kayakomaImageDidLoad, object: info.key)
            }
        }
    }

    private func store(_ image: NSImage, for key: Key) {
        lock.withLock {
            images[key] = image
            touch(key)
            while order.count > capacity {
                images[order.removeFirst()] = nil
            }
        }
    }

    /// Marks a key as most recently used; the lock must be held.
    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    // MARK: - Decoding

    private static func headerSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        // Points, as NSImage counts them: pixels at the file's resolution.
        let dpiX = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let dpiY = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
        var size = CGSize(width: width * 72 / (dpiX > 0 ? dpiX : 72), height: height * 72 / (dpiY > 0 ? dpiY : 72))
        // EXIF orientations 5 to 8 turn the picture a quarter turn.
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(orientation) {
            size = CGSize(width: size.height, height: size.width)
        }
        return size
    }

    private static func decode(_ info: Info) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(info.key.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return NSImage(contentsOf: info.key.url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: info.key.url)
        }
        return NSImage(cgImage: image, size: info.size)
    }
}
