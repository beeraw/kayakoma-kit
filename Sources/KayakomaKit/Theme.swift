import AppKit

/// Visual settings of a rendered document.
///
/// The list of settings is closed on purpose: there are no selectors and no
/// cascade, each value applies to one kind of element.
///
/// In JSON, every key is optional and takes its value from `Theme.default` when
/// missing, so a theme file only states what it changes. Nested objects
/// (`headings` and its levels, `codeSyntax`, `contentMargins`, `tableCellPadding`) are partial
/// in the same way. Unknown keys, unknown color names, malformed hexadecimal
/// colors and negative numbers are decoding errors that name the key's path.
/// `null` clears an optional setting. Encoding always writes every key.
///
/// ```json
/// {
///   "fontFamily": "Georgia",
///   "fontSize": 16,
///   "headings": { "1": { "size": 32 }, "2": { "weight": "semibold" } },
///   "contentMargins": { "horizontal": 48 },
///   "linkColor": { "light": "#0055CC", "dark": "#66AAFF" },
///   "maxLineWidth": null
/// }
/// ```
public struct Theme: Codable, Sendable, Equatable {
    /// Font family of body text; `nil` uses the system font.
    public var fontFamily: String?
    /// Size of body text, in points.
    public var fontSize: CGFloat
    /// Font family of code; `nil` uses the system monospaced font.
    public var codeFontFamily: String?
    /// Size of code text, in points.
    public var codeFontSize: CGFloat
    /// Styles of headings, from level 1 to level 6.
    ///
    /// In JSON, an object keyed by level, `"1"` to `"6"`, whose levels and their
    /// keys are all optional. All six levels are always encoded.
    public var headings: HeadingStyles
    /// Line height as a multiple of the font's natural line height.
    public var lineHeightMultiple: CGFloat

    public var textColor: Color
    public var secondaryTextColor: Color
    public var linkColor: Color
    public var codeBackgroundColor: Color
    /// Colors of the tokens of highlighted code blocks.
    public var codeSyntax: CodeSyntaxColors
    /// Whether a code block shows its language, as written after the opening
    /// fence, in its top right corner.
    public var codeLanguageLabel: Bool
    public var quoteBarColor: Color
    public var ruleColor: Color
    public var backgroundColor: Color
    /// Which lines are drawn around and between table cells.
    public var tableBorders: TableBorders
    /// Color of those lines.
    public var tableBorderColor: Color
    /// Background of a table's header row.
    public var tableHeaderBackgroundColor: Color
    /// Background of every other body row; `nil` leaves all rows plain.
    public var tableAlternateRowBackgroundColor: Color?

    /// Space after a paragraph.
    public var paragraphSpacing: CGFloat
    /// Space after any other block (heading, list, quote, code, rule, image).
    public var blockSpacing: CGFloat
    /// Space between the items of a tight list.
    public var listItemSpacing: CGFloat
    /// Indentation added by each level of list.
    public var listIndent: CGFloat
    /// Indentation added by each level of block quote.
    public var quoteIndent: CGFloat
    /// Width of the bar drawn on the left of a block quote.
    public var quoteBarWidth: CGFloat
    /// Inner padding of code blocks.
    public var codePadding: CGFloat
    /// Corner radius of code block backgrounds.
    public var codeCornerRadius: CGFloat
    /// Space between a table cell's border and its text.
    public var tableCellPadding: Margins
    /// Space around the text, horizontally and vertically.
    public var contentMargins: Margins
    /// Maximum width of the text column; `nil` lets text span the whole view.
    public var maxLineWidth: CGFloat?

