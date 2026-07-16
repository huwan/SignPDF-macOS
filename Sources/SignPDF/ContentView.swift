import AppKit
import PDFKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DocumentModel

    var body: some View {
        NavigationSplitView {
            PageSidebar()
                .navigationSplitViewColumnWidth(min: 130, ideal: 160, max: 220)
        } content: {
            canvasArea
                .navigationSplitViewColumnWidth(min: 520, ideal: 760)
        } detail: {
            SignatureSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        }
        .toolbar { toolbar }
        .alert("SignPDF", isPresented: alertBinding) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onExitCommand {
            model.cancelSignaturePlacement()
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    @ViewBuilder
    private var canvasArea: some View {
        if model.document == nil {
            EmptyState(
                title: "打开一份 PDF 开始签名",
                systemImage: "signature",
                description: "签名以矢量方式叠加，导出后仍可清晰缩放。"
            ) {
                Button("打开 PDF…") { model.openDocument() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ZStack(alignment: .top) {
                ScrollView([.horizontal, .vertical]) {
                    PDFCanvasRepresentable(model: model)
                        .frame(
                            width: model.currentPageSize.width * model.zoom,
                            height: model.currentPageSize.height * model.zoom
                        )
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                        .padding(36)
                }

                if let asset = model.pendingSignatureAsset {
                    Label(
                        "在页面上单击放置“\(asset.name)”；按 Esc 或右键取消",
                        systemImage: "cursorarrow.click"
                    )
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 3, y: 1)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.openDocument() } label: {
                Label("打开", systemImage: "doc")
            }
            Button { model.importSignatures() } label: {
                Label("导入签名", systemImage: "signature")
            }
            Button { model.exportDocument() } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(model.document == nil)
            Button(role: .destructive) { model.deleteSelected() } label: {
                Label("删除所选签名", systemImage: "trash")
            }
            .disabled(model.selectedPlacementID == nil)
            .help("删除所选签名")
        }
        ToolbarItem(placement: .principal) {
            if let name = model.sourceURL?.lastPathComponent {
                Text(name).font(.headline)
            }
        }
        ToolbarItemGroup {
            Button { model.zoom = max(0.35, model.zoom - 0.1) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(Int(model.zoom * 100))%")
                .monospacedDigit()
                .frame(width: 46)
            Button { model.zoom = min(3, model.zoom + 0.1) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
        }
    }
}

private struct PageSidebar: View {
    @EnvironmentObject private var model: DocumentModel

    var body: some View {
        List(selection: $model.currentPage) {
            if let document = model.document {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    VStack(spacing: 6) {
                        if let page = document.page(at: index) {
                            Image(nsImage: page.thumbnail(of: CGSize(width: 112, height: 150), for: .mediaBox))
                                .resizable()
                                .scaledToFit()
                                .shadow(radius: 2)
                        }
                        Text("第 \(index + 1) 页")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .tag(index)
                }
            }
        }
        .navigationTitle("页面")
        .onChange(of: model.currentPage) { _ in
            model.selectedPlacementID = nil
            model.cancelSignaturePlacement()
        }
    }
}

private struct SignatureSidebar: View {
    @EnvironmentObject private var model: DocumentModel
    @State private var assetPendingDeletion: SignatureAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("签名库").font(.headline)
            if model.libraryAssets.isEmpty {
                Spacer()
                EmptyState(
                    title: "尚未保存签名",
                    systemImage: "signature",
                    description: "导入单页矢量 PDF；签名会保存在本机供以后使用。"
                ) { EmptyView() }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.libraryAssets) { asset in
                            ZStack(alignment: .topTrailing) {
                                Button { activate(asset) } label: {
                                    VStack(spacing: 8) {
                                        PDFPageVectorPreview(page: asset.page)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 80)
                                        Text(asset.name).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                model.pendingSignatureAssetID == asset.id
                                                    ? Color.accentColor
                                                    : Color.clear,
                                                lineWidth: 2
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(model.document == nil)
                                .help(
                                    model.document == nil
                                        ? "请先打开一份 PDF"
                                        : "单击后在页面选择位置；双击插入页面中央"
                                )

                                Menu {
                                    Button("插入页面中央", systemImage: "rectangle") {
                                        model.addSignature(asset)
                                    }
                                    .disabled(model.document == nil)
                                    Divider()
                                    Button("从签名库删除…", role: .destructive) {
                                        assetPendingDeletion = asset
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.hierarchical)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .padding(7)
                            }
                            .contextMenu {
                                Button("插入页面中央") {
                                    model.addSignature(asset)
                                }
                                .disabled(model.document == nil)
                                Divider()
                                Button("从签名库删除…", role: .destructive) {
                                    assetPendingDeletion = asset
                                }
                            }
                        }
                    }
                }
            }
            Button { model.importSignatures() } label: {
                Label("导入签名 PDF…", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding()
        .confirmationDialog(
            "删除签名？",
            isPresented: deletionDialogPresented,
            titleVisibility: .visible,
            presenting: assetPendingDeletion
        ) { asset in
            Button("从签名库删除", role: .destructive) {
                assetPendingDeletion = nil
                model.deleteAsset(asset)
            }
            Button("取消", role: .cancel) {
                assetPendingDeletion = nil
            }
        } message: { asset in
            Text(deletionMessage(for: asset))
        }
    }

    private var deletionDialogPresented: Binding<Bool> {
        Binding(
            get: { assetPendingDeletion != nil },
            set: { if !$0 { assetPendingDeletion = nil } }
        )
    }

    private func deletionMessage(for asset: SignatureAsset) -> String {
        let placementCount = model.placements.lazy.filter { $0.assetID == asset.id }.count
        if placementCount > 0 {
            return "“\(asset.name)”会从本机签名库中永久删除；当前文档中已经插入的 \(placementCount) 个实例会保留。"
        }
        return "“\(asset.name)”会从本机签名库中永久删除。"
    }

    private func activate(_ asset: SignatureAsset) {
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            model.addSignature(asset)
        } else {
            model.beginPlacingSignature(asset)
        }
    }
}

private struct EmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title2).fontWeight(.semibold)
            Text(description)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
