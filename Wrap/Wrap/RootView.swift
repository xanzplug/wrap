import SwiftUI

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
            case .signedIn:
                ContentView()
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .task {
            if auth.state == .loading {
                await auth.restoreSession()
            }
        }
    }
}
