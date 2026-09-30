import SwiftUI
import SwiftData

/// Shows the sign-in screen until someone is logged in, then the app.
struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.wrapBackground)
            case .signedOut:
                AuthView()
            case .signedIn(let account):
                // Each account has its own projects.
                ContentView()
                    .modelContainer(LibraryStore.container(for: account.id))
                    .id(account.id)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .task {
            if auth.state == .loading {
                await auth.restoreSession()
            }
        }
        // Start syncing when someone logs in; stop when they log out.
        .task(id: auth.account?.id) {
            if let account = auth.account {
                SyncEngine.shared.start(
                    accountID: account.id,
                    container: LibraryStore.container(for: account.id),
                    auth: auth
                )
            } else {
                SyncEngine.shared.stop()
            }
        }
    }
}
