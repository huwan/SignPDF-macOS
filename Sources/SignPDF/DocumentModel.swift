import AppKit
import PDFKit
import SwiftUI

struct SignatureAsset: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    let document: PDFDocument
    let page: PDFPage
    let isInLibrary: Bool

    init?(
        id: UUID = UUID(),
        name: String,
        url: URL,
        document: PDFDocument,
        isInLibrary: Bool = true
    ) {
        guard let page = document.page(at: 0) else { return nil }
        self.id = id
        self.name = name
        self.url = url
        self.document = document
        self.page = page
        self.isInLibrary = isInLibrary
    }

    var aspectRatio: CGFloat {
        let bounds = page.bounds(for: .mediaBox)
        return bounds.width > 0 && bounds.height > 0 ? bounds.width / bounds.height : 1
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
    case cannotDeleteSignature(String)
    case cannotCreateOutput
    case cannotWriteOutput

    var errorDescription: String? {
        switch self {
        case .cannotReadPDF(let name): return "无法读取 PDF：\(name)"
        case .signatureMustBeSinglePage(let name): return "签名 PDF 必须只有一页：\(name)"
        case .cannotLoadSignatures: return "无法读取已保存的签名库。"
        case .cannotSaveSignature(let name): return "无法保存签名：\(name)"
        case .cannotDeleteSignature(let name): return "无法删除签名：\(name)"
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
    @Published private var handledSignatureLayout: [SignatureLayoutItem] = []

    private let signatureLibrary: SignatureLibrary

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

    var currentPDFPage: PDFPage? {
        guard let document, currentPage >= 0, currentPage < document.pageCount else { return nil }
        return document.page(at: currentPage)
    }

    var currentPageSize: CGSize {
        currentPDFPage?.bounds(for: .mediaBox).size ?? CGSize(width: 595, height: 842)
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
        document = pdf
        self.sourceURL = sourceURL
        currentPage = 0
        placements = []
        handledSignatureLayout = []
        purgeUnusedDetachedAssets()
        selectedPlacementID = nil
        pendingSignatureAssetID = nil
        zoom = 1
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
        guard let asset = pendingSignatureAsset else {
            pendingSignatureAssetID = nil
            return
        }
        addSignature(asset, centeredAt: pagePoint)
    }

    func addSignature(_ asset: SignatureAsset) {
        guard document != nil else { return }
        let pageSize = currentPageSize
        addSignature(
            asset,
            centeredAt: CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)
        )
    }

    func addSignature(_ asset: SignatureAsset, centeredAt pagePoint: CGPoint) {
        guard document != nil else { return }
        let rect = proposedSignatureRect(for: asset, centeredAt: pagePoint)
        let placement = SignaturePlacement(assetID: asset.id, pageIndex: currentPage, rect: rect)
        placements.append(placement)
        selectedPlacementID = placement.id
        pendingSignatureAssetID = nil
    }

    func proposedSignatureRect(for asset: SignatureAsset, centeredAt pagePoint: CGPoint) -> CGRect {
        let pageSize = currentPageSize
        let width = min(
            150.0,
            pageSize.width * 0.35,
            pageSize.height * 0.35 * max(asset.aspectRatio, 0.001)
        )
        let height = width / asset.aspectRatio
        let rect = CGRect(
            x: pagePoint.x - width / 2,
            y: pagePoint.y - height / 2,
            width: width,
            height: height
        )
        return PlacementGeometry.clamped(rect, to: pageSize)
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

    func deleteAsset(_ asset: SignatureAsset) {
        do {
            let isUsedInDocument = placements.contains { $0.assetID == asset.id }
            let detachedAsset: SignatureAsset?
            if isUsedInDocument {
                let detachedData = asset.document.dataRepresentation()
                    ?? (try? Data(contentsOf: asset.url))
                guard let detachedData,
                      let document = PDFDocument(data: detachedData),
                      let detached = SignatureAsset(
                        id: asset.id,
                        name: asset.name,
                        url: asset.url,
                        document: document,
                        isInLibrary: false
                      ) else {
                    throw SignPDFError.cannotReadPDF(asset.name)
                }
                detachedAsset = detached
            } else {
                detachedAsset = nil
            }

            try signatureLibrary.delete(asset)

            if pendingSignatureAssetID == asset.id {
                pendingSignatureAssetID = nil
            }

            if let index = assets.firstIndex(where: { $0.id == asset.id }),
               let detachedAsset {
                assets[index] = detachedAsset
            } else {
                assets.removeAll { $0.id == asset.id }
            }
        } catch {
            present(SignPDFError.cannotDeleteSignature(asset.name))
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
