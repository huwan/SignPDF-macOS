import CoreGraphics
import Foundation
import PDFKit

enum PDFExporter {
    static func export(
        document: PDFDocument?,
        placements: [SignaturePlacement],
        assets: [SignatureAsset],
        to destination: URL
    ) throws {
        guard let document else { throw SignPDFError.cannotCreateOutput }
        guard let consumer = CGDataConsumer(url: destination as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw SignPDFError.cannotCreateOutput
        }

        let assetMap = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let sourceBounds = page.bounds(for: .mediaBox)
            var outputBox = CGRect(origin: .zero, size: sourceBounds.size)
            let pageInfo = [kCGPDFContextMediaBox as String: NSData(bytes: &outputBox, length: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)

            draw(page, in: outputBox, context: context)

            for placement in placements where placement.pageIndex == pageIndex {
                guard let signaturePage = assetMap[placement.assetID]?.page else { continue }
                draw(signaturePage, in: placement.rect, context: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func draw(_ page: PDFPage, in rect: CGRect, context: CGContext) {
        guard let pageRef = page.pageRef else { return }
        let sourceSize = page.bounds(for: .mediaBox).size
        let fittedRect = PDFDrawingGeometry.fittedRect(sourceSize: sourceSize, in: rect)
        guard sourceSize.width > 0, sourceSize.height > 0,
              fittedRect.width > 0, fittedRect.height > 0 else { return }

        context.saveGState()
        context.translateBy(x: fittedRect.minX, y: fittedRect.minY)
        context.scaleBy(
            x: fittedRect.width / sourceSize.width,
            y: fittedRect.height / sourceSize.height
        )
        let normalizationTransform = pageRef.getDrawingTransform(
            .mediaBox,
            rect: CGRect(origin: .zero, size: sourceSize),
            rotate: 0,
            preserveAspectRatio: true
        )
        context.concatenate(normalizationTransform)

        // CGPDFPage draws the page content and obeys the manual scale above.
        // PDFPage.draw cannot be used here because it refuses to upscale and
        // instead centers the page at its original size inside a larger rect.
        context.drawPDFPage(pageRef)

        // Annotations and AcroForm appearances are a separate PDF layer.
        // Draw them through PDFKit using exactly the same transform so filled
        // text remains visible and aligned at every preview zoom level.
        for annotation in page.annotations {
            annotation.draw(with: .mediaBox, in: context)
        }
        context.restoreGState()
    }
}

enum PDFDrawingGeometry {
    static func fittedRect(sourceSize: CGSize, in targetRect: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0,
              targetRect.width > 0, targetRect.height > 0 else { return .zero }
        let scale = min(targetRect.width / sourceSize.width, targetRect.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: targetRect.midX - size.width / 2,
            y: targetRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
