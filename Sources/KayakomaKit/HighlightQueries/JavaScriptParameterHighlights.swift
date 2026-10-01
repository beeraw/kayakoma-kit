// `queries/highlights-params.scm` of tree-sitter-javascript v0.23.1, MIT License; see THIRD_PARTY_NOTICES.md.
// Generated from the upstream file: update it with the grammar's version in Package.swift.

extension HighlightQueries {
    static let javascriptParameters = #"""
    (formal_parameters
      [
        (identifier) @variable.parameter
        (array_pattern
          (identifier) @variable.parameter)
        (object_pattern
          [
            (pair_pattern value: (identifier) @variable.parameter)
            (shorthand_property_identifier_pattern) @variable.parameter
          ])
      ]
    )
    """#
}
