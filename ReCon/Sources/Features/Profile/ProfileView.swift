import SwiftUI

struct ProfileView: View {
    @Environment private var app: AppContainer

    @State private var quota: StorageQuota?
    @State private var errorText: String?

    var body: some View {
        List {
            if let quota {
                Text("Storage")
                let usedGB = Double(quota.usedBytes) * 9.3132257461548e-10
                let maxGB = Double(quota.fullQuotaBytes) * 9.3132257461548e-10
                ProgressView(value: quota.fullQuotaBytes == 0 ? 0 : Double(quota.usedBytes) / Double(quota.fullQuotaBytes))
                Text(String(format: "%.2f / %.2f GB", usedGB, maxGB))
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("My Profile")
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
