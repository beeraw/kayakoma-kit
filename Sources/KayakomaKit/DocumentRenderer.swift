import AppKit

/// Keeps the attributed text of each block and rebuilds only the blocks whose
/// source text changed.
///
/// Blocks are keyed by their source text (and the resolved targets of their
/// links, see `RenderedDocument.Block.reuseKey`): a block whose key is
/// unchanged reuses its previous rendering, wherever it moved in the document.
@MainActor
final class DocumentRenderer {
    /// A replacement to apply to the text storage to reach the new document.
    struct Edit {
        let range: NSRange
        let replacement: NSAttributedString
    }

    var theme: Theme = .default {
        didSet { if theme != oldValue { invalidate() } }
    }
    var baseURL: URL? {
        didSet { if baseURL != oldValue { invalidate() } }
    }

    private(set) var blocks: [RenderedDocument.Block] = []
    private var pieces: [NSAttributedString] = []
    /// Start offset of each block in the text storage, followed by the total length.
    private(set) var offsets: [Int] = [0]
    private var cache: [String: NSAttributedString] = [:]
    private var needsFullRebuild = false
    /// Number of blocks built since the renderer was created; used by tests.
    private(set) var buildCount = 0

    /// Brings the renderer to `document` and returns the storage edit that does the same.
    func update(to document: RenderedDocument) -> Edit {
        let builder = BlockBuilder(theme: theme, baseURL: baseURL)
        if needsFullRebuild { cache.removeAll() }
        var newCache: [String: NSAttributedString] = [:]
        let newPieces = document.blocks.map { block in
            if let piece = newCache[block.reuseKey] ?? cache[block.reuseKey] {
                newCache[block.reuseKey] = piece
                return piece
            }
            buildCount += 1
            let piece = builder.build(block.markup.markup)
            newCache[block.reuseKey] = piece
            return piece
        }

        let oldKeys = needsFullRebuild ? [] : blocks.map(\.reuseKey)
        let newKeys = document.blocks.map(\.reuseKey)
        var prefix = 0
        while prefix < oldKeys.count, prefix < newKeys.count, oldKeys[prefix] == newKeys[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldKeys.count - prefix, suffix < newKeys.count - prefix,
              oldKeys[oldKeys.count - 1 - suffix] == newKeys[newKeys.count - 1 - suffix] { suffix += 1 }

        let oldTotal = offsets.last ?? 0
        let start = needsFullRebuild ? 0 : offsets[prefix]
        let end = needsFullRebuild ? oldTotal : offsets[oldKeys.count - suffix]
        let replacement = NSMutableAttributedString()
        for piece in newPieces[prefix..<(newPieces.count - suffix)] {
            replacement.append(piece)
        }

        blocks = document.blocks
        pieces = newPieces
        cache = newCache
        needsFullRebuild = false
        var running = 0
        offsets = [0] + pieces.map { running += $0.length; return running }
        return Edit(range: NSRange(location: start, length: end - start), replacement: replacement)
    }

    /// Index of the block that holds the character at `offset`.
    func blockIndex(atOffset offset: Int) -> Int? {
        guard !blocks.isEmpty else { return nil }
        var low = 0
        var high = blocks.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if offsets[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Character range of the block at `index` in the text storage.
    func range(ofBlock index: Int) -> NSRange {
        NSRange(location: offsets[index], length: offsets[index + 1] - offsets[index])
    }

    private func invalidate() {
        needsFullRebuild = true
    }
}
