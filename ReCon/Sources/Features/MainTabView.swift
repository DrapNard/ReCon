import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct MainTabView: View {
    @ObservedObject var app: AppContainer

    var body: some View {
        ZStack {
            ReConBackdrop()
                .ignoresSafeArea()

            TabView(selection: $app.selectedTab) {
                NavigationStack {
                    FriendsView(app: app)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.clear)
                }
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(AppTab.chat)

                NavigationStack {
                    SessionsView(app: app)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.clear)
                }
                .tabItem { Label("Sessions", systemImage: "person.3") }
                .tag(AppTab.sessions)

                NavigationStack {
                    WorldsView(app: app)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.clear)
                }
                .tabItem { Label("Worlds", systemImage: "globe") }
                .tag(AppTab.worlds)

                NavigationStack {
                    InventoryView(app: app)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.clear)
                }
                .tabItem { Label("Inventory", systemImage: "shippingbox") }
                .tag(AppTab.inventory)

                NavigationStack {
                    SettingsView(app: app)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.clear)
                }
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.48, dampingFraction: 0.85), value: app.selectedTab)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
            .background(Color.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: [.top, .leading, .trailing])
        .sheet(item: $app.pendingInventoryWorldSave) { world in
            InventoryWorldSaveSheet(app: app, world: world)
        }
        .safeAreaInset(edge: .bottom) {
            if let text = app.inventoryBannerText {
                Text(text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        await MainActor.run {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                app.inventoryBannerText = nil
                            }
                        }
                    }
            }
        }
    }
}

struct InventoryWorldSaveSheet: View {
    @ObservedObject var app: AppContainer
    let world: WorldRecord

