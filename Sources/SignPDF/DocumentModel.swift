import AppKit
import PDFKit
import SwiftUI

enum SignatureSizing {
    static let pointsPerCentimeter: CGFloat = 72 / 2.54
    static let minimumWidthCentimeters: CGFloat = 0.5
    static let maximumWidthCentimeters: CGFloat = 100
    static let widthComparisonToleranceCentimeters: CGFloat = 0.000_5
    static let defaultWidthCentimeters: CGFloat = 3.6
    static let defaultWidthPoints = defaultWidthCentimeters * pointsPerCentimeter
    static let minimumWidthPoints = minimumWidthCentimeters * pointsPerCentimeter
    static let maximumWidthPoints = maximumWidthCentimeters * pointsPerCentimeter

    static func points(fromCentimeters centimeters: CGFloat) -> CGFloat {
        centimeters * pointsPerCentimeter
    }

    static func centimeters(fromPoints points: CGFloat) -> CGFloat {
        points / pointsPerCentimeter
    }

    static func validPoints(fromCentimeters centimeters: CGFloat) -> CGFloat? {
        guard centimeters.isFinite,
              centimeters >= minimumWidthCentimeters,
              centimeters <= maximumWidthCentimeters else { return nil }
        let points = points(fromCentimeters: centimeters)
        return isValid(points: points) ? points : nil
    }

    static func isValid(points: CGFloat) -> Bool {
        guard points.isFinite else { return false }
        let centimeters = centimeters(fromPoints: points)
        return centimeters >= minimumWidthCentimeters
            && centimeters <= maximumWidthCentimeters
    }
}

struct SignatureAsset: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    let document: PDFDocument
    let page: PDFPage
    let defaultWidthPoints: CGFloat
    let isInLibrary: Bool

    init?(
        id: UUID = UUID(),
        name: String,
        url: URL,
        document: PDFDocument,
        defaultWidthPoints: CGFloat = SignatureSizing.defaultWidthPoints,
        isInLibrary: Bool = true
    ) {
        guard let page = document.page(at: 0) else { return nil }
        self.id = id
        self.name = name
        self.url = url
        self.document = document
        self.page = page
        self.defaultWidthPoints = SignatureSizing.isValid(points: defaultWidthPoints)
            ? defaultWidthPoints
            : SignatureSizing.defaultWidthPoints
        self.isInLibrary = isInLibrary
    }

    var aspectRatio: CGFloat {
        let bounds = page.bounds(for: .mediaBox)
        return bounds.width > 0 && bounds.height > 0 ? bounds.width / bounds.height : 1
    }

    var defaultWidthCentimeters: CGFloat {
        SignatureSizing.centimeters(fromPoints: defaultWidthPoints)
    }

    func replacingDefaultWidthPoints(_ width: CGFloat) -> SignatureAsset? {
        SignatureAsset(
            id: id,
            name: name,
            url: url,
            document: document,
            defaultWidthPoints: width,
            isInLibrary: isInLibrary
        )
    }
}

struct SignaturePlacement: Identifiable, Equatable {
    let id: UUID
    let assetID: UUID
    let pageIndex: Int
    var rect: CGRect

    init(id: UUID = UUID(), assetID: UUID, pageIndex: Int, rect: CGRect) {
        self.id = id
        self.assetID = assetID
        self.pageIndex = pageIndex
        self.rect = rect
    }
}

struct PageNavigationRequest: Equatable {
    let id = UUID()
    let pageIndex: Int
}

enum ZoomGeometry {
    static let minimum: CGFloat = 0.35
    static let maximum: CGFloat = 3
    static let step: CGFloat = 0.1

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(maximum, max(minimum, zoom))
    }

    static func stepped(_ zoom: CGFloat, by delta: CGFloat) -> CGFloat {
        clamped(zoom + delta)
    }

    static func magnified(_ zoom: CGFloat, by scale: CGFloat) -> CGFloat {
        clamped(zoom * scale)
    }
}

private struct SignatureLayoutItem: Equatable {
    let assetID: UUID
    let pageIndex: Int
    let rect: CGRect

