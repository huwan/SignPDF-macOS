import CoreGraphics
import PDFKit
import XCTest
@testable import SignPDF

final class SignPDFTests: XCTestCase {
    func testZoomGeometrySupportsTrackpadMagnificationAndToolbarSteps() {
        XCTAssertEqual(ZoomGeometry.magnified(1, by: 1.25), 1.25, accuracy: 0.001)
        XCTAssertEqual(ZoomGeometry.magnified(2, by: 0.75), 1.5, accuracy: 0.001)
        XCTAssertEqual(ZoomGeometry.stepped(1, by: ZoomGeometry.step), 1.1, accuracy: 0.001)
        XCTAssertEqual(ZoomGeometry.stepped(1, by: -ZoomGeometry.step), 0.9, accuracy: 0.001)
    }

    func testZoomGeometryClampsTrackpadMagnificationToSupportedRange() {
        XCTAssertEqual(ZoomGeometry.magnified(1, by: 0.01), ZoomGeometry.minimum)
        XCTAssertEqual(ZoomGeometry.magnified(2, by: 10), ZoomGeometry.maximum)
        XCTAssertEqual(ZoomGeometry.stepped(ZoomGeometry.minimum, by: -1), ZoomGeometry.minimum)
        XCTAssertEqual(ZoomGeometry.stepped(ZoomGeometry.maximum, by: 1), ZoomGeometry.maximum)
    }