    @Environment(\.dismiss) private var dismiss
    @State private var currentPath: String = "Inventory"
    @State private var folderStack: [String] = ["Inventory"]
    @State private var folders: [InventoryRecord] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var creatingFolder = false
    @State private var newFolderName = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                DynamicTintedRow(urlString: world.thumbnailUri, environment: app.environment, fallback: .orange) {
                    HStack(spacing: 10) {
                        SharedThumbnailView(urlString: world.thumbnailUri, environment: app.environment, size: 42, fallbackSystemName: "globe")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Save World")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(RichTextFormatter.toAttributedString(world.name))
                                .lineLimit(2)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section("Current Folder") {
                    Text(currentPath)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !folderStack.isEmpty && currentPath != "Inventory" {
                    Button {
                        goUp()
                    } label: {
                        Label("..", systemImage: "arrow.up.left")
                    }
                }

                Section("Folders") {
                    if loading {
                        HStack {
                            ProgressView()
                            Text("Loading folders...")
                                .foregroundStyle(.secondary)
                        }
                    } else if folders.isEmpty {
                        Text("No subfolders")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(folders) { folder in
                            Button {
                                enter(folder: folder)
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(folder.name)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save To Inventory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        app.finishInventoryWorldSave()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        creatingFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .disabled(saving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await saveHere() }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Label("Save Here", systemImage: "star.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
                }
            }
            .alert("Create Folder", isPresented: $creatingFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    Task { await createFolder() }
                }
            } message: {
                Text("New folder will be created in \(currentPath).")
            }
            .safeAreaInset(edge: .bottom) {
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
            .task { await loadFolders() }
        }
    }

    private func enter(folder: InventoryRecord) {
        let next = "\(folder.path)\\\(folder.name)"
        currentPath = next
        folderStack.append(next)
        Task { await loadFolders() }
    }

    private func goUp() {
        guard folderStack.count > 1 else { return }
        _ = folderStack.popLast()
        currentPath = folderStack.last ?? "Inventory"
        Task { await loadFolders() }
    }

    private func loadFolders() async {
        guard app.auth.isAuthenticated else { return }
        loading = true
        defer { loading = false }
        do {
            let records = try await app.repository.fetchInventory(auth: app.auth, path: currentPath)
            folders = records.filter { $0.recordType.lowercased() == "directory" }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try await app.repository.createInventoryFolder(auth: app.auth, parentPath: currentPath, folderName: name)
            newFolderName = ""
            errorText = nil
            await loadFolders()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveHere() async {
        guard app.auth.isAuthenticated else { return }
        saving = true
        defer { saving = false }
        do {
            try await app.repository.saveWorldToInventory(auth: app.auth, world: world, folderPath: currentPath)
            app.finishInventoryWorldSave(message: "Saved to \(currentPath).")
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct SharedThumbnailView: View {
    let urlString: String
    let environment: AppEnvironment
    let size: CGFloat
    let fallbackSystemName: String

    var body: some View {
        if let url = AssetURLResolver.resolveImageURL(urlString, environment: environment) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.gray.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: fallbackSystemName)
                    .foregroundStyle(.secondary)
            }
    }
}

struct DynamicTintedRow<Content: View>: View {
    let urlString: String
    let environment: AppEnvironment
    let fallback: Color
    let uniformHeight: CGFloat?
    @ViewBuilder let content: () -> Content
    @State private var color: Color
    @State private var isVisible = false

    init(
        urlString: String,
        environment: AppEnvironment,
        fallback: Color = .accentColor,
        uniformHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.urlString = urlString
        self.environment = environment
        self.fallback = fallback
        self.uniformHeight = uniformHeight
        self.content = content
        _color = State(initialValue: fallback)
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: uniformHeight, maxHeight: uniformHeight, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(color.opacity(0.24), lineWidth: 1)
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.96)
            .offset(y: isVisible ? 0 : 10)
            .task(id: urlString) {
                refreshColor()
            }
            .onAppear {
                guard !isVisible else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                    isVisible = true
                }
            }
            .animation(.easeInOut(duration: 0.4), value: color)
    }

    private func refreshColor() {
        // Avoid extra network fetch per row; use a stable tint derived from the resource key.
        color = StableTintPalette.color(for: urlString, fallback: fallback)
    }
}

struct ReConBackdrop: View {
    let style: ReConBackdropStyle
    @Environment(\.colorScheme) private var colorScheme

    init(style: ReConBackdropStyle = .default) {
        self.style = style
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let t = timeline.date.timeIntervalSinceReferenceDate
                let x1 = (sin(t * 0.18) + 1) * 0.5
                let y1 = (cos(t * 0.15) + 1) * 0.5
                let x2 = (sin(t * 0.12 + .pi * 0.4) + 1) * 0.5
                let y2 = (cos(t * 0.17 + .pi * 0.6) + 1) * 0.5

                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colors.last?.opacity(0.40) ?? .blue.opacity(0.4), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: size.width * 0.62
                            )
                        )
                        .frame(width: size.width * 1.05, height: size.width * 1.05)
                        .position(x: size.width * x1, y: size.height * y1)
                        .blur(radius: 36)
                        .blendMode(.screen)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colors.first?.opacity(0.35) ?? .cyan.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: size.width * 0.52
                            )
                        )
                        .frame(width: size.width * 0.92, height: size.width * 0.92)
                        .position(x: size.width * x2, y: size.height * y2)
                        .blur(radius: 30)
                        .blendMode(.plusLighter)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.07), .clear, .white.opacity(0.04)],
                                startPoint: UnitPoint(x: x2, y: 0),
                                endPoint: UnitPoint(x: 1 - x1 * 0.5, y: 1)
                            )
                        )
                        .blendMode(.softLight)
                        .opacity(0.55)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        if colorScheme != .dark {
            return [
                Color(red: 0.88, green: 0.94, blue: 0.99),
                Color(red: 0.84, green: 0.92, blue: 0.99),
                Color(red: 0.90, green: 0.96, blue: 1.0)
            ]
        }

        switch style {
        case .chat:
            return [
                Color(red: 0.03, green: 0.10, blue: 0.22),
                Color(red: 0.06, green: 0.18, blue: 0.34),
                Color(red: 0.08, green: 0.24, blue: 0.42)
            ]
        case .sessions:
            return [
                Color(red: 0.03, green: 0.14, blue: 0.12),
                Color(red: 0.05, green: 0.22, blue: 0.17),
                Color(red: 0.08, green: 0.28, blue: 0.20)
            ]
        case .worlds:
            return [
                Color(red: 0.10, green: 0.08, blue: 0.24),
                Color(red: 0.17, green: 0.13, blue: 0.35),
                Color(red: 0.24, green: 0.18, blue: 0.42)
            ]
        case .inventory:
            return [
                Color(red: 0.18, green: 0.11, blue: 0.04),
                Color(red: 0.28, green: 0.18, blue: 0.07),
                Color(red: 0.36, green: 0.23, blue: 0.09)
            ]
        case .default:
            return [
                Color(red: 0.05, green: 0.09, blue: 0.20),
                Color(red: 0.07, green: 0.15, blue: 0.30),
                Color(red: 0.11, green: 0.22, blue: 0.42)
            ]
        }
    }
}

