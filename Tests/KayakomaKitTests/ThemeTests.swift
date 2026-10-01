import Foundation
import Testing
@testable import KayakomaKit

@Test func defaultThemeRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(Theme.default)
    let decoded = try JSONDecoder().decode(Theme.self, from: data)
    #expect(decoded == Theme.default)
}

@Test func customThemeRoundTripsThroughJSON() throws {
    var theme = Theme.default
    theme.fontFamily = "Georgia"
    theme.fontSize = 16
    theme.maxLineWidth = nil
    theme.linkColor = .custom(light: "#0055CC", dark: "#66AAFFCC")
    theme.headings.level1 = Theme.HeadingStyle(size: 34, weight: .heavy, spacingBefore: 24)

    let decoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
    #expect(decoded == theme)
}

@Test func colorsDecodeFromNamesAndPairs() throws {
    let json = ##"[ "secondaryLabel", { "light": "#112233", "dark": "#445566" } ]"##
    let colors = try JSONDecoder().decode([Theme.Color].self, from: Data(json.utf8))
    #expect(colors == [.system(.secondaryLabel), .custom(light: "#112233", dark: "#445566")])
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode([Theme.Color].self, from: Data(#"["chartreuse"]"#.utf8))
    }
}

@Test func tableSettingsRoundTripThroughJSON() throws {
    var theme = Theme.default
    theme.tableBorderColor = .custom(light: "#CCCCCC", dark: "#444444")
    theme.tableHeaderBackgroundColor = .system(.windowBackground)
    theme.tableAlternateRowBackgroundColor = .custom(light: "#00000008", dark: "#FFFFFF0A")
    theme.tableCellPadding = Theme.Margins(horizontal: 12, vertical: 4)

    let decoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
    #expect(decoded == theme)
    #expect(Theme.default.tableAlternateRowBackgroundColor == nil)
}

// MARK: - Partial themes

private func decodeTheme(_ json: String) throws -> Theme {
    try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
}

/// The message of the decoding error thrown for `json`, or `nil` if it decodes.
private func decodingErrorMessage(_ json: String) -> String? {
    do {
        _ = try decodeTheme(json)
        return nil
    } catch let DecodingError.dataCorrupted(context) {
        return context.debugDescription
    } catch {
        return "\(error)"
    }
}

@Test func emptyObjectDecodesToDefaultTheme() throws {
    #expect(try decodeTheme("{}") == Theme.default)
}

@Test func singleTopLevelKeyOverridesOnlyThatSetting() throws {
    var expected = Theme.default
    expected.fontSize = 16
    #expect(try decodeTheme(##"{ "fontSize": 16 }"##) == expected)
}

@Test func nullClearsAnOptionalSetting() throws {
    #expect(try decodeTheme(##"{ "maxLineWidth": null }"##).maxLineWidth == nil)
}

@Test func singleHeadingLevelOverridesOnlyItsKeys() throws {
    let theme = try decodeTheme(##"{ "headings": { "2": { "size": 30 } } }"##)
    var expected = Theme.default
    expected.headings.level2.size = 30
    #expect(theme == expected)
    #expect(theme.headings.level2.weight == Theme.HeadingStyles.default.level2.weight)
}

@Test func partialMarginsKeepTheOtherDefaultField() throws {
    let theme = try decodeTheme(##"{ "contentMargins": { "horizontal": 48 }, "tableCellPadding": { "vertical": 2 } }"##)
    #expect(theme.contentMargins == Theme.Margins(horizontal: 48, vertical: Theme.default.contentMargins.vertical))
    #expect(theme.tableCellPadding == Theme.Margins(horizontal: Theme.default.tableCellPadding.horizontal, vertical: 2))
}

@Test func lightOnlyColorIsUsedForBothAppearances() throws {
    let theme = try decodeTheme(##"{ "linkColor": { "light": "#0055CC" } }"##)
    #expect(theme.linkColor == .custom(light: "#0055CC", dark: "#0055CC"))
}

@Test func unknownTopLevelKeyIsRejected() throws {
    let message = try #require(decodingErrorMessage(##"{ "fontSzie": 16 }"##))
    #expect(message.contains("fontSzie"))
}

@Test func unknownNestedKeyIsRejectedWithItsPath() throws {
    let heading = try #require(decodingErrorMessage(##"{ "headings": { "1": { "sizze": 30 } } }"##))
    #expect(heading.contains("\"sizze\"") && heading.contains("headings.1"))

    let level = try #require(decodingErrorMessage(##"{ "headings": { "7": { "size": 30 } } }"##))
    #expect(level.contains("\"7\"") && level.contains("headings"))

    let emptyLevel = try #require(decodingErrorMessage(##"{ "headings": { "7": {} } }"##))
    #expect(emptyLevel.contains("\"7\"") && emptyLevel.contains("headings"))

    let levelZero = try #require(decodingErrorMessage(##"{ "headings": { "0": {} } }"##))
    #expect(levelZero.contains("\"0\"") && levelZero.contains("headings"))

    let margins = try #require(decodingErrorMessage(##"{ "contentMargins": { "top": 4 } }"##))
    #expect(margins.contains("\"top\"") && margins.contains("contentMargins"))

    let color = try #require(decodingErrorMessage(##"{ "linkColor": { "light": "#000000", "drak": "#FFFFFF" } }"##))
    #expect(color.contains("\"drak\"") && color.contains("linkColor"))
}

@Test func invalidValuesAreRejectedWithTheirPath() throws {
    let hex = try #require(decodingErrorMessage(##"{ "linkColor": { "light": "#12345G" } }"##))
    #expect(hex.contains("#12345G") && hex.contains("linkColor.light"))

    let name = try #require(decodingErrorMessage(##"{ "ruleColor": "chartreuse" }"##))
    #expect(name.contains("chartreuse") && name.contains("ruleColor"))

    let negative = try #require(decodingErrorMessage(##"{ "headings": { "3": { "spacingBefore": -2 } } }"##))
    #expect(negative.contains("headings.3.spacingBefore"))
}

@Test func encodingWritesEveryKey() throws {
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Theme.default)) as? [String: Any])
    #expect(object.count == Theme.fields.count)
    #expect(object["maxLineWidth"] != nil && object["tableAlternateRowBackgroundColor"] is NSNull)
    let headings = try #require(object["headings"] as? [String: Any])
    #expect(headings.keys.sorted() == ["1", "2", "3", "4", "5", "6"])
}

@Test func heavilyCustomisedThemeRoundTripsThroughJSON() throws {
    var theme = Theme.default
    theme.codeFontFamily = "Menlo"
    theme.headings[level: 6] = Theme.HeadingStyle(size: 11, weight: .medium, spacingBefore: 4)
    theme.textColor = .custom(light: "#111111", dark: "#EEEEEE")
    theme.tableAlternateRowBackgroundColor = .system(.windowBackground)
    theme.contentMargins = Theme.Margins(horizontal: 0, vertical: 60)
    theme.maxLineWidth = nil

    let decoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
    #expect(decoded == theme)
}

@Test func headingStyleDecodedOnItsOwnNeedsEveryKey() {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Theme.HeadingStyle.self, from: Data(##"{ "size": 20 }"##.utf8))
    }
}

// MARK: - Heading levels

@Test func themeWithSeveralCustomisedLevelsRoundTripsThroughJSON() throws {
    var theme = Theme.default
    theme.headings.level1 = Theme.HeadingStyle(size: 40, weight: .heavy, spacingBefore: 30)
    theme.headings[level: 3].weight = .regular
    theme.headings.level4.spacingBefore = 0
    theme.headings[level: 6] = Theme.HeadingStyle(size: 9, weight: .medium, spacingBefore: 2)

    let decoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
    #expect(decoded == theme)
    #expect(decoded.headings.level2 == Theme.HeadingStyles.default.level2)
}

@Test func themeWithEveryLevelCustomisedRoundTripsThroughJSON() throws {
    var theme = Theme.default
    for level in Theme.HeadingStyles.levels {
        theme.headings[level: level] = Theme.HeadingStyle(size: CGFloat(50 - level), weight: .medium, spacingBefore: CGFloat(level))
    }
    let decoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
    #expect(decoded == theme)
}

@Test func headingSubscriptReadsAndWritesEachLevel() {
    var headings = Theme.HeadingStyles.default
    #expect(headings[level: 1] == headings.level1)
    #expect(headings[level: 4] == headings.level4)
    #expect(headings[level: 6] == headings.level6)

    let style = Theme.HeadingStyle(size: 21, weight: .regular, spacingBefore: 7)
    for level in Theme.HeadingStyles.levels {
        var copy = headings
        copy[level: level] = style
        #expect(copy[level: level] == style)
        // Only that level changed.
        for other in Theme.HeadingStyles.levels where other != level {
            #expect(copy[level: other] == headings[level: other])
        }
    }

    headings[level: 5].size = 99
    #expect(headings.level5.size == 99)
}

@Test func headingSubscriptClampsOutOfRangeLevels() {
    var headings = Theme.HeadingStyles.default
    #expect(headings[level: 0] == headings.level1)
    #expect(headings[level: -3] == headings.level1)
    #expect(headings[level: 7] == headings.level6)
    #expect(headings[level: .max] == headings.level6)

    let style = Theme.HeadingStyle(size: 5, weight: .heavy, spacingBefore: 1)
    headings[level: 0] = style
    #expect(headings.level1 == style)
    headings[level: 12] = style
    #expect(headings.level6 == style)
    #expect(headings.level2 == Theme.HeadingStyles.default.level2)
}

// MARK: - Table borders

@Test func tableBordersDefaultToHorizontal() throws {
    #expect(Theme.default.tableBorders == .horizontal)
    #expect(try decodeTheme("{}").tableBorders == .horizontal)
    #expect(try decodeTheme(##"{ "fontSize": 15 }"##).tableBorders == .horizontal)
}

@Test func tableBordersDecodeBothValues() throws {
    #expect(try decodeTheme(##"{ "tableBorders": "horizontal" }"##).tableBorders == .horizontal)
    #expect(try decodeTheme(##"{ "tableBorders": "all" }"##).tableBorders == .all)
}

@Test func invalidTableBordersAreRejectedWithTheirPath() throws {
    let message = try #require(decodingErrorMessage(##"{ "tableBorders": "vertical" }"##))
    #expect(message.contains("tableBorders") && message.contains("vertical"))
}

@Test func tableBordersRoundTripThroughJSON() throws {
    var theme = Theme.default
    theme.tableBorders = .all
    let data = try JSONEncoder().encode(theme)
    #expect(try JSONDecoder().decode(Theme.self, from: data) == theme)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["tableBorders"] as? String == "all")
    let defaults = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Theme.default)) as? [String: Any])
    #expect(defaults["tableBorders"] as? String == "horizontal")
}
