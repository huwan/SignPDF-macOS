import AppKit
import PDFKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DocumentModel
    @GestureState private var pinchScale: CGFloat = 1
    @State private var placementWidthEditor: PlacementWidthEditorRequest?

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
        .sheet(item: $placementWidthEditor) { request in
            SignatureWidthEditorSheet(
                title: "设置签名宽度",
                signatureName: request.signatureName,
                initialCentimeters: request.initialCentimeters,
                maximumCentimeters: request.maximumCentimeters,
                explanation: "精确调整当前实例；不会改变这个签名以后插入时的默认宽度。",
                actionTitle: "应用"
            ) { centimeters in
                model.resizePlacement(
                    id: request.placementID,
                    toWidthCentimeters: centimeters
                )
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private var effectiveZoom: CGFloat {
        ZoomGeometry.magnified(model.zoom, by: pinchScale)
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                model.zoom = ZoomGeometry.magnified(model.zoom, by: value)
            }
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
        } else if let document = model.document {
            ZStack(alignment: .top) {
                GeometryReader { viewport in
                    ScrollViewReader { reader in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<document.pageCount, id: \.self) { pageIndex in
                                    let pageSize = model.pageSize(at: pageIndex)
                                    PDFCanvasRepresentable(model: model, pageIndex: pageIndex)
                                        .frame(
                                            width: pageSize.width * effectiveZoom,
                                            height: pageSize.height * effectiveZoom
                                        )
                                        .background(PageFrameReporter(pageIndex: pageIndex))
                                        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                                        .padding(.vertical, ContinuousScrollLayout.pageVerticalPadding)
                                        .id(pageIndex)
                                }
                            }
                            .frame(
                                width: ContinuousScrollLayout.contentWidth(
                                    viewportWidth: viewport.size.width,
                                    maximumPageWidth: model.maximumPageWidth,
                                    zoom: effectiveZoom
                                )
                            )
                            .padding(.vertical, ContinuousScrollLayout.documentVerticalPadding)
                        }
                        .coordinateSpace(name: ContinuousScrollLayout.coordinateSpaceName)
                        .simultaneousGesture(pinchGesture)
                        .onPreferenceChange(PageFramePreferenceKey.self) { pageFrames in
                            let viewportRect = CGRect(origin: .zero, size: viewport.size)
                            guard let pageIndex = ContinuousPageGeometry.activePageIndex(
                                viewport: viewportRect,
                                pageFrames: pageFrames,
                                pageCount: document.pageCount,
                                keeping: model.currentPage
                            ) else { return }
                            model.updateCurrentPageFromViewport(pageIndex)
                        }
                        .onChange(of: model.pageNavigationRequest) { request in
                            guard let request else { return }
                            let pageHeight = model.pageSize(at: request.pageIndex).height * effectiveZoom
                            let anchor: UnitPoint = pageHeight < viewport.size.height ? .center : .top
                            reader.scrollTo(request.pageIndex, anchor: anchor)
                        }
                    }
                }
                .id(ObjectIdentifier(document))

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
            Menu {
                Button("精确设置宽度…", systemImage: "ruler") {
                    editSelectedPlacementWidth()
                }
                Button("将当前宽度设为默认", systemImage: "arrow.down.to.line") {
                    model.saveSelectedPlacementWidthAsDefault()
                }
                .disabled(!model.canSaveSelectedWidthAsDefault)
            } label: {
                Label("签名尺寸", systemImage: "ruler")
            }
            .disabled(!model.canEditSelectedPlacementWidth)
            .help(
                model.selectedPlacementID == nil
                    ? "请先选择一个签名"
                    : model.canEditSelectedPlacementWidth
                        ? "调整所选签名的宽度"
                        : "当前页面无法容纳最小 0.5 cm 的签名宽度"
            )
        }
        ToolbarItem(placement: .principal) {
            if let name = model.sourceURL?.lastPathComponent {
                Text(name).font(.headline)
            }
        }
        ToolbarItemGroup {
            Button { model.zoom = ZoomGeometry.stepped(model.zoom, by: -ZoomGeometry.step) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(Int((effectiveZoom * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 46)
            Button { model.zoom = ZoomGeometry.stepped(model.zoom, by: ZoomGeometry.step) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
        }
    }

    private func editSelectedPlacementWidth() {
        guard let placement = model.selectedPlacement,
              let asset = model.asset(for: placement) else { return }
        placementWidthEditor = PlacementWidthEditorRequest(
            placementID: placement.id,
            signatureName: asset.name,
            initialCentimeters: SignatureSizing.centimeters(fromPoints: placement.rect.width),
            maximumCentimeters: model.maximumPlacementWidthCentimeters(id: placement.id)
        )
    }
}

private struct PlacementWidthEditorRequest: Identifiable {
    var id: UUID { placementID }
    let placementID: UUID
    let signatureName: String
    let initialCentimeters: CGFloat
    let maximumCentimeters: CGFloat?
}

private struct PageSidebar: View {
    @EnvironmentObject private var model: DocumentModel

    var body: some View {
        ScrollViewReader { reader in
            List(selection: pageSelection) {
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
                        .id(index)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                model.requestPageNavigation(to: index)
                            }
                        )
                    }
                }
            }
            .onChange(of: model.currentPage) { pageIndex in
                reader.scrollTo(pageIndex, anchor: .center)
            }
        }
        .navigationTitle("页面")
    }

    private var pageSelection: Binding<Int> {
        Binding(
            get: { model.currentPage },
            set: { model.requestPageNavigation(to: $0) }
        )
    }
}

