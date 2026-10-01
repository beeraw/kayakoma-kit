// `queries/highlights.scm` of tree-sitter-html v0.23.2, MIT License; see THIRD_PARTY_NOTICES.md.
// Generated from the upstream file: update it with the grammar's version in Package.swift.

extension HighlightQueries {
    static let html = #"""
    (tag_name) @tag
    (erroneous_end_tag_name) @tag.error
    (doctype) @constant
    (attribute_name) @attribute
    (attribute_value) @string
    (comment) @comment

    [
      "<"
      ">"
      "</"
      "/>"
    ] @punctuation.bracket
    """#
}
