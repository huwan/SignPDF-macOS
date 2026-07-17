# SignPDF contributor instructions

## Project overview

SignPDF is a native macOS 13+ SwiftUI/AppKit application for placing reusable vector PDF signatures onto PDF documents. It is a Swift Package executable with no third-party runtime dependencies. The UI is primarily Chinese.

Keep all document and signature processing local. Do not introduce uploads, analytics, network services, or rasterization into the signing workflow.

## Repository layout

- `Sources/SignPDF/ContentView.swift`: main SwiftUI layout, sidebars, toolbar, width editor, and localized width parsing/formatting.
- `Sources/SignPDF/DocumentModel.swift`: document state, signature assets, placements, dirty-state handling, open/import/export actions.
- `Sources/SignPDF/PDFCanvasView.swift`: AppKit canvas, mouse and keyboard interaction, placement geometry, coordinate conversion.
- `Sources/SignPDF/PDFExporter.swift`: vector PDF composition, page normalization, annotation flattening.
- `Sources/SignPDF/PDFPageVectorPreview.swift`: vector preview drawing.
- `Sources/SignPDF/SignatureLibrary.swift`: persistent signature library under Application Support.
- `Sources/SignPDF/SignPDFApp.swift`: app lifecycle, Finder open handling, window close/quit safeguards.
- `Tests/SignPDFTests/SignPDFTests.swift`: geometry, export, persistence, and state regression tests.
- `Resources/Info.plist`: app and build version plus PDF document association.
- `Scripts/build-app.sh`: production build, app bundle assembly, icon generation, ad-hoc signing.
- `Scripts/install-app.sh`: build, non-interactive install to `/Applications`, Launch Services registration.

## Architecture and implementation rules

### PDF fidelity

- Preserve source pages and signatures as vector content. Do not render pages or signatures to bitmap images for export.
- The original PDF must never be modified in place. Export to a separate destination.
- Existing annotations and AcroForm appearances are intentionally flattened into the exported visual page. Interactive annotations, form controls, and links are not preserved.
- Use `.mediaBox` consistently unless a task explicitly changes the box policy.
- Do not use `page.bounds(for: .mediaBox).size` directly as the displayed page size. PDFKit returns the unrotated box. Use `PDFPageGeometry.displaySize(for:)`, which swaps width and height for 90° and 270° rotations.
- Keep preview, placement coordinates, signature aspect ratios, and exported page sizes in the same display-oriented coordinate system.
- Preserve `PDFPageGeometry.concatenate(_:to:)`. Replacing it with a direct `CGContext.concatenate` can cause Quartz to drop quarter-turned page content when drawing into another PDF context.
- `PDFExporter.draw` is shared by document previews, signature previews, and export. Changes there require regression testing for ordinary pages, rotated pages, annotations, and zoom scaling.

### Geometry and sizing

- PDF placement rectangles use bottom-left PDF coordinates and PDF points.
- `PDFCanvasView` is flipped AppKit space. Convert through `CanvasGeometry`; do not duplicate ad hoc coordinate transforms.
- Signature width is the canonical physical dimension. Convert using `SignatureSizing.pointsPerCentimeter` (`72 / 2.54`).
- Preserve signature aspect ratio during insertion and resizing.
- Clamp placements to the displayed page bounds through `PlacementGeometry`.
- Reuse `SignatureWidthText` for localized numeric formatting and parsing. UI measurements must agree with exact-width and saved-default-width values.
- Default signature width is stored per library asset. Changing a default must not resize existing placements or mark the current PDF layout dirty.

### State and UI behavior

- `DocumentModel` is `@MainActor`; keep UI-observed mutations on the main actor.
- A signature layout is dirty only when placements effectively differ from the last handled/exported layout.
- Preserve the unsaved-change prompt when opening another document, closing the window, or quitting.
- Signature placement mode is one-shot and must remain cancellable with Escape or right-click.
- Keep selection, hover, preview, zoom, continuous scrolling, and current-page tracking synchronized across all pages.
- Avoid binding destructive file behavior to the bare Delete key; Finder may still own keyboard focus.
- Keep user-facing strings in Chinese unless the surrounding UI is already English.

