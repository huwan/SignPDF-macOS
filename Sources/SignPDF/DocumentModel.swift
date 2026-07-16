import AppKit
import PDFKit
import SwiftUI

struct SignatureAsset: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let document: PDFDocument
    let page: PDFPage

    init(name: String, url: URL, document: PDFDocument) {
        self.name = name
        self.url = url
        self.document = document
        self.page = document.page(at: 0)!
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
    case cannotCreateOutput
    case cannotWriteOutput

    var errorDescription: String? {
        switch self {
        case .cannotReadPDF(let name): return "无法读取 PDF：\(name)"
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

    var pageCount: Int { document?.pageCount ?? 0 }

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
            guard !assets.contains(where: { $0.url == url }) else { continue }
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                present(SignPDFError.cannotReadPDF(url.lastPathComponent))
                continue
            }
            assets.append(SignatureAsset(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                document: document
            ))
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
