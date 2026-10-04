import SwiftUI

struct DeleteProjectPopup: View {
    let project: Project
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete project?")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(project.displayName) will be removed from Wrap on all your Macs.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.wrapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                CloseSquareButton(action: cancel)
            }

            HStack(spacing: 12) {
                InfoTile(icon: "checklist", value: "\(project.shots.count)",
                         label: project.shots.count == 1 ? "shot" : "shots")
                InfoTile(icon: "square.stack", value: "\(project.workspaceItems.count)",
                         label: project.workspaceItems.count == 1 ? "workspace app" : "workspace apps")
            }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                Text("Your files on disk stay where they are.")
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.wrapSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06)))

            HStack(spacing: 10) {
                Button("Cancel", action: cancel)
                    .buttonStyle(PopupPillStyle(kind: .outline))
                    .keyboardShortcut(.cancelAction)
                Button(action: confirm) {
                    Label("Delete Project", systemImage: "trash")
                }
                .buttonStyle(PopupPillStyle(kind: .destructive))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(26)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.wrapCard))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }
}

private struct InfoTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.wrapSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wrapSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

private struct CloseSquareButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? .white : Color.wrapSecondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hovering ? 0.08 : 0.02)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(hovering ? 0.25 : 0.12)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct PopupPillStyle: ButtonStyle {
    enum Kind { case outline, destructive }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        PillBody(kind: kind, configuration: configuration)
    }

    private struct PillBody: View {
        let kind: Kind
        let configuration: Configuration
        @State private var hovering = false

        private let red = Color(red: 1.0, green: 0.36, blue: 0.36)

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(kind == .destructive ? .white : Color.white.opacity(0.85))
                .padding(.horizontal, 20)
                .frame(height: 38)
                .background {
                    Capsule().fill(kind == .destructive
                                   ? red.opacity(hovering ? 1 : 0.88)
                                   : Color.black.opacity(hovering ? 0.5 : 0.3))
                }
                .overlay {
                    if kind == .outline {
                        Capsule().strokeBorder(Color.white.opacity(hovering ? 0.3 : 0.14))
                    }
                }
                .shadow(color: kind == .destructive ? red.opacity(hovering ? 0.45 : 0) : .clear, radius: 14)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