### Signature library

- Library items live under `~/Library/Application Support/app.signpdf.SignPDF/Signatures` by default.
- Use atomic/temp-directory replacement patterns already implemented in `SignatureLibrary`.
- Isolate corrupt items without hiding valid signatures.
- Deleting a library asset that is already placed in the current document must preserve a detached in-memory copy until all placements using it are removed.
- Maintain backward compatibility with existing metadata unless a migration is deliberately added and tested.

## Verification

Run the complete test suite after every behavior or PDF-processing change:

```bash
swift test
```

Tests must create their own temporary PDFs and clean them up. Do not commit personal documents, signatures, or PDF fixtures.

For release-relevant changes, also build and verify the application bundle:

```bash
./Scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 .build/app/SignPDF.app
```

Confirm the executable architecture and embedded version when publishing:

```bash
file .build/app/SignPDF.app/Contents/MacOS/SignPDF
plutil -p .build/app/SignPDF.app/Contents/Info.plist
```

Before committing, run:

```bash
git diff --check
git status -sb
```

## Installation and privileges

- Prefer user-scoped and unprivileged workflows when they can complete the task safely.
- Avoid interactive password prompts and macOS authorization dialogs when practical; this is a preference, not an absolute prohibition.
- When elevation may be needed, try a non-interactive check such as `sudo -n` first so the workflow does not unexpectedly block on a password prompt.
- If elevated privileges are genuinely required and no reasonable unprivileged alternative exists, explain why and proceed with interactive password entry or the macOS authorization dialog as needed.
- Keep routine builds and tests non-interactive. Changes to `Scripts/install-app.sh` may add an interactive fallback only when the behavior is explicit to the user and the non-interactive path is attempted first.
- Building and testing do not require elevated privileges.

## Release process

Stable releases use patch-style semantic versions such as `v1.1.2` and are published from `main`.

1. Ensure `main` is synchronized with `origin/main` and the worktree contains only intended changes.
2. Update both values in `Resources/Info.plist`:
   - `CFBundleShortVersionString`: release version without `v`.
   - `CFBundleVersion`: incrementing integer build number.
3. Update the release asset filename in `README.md`.
4. Run `swift test` and `./Scripts/build-app.sh`; verify the ad-hoc signature.
5. Commit with a terse imperative summary and push `main`.
6. Package the built app as `SignPDF-<version>-macOS-arm64.zip` using `ditto --keepParent`.
7. Run `unzip -t` and calculate SHA-256 with `shasum -a 256`.
8. Create a non-draft, non-prerelease GitHub Release titled `SignPDF <version>`, tag `v<version>`, targeting the released commit.
9. Include highlights, macOS/architecture requirements, installation instructions, the ad-hoc signing warning, and SHA-256 in the release notes.
10. Verify the uploaded asset, remote tag, release URL, and clean synchronized worktree.

Do not publish, tag, push, install, or modify a GitHub Release unless the user explicitly requests it.

## Change discipline

- Preserve unrelated user changes in a dirty worktree; stage only files belonging to the task.
- Prefer focused changes over broad rewrites.
- Add regression tests for bug fixes, especially page rotation, coordinate mapping, export fidelity, sizing, persistence, and dirty-state behavior.
- Do not add dependencies when Foundation, Core Graphics, PDFKit, SwiftUI, or AppKit can solve the problem cleanly.

## Maintaining this file

- Treat `AGENTS.md` as living project documentation and keep it aligned with the repository.
- Update it in the same task when a change materially affects architecture, file responsibilities, supported platforms, core PDF/geometry rules, development commands, testing requirements, installation behavior, privilege handling, or the release process.
- Do not update it for routine implementation details that do not change contributor guidance.
- When instructions become obsolete, replace or remove them instead of only appending new exceptions.
- Include an `AGENTS.md` update in the same commit as the code or workflow change that requires it, unless the user asks to keep documentation changes separate.
