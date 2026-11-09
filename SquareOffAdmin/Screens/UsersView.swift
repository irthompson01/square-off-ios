import SquareOffNet
import SwiftUI

/// The user directory: search, sort, filters, 50 a page (web `pages/admin/users.tsx`).
struct UsersView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var list: PagedQuery<AdminUserRow, AdminUserQuery>?
    @State private var search = ""
    @State private var draft = AdminUserQuery()
    @State private var showsFilters = false
    @State private var path: [AdminRoute] = []

    var body: some View {
        @Bindable var console = console
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "Users", description: "Every registered account. Tap one for stats, games, the audit trail and actions.")
                HStack(spacing: 8) {
                    sortMenu
                    Button {
                        showsFilters = true
                    } label: {
                        Label(draft.hasFilters ? "Filters · on" : "Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                    Spacer()
                    if let list { Text(list.rangeLabel).font(.caption).foregroundStyle(Theme.muted) }
                }
                if let list {
                    if let error = list.error, list.items.isEmpty {
                        SectionError(message: error) { Task { await list.load() } }
                    } else if list.status == .loading {
                        SkeletonRows().padding(.horizontal, 16).card()
                    } else if list.items.isEmpty {
                        EmptyState(symbol: "person.2", title: "No users match", text: "Try another search or clear the filters.") {
                            if draft.hasFilters || !search.isEmpty {
                                Button("Clear") { search = ""; draft = AdminUserQuery(); Task { await list.setQuery(draft) } }
                                    .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(list.items) { user in
                                NavigationLink(value: AdminRoute.user(id: user.id)) { row(user) }
                                    .buttonStyle(.plain)
                                if user.id != list.items.last?.id { Theme.separator.frame(height: 1) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .card()
                        .opacity(list.isBusy ? 0.6 : 1)
                        PageStrip(list: list)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Users")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Email or username")
        .onAppear {
            if list == nil {
                let api = app.admin
                list = PagedQuery(query: draft) { query, page in
                    var q = query
                    q.page = page
                    let result = try await api.users(q)
                    return (result.total, result.items)
                }
                Task { await list?.load() }
            }
        }
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            draft.q = search.isEmpty ? nil : search
            await list?.setQuery(draft)
        }
        .sheet(isPresented: $showsFilters) {
            UserFiltersSheet(query: $draft) { Task { await list?.setQuery(draft) } }
                .presentationDetents([.medium])
                .presentationBackground(Theme.overlay)
        }
        .onChange(of: console.pendingUser, initial: true) { _, id in
            guard let id else { return }
            console.pendingUser = nil
            path.append(.user(id: id))
        }
        .navigationDestination(for: AdminRoute.self) { route in
            if case .user(let id) = route { UserDetailView(userID: id) }
        }
        .modifier(PathHost(path: $path))
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AdminUserQuery.Sort.allCases, id: \.self) { sort in
                Button {
                    if draft.sort == sort { draft.dir = draft.dir == .asc ? .desc : .asc } else { draft.sort = sort; draft.dir = sort == .username ? .asc : .desc }
                    Task { await list?.setQuery(draft) }
                } label: {
                    Label(Self.sortTitle(sort), systemImage: draft.sort == sort ? (draft.dir == .asc ? "chevron.up" : "chevron.down") : "")
                }
            }
        } label: {
            Label("\(Self.sortTitle(draft.sort)) \(draft.dir == .asc ? "↑" : "↓")", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
    }

    static func sortTitle(_ sort: AdminUserQuery.Sort) -> String {
        switch sort {
        case .createdAt: "Joined"
        case .lastLoginAt: "Last sign-in"
        case .username: "Username"
        case .gamesPlayed: "Games"
        }
    }

    private func row(_ user: AdminUserRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.username).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                    if user.appRole == .superadmin { AdminChips.role(user.appRole) }
                    if !user.isActive { AdminChips.active(false) }
                }
                Text(user.email).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                Text("\(user.gamesPlayed) games · joined \(AdminFormat.absolute(user.createdAt, time: false)) · last sign-in \(AdminFormat.relative(user.lastLoginAt))")
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Hosts a tab's `NavigationStack` path so deep links can push onto it.
struct PathHost: ViewModifier {
    @Binding var path: [AdminRoute]

    func body(content: Content) -> some View {
        content
    }
}

struct UserFiltersSheet: View {
    @Binding var query: AdminUserQuery
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Role", selection: $query.role) {
                    Text("Any").tag(AppRole?.none)
                    ForEach(AppRole.allCases, id: \.self) { Text($0.rawValue).tag(AppRole?.some($0)) }
                }
                Picker("Status", selection: $query.active) {
                    Text("Any").tag(Bool?.none)
                    Text("Active").tag(Bool?.some(true))
                    Text("Inactive").tag(Bool?.some(false))
                }
                Picker("Sign-in method", selection: $query.provider) {
                    Text("Any").tag(AuthProvider?.none)
                    ForEach(AuthProvider.allCases, id: \.self) { Text($0.rawValue).tag(AuthProvider?.some($0)) }
                }
                Picker("Has played", selection: $query.hasPlayed) {
                    Text("Any").tag(Bool?.none)
                    Text("Yes").tag(Bool?.some(true))
                    Text("No").tag(Bool?.some(false))
                }
                Button("Clear filters") { query.role = nil; query.active = nil; query.provider = nil; query.hasPlayed = nil }
                    .disabled(!query.hasFilters)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { onApply(); dismiss() } }
            }
        }
    }
}
