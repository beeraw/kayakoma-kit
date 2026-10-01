// `queries/highlights.scm` of tree-sitter-typescript v0.23.2, MIT License; see THIRD_PARTY_NOTICES.md.
// Generated from the upstream file: update it with the grammar's version in Package.swift.

extension HighlightQueries {
    static let typescript = #"""
    ; Types

    (type_identifier) @type
    (predefined_type) @type.builtin

    ((identifier) @type
     (#match? @type "^[A-Z]"))

    (type_arguments
      "<" @punctuation.bracket
      ">" @punctuation.bracket)

    ; Variables

    (required_parameter (identifier) @variable.parameter)
    (optional_parameter (identifier) @variable.parameter)

    ; Keywords

    [ "abstract"
      "declare"
      "enum"
      "export"
      "implements"
      "interface"
      "keyof"
      "namespace"
      "private"
      "protected"
      "public"
      "type"
      "readonly"
      "override"
      "satisfies"
    ] @keyword
    """#
}
