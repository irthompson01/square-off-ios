import SquareOffNet
import SwiftUI

/// One account: profile (editable), role and status, sessions, stats, identities, games and
/// the audit trail (web `pages/admin/user-detail.tsx`).
struct UserDetailView: View {
    @Environment(AppModel.self) private var app
    let userID: String

    @State private var overview: AdminQuery<AdminUserOverview>?
    @State private var games: PagedQuery<AdminUserGameRow, String>?
    @State private var audit: PagedQuery<AdminAuditRow, String>?
    @State private var isEditing = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var colorHex = ""
    @State private var pending = false
    @State private var confirmRole: AppRole?
    @State private var confirmDeactivate = false
    @State private var confirmForceLogout = false
    @State private var showsResetPassword = false
    @State private var replay: ReplayTarget?

    private var isSelf: Bool { app.account.profile?.id == userID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let overview {
                    if let error = overview.error, overview.value == nil {
                        SectionError(message: error) { Task { await overview.refresh() } }
                    } else if let data = overview.value {
                        header(data.user)
                        profileCard(data)
                        actionsCard(data.user)
                        statsCard(data)
                        identitiesCard(data)
                        if let games { gamesCard(games) }
                        if let audit { auditCard(audit) }
                    } else {
                        SkeletonRows().padding(16).card()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(overview?.value?.user.username ?? "User")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setUp)
        .task { await overview?.refresh(); await games?.load(); await audit?.load() }
        .alert("Change role to \(confirmRole?.rawValue ?? "")?", isPresented: Binding(get: { confirmRole != nil }, set: { if !$0 { confirmRole = nil } })) {
            Button("Change role", role: .destructive) { if let role = confirmRole { patch(AdminUserPatch(appRole: role)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmRole == .superadmin ? "Superadmins can see every user's data and change accounts." : "The user loses access to the admin console on their next request.")
        }
        .alert("Deactivate this account?", isPresented: $confirmDeactivate) {
            Button("Deactivate", role: .destructive) { patch(AdminUserPatch(isActive: false)) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("They are signed out everywhere on their next request and can't sign in until reactivated.") }
        .alert("Sign out everywhere?", isPresented: $confirmForceLogout) {
            Button("Sign out", role: .destructive) { forceLogout() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Every device's session ends on its next request. The user can sign in again.") }
        .sheet(isPresented: $showsResetPassword) {
            ResetPasswordSheet(userID: userID, username: overview?.value?.user.username ?? "") { Task { await audit?.load() } }
                .presentationDetents([.medium])
                .presentationBackground(Theme.overlay)
        }
        .sheet(item: $replay) { target in AdminReplaySheet(gameID: target.id) }
    }

    private func setUp() {
        guard overview == nil else { return }
        let api = app.admin, id = userID
        overview = AdminQuery { try await api.userOverview(id: id) }
        games = PagedQuery(query: id) { id, page in
            let result = try await api.userGames(id: id, page: page)
            return (result.total, result.items)
        }
        audit = PagedQuery(query: id) { id, page in
            let result = try await api.userAudit(id: id, page: page)
            return (result.total, result.items)
        }
    }

    // MARK: Cards

    private func header(_ user: AdminUserDetail) -> some View {
        HStack(spacing: 14) {
            Text(String(user.username.prefix(1)).uppercased())
                .font(Theme.display(22, relativeTo: .title2)).foregroundStyle(Theme.background)
                .frame(width: 52, height: 52).background(Color(hex: user.color), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(Theme.display(20, relativeTo: .title2)).foregroundStyle(Theme.foreground)
                Text(user.email).font(.subheadline).foregroundStyle(Theme.foregroundSecondary).textSelection(.enabled)
                HStack(spacing: 6) {
                    AdminChips.role(user.appRole)
                    AdminChips.active(user.isActive)
                    AdminChips.provider(user.oauthProvider)
                    if isSelf { Chip(text: "You", style: .accentFilled) }
                }
            }
        }
    }

    private func profileCard(_ data: AdminUserOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Profile")
                Spacer()
                if !isEditing {
                    Button { beginEditing(data.user) } label: { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                }
            }
            if isEditing {
                LabeledField(label: "Username") { TextField("username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(Theme.foreground) }
                LabeledField(label: "First name") { TextField("First name", text: $firstName).foregroundStyle(Theme.foreground) }
                LabeledField(label: "Last name") { TextField("Last name", text: $lastName).foregroundStyle(Theme.foreground) }
                HStack(spacing: 10) {
                    Text("Color").font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                    ColorSwatchPicker(selection: $colorHex, allowCustom: true)
                }
                HStack(spacing: 10) {
                    Button { saveProfile(data.user) } label: { PendingLabel(title: "Save changes", pendingTitle: "Saving…", symbol: "checkmark", isPending: pending) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false)).disabled(pending)
                    Button("Cancel") { isEditing = false }.buttonStyle(TertiaryButtonStyle(small: true, fullWidth: false))
                }
            } else {
                VStack(spacing: 0) {
                    DetailRow(label: "User id", value: data.user.id)
                    DetailRow(label: "Joined", value: AdminFormat.absolute(data.user.createdAt))
                    DetailRow(label: "Last sign-in", value: AdminFormat.absolute(data.user.lastLoginAt), dim: data.user.lastLoginAt == nil)
                    DetailRow(label: "Session version", value: "\(data.user.sessionVersion)")
                    DetailRow(label: "Games played", value: "\(data.gamesPlayed) (\(data.gamesAbandoned) abandoned)")
                    DetailRow(label: "Last played", value: AdminFormat.relative(data.lastPlayedAt), dim: data.lastPlayedAt == nil)
                    DetailRow(label: "Feedback / audit", value: "\(data.feedbackCount) · \(data.auditCount)")
                }
            }
        }
        .padding(16)
        .card()
    }

    private func actionsCard(_ user: AdminUserDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Actions")
            if isSelf {
                Text("Your own role, status and sessions are managed from another admin account.").font(.caption).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                Button(user.appRole == .superadmin ? "Make standard" : "Make superadmin") {
                    confirmRole = user.appRole == .superadmin ? .standard : .superadmin
                }
                .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                .disabled(isSelf || pending)
                if user.isActive {
                    Button("Deactivate") { confirmDeactivate = true }
                        .buttonStyle(DangerButtonStyle(soft: true, small: true, fullWidth: false)).disabled(isSelf || pending)
                } else {
                    Button("Reactivate") { patch(AdminUserPatch(isActive: true)) }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false)).disabled(pending)
                }
            }
            HStack(spacing: 10) {
                Button("Set password") { showsResetPassword = true }.buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false)).disabled(pending)
                Button("Sign out everywhere") { confirmForceLogout = true }
                    .buttonStyle(DangerButtonStyle(soft: true, small: true, fullWidth: false)).disabled(isSelf || pending)
            }
        }
        .padding(16)
        .card()
    }

    @ViewBuilder
    private func statsCard(_ data: AdminUserOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Stats")
            if let stats = data.stats {
                StatsSummaryView(summary: StatsSummary(stats))
            } else {
                Text("No finished games yet.").font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .card()
    }

    @ViewBuilder
    private func identitiesCard(_ data: AdminUserOverview) -> some View {
        if !data.identities.isEmpty || !data.entitlements.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Identities and entitlements")
                ForEach(data.identities) { identity in
                    DetailRow(label: identity.provider, value: "\(identity.providerEmail ?? "—") · \(identity.providerSub)")
                }
                ForEach(data.entitlements) { entitlement in
                    DetailRow(label: entitlement.entitlementType, value: "\(entitlement.entitlementValue ?? "—") · \(entitlement.source)\(entitlement.expiresAt.map { " · until \(AdminFormat.absolute($0, time: false))" } ?? "")")
                }
            }
            .padding(16)
            .card()
        }
    }

