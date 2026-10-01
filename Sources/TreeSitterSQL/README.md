# TreeSitterSQL (vendored)

Generated parser of [tree-sitter-sql](https://github.com/DerekStride/tree-sitter-sql)
by Derek Stride, MIT License (see `LICENSE` beside this file).

The project's release tags do not contain the generated `src/parser.c`; it is
published on the `gh-pages` branch instead. These files come unchanged from
commit `39fdb006403747241244326e8af3b3e96b85381c` of that branch, the build of
`main` at `97614d051eebfd3bc5d97c0bdb5a1638719ca811` (after release v0.3.11):

- `src/parser.c`, `src/scanner.c`, `src/tree_sitter/*.h`
- `include/tree_sitter_sql.h` (from `bindings/swift/TreeSitterSql/sql.h`)

`src/scanner_wrapper.c` is not part of the grammar: it compiles `scanner.c`
with a warning turned off. The highlight query is embedded in
`Sources/KayakomaKit/HighlightQueries`.
