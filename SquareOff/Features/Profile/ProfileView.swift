import SwiftUI

/// Guest-only for v1: a guest card, the feel settings, and a preview of the sign-in screen.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("musicEnabled") private var musicEnabled = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("starsEnabled") private var starsEnabled = true
    @State private var isSignInPresented = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Text(String(app.account.displayName.prefix(1)).uppercased())
                        .font(.title.weight(.heavy))
                        .frame(width: 60, height: 60)
                        .background(Color(hex: Theme.playerColors[0]), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.account.displayName).font(.title3.bold())
                        Text(app.account == .guest ? "Playing as a guest on this device" : "Signed in")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
                Button("Sign in (preview)") { isSignInPresented = true }
            }

            Section("Stats") {
                LabeledContent("Games", value: "—")
                LabeledContent("Win rate", value: "—")
                LabeledContent("Best turn", value: "—")
                Text("Stats and replays arrive with accounts.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section("Settings") {
                Toggle("Sound effects", isOn: $soundEnabled)
                Toggle("Music", isOn: $musicEnabled)
                Toggle("Haptics", isOn: $hapticsEnabled)
                Toggle("Stars background", isOn: $starsEnabled)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Profile")
        .sheet(isPresented: $isSignInPresented) { SignInView() }
        .onAppear {
            if app.pendingSignIn {
                app.pendingSignIn = false
                isSignInPresented = true
            }
        }
    }
}

/// Static mockup of the web's login page. Nothing here signs in: every button explains that
/// accounts aren't in this build. Guest play needs no account.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var comingSoon: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email or username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    Button { comingSoon = "Sign in" } label: {
                        Text("Sign in").bold()
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                }

                Section {
                    socialButton("Sign in with Apple", background: .white, foreground: .black) {
                        Image(systemName: "apple.logo")
                    }
                    socialButton("Continue with Google", background: Theme.surfaceRaised, foreground: .white) {
                        Image(systemName: "g.circle.fill")
                    }
                    socialButton("Continue with GitHub", background: Theme.surfaceRaised, foreground: .white) {
                        Image("github-mark").resizable().scaledToFit().frame(width: 20, height: 20)
                    }
                } footer: {
                    Text("Preview only. Accounts and Sign in with Apple come in a later build.")
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

                Section {
                    Button("Keep playing as a guest") { dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert(comingSoon ?? "", isPresented: Binding(get: { comingSoon != nil }, set: { if !$0 { comingSoon = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Not available yet in this build.")
            }
        }
    }

    private func socialButton(_ title: String, background: Color, foreground: Color, @ViewBuilder icon: () -> some View) -> some View {
        Button { comingSoon = title } label: {
            Label { Text(title) } icon: { icon() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
                .opacity(0.55)
        }
        .buttonStyle(.plain)
    }
}
