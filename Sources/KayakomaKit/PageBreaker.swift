import CoreGraphics

/// Splits a laid-out document into pages without cutting what must stay whole.
///
/// The document is a column of atoms, the smallest pieces a page break may
/// not cut: a line of text, a table row. A page holds consecutive atoms, so
/// it shows the column from the top of its first atom to the bottom of its
/// last one; the space between two pages is dropped.
struct PageBreaker {
    /// What an atom draws: a line of a layout fragment, or a row of a table.
    struct Part: Hashable {
        let fragment: Int
        let index: Int
    }

    struct Atom {
        var top: CGFloat
        var bottom: CGFloat
        var part: Part
        /// Moves to the next page with the atom that follows it (the last line
        /// of a heading, a table's header row).
        var keepWithNext = false
        /// For a table body row, the index of the header row's atom, repeated
        /// at the top of a page that the row starts.
        var header: Int?
        /// Height the repeated header takes on the page.
        var headerHeight: CGFloat = 0
        /// Set on the pieces of an atom taller than a page, which had to be cut.
        var isCut = false

        var height: CGFloat { bottom - top }
    }

    struct Page: Equatable {
        /// Indices of the page's atoms.
        let atoms: Range<Int>
        /// The table header row repeated above the first atom, if any.
        let header: Int?
    }

    /// Breaks `atoms`, in reading order, into pages of `height` points.
    ///
    /// An atom taller than a page is cut into page-high pieces: the only case
    /// where a page break goes through an atom.
    static func pages(for input: [Atom], height: CGFloat) -> (atoms: [Atom], pages: [Page]) {
        let atoms = cut(input, height: height)
        var pages: [Page] = []
        func extra(_ start: Int) -> CGFloat { atoms[start].header != nil ? atoms[start].headerHeight : 0 }
        var start = 0
        var index = 0
        while index < atoms.count {
            if index > start, atoms[index].bottom - atoms[start].top + extra(start) > height {
                var end = index
                while end - 1 > start, atoms[end - 1].keepWithNext { end -= 1 }
                pages.append(Page(atoms: start..<end, header: atoms[start].header))
                start = end
                index = end
                continue
            }
            index += 1
        }
        if start < atoms.count {
            pages.append(Page(atoms: start..<atoms.count, header: atoms[start].header))
        }
        return (atoms, pages)
    }

    private static func cut(_ atoms: [Atom], height: CGFloat) -> [Atom] {
        guard height > 1 else { return atoms }
        var result: [Atom] = []
        result.reserveCapacity(atoms.count)
        /// Where each input atom (its first piece) lands in the result.
        var moved: [Int] = []
        moved.reserveCapacity(atoms.count)
        for var atom in atoms {
            moved.append(result.count)
            // Headers come before their rows, so they have already moved.
            atom.header = atom.header.map { moved[$0] }
            let room = height - (atom.header != nil ? atom.headerHeight : 0)
            guard atom.height > room, room > 1 else {
                result.append(atom)
                continue
            }
            var top = atom.top
            while top < atom.bottom {
                var piece = atom
                piece.top = top
                piece.bottom = min(atom.bottom, top + (top == atom.top ? room : height))
                piece.isCut = true
                // Only the first piece can follow a repeated header.
                if top != atom.top { piece.header = nil }
                piece.keepWithNext = atom.keepWithNext && piece.bottom == atom.bottom
                result.append(piece)
                top = piece.bottom
            }
        }
        return result
    }
}