enum ContinuousPageGeometry {
    static func activePageIndex(
        viewport: CGRect,
        pageFrames: [Int: CGRect],
        pageCount: Int,
        keeping currentPage: Int?
    ) -> Int? {
        guard pageCount > 0, viewport.width > 0, viewport.height > 0,
              viewport.minY.isFinite, viewport.maxY.isFinite else { return nil }

        let validFrames = pageFrames.compactMap { pageIndex, frame -> (Int, CGRect)? in
            guard pageIndex >= 0, pageIndex < pageCount,
                  frame.width > 0, frame.height > 0,
                  frame.minY.isFinite, frame.maxY.isFinite else { return nil }
            return (pageIndex, frame)
        }
        let lastPageIndex = pageCount - 1
        let firstPageFrame = validFrames.first(where: { $0.0 == 0 })?.1
        let lastPageFrame = validFrames.first(where: { $0.0 == lastPageIndex })?.1
        let atDocumentTop = firstPageFrame.map { $0.minY >= viewport.minY } ?? false
        let atDocumentBottom = lastPageFrame.map { $0.maxY <= viewport.maxY } ?? false
        if atDocumentTop && atDocumentBottom,
           let currentPage,
           validFrames.contains(where: { $0.0 == currentPage }) {
            return currentPage
        }
        if atDocumentTop && !atDocumentBottom {
            return 0
        }
        if atDocumentBottom && !atDocumentTop {
            return lastPageIndex
        }

        let visibleFrames = validFrames.filter {
            $0.1.maxY > viewport.minY && $0.1.minY < viewport.maxY
        }
        let framesToRank = visibleFrames.isEmpty ? validFrames : visibleFrames
        let candidates = framesToRank.map { pageIndex, frame -> (Int, CGFloat) in
            let distance: CGFloat
            if viewport.midY < frame.minY {
                distance = frame.minY - viewport.midY
            } else if viewport.midY > frame.maxY {
                distance = viewport.midY - frame.maxY
            } else {
                distance = 0
            }
            return (pageIndex, distance)
        }
        guard let minimumDistance = candidates.map(\.1).min() else { return nil }
        let nearest = candidates.filter { abs($0.1 - minimumDistance) < 0.001 }
        if let currentPage, nearest.contains(where: { $0.0 == currentPage }) {
            return currentPage
        }
        return nearest.map(\.0).min()
    }
}

private enum ContinuousScrollLayout {
    static let coordinateSpaceName = "SignPDFContinuousScroll"
    static let pageVerticalPadding: CGFloat = 12
    static let documentVerticalPadding: CGFloat = 24
    static let horizontalMargin: CGFloat = 36

    static func contentWidth(viewportWidth: CGFloat, maximumPageWidth: CGFloat, zoom: CGFloat) -> CGFloat {
        max(viewportWidth, maximumPageWidth * zoom + horizontalMargin * 2)
    }
}

private struct PageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct PageFrameReporter: View {
    let pageIndex: Int

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: PageFramePreferenceKey.self,
                value: [
                    pageIndex: proxy.frame(in: .named(ContinuousScrollLayout.coordinateSpaceName))
                ]
            )
        }
    }
}

