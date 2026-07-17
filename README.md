# SignPDF

<p align="center">
  <img src="Resources/AppIcon.png" alt="SignPDF app icon" width="144">
</p>

SignPDF is a native macOS app for placing vector signatures onto PDF documents. It provides a visual editor for positioning and resizing signatures while keeping them sharp at any zoom level in the exported PDF.

Document and signature processing stays local. SignPDF does not upload documents or signatures; its only network access is checking and downloading signed updates from GitHub Releases.

## Features

- Native SwiftUI and AppKit interface for macOS.
- Check GitHub Releases on launch and securely download, install, and relaunch into signed updates with Sparkle.
- Manually check for updates at any time from the application menu.
- Open PDFs from Finder, the Open With menu, or the app toolbar.
- Import one or more single-page PDF signature files.
- Keep imported signatures in a local library for reuse across launches.
- Start new signatures at a practical 3.6 cm width and keep a separate default width for each saved signature.
- Remove saved signatures from the library when they are no longer needed.
- Select a signature, preview it under the pointer, and click the exact page location where it belongs.
- Double-click a signature to insert it in the center of the current page.
- Add multiple signatures to any page.
- Drag signatures to reposition them.
- Resize signatures proportionally with the selection handle.
- Enter an exact width in centimeters for a selected signature, or save its current width as that signature's future default.
- Use arrow keys for precise positioning; hold Shift to move by 10 points.
- Delete selected signatures from the toolbar or context menu.
- Read PDFs in a continuous vertical page stream with lazy page rendering.
- Use the thumbnail sidebar for navigation; its selection follows the page at the center of the viewport.
- Zoom the editor from 35% to 300% with the toolbar or a trackpad pinch gesture, without changing export coordinates.
- Preserve vector page content and vector signature artwork during export.
- Flatten existing annotation and form appearances so filled-in text remains visible.
- Export beside the source PDF by default as `<name>-signed.pdf`.
- Warn before closing, quitting, or opening another PDF when signature changes have not been exported.

## Requirements

- macOS 13 or later
- Apple silicon for the prebuilt release
- Xcode 15.3 or later, including the Xcode Command Line Tools, when building from source

The release bundle includes Sparkle 2 for secure automatic updates. No separate runtime installation is required.

## Install

### Download a release

Download `SignPDF-1.2.0-macOS-arm64.zip` from the [GitHub Releases page](https://github.com/huwan/SignPDF-macOS/releases), unzip it, and move `SignPDF.app` to `/Applications`.

The prebuilt app is ad-hoc signed and is not notarized by Apple. If macOS blocks its first launch, try opening it once, then go to **System Settings > Privacy & Security** and choose **Open Anyway** for SignPDF. This approval is needed only once.

### Build from source

Build and install SignPDF in the system Applications folder:

```bash
./Scripts/install-app.sh
```

The app is installed at:

```text
/Applications/SignPDF.app
```

The installer also registers SignPDF as a PDF editor with macOS Launch Services. After installation, you can:

- Double-click SignPDF in `/Applications`.
- Right-click a PDF and choose **Open With > SignPDF**.
- Drag a PDF onto the SignPDF app icon.

The installer writes directly to `/Applications` when it is writable. Otherwise, it attempts non-interactive administrator authorization with `sudo -n` and exits with an error instead of opening a password prompt if authorization is unavailable.

## Usage

1. Open the PDF that needs to be signed.
2. Select **Import Signature PDF** and choose one or more single-page vector PDF signatures. Imported signatures are copied into SignPDF's local Application Support directory and restored the next time the app opens.
   New signatures use a default insertion width of 3.6 cm. To choose a different default for one signature, open the ellipsis menu on its library card and select **Set Default Width**.
3. Scroll continuously through the document, or click a thumbnail to jump to a page.
4. Click a signature in the right sidebar, then click the desired location on any page. A translucent vector preview follows the pointer; press Escape or right-click to cancel. Double-clicking a signature inserts it in the center of the currently visible page instead.
5. Drag the signature to position it.
6. Drag the lower-right selection handle to resize it proportionally.
7. For a precise physical size, select the placed signature and open the ruler menu in the toolbar. Choose **Set Exact Width** to enter centimeters, or **Use Current Width as Default** to reuse the current size the next time that library signature is inserted.
8. Use the toolbar trash button or the signature context menu to delete it.
9. Select **Export** to create the signed PDF.

If the signature layout has changed since the PDF was opened or last exported, SignPDF asks whether to export before closing the window, quitting the app, or opening another PDF. Choosing **Cancel** keeps the current document open.

To remove a saved signature, use the ellipsis menu on its card in the signature library. Existing instances in the document currently being edited remain in place and can still be removed individually with the toolbar trash button or context menu.

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

Swift Package Manager resolves the pinned Sparkle framework used for automatic updates. Release archives are signed with a project Ed25519 key stored in the maintainer's macOS login Keychain; only the public key is embedded in the app.

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
  generate-appcast.sh         Signs an update archive and refreshes appcast.xml
  install-app.sh              Installs and registers the app in /Applications
Sources/SignPDF/
  ContentView.swift           Main SwiftUI layout
  DocumentModel.swift         Document, signature, and placement state
  PDFCanvasView.swift         Interactive PDF editor canvas
  PDFExporter.swift           Vector PDF composition and export
  PDFPageVectorPreview.swift  Vector signature previews
  SignatureLibrary.swift      Persistent local signature storage
  SignPDFApp.swift            App lifecycle and Finder open handling
  UpdateController.swift      Sparkle automatic and manual update integration
Tests/SignPDFTests/           Geometry, PDF export, and persistence tests
appcast.xml                   Sparkle stable update feed
```
