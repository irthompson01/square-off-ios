import SquareOffNet
import SwiftUI

/// ⌘K on the web: a number opens that game's replay, two or more characters search users.
struct AdminSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var text = ""
    @State private var results: [AdminUserRow] = []
    @State private var searching = false
    @State private var error: String?
    @State private var replay: ReplayTarget?

    private var gameID: Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "Search", description: "A game number opens its replay; a name or email finds users.")
                LabeledField(label: "Find") {
                    TextField("Game #, username or email", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(Theme.foreground)
                }
                if let gameID {
                    Button { replay = ReplayTarget(id: gameID) } label: { Label("Open replay of game #\(String(gameID))", systemImage: "play.fill") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if let error { AlertBox(.danger, message: error) }
                if searching { ProgressView().tint(Theme.link).frame(maxWidth: .infinity) }
                if !results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(results) { user in
                            Button { console.open(user: user.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.username).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                                        Text(user.email).font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    AdminChips.role(user.appRole)
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if user.id != results.last?.id { Theme.separator.frame(height: 1) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .card()
                } else if text.count >= 2, gameID == nil, !searching, error == nil {
                    Text("No users match.").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: text) {
            results = []
            error = nil
            guard text.count >= 2, gameID == nil else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                results = try await app.admin.users(AdminUserQuery(q: text, page: PageRequest(limit: 8, offset: 0))).items
            } catch {
                self.error = AdminErrors.message(for: error)
            }
        }
        .sheet(item: $replay) { target in AdminReplaySheet(gameID: target.id) }
    }
}
