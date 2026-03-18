import SwiftUI

struct ProfileView: View {
    @ObservedObject var app: AppContainer

    @State private var quota: StorageQuota?
    @State private var errorText: String?

    var body: some View {
        List {
            if let quota {
                let usedGB = Double(quota.usedBytes) * 9.3132257461548e-10
                let maxGB = Double(quota.fullQuotaBytes) * 9.3132257461548e-10
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage")
                        .font(.headline)
                    ProgressView(value: quota.fullQuotaBytes == 0 ? 0 : Double(quota.usedBytes) / Double(quota.fullQuotaBytes))
                    Text(String(format: "%.2f / %.2f GB", usedGB, maxGB))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .reconRowCard()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .reconRowCard()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ProgressView()
            }
        }
        .reconListScreen()
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            quota = try await app.repository.fetchStorageQuota(auth: app.auth)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
