import SwiftUI

struct InventoryView: View {
    @ObservedObject var app: AppContainer
    @State private var records: [InventoryRecord] = []
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        List(records) { record in
            HStack(spacing: 12) {
                SharedThumbnailView(urlString: record.thumbnailUri, environment: app.environment, size: 44, fallbackSystemName: "shippingbox")
                VStack(alignment: .leading) {
                    Text(RichTextFormatter.toAttributedString(record.name))
                        .lineLimit(2)
                    Text(record.recordType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if loading { ProgressView() }
            if records.isEmpty, !loading {
                ContentUnavailableView("Inventory", systemImage: "shippingbox", description: Text("No records loaded"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorText {
                Text(errorText).foregroundStyle(.red).padding(8)
            }
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRoot() }
        .refreshable { await loadRoot() }
    }

    private func loadRoot() async {
        guard app.auth.isAuthenticated else { return }
        loading = true
        defer { loading = false }

        do {
            records = try await app.repository.fetchInventory(auth: app.auth, path: "Inventory")
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
