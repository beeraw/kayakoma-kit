import SwiftUI

/// SwiftUI wrapper around `MarkdownView`.
public struct MarkdownPreview: NSViewRepresentable {
    private let source: String
    private let theme: Theme
    private let baseURL: URL?

    /// - Parameter baseURL: directory that relative image paths and links are resolved against.
    public init(source: String, theme: Theme = .default, baseURL: URL? = nil) {
        self.source = source
        self.theme = theme
        self.baseURL = baseURL
    }

    public func makeNSView(context: Context) -> MarkdownView {
        MarkdownView()
    }

    public func updateNSView(_ view: MarkdownView, context: Context) {
        view.theme = theme
        view.baseURL = baseURL
        if view.document?.source != source {
            view.document = RenderedDocument(source: source)
        }
    }
}