    func testContinuousPageGeometryKeepsPageContainingViewportCenter() {
        let pageFrames = [
            0: CGRect(x: 100, y: 0, width: 600, height: 800),
            1: CGRect(x: 100, y: 824, width: 600, height: 200)
        ]
        let viewport = CGRect(x: 0, y: 650, width: 800, height: 220)

        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: viewport,
                pageFrames: pageFrames,
                pageCount: 2,
                keeping: 0
            ),
            0
        )
    }

    func testContinuousPageGeometryChoosesNearestPageAcrossGapAndKeepsTie() {
        let pageFrames = [
            0: CGRect(x: 100, y: 0, width: 600, height: 800),
            1: CGRect(x: 100, y: 824, width: 600, height: 800)
        ]

        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 710, width: 800, height: 220),
                pageFrames: pageFrames,
                pageCount: 2,
                keeping: 0
            ),
            1
        )
        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 702, width: 800, height: 220),
                pageFrames: pageFrames,
                pageCount: 2,
                keeping: 1
            ),
            1
        )
        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 702, width: 800, height: 220),
                pageFrames: pageFrames,
                pageCount: 2,
                keeping: nil
            ),
            0
        )
    }

    func testContinuousPageGeometryIgnoresInvalidFrames() {
        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 0, width: 800, height: 600),
                pageFrames: [
                    0: CGRect(x: 100, y: 0, width: 600, height: 800),
                    1: .zero,
                    2: CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 100)
                ],
                pageCount: 3,
                keeping: nil
            ),
            0
        )
    }

    func testContinuousPageGeometryKeepsFirstAndLastPageAtDocumentEdges() {
        let topFrames = [
            0: CGRect(x: 100, y: 36, width: 210, height: 295),
            1: CGRect(x: 100, y: 355, width: 210, height: 295),
            2: CGRect(x: 100, y: 674, width: 210, height: 295)
        ]
        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 0, width: 800, height: 700),
                pageFrames: topFrames,
                pageCount: 3,
                keeping: 1
            ),
            0
        )

        let bottomFrames = [
            0: CGRect(x: 100, y: -269, width: 210, height: 295),
            1: CGRect(x: 100, y: 50, width: 210, height: 295),
            2: CGRect(x: 100, y: 369, width: 210, height: 295)
        ]
        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 0, width: 800, height: 700),
                pageFrames: bottomFrames,
                pageCount: 3,
                keeping: 1
            ),
            2
        )
    }

    func testContinuousPageGeometryKeepsCurrentPageWhenWholeDocumentFitsViewport() {
        let pageFrames = [
            0: CGRect(x: 100, y: 12, width: 210, height: 295),
            1: CGRect(x: 100, y: 331, width: 210, height: 295)
        ]

        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 0, width: 800, height: 700),
                pageFrames: pageFrames,
                pageCount: 2,
                keeping: 0
            ),
            0
        )
        XCTAssertEqual(
            ContinuousPageGeometry.activePageIndex(
                viewport: CGRect(x: 0, y: 0, width: 800, height: 700),
                pageFrames: pageFrames,
                pageCount: 2,
                keeping: 1
            ),
            1
        )
    }

    func testClampsPlacementInsidePage() {
        let result = PlacementGeometry.clamped(
            CGRect(x: -20, y: 790, width: 200, height: 100),
            to: CGSize(width: 595, height: 842)
        )
        XCTAssertEqual(result.origin.x, 0)
        XCTAssertEqual(result.origin.y, 742)
        XCTAssertEqual(result.size.width, 200)
        XCTAssertEqual(result.size.height, 100)
    }

    func testClampsOversizedPlacement() {
        let result = PlacementGeometry.clamped(
            CGRect(x: 30, y: 40, width: 900, height: 1000),
            to: CGSize(width: 595, height: 842)
        )
        XCTAssertEqual(result, CGRect(x: 0, y: 0, width: 595, height: 842))
    }

    func testCanvasGeometryUsesActualCanvasSizeForZoom() {
        let pageSize = CGSize(width: 600, height: 800)
        let placement = CGRect(x: 100, y: 120, width: 160, height: 64)
        let canvasSize = CGSize(width: 900, height: 1200)

        XCTAssertEqual(CanvasGeometry.scale(pageSize: pageSize, canvasSize: canvasSize), 1.5)
        XCTAssertEqual(
            CanvasGeometry.drawingRect(for: placement, pageSize: pageSize, canvasSize: canvasSize),
            CGRect(x: 150, y: 180, width: 240, height: 96)
        )
        XCTAssertEqual(
            CanvasGeometry.visualRect(for: placement, pageSize: pageSize, canvasSize: canvasSize),
            CGRect(x: 150, y: 924, width: 240, height: 96)
        )
    }

    func testCanvasGeometryKeepsPageAndPlacementOnSameScaleDuringResize() {
        let pageSize = CGSize(width: 600, height: 800)
        let placement = CGRect(x: 100, y: 120, width: 160, height: 64)

        let at100 = CanvasGeometry.drawingRect(
            for: placement,
            pageSize: pageSize,
            canvasSize: pageSize
        )
        let at150 = CanvasGeometry.drawingRect(
            for: placement,
            pageSize: pageSize,
            canvasSize: CGSize(width: 900, height: 1200)
        )

        XCTAssertEqual(at150.minX, at100.minX * 1.5)
        XCTAssertEqual(at150.minY, at100.minY * 1.5)
        XCTAssertEqual(at150.width, at100.width * 1.5)
        XCTAssertEqual(at150.height, at100.height * 1.5)
    }

    func testCanvasGeometryConvertsVisualPointsBackToPDFCoordinates() throws {
        let pageSize = CGSize(width: 600, height: 800)
        let canvasSize = CGSize(width: 1_000, height: 1_200)

        let converted = try XCTUnwrap(CanvasGeometry.pdfPoint(
            for: CGPoint(x: 200, y: 1_020),
            pageSize: pageSize,
            canvasSize: canvasSize
        ))
        XCTAssertEqual(converted.x, 100, accuracy: 0.001)
        XCTAssertEqual(converted.y, 120, accuracy: 0.001)

        let topLeft = try XCTUnwrap(CanvasGeometry.pdfPoint(
            for: CGPoint(x: 50, y: 0),
            pageSize: pageSize,
            canvasSize: canvasSize
        ))
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, 800, accuracy: 0.001)

        let bottomRight = try XCTUnwrap(CanvasGeometry.pdfPoint(
            for: CGPoint(x: 950, y: 1_200),
            pageSize: pageSize,
            canvasSize: canvasSize
        ))
        XCTAssertEqual(bottomRight.x, 600, accuracy: 0.001)
        XCTAssertEqual(bottomRight.y, 0, accuracy: 0.001)

        XCTAssertNil(CanvasGeometry.pdfPoint(
            for: CGPoint(x: 20, y: 600),
            pageSize: pageSize,
            canvasSize: canvasSize
        ))
    }

    func testPDFDrawingGeometryUpscalesBeyondOriginalSize() {
        let sourceSize = CGSize(width: 600, height: 800)
        let target = CGRect(x: 10, y: 20, width: 900, height: 1200)

        XCTAssertEqual(
            PDFDrawingGeometry.fittedRect(sourceSize: sourceSize, in: target),
            target
        )
    }

    func testPDFDrawingGeometryPreservesAspectRatioAndCenters() {
        let sourceSize = CGSize(width: 600, height: 800)
        let target = CGRect(x: 10, y: 20, width: 1000, height: 1000)

        XCTAssertEqual(
            PDFDrawingGeometry.fittedRect(sourceSize: sourceSize, in: target),
            CGRect(x: 135, y: 20, width: 750, height: 1000)
        )
    }

    func testExporterKeepsPageCountAndSize() throws {
        let sourceURL = temporaryPDFURL(named: "source")
        let signatureURL = temporaryPDFURL(named: "signature")
        let outputURL = temporaryPDFURL(named: "output")
        defer { removeTemporaryFiles([sourceURL, signatureURL, outputURL]) }

        try makeSourcePDF(at: sourceURL, pageCount: 3, pageSize: CGSize(width: 595, height: 842))
        try makeVectorSignaturePDF(at: signatureURL)

        let source = try XCTUnwrap(PDFDocument(url: sourceURL))
        let signatureDocument = try XCTUnwrap(PDFDocument(url: signatureURL))
        let asset = try XCTUnwrap(SignatureAsset(
            name: "signature",
            url: signatureURL,
            document: signatureDocument
        ))
        let placement = SignaturePlacement(
            assetID: asset.id,
            pageIndex: 0,
            rect: CGRect(x: 100, y: 100, width: 150, height: 46.8)
        )

        try PDFExporter.export(
            document: source,
            placements: [placement],
            assets: [asset],
            to: outputURL
        )

        let exported = try XCTUnwrap(PDFDocument(url: outputURL))
        XCTAssertEqual(exported.pageCount, 3)
        XCTAssertEqual(exported.page(at: 0)?.bounds(for: .mediaBox).size.width ?? 0, 595, accuracy: 0.01)
        XCTAssertEqual(exported.page(at: 0)?.bounds(for: .mediaBox).size.height ?? 0, 842, accuracy: 0.01)
        XCTAssertGreaterThan(fileSize(at: outputURL), 1_000)
    }

    func testExporterDrawsSignatureOnlyOnItsAssignedPage() throws {
        let sourceURL = temporaryPDFURL(named: "page-target-source")
        let signatureURL = temporaryPDFURL(named: "page-target-signature")
        let outputURL = temporaryPDFURL(named: "page-target-output")
        defer { removeTemporaryFiles([sourceURL, signatureURL, outputURL]) }

        try makeSourcePDF(at: sourceURL, pageCount: 2, pageSize: CGSize(width: 595, height: 842))
        try makeVectorSignaturePDF(at: signatureURL)

        let source = try XCTUnwrap(PDFDocument(url: sourceURL))
        let signatureDocument = try XCTUnwrap(PDFDocument(url: signatureURL))
        let asset = try XCTUnwrap(SignatureAsset(
            name: "signature",
            url: signatureURL,
            document: signatureDocument
        ))
        let placement = SignaturePlacement(
            assetID: asset.id,
            pageIndex: 1,
            rect: CGRect(x: 100, y: 100, width: 180, height: 56.16)
        )

        try PDFExporter.export(
            document: source,
            placements: [placement],
            assets: [asset],
            to: outputURL
        )

        let exported = try XCTUnwrap(PDFDocument(url: outputURL))
        let firstPage = try XCTUnwrap(exported.page(at: 0))
        let secondPage = try XCTUnwrap(exported.page(at: 1))
        XCTAssertGreaterThan(darkPixelCount(in: secondPage), darkPixelCount(in: firstPage) + 20)
    }

    func testExporterFlattensAnnotationAppearanceIntoVisiblePage() throws {
        let sourceURL = temporaryPDFURL(named: "annotation-source")
        let outputURL = temporaryPDFURL(named: "annotation-output")
        defer { removeTemporaryFiles([sourceURL, outputURL]) }

        try makeSourcePDF(at: sourceURL, pageCount: 1, pageSize: CGSize(width: 300, height: 200))

        let source = try XCTUnwrap(PDFDocument(url: sourceURL))
        let page = try XCTUnwrap(source.page(at: 0))
        let annotation = PDFAnnotation(
            bounds: CGRect(x: 40, y: 80, width: 220, height: 40),
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = "ANNOTATION_VISIBLE_12345"
        annotation.font = NSFont.systemFont(ofSize: 14)
        annotation.fontColor = .black
        annotation.color = .clear
        page.addAnnotation(annotation)

        try PDFExporter.export(document: source, placements: [], assets: [], to: outputURL)

        let exported = try XCTUnwrap(PDFDocument(url: outputURL))
        let exportedPage = try XCTUnwrap(exported.page(at: 0))
        XCTAssertTrue(exportedPage.annotations.isEmpty)
        XCTAssertGreaterThan(darkPixelCount(in: exportedPage), 20)
    }

    @MainActor
    func testSignatureLibraryPersistsAndDeletesImportedSignature() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignPDF-library-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = temporaryPDFURL(named: "persistent-signature")
        let documentURL = temporaryPDFURL(named: "document")
        let outputURL = temporaryPDFURL(named: "detached-output")
        defer { removeTemporaryFiles([rootURL, sourceURL, documentURL, outputURL]) }

        try makeVectorSignaturePDF(at: sourceURL)
        try makeSourcePDF(at: documentURL, pageCount: 1, pageSize: CGSize(width: 300, height: 200))
        let library = SignatureLibrary(rootURL: rootURL)
        let firstModel = DocumentModel(signatureLibrary: library)
        let expectedName = sourceURL.deletingPathExtension().lastPathComponent

        firstModel.importSignatures(urls: [sourceURL, sourceURL])

        let imported = try XCTUnwrap(firstModel.assets.first)
        XCTAssertEqual(firstModel.assets.count, 1)
        XCTAssertEqual(imported.name, expectedName)
        XCTAssertNotEqual(imported.url.standardizedFileURL, sourceURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.url.path))

        try FileManager.default.removeItem(at: sourceURL)

        let restoredModel = DocumentModel(signatureLibrary: library)
        let restored = try XCTUnwrap(restoredModel.assets.first)
        XCTAssertEqual(restoredModel.assets.count, 1)
        XCTAssertEqual(restored.id, imported.id)
        XCTAssertEqual(restored.name, imported.name)
        XCTAssertNotNil(restored.document.page(at: 0))

        restoredModel.open(url: documentURL)
        restoredModel.addSignature(restored)
        XCTAssertEqual(restoredModel.placements.count, 1)
        XCTAssertNotNil(restoredModel.selectedPlacementID)

        restoredModel.deleteAsset(restored)
        XCTAssertTrue(restoredModel.libraryAssets.isEmpty)
        XCTAssertEqual(restoredModel.assets.count, 1)
        XCTAssertEqual(restoredModel.placements.count, 1)
        XCTAssertNotNil(restoredModel.selectedPlacementID)
        XCTAssertNotNil(restoredModel.asset(for: restoredModel.placements[0]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.url.deletingLastPathComponent().path))

        try PDFExporter.export(
            document: restoredModel.document,
            placements: restoredModel.placements,
            assets: restoredModel.assets,
            to: outputURL
        )
        XCTAssertGreaterThan(fileSize(at: outputURL), 1_000)
        let exportedDocument = try XCTUnwrap(PDFDocument(url: outputURL))
        let exportedPage = try XCTUnwrap(exportedDocument.page(at: 0))
        let unsignedPage = try XCTUnwrap(restoredModel.document?.page(at: 0))
        XCTAssertGreaterThan(
            darkPixelCount(in: exportedPage),
            darkPixelCount(in: unsignedPage) + 20
        )

        let reloadedModel = DocumentModel(signatureLibrary: library)
        XCTAssertTrue(reloadedModel.libraryAssets.isEmpty)

        restoredModel.deleteSelected()
        XCTAssertTrue(restoredModel.placements.isEmpty)
        XCTAssertTrue(restoredModel.assets.isEmpty)
    }

    @MainActor
    func testSignatureLibraryRejectsMultipagePDF() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignPDF-library-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = temporaryPDFURL(named: "multipage-signature")
        defer { removeTemporaryFiles([rootURL, sourceURL]) }

        try makeSourcePDF(at: sourceURL, pageCount: 2, pageSize: CGSize(width: 500, height: 156))
        let model = DocumentModel(signatureLibrary: SignatureLibrary(rootURL: rootURL))

        model.importSignatures(urls: [sourceURL])

        XCTAssertTrue(model.assets.isEmpty)
        XCTAssertTrue(model.alertMessage?.contains("必须只有一页") == true)
    }

    func testSignatureLibraryIsolatesCorruptItemsWithoutHidingValidSignatures() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignPDF-library-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = temporaryPDFURL(named: "valid-signature")
        defer { removeTemporaryFiles([rootURL, sourceURL]) }

        try makeVectorSignaturePDF(at: sourceURL)
        let library = SignatureLibrary(rootURL: rootURL)
        _ = try library.importSignature(from: sourceURL, name: "Valid")

        let corruptID = UUID()
        let corruptURL = rootURL.appendingPathComponent(corruptID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: corruptURL, withIntermediateDirectories: false)
        try Data("not-json".utf8).write(
            to: corruptURL.appendingPathComponent("metadata.json"),
            options: .atomic
        )
        try FileManager.default.copyItem(
            at: sourceURL,
            to: corruptURL.appendingPathComponent("signature.pdf")
        )

        let firstLoad = try library.load()
        XCTAssertEqual(firstLoad.assets.count, 1)
        XCTAssertEqual(firstLoad.skippedItemCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))

        let secondLoad = try library.load()
        XCTAssertEqual(secondLoad.assets.count, 1)
        XCTAssertEqual(secondLoad.skippedItemCount, 0)
    }

    @MainActor
    func testSignaturePlacementModeIsOneShotAndPreservesAspectRatioAtPageEdges() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignPDF-library-\(UUID().uuidString)", isDirectory: true)
        let documentURL = temporaryPDFURL(named: "placement-document")
        let signatureURL = temporaryPDFURL(named: "placement-signature")
        let tallSignatureURL = temporaryPDFURL(named: "tall-signature")
        defer { removeTemporaryFiles([rootURL, documentURL, signatureURL, tallSignatureURL]) }

        try makeSourcePDF(at: documentURL, pageCount: 1, pageSize: CGSize(width: 600, height: 800))
        try makeVectorSignaturePDF(at: signatureURL)
        try makeSourcePDF(at: tallSignatureURL, pageCount: 1, pageSize: CGSize(width: 100, height: 1_000))

        let model = DocumentModel(signatureLibrary: SignatureLibrary(rootURL: rootURL))
        model.open(url: documentURL)
        model.importSignatures(urls: [signatureURL])
        let asset = try XCTUnwrap(model.libraryAssets.first)

        model.beginPlacingSignature(asset)
        XCTAssertEqual(model.pendingSignatureAssetID, asset.id)
        XCTAssertTrue(model.placements.isEmpty)

        let proposed = model.proposedSignatureRect(
            for: asset,
            centeredAt: CGPoint(x: 595, y: 5)
        )
        model.placePendingSignature(at: CGPoint(x: 595, y: 5))

        XCTAssertEqual(model.placements.count, 1)
        XCTAssertEqual(model.placements[0].rect, proposed)
        XCTAssertEqual(model.placements[0].rect.maxX, 600, accuracy: 0.001)
        XCTAssertEqual(model.placements[0].rect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(
            model.placements[0].rect.width / model.placements[0].rect.height,
            asset.aspectRatio,
            accuracy: 0.001
        )
        XCTAssertNil(model.pendingSignatureAssetID)
        XCTAssertEqual(model.selectedPlacementID, model.placements[0].id)

        model.beginPlacingSignature(asset)
        model.cancelSignaturePlacement()
        XCTAssertEqual(model.placements.count, 1)
        XCTAssertNil(model.pendingSignatureAssetID)

        let tallDocument = try XCTUnwrap(PDFDocument(url: tallSignatureURL))
        let tallAsset = try XCTUnwrap(SignatureAsset(
            name: "Tall",
            url: tallSignatureURL,
            document: tallDocument
        ))
        let tallRect = model.proposedSignatureRect(
            for: tallAsset,
            centeredAt: CGPoint(x: 300, y: 400)
        )
        XCTAssertLessThanOrEqual(tallRect.height, 800 * 0.35 + 0.001)
        XCTAssertEqual(tallRect.width / tallRect.height, tallAsset.aspectRatio, accuracy: 0.001)

        model.beginPlacingSignature(asset)
        model.addSignature(asset)
        XCTAssertEqual(model.placements.count, 2)
        XCTAssertNil(model.pendingSignatureAssetID)
    }

    @MainActor
    func testContinuousNavigationAndExplicitPagePlacementUseIndependentPageState() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignPDF-continuous-\(UUID().uuidString)", isDirectory: true)
        let documentURL = temporaryPDFURL(named: "continuous-document")
        let signatureURL = temporaryPDFURL(named: "continuous-signature")
        defer { removeTemporaryFiles([rootURL, documentURL, signatureURL]) }

        try makeSourcePDF(
            at: documentURL,
            pageSizes: [CGSize(width: 600, height: 800), CGSize(width: 240, height: 300)]
        )
        try makeVectorSignaturePDF(at: signatureURL)

        let model = DocumentModel(signatureLibrary: SignatureLibrary(rootURL: rootURL))
        model.open(url: documentURL)
        model.importSignatures(urls: [signatureURL])
        let asset = try XCTUnwrap(model.libraryAssets.first)

        XCTAssertEqual(model.pageSize(at: 0), CGSize(width: 600, height: 800))
        XCTAssertEqual(model.pageSize(at: 1), CGSize(width: 240, height: 300))
        XCTAssertEqual(model.maximumPageWidth, 600)

        model.beginPlacingSignature(asset)
        let pendingAssetID = model.pendingSignatureAssetID
        model.requestPageNavigation(to: 1)
        let firstRequestID = try XCTUnwrap(model.pageNavigationRequest?.id)
        model.requestPageNavigation(to: 1)
        let secondRequest = try XCTUnwrap(model.pageNavigationRequest)

        XCTAssertNotEqual(firstRequestID, secondRequest.id)
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.pendingSignatureAssetID, pendingAssetID)

        model.updateCurrentPageFromViewport(0)
        XCTAssertEqual(model.currentPage, 0)
        XCTAssertEqual(model.pageNavigationRequest, secondRequest)
        XCTAssertEqual(model.pendingSignatureAssetID, pendingAssetID)

        model.placePendingSignature(at: CGPoint(x: 235, y: 5), onPage: 1)
        let placement = try XCTUnwrap(model.placements.first)
        XCTAssertEqual(placement.pageIndex, 1)
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertNil(model.pendingSignatureAssetID)
        XCTAssertEqual(placement.rect.maxX, 240, accuracy: 0.001)
        XCTAssertEqual(placement.rect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(
            placement.rect.width / placement.rect.height,
            asset.aspectRatio,
            accuracy: 0.001
        )
    }

    @MainActor
    func testUnsavedChangesFollowTheEffectiveSignatureLayout() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignPDF-library-\(UUID().uuidString)", isDirectory: true)
        let documentURL = temporaryPDFURL(named: "dirty-state-document")
        let signatureURL = temporaryPDFURL(named: "dirty-state-signature")
        defer { removeTemporaryFiles([rootURL, documentURL, signatureURL]) }

        try makeSourcePDF(at: documentURL, pageCount: 1, pageSize: CGSize(width: 600, height: 800))
        try makeVectorSignaturePDF(at: signatureURL)

        let model = DocumentModel(signatureLibrary: SignatureLibrary(rootURL: rootURL))
        model.open(url: documentURL)
        model.importSignatures(urls: [signatureURL])
        let asset = try XCTUnwrap(model.libraryAssets.first)

        XCTAssertFalse(model.hasUnsavedChanges)

        model.addSignature(asset, centeredAt: CGPoint(x: 300, y: 400))
        XCTAssertTrue(model.hasUnsavedChanges)

        model.markCurrentSignatureLayoutAsHandled()
        XCTAssertFalse(model.hasUnsavedChanges)
        let handledRect = model.placements[0].rect

        model.placements[0].rect.origin.x += 10
        XCTAssertTrue(model.hasUnsavedChanges)
        model.placements[0].rect = handledRect
        XCTAssertFalse(model.hasUnsavedChanges)

        model.addSignature(asset, centeredAt: CGPoint(x: 100, y: 100))
        XCTAssertTrue(model.hasUnsavedChanges)
        model.deletePlacement(id: model.placements[1].id)
        XCTAssertFalse(model.hasUnsavedChanges)

        model.deletePlacement(id: model.placements[0].id)
        XCTAssertTrue(model.hasUnsavedChanges)
        model.addSignature(
            asset,
            centeredAt: CGPoint(x: handledRect.midX, y: handledRect.midY)
        )
        XCTAssertFalse(model.hasUnsavedChanges)

        model.open(url: documentURL)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    private func makeSourcePDF(at url: URL, pageCount: Int, pageSize: CGSize) throws {
        try makeSourcePDF(at: url, pageSizes: Array(repeating: pageSize, count: pageCount))
    }

    private func makeSourcePDF(at url: URL, pageSizes: [CGSize]) throws {
        let firstPageSize = try XCTUnwrap(pageSizes.first)
        var defaultMediaBox = CGRect(origin: .zero, size: firstPageSize)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &defaultMediaBox, nil))

        for (pageIndex, pageSize) in pageSizes.enumerated() {
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            let pageInfo = [
                kCGPDFContextMediaBox as String: NSData(
                    bytes: &mediaBox,
                    length: MemoryLayout<CGRect>.size
                )
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
            context.setLineWidth(2)
            context.move(to: CGPoint(x: 48, y: pageSize.height - 72 - CGFloat(pageIndex * 4)))
            context.addLine(to: CGPoint(x: pageSize.width - 48, y: pageSize.height - 72 - CGFloat(pageIndex * 4)))
            context.strokePath()
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func makeVectorSignaturePDF(at url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 500, height: 156)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))

        context.beginPDFPage(nil)
        context.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
        context.setLineWidth(7)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 45, y: 38))
        context.addCurve(
            to: CGPoint(x: 240, y: 95),
            control1: CGPoint(x: 120, y: 145),
            control2: CGPoint(x: 145, y: 5)
        )
        context.addCurve(
            to: CGPoint(x: 450, y: 75),
            control1: CGPoint(x: 290, y: 135),
            control2: CGPoint(x: 340, y: 38)
        )
        context.strokePath()
        context.endPDFPage()
        context.closePDF()
    }

    private func darkPixelCount(in page: PDFPage) -> Int {
        let thumbnail = page.thumbnail(of: CGSize(width: 300, height: 200), for: .mediaBox)
        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return 0 }
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5 && color.brightnessComponent < 0.7 {
                    count += 1
                }
            }
        }
        return count
    }

    private func temporaryPDFURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SignPDF-\(name)-\(UUID().uuidString).pdf")
    }

    private func removeTemporaryFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func fileSize(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }
}
