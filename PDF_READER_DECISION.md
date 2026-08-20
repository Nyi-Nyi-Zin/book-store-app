# PDF Reader Decision

The reader needs Android and iOS support, protected local-file rendering, and offline reading after an authorized download.

| Package | Relevant support | Decision |
|---|---|---|
| `syncfusion_flutter_pdfviewer` | Android/iOS and file/memory loading; rich navigation/search/bookmarks; commercial package with a Community License path | Not selected for the first implementation because licensing must be confirmed for the app distribution model. |
| `flutter_pdfview` | Android/iOS, local `filePath` and `pdfData`, native viewer, MIT license | Selected for the initial mobile implementation because it directly supports the required mobile platforms and local protected files with a permissive license. |
| `pdf_render` | Cross-platform rendering and local file/data APIs, but package page notes it is in maintenance mode and points to `pdfrx` | Not selected for the first implementation because the package is in maintenance mode. |

The implementation will download the protected PDF only after the backend access check succeeds, store it in the app cache/documents directory, open it through `PDFView`, and sync page changes to the existing progress endpoint. A cached copy will be usable offline only for a user who previously received authorized access. The server must continue to enforce entitlement checks; local cache presence must never grant server access to another account.

References:

1. [Syncfusion Flutter PDF Viewer on pub.dev](https://pub.dev/packages/syncfusion_flutter_pdfviewer)
2. [flutter_pdfview on pub.dev](https://pub.dev/packages/flutter_pdfview)
3. [pdf_render on pub.dev](https://pub.dev/packages/pdf_render)