    private func gamesCard(_ list: PagedQuery<AdminUserGameRow, String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Games · \(list.total)")
            if let error = list.error, list.items.isEmpty { Text(error).font(.caption).foregroundStyle(Theme.dangerText) }
            if list.isEmpty { Text("No games.").font(.caption).foregroundStyle(Theme.muted) }
            ForEach(list.items) { game in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("#\(String(game.gameId)) vs \(game.opponentLabel)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                        Text("\(game.gameType) · \(game.boardSize)×\(game.boardSize) · \(AdminFormat.relative(game.startTime))").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if let score = game.myScore { Text("\(score)").font(Theme.display(14, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.foreground) }
                    AdminChips.result(game.result)
                    if game.replayAvailable {
                        Button { replay = ReplayTarget(id: game.gameId) } label: { Image(systemName: "play").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foregroundSecondary).frame(width: 32, height: 32) }
                            .buttonStyle(.plain).accessibilityLabel("Replay game \(game.gameId)")
                    }
                }
                .padding(.vertical, 6)
            }
            PageStrip(list: list)
        }
        .padding(16)
        .card()
    }

    private func auditCard(_ list: PagedQuery<AdminAuditRow, String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Audit trail · \(list.total)")
            if list.isEmpty { Text("Nothing yet.").font(.caption).foregroundStyle(Theme.muted) }
            ForEach(list.items) { row in AuditRowView(row: row) }
            PageStrip(list: list)
        }
        .padding(16)
        .card()
    }

    // MARK: Actions

    private func beginEditing(_ user: AdminUserDetail) {
        firstName = user.firstName
        lastName = user.lastName
        username = user.username
        colorHex = user.color
        isEditing = true
    }

    private func saveProfile(_ user: AdminUserDetail) {
        var patch = AdminUserPatch()
        if firstName != user.firstName { patch.firstName = firstName }
        if lastName != user.lastName { patch.lastName = lastName }
        if username.trimmingCharacters(in: .whitespaces) != user.username { patch.username = username.trimmingCharacters(in: .whitespaces) }
        if colorHex != user.color { patch.color = colorHex }
        guard !patch.isEmpty else { isEditing = false; return }
        self.patch(patch) { isEditing = false }
    }

    private func patch(_ patch: AdminUserPatch, then: @escaping () -> Void = {}) {
        pending = true
        Task {
            defer { pending = false }
            do {
                _ = try await app.admin.patchUser(id: userID, patch)
                app.toasts.success("User updated")
                then()
                await overview?.refresh()
                await audit?.load()
            } catch {
                app.toasts.danger("Couldn't update the user", description: AdminErrors.message(for: error))
            }
        }
    }

    private func forceLogout() {
        pending = true
        Task {
            defer { pending = false }
            do {
                let result = try await app.admin.forceLogout(id: userID)
                app.toasts.success("Sessions revoked", description: "Session version is now \(result.sessionVersion).")
                await overview?.refresh()
                await audit?.load()
            } catch {
                app.toasts.danger("Couldn't sign the user out", description: AdminErrors.message(for: error))
            }
        }
    }
}

