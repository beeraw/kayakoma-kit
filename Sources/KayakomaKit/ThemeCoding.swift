import Foundation

// Partial JSON coding of themes: a theme file only states what it changes.
// Missing keys keep the value of a base (the default theme, or the default
// style of a heading level), unknown keys are errors so that typos are caught.

/// A coding key made from any string, used to see every key of a JSON object.
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }

    /// A readable dotted path such as `headings.1.size`.
    static func path(_ codingPath: [any CodingKey]) -> String {
        codingPath.isEmpty ? "the top level"
            : codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}

extension Decoder {
    /// A keyed container that throws if the JSON object holds a key outside `keys`.
    func strictContainer(allowing keys: [String]) throws -> KeyedDecodingContainer<AnyCodingKey> {
        let container = try container(keyedBy: AnyCodingKey.self)
        let unknown = container.allKeys.map(\.stringValue).filter { !keys.contains($0) }.sorted()
        if let key = unknown.first {
            throw DecodingError.dataCorruptedError(
                forKey: AnyCodingKey(key), in: container,
                debugDescription: "Unknown key \"\(key)\" at \(AnyCodingKey.path(codingPath))"
            )
        }
        return container
    }
}

/// One key of a JSON object, bound to a property of `Root`.
struct CodingField<Root> {
    let key: String
    /// Updates the property if the key is present; leaves it unchanged otherwise.
    let decode: (KeyedDecodingContainer<AnyCodingKey>, inout Root) throws -> Void
    let encode: (Root, inout KeyedEncodingContainer<AnyCodingKey>) throws -> Void
}

extension CodingField {
    /// A property replaced as a whole by the JSON value. Numbers must not be negative.
    init<Value: Codable>(_ key: String, _ path: WritableKeyPath<Root, Value>) {
        self.init(key: key, decode: { container, root in
            let codingKey = AnyCodingKey(key)
            guard container.contains(codingKey) else { return }
            let value = try container.decode(Value.self, forKey: codingKey)
            if let number = value as? CGFloat, number < 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: codingKey, in: container,
                    debugDescription: "Invalid value \(number) at \(AnyCodingKey.path(container.codingPath + [codingKey])): must not be negative"
                )
            }
            root[keyPath: path] = value
        }, encode: { root, container in
            try container.encode(root[keyPath: path], forKey: AnyCodingKey(key))
        })
    }

    /// A property whose JSON object only overrides the keys it contains.
    init<Value: PartiallyCodable>(_ key: String, _ path: WritableKeyPath<Root, Value>) {
        self.init(key: key, decode: { container, root in
            let codingKey = AnyCodingKey(key)
            guard container.contains(codingKey) else { return }
            root[keyPath: path] = try Value(from: container.superDecoder(forKey: codingKey), over: root[keyPath: path])
        }, encode: { root, container in
            try container.encode(root[keyPath: path], forKey: AnyCodingKey(key))
        })
    }
}

/// A value coded as a JSON object whose keys are listed in `fields`.
protocol PartiallyCodable: Codable {
    static var fields: [CodingField<Self>] { get }
}

extension PartiallyCodable {
    /// Decodes the keys present over `base`; missing keys keep the base's values.
    init(from decoder: any Decoder, over base: Self) throws {
        let container = try decoder.strictContainer(allowing: Self.fields.map(\.key))
        var value = base
        for field in Self.fields { try field.decode(container, &value) }
        self = value
    }

    /// Decodes a value that has no base to fall back on: every key is required.
    init(from decoder: any Decoder, requiringAllKeysOver seed: Self) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        if let missing = Self.fields.first(where: { !container.contains(AnyCodingKey($0.key)) }) {
            throw DecodingError.keyNotFound(AnyCodingKey(missing.key), DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Missing key \"\(missing.key)\" in \(AnyCodingKey.path(decoder.codingPath))"
            ))
        }
        try self.init(from: decoder, over: seed)
    }

    /// Encodes every key, so that the output is complete.
    func encodeFields(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for field in Self.fields { try field.encode(self, &container) }
    }
}

// MARK: - Conformances

