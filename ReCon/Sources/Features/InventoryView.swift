import SwiftUI
import QuickLook

struct InventoryView: View {
    @ObservedObject var app: AppContainer
    @State private var currentPath = "Inventory"
    @State private var pathStack: [String] = ["Inventory"]
    @State private var records: [InventoryRecord] = []
    @State private var errorText: String?
    @State private var loading = false
    @State private var backdropAccent: Color = .orange
    @State private var createFolderPrompt = false
    @State private var newFolderName = ""
    @State private var moveRecordTarget: InventoryRecord?
    @State private var showMoveSheet = false
    @State private var showLinkSourceSheet = false
    @State private var storageQuota: StorageQuota?
    @State private var photoViewerItem: InventoryPhotoItem?
    @State private var modelViewerItem: InventoryModelItem?
    @State private var previewItem: InventoryAssetPreviewItem?
    @State private var searchQuery = ""
    @State private var hiddenTypes: Set<String> = []
    @State private var sortMode: InventorySortMode = .aToZOwnFirst

    var body: some View {
        List {
            storageStatusCard
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if currentPath != "Inventory" {
                Button {
                    goUp()
                } label: {
                    Label("..", systemImage: "arrow.up.left")
                        .font(.headline)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(filteredSortedRecords) { record in
                Button {
                    Task { await openRecord(record) }
                } label: {
                    DynamicTintedRow(urlString: record.thumbnailUri.isEmpty ? record.id : record.thumbnailUri, environment: app.environment, fallback: .orange) {
                        HStack(spacing: 12) {
                            SharedThumbnailView(
                                urlString: record.thumbnailUri,
                                environment: app.environment,
                                size: 44,
                                fallbackSystemName: iconName(for: record)
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(RichTextFormatter.toAttributedString(record.name))
                                    .lineLimit(2)
                                Text(record.recordType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if isFolderLike(record) {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        moveRecordTarget = record
                        showMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "arrowshape.turn.up.right")
                    }
                    Button(role: .destructive) {
                        Task { await deleteRecord(record) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .overlay {
            if loading { ProgressView() }
            if filteredSortedRecords.isEmpty, !loading {
                ContentUnavailableView("Inventory", systemImage: "shippingbox", description: Text("No records loaded"))
            }
        }
        .searchable(text: $searchQuery, prompt: "Search inventory, tags, names")
        .reconListScreen(backdrop: .inventory, accent: backdropAccent)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(allRecordTypes, id: \.self) { type in
                        Button {
                            toggleTypeFilter(type)
                        } label: {
                            Label(type, systemImage: hiddenTypes.contains(type) ? "eye.slash" : "eye")
                        }
                    }
                    if !hiddenTypes.isEmpty {
                        Divider()
                        Button("Show All Types") {
                            hiddenTypes.removeAll()
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(InventorySortMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Divider()

                    Button {
                        createFolderPrompt = true
                    } label: {
                        Label("Create Folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        showLinkSourceSheet = true
                    } label: {
                        Label("Link Folder Here", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorText {
                Text(errorText).foregroundStyle(.red).padding(8)
            }
        }
        .navigationTitle(currentPath)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRoot() }
        .refreshable { await loadCurrent() }
        .alert("Create Folder", isPresented: $createFolderPrompt) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task { await createFolder() }
            }
        } message: {
            Text("New folder will be created in \(currentPath).")
        }
        .sheet(isPresented: $showMoveSheet) {
            if let moveRecordTarget {
                InventoryPathPickerSheet(app: app, title: "Move To...", initialPath: currentPath) { destinationPath in
                    Task { await moveRecord(moveRecordTarget, destinationPath: destinationPath) }
                }
            }
        }
        .sheet(isPresented: $showLinkSourceSheet) {
            InventoryFolderSourcePickerSheet(app: app) { sourceFolder in
                Task { await linkFolder(sourceFolder) }
            }
        }
        .sheet(item: $photoViewerItem) { item in
            InventoryPhotoViewer(item: item)
        }
        .sheet(item: $modelViewerItem) { item in
            InventoryModelViewer(item: item)
        }
        .sheet(item: $previewItem) { item in
            InventoryAssetPreviewSheet(item: item)
        }
    }

    private func loadRoot() async {
        pathStack = ["Inventory"]
        currentPath = "Inventory"
        await loadCurrent()
    }

    private func loadCurrent() async {
        guard app.auth.isAuthenticated else { return }
        loading = true
        defer { loading = false }

        do {
            async let recordsTask = app.repository.fetchInventory(auth: app.auth, path: currentPath)
            async let quotaTask = app.repository.fetchStorageQuota(auth: app.auth)
            records = try await recordsTask
            storageQuota = try? await quotaTask
            if let first = records.first {
                backdropAccent = StableTintPalette.color(for: first.thumbnailUri, fallback: .orange)
                if
                    let url = AssetURLResolver.resolveImageURL(first.thumbnailUri, environment: app.environment),
                    let dominant = await DominantColorPalette.color(for: url)
                {
                    backdropAccent = dominant
                }
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var storageStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.secondary)
                Text("Storage")
                    .font(.headline)
            }

            if let storageQuota {
                let fraction = storageQuota.fullQuotaBytes > 0
                    ? Double(storageQuota.usedBytes) / Double(storageQuota.fullQuotaBytes)
                    : 0
                ProgressView(value: min(max(fraction, 0), 1))
                    .tint(.cyan)
                Text("\(formatBytes(storageQuota.usedBytes)) / \(formatBytes(storageQuota.fullQuotaBytes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Storage usage unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .reconRowCard()
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .file)
    }

    private var filteredSortedRecords: [InventoryRecord] {
        let q = normalizedSearch(searchQuery)
        let filtered = records.filter { record in
            if hiddenTypes.contains(record.recordType.lowercased()) { return false }
            guard !q.isEmpty else { return true }
            let haystack = normalizedSearch("\(record.name) \(record.recordType) \(record.path)")
            return haystack.contains(q)
        }
        return filtered.sorted { lhs, rhs in
            sortMode.compare(lhs: lhs, rhs: rhs, isOwn: isOwnRecord)
        }
    }

    private var allRecordTypes: [String] {
        Array(Set(records.map { $0.recordType.lowercased() })).sorted()
    }

    private func toggleTypeFilter(_ type: String) {
        if hiddenTypes.contains(type) {
            hiddenTypes.remove(type)
        } else {
            hiddenTypes.insert(type)
        }
    }

    private func normalizedSearch(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isOwnRecord(_ record: InventoryRecord) -> Bool {
        record.path.lowercased().hasPrefix("inventory")
    }

    private func isFolderLike(_ record: InventoryRecord) -> Bool {
        let type = record.recordType.lowercased()
        return type == "directory" || type == "link"
    }

    private func iconName(for record: InventoryRecord) -> String {
        switch record.recordType.lowercased() {
        case "directory": return "folder"
        case "link": return "link"
        case "audio": return "waveform"
        case "texture": return "photo"
        default: return "shippingbox"
        }
    }

    private func goUp() {
        guard pathStack.count > 1 else { return }
        _ = pathStack.popLast()
        currentPath = pathStack.last ?? "Inventory"
        Task { await loadCurrent() }
    }

    private func openRecord(_ record: InventoryRecord) async {
        let type = record.recordType.lowercased()
        if type == "directory" {
            let nextPath = "\(record.path)\\\(record.name)"
            pathStack.append(nextPath)
            currentPath = nextPath
            await loadCurrent()
            return
        }

        if let target = parseResRecURI(record.assetUri) {
            do {
                let linked = try await app.repository.fetchInventoryRecord(auth: app.auth, ownerId: target.ownerId, recordId: target.recordId)
                await openResolvedRecord(linked, fallbackOwnerId: target.ownerId)
            } catch {
                errorText = error.localizedDescription
            }
            return
        }

        await openResolvedRecord(record, fallbackOwnerId: app.auth.userId)
    }

    private func openResolvedRecord(_ record: InventoryRecord, fallbackOwnerId: String) async {
        let type = record.recordType.lowercased()
        if type == "directory" {
            let nextPath = "\(record.path)\\\(record.name)"
            pathStack.append(nextPath)
            currentPath = nextPath
            await loadCurrent()
            return
        }

        if let target = parseResRecURI(record.assetUri) {
            do {
                let linked = try await app.repository.fetchInventoryRecord(auth: app.auth, ownerId: target.ownerId, recordId: target.recordId)
                await openResolvedRecord(linked, fallbackOwnerId: target.ownerId)
                return
            } catch {
                // Keep resolving as local content when target lookup fails.
            }
        }

        if let worldId = extractWorldId(from: record.assetUri)
            ?? (isWorldLike(type: type) ? (extractWorldId(from: record.id) ?? record.id) : nil) {
            let world = WorldRecord(
                id: worldId,
                ownerId: fallbackOwnerId,
                name: record.name,
                thumbnailUri: record.thumbnailUri,
                description: ""
            )
            app.openWorldInWorldsTab(world)
            return
        }

        if let sessionId = extractSessionId(from: record.assetUri)
            ?? (isSessionLike(type: type) ? (extractSessionId(from: record.id) ?? record.id) : nil) {
            app.openSessionInSessionsTab(sessionId)
            return
        }

        if isPhotoLike(type: type),
           let imageURL = resolvePhotoURL(record) {
            photoViewerItem = InventoryPhotoItem(title: record.name, imageURL: imageURL)
            return
        }

        if let modelURL = resolveModelURL(record) {
            modelViewerItem = InventoryModelItem(title: record.name, modelURL: modelURL)
            return
        }

        if let assetURL = AssetURLResolver.resolveMediaURL(record.assetUri, environment: app.environment)
            ?? AssetURLResolver.resolveImageURL(record.assetUri, environment: app.environment)
            ?? AssetURLResolver.resolveImageURL(record.thumbnailUri, environment: app.environment) {
            if !isSafePreviewAssetURL(assetURL) {
                errorText = "Unsupported object format for preview."
                return
            }
            previewItem = InventoryAssetPreviewItem(title: record.name, url: assetURL)
            return
        }

        errorText = "No preview available for this item."
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try await app.repository.createInventoryFolder(auth: app.auth, parentPath: currentPath, folderName: name)
            newFolderName = ""
            await loadCurrent()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func moveRecord(_ record: InventoryRecord, destinationPath: String) async {
        do {
            try await app.repository.moveInventoryRecord(auth: app.auth, record: record, destinationPath: destinationPath)
            moveRecordTarget = nil
            showMoveSheet = false
            await loadCurrent()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteRecord(_ record: InventoryRecord) async {
        do {
            try await app.repository.deleteInventoryRecord(auth: app.auth, recordId: record.id)
            await loadCurrent()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func linkFolder(_ source: InventoryRecord) async {
        do {
            try await app.repository.createFolderLink(auth: app.auth, sourceFolder: source, destinationPath: currentPath, linkName: nil)
            showLinkSourceSheet = false
            await loadCurrent()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func parseResRecURI(_ uri: String) -> (ownerId: String, recordId: String)? {
        guard uri.lowercased().hasPrefix("resrec:///") else { return nil }
        let body = uri.replacingOccurrences(of: "resrec:///", with: "")
        let comps = body.split(separator: "/")
        guard comps.count >= 2 else { return nil }
        return (String(comps[0]), String(comps[1]))
    }

    private func isPhotoLike(type: String) -> Bool {
        type == "texture" || type == "image" || type == "photo"
    }

    private func isWorldLike(type: String) -> Bool {
        let normalized = type.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "world"
            || normalized == "world orb"
            || normalized == "worldorb"
            || normalized == "world link"
    }

    private func isSessionLike(type: String) -> Bool {
        let normalized = type.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "session"
            || normalized == "session orb"
            || normalized == "sessionorb"
            || normalized == "session invite"
    }

    private func extractWorldId(from raw: String) -> String? {
        guard let range = raw.range(of: "R-[A-Za-z0-9\\-]+", options: .regularExpression) else { return nil }
        return String(raw[range])
    }

    private func extractSessionId(from raw: String) -> String? {
        if let range = raw.range(of: "S-[A-Za-z0-9\\-]+", options: .regularExpression) {
            return String(raw[range])
        }
        if let uuidRange = raw.range(of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", options: .regularExpression) {
            return String(raw[uuidRange])
        }
        return nil
    }

    private func resolvePhotoURL(_ record: InventoryRecord) -> URL? {
        AssetURLResolver.resolveImageURL(record.thumbnailUri, environment: app.environment)
            ?? AssetURLResolver.resolveImageURL(record.assetUri, environment: app.environment)
            ?? AssetURLResolver.resolveMediaURL(record.assetUri, environment: app.environment)
    }

    private func resolveModelURL(_ record: InventoryRecord) -> URL? {
        let type = record.recordType.lowercased()
        if !(type.contains("model") || type.contains("object") || type.contains("mesh") || type.contains("3d")) {
            return nil
        }

        if let fromAsset = AssetURLResolver.resolveMediaURL(record.assetUri, environment: app.environment),
           isModelAssetURL(fromAsset) {
            return fromAsset
        }
        if let fromEmbedded = parseEmbeddedAssetURL(fromDataURI: record.assetUri),
           isModelAssetURL(fromEmbedded) {
            return fromEmbedded
        }
        if let fromThumb = AssetURLResolver.resolveMediaURL(record.thumbnailUri, environment: app.environment),
           isModelAssetURL(fromThumb) {
            return fromThumb
        }
        return nil
    }

    private func parseEmbeddedAssetURL(fromDataURI raw: String) -> URL? {
        guard raw.lowercased().hasPrefix("data:"),
              let comma = raw.firstIndex(of: ",")
        else { return nil }

        let metadata = String(raw[..<comma]).lowercased()
        let payloadStart = raw.index(after: comma)
        let payload = String(raw[payloadStart...])
        let text: String
        if metadata.contains(";base64") {
            guard let data = Data(base64Encoded: payload), let decoded = String(data: data, encoding: .utf8) else {
                return nil
            }
            text = decoded
        } else {
            text = payload.removingPercentEncoding ?? payload
        }

        let patterns = [
            "resdb:///[-A-Za-z0-9_./]+",
            "https?://[^\\s\\\"]+"
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let candidate = String(text[range])
                if candidate.lowercased().hasPrefix("resdb:///") {
                    return AssetURLResolver.resolveMediaURL(candidate, environment: app.environment)
                }
                if let url = URL(string: candidate) {
                    return url
                }
            }
        }
        return nil
    }

    private func isModelAssetURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["usdz", "reality", "obj", "dae", "scn", "ply", "stl", "glb", "gltf", "fbx"].contains(ext)
    }

    private func isSafePreviewAssetURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        let blocked = ["txt", "json", "xml", "csv", "md", "html", "htm", "yaml", "yml"]
        return !blocked.contains(ext)
    }
}

private struct InventoryPhotoItem: Identifiable {
    let id = UUID()
    let title: String
    let imageURL: URL
}

private struct InventoryAssetPreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct InventoryModelItem: Identifiable {
    let id = UUID()
    let title: String
    let modelURL: URL
}

private struct InventoryPhotoViewer: View {
    let item: InventoryPhotoItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: item.imageURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                }
                .padding(12)
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct InventoryAssetPreviewSheet: View {
    let item: InventoryAssetPreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading preview...")
                } else if let localURL {
                    QuickLookPreview(url: localURL)
                } else if let loadError {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    Text("No preview available.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadPreviewIfNeeded() }
        }
    }

    private func loadPreviewIfNeeded() async {
        if item.url.isFileURL {
            localURL = item.url
            return
        }
        loading = true
        defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: item.url)
            let ext = item.url.pathExtension.isEmpty ? "bin" : item.url.pathExtension
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).\(ext)")
            try data.write(to: tmp)
            localURL = tmp
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct InventoryModelViewer: View {
    let item: InventoryModelItem
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading 3D model...")
                } else if let localURL {
                    QuickLookPreview(url: localURL)
                } else if let loadError {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    Text("No 3D preview available.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadPreviewIfNeeded() }
        }
    }

    private func loadPreviewIfNeeded() async {
        if item.modelURL.isFileURL {
            localURL = item.modelURL
            return
        }
        loading = true
        defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: item.modelURL)
            let ext = item.modelURL.pathExtension.isEmpty ? "bin" : item.modelURL.pathExtension
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString).\(ext)")
            try data.write(to: tmp)
            localURL = tmp
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private enum InventorySortMode: String, CaseIterable, Identifiable {
    case aToZOwnFirst
    case aToZ
    case zToA
    case typeThenName

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aToZOwnFirst: return "A-Z (Own first)"
        case .aToZ: return "A-Z"
        case .zToA: return "Z-A"
        case .typeThenName: return "Type + Name"
        }
    }

    func compare(lhs: InventoryRecord, rhs: InventoryRecord, isOwn: (InventoryRecord) -> Bool) -> Bool {
        switch self {
        case .aToZOwnFirst:
            let lhsOwn = isOwn(lhs)
            let rhsOwn = isOwn(rhs)
            if lhsOwn != rhsOwn { return lhsOwn && !rhsOwn }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .aToZ:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .zToA:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
        case .typeThenName:
            let typeCompare = lhs.recordType.localizedCaseInsensitiveCompare(rhs.recordType)
            if typeCompare != .orderedSame {
                return typeCompare == .orderedAscending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private struct InventoryPathPickerSheet: View {
    @ObservedObject var app: AppContainer
    let title: String
    let initialPath: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPath: String = "Inventory"
    @State private var stack: [String] = ["Inventory"]
    @State private var folders: [InventoryRecord] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Current") { Text(currentPath).font(.footnote).foregroundStyle(.secondary) }
                if currentPath != "Inventory" {
                    Button("..") { goUp() }
                }
                ForEach(folders) { folder in
                    Button {
                        enter(folder)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(folder.name)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                }
                if loading { ProgressView() }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") {
                        onPick(currentPath)
                        dismiss()
                    }
                }
            }
            .task {
                currentPath = initialPath
                stack = [initialPath]
                await loadFolders()
            }
        }
    }

    private func enter(_ folder: InventoryRecord) {
        let next = "\(folder.path)\\\(folder.name)"
        currentPath = next
        stack.append(next)
        Task { await loadFolders() }
    }

    private func goUp() {
        guard stack.count > 1 else { return }
        _ = stack.popLast()
        currentPath = stack.last ?? "Inventory"
        Task { await loadFolders() }
    }

    private func loadFolders() async {
        guard app.auth.isAuthenticated else { return }
        loading = true
        defer { loading = false }
        let all = (try? await app.repository.fetchInventory(auth: app.auth, path: currentPath)) ?? []
        folders = all.filter { $0.recordType.lowercased() == "directory" }
    }
}

private struct InventoryFolderSourcePickerSheet: View {
    @ObservedObject var app: AppContainer
    let onPickSource: (InventoryRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPath = "Inventory"
    @State private var stack: [String] = ["Inventory"]
    @State private var folders: [InventoryRecord] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Browse Folders") {
                    Text(currentPath).font(.footnote).foregroundStyle(.secondary)
                }
                if currentPath != "Inventory" {
                    Button("..") { goUp() }
                }
                ForEach(folders) { folder in
                    Menu {
                        Button("Select This Folder") {
                            onPickSource(folder)
                            dismiss()
                        }
                        Button("Open") {
                            enter(folder)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(folder.name)
                            Spacer()
                            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select Folder To Link")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
            .task { await loadFolders() }
        }
    }

    private func enter(_ folder: InventoryRecord) {
        let next = "\(folder.path)\\\(folder.name)"
        currentPath = next
        stack.append(next)
        Task { await loadFolders() }
    }

    private func goUp() {
        guard stack.count > 1 else { return }
        _ = stack.popLast()
        currentPath = stack.last ?? "Inventory"
        Task { await loadFolders() }
    }

    private func loadFolders() async {
        guard app.auth.isAuthenticated else { return }
        let all = (try? await app.repository.fetchInventory(auth: app.auth, path: currentPath)) ?? []
        folders = all.filter { $0.recordType.lowercased() == "directory" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
