import AppKit
import PDFKit
import SwiftUI

struct PDFPageVectorPreview: NSViewRepresentable {
    let page: PDFPage

    func makeNSView(context: Context) -> PDFPageVectorPreviewView {
        PDFPageVectorPreviewView(page: page)
    }

    func updateNSView(_ view: PDFPageVectorPreviewView, context: Context) {
        view.page = page
        view.needsDisplay = true
    }
}

final class PDFPageVectorPreviewView: NSView {
    var page: PDFPage

    init(page: PDFPage) {
        self.page = page
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.white.setFill()
        bounds.fill()

        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        PDFExporter.draw(page, in: bounds, context: context)
        context.restoreGState()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = frame.size != newSize
        super.setFrameSize(newSize)
        if sizeChanged {
            needsDisplay = true
        }
    }
}