    public init(
        fontFamily: String? = nil,
        fontSize: CGFloat = 14,
        codeFontFamily: String? = nil,
        codeFontSize: CGFloat = 12.5,
        headings: HeadingStyles = .default,
        lineHeightMultiple: CGFloat = 1.2,
        textColor: Color = .system(.label),
        secondaryTextColor: Color = .system(.secondaryLabel),
        linkColor: Color = .system(.link),
        codeBackgroundColor: Color = .system(.quaternaryFill),
        codeSyntax: CodeSyntaxColors = .default,
        codeLanguageLabel: Bool = true,
        quoteBarColor: Color = .system(.tertiaryLabel),
        ruleColor: Color = .system(.separator),
        backgroundColor: Color = .system(.textBackground),
        tableBorders: TableBorders = .horizontal,
        tableBorderColor: Color = .system(.separator),
        tableHeaderBackgroundColor: Color = .system(.quaternaryFill),
        tableAlternateRowBackgroundColor: Color? = nil,
        paragraphSpacing: CGFloat = 10,
        blockSpacing: CGFloat = 14,
        listItemSpacing: CGFloat = 3,
        listIndent: CGFloat = 26,
        quoteIndent: CGFloat = 18,
        quoteBarWidth: CGFloat = 3,
        codePadding: CGFloat = 10,
        codeCornerRadius: CGFloat = 6,
        tableCellPadding: Margins = Margins(horizontal: 10, vertical: 5),
        contentMargins: Margins = Margins(horizontal: 32, vertical: 28),
        maxLineWidth: CGFloat? = 760
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.codeFontFamily = codeFontFamily
        self.codeFontSize = codeFontSize
        self.headings = headings
        self.lineHeightMultiple = lineHeightMultiple
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.codeBackgroundColor = codeBackgroundColor
        self.codeSyntax = codeSyntax
        self.codeLanguageLabel = codeLanguageLabel
        self.quoteBarColor = quoteBarColor
        self.ruleColor = ruleColor
        self.backgroundColor = backgroundColor
        self.tableBorders = tableBorders
        self.tableBorderColor = tableBorderColor
        self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
        self.tableAlternateRowBackgroundColor = tableAlternateRowBackgroundColor
        self.paragraphSpacing = paragraphSpacing
        self.blockSpacing = blockSpacing
        self.listItemSpacing = listItemSpacing
        self.listIndent = listIndent
        self.quoteIndent = quoteIndent
        self.quoteBarWidth = quoteBarWidth
        self.codePadding = codePadding
        self.codeCornerRadius = codeCornerRadius
        self.tableCellPadding = tableCellPadding
        self.contentMargins = contentMargins
        self.maxLineWidth = maxLineWidth
    }

    /// System fonts and dynamic system colors: follows the light or dark appearance.
    public static let `default` = Theme()
}

extension Theme {
    /// The lines a table draws.
    public enum TableBorders: String, Codable, Sendable, CaseIterable {
        /// A rule under the header and under every body row, including the last;
        /// no vertical lines and no outer box.
        case horizontal
        /// A full grid: every cell is boxed.
        case all

