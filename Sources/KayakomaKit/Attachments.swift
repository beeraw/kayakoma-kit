import AppKit

/// Text container of a paged layout: images are scaled down to fit a page.
final class PageTextContainer: NSTextContainer {
    var maximumAttachmentHeight: CGFloat = .greatestFiniteMagnitude
}

/// A local image, scaled down to the width of the line it sits on.
///
/// Its size comes from the file's header, so the layout reserves the right
/// space at once; the pixels are decoded off the main thread the first time
/// the image is drawn, and a placeholder of the same size stands in until then.
final class ImageAttachment: NSTextAttachment {
    let info: ImageStore.Info
    private var picture: NSImage?
    private let store: ImageStore

    /// - Parameter image: the decoded image when it is already at hand.
    init(info: ImageStore.Info, image: NSImage?, store: ImageStore = .shared) {
        self.info = info
        self.store = store
        picture = image
        super.init(data: nil, ofType: nil)
        // TextKit asks `image(for:…)` only of attachments that have an image.
        self.image = image ?? Self.placeholder(size: info.size)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var isLoaded: Bool { picture != nil }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let size = info.size
        guard size.width > 0, size.height > 0 else { return .zero }
        let available = max(proposedLineFragment.width - position.x - 1, 16)
        let maximumHeight = (textContainer as? PageTextContainer)?.maximumAttachmentHeight ?? .greatestFiniteMagnitude
        let scale = min(1, available / size.width, maximumHeight / size.height)
        return CGRect(x: 0, y: 0, width: floor(size.width * scale), height: floor(size.height * scale))
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSImage? {
        if let picture { return picture }
        if let cached = store.cachedImage(for: info.key) {
            picture = cached
            image = cached
            return cached
        }
        store.load(info)
        return Self.placeholder(size: bounds.size)
    }

    /// A quiet rounded panel with a picture symbol, the size of the image.
    static func placeholder(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.quaternarySystemFill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            let side = min(32, rect.width / 2, rect.height / 2)
            guard side >= 8, let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) else { return true }
            let configured = symbol.withSymbolConfiguration(.init(hierarchicalColor: .tertiaryLabelColor)) ?? symbol
            configured.draw(in: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
            return true
        }
    }
}

/// Discreet icon standing for an image that cannot be shown (missing file,
/// remote URL).
final class PlaceholderAttachment: NSTextAttachment {
    init(size: CGFloat) {
        super.init(data: nil, ofType: nil)
        let side = round(size * 1.05)
        image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) else { return false }
            let configured = symbol.withSymbolConfiguration(.init(hierarchicalColor: .secondaryLabelColor)) ?? symbol
            configured.draw(in: rect.insetBy(dx: 0.5, dy: 1.5))
            return true
        }
        bounds = CGRect(x: 0, y: -round(size * 0.18), width: side, height: side)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

/// Read-only checkbox of a task list item, drawn to follow the appearance.
enum CheckboxAttachment {
    static func string(checked: Bool, size: CGFloat) -> NSAttributedString {
        let side = round(size * 0.95)
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let box = rect.insetBy(dx: 0.75, dy: 0.75)
            let path = NSBezierPath(roundedRect: box, xRadius: side * 0.22, yRadius: side * 0.22)
            if checked {
                NSColor.controlAccentColor.setFill()
                path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: box.minX + box.width * 0.24, y: box.minY + box.height * 0.52))
                check.line(to: NSPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.30))
                check.line(to: NSPoint(x: box.minX + box.width * 0.77, y: box.minY + box.height * 0.72))
                check.lineWidth = max(1.5, side * 0.12)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1
                NSColor.secondaryLabelColor.setStroke()
                path.stroke()
            }
            return true
        }
        attachment.bounds = CGRect(x: 0, y: -round(size * 0.14), width: side, height: side)
        return NSAttributedString(attachment: attachment)
    }
}
