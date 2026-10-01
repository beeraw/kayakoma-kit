<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/kayakoma-logo-dark.svg">
    <img alt="Kayakoma" src="docs/kayakoma-logo-light.svg" width="360">
  </picture>
</p>

# KayakomaKit

KayakomaKit is a Swift package that renders Markdown natively on macOS: no WebView, no HTML, no JavaScript. Text is parsed with [swift-markdown](https://github.com/swiftlang/swift-markdown) and laid out with TextKit 2, so you get a real `NSView` with selectable text, native scrolling and PDF output drawn by the same code.

The name: "Kaya koma" means "it is not finished" in Shimaore, the language of Mayotte. A nod to Markdown, an unfinished document that is waiting to be rendered.

KayakomaKit only displays Markdown; it never edits it. Two apps are built on it: Kayakoma Viewer (with a Quick Look extension) and Kayakoma Editor.

## Features

- Paragraphs, headings, ordered and unordered lists (nested), task lists, block quotes, code blocks, inline code, emphasis, strong, strikethrough, links, images, thematic breaks and GitHub-style tables.
- Syntax highlighting of fenced code blocks with [Tree-sitter](https://tree-sitter.github.io) grammars, compiled into the package: Bash, C, C++, CSS, Go, HTML, JavaScript (with JSX), JSON, PHP, Python, Rust, SQL, Swift, TypeScript, TSX, XML and YAML. A discreet label shows the block's language.
- `MarkdownView` (AppKit) and `MarkdownPreview` (SwiftUI).
- Themes: a closed list of settings, stored as plain Swift values or as partial JSON, with one theme covering light and dark appearances.
- Incremental rendering: when the source changes, only the blocks whose text changed are rebuilt.
- Every block keeps its range in the source (`RenderedDocument.Block.sourceLines`), and the view can scroll to a source line and report the line at its top: this is what keeps an editor and its preview in sync.
- GitHub-style heading anchors; `#anchor` links scroll to their heading.
- Local images are decoded off the main thread; their space is reserved at once.
- PDF export with the same drawing code, without a view or a window (`MarkdownPDFExporter`): real text, clickable links, page breaks that never cut a line.

## Requirements

- macOS 14 or later
- Swift 6 (Xcode 16 or later)

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/beeraw/kayakoma-kit.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "KayakomaKit", package: "kayakoma-kit"),
    ]),
]
```

In an Xcode project, use File > Add Package Dependencies… and enter `https://github.com/beeraw/kayakoma-kit.git`.

## Quick start

AppKit:

```swift
import AppKit
import KayakomaKit

let markdownView = MarkdownView()
markdownView.baseURL = fileURL.deletingLastPathComponent() // relative images and links
markdownView.document = RenderedDocument(source: text)
```

Assigning a new `RenderedDocument` updates the view; unchanged blocks are reused. Put the view in a window or a container as any `NSView`; it contains its own scroll view.

SwiftUI:

```swift
import KayakomaKit
import SwiftUI

struct PreviewPane: View {
    var text: String
    var folder: URL

    var body: some View {
        MarkdownPreview(source: text, theme: .default, baseURL: folder)
    }
}
```

## Theming

A `Theme` is a plain value with a closed list of settings: no selectors, no cascade. `Theme.default` uses system fonts and dynamic system colors, so it follows light and dark mode. Assign it to `MarkdownView.theme` (the whole document is re-rendered) or pass it to `MarkdownPreview` and `MarkdownPDFExporter`.

In code:

```swift
var theme = Theme.default
theme.fontFamily = "Georgia"
theme.fontSize = 16
theme.headings[level: 1].size = 32
theme.linkColor = .custom(light: "#0055CC", dark: "#66AAFF")
theme.tableBorders = .all
markdownView.theme = theme
```

As JSON, `Theme` is `Codable`, and a theme file is partial: every key is optional and missing keys keep the value of `Theme.default`. Nested objects (`headings` and each of its levels, `codeSyntax`, `contentMargins`, `tableCellPadding`) are partial too. `null` clears an optional setting.

