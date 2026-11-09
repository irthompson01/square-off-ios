import SquareOffNet
import SwiftUI

/// The user directory: search, sort, filters (role, status, provider, played, verified, bots),
/// 50 a page, with a select mode for bulk deactivation (web `pages/admin/users.tsx`).
struct UsersView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var list: PagedQuery<AdminUserRow, AdminUserQuery>?
    @State private var search = ""
    @State private var draft = AdminUserQuery()
    @State private var showsFilters = false
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var confirmSelected = false
    @State private var confirmSuspects = false
    @State private var deactivating = false

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
                    if selecting, let list, !list.items.isEmpty {
                        Button(selected.count == list.items.count ? "Deselect all" : "Select all") {
                            selected = selected.count == list.items.count ? [] : Set(list.items.map(\.id))
                        }
                        .buttonStyle(TertiaryButtonStyle(small: true, fullWidth: false))
                    }
                    Spacer()
                    if let list { Text(list.rangeLabel).font(.caption).foregroundStyle(Theme.muted) }
                }
                if let list, selected.count > 0 || (draft.suspect == true && list.total > 0) {
                    bulkBar(total: list.total)
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
                                if selecting {
                                    Button { toggle(user.id) } label: { row(user, checked: selected.contains(user.id)) }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Select \(user.username)")
                                        .accessibilityAddTraits(selected.contains(user.id) ? .isSelected : [])
                                } else {
                                    NavigationLink(value: AdminRoute.user(id: user.id)) { row(user, checked: nil) }
                                        .buttonStyle(.plain)
                                }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    selecting.toggle()
                    if !selecting { selected = [] }
                }
            }
        }
        .onAppear {
            if list == nil {
                if console.pendingUsersSuspects {
                    console.pendingUsersSuspects = false
                    draft.suspect = true
                }
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
        // Like the web, the selection belongs to the page on screen: a new page, sort or filter clears it.
        .onChange(of: list?.items.map(\.id) ?? []) { _, _ in selected = [] }
        .sheet(isPresented: $showsFilters) {
            UserFiltersSheet(query: $draft) { Task { await list?.setQuery(draft) } }
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.overlay)
        }
        .alert(UsersBulk.selectedTitle(selected.count), isPresented: $confirmSelected) {
            Button("Deactivate", role: .destructive) { deactivate(.ids(Array(selected))) }
            Button("Cancel", role: .cancel) {}
        } message: { Text(UsersBulk.selectedMessage(selected.count)) }
        .alert(UsersBulk.suspectsTitle, isPresented: $confirmSuspects) {
            Button("Deactivate", role: .destructive) { deactivate(.suspects()) }
            Button("Cancel", role: .cancel) {}
        } message: { Text(UsersBulk.suspectsMessage(list?.total ?? 0)) }
        .onChange(of: console.pendingUser, initial: true) { _, id in
            guard let id else { return }
            console.pendingUser = nil
            console.paths[.users, default: []].append(.user(id: id))
        }
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

    /// "{n} selected" (or "Suspected bots" while that filter is on with nothing ticked) and the
    /// deactivate buttons (web `bulk-deactivate-bar.tsx`).
    private func bulkBar(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selected.isEmpty ? "Suspected bots" : "\(selected.count) selected")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
            HStack(spacing: 10) {
                if !selected.isEmpty {
                    Button("Deactivate \(selected.count) selected") { confirmSelected = true }
                        .buttonStyle(DangerButtonStyle(small: true, fullWidth: false))
                        .disabled(deactivating)
                }
                if draft.suspect == true {
                    Button("Deactivate all suspected bots (\(total))") { confirmSuspects = true }
                        .buttonStyle(DangerButtonStyle(soft: true, small: true, fullWidth: false))
                        .disabled(deactivating || total == 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Theme.surfaceSecondary, radius: 12)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func deactivate(_ request: BulkDeactivateRequest) {
        deactivating = true
        Task {
            defer { deactivating = false }
            do {
                let result = try await app.admin.bulkDeactivate(request)
                app.toasts.success(UsersBulk.successTitle(result), description: UsersBulk.skippedDescription(result))
                selected = []
                await list?.load()
            } catch {
                app.toasts.danger(UsersBulk.failureTitle, description: AdminErrors.message(for: error))
            }
        }
    }

    private func row(_ user: AdminUserRow, checked: Bool?) -> some View {
        HStack(spacing: 12) {
            if let checked {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Theme.link : Theme.muted)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.username).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                    if user.appRole == .superadmin { AdminChips.role(user.appRole) }
                    if !user.isActive { AdminChips.active(false) }
                    if !user.isEmailVerified { AdminChips.verified(nil) }
                    if user.isSuspect { AdminChips.suspect() }
                }
                Text(user.email).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                Text("\(user.gamesPlayed) games · joined \(AdminFormat.absolute(user.createdAt, time: false)) · last sign-in \(AdminFormat.relative(user.lastLoginAt))")
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            if checked == nil {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
                Picker("Verified", selection: $query.verified) {
                    Text("Any").tag(Bool?.none)
                    Text("Verified").tag(Bool?.some(true))
                    Text("Unverified").tag(Bool?.some(false))
                }
                Picker("Bots", selection: $query.suspect) {
                    Text("Any").tag(Bool?.none)
                    Text("Suspected").tag(Bool?.some(true))
                }
                Button("Clear filters") {
                    query.role = nil; query.active = nil; query.provider = nil; query.hasPlayed = nil; query.verified = nil; query.suspect = nil
                }
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
