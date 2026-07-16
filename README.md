# SignPDF

<img src="Resources/AppIcon.png" alt="SignPDF app icon" width="144">

SignPDF is a native macOS app for placing vector signatures onto PDF documents. It provides a visual editor for positioning and resizing signatures while keeping them sharp at any zoom level in the exported PDF.

Everything runs locally. SignPDF does not upload documents or signatures to a server.

## Features

- Native SwiftUI and AppKit interface for macOS.
- Open PDFs from Finder, the Open With menu, or the app toolbar.
- Import one or more single-page PDF signature files.
- Add multiple signatures to any page.
- Drag signatures to reposition them.
- Resize signatures proportionally with the selection handle.
- Use arrow keys for precise positioning; hold Shift to move by 10 points.
- Delete selected signatures from the toolbar or context menu.
- Navigate pages with a thumbnail sidebar.
- Zoom the editor from 35% to 300% without changing export coordinates.
- Preserve vector page content and vector signature artwork during export.
- Flatten existing annotation and form appearances so filled-in text remains visible.
- Export beside the source PDF by default as `<name>-signed.pdf`.

## Requirements

- macOS 13 or later
- Xcode 15 or later, including the Xcode Command Line Tools

No third-party runtime dependencies are required.

## Install

Build and install SignPDF for the current user:

```bash
./Scripts/install-app.sh
```

The app is installed at:

```text
~/Applications/SignPDF.app
```

The installer also registers SignPDF as a PDF editor with macOS Launch Services. After installation, you can:

- Double-click SignPDF in `~/Applications`.
- Right-click a PDF and choose **Open With > SignPDF**.
- Drag a PDF onto the SignPDF app icon.

No administrator privileges or password prompts are required.

## Usage

1. Open the PDF that needs to be signed.
2. Select **Import Signature PDF** and choose one or more single-page vector PDF signatures.
3. Click a signature in the right sidebar to add it to the current page.
4. Drag the signature to position it.
5. Drag the lower-right selection handle to resize it proportionally.
6. Use the toolbar trash button or the signature context menu to delete it.
7. Select **Export** to create the signed PDF.

SignPDF intentionally does not bind deletion to the bare Delete key. This avoids accidental Finder file deletion when keyboard focus is outside the app.

## PDF Output Behavior

Export uses Core Graphics and PDFKit drawing commands rather than screenshots or rasterized page images. Vector signatures therefore remain sharp when the resulting PDF is enlarged.

Existing annotation and AcroForm appearances are drawn into the exported page so visible filled-in text is preserved. The export is a visual flattening process, so the following interactive features are not retained:

- Editable annotations
- Editable form controls
- Hyperlinks and other interactive actions

The original PDF is never modified in place.

## Development

Open `Package.swift` in Xcode and run the `SignPDF` scheme, or launch a development build from Terminal:

```bash
swift run SignPDF
```

Build an app bundle without installing it:

```bash
./Scripts/build-app.sh
```

The generated development bundle is placed under `.build/app/SignPDF.app`.

## Tests

Run the test suite with:

```bash
swift test
```

The tests generate their own temporary vector PDFs. No personal documents, signatures, or PDF fixtures are stored in the repository.

## Project Structure

```text
Package.swift                 Swift package definition
Resources/
  AppIcon.png                 Source app icon
  Info.plist                  macOS bundle metadata and PDF association
Scripts/
  build-app.sh                Builds and signs a local app bundle
  install-app.sh              Installs and registers the app for the user
Sources/SignPDF/
  ContentView.swift           Main SwiftUI layout
  DocumentModel.swift         Document, signature, and placement state
  PDFCanvasView.swift         Interactive PDF editor canvas
  PDFExporter.swift           Vector PDF composition and export
  PDFPageVectorPreview.swift  Vector signature previews
  SignPDFApp.swift            App lifecycle and Finder open handling
Tests/SignPDFTests/           Geometry and PDF export tests
```
