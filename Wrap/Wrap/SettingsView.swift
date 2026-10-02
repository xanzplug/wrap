import SwiftUI

/// The Settings page: account, reminders and app updates.
struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("displayName") private var displayName = WrapUser.defaultName
    @AppStorage(ShootReminders.enabledKey) private var remindersOn = true

    private var updater: AppUpdater { AppUpdater.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Heading("Settings")
                    .padding(.top, 24)

                section("Account") {
                    row("Your name", detail: "Shown in the greeting on your dashboard.") {
                        TextField("Name", text: $displayName)
                            .textFieldStyle(WrapFieldStyle())
                            .frame(width: 240)
                    }
                    divider
                    row("Email", detail: auth.account?.email ?? "Not signed in") {
                        Button("Sign Out") {
                            Task { await auth.signOut() }
                        }
                        .buttonStyle(.wrapSecondary)
                    }
                    divider
                    row("Sync", detail: syncDetail) {
                        Button("Sync Now") {
                            Task { await SyncEngine.shared.syncNow() }
                        }
                        .buttonStyle(.wrapSecondary)
                    }
                }

                section("Reminders") {
                    row("Shoot reminders",
                        detail: "A notification the evening before each shoot at 6 PM, and 2 hours before it starts.") {
                        Toggle("", isOn: $remindersOn)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                section("Updates") {
                    row("Wrap \(AppUpdater.versionText.replacingOccurrences(of: "Version ", with: ""))",
                        detail: lastCheckedText) {
                        Button("Check for Updates") {
                            updater.checkForUpdates()
                        }
                        .buttonStyle(.wrapPrimary)
                        .disabled(!updater.canCheck)
                    }
                    divider
                    row("Check automatically", detail: "Looks for a new version once a day and lets you know.") {
                        Toggle("", isOn: Binding(
                            get: { updater.checksAutomatically },
                            set: { updater.checksAutomatically = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title)
            VStack(spacing: 0) {
                content()
            }
            .wrapCard(padding: 0)
        }
    }

    private func row<Control: View>(_ title: String, detail: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wrapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle().fill(Color.wrapBorder).frame(height: 1)
    }

    private var syncDetail: String {
        switch SyncEngine.shared.status {
        case .idle: "Your projects sync across your Macs."
        case .syncing: "Syncing…"
        case .synced(let date): "Last synced \(date.formatted(date: .omitted, time: .shortened))."
        case .failed(let message): "Sync failed: \(message)"
        }
    }

    private var lastCheckedText: String {
        guard let date = updater.lastChecked else { return "Not checked for updates yet." }
        return "Last checked \(date.formatted(.relative(presentation: .named)))."
    }
}
