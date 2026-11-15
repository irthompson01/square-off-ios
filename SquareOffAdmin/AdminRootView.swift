import SquareOffNet
import SwiftUI

extension AppModel {
    var admin: any AdminAPI { backend.adminAPI }
}

/// The admin app's root: a gate (sign in, then a superadmin check against the current role),
/// then the console. Any 403 from an admin call drops back to the gate.
struct AdminRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var console = AdminAppModel()

    var body: some View {
        Group {
            if app.account.isSignedIn, app.account.profile?.appRole == "superadmin" {
                AdminShell()
                    .environment(console)
            } else if app.account.isSignedIn {
                notAnAdmin
            } else if app.accounts.isRestoring && app.backend.tokenStore.accessToken() != nil {
                ProgressView("Checking access…")
                    .tint(Theme.link)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.overlay)
            } else {
                SignInView()
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) { ToastOverlay(center: app.toasts) }
        .task {
            await app.accounts.restore()
        }
        .onAppear {
            AdminErrors.forbidden = { Task { await app.accounts.restore() } }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await app.accounts.restore() }
        }
    }

    private var notAnAdmin: some View {
        VStack(spacing: 24) {
            EmptyState(symbol: "lock.shield", title: "This account isn't an admin",
                       text: "\(app.account.profile?.email ?? "This account") is signed in, but only superadmins can use the console.") {
                Button("Try again") { Task { await app.accounts.restore() } }
                    .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                Button("Sign out") { Task { await app.accounts.signOut() } }
                    .buttonStyle(DangerButtonStyle(soft: true, small: true, fullWidth: false))
            }
            .padding(24)
            .frame(maxWidth: 448)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.overlay)
    }
}

/// Sections as tabs: every section on wide screens (sidebar-adaptable, two groups), five on a
/// phone (Overview · Live · Users · Games · Console, the last one a list of the rest).
struct AdminShell: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var console = console
        TabView(selection: $console.section) {
            if sizeClass == .regular {
                TabSection("Monitor") {
                    tab(.overview) { OverviewView() }
                    tab(.live) { LiveView() }
                }
                TabSection("Manage") {
                    tab(.users) { UsersView() }
                    tab(.games) { GamesView() }
                    tab(.cpus) { CPUsView() }
                    tab(.audit) { AuditView() }
                    tab(.feedback) { FeedbackInboxView() }
                }
                Tab(value: AdminSection.overview, role: .search) {
                    NavigationStack { AdminSearchView() }
                }
            } else {
                tab(.overview) { OverviewView() }
                tab(.live) { LiveView() }
                tab(.users) { UsersView() }
                tab(.games) { GamesView() }
                Tab("Console", systemImage: "slider.horizontal.3", value: AdminSection.cpus) {
                    NavigationStack { ConsoleView() }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.link)
        .task { await refreshFeedbackBadge() }
        .onChange(of: console.section) { _, section in
            // The compact Console tab stands for CPUs, Audit and Feedback.
            if sizeClass == .compact, section == .audit || section == .feedback { console.section = .cpus }
        }
    }

    private func tab<Content: View>(_ section: AdminSection, @ViewBuilder content: () -> Content) -> some TabContent<AdminSection> {
        Tab(section.title, systemImage: section.symbol, value: section) {
            NavigationStack {
                content()
                    .navigationDestination(for: AdminRoute.self) { route in destination(route) }
            }
        }
        .badge(section == .feedback ? console.newFeedbackCount : 0)
    }

    @ViewBuilder
    private func destination(_ route: AdminRoute) -> some View {
        switch route {
        case .user(let id): UserDetailView(userID: id)
        case .cpus: CPUsView()
        case .audit: AuditView()
        case .feedback: FeedbackInboxView()
        case .search: AdminSearchView()
        case .account: AdminAccountView()
        }
    }

    private func refreshFeedbackBadge() async {
        if let page = try? await app.admin.feedback(status: .new, page: PageRequest(limit: 1, offset: 0)) {
            console.newFeedbackCount = page.counts.new
        }
    }
}

/// The phone's fifth tab: the sections that didn't fit, plus search and the account.
struct ConsoleView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console

    var body: some View {
        List {
            Section {
                NavigationLink(value: AdminRoute.cpus) { Label("CPUs", systemImage: AdminSection.cpus.symbol) }
                NavigationLink(value: AdminRoute.audit) { Label("Audit log", systemImage: AdminSection.audit.symbol) }
                NavigationLink(value: AdminRoute.feedback) {
                    Label("Feedback", systemImage: AdminSection.feedback.symbol)
                        .badge(console.newFeedbackCount)
                }
                NavigationLink(value: AdminRoute.search) { Label("Search", systemImage: "magnifyingglass") }
            }
            Section {
                NavigationLink(value: AdminRoute.account) { Label("Account", systemImage: "person.crop.circle") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Console")
        .navigationDestination(for: AdminRoute.self) { route in
            switch route {
            case .user(let id): UserDetailView(userID: id)
            case .cpus: CPUsView()
            case .audit: AuditView()
            case .feedback: FeedbackInboxView()
            case .search: AdminSearchView()
            case .account: AdminAccountView()
            }
        }
    }
}

/// Who is signed in, the backend (Debug), sign out.
struct AdminAccountView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Signed in as")
                    Text(app.account.profile?.email ?? "—").font(.subheadline).foregroundStyle(Theme.foreground)
                    Chip(text: "superadmin", style: .accent)
                    Text("Server: \(app.backend.configuration.environment.baseURL.host() ?? "—")")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                #if DEBUG
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Developer")
                    Picker("Backend", selection: Binding(get: { app.backend.configuration.kind }, set: { app.switchBackend(to: $0) })) {
                        ForEach(BackendKind.available) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Launch arguments: -backend production|local|mock, -demoSignedIn YES, -demoRole standard, -adminSection <section>, -adminUser <id>, -adminReplay <game id>.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(20)
                .card()
                #endif
                Button { Task { await app.accounts.signOut() } } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                    .buttonStyle(DangerButtonStyle(soft: true))
            }
            .padding(16)
            .frame(maxWidth: 672)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}