    init(_ placement: SignaturePlacement) {
        assetID = placement.assetID
        pageIndex = placement.pageIndex
        rect = CGRect(
            x: Self.normalized(placement.rect.origin.x),
            y: Self.normalized(placement.rect.origin.y),
            width: Self.normalized(placement.rect.width),
            height: Self.normalized(placement.rect.height)
        )
    }

    private static func normalized(_ value: CGFloat) -> CGFloat {
        (value * 1_000).rounded() / 1_000
    }
}

enum SignPDFError: LocalizedError {
    case cannotReadPDF(String)
    case signatureMustBeSinglePage(String)
    case cannotLoadSignatures
    case cannotSaveSignature(String)
    case cannotUpdateSignature(String)
    case cannotDeleteSignature(String)
    case invalidSignatureWidth
    case signatureWidthDoesNotFitPage
    case invalidSignatureGeometry(String)
    case cannotCreateOutput
    case cannotWriteOutput

    var errorDescription: String? {
        switch self {
        case .cannotReadPDF(let name): return "无法读取 PDF：\(name)"
        case .signatureMustBeSinglePage(let name): return "签名 PDF 必须只有一页：\(name)"
        case .cannotLoadSignatures: return "无法读取已保存的签名库。"
        case .cannotSaveSignature(let name): return "无法保存签名：\(name)"
        case .cannotUpdateSignature(let name): return "无法保存“\(name)”的默认宽度。"
        case .cannotDeleteSignature(let name): return "无法删除签名：\(name)"
        case .invalidSignatureWidth:
            return "签名宽度必须在 0.5 到 100 cm 之间。"
        case .signatureWidthDoesNotFitPage:
            return "输入的签名宽度无法完整放入当前页面。"
        case .invalidSignatureGeometry(let name):
            return "无法计算签名“\(name)”的页面尺寸。"
        case .cannotCreateOutput: return "无法创建输出 PDF。"
        case .cannotWriteOutput: return "写入 PDF 时发生错误。"
        }
    }
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var sourceURL: URL?
    @Published var currentPage = 0
    @Published var assets: [SignatureAsset] = []
    @Published var placements: [SignaturePlacement] = []
    @Published var selectedPlacementID: UUID?
    @Published var pendingSignatureAssetID: UUID?
    @Published var zoom: CGFloat = 1
    @Published var alertMessage: String?
    @Published private(set) var pageNavigationRequest: PageNavigationRequest?
    @Published private var handledSignatureLayout: [SignatureLayoutItem] = []

    private let signatureLibrary: SignatureLibrary
    private(set) var pageSizes: [CGSize] = []
    private(set) var maximumPageWidth: CGFloat = 595

    private static let fallbackPageSize = CGSize(width: 595, height: 842)

    init(signatureLibrary: SignatureLibrary = SignatureLibrary()) {
        self.signatureLibrary = signatureLibrary
        do {
            let result = try signatureLibrary.load()
            assets = result.assets
            if result.skippedItemCount > 0 {
                alertMessage = "有 \(result.skippedItemCount) 个已保存的签名无法读取。"
            }
        } catch {
            alertMessage = SignPDFError.cannotLoadSignatures.localizedDescription
        }
    }

    var pageCount: Int { document?.pageCount ?? 0 }

    var hasUnsavedChanges: Bool {
        document != nil && currentSignatureLayout != handledSignatureLayout
    }

    var libraryAssets: [SignatureAsset] {
        assets.filter(\.isInLibrary)
    }

    var pendingSignatureAsset: SignatureAsset? {
        guard let pendingSignatureAssetID else { return nil }
        return assets.first { $0.id == pendingSignatureAssetID }
    }

    var selectedPlacement: SignaturePlacement? {
        guard let selectedPlacementID else { return nil }
        return placements.first { $0.id == selectedPlacementID }
    }

    var selectedSignatureAsset: SignatureAsset? {
        guard let selectedPlacement else { return nil }
        return asset(for: selectedPlacement)
    }

    var selectedPlacementWidthCentimeters: CGFloat? {
        selectedPlacement.map { SignatureSizing.centimeters(fromPoints: $0.rect.width) }
    }

    var canSaveSelectedWidthAsDefault: Bool {
        selectedSignatureAsset?.isInLibrary == true
            && selectedPlacement.map { SignatureSizing.isValid(points: $0.rect.width) } == true
    }

