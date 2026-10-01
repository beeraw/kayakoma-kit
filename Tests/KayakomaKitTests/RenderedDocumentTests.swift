import Testing
@testable import KayakomaKit

@Test func blocksKeepTheirKindAndSourceLines() {
    let document = RenderedDocument(source: """
    # Title

    First paragraph.

    - one
    - two

    > A quote.

    ```
    let x = 1
    ```

    ---

    | a | b |
    |---|---|
    | 1 | 2 |

    <div>raw</div>
    """)

    #expect(document.blocks.map(\.kind) == [
        .heading(level: 1), .paragraph, .list, .blockQuote, .codeBlock, .thematicBreak, .table, .html,
    ])
    #expect(document.blocks.map(\.sourceLines) == [1...1, 3...3, 5...6, 8...8, 10...12, 14...14, 16...18, 20...20])
    #expect(document.blocks[2].sourceText == "- one\n- two")
}

@Test func sourceLinesMapToBlocks() {
    let document = RenderedDocument(source: """
    # Title

    Paragraph one
    still paragraph one.

    Paragraph two.
    """)

    #expect(document.blockIndex(forSourceLine: 1) == 0)
    #expect(document.blockIndex(forSourceLine: 2) == 0)
    #expect(document.blockIndex(forSourceLine: 4) == 1)
    #expect(document.blockIndex(forSourceLine: 6) == 2)
    #expect(document.blockIndex(forSourceLine: 99) == 2)
    #expect(RenderedDocument(source: "").blockIndex(forSourceLine: 1) == nil)
}