```json
{
  "fontFamily": "Georgia",
  "fontSize": 17,
  "headings": { "1": { "size": 34 }, "2": { "weight": "semibold" } },
  "linkColor": { "light": "#0055CC", "dark": "#66AAFF" },
  "codeSyntax": { "keyword": { "light": "#AF00DB", "dark": "#C586C0" } },
  "codeLanguageLabel": false,
  "backgroundColor": { "light": "#FBF8F2", "dark": "#24211D" },
  "tableBorders": "all",
  "tableAlternateRowBackgroundColor": { "light": "#00000008", "dark": "#FFFFFF08" },
  "contentMargins": { "horizontal": 48 },
  "maxLineWidth": null
}
```

```swift
let theme = try JSONDecoder().decode(Theme.self, from: jsonData)
```

Decoding is strict so that typos are caught: an unknown key, an unknown color name, a malformed hexadecimal color or a negative number is an error whose message names the key's path (for example `Unknown key "fontsize" at the top level`). Encoding always writes every key.

### Values

- Colors: a system color name, or `{"light": "#RRGGBB", "dark": "#RRGGBB"}`. Hexadecimal values may carry an alpha component (`#RRGGBBAA`). When `dark` is missing, the light color is used for both appearances. System names: `label`, `secondaryLabel`, `tertiaryLabel`, `quaternaryLabel`, `link`, `separator`, `textBackground`, `windowBackground`, `quaternaryFill`, `controlAccent`.
- Heading levels: keys `"1"` to `"6"`, each with `size`, `weight` and `spacingBefore`. Weights: `regular`, `medium`, `semibold`, `bold`, `heavy`.
- Margins (`contentMargins`, `tableCellPadding`): `{"horizontal": 32, "vertical": 28}`.
- `tableBorders`: `"horizontal"` (a rule under the header and under every row) or `"all"` (a full grid).
- `codeSyntax`: one color per kind of token, see [Code highlighting](#code-highlighting).

### Settings

| Key | Default | Meaning |
|---|---|---|
| `fontFamily` | system font | Body font family |
| `fontSize` | 14 | Body size, in points |
| `codeFontFamily` | system monospaced | Code font family |
| `codeFontSize` | 12.5 | Code size, in points |
| `headings` | 28 / 22 / 18 / 16 / 14 / 13 pt | Size, weight and space before, per level 1 to 6 |
| `lineHeightMultiple` | 1.2 | Line height, as a multiple of the font's natural height |
| `textColor` | `label` | Body text |
| `secondaryTextColor` | `secondaryLabel` | Block quotes and secondary text |
| `linkColor` | `link` | Links |
| `codeBackgroundColor` | `quaternaryFill` | Code block and inline code background |
| `codeSyntax` | see below | Colors of highlighted code, one per kind of token |
| `codeLanguageLabel` | `true` | Shows a code block's language in its top right corner |
| `quoteBarColor` | `tertiaryLabel` | Bar of block quotes |
| `ruleColor` | `separator` | Thematic breaks |
| `backgroundColor` | `textBackground` | Document background |
| `tableBorders` | `horizontal` | Lines drawn in tables |
| `tableBorderColor` | `separator` | Color of those lines |
| `tableHeaderBackgroundColor` | `quaternaryFill` | Background of the header row |
| `tableAlternateRowBackgroundColor` | none | Background of every other body row |
| `paragraphSpacing` | 10 | Space after a paragraph |
| `blockSpacing` | 14 | Space after any other block |
| `listItemSpacing` | 3 | Space between the items of a tight list |
| `listIndent` | 26 | Indentation per list level |
| `quoteIndent` | 18 | Indentation per quote level |
| `quoteBarWidth` | 3 | Width of the quote bar |
| `codePadding` | 10 | Inner padding of code blocks |
| `codeCornerRadius` | 6 | Corner radius of code blocks |
| `tableCellPadding` | 10 x 5 | Space between a cell's border and its text |
| `contentMargins` | 32 x 28 | Space around the text |
| `maxLineWidth` | 760 | Maximum width of the text column; `null` uses the whole view |

### Code highlighting

A fenced code block is highlighted when the first word of its info string names a known language, whatever its case: `bash` (also `sh`, `zsh`, `shell`), `c`, `cpp` (`c++`, `cc`, `cxx`, `h`, `hpp`), `css`, `go` (`golang`), `html` (`htm`), `javascript` (`js`, `mjs`, `cjs`, `jsx`), `json` (`jsonc`), `php`, `python` (`py`), `rust` (`rs`), `sql`, `swift`, `typescript` (`ts`), `tsx`, `xml`, `yaml` (`yml`). Other blocks, and blocks without a language, stay plain in `textColor`. PHP is read with or without its `<?php` tag.

When `codeLanguageLabel` is on, the language is written small, in `secondaryTextColor`, in the block's top right corner, as it appears after the fence (lowercased), for known and unknown languages alike. The label is drawn, not part of the text: it is never selected, copied or found, on screen or in a PDF.

Each token takes the color of its kind in `codeSyntax`; text that is no token keeps `textColor`. The defaults are a calm palette in the spirit of GitHub's, readable on the default code background in both appearances.

| `codeSyntax` key | Default (light / dark) | Tokens |
|---|---|---|
| `keyword` | `#CF222E` / `#FF7B72` | Keywords and keyword-like operators (`fn`, `return`, `and`, `@media`) |
| `string` | `#0A3069` / `#A5D6FF` | String and character literals |
| `comment` | `#656D76` / `#8B949E` | Comments |
| `number` | `#0550AE` / `#79C0FF` | Numeric literals |
| `type` | `#953800` / `#F0B35E` | Types, type-like names and modules |
| `function` | `#6639BA` / `#D2A8FF` | Names of functions, methods and macros |
| `variable` | `#3B5470` / `#B4C7DC` | Variables, parameters, fields and properties, including object keys |
| `constant` | `#0550AE` / `#79C0FF` | Constants, booleans, `null`, escapes in strings, built-in names such as `self` |
| `operator` | `#0F6E80` / `#7CCBD6` | Operators (`+`, `=`, `->`) |
| `punctuation` | `#57606A` / `#9DA5AE` | Brackets, commas, semicolons and other delimiters |
| `tag` | `#116329` / `#7EE787` | Tag names in HTML and XML |
| `attribute` | `#0550AE` / `#79C0FF` | Attributes in markup, annotations and attributes in code, lifetimes and labels |

## PDF export

`MarkdownPDFExporter` draws a document to PDF with the code that draws `MarkdownView`, without a view or a window, from any thread: it works in an app, a Quick Look extension or a command-line tool.

```swift
let exporter = MarkdownPDFExporter(
    theme: theme,
    baseURL: fileURL.deletingLastPathComponent(),
    pageSize: MarkdownPDFExporter.letter // default is MarkdownPDFExporter.a4
)
let data = exporter.pdfData(for: RenderedDocument(source: text))
try data.write(to: pdfURL)
```

Text stays real text (selectable, searchable), links stay clickable and `#anchor` links jump to their heading. A heading stays with what follows it, tables repeat their header row on the next page, and an image taller than a page is scaled down. Colors are always those of the light appearance, and the page `margins` replace the theme's `contentMargins` and `maxLineWidth`.

## Scroll sync and anchors

```swift
// Scroll the preview to the block holding line 120 of the source (1-based).
markdownView.scrollToSourceLine(120)

// Be told when the user scrolls the preview.
markdownView.onTopVisibleSourceLineChange = { line in
    // scroll the source pane to `line`
}

// Scroll to a heading, as following a link does.
let found = markdownView.scrollToAnchor("#getting-started")

// Without a view: where a heading is in the document.
if let index = document.blockIndex(forAnchor: "getting-started") {
    let block = document.blocks[index]
    print(block.sourceLines as Any, block.kind)
}
```

`topVisibleSourceLine` gives the source line at the top of the visible area, interpolated inside tall blocks. `scrollToSourceLine(_:)` does not call `onTopVisibleSourceLineChange`, so two panes cannot feed each other in a loop; `scrollToAnchor(_:)` does, like following a link. Anchors follow GitHub's rules: lowercase, punctuation dropped, spaces turned into hyphens, `-1`, `-2`... appended to duplicates. `blockIndex(forSourceLine:)` goes the other way, from a line to a block.

## Links

```swift
// Handle link clicks before the view does (it opens them otherwise).
markdownView.onLinkClick = { click in
    guard click.url.isFileURL, !click.modifiers.contains(.option) else { return false }
    // open click.url (fragment: click.url.fragment), named click.text
    return true
}

// Underline links to missing files with dashes.
markdownView.isLinkBroken = { url in url.isFileURL && !FileManager.default.fileExists(atPath: url.path) }
markdownView.revalidateLinks() // after a file was created or removed
```

`onLinkClick` receives the target resolved against `baseURL` (fragment-only `#anchor` links stay relative), the modifier keys, the clicked character and the link's text; returning `false` lets the view scroll to the anchor or open the link with the workspace. `isLinkBroken` is asked for each link when its block is rendered.

## Block geometry

```swift
// Where a block is drawn, in the view's coordinate space (follows scrolling).
if let frame = markdownView.frame(ofBlockAt: 3) {
    let marker = NSView(frame: NSRect(x: 0, y: frame.minY, width: 3, height: frame.height))
    markdownView.addSubview(marker)
}

// Which block is under a point (a click, a drop...), given in the same space.
if let index = markdownView.blockIndex(at: clickPoint) {
    print(document.blocks[index].sourceLines as Any)
}

// The block holding the start of the selection.
let current = markdownView.selectedBlockIndex
```

Indexes are those of `document.blocks`. `frame(ofBlockAt:)` includes the space after the block and returns `nil` for an index out of range or a block without text; the frame of a block far from the viewport is an estimate until its surroundings are laid out. `blockIndex(at:)` counts the whole row of a block, margins included, and returns `nil` outside the view or below the last block. `selectedBlockIndex` is `nil` when there is no document or the view is not yet up to date with it. Together they let a host draw a marker on the current block or map a click back to the source.

## Design notes

- Parsing: swift-markdown (cmark-gfm). Layout and drawing: TextKit 2, with custom layout fragments for block quotes, code blocks, rules and tables.
- Incremental rendering: a block is rebuilt only when its source text changes (or, for a block with links or images, when what its references resolve to changes).
- No network access, ever. Local images are read from files, decoded off the main thread and cached. Remote (`http`, `https`) images are not downloaded; they show as a placeholder with their description. This is on purpose: privacy, and a Quick Look extension's sandbox would refuse the connection anyway.
- Relative image paths and links are resolved against `baseURL`.
- Text can be selected and copied, never edited. Copying a code block keeps its line breaks.
- Highlighting: the Tree-sitter C runtime and its grammars are compiled into the package; there is no JavaScript, no web view and no network access. Each grammar's own highlight query is embedded (a few are slightly adapted, with a note in the query) and compiled the first time its language appears. A code block is highlighted when it is built, so the incremental renderer does not highlight unchanged blocks again.

## Limitations

- Syntax highlighting covers the languages listed under [Code highlighting](#code-highlighting); there is no highlighting of one language inside another (CSS or JavaScript in HTML, HTML around PHP).
- The grammars make the package large: they add about 27 MB per architecture to each binary that links the engine (the SQL grammar alone about 11 MB, Swift and C++ about 4 MB each), and resolving the package downloads their repositories once (about 500 MB of git history).
- Remote images are not loaded.
- Raw HTML is not interpreted: it is shown as text.
- macOS only (AppKit and TextKit 2); there is no iOS or visionOS version.
- The theme has a closed list of settings; there is no CSS and no way to style one block individually.

## Development

```bash
swift test
```

## License

MIT, see [LICENSE](LICENSE). Third-party licenses (swift-markdown, swift-cmark, Tree-sitter and its grammars) are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