    var canEditSelectedPlacementWidth: Bool {
        guard let placement = selectedPlacement,
              let maximumWidth = maximumPlacementWidthCentimeters(id: placement.id) else {
            return false
        }
        return maximumWidth + SignatureSizing.widthComparisonToleranceCentimeters
            >= SignatureSizing.minimumWidthCentimeters
    }

    func maximumPlacementWidthCentimeters(id: UUID) -> CGFloat? {
        guard let placement = placements.first(where: { $0.id == id }),
              let asset = asset(for: placement),
              let maximumWidth = PlacementGeometry.maximumSignatureWidth(
                aspectRatio: asset.aspectRatio,
                pageSize: pageSize(at: placement.pageIndex)
              ) else { return nil }
        return min(
            SignatureSizing.maximumWidthCentimeters,
            SignatureSizing.centimeters(fromPoints: maximumWidth)
        )
    }

    var currentPDFPage: PDFPage? {
        pdfPage(at: currentPage)
    }

    var currentPageSize: CGSize {
        pageSize(at: currentPage)
    }

    func pdfPage(at pageIndex: Int) -> PDFPage? {
        guard let document, pageIndex >= 0, pageIndex < document.pageCount else { return nil }
        return document.page(at: pageIndex)
    }

    func pageSize(at pageIndex: Int) -> CGSize {
        guard pageSizes.indices.contains(pageIndex) else { return Self.fallbackPageSize }
        return pageSizes[pageIndex]
    }

    func requestPageNavigation(to pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < pageCount else { return }
        currentPage = pageIndex
        selectedPlacementID = nil
        pageNavigationRequest = PageNavigationRequest(pageIndex: pageIndex)
    }

    func updateCurrentPageFromViewport(_ pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < pageCount, pageIndex != currentPage else { return }
        currentPage = pageIndex
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "选择需要签名的 PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        requestOpen(url: url)
    }

