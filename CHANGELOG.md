# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.1

### Fixed

- Replacing the document of a `MarkdownView` with a shorter one no longer raises an `NSRangeException` when a table or a paragraph with code spans was laid out.
- `frame(ofBlockAt:)` of the last block no longer includes the empty line after the document's final line break.

## 1.0.0

- Initial release.