enum ReConBackdropStyle {
    case `default`
    case chat
    case sessions
    case worlds
    case inventory
}

extension View {
    func reconListScreen(backdrop: ReConBackdropStyle = .default, accent: Color? = nil) -> some View {
        ZStack {
            ReConBackdrop(style: backdrop)
                .ignoresSafeArea()
            if let accent {
                LinearGradient(
                    colors: [accent.opacity(0.62), accent.opacity(0.26), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            self
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    func reconRowCard() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .modifier(ReconPopInModifier())
    }
}

private struct ReconPopInModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                guard !appeared else { return }
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                    appeared = true
                }
            }
    }
}


enum DominantColorPalette {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func color(for url: URL) async -> Color? {
        if let cached = await DominantColorCache.shared.get(for: url.absoluteString) {
            return Color(red: cached.r, green: cached.g, blue: cached.b)
        }
        if await DominantColorCache.shared.isBackedOff(for: url.absoluteString) {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiColor = extractUIColor(from: data) else { return nil }
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 1
            guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
                return Color(uiColor: uiColor)
            }
            await DominantColorCache.shared.set(RGBColor(r: r, g: g, b: b), for: url.absoluteString)
            return Color(uiColor: uiColor)
        } catch {
            await DominantColorCache.shared.setBackoff(for: url.absoluteString, seconds: 300)
            return nil
        }
    }

    private static func extractUIColor(from data: Data) -> UIColor? {
        guard let input = CIImage(data: data) else { return nil }
        let extent = input.extent
        guard !extent.isEmpty else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = extent
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = CGFloat(bitmap[0]) / 255
        let g = CGFloat(bitmap[1]) / 255
        let b = CGFloat(bitmap[2]) / 255
        let base = UIColor(red: r, green: g, blue: b, alpha: 1)

        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var alpha: CGFloat = 1
        if base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha) {
            return UIColor(hue: hue, saturation: min(max(sat, 0.35), 0.85), brightness: min(max(bri, 0.55), 0.9), alpha: 1)
        }
        return base
    }
}

actor DominantColorCache {
    static let shared = DominantColorCache()
    private var colors: [String: RGBColor] = [:]
    private var backoffUntil: [String: Date] = [:]

    func get(for key: String) -> RGBColor? {
        colors[key]
    }

    func set(_ color: RGBColor, for key: String) {
        colors[key] = color
        backoffUntil[key] = nil
    }

    func setBackoff(for key: String, seconds: TimeInterval) {
        backoffUntil[key] = Date().addingTimeInterval(seconds)
    }

    func isBackedOff(for key: String) -> Bool {
        guard let until = backoffUntil[key] else { return false }
        if until > Date() { return true }
        backoffUntil[key] = nil
        return false
    }
}

struct RGBColor: Sendable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
}

enum StableTintPalette {
    static func color(for key: String, fallback: Color) -> Color {
        guard !key.isEmpty else { return fallback }
        let value = fnv1a(key)
        let hue = Double(value % 360) / 360.0
        let saturation = 0.50 + Double((value >> 8) % 20) / 100.0
        let brightness = 0.68 + Double((value >> 16) % 14) / 100.0
        return Color(hue: hue, saturation: min(saturation, 0.72), brightness: min(brightness, 0.85))
    }

    private static func fnv1a(_ string: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return hash
    }
}
