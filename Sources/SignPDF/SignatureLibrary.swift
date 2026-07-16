import Foundation
import PDFKit

struct SignatureLibrary {
    struct LoadResult {
        let assets: [SignatureAsset]
        let skippedItemCount: Int
    }

    private struct Metadata: Codable {
        let id: UUID
        let name: String
        let createdAt: Date
    }

    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.rootURL = applicationSupport
                .appendingPathComponent("app.signpdf.SignPDF", isDirectory: true)
                .appendingPathComponent("Signatures", isDirectory: true)
        }
    }

    func load() throws -> LoadResult {
        try prepareRootDirectory()
        removeAbandonedWorkingDirectories()

        let itemURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var loaded: [(metadata: Metadata, asset: SignatureAsset)] = []
        var skippedItemCount = 0

        for itemURL in itemURLs {
            guard UUID(uuidString: itemURL.lastPathComponent) != nil else { continue }
            do {
                let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    skippedItemCount += 1
                    isolateCorruptItem(at: itemURL)
                    continue
                }
                let metadataData = try Data(contentsOf: metadataURL(in: itemURL))
                let metadata = try JSONDecoder().decode(Metadata.self, from: metadataData)
                guard metadata.id.uuidString == itemURL.lastPathComponent,
                      let document = PDFDocument(url: pdfURL(in: itemURL)),
                      document.pageCount == 1,
                      let asset = SignatureAsset(
                        id: metadata.id,
                        name: metadata.name,
                        url: pdfURL(in: itemURL),
                        document: document
                      ) else {
                    skippedItemCount += 1
                    isolateCorruptItem(at: itemURL)
                    continue
                }
                loaded.append((metadata, asset))
            } catch {
                skippedItemCount += 1
                isolateCorruptItem(at: itemURL)
            }
        }

        loaded.sort {
            if $0.metadata.createdAt == $1.metadata.createdAt {
                return $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending
            }
            return $0.metadata.createdAt < $1.metadata.createdAt
        }

        return LoadResult(
            assets: loaded.map(\.asset),
            skippedItemCount: skippedItemCount
        )
    }

    func containsCopy(of sourceURL: URL, in assets: [SignatureAsset]) -> Bool {
        assets.contains { asset in
            asset.url.standardizedFileURL == sourceURL.standardizedFileURL
                || fileManager.contentsEqual(atPath: asset.url.path, andPath: sourceURL.path)
        }
    }

    func importSignature(from sourceURL: URL, name: String) throws -> SignatureAsset {
        try prepareRootDirectory()
        removeAbandonedWorkingDirectories()

        let id = UUID()
        let temporaryURL = rootURL.appendingPathComponent(".\(id.uuidString).tmp", isDirectory: true)
        let destinationURL = itemURL(for: id)

        do {
            try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
            try fileManager.copyItem(at: sourceURL, to: pdfURL(in: temporaryURL))

            let metadata = Metadata(id: id, name: name, createdAt: Date())
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataURL(in: temporaryURL), options: .atomic)

            guard let temporaryDocument = PDFDocument(url: pdfURL(in: temporaryURL)),
                  temporaryDocument.pageCount > 0 else {
                throw SignPDFError.cannotReadPDF(sourceURL.lastPathComponent)
            }
            guard temporaryDocument.pageCount == 1 else {
                throw SignPDFError.signatureMustBeSinglePage(sourceURL.lastPathComponent)
            }

            try fileManager.moveItem(at: temporaryURL, to: destinationURL)

            guard let storedDocument = PDFDocument(url: pdfURL(in: destinationURL)),
                  let asset = SignatureAsset(
                    id: id,
                    name: name,
                    url: pdfURL(in: destinationURL),
                    document: storedDocument
                  ) else {
                throw SignPDFError.cannotReadPDF(sourceURL.lastPathComponent)
            }
            return asset
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    func delete(_ asset: SignatureAsset) throws {
        try prepareRootDirectory()
        let destinationURL = itemURL(for: asset.id)
        guard asset.url.standardizedFileURL.deletingLastPathComponent() == destinationURL.standardizedFileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard fileManager.fileExists(atPath: destinationURL.path) else { return }

        let tombstoneURL = rootURL.appendingPathComponent(
            ".\(UUID().uuidString).deleted",
            isDirectory: true
        )
        try fileManager.moveItem(at: destinationURL, to: tombstoneURL)
        try? fileManager.removeItem(at: tombstoneURL)
    }

    private func prepareRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func itemURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func pdfURL(in itemURL: URL) -> URL {
        itemURL.appendingPathComponent("signature.pdf", isDirectory: false)
    }

    private func metadataURL(in itemURL: URL) -> URL {
        itemURL.appendingPathComponent("metadata.json", isDirectory: false)
    }

    private func removeAbandonedWorkingDirectories() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }

        for url in urls {
            let name = url.lastPathComponent
            guard workingItemID(from: name, suffix: ".tmp") != nil
                    || workingItemID(from: name, suffix: ".deleted") != nil else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func workingItemID(from name: String, suffix: String) -> UUID? {
        guard name.hasPrefix("."), name.hasSuffix(suffix) else { return nil }
        let start = name.index(after: name.startIndex)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return UUID(uuidString: String(name[start..<end]))
    }

    private func isolateCorruptItem(at itemURL: URL) {
        let quarantineRoot = rootURL.appendingPathComponent("Corrupt", isDirectory: true)
        guard (try? fileManager.createDirectory(
            at: quarantineRoot,
            withIntermediateDirectories: true,
            attributes: nil
        )) != nil else { return }

        var destinationURL = quarantineRoot.appendingPathComponent(
            itemURL.lastPathComponent,
            isDirectory: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = quarantineRoot.appendingPathComponent(
                "\(itemURL.lastPathComponent)-\(UUID().uuidString)",
                isDirectory: true
            )
        }
        try? fileManager.moveItem(at: itemURL, to: destinationURL)
    }
}
