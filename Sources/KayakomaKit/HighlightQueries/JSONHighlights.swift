// `queries/highlights.scm` of tree-sitter-json v0.24.8, MIT License; see THIRD_PARTY_NOTICES.md. Adapted as noted in the query's `Kayakoma:` comments.
// Generated from the upstream file: update it with the grammar's version in Package.swift.

extension HighlightQueries {
    static let json = #"""
    (string) @string

    ; Kayakoma: moved after `(string) @string`, since the last pattern that
    ; matches a node wins and object keys are strings too.
    (pair
      key: (_) @string.special.key)

    (number) @number

    [
      (null)
      (true)
      (false)
    ] @constant.builtin

    (escape_sequence) @escape

    (comment) @comment
    """#
}
