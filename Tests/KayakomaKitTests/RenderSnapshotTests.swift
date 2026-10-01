import AppKit
import Foundation
import PDFKit
import Testing
@testable import KayakomaKit

/// Renders a sample document to PNG files, in light and dark appearance, so
/// that a person can look at the result. Runs only when `KAYAKOMA_RENDER_DIR`
/// names the output directory.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["KAYAKOMA_RENDER_DIR"] != nil))
func renderSampleDocument() throws {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KAYAKOMA_RENDER_DIR"]!)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let assets = FileManager.default.temporaryDirectory.appendingPathComponent("kayakoma-sample-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: assets) }
    try samplePicture().write(to: assets.appendingPathComponent("picture.png"))

    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.appearance = NSAppearance(named: appearance)
        view.baseURL = assets
        view.document = RenderedDocument(source: sampleMarkdown)
        let png = try #require(snapshot(view))
        try png.write(to: output.appendingPathComponent("sample-\(name).png"))
    }

    // The same sample as PDF, followed by the tables and long blocks that
    // have to break across pages; each page is also written as PNG.
    let exporter = MarkdownPDFExporter(baseURL: assets)
    let pdf = exporter.pdfData(for: RenderedDocument(source: [sampleMarkdown, tableSamples, pagedSample].joined(separator: "\n\n")))
    try pdf.write(to: output.appendingPathComponent("sample.pdf"))
    let document = try #require(PDFDocument(data: pdf))
    for index in 0..<document.pageCount {
        let page = try #require(document.page(at: index))
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: NSSize(width: bounds.width * 1.5, height: bounds.height * 1.5), for: .mediaBox)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent(String(format: "sample-pdf-%02d.png", index + 1)))
    }
}

/// Renders table samples in light and dark appearance, and the wide table in
/// a narrow window. Runs only when `KAYAKOMA_RENDER_DIR` names the output directory.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["KAYAKOMA_RENDER_DIR"] != nil))
func renderTableSamples() throws {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KAYAKOMA_RENDER_DIR"]!)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.appearance = NSAppearance(named: appearance)
        var theme = Theme.default
        if name == "dark" {
            // Shows the optional alternate row background in one of the two renders.
            theme.tableAlternateRowBackgroundColor = .custom(light: "#0000000A", dark: "#FFFFFF0D")
        }
        view.theme = theme
        view.document = RenderedDocument(source: tableSamples)
        let png = try #require(snapshot(view))
        try png.write(to: output.appendingPathComponent("tables-\(name).png"))
    }

    let narrow = MarkdownView(frame: NSRect(x: 0, y: 0, width: 420, height: 600))
    narrow.appearance = NSAppearance(named: .aqua)
    narrow.document = RenderedDocument(source: wideTableSample)
    let png = try #require(snapshot(narrow))
    try png.write(to: output.appendingPathComponent("tables-narrow.png"))
}

/// Renders a code block in every highlighted language, in light and dark
/// appearance and as PDF. Runs only when `KAYAKOMA_RENDER_DIR` names the
/// output directory.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["KAYAKOMA_RENDER_DIR"] != nil))
func renderCodeSamples() throws {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KAYAKOMA_RENDER_DIR"]!)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let view = MarkdownView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.appearance = NSAppearance(named: appearance)
        view.document = RenderedDocument(source: codeSamples)
        let png = try #require(snapshot(view))
        try png.write(to: output.appendingPathComponent("code-\(name).png"))
    }

    let pdf = MarkdownPDFExporter().pdfData(for: RenderedDocument(source: codeSamples))
    try pdf.write(to: output.appendingPathComponent("code.pdf"))
    let document = try #require(PDFDocument(data: pdf))
    for index in 0..<document.pageCount {
        let page = try #require(document.page(at: index))
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: NSSize(width: bounds.width * 1.5, height: bounds.height * 1.5), for: .mediaBox)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent(String(format: "code-pdf-%02d.png", index + 1)))
    }
}

