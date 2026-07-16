import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var documentModel: DocumentModel?
    private weak var mainWindow: NSWindow?
    private var pendingDocumentURL: URL?
    private var modelObservation: AnyCancellable?
    private var windowDelegateProxy: WindowDelegateProxy?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Swift Package executables do not always become the active macOS app
        // when launched from Terminal. Make the editor a regular foreground app
        // so keyboard input cannot accidentally remain directed at Finder.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            (self.mainWindow ?? NSApp.windows.first)?.makeKeyAndOrderFront(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return }
        openDocument(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let documentModel else { return .terminateNow }
        return documentModel.resolveUnsavedChanges() ? .terminateNow : .terminateCancel
    }

    func connect(to model: DocumentModel) {
        documentModel = model
        modelObservation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateWindowDocumentState()
            }
        }
        DispatchQueue.main.async {
            self.updateWindowDocumentState()
        }
        if let pendingDocumentURL {
            self.pendingDocumentURL = nil
            model.requestOpen(url: pendingDocumentURL)
        }
    }

    private func openDocument(_ url: URL) {
        if let documentModel {
            documentModel.requestOpen(url: url)
        } else {
            pendingDocumentURL = url
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func connect(to window: NSWindow) {
        mainWindow = window
        if windowDelegateProxy == nil || window.delegate !== windowDelegateProxy {
            let proxy = WindowDelegateProxy(originalDelegate: window.delegate) { [weak self] sender in
                guard let self, sender === self.mainWindow,
                      let documentModel = self.documentModel else { return true }
                return documentModel.resolveUnsavedChanges()
            }
            windowDelegateProxy = proxy
            window.delegate = proxy
        }
        updateWindowDocumentState()
    }

    private func updateWindowDocumentState() {
        mainWindow?.isDocumentEdited = documentModel?.hasUnsavedChanges ?? false
    }
}

@MainActor
private final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    let originalDelegate: NSWindowDelegate?
    private let shouldClose: (NSWindow) -> Bool

    init(originalDelegate: NSWindowDelegate?, shouldClose: @escaping (NSWindow) -> Bool) {
        self.originalDelegate = originalDelegate
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard originalDelegate?.windowShouldClose?(sender) ?? true else { return false }
        return shouldClose(sender)
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return true
        }
        return super.responds(to: selector)
            || (originalDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let resolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        resolveWindow(for: view)
    }

    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            if let window = view.window {
                resolve(window)
            }
        }
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
                .background(WindowAccessor { appDelegate.connect(to: $0) })
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
