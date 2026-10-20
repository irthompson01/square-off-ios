import SquareOffNet
import SwiftUI

/// Account card (guest or signed in), stats and recent games for signed-in users, the feel
/// settings and, in debug builds, the backend switch.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("musicEnabled") private var musicEnabled = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("starsEnabled") private var starsEnabled = true
    @State private var isSignInPresented = false
    @State private var isEditPresented = false
    @State private var stats: PlayerStatsView?
    @State private var recent: RecentGamesPage?
    @State private var statsError: String?

    var body: some View {
        Form {
            accountSection
            statsSection
            if app.account.isSignedIn { recentGamesSection }

            Section("Settings") {
                Toggle("Sound effects", isOn: $soundEnabled)
                Toggle("Music", isOn: $musicEnabled)
                Toggle("Haptics", isOn: $hapticsEnabled)
                Toggle("Stars background", isOn: $starsEnabled)
            }

            #if DEBUG
            developerSection
            #endif
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Profile")
        .sheet(isPresented: $isSignInPresented) { SignInView() }
        .sheet(isPresented: $isEditPresented) {
            if let profile = app.account.profile { EditProfileSheet(profile: profile) }
        }
        .task(id: app.account) { await loadStats() }
        .onAppear {
            if app.pendingSignIn {
                app.pendingSignIn = false
                isSignInPresented = true
            }
        }
    }

    // MARK: Sections

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                Text(String(app.account.displayName.prefix(1)).uppercased())
                    .font(.title.weight(.heavy))
                    .frame(width: 60, height: 60)
                    .background(Color(hex: app.account.colorHex), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.account.profile?.displayName ?? app.account.displayName).font(.title3.bold())
                    Text(app.account.profile?.email ?? "Playing as a guest on this device")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    if let profile = app.account.profile, let since = Self.memberSince(profile.createdAt) {
                        Text("Member since \(since)").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.vertical, 4)
            if app.account.isSignedIn {
                Button("Edit profile") { isEditPresented = true }
                Button("Sign out", role: .destructive) { Task { await app.accounts.signOut() } }
            } else {
                Button("Sign in") { isSignInPresented = true }
            }
        }
    }

    private var statsSection: some View {
        Section("Stats") {
            if let stats {
                LabeledContent("Games", value: "\(stats.totalGamesPlayed)")
                LabeledContent("Win rate", value: stats.totalGamesPlayed == 0 ? "—" : String(format: "%.0f%%", stats.winPercentage))
                LabeledContent("Best score", value: "\(stats.highestScore)")
                LabeledContent("Average score", value: String(format: "%.0f", stats.avgFinalScore))
                NavigationLink("Vs CPU breakdown") { CPUStatsView() }
            } else {
                LabeledContent("Games", value: "—")
                LabeledContent("Win rate", value: "—")
                LabeledContent("Best score", value: "—")
                Text(statsError ?? (app.account.isSignedIn ? "Loading…" : "Sign in to keep stats and replays."))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var recentGamesSection: some View {
        Section("Recent games") {
            if let recent, !recent.games.isEmpty {
                ForEach(recent.games) { row in
                    NavigationLink { ReplayView(gameID: row.gameId) } label: {
                        HStack(spacing: 12) {
                            Text(row.result)
                                .font(.headline)
                                .frame(width: 28, height: 28)
                                .background(Self.resultColor(row.result).opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("vs \(row.opponentLabel)").font(.subheadline.weight(.semibold))
                                Text(row.gameType.capitalized).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text("\(row.myScore)").font(.headline).monospacedDigit()
                        }
                    }
                }
                if recent.total > recent.games.count {
                    Text("Showing \(recent.games.count) of \(recent.total)").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text(recent == nil ? "Loading…" : "No finished games yet. Play one and it shows up here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section {
            Picker("Backend", selection: Binding(
                get: { app.backend.configuration.kind },
                set: { app.switchBackend(to: $0) }
            )) {
                ForEach(BackendKind.allCases) { Text($0.title).tag($0) }
            }
            Toggle("CPU moves from server", isOn: Binding(
                get: { app.backend.configuration.cpuMovesFromServer },
                set: { app.setCPUMovesFromServer($0) }
            ))
            LabeledContent("API", value: app.backend.configuration.environment.baseURL.absoluteString)
                .font(.footnote)
            LabeledContent("Guest ID", value: app.backend.identity.guest.map { String($0.playerID.prefix(13)) + "…" } ?? "—")
                .font(.footnote)
            Button("Reset guest identity") { app.backend.identity.reset() }
        } header: {
            Text("Developer")
        } footer: {
            Text("Applies to new games. Launch argument: -backend mock|live. The docker stack needs the mkcert CA trusted in this simulator (scripts/trust-mkcert-simulator.sh).")
        }
    }
    #endif

    // MARK: Data

    private func loadStats() async {
        stats = nil
        recent = nil
        statsError = nil
        guard app.account.isSignedIn else { return }
        let api = app.backend.api
        do {
            async let statsView = api.statsView()
            async let page = api.recentGames(limit: 10, offset: 0)
            stats = try await statsView
            recent = try await page
        } catch {
            statsError = "Couldn't load stats: \((error as? APIError)?.detail ?? error.localizedDescription)"
        }
    }

    static func memberSince(_ createdAt: String) -> String? {
        guard createdAt.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(createdAt.prefix(10))) else { return nil }
        return date.formatted(.dateTime.month(.wide).year())
    }

    static func resultColor(_ result: String) -> Color {
        switch result {
        case "W": Theme.go
        case "L": Theme.destructive
        default: Theme.warning
        }
    }
}

/// `GET /stats_view_cpu` with the web's filters.
struct CPUStatsView: View {
    @Environment(AppModel.self) private var app
    @State private var rows: [PlayerStatsCPUView] = []
    @State private var boardSize: Int?
    @State private var timer: Int?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Picker("Board", selection: $boardSize) {
                    Text("Any board").tag(Int?.none)
                    ForEach(SetupForm.boardSizes, id: \.self) { Text("\($0)×\($0)").tag(Int?.some($0)) }
                }
                Picker("Timer", selection: $timer) {
                    Text("Any timer").tag(Int?.none)
                    ForEach(SetupForm.timers, id: \.self) { Text($0 == 0 ? "Off" : "\($0)s").tag(Int?.some($0)) }
                }
            }
            Section("By level") {
                if rows.isEmpty {
                    Text(error ?? "No games against the CPU yet.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.username).font(.subheadline.weight(.semibold))
                        HStack {
                            Text("\(row.totalGamesPlayed) games · \(row.gamesWon) won")
                            Spacer()
                            Text(String(format: "%.0f%%", row.winPercentage)).monospacedDigit()
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Vs CPU")
        .task(id: "\(boardSize ?? 0)-\(timer ?? -1)") {
            do {
                rows = try await app.backend.api.statsViewCPU(boardSize: boardSize, timer: timer, cpuType: nil)
                error = nil
            } catch {
                self.error = "Couldn't load: \((error as? APIError)?.detail ?? error.localizedDescription)"
            }
        }
    }
}

struct EditProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var colorHex: String
    @State private var isBusy = false
    @State private var error: String?

    init(profile: ProfileResponse) {
        _firstName = State(initialValue: profile.firstName)
        _lastName = State(initialValue: profile.lastName)
        _colorHex = State(initialValue: profile.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }
                Section("Colour") {
                    HStack {
                        Text("Player colour")
                        Spacer()
                        ColorSwatchPicker(selection: $colorHex)
                    }
                }
                if let error { Text(error).foregroundStyle(Theme.destructive).font(.footnote) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isBusy ? "Saving…" : "Save") {
                        isBusy = true
                        Task {
                            defer { isBusy = false }
                            do {
                                try await app.accounts.updateProfile(firstName: firstName, lastName: lastName, colorHex: colorHex)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isBusy)
                }
            }
        }
    }
}