    func open(url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            present(SignPDFError.cannotReadPDF(url.lastPathComponent))
            return
        }
        replaceDocument(with: pdf, sourceURL: url)
    }

    func requestOpen(url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            present(SignPDFError.cannotReadPDF(url.lastPathComponent))
            return
        }
        guard resolveUnsavedChanges() else { return }
        replaceDocument(with: pdf, sourceURL: url)
    }

    private func replaceDocument(with pdf: PDFDocument, sourceURL: URL) {
        pageSizes = (0..<pdf.pageCount).map { pageIndex in
            guard let page = pdf.page(at: pageIndex) else { return Self.fallbackPageSize }
            let size = page.bounds(for: .mediaBox).size
            guard size.width > 0, size.height > 0,
                  size.width.isFinite, size.height.isFinite else { return Self.fallbackPageSize }
            return size
        }
        maximumPageWidth = pageSizes.map(\.width).max() ?? Self.fallbackPageSize.width
        document = pdf
        self.sourceURL = sourceURL
        currentPage = 0
        placements = []
        handledSignatureLayout = []
        purgeUnusedDetachedAssets()
        selectedPlacementID = nil
        pendingSignatureAssetID = nil
        zoom = 1
        pageNavigationRequest = PageNavigationRequest(pageIndex: 0)
    }

    @discardableResult
    func resolveUnsavedChanges() -> Bool {
        guard hasUnsavedChanges else { return true }

        let documentName = sourceURL?.lastPathComponent ?? "当前 PDF"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "要导出对“\(documentName)”所做的更改吗？"
        alert.informativeText = "如果不导出，添加、移动或删除的签名将会丢失。"
        alert.addButton(withTitle: "导出…")
        let discardButton = alert.addButton(withTitle: "不导出")
        discardButton.hasDestructiveAction = true
        let cancelButton = alert.addButton(withTitle: "取消")
        cancelButton.keyEquivalent = "\u{1b}"

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return exportDocument()
        case .alertSecondButtonReturn:
            markCurrentSignatureLayoutAsHandled()
            return true
        default:
            return false
        }
    }

    func markCurrentSignatureLayoutAsHandled() {
        handledSignatureLayout = currentSignatureLayout
    }

    func importSignatures() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "选择一个或多个矢量 PDF 签名"
        guard panel.runModal() == .OK else { return }
        importSignatures(urls: panel.urls)
    }

    func importSignatures(urls: [URL]) {
        for url in urls {
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                present(SignPDFError.cannotReadPDF(url.lastPathComponent))
                continue
            }
            guard document.pageCount == 1 else {
                present(SignPDFError.signatureMustBeSinglePage(url.lastPathComponent))
                continue
            }
            guard !signatureLibrary.containsCopy(of: url, in: libraryAssets) else { continue }
            do {
                let asset = try signatureLibrary.importSignature(
                    from: url,
                    name: url.deletingPathExtension().lastPathComponent
                )
                assets.append(asset)
            } catch {
                present(SignPDFError.cannotSaveSignature(url.lastPathComponent))
            }
        }
    }

    func beginPlacingSignature(_ asset: SignatureAsset) {
        guard document != nil, assets.contains(where: { $0.id == asset.id }) else { return }
        pendingSignatureAssetID = asset.id
        selectedPlacementID = nil
    }

    func cancelSignaturePlacement() {
        pendingSignatureAssetID = nil
    }

    func placePendingSignature(at pagePoint: CGPoint) {
        placePendingSignature(at: pagePoint, onPage: currentPage)
    }

    func placePendingSignature(at pagePoint: CGPoint, onPage pageIndex: Int) {
        guard let asset = pendingSignatureAsset else {
            pendingSignatureAssetID = nil
            return
        }
        addSignature(asset, centeredAt: pagePoint, onPage: pageIndex)
    }

    func addSignature(_ asset: SignatureAsset) {
        guard document != nil else { return }
        let pageSize = currentPageSize
        addSignature(
            asset,
            centeredAt: CGPoint(x: pageSize.width / 2, y: pageSize.height / 2),
            onPage: currentPage
        )
    }

    func addSignature(_ asset: SignatureAsset, centeredAt pagePoint: CGPoint) {
        addSignature(asset, centeredAt: pagePoint, onPage: currentPage)
    }

    func addSignature(_ asset: SignatureAsset, centeredAt pagePoint: CGPoint, onPage pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < pageCount else { return }
        guard let currentAsset = assets.first(where: { $0.id == asset.id }) else { return }
        let rect = proposedSignatureRect(for: currentAsset, centeredAt: pagePoint, onPage: pageIndex)
        guard rect.width.isFinite, rect.width > 0,
              rect.height.isFinite, rect.height > 0 else {
            present(SignPDFError.invalidSignatureGeometry(currentAsset.name))
            return
        }
        let placement = SignaturePlacement(assetID: currentAsset.id, pageIndex: pageIndex, rect: rect)
        placements.append(placement)
        currentPage = pageIndex
        selectedPlacementID = placement.id
        pendingSignatureAssetID = nil
    }

    func proposedSignatureRect(for asset: SignatureAsset, centeredAt pagePoint: CGPoint) -> CGRect {
        proposedSignatureRect(for: asset, centeredAt: pagePoint, onPage: currentPage)
    }

    func proposedSignatureRect(
        for asset: SignatureAsset,
        centeredAt pagePoint: CGPoint,
        onPage pageIndex: Int
    ) -> CGRect {
        let pageSize = pageSize(at: pageIndex)
        return PlacementGeometry.signatureRect(
            centeredAt: pagePoint,
            requestedWidth: asset.defaultWidthPoints,
            aspectRatio: asset.aspectRatio,
            pageSize: pageSize
        ) ?? .zero
    }

    func asset(for placement: SignaturePlacement) -> SignatureAsset? {
        assets.first(where: { $0.id == placement.assetID })
    }

    func deleteSelected() {
        guard let id = selectedPlacementID else { return }
        deletePlacement(id: id)
    }

    func deletePlacement(id: UUID) {
        placements.removeAll { $0.id == id }
        if selectedPlacementID == id {
            selectedPlacementID = nil
        }
        purgeUnusedDetachedAssets()
    }

    @discardableResult
    func resizePlacement(id: UUID, toWidthCentimeters centimeters: CGFloat) -> Bool {
        guard let width = SignatureSizing.validPoints(fromCentimeters: centimeters) else {
            present(SignPDFError.invalidSignatureWidth)
            return false
        }
        guard let index = placements.firstIndex(where: { $0.id == id }),
              let asset = asset(for: placements[index]),
              let maximumWidth = PlacementGeometry.maximumSignatureWidth(
                aspectRatio: asset.aspectRatio,
                pageSize: pageSize(at: placements[index].pageIndex)
              ) else { return false }
        guard width <= maximumWidth + SignatureSizing.points(
            fromCentimeters: SignatureSizing.widthComparisonToleranceCentimeters
        ) else {
            present(SignPDFError.signatureWidthDoesNotFitPage)
            return false
        }
        guard let resized = PlacementGeometry.resizedSignatureRect(
                placements[index].rect,
                requestedWidth: width,
                aspectRatio: asset.aspectRatio,
                pageSize: pageSize(at: placements[index].pageIndex)
              ) else { return false }
        placements[index].rect = resized
        return true
    }

    @discardableResult
    func updateDefaultWidth(for asset: SignatureAsset, toCentimeters centimeters: CGFloat) -> Bool {
        guard let width = SignatureSizing.validPoints(fromCentimeters: centimeters) else {
            present(SignPDFError.invalidSignatureWidth)
            return false
        }
        guard let index = assets.firstIndex(where: { $0.id == asset.id }),
              assets[index].isInLibrary,
              let updatedAsset = assets[index].replacingDefaultWidthPoints(width) else {
            return false
        }

        do {
            try signatureLibrary.updateDefaultWidth(width, for: assets[index])
            assets[index] = updatedAsset
            return true
        } catch {
            present(SignPDFError.cannotUpdateSignature(asset.name))
            return false
        }
    }

    @discardableResult
    func saveSelectedPlacementWidthAsDefault() -> Bool {
        guard let placement = selectedPlacement,
              let asset = asset(for: placement),
              asset.isInLibrary else { return false }
        return updateDefaultWidth(
            for: asset,
            toCentimeters: SignatureSizing.centimeters(fromPoints: placement.rect.width)
        )
    }

    func deleteAsset(_ asset: SignatureAsset) {
        guard let currentAsset = assets.first(where: { $0.id == asset.id }),
              currentAsset.isInLibrary else { return }
        do {
            let isUsedInDocument = placements.contains { $0.assetID == currentAsset.id }
            let detachedAsset: SignatureAsset?
            if isUsedInDocument {
                let detachedData = currentAsset.document.dataRepresentation()
                    ?? (try? Data(contentsOf: currentAsset.url))
                guard let detachedData,
                      let document = PDFDocument(data: detachedData),
                      let detached = SignatureAsset(
                        id: currentAsset.id,
                        name: currentAsset.name,
                        url: currentAsset.url,
                        document: document,
                        defaultWidthPoints: currentAsset.defaultWidthPoints,
                        isInLibrary: false
                      ) else {
                    throw SignPDFError.cannotReadPDF(currentAsset.name)
                }
                detachedAsset = detached
            } else {
                detachedAsset = nil
            }

            try signatureLibrary.delete(currentAsset)

            if pendingSignatureAssetID == currentAsset.id {
                pendingSignatureAssetID = nil
            }

            if let index = assets.firstIndex(where: { $0.id == currentAsset.id }),
               let detachedAsset {
                assets[index] = detachedAsset
            } else {
                assets.removeAll { $0.id == currentAsset.id }
            }
        } catch {
            present(SignPDFError.cannotDeleteSignature(currentAsset.name))
        }
    }

    private func purgeUnusedDetachedAssets() {
        let usedAssetIDs = Set(placements.map(\.assetID))
        assets.removeAll { !$0.isInLibrary && !usedAssetIDs.contains($0.id) }
    }

    @discardableResult
    func exportDocument() -> Bool {
        guard let sourceURL else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + "-signed.pdf"
        panel.message = "导出会保留原页面和签名的矢量内容"
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        do {
            try PDFExporter.export(document: document, placements: placements, assets: assets, to: destination)
            markCurrentSignatureLayoutAsHandled()
            return true
        } catch {
            present(error)
            return false
        }
    }

    private var currentSignatureLayout: [SignatureLayoutItem] {
        placements.map(SignatureLayoutItem.init)
    }

    func present(_ error: Error) {
        alertMessage = error.localizedDescription
    }
}