private struct SignatureSidebar: View {
    @EnvironmentObject private var model: DocumentModel
    @State private var assetPendingDeletion: SignatureAsset?
    @State private var assetPendingWidthEdit: SignatureAsset?

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
                                        Text("默认宽度 \(SignatureWidthText.string(from: asset.defaultWidthCentimeters)) cm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                                    Button("设置默认宽度…", systemImage: "ruler") {
                                        assetPendingWidthEdit = asset
                                    }
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
                                Button("设置默认宽度…") {
                                    assetPendingWidthEdit = asset
                                }
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
        .sheet(item: $assetPendingWidthEdit) { asset in
            SignatureWidthEditorSheet(
                title: "设置默认插入宽度",
                signatureName: asset.name,
                initialCentimeters: asset.defaultWidthCentimeters,
                explanation: "以后插入这个签名时会使用该宽度；文档中已有的实例不会改变。",
                actionTitle: "保存"
            ) { centimeters in
                model.updateDefaultWidth(for: asset, toCentimeters: centimeters)
            }
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

private struct SignatureWidthEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let signatureName: String
    let maximumCentimeters: CGFloat?
    let explanation: String
    let actionTitle: String
    let onCommit: (CGFloat) -> Bool

    @State private var widthText: String
    @State private var validationMessage: String?
    @FocusState private var widthIsFocused: Bool

    init(
        title: String,
        signatureName: String,
        initialCentimeters: CGFloat,
        maximumCentimeters: CGFloat? = nil,
        explanation: String,
        actionTitle: String,
        onCommit: @escaping (CGFloat) -> Bool
    ) {
        self.title = title
        self.signatureName = signatureName
        self.maximumCentimeters = maximumCentimeters
        self.explanation = explanation
        self.actionTitle = actionTitle
        self.onCommit = onCommit
        _widthText = State(initialValue: SignatureWidthText.string(from: initialCentimeters))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(signatureName)
                .font(.headline)
                .lineLimit(1)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let maximumCentimeters {
                Text("当前可设置的最大宽度约为 \(SignatureWidthText.string(from: maximumCentimeters)) cm。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("宽度")
                TextField("3.6", text: $widthText)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .focused($widthIsFocused)
                    .onSubmit(commit)
                Text("cm")
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, action: commit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 390)
        .onAppear {
            DispatchQueue.main.async {
                widthIsFocused = true
            }
        }
    }

    private func commit() {
        guard let centimeters = SignatureWidthText.centimeters(from: widthText) else {
            validationMessage = "请输入有效的宽度。"
            return
        }
        guard centimeters >= SignatureSizing.minimumWidthCentimeters,
              centimeters <= SignatureSizing.maximumWidthCentimeters else {
            validationMessage = "宽度必须在 0.5 到 100 cm 之间。"
            return
        }
        if let maximumCentimeters,
           centimeters > maximumCentimeters
            + SignatureSizing.widthComparisonToleranceCentimeters {
            validationMessage = "当前可设置的最大宽度约为 \(SignatureWidthText.string(from: maximumCentimeters)) cm。"
            return
        }
        validationMessage = nil
        if onCommit(centimeters) {
            dismiss()
        } else {
            validationMessage = "无法保存更改，请重试。"
        }
    }
}

enum SignatureWidthText {
    static func string(from centimeters: CGFloat, locale: Locale = .current) -> String {
        let formatter = formatter(locale: locale)
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: Double(centimeters)))
            ?? String(format: "%.3f", Double(centimeters))
    }

    static func centimeters(from text: String, locale: Locale = .current) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for candidateLocale in [locale, Locale(identifier: "en_US_POSIX")] {
            let formatter = formatter(locale: candidateLocale)

            var valueObject: AnyObject?
            let stringLength = (trimmed as NSString).length
            var parsedRange = NSRange(location: 0, length: stringLength)
            guard (try? formatter.getObjectValue(
                &valueObject,
                for: trimmed,
                range: &parsedRange
            )) != nil,
            parsedRange == NSRange(location: 0, length: stringLength),
            let number = valueObject as? NSNumber else { continue }
            let value = number.doubleValue
            guard value.isFinite, value > 0 else { continue }
            return CGFloat(value)
        }
        return nil
    }

    private static func formatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.isLenient = false
        return formatter
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
