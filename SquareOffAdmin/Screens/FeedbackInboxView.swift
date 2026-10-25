import SquareOffNet
import SwiftUI

/// The feedback inbox: New / Handled / All, a detail sheet with notes and the status switch
/// (web `pages/admin/feedback.tsx`).
struct FeedbackInboxView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var list: PagedQuery<AdminFeedbackItem, FeedbackStatus?>?
    @State private var counts: AdminFeedbackPage.Counts?
    @State private var filter: Filter = .new
    @State private var selected: AdminFeedbackItem?

    enum Filter: String, CaseIterable, Identifiable {
        case new, handled, all
        var id: String { rawValue }
        var status: FeedbackStatus? {
            switch self {
            case .new: .new
            case .handled: .handled
            case .all: nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "Feedback", description: "What players sent from the app and the site.")
                SegmentedPills(options: Filter.allCases, selection: $filter, title: { option in
                    switch option {
                    case .new: "New\(counts.map { " · \($0.new)" } ?? "")"
                    case .handled: "Handled\(counts.map { " · \($0.handled)" } ?? "")"
                    case .all: "All"
                    }
                }, compact: true)
                if let list {
                    if let error = list.error, list.items.isEmpty {
                        SectionError(message: error) { Task { await list.load() } }
                    } else if list.status == .loading {
                        SkeletonRows().padding(.horizontal, 16).card()
                    } else if list.items.isEmpty {
                        EmptyState(symbol: "tray", title: filter == .new ? "Inbox zero" : "Nothing here", text: filter == .new ? "No new feedback." : "No messages match.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(list.items) { item in
                                Button { selected = item } label: { row(item) }.buttonStyle(.plain)
                                if item.id != list.items.last?.id { Theme.separator.frame(height: 1) }
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
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if list == nil {
                let api = app.admin
                list = PagedQuery(query: filter.status) { status, page in
                    let result = try await api.feedback(status: status, page: page)
                    return (result.total, result.items)
                }
                Task { await list?.load(); await refreshCounts() }
            }
        }
        .onChange(of: filter) { _, filter in Task { await list?.setQuery(filter.status) } }
        .sheet(item: $selected) { item in
            FeedbackDetailSheet(item: item) { updated in
                Task { await list?.load(); await refreshCounts() }
                if let updated { selected = updated }
            }
            .presentationBackground(Theme.overlay)
        }
    }

    private func refreshCounts() async {
        if let page = try? await app.admin.feedback(status: nil, page: PageRequest(limit: 1, offset: 0)) {
            counts = page.counts
            console.newFeedbackCount = page.counts.new
        }
    }

    private func row(_ item: AdminFeedbackItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.subject).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                    AdminChips.feedback(item.status)
                }
                Text(item.message).font(.caption).foregroundStyle(Theme.foregroundSecondary).lineLimit(2)
                Text("\(item.displayName ?? item.user?.label ?? "Anonymous") · \(AdminFormat.relative(item.createdAt))").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct FeedbackDetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @Environment(\.dismiss) private var dismiss
    let item: AdminFeedbackItem
    let onChanged: (AdminFeedbackItem?) -> Void

    @State private var notes = ""
    @State private var pending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        AdminChips.feedback(item.status)
                        if !item.emailSent { Chip(text: "Email not sent", style: .warning) }
                        Spacer()
                        Text(AdminFormat.absolute(item.createdAt)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Text(item.message).font(.body).foregroundStyle(Theme.foreground).textSelection(.enabled)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card(fill: Theme.surfaceSecondary, radius: 12)
                    VStack(spacing: 0) {
                        DetailRow(label: "From", value: item.displayName ?? "Anonymous", dim: item.displayName == nil)
                        if let email = item.contactEmail {
                            HStack {
                                Text("Contact").font(.subheadline).foregroundStyle(Theme.muted)
                                Spacer()
                                Link(email, destination: URL(string: "mailto:\(email)")!).font(.subheadline.weight(.medium)).foregroundStyle(Theme.link)
                            }
                            .padding(.vertical, 8)
                        }
                        if let user = item.user {
                            HStack {
                                Text("Account").font(.subheadline).foregroundStyle(Theme.muted)
                                Spacer()
                                Button(user.label) { dismiss(); console.open(user: user.id) }.font(.subheadline.weight(.medium)).foregroundStyle(Theme.link)
                            }
                            .padding(.vertical, 8)
                        }
                        if let handledBy = item.handledBy {
                            DetailRow(label: "Handled by", value: "\(handledBy.username ?? handledBy.id) · \(AdminFormat.relative(item.handledAt))")
                        }
                    }
                    .padding(.horizontal, 16)
                    .card()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                        TextEditor(text: $notes)
                            .scrollContentBackground(.hidden).foregroundStyle(Theme.foreground).frame(minHeight: 100).padding(8)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.fieldBorder))
                    }
                    HStack(spacing: 10) {
                        Button { save(status: item.status == .handled ? .new : .handled) } label: {
                            PendingLabel(title: item.status == .handled ? "Reopen" : "Mark handled", pendingTitle: "Saving…", symbol: item.status == .handled ? "arrow.uturn.backward" : "checkmark", isPending: pending)
                        }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false)).disabled(pending)
                        Button("Save notes") { save(status: nil) }.buttonStyle(SecondaryButtonStyle(fullWidth: false)).disabled(pending || notes == (item.notes ?? ""))
                    }
                }
                .padding(16)
            }
            .background(Theme.overlay)
            .navigationTitle(item.subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { notes = item.notes ?? "" }
    }

    private func save(status: FeedbackStatus?) {
        pending = true
        Task {
            defer { pending = false }
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            var patch = AdminFeedbackPatch(status: status)
            if trimmed != (item.notes ?? "") {
                if trimmed.isEmpty { patch.clearNotes = true } else { patch.notes = trimmed }
            }
            do {
                let result = try await app.admin.patchFeedback(id: item.id, patch)
                app.toasts.success(status == .handled ? "Marked handled" : (status == .new ? "Reopened" : "Notes saved"))
                onChanged(result.item)
                if status != nil { dismiss() }
            } catch {
                app.toasts.danger("Couldn't update the feedback", description: AdminErrors.message(for: error))
            }
        }
    }
}
