## Unreleased

- `dartvel_documents` compiles for the web: PDFium sits behind a conditional import, and on the web `DVDocuments.open` answers `DVDocumentUnavailable` with the reason. Its first version imported `dart:ffi` from the public library, which broke Media-Bits' web build.
- First version: `DVDocuments.open`, `DVDocument.pageCount`, `pageSize`, `renderPage`, `close`, and the `DVDocumentPage` widget. PDF through a bundled, sha256-pinned PDFium (`chromium/8076`); presentations and office documents through LibreOffice where installed; a reason (`DVDocumentUnavailable`) everywhere else. Verified on Linux x64.
