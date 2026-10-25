import SquareOffNet
import SwiftUI

/// Profile (web `/profile`): the account panel with label/value rows and inline editing, the
/// stats link, the feel settings and, in debug builds, the backend switch.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage(MusicPlayer.defaultsKey) private var musicEnabled = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("starsEnabled") private var starsEnabled = true
    @State private var signIn: SignInView.Mode?
    @State private var isEditing = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var colorHex = Theme.playerColors[0]
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Profile", description: "Your account, and how you appear in games.")
                if app.account.isSignedIn {
                    accountPanel
                    NavigationLink { StatsView() } label: {
                        HStack {
                            Label("Game stats", systemImage: "chart.bar")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.foreground)
                        .padding(16)
                        .card()
                    }
                    .buttonStyle(.plain)
                } else {
                    guestPanel
                }
                settingsPanel
                #if DEBUG
                developerPanel
                #endif
            }
            .padding(16)
            .frame(maxWidth: 672)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $signIn) { mode in SignInView(initialMode: mode) }
        .onAppear {
            if app.pendingSignIn {
                app.pendingSignIn = false
                signIn = .signIn
            }
        }
        .onChange(of: app.account) { _, _ in
            isEditing = false
            saveError = nil
        }
    }

    // MARK: Account

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Account").font(Theme.display(18, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                Spacer()
                if !isEditing {
                    Button { beginEditing() } label: { Label("Edit profile", systemImage: "pencil") }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                }
            }
            if let error = saveError {
                AlertBox(.danger, title: "Something went wrong", message: error)
            }
            if let profile = app.account.profile {
                if isEditing {
                    editor(profile)
                } else {
                    rows(profile)
                }
            } else if app.accounts.isRestoring {
                ForEach(0..<6, id: \.self) { _ in
                    HStack {
                        SkeletonBar(width: 96)
                        Spacer()
                        SkeletonBar(width: 144)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(20)
        .card()
    }

    private func rows(_ profile: ProfileResponse) -> some View {
        VStack(spacing: 0) {
            row("Username", profile.username)
            row("Email", profile.email)
            row("First name", profile.firstName.isEmpty ? "Not set" : profile.firstName, dim: profile.firstName.isEmpty)
            row("Last name", profile.lastName.isEmpty ? "Not set" : profile.lastName, dim: profile.lastName.isEmpty)
            HStack {
                Text("Color").font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Circle().fill(Color(hex: profile.color)).frame(width: 14, height: 14)
                Text(ColorNames.name(for: profile.color)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
            }
            .padding(.vertical, 12)
            Theme.separator.frame(height: 1)
            row("Member since", Self.memberSince(profile.createdAt) ?? "—")
        }
    }

    private func row(_ label: String, _ value: String, dim: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(dim ? Theme.muted : Theme.foreground)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            Theme.separator.frame(height: 1)
        }
    }

    private func editor(_ profile: ProfileResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField(label: "First name") {
                TextField("First name", text: $firstName).textContentType(.givenName).foregroundStyle(Theme.foreground)
            }
            LabeledField(label: "Last name") {
                TextField("Last name", text: $lastName).textContentType(.familyName).foregroundStyle(Theme.foreground)
            }
            HStack(spacing: 12) {
                ColorSwatchPicker(selection: $colorHex, allowCustom: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Color").font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                    Text("\(ColorNames.name(for: colorHex)) · shown on your tiles and in rooms").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 10) {
                Button(action: save) {
                    PendingLabel(title: "Save changes", pendingTitle: "Saving…", symbol: "checkmark", isPending: isSaving)
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .disabled(isSaving)
                Button {
                    isEditing = false
                    saveError = nil
                } label: { Label("Cancel", systemImage: "xmark") }
                    .buttonStyle(TertiaryButtonStyle(fullWidth: false))
                    .disabled(isSaving)
            }
        }
    }

    private func beginEditing() {
        guard let profile = app.account.profile else { return }
        firstName = profile.firstName
        lastName = profile.lastName
        colorHex = profile.color.isEmpty ? Theme.playerColors[0] : profile.color
        saveError = nil
        isEditing = true
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            defer { isSaving = false }
            do {
                try await app.accounts.updateProfile(firstName: firstName, lastName: lastName, colorHex: colorHex)
                isEditing = false
                app.toasts.success("Profile updated")
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private var guestPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(String(app.account.displayName.prefix(1)).uppercased())
                    .font(Theme.display(22, relativeTo: .title2))
                    .foregroundStyle(Theme.background)
                    .frame(width: 52, height: 52)
                    .background(Color(hex: app.account.colorHex), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.account.displayName).font(Theme.display(17, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                    Text("Playing as a guest on this device").font(.footnote).foregroundStyle(Theme.foregroundSecondary)
                }
            }
            Text("Sign in to keep stats and replays.").font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
            HStack(spacing: 10) {
                Button { signIn = .signIn } label: { Label("Log in", systemImage: "arrow.right.to.line") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                Button { signIn = .register } label: { Label("Create account", systemImage: "person.badge.plus") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: false))
            }
        }
        .padding(20)
        .card()
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Preferences")
            SettingsToggle(title: "Sound effects", isOn: $soundEnabled)
            SettingsToggle(title: "Music", description: "Music by Missy Cundiff", isOn: $musicEnabled)
            SettingsToggle(title: "Haptics", isOn: $hapticsEnabled)
            SettingsToggle(title: "Starfield", isOn: $starsEnabled)
            if app.account.isSignedIn {
                Theme.separator.frame(height: 1).padding(.vertical, 4)
                Button { Task { await app.accounts.signOut() } } label: { Label("Log out", systemImage: "rectangle.portrait.and.arrow.right") }
                    .buttonStyle(DangerButtonStyle(soft: true))
            }
        }
        .padding(20)
        .card()
    }

    #if DEBUG
    private var developerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Developer")
            HStack {
                Text("Backend").font(.subheadline).foregroundStyle(Theme.foreground)
                Spacer()
                Picker("Backend", selection: Binding(
                    get: { app.backend.configuration.kind },
                    set: { app.switchBackend(to: $0) }
                )) {
                    ForEach(BackendKind.available) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }
            SettingsToggle(title: "CPU moves from server", isOn: Binding(
                get: { app.backend.configuration.cpuMovesFromServer },
                set: { app.setCPUMovesFromServer($0) }
            ))
            row("API", app.backend.configuration.environment.baseURL.absoluteString)
            row("Guest ID", app.backend.identity.guest.map { String($0.playerID.prefix(13)) + "…" } ?? "—")
            Button("Reset guest identity") { app.backend.identity.reset() }
                .buttonStyle(TertiaryButtonStyle(small: true, fullWidth: false))
            if app.backend.configuration.kind == .mock, app.account.isSignedIn {
                Button("Simulate revoked session") {
                    Task { await (app.backend.api as? MockSquareOffAPI)?.revokeSession(); await app.accounts.restore() }
                }
                .buttonStyle(TertiaryButtonStyle(small: true, fullWidth: false))
            }
            Text("Applies to new games. Launch argument: -backend production|local|mock. The docker stack needs the mkcert CA trusted in this simulator (scripts/trust-mkcert-simulator.sh).")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(20)
        .card()
    }
    #endif

    static func memberSince(_ createdAt: String) -> String? {
        guard createdAt.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(createdAt.prefix(10))) else { return nil }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
