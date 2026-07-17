import AppKit
import PDFKit
import SwiftUI

struct PDFCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var model: DocumentModel
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFCanvasView {
        PDFCanvasView(model: model, pageIndex: pageIndex)
    }

    func updateNSView(_ view: PDFCanvasView, context: Context) {
        view.model = model
        view.pageIndex = pageIndex
        view.synchronizeInteractionState()
        view.needsDisplay = true
    }
}

final class PDFCanvasView: NSView {
    var model: DocumentModel
    var pageIndex: Int {
        didSet {
            guard pageIndex != oldValue else { return }
            resetDrag()
            hoverPoint = nil
            needsDisplay = true
        }
    }
    private var dragStart: CGPoint?
    private var originalPlacement: SignaturePlacement?
    private var isResizing = false
    private var hoverPoint: CGPoint?
    private var mouseTrackingArea: NSTrackingArea?
    private var lastPendingSignatureAssetID: UUID?

    private static let signaturePlacementCursor: NSCursor = {
        let size = NSSize(width: 36, height: 34)
        let image = NSImage(size: size, flipped: false) { _ in
            NSCursor.arrow.image.draw(
                in: NSRect(x: 0, y: 15, width: 19, height: 19),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let signature = NSImage(
                systemSymbolName: "signature",
                accessibilityDescription: "放置签名"
            )?.withSymbolConfiguration(configuration) {
                signature.draw(
                    in: NSRect(x: 13, y: 0, width: 22, height: 17),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: 2))
    }()

    init(model: DocumentModel, pageIndex: Int) {
        self.model = model
        self.pageIndex = pageIndex
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        mouseTrackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(
            bounds,
            cursor: model.pendingSignatureAssetID == nil ? .arrow : Self.signaturePlacementCursor
        )
    }

    func synchronizeInteractionState() {
        let pendingID = model.pendingSignatureAssetID
        guard lastPendingSignatureAssetID != pendingID else { return }
        lastPendingSignatureAssetID = pendingID
        hoverPoint = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

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
              let page else { return }

        NSColor.white.setFill()
        bounds.fill()

        let preview = pendingSignaturePreview

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        PDFExporter.draw(page, in: bounds, context: context)

        for placement in currentPlacements {
            guard let asset = model.asset(for: placement) else { continue }
            let target = CanvasGeometry.drawingRect(
                for: placement.rect,
                pageSize: pageSize,
                canvasSize: bounds.size
            )
            PDFExporter.draw(asset.page, in: target, context: context)
        }

        if let preview {
            let target = CanvasGeometry.drawingRect(
                for: preview.rect,
                pageSize: pageSize,
                canvasSize: bounds.size
            )
            context.saveGState()
            context.setAlpha(0.55)
            PDFExporter.draw(preview.asset.page, in: target, context: context)
            context.restoreGState()
        }
        context.restoreGState()

        if let selected = selectedPlacement {
            let rect = visualRect(for: selected)
            drawSelection(rect)
            if isResizing {
                drawResizeMeasurement(widthPoints: selected.rect.width, near: rect)
            }
        }
        if let preview {
            drawPlacementPreview(
                CanvasGeometry.visualRect(
                    for: preview.rect,
                    pageSize: pageSize,
                    canvasSize: bounds.size
                )
            )
        }
    }

    private var currentPlacements: [SignaturePlacement] {
        model.placements.filter { $0.pageIndex == pageIndex }
    }

    private var page: PDFPage? {
        model.pdfPage(at: pageIndex)
    }

    private var pageSize: CGSize {
        model.pageSize(at: pageIndex)
    }

    private var selectedPlacement: SignaturePlacement? {
        currentPlacements.first { $0.id == model.selectedPlacementID }
    }

    private var pendingSignaturePreview: (asset: SignatureAsset, rect: CGRect)? {
        guard let asset = model.pendingSignatureAsset,
              let hoverPoint,
              let pagePoint = CanvasGeometry.pdfPoint(
                for: hoverPoint,
                pageSize: pageSize,
                canvasSize: bounds.size
              ) else { return nil }
        return (
            asset,
            model.proposedSignatureRect(for: asset, centeredAt: pagePoint, onPage: pageIndex)
        )
    }

    private func visualRect(for placement: SignaturePlacement) -> CGRect {
        CanvasGeometry.visualRect(
            for: placement.rect,
            pageSize: pageSize,
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

    private func drawPlacementPreview(_ rect: CGRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 3, yRadius: 3)
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()
    }

    private func drawResizeMeasurement(widthPoints: CGFloat, near rect: CGRect) {
        let text = ResizeMeasurement.widthText(points: widthPoints)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 5
        let bubbleSize = CGSize(
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )
        let margin: CGFloat = 6
        var bubble = CGRect(
            x: rect.maxX - bubbleSize.width,
            y: rect.maxY + 10,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        if bubble.maxY > bounds.maxY - margin {
            bubble.origin.y = rect.maxY - bubble.height - 10
        }
        bubble.origin.x = min(
            max(bounds.minX + margin, bubble.minX),
            max(bounds.minX + margin, bounds.maxX - bubble.width - margin)
        )
        bubble.origin.y = min(
            max(bounds.minY + margin, bubble.minY),
            max(bounds.minY + margin, bounds.maxY - bubble.height - margin)
        )

        NSColor.labelColor.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 5, yRadius: 5).fill()
        attributedText.draw(
            at: CGPoint(
                x: bubble.minX + horizontalPadding,
                y: bubble.minY + verticalPadding
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverPoint(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverPoint(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard hoverPoint != nil else { return }
        hoverPoint = nil
        needsDisplay = true
    }

    private func updateHoverPoint(with event: NSEvent) {
        guard model.pendingSignatureAssetID != nil else {
            hoverPoint = nil
            return
        }
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        model.updateCurrentPageFromViewport(pageIndex)
        let point = convert(event.locationInWindow, from: nil)

        if model.pendingSignatureAssetID != nil {
            if event.modifierFlags.contains(.control) {
                cancelSignaturePlacement()
                return
            }
            guard let pagePoint = CanvasGeometry.pdfPoint(
                for: point,
                pageSize: pageSize,
                canvasSize: bounds.size
            ) else { return }
            model.placePendingSignature(at: pagePoint, onPage: pageIndex)
            hoverPoint = nil
            synchronizeInteractionState()
            needsDisplay = true
            return
        }

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
        let scale = CanvasGeometry.scale(pageSize: pageSize, canvasSize: bounds.size)
        let dx = (point.x - start.x) / scale
        let dy = (point.y - start.y) / scale
        var updated = original

        if isResizing, let asset = model.asset(for: original) {
            let newWidth = min(
                SignatureSizing.maximumWidthPoints,
                max(SignatureSizing.minimumWidthPoints, original.rect.width + dx)
            )
            guard let resized = PlacementGeometry.resizedSignatureRect(
                original.rect,
                requestedWidth: newWidth,
                aspectRatio: asset.aspectRatio,
                pageSize: pageSize
            ) else { return }
            updated.rect = resized
        } else {
            updated.rect.origin.x += dx
            updated.rect.origin.y -= dy
            updated.rect = PlacementGeometry.clamped(updated.rect, to: pageSize)
        }

        model.placements[index] = updated
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        resetDrag()
    }

    override func rightMouseDown(with event: NSEvent) {
        if model.pendingSignatureAssetID != nil {
            cancelSignaturePlacement()
            return
        }
        super.rightMouseDown(with: event)
    }

    private func resetDrag() {
        dragStart = nil
        originalPlacement = nil
        isResizing = false
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if model.pendingSignatureAssetID != nil {
            cancelSignaturePlacement()
            return nil
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = currentPlacements.reversed().first(where: { visualRect(for: $0).contains(point) }) else {
            return nil
        }
        model.updateCurrentPageFromViewport(pageIndex)
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
        if event.keyCode == 53, model.pendingSignatureAssetID != nil {
            cancelSignaturePlacement()
            return
        }
        guard let id = model.selectedPlacementID,
              let index = model.placements.firstIndex(where: { $0.id == id }),
              model.placements[index].pageIndex == pageIndex else {
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
        model.placements[index].rect = PlacementGeometry.clamped(rect, to: pageSize)
        needsDisplay = true
    }

    override func cancelOperation(_ sender: Any?) {
        if model.pendingSignatureAssetID != nil {
            cancelSignaturePlacement()
        } else {
            super.cancelOperation(sender)
        }
    }

    private func cancelSignaturePlacement() {
        model.cancelSignaturePlacement()
        hoverPoint = nil
        synchronizeInteractionState()
        needsDisplay = true
    }
}

enum ResizeMeasurement {
    static func widthText(points: CGFloat, locale: Locale = .current) -> String {
        let centimeters = SignatureSizing.centimeters(fromPoints: points)
        return "\(SignatureWidthText.string(from: centimeters, locale: locale)) cm"
    }
}

enum PlacementGeometry {
    static func maximumSignatureWidth(
        aspectRatio: CGFloat,
        pageSize: CGSize
    ) -> CGFloat? {
        guard aspectRatio.isFinite, aspectRatio > 0,
              pageSize.width.isFinite, pageSize.width > 0,
              pageSize.height.isFinite, pageSize.height > 0 else { return nil }
        let heightLimitedWidth = pageSize.height * aspectRatio
        let maximumWidth = heightLimitedWidth.isFinite
            ? min(pageSize.width, heightLimitedWidth)
            : pageSize.width
        return maximumWidth.isFinite && maximumWidth > 0 ? maximumWidth : nil
    }

    static func signatureSize(
        requestedWidth: CGFloat,
        aspectRatio: CGFloat,
        pageSize: CGSize
    ) -> CGSize? {
        guard requestedWidth.isFinite, requestedWidth > 0,
              let maximumWidth = maximumSignatureWidth(
                aspectRatio: aspectRatio,
                pageSize: pageSize
              ) else { return nil }
        let width = min(requestedWidth, maximumWidth)
        let height = width / aspectRatio
        guard width.isFinite, width > 0,
              height.isFinite, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    static func signatureRect(
        centeredAt point: CGPoint,
        requestedWidth: CGFloat,
        aspectRatio: CGFloat,
        pageSize: CGSize
    ) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite,
              let size = signatureSize(
                requestedWidth: requestedWidth,
                aspectRatio: aspectRatio,
                pageSize: pageSize
              ) else { return nil }
        let rect = CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        let positioned = clampedPosition(rect, to: pageSize)
        guard positioned.minX.isFinite, positioned.minY.isFinite,
              positioned.width.isFinite, positioned.width > 0,
              positioned.height.isFinite, positioned.height > 0 else { return nil }
        return positioned
    }

    static func resizedSignatureRect(
        _ rect: CGRect,
        requestedWidth: CGFloat,
        aspectRatio: CGFloat,
        pageSize: CGSize
    ) -> CGRect? {
        guard rect.minX.isFinite, rect.maxY.isFinite,
              let size = signatureSize(
                requestedWidth: requestedWidth,
                aspectRatio: aspectRatio,
                pageSize: pageSize
              ) else { return nil }
        let resized = CGRect(
            x: rect.minX,
            y: rect.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let positioned = clampedPosition(resized, to: pageSize)
        guard positioned.minX.isFinite, positioned.minY.isFinite,
              positioned.width.isFinite, positioned.width > 0,
              positioned.height.isFinite, positioned.height > 0 else { return nil }
        return positioned
    }

    static func clamped(_ rect: CGRect, to pageSize: CGSize) -> CGRect {
        var result = rect
        result.size.width = min(max(1, result.width), pageSize.width)
        result.size.height = min(max(1, result.height), pageSize.height)
        result.origin.x = min(max(0, result.minX), pageSize.width - result.width)
        result.origin.y = min(max(0, result.minY), pageSize.height - result.height)
        return result
    }

    private static func clampedPosition(_ rect: CGRect, to pageSize: CGSize) -> CGRect {
        var result = rect
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

    static func pdfPoint(
        for visualPoint: CGPoint,
        pageSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint? {
        let scale = scale(pageSize: pageSize, canvasSize: canvasSize)
        guard scale > 0 else { return nil }
        let drawnPageSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let offset = CGPoint(
            x: (canvasSize.width - drawnPageSize.width) / 2,
            y: (canvasSize.height - drawnPageSize.height) / 2
        )
        let drawingPoint = CGPoint(x: visualPoint.x, y: canvasSize.height - visualPoint.y)
        guard drawingPoint.x >= offset.x,
              drawingPoint.x <= offset.x + drawnPageSize.width,
              drawingPoint.y >= offset.y,
              drawingPoint.y <= offset.y + drawnPageSize.height else { return nil }
        return CGPoint(
            x: (drawingPoint.x - offset.x) / scale,
            y: (drawingPoint.y - offset.y) / scale
        )
    }
}