/// Lays the whole document out, grows the view to fit it and draws it.
@MainActor
private func snapshot(_ view: MarkdownView) -> Data? {
    view.layoutSubtreeIfNeeded()
    guard let layoutManager = view.textView.textLayoutManager else { return nil }
    layoutManager.ensureLayout(for: layoutManager.documentRange)
    let height = layoutManager.usageBoundsForTextContainer.height + 2 * view.textView.textContainerInset.height
    view.setFrameSize(NSSize(width: view.frame.width, height: ceil(height)))
    view.layoutSubtreeIfNeeded()
    view.textView.setFrameSize(NSSize(width: view.textView.frame.width, height: ceil(height)))
    layoutManager.textViewportLayoutController.layoutViewport()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
}

private func samplePicture() -> Data {
    let size = NSSize(width: 480, height: 200)
    let image = NSImage(size: size, flipped: false) { rect in
        NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 20)
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: 40, y: 50, width: 100, height: 100)).fill()
        return true
    }
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

/// Blocks long enough to cross page breaks in the PDF sample.
private let pagedSample = """
# Long blocks

[Back to the top](#sample-document) · [to the lists](#lists)

| # | Item | Quantity | Note |
|--:|------|---------:|------|
\((1...60).map { "| \($0) | Part \($0) | \($0 * 7 % 23) | \($0 % 5 == 0 ? "A longer note that wraps in its narrow column, to make the row taller." : "Short." ) |" }.joined(separator: "\n"))

```text
\((1...70).map { "line \($0): the quick brown fox jumps over the lazy dog" }.joined(separator: "\n"))
```

\((1...12).map { "Paragraph \($0). " + String(repeating: "Some filler text that wraps over several lines of the page. ", count: 6) }.joined(separator: "\n\n"))

The end of the long blocks.
"""

private let wideTableSample = """
## Wide table

| Planet | Description | Notes |
|--------|-------------|-------|
| Ixora | A cold world with long seasons, wide frozen plains and a thin atmosphere that glows green at dusk. | Visited twice; see the survey log for details. |
| Brell | Small and rocky. | `orbit: 0.4 AU`, tidally locked, with an unusually_long_identifier_that_cannot_wrap_anywhere |
| Quen | Ocean planet covered by a single sea, with floating kelp forests several kilometres long. | None. |
"""

private let tableSamples = """
# Tables

A simple table:

| Fruit | Colour | Count |
|-------|--------|-------|
| Apple | Red | 3 |
| Lime | Green | 12 |
| Plum | Purple | 7 |

Aligned columns, an empty cell and a short row:

| Left | Centre | Right |
|:-----|:------:|------:|
| a | b | 1 |
| longer text | centred | 22.50 |
| | empty first | 333 |
| short row |

Inline styling in cells:

| Style | Example |
|-------|---------|
| Emphasis | *slanted* and **bold** and ***both*** |
| Code | `let x = 1` in a cell |
| Link | [an example link](https://example.com) |
| Strike | ~~no longer true~~ |
| Pipe | a \\| b, escaped |

\(wideTableSample)

## In a quote

> A table inside a quote:
>
> | Key | Value |
> |-----|------:|
> | width | 640 |
> | height | 480 |
>
> Text after the table.

## In a list

- An item with a table:

  | One | Two |
  |-----|-----|
  | 1 | 2 |

- The next item.

The end.
"""

