import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var documentModel: DocumentModel?
    private var pendingDocumentURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Swift Package executables do not always become the active macOS app
        // when launched from Terminal. Make the editor a regular foreground app
        // so keyboard input cannot accidentally remain directed at Finder.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return }
        openDocument(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func connect(to model: DocumentModel) {
        documentModel = model
        if let pendingDocumentURL {
            self.pendingDocumentURL = nil
            model.open(url: pendingDocumentURL)
        }
    }

    private func openDocument(_ url: URL) {
        if let documentModel {
            documentModel.open(url: url)
        } else {
            pendingDocumentURL = url
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@main
struct SignPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DocumentModel()

    var body: some Scene {
        Window("SignPDF", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { appDelegate.connect(to: model) }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开 PDF…") { model.openDocument() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .importExport) {
                Button("导入矢量签名…") { model.importSignatures() }
                    .keyboardShortcut("i")
                Button("导出已签名 PDF…") { model.exportDocument() }
                    .keyboardShortcut("e")
                    .disabled(model.document == nil)
            }
        }
    }
}
