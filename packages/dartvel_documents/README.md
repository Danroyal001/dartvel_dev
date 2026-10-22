# dartvel_documents

PDFs and presentations in a Dartvel app: open a document, count its pages,
draw any page at the size it is shown.

```dart
import 'package:dartvel_documents/dartvel_documents.dart';

final DVDocument deck = await DVDocuments.open('/church/sunday.pptx');
print(deck.pageCount);

// A page as a widget, drawn at the pixel size it is shown at:
DVDocumentPage(document: deck, page: 3);

// Or as an image:
final ui.Image slide = await deck.renderPage(3, width: 1920);
```

## How it works

- **PDF** is drawn by [PDFium](https://pdfium.googlesource.com/pdfium/),
  Chrome's PDF engine, which this package's build hook bundles into the app
  for the target: the pinned `chromium/8076` build from
  [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries),
  downloaded once into `~/.dartvel/cache/pdfium/` and refused if its sha256
  differs from the pin in `lib/src/pdfium_release.dart`. Nothing is installed
  on the machine running the app.
- **Presentations and office documents** (`.pptx`, `.ppt`, `.pps`, `.ppsx`,
  `.odp`, `.key`, `.docx`, `.doc`, `.odt`, `.rtf`) are converted to PDF with
  LibreOffice where it is installed (on `PATH`, or its usual place on Windows
  and macOS), once per change to the file. Where it is not, opening one
  answers with `DVDocumentUnavailable` saying so, and how to fix it.
- Calls into PDFium are made one at a time; it is not thread-safe.

## Targets

| Target | PDF | Presentations |
|---|---|---|
| Linux x64 / arm64 | Yes (verified on Linux x64: opened, measured and drawn in tests) | With LibreOffice (verified with an `.odt`) |
| Windows x64 / arm64 | PDFium bundled; not yet run there | With LibreOffice; not yet run there |
| macOS x64 / arm64 | PDFium bundled; not yet run there | With LibreOffice; not yet run there |
| Android, iOS | PDFium bundled; not yet run there | No (no LibreOffice): answers with the reason |
| Web | No: answers with the reason (a PDFium WebAssembly build is the next step) | No |
| Fuchsia, 32-bit targets | No PDFium build: answers with the reason | No |

## Status

Unpublished (`publish_to: none`) while it is new; an app depends on it from the
Dartvel repository at a release tag, as it does on `dartvel_windowing`.
