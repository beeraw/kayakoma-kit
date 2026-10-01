// swift-tools-version: 6.0
import PackageDescription

/// Tree-sitter grammars used to highlight code blocks, pinned to exact releases:
/// a grammar's highlight query (embedded in `HighlightQueries`) must match the
/// node names of its parser.
///
/// The CSS, JavaScript, Python and YAML grammars stay on their last release
/// whose manifest lists `src/scanner.c`: later ones only add it when a
/// relative `FileManager.fileExists` finds it, which fails while SwiftPM
/// evaluates the manifest, and the external scanner is then left out.
let grammars: [(url: String, version: Version, products: [String])] = [
    ("https://github.com/tree-sitter/tree-sitter-bash", "0.25.1", ["TreeSitterBash"]),
    ("https://github.com/tree-sitter/tree-sitter-c", "0.24.2", ["TreeSitterC"]),
    ("https://github.com/tree-sitter/tree-sitter-cpp", "0.23.4", ["TreeSitterCPP"]),
    ("https://github.com/tree-sitter/tree-sitter-css", "0.23.2", ["TreeSitterCSS"]),
    ("https://github.com/tree-sitter/tree-sitter-go", "0.25.0", ["TreeSitterGo"]),
    ("https://github.com/tree-sitter/tree-sitter-html", "0.23.2", ["TreeSitterHTML"]),
    ("https://github.com/tree-sitter/tree-sitter-javascript", "0.23.1", ["TreeSitterJavaScript"]),
    ("https://github.com/tree-sitter/tree-sitter-json", "0.24.8", ["TreeSitterJSON"]),
    ("https://github.com/tree-sitter/tree-sitter-php", "0.25.0", ["TreeSitterPHP"]),
    ("https://github.com/tree-sitter/tree-sitter-python", "0.23.6", ["TreeSitterPython"]),
    ("https://github.com/tree-sitter/tree-sitter-rust", "0.24.2", ["TreeSitterRust"]),
    ("https://github.com/tree-sitter/tree-sitter-typescript", "0.23.2", ["TreeSitterTypeScript"]),
    ("https://github.com/alex-pinkus/tree-sitter-swift", "0.7.3-with-generated-files", ["TreeSitterSwift"]),
    ("https://github.com/tree-sitter-grammars/tree-sitter-xml", "0.7.0", ["TreeSitterXML"]),
    ("https://github.com/tree-sitter-grammars/tree-sitter-yaml", "0.7.0", ["TreeSitterYAML"]),
]

/// The package name SwiftPM derives from a URL: its last path component.
func packageName(_ url: String) -> String {
    String(url.split(separator: "/").last!)
}

let package = Package(
    name: "KayakomaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KayakomaKit", targets: ["KayakomaKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter", exact: "0.25.10"),
    ] + grammars.map { .package(url: $0.url, exact: $0.version) },
    targets: [
        .target(
            name: "KayakomaKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "TreeSitter", package: "tree-sitter"),
                "TreeSitterSQL",
            ] + grammars.flatMap { grammar in
                grammar.products.map { Target.Dependency.product(name: $0, package: packageName(grammar.url)) }
            }
        ),
        // The SQL grammar does not commit its generated parser to its release
        // tags, so its generated sources are vendored; see its README.
        .target(
            name: "TreeSitterSQL",
            path: "Sources/TreeSitterSQL",
            exclude: ["LICENSE", "README.md"],
            sources: ["src/parser.c", "src/scanner_wrapper.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .testTarget(
            name: "KayakomaKitTests",
            dependencies: ["KayakomaKit"]
        ),
    ]
)
