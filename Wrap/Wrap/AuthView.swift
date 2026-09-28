import SwiftUI

/// The sign-in screen: log in, sign up, or reset a password.
struct AuthView: View {
    @Environment(AuthService.self) private var auth

    enum Mode { case logIn, signUp, reset }

    @State private var mode: Mode = .logIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var notice: String?

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image("WrapLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
                Text("wrap")
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 14)
            Rectangle().fill(Color.wrapBorder).frame(height: 1)

            Spacer()
            form
                .frame(width: 380)
            Spacer()
            Spacer()
        }
        .background(Color.wrapBackground)
        .frame(minWidth: 900, minHeight: 640)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text(titleLines.0).foregroundStyle(.white)
                Text(titleLines.1).foregroundStyle(Color.wrapSecondary)
            }
            .font(.system(size: 40, weight: .medium))
            .tracking(-1.2)
            .padding(.bottom, 8)

            if !auth.isConfigured {
                HintText("Accounts aren't connected yet. Add your Supabase project URL and key in SupabaseConfig.swift.")
            }

            if mode != .reset {
                HStack(spacing: 24) {
                    modeTab("Log in", .logIn)
                    modeTab("Sign up", .signUp)
                }
            }

            VStack(spacing: 10) {
                if mode == .signUp {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                }
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                if mode != .reset {
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .onSubmit(submit)
                }
            }
            .textFieldStyle(WrapFieldStyle())

            if mode == .signUp {
                HintText("Passwords need at least 6 characters.")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1, green: 0.47, blue: 0.47))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView().controlSize(.small)
                    }
                    Text(buttonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.wrapPrimary)
            .disabled(!canSubmit || busy)
            .keyboardShortcut(.defaultAction)

            HStack {
                switch mode {
                case .logIn:
                    link("Forgot password?") { switchTo(.reset) }
                case .signUp:
                    HintText("By signing up you get a Wrap account for this app.")
                case .reset:
                    link("Back to log in") { switchTo(.logIn) }
                }
            }
        }
    }

    // MARK: Pieces

    private var titleLines: (String, String) {
        switch mode {
        case .logIn: ("Welcome back,", "log in to Wrap.")
        case .signUp: ("Create your", "Wrap account.")
        case .reset: ("Reset your", "password.")
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .logIn: "Log in"
        case .signUp: "Create account"
        case .reset: "Send reset link"
        }
    }

    private var canSubmit: Bool {
        guard trimmedEmail.contains("@") else { return false }
        switch mode {
        case .logIn: return !password.isEmpty
        case .signUp: return password.count >= 6 && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .reset: return true
        }
    }

    private func modeTab(_ title: String, _ target: Mode) -> some View {
        Button(title) { switchTo(target) }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(mode == target ? Color.white : Color.wrapSecondary)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color.wrapSecondary)
            .underline()
    }

    private func switchTo(_ newMode: Mode) {
        mode = newMode
        errorMessage = nil
        notice = nil
    }

    // MARK: Submit

    private func submit() {
        guard canSubmit, !busy else { return }
        busy = true
        errorMessage = nil
        notice = nil
        Task {
            defer { busy = false }
            do {
                switch mode {
                case .logIn:
                    try await auth.signIn(email: trimmedEmail, password: password)
                case .signUp:
                    let result = try await auth.signUp(
                        name: name.trimmingCharacters(in: .whitespaces),
                        email: trimmedEmail,
                        password: password
                    )
                    if result == .checkEmail {
                        mode = .logIn
                        password = ""
                        notice = "Almost done. Check your inbox to confirm your email, then log in."
                    }
                case .reset:
                    try await auth.sendPasswordReset(email: trimmedEmail)
                    notice = "If there's an account for that email, a reset link is on its way."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