struct ResetPasswordSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let userID: String
    let username: String
    let onDone: () -> Void

    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var pending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Set a new password for \(username). Their current sessions stay signed in; use Sign out everywhere to end them.")
                        .font(.subheadline).foregroundStyle(Theme.foregroundSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    if let error { AlertBox(.danger, title: "Couldn't set the password", message: error) }
                    LabeledField(label: "New password", help: "At least 8 characters.") { SecureField("••••••••", text: $password).textContentType(.newPassword).foregroundStyle(Theme.foreground) }
                    LabeledField(label: "Confirm password") { SecureField("••••••••", text: $confirm).textContentType(.newPassword).foregroundStyle(Theme.foreground) }
                    Button(action: submit) { PendingLabel(title: "Set password", pendingTitle: "Saving…", symbol: "key", isPending: pending) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(pending || password.count < 8 || password != confirm)
                }
                .padding(20)
            }
            .background(Theme.overlay)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(pending) } }
        }
    }

    private func submit() {
        pending = true
        error = nil
        Task {
            defer { pending = false }
            do {
                _ = try await app.admin.resetPassword(id: userID, newPassword: password)
                dismiss()
                app.toasts.success("Password updated", description: "\(username) can sign in with the new password.")
                onDone()
            } catch {
                self.error = AdminErrors.message(for: error)
            }
        }
    }
}

/// One audit row: when, what, who → whom, with the JSON detail behind a disclosure.
struct AuditRowView: View {
    @Environment(AdminAppModel.self) private var console
    let row: AdminAuditRow
    var linksToTarget = true
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Chip(text: Self.title(row.action), style: Self.style(row.action))
                Spacer()
                Text(AdminFormat.relative(row.createdAt)).font(.caption).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 4) {
                Text(row.admin.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                if let target = row.target {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.muted)
                    if linksToTarget {
                        Button(target.label) { console.open(user: target.id) }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
                    } else {
                        Text(target.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                    }
                }
            }
            if let detail = row.detail {
                DisclosureGroup(isExpanded: $expanded) {
                    Text(detail.prettyPrinted).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.foregroundSecondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                } label: {
                    Text("Details").font(.caption).foregroundStyle(Theme.muted)
                }
                .tint(Theme.link)
            }
        }
        .padding(.vertical, 8)
    }

    static func title(_ action: AdminAuditAction) -> String {
        switch action {
        case .userPatch: "User edited"
        case .resetPassword: "Password set"
        case .forceLogout: "Signed out everywhere"
        case .cpuCreate: "CPU created"
        case .cpuPatch: "CPU edited"
        case .cpuDelete: "CPU deleted"
        case .feedbackPatch: "Feedback updated"
        case .passwordResetSelf: "Password reset (self)"
        case .accountDeleteSelf: "Account deleted (self)"
        case .unknown: action.rawValue
        }
    }

    static func style(_ action: AdminAuditAction) -> Chip.Style {
        switch action {
        case .forceLogout, .cpuDelete, .accountDeleteSelf: .danger
        case .resetPassword, .passwordResetSelf: .warning
        case .feedbackPatch: .success
        default: .accent
        }
    }
}