        public init(from decoder: any Decoder) throws {
            let name = try decoder.singleValueContainer().decode(String.self)
            guard let value = Self(rawValue: name) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown table borders \"\(name)\" at \(AnyCodingKey.path(decoder.codingPath)): expected \"horizontal\" or \"all\""
                ))
            }
            self = value
        }
    }

    /// The styles of the six heading levels.
    public struct HeadingStyles: Sendable, Equatable {
        public var level1: HeadingStyle
        public var level2: HeadingStyle
        public var level3: HeadingStyle
        public var level4: HeadingStyle
        public var level5: HeadingStyle
        public var level6: HeadingStyle

        public init(
            level1: HeadingStyle, level2: HeadingStyle, level3: HeadingStyle,
            level4: HeadingStyle, level5: HeadingStyle, level6: HeadingStyle
        ) {
            self.level1 = level1
            self.level2 = level2
            self.level3 = level3
            self.level4 = level4
            self.level5 = level5
            self.level6 = level6
        }

        public static let `default` = HeadingStyles(
            level1: HeadingStyle(size: 28, weight: .bold, spacingBefore: 20),
            level2: HeadingStyle(size: 22, weight: .bold, spacingBefore: 18),
            level3: HeadingStyle(size: 18, weight: .semibold, spacingBefore: 14),
            level4: HeadingStyle(size: 16, weight: .semibold, spacingBefore: 12),
            level5: HeadingStyle(size: 14, weight: .semibold, spacingBefore: 10),
            level6: HeadingStyle(size: 13, weight: .semibold, spacingBefore: 10)
        )

        /// The valid heading levels.
        public static let levels = 1...6

        /// The style of a heading level, from 1 to 6. A level outside that range
        /// is clamped to the nearest valid one: 0 and below read and write level 1,
        /// 7 and above level 6.
        public subscript(level level: Int) -> HeadingStyle {
            get {
                switch Self.levels.clamp(level) {
                case 1: level1
                case 2: level2
                case 3: level3
                case 4: level4
                case 5: level5
                default: level6
                }
            }
            set {
                switch Self.levels.clamp(level) {
                case 1: level1 = newValue
                case 2: level2 = newValue
                case 3: level3 = newValue
                case 4: level4 = newValue
                case 5: level5 = newValue
                default: level6 = newValue
                }
            }
        }
    }

    /// Colors of the tokens of a highlighted code block, one per kind of token.
    /// Text that is none of these, and code in a language that is not
    /// highlighted, keeps `textColor`.
    ///
    /// Code blocks are highlighted when the first word of their info string
    /// names a known language: `bash` (`sh`, `zsh`, `shell`), `c`, `cpp` (`c++`,
    /// `cc`, `cxx`, `h`, `hpp`), `css`, `go` (`golang`), `html` (`htm`),
    /// `javascript` (`js`, `mjs`, `cjs`, `jsx`), `json` (`jsonc`), `php`,
    /// `python` (`py`), `rust` (`rs`), `sql`, `swift`, `typescript` (`ts`),
    /// `tsx`, `xml`, `yaml` (`yml`).
    public struct CodeSyntaxColors: Sendable, Equatable {
        /// Keywords and keyword-like operators (`fn`, `return`, `and`, `@media`).
        public var keyword: Color
        /// String and character literals.
        public var string: Color
        public var comment: Color
        /// Numeric literals.
        public var number: Color
        /// Types, type-like names and modules.
        public var type: Color
        /// Names of functions, methods and macros.
        public var function: Color
        /// Variables, parameters, fields and properties, including object keys.
        public var variable: Color
        /// Constants, booleans, `null`, escapes in strings and built-in names such as `self`.
        public var constant: Color
        /// Operators (`+`, `=`, `->`).
        public var `operator`: Color
        /// Brackets, commas, semicolons and other delimiters.
        public var punctuation: Color
        /// Tag names in HTML and XML.
        public var tag: Color
        /// Attributes in markup, annotations and attributes in code, lifetimes and labels.
        public var attribute: Color

        public init(
            keyword: Color, string: Color, comment: Color, number: Color,
            type: Color, function: Color, variable: Color, constant: Color,
            operator: Color, punctuation: Color, tag: Color, attribute: Color
        ) {
            self.keyword = keyword
            self.string = string
            self.comment = comment
            self.number = number
            self.type = type
            self.function = function
            self.variable = variable
            self.constant = constant
            self.operator = `operator`
            self.punctuation = punctuation
            self.tag = tag
            self.attribute = attribute
        }

        /// A calm palette in the spirit of GitHub's, readable on the default
        /// code background in both appearances.
        public static let `default` = CodeSyntaxColors(
            keyword: .custom(light: "#CF222E", dark: "#FF7B72"),
            string: .custom(light: "#0A3069", dark: "#A5D6FF"),
            comment: .custom(light: "#656D76", dark: "#8B949E"),
            number: .custom(light: "#0550AE", dark: "#79C0FF"),
            type: .custom(light: "#953800", dark: "#F0B35E"),
            function: .custom(light: "#6639BA", dark: "#D2A8FF"),
            variable: .custom(light: "#3B5470", dark: "#B4C7DC"),
            constant: .custom(light: "#0550AE", dark: "#79C0FF"),
            operator: .custom(light: "#0F6E80", dark: "#7CCBD6"),
            punctuation: .custom(light: "#57606A", dark: "#9DA5AE"),
            tag: .custom(light: "#116329", dark: "#7EE787"),
            attribute: .custom(light: "#0550AE", dark: "#79C0FF")
        )

        subscript(role: TokenRole) -> Color {
            switch role {
            case .keyword: keyword
            case .string: string
            case .comment: comment
            case .number: number
            case .type: type
            case .function: function
            case .variable: variable
            case .constant: constant
            case .operator: `operator`
            case .punctuation: punctuation
            case .tag: tag
            case .attribute: attribute
            }
        }
    }

    public struct HeadingStyle: Codable, Sendable, Equatable {
        public var size: CGFloat
        public var weight: Weight
        /// Extra space above the heading, added to the space after the previous block.
        public var spacingBefore: CGFloat

        public init(size: CGFloat, weight: Weight, spacingBefore: CGFloat) {
            self.size = size
            self.weight = weight
            self.spacingBefore = spacingBefore
        }
    }

    public enum Weight: String, Codable, Sendable, CaseIterable {
        case regular, medium, semibold, bold, heavy

        var fontWeight: NSFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            }
        }
    }

    public struct Margins: Codable, Sendable, Equatable {
        public var horizontal: CGFloat
        public var vertical: CGFloat

        public init(horizontal: CGFloat, vertical: CGFloat) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
    }

    /// A color that is either a dynamic system color or a pair of fixed colors
    /// for the light and dark appearances.
    ///
    /// Encoded as a system color name (`"label"`) or as `{"light": "#RRGGBB", "dark": "#RRGGBB"}`;
    /// hexadecimal values may carry an alpha component (`#RRGGBBAA`). When `dark` is
    /// missing, the `light` color is used for both appearances.
    public enum Color: Codable, Sendable, Equatable {
        case system(SystemColor)
        case custom(light: String, dark: String)

        public enum SystemColor: String, Codable, Sendable, CaseIterable {
            case label, secondaryLabel, tertiaryLabel, quaternaryLabel
            case link, separator, textBackground, windowBackground
            case quaternaryFill, controlAccent

            var nsColor: NSColor {
                switch self {
                case .label: .labelColor
                case .secondaryLabel: .secondaryLabelColor
                case .tertiaryLabel: .tertiaryLabelColor
                case .quaternaryLabel: .quaternaryLabelColor
                case .link: .linkColor
                case .separator: .separatorColor
                case .textBackground: .textBackgroundColor
                case .windowBackground: .windowBackgroundColor
                case .quaternaryFill: .quaternarySystemFill
                case .controlAccent: .controlAccentColor
                }
            }
        }

        public init(from decoder: any Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                guard let system = SystemColor(rawValue: name) else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown system color \"\(name)\" at \(AnyCodingKey.path(decoder.codingPath))"
                    ))
                }
                self = .system(system)
                return
            }
            let container = try decoder.strictContainer(allowing: ["light", "dark"])
            let light = try Self.hex("light", in: container)
            let dark = container.contains(AnyCodingKey("dark")) ? try Self.hex("dark", in: container) : light
            self = .custom(light: light, dark: dark)
        }

        private static func hex(_ key: String, in container: KeyedDecodingContainer<AnyCodingKey>) throws -> String {
            let codingKey = AnyCodingKey(key)
            let hex = try container.decode(String.self, forKey: codingKey)
            guard components(hex) != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: codingKey, in: container,
                    debugDescription: "Invalid hexadecimal color \"\(hex)\" at \(AnyCodingKey.path(container.codingPath + [codingKey]))"
                )
            }
            return hex
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .system(let system): try container.encode(system.rawValue)
            case .custom(let light, let dark): try container.encode(["light": light, "dark": dark])
            }
        }

        /// The AppKit color; dynamic, so it resolves against the appearance it is drawn in.
        public var nsColor: NSColor {
            switch self {
            case .system(let system):
                return system.nsColor
            case .custom(let light, let dark):
                let lightColor = Self.color(light)
                let darkColor = Self.color(dark)
                return NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
                }
            }
        }

        private static func color(_ hex: String) -> NSColor {
            guard let c = components(hex) else { return .labelColor }
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        }

        private static func components(_ hex: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
            var digits = Substring(hex)
            if digits.hasPrefix("#") { digits = digits.dropFirst() }
            guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
            let rgba = digits.count == 6 ? value << 8 | 0xFF : value
            return (
                CGFloat(rgba >> 24 & 0xFF) / 255,
                CGFloat(rgba >> 16 & 0xFF) / 255,
                CGFloat(rgba >> 8 & 0xFF) / 255,
                CGFloat(rgba & 0xFF) / 255
            )
        }
    }
}

private extension ClosedRange<Int> {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
