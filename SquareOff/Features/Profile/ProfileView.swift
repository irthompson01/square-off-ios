import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("musicEnabled") private var musicEnabled = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var isSignInPresented = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                HStack(spacing: 14) {
                    Text(String(app.account.displayName.prefix(1)).uppercased())
                        .font(.title.weight(.heavy))
                        .frame(width: 60, height: 60)
                        .background(Color(hex: Theme.playerColors[0]), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.account.displayName).font(.title3.bold())
                        Text(app.account == .guest ? "Playing as a guest" : "Signed in")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
                if app.account == .guest {
                    Button("Sign in or create account") { isSignInPresented = true }
                }
            }

            Section("Stats") {
                LabeledContent("Games", value: "—")
                LabeledContent("Win rate", value: "—")
                LabeledContent("Best turn", value: "—")
                Text("Stats and replays will load from /stats_view once signed in.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section("Settings") {
                Toggle("Sound effects", isOn: $soundEnabled)
                Toggle("Music", isOn: $musicEnabled)
                Toggle("Haptics", isOn: $hapticsEnabled)
            }

            Section {
                Picker("Backend", selection: $app.backend) {
                    ForEach(Backend.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Local server = docker-compose backend at https://localhost:8002. The simulator must trust the mkcert root (see README).")
            }

            if app.account != .guest {
                Section {
                    Button("Sign out", role: .destructive) { Task { await app.signOut() } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Profile")
        .sheet(isPresented: $isSignInPresented) { SignInView() }
    }
}

/// Password + guest login for v1. Apple / Google / GitHub are placeholders until Sign in with
/// Apple works on the web (the server needs mobile OAuth redirects first).
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
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
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.destructive)
                    }
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Sign in").bold()
                            if isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isWorking)
                }

                Section {
                    socialButton("Sign in with Apple", systemImage: "apple.logo", background: .white, foreground: .black)
                    socialButton("Continue with Google", systemImage: "g.circle.fill", background: Theme.surfaceRaised, foreground: .white)
                    socialButton("Continue with GitHub", systemImage: "chevron.left.forwardslash.chevron.right", background: Theme.surfaceRaised, foreground: .white)
                } footer: {
                    Text("Coming soon. These turn on once Sign in with Apple ships on the web.")
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

    private func socialButton(_ title: String, systemImage: String, background: Color, foreground: Color) -> some View {
        Button { comingSoon = title } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
                .opacity(0.55)
        }
        .buttonStyle(.plain)
    }

    private func signIn() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await app.signIn(username: username, password: password)
            dismiss()
        } catch {
            self.error = "Couldn't sign in. Check your details and try again."
        }
    }
}
