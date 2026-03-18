import SwiftUI

struct RootView: View {
    @ObservedObject var app: AppContainer

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ReConBackdrop()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()

                if !app.startupComplete {
                    ProgressView("Loading")
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if app.auth.isAuthenticated {
                    MainTabView(app: app)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    LoginView(app: app)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            if !app.startupComplete {
                await app.bootstrap()
            }
        }
    }
}
