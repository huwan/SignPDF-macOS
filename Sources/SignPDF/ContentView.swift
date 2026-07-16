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
            ScrollView([.horizontal, .vertical]) {
                PDFCanvasRepresentable(model: model)
                    .frame(
                        width: model.currentPageSize.width * model.zoom,
                        height: model.currentPageSize.height * model.zoom
                    )
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .padding(36)
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
            .disabled(model.document == nil)
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
        .onChange(of: model.currentPage) { _ in model.selectedPlacementID = nil }
    }
}

private struct SignatureSidebar: View {
    @EnvironmentObject private var model: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("矢量签名").font(.headline)
            if model.assets.isEmpty {
                Spacer()
                EmptyState(
                    title: "尚未导入签名",
                    systemImage: "signature",
                    description: "请导入单页 PDF 格式的矢量签名。"
                ) { EmptyView() }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.assets) { asset in
                            Button { model.addSignature(asset) } label: {
                                VStack(spacing: 8) {
                                    PDFPageVectorPreview(page: asset.page)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 80)
                                    Text(asset.name).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .help("添加到当前页")
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