private let sampleMarkdown = """
# Sample document

A paragraph with *emphasis*, **strong text**, ***both***, ~~struck words~~, `inline code`
and a [link to an example site](https://example.com). A soft break follows
on this line, and a hard break ends this one\\
so this sentence starts on a new line. Inline HTML stays literal: <span>like this</span>.

## Lists

- First item
- Second item with a longer text that wraps onto a second line to check that the hanging indent keeps the text aligned.
  - Nested item
    - Deeper item
- Third item

1. One
2. Two
   1. Two point one
   2. Two point two
3. Three

Counting on from eight:

8. Eight
9. Nine
10. Ten

- [ ] An open task
- [x] A finished task

A loose list:

- First paragraph of a loose item.

  Second paragraph of the same item.

- Another loose item.

### Quotes

> A quote that is long enough to wrap onto a second line, so that the bar on the left has to span both lines of text.
>
> A second paragraph in the same quote.
>
> > A nested quote.
>
> - A list inside a quote
> - and its second item

#### Code

```swift
struct Greeting {
    let name: String

    func text() -> String {
        "Hello, \\(name)!"
    }
}
```

    indented code block
    on two lines

- A list item with code:

  ```
  make build
  ```

---

##### Images

![A local picture](picture.png)

Missing: ![a missing picture](missing.png) and remote: ![a remote picture](https://example.com/picture.png).

###### Table

| Column | Value |
|--------|------:|
| alpha  |     1 |
| beta   |    22 |

The end.
"""

/// One short, invented snippet per highlighted language.
private let codeSamples = #"""
# Code samples

A block in each highlighted language; the last one has no language.

```php
<?php
// Greets a visitor by name.
function greet(string $name, int $times = 2): string {
    $line = "Hello, {$name}!";
    return str_repeat($line . "\n", $times);
}
echo greet('Ixora');
```

```javascript
// Counts the words of a sentence.
export function countWords(text) {
  const words = text.trim().split(/\s+/);
  return words.length > 0 ? words.length : null;
}
console.log(`total: ${countWords("one two three")}`);
```

```ts
interface Planet { name: string; moons: number }
const planets: Planet[] = [{ name: "Brell", moons: 0 }];
export const ringed = (p: Planet): boolean => p.moons > 2;
```

```tsx
export function Badge({ label }: { label: string }) {
  return <span className="badge">{label.toUpperCase()}</span>;
}
```

```css
/* A card with a soft shadow. */
.card > h2 {
  color: #2c8a84;
  margin: 12px auto;
  font-family: "Inter", sans-serif;
}
@media (min-width: 600px) { .card { display: none !important; } }
```

```html
<!-- A short list -->
<ul class="planets" data-count="2">
  <li><a href="#ixora">Ixora</a></li>
</ul>
```

```json
{ "name": "Ixora", "moons": 2, "ringed": true, "notes": null }
```

```rust
/// Returns the longer of two strings.
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() >= y.len() { x } else { y }
}

#[derive(Debug)]
struct Orbit { radius: f64 }
const MAX: u32 = 42;
```

```python
@dataclass
class Moon:
    name: str
    radius_km: float = 1.5

    def area(self) -> float:
        """Surface of the moon."""
        return 4 * math.pi * self.radius_km ** 2
```

```go
package main

import "fmt"

func main() {
	for i := 0; i < 3; i++ {
		fmt.Printf("orbit %d\n", i)
	}
}
```

```sh
# Builds the site and counts the pages.
for file in pages/*.md; do
  echo "building $file" && make "${file%.md}.html"
done
```

```c
#include <stdio.h>

int main(void) {
    const char *name = "Quen";
    printf("%s has %d seas\n", name, 1);
    return 0;
}
```

```cpp
template <typename T>
class Stack {
public:
    void push(const T& value) { items.push_back(value); }
private:
    std::vector<T> items;
};
```

```swift
struct Planet: Identifiable {
    let id = UUID()
    var name: String
    @MainActor func describe() -> String { "\(name) has \(moons.count) moons" }
}
```

```sql
SELECT name, COUNT(*) AS moons
FROM planets
WHERE radius > 1.5 AND name <> 'Brell'
GROUP BY name; -- one row per planet
```

```yaml
# Survey settings
name: Ixora
moons: 2
visited: true
targets:
  - Brell
  - "Quen"
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<survey planet="Ixora">
  <moon radius="1.5">Kell</moon>
</survey>
```

```
A block without a language stays plain.
```
"""#