extension Theme: PartiallyCodable {
    /// Missing keys take the values of `Theme.default`.
    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, over: .default)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeFields(to: encoder)
    }

    static var fields: [CodingField<Theme>] {
        [
            CodingField("fontFamily", \.fontFamily),
            CodingField("fontSize", \.fontSize),
            CodingField("codeFontFamily", \.codeFontFamily),
            CodingField("codeFontSize", \.codeFontSize),
            headingsField,
            CodingField("lineHeightMultiple", \.lineHeightMultiple),
            CodingField("textColor", \.textColor),
            CodingField("secondaryTextColor", \.secondaryTextColor),
            CodingField("linkColor", \.linkColor),
            CodingField("codeBackgroundColor", \.codeBackgroundColor),
            CodingField("codeSyntax", \.codeSyntax),
            CodingField("codeLanguageLabel", \.codeLanguageLabel),
            CodingField("quoteBarColor", \.quoteBarColor),
            CodingField("ruleColor", \.ruleColor),
            CodingField("backgroundColor", \.backgroundColor),
            CodingField("tableBorders", \.tableBorders),
            CodingField("tableBorderColor", \.tableBorderColor),
            CodingField("tableHeaderBackgroundColor", \.tableHeaderBackgroundColor),
            CodingField("tableAlternateRowBackgroundColor", \.tableAlternateRowBackgroundColor),
            CodingField("paragraphSpacing", \.paragraphSpacing),
            CodingField("blockSpacing", \.blockSpacing),
            CodingField("listItemSpacing", \.listItemSpacing),
            CodingField("listIndent", \.listIndent),
            CodingField("quoteIndent", \.quoteIndent),
            CodingField("quoteBarWidth", \.quoteBarWidth),
            CodingField("codePadding", \.codePadding),
            CodingField("codeCornerRadius", \.codeCornerRadius),
            CodingField("tableCellPadding", \.tableCellPadding),
            CodingField("contentMargins", \.contentMargins),
            CodingField("maxLineWidth", \.maxLineWidth),
        ]
    }

    /// Headings are an object keyed by level, `"1"` to `"6"`; each level only
    /// overrides the keys it contains, over the current style of that level.
    private static var headingsField: CodingField<Theme> {
        CodingField(key: "headings", decode: { container, theme in
            let key = AnyCodingKey("headings")
            guard container.contains(key) else { return }
            let levels = try container.superDecoder(forKey: key)
                .strictContainer(allowing: HeadingStyles.levels.map(String.init))
            for level in HeadingStyles.levels {
                let levelKey = AnyCodingKey(String(level))
                guard levels.contains(levelKey) else { continue }
                theme.headings[level: level] = try HeadingStyle(
                    from: levels.superDecoder(forKey: levelKey), over: theme.headings[level: level]
                )
            }
        }, encode: { theme, container in
            let levels = Dictionary(uniqueKeysWithValues: HeadingStyles.levels.map { (String($0), theme.headings[level: $0]) })
            try container.encode(levels, forKey: AnyCodingKey("headings"))
        })
    }
}

extension Theme.HeadingStyle: PartiallyCodable {
    /// Decoded on its own, a heading style needs every key; inside a theme, missing
    /// keys take the values of the same level in the base theme.
    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, requiringAllKeysOver: Self(size: 0, weight: .regular, spacingBefore: 0))
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeFields(to: encoder)
    }

    static var fields: [CodingField<Self>] {
        [CodingField("size", \.size), CodingField("weight", \.weight), CodingField("spacingBefore", \.spacingBefore)]
    }
}

extension Theme.Margins: PartiallyCodable {
    /// Decoded on its own, margins need every key; inside a theme, missing keys
    /// take the values of the base theme.
    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, requiringAllKeysOver: Self(horizontal: 0, vertical: 0))
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeFields(to: encoder)
    }

    static var fields: [CodingField<Self>] {
        [CodingField("horizontal", \.horizontal), CodingField("vertical", \.vertical)]
    }
}

extension Theme.CodeSyntaxColors: PartiallyCodable {
    /// Decoded on its own, the colors need every key; inside a theme, missing
    /// keys take the values of the base theme.
    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, requiringAllKeysOver: .default)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeFields(to: encoder)
    }

    static var fields: [CodingField<Self>] {
        [
            CodingField("keyword", \.keyword),
            CodingField("string", \.string),
            CodingField("comment", \.comment),
            CodingField("number", \.number),
            CodingField("type", \.type),
            CodingField("function", \.function),
            CodingField("variable", \.variable),
            CodingField("constant", \.constant),
            CodingField("operator", \.operator),
            CodingField("punctuation", \.punctuation),
            CodingField("tag", \.tag),
            CodingField("attribute", \.attribute),
        ]
    }
}
