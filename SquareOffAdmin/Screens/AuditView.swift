import SquareOffNet
import SwiftUI

/// Every admin action, newest first, filtered by action and date (web `pages/admin/audit.tsx`).
struct AuditView: View {
    @Environment(AppModel.self) private var app
    @State private var list: PagedQuery<AdminAuditRow, AdminAuditQuery>?
    @State private var draft = AdminAuditQuery()
    @State private var range = GameFiltersSheet.Range.any

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "Audit log", description: "Who changed what, with the server's detail for each action.")
                HStack(spacing: 8) {
                    Menu {
                        Button("Any action") { draft.action = nil; apply() }
                        ForEach(AdminAuditAction.allCases, id: \.self) { action in
                            Button(AuditRowView.title(action)) { draft.action = action; apply() }
                        }
                    } label: { Label(draft.action.map(AuditRowView.title) ?? "Any action", systemImage: "line.3.horizontal.decrease.circle") }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                    Menu {
                        ForEach(GameFiltersSheet.Range.allCases) { option in
                            Button(option.title) { range = option; applyRange(); apply() }
                        }
                    } label: { Label(range.title, systemImage: "calendar") }
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
                        EmptyState(symbol: "scroll", title: "No audit rows", text: "Nothing matches these filters.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(list.items) { row in
                                AuditRowView(row: row)
                                if row.id != list.items.last?.id { Theme.separator.frame(height: 1) }
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
        .navigationTitle("Audit log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if list == nil {
                let api = app.admin
                list = PagedQuery(query: draft) { query, page in
                    var q = query
                    q.page = page
                    let result = try await api.audit(q)
                    return (result.total, result.items)
                }
                Task { await list?.load() }
            }
        }
    }

    private func applyRange() {
        if let days = range.days {
            draft.from = AdminFormat.queryDay(Date().addingTimeInterval(-Double(days - 1) * 86_400))
            draft.to = AdminFormat.queryDay(Date().addingTimeInterval(86_400))
        } else {
            draft.from = nil
            draft.to = nil
        }
    }

    private func apply() {
        Task { await list?.setQuery(draft) }
    }
}
