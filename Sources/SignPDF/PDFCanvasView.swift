import AppKit
import PDFKit
import SwiftUI

struct PDFCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var model: DocumentModel

    func makeNSView(context: Context) -> PDFCanvasView {
        PDFCanvasView(model: model)
    }

    func updateNSView(_ view: PDFCanvasView, context: Context) {
        view.model = model
        view.needsDisplay = true
    }
}

final class PDFCanvasView: NSView {
    var model: DocumentModel
    private var dragStart: CGPoint?
    private var originalPlacement: SignaturePlacement?
    private var isResizing = false

    init(model: DocumentModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = frame.size != newSize
        super.setFrameSize(newSize)
        if sizeChanged {
            needsDisplay = true
        }
    }

    override func setBoundsSize(_ newSize: NSSize) {
        let sizeChanged = bounds.size != newSize
        super.setBoundsSize(newSize)
        if sizeChanged {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext,
              let page = model.currentPDFPage else { return }

        NSColor.white.setFill()
        bounds.fill()

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        PDFExporter.draw(page, in: bounds, context: context)

        for placement in currentPlacements {
            guard let asset = model.asset(for: placement) else { continue }
            let target = CanvasGeometry.drawingRect(
                for: placement.rect,
                pageSize: model.currentPageSize,
                canvasSize: bounds.size
            )
            PDFExporter.draw(asset.page, in: target, context: context)
        }
        context.restoreGState()

        if let selected = selectedPlacement {
            drawSelection(visualRect(for: selected))
        }
    }

    private var currentPlacements: [SignaturePlacement] {
        model.placements.filter { $0.pageIndex == model.currentPage }
    }

    private var selectedPlacement: SignaturePlacement? {
        currentPlacements.first { $0.id == model.selectedPlacementID }
    }

    private func visualRect(for placement: SignaturePlacement) -> CGRect {
        CanvasGeometry.visualRect(
            for: placement.rect,
            pageSize: model.currentPageSize,
            canvasSize: bounds.size
        )
    }

    private func drawSelection(_ rect: CGRect) {
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
        path.lineWidth = 2
        path.stroke()

        let handle = CGRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 10, height: 10)
        NSColor.white.setFill()
        handle.fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: handle).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if let selected = selectedPlacement {
            let rect = visualRect(for: selected)
            let handle = CGRect(x: rect.maxX - 10, y: rect.maxY - 10, width: 20, height: 20)
            if handle.contains(point) {
                beginDrag(point, placement: selected, resizing: true)
                return
            }
        }

        if let hit = currentPlacements.reversed().first(where: { visualRect(for: $0).contains(point) }) {
            model.selectedPlacementID = hit.id
            beginDrag(point, placement: hit, resizing: false)
        } else {
            model.selectedPlacementID = nil
            needsDisplay = true
        }
    }

    private func beginDrag(_ point: CGPoint, placement: SignaturePlacement, resizing: Bool) {
        dragStart = point
        originalPlacement = placement
        isResizing = resizing
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let original = originalPlacement,
              let index = model.placements.firstIndex(where: { $0.id == original.id }) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let scale = CanvasGeometry.scale(pageSize: model.currentPageSize, canvasSize: bounds.size)
        let dx = (point.x - start.x) / scale
        let dy = (point.y - start.y) / scale
        var updated = original

        if isResizing, let asset = model.asset(for: original) {
            let newWidth = max(24, original.rect.width + dx)
            let newHeight = newWidth / asset.aspectRatio
            let top = original.rect.maxY
            updated.rect.size = CGSize(width: newWidth, height: newHeight)
            updated.rect.origin.y = top - newHeight
        } else {
            updated.rect.origin.x += dx
            updated.rect.origin.y -= dy
        }

        updated.rect = PlacementGeometry.clamped(updated.rect, to: model.currentPageSize)
        model.placements[index] = updated
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        resetDrag()
    }

    private func resetDrag() {
        dragStart = nil
        originalPlacement = nil
        isResizing = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = currentPlacements.reversed().first(where: { visualRect(for: $0).contains(point) }) else {
            return nil
        }
        model.selectedPlacementID = hit.id
        needsDisplay = true
        let menu = NSMenu()
        let item = NSMenuItem(title: "删除签名", action: #selector(deleteSelectedFromMenu), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除签名")
        menu.addItem(item)
        return menu
    }

    @objc private func deleteSelectedFromMenu() {
        model.deleteSelected()
        resetDrag()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard let id = model.selectedPlacementID,
              let index = model.placements.firstIndex(where: { $0.id == id }) else {
            super.keyDown(with: event)
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        var rect = model.placements[index].rect
        switch event.keyCode {
        case 123: rect.origin.x -= step
        case 124: rect.origin.x += step
        case 125: rect.origin.y -= step
        case 126: rect.origin.y += step
        default:
            super.keyDown(with: event)
            return
        }
        model.placements[index].rect = PlacementGeometry.clamped(rect, to: model.currentPageSize)
        needsDisplay = true
    }
}

enum PlacementGeometry {
    static func clamped(_ rect: CGRect, to pageSize: CGSize) -> CGRect {
        var result = rect
        result.size.width = min(max(1, result.width), pageSize.width)
        result.size.height = min(max(1, result.height), pageSize.height)
        result.origin.x = min(max(0, result.minX), pageSize.width - result.width)
        result.origin.y = min(max(0, result.minY), pageSize.height - result.height)
        return result
    }
}

enum CanvasGeometry {
    static func scale(pageSize: CGSize, canvasSize: CGSize) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0,
              canvasSize.width > 0, canvasSize.height > 0 else { return 1 }
        return min(canvasSize.width / pageSize.width, canvasSize.height / pageSize.height)
    }

    static func drawingRect(for pdfRect: CGRect, pageSize: CGSize, canvasSize: CGSize) -> CGRect {
        let scale = scale(pageSize: pageSize, canvasSize: canvasSize)
        let drawnPageSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let offset = CGPoint(
            x: (canvasSize.width - drawnPageSize.width) / 2,
            y: (canvasSize.height - drawnPageSize.height) / 2
        )
        return CGRect(
            x: offset.x + pdfRect.minX * scale,
            y: offset.y + pdfRect.minY * scale,
            width: pdfRect.width * scale,
            height: pdfRect.height * scale
        )
    }

    static func visualRect(for pdfRect: CGRect, pageSize: CGSize, canvasSize: CGSize) -> CGRect {
        let drawingRect = drawingRect(for: pdfRect, pageSize: pageSize, canvasSize: canvasSize)
        return CGRect(
            x: drawingRect.minX,
            y: canvasSize.height - drawingRect.maxY,
            width: drawingRect.width,
            height: drawingRect.height
        )
    }
}
