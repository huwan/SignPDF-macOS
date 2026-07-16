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
        return bounds.height > 0 ? bounds.width / bounds.height : 1
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
    @Published var zoom: CGFloat = 1
    @Published var alertMessage: String?

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

    var libraryAssets: [SignatureAsset] {
        assets.filter(\.isInLibrary)
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
        open(url: url)
    }

    func open(url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            present(SignPDFError.cannotReadPDF(url.lastPathComponent))
            return
        }
        document = pdf
        sourceURL = url
        currentPage = 0
        placements = []
        purgeUnusedDetachedAssets()
        selectedPlacementID = nil
        zoom = 1
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

    func addSignature(_ asset: SignatureAsset) {
        guard document != nil else { return }
        let pageSize = currentPageSize
        let width = min(150.0, pageSize.width * 0.35)
        let height = width / asset.aspectRatio
        let rect = CGRect(
            x: (pageSize.width - width) / 2,
            y: (pageSize.height - height) / 2,
            width: width,
            height: height
        )
        let placement = SignaturePlacement(assetID: asset.id, pageIndex: currentPage, rect: rect)
        placements.append(placement)
        selectedPlacementID = placement.id
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

    func exportDocument() {
        guard let sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + "-signed.pdf"
        panel.message = "导出会保留原页面和签名的矢量内容"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try PDFExporter.export(document: document, placements: placements, assets: assets, to: destination)
        } catch {
            present(error)
        }
    }

    func present(_ error: Error) {
        alertMessage = error.localizedDescription
    }
}
