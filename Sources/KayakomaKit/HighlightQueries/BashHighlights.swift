// `queries/highlights.scm` of tree-sitter-bash v0.25.1, MIT License; see THIRD_PARTY_NOTICES.md.
// Generated from the upstream file: update it with the grammar's version in Package.swift.

extension HighlightQueries {
    static let bash = #"""
    [
      (string)
      (raw_string)
      (heredoc_body)
      (heredoc_start)
    ] @string

    (command_name) @function

    (variable_name) @property

    [
      "case"
      "do"
      "done"
      "elif"
      "else"
      "esac"
      "export"
      "fi"
      "for"
      "function"
      "if"
      "in"
      "select"
      "then"
      "unset"
      "until"
      "while"
    ] @keyword

    (comment) @comment

    (function_definition name: (word) @function)

    (file_descriptor) @number

    [
      (command_substitution)
      (process_substitution)
      (expansion)
    ]@embedded

    [
      "$"
      "&&"
      ">"
      ">>"
      "<"
      "|"
    ] @operator

    (
      (command (_) @constant)
      (#match? @constant "^-")
    )
    """#
}
