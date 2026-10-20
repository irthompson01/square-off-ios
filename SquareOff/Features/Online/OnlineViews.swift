import SwiftUI

/// Online hub. MOCK: these flows will call the matcher REST API + `/ws` (see docs/UI_RESEARCH.md);
/// for now they lead to a simulated waiting room and start a Pass & Play game.
struct OnlineHubView: View {
    @State private var boardSize = 8
    @State private var timer = 20
    @State private var roomCode = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                quickMatch
                joinFriend
                VStack(spacing: 0) {
                    NavigationLink { WaitingRoomView(kind: .created(code: Self.mockCode()), boardSize: boardSize, timer: timer) } label: {
                        row("Create a room", systemImage: "plus.square")
                    }
                    Divider().overlay(Theme.hairline)
                    NavigationLink { OpenRoomsView() } label: {
                        row("Browse open rooms", systemImage: "list.bullet")
                    }
                }
                .buttonStyle(.plain)
                .card()
                MockBadge()
            }
            .padding(16)
        }
        .appBackground()
        .navigationTitle("Online")
    }

    private var quickMatch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Match").font(.title3.bold())
                Spacer()
                Menu {
                    Picker("Board", selection: $boardSize) {
                        ForEach(SetupForm.boardSizes, id: \.self) { Text("\($0)×\($0)").tag($0) }
                    }
                    Picker("Timer", selection: $timer) {
                        ForEach(SetupForm.timers, id: \.self) { Text($0 == 0 ? "No timer" : "\($0)s").tag($0) }
                    }
                } label: {
                    Label("\(boardSize)×\(boardSize) · \(timer == 0 ? "No timer" : "\(timer)s")", systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Theme.surfaceRaised, in: Capsule())
                }
            }
            Text("We'll pair you with someone who picked the same board and timer.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            NavigationLink { WaitingRoomView(kind: .quickMatch, boardSize: boardSize, timer: timer) } label: {
                Label("Find a match", systemImage: "magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.go))
        }
        .padding(16)
        .card(tint: Color(hex: "#50C878"))
    }

    private var joinFriend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join a friend").font(.title3.bold())
            HStack(spacing: 10) {
                TextField("Room code", text: $roomCode)
                    .keyboardType(.numberPad)
                    .font(.title3.monospaced().weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: roomCode) { _, value in roomCode = String(value.filter(\.isNumber).prefix(6)) }
                NavigationLink { WaitingRoomView(kind: .joined(code: roomCode), boardSize: boardSize, timer: timer) } label: {
                    Text("Join").font(.headline).padding(.horizontal, 20).frame(height: 50)
                        .background(Color(hex: "#0583D2"), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(roomCode.isEmpty)
                .opacity(roomCode.isEmpty ? 0.5 : 1)
            }
            Text("Or open an invite link: it lands right in the room.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .card()
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).foregroundStyle(Theme.link).frame(width: 24)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    static func mockCode() -> String { String(Int.random(in: 10_000...99_999)) }
}

struct WaitingRoomView: View {
    enum Kind: Hashable {
        case quickMatch
        case created(code: String)
        case joined(code: String)
    }

    let kind: Kind
    let boardSize: Int
    let timer: Int

    @Environment(AppModel.self) private var app
    @State private var opponents: [String] = []
    @State private var code = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    SectionLabel(kind == .quickMatch ? "Quick match" : "Room code")
                    Text(kind == .quickMatch && opponents.isEmpty ? "Searching…" : code)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .tracking(6)
                    HStack(spacing: 8) {
                        chip("\(boardSize)×\(boardSize) board")
                        chip(timer == 0 ? "No timer" : "\(timer)s turns")
                    }
                    if kind != .quickMatch {
                        HStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.string = code
                            } label: { Label("Copy code", systemImage: "doc.on.doc") }
                                .buttonStyle(SecondaryButtonStyle())
                            ShareLink(item: URL(string: "https://square-off.example/guest/\(code)")!) {
                                Label("Invite", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Players · \(1 + opponents.count) of 4")
                    slot(name: app.account.displayName + " (you)", color: Theme.playerColors[0], filled: true)
                    ForEach(0..<3, id: \.self) { i in
                        slot(name: opponents.indices.contains(i) ? opponents[i] : "Waiting for player…",
                             color: Theme.playerColors[i + 1], filled: opponents.indices.contains(i))
                    }
                }
                MockBadge()
            }
            .padding(16)
        }
        .appBackground()
        .safeAreaInset(edge: .bottom) {
            Button { startMockGame() } label: { Label("Start Game", systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle(color: Theme.go))
                .disabled(opponents.isEmpty)
                .opacity(opponents.isEmpty ? 0.5 : 1)
                .padding(16)
        }
        .navigationTitle(kind == .quickMatch ? "Finding a match" : "Waiting room")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            switch kind {
            case .quickMatch: code = OnlineHubView.mockCode()
            case .created(let c), .joined(let c): code = c
            }
            try? await Task.sleep(for: .seconds(kind == .quickMatch ? 2 : 1.5))
            withAnimation(.spring) { opponents = ["Opponent (mock)"] }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.footnote).padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func slot(name: String, color: String, filled: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(filled ? Color(hex: color) : .clear)
                .strokeBorder(Color(hex: color), style: StrokeStyle(lineWidth: filled ? 0 : 1.5, dash: [4]))
                .frame(width: 34, height: 34)
            Text(name).font(filled ? .headline : .subheadline).foregroundStyle(filled ? .white : Theme.textSecondary)
            Spacer()
            if filled { Text("Ready").font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: "#6FD99A")) }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .card()
    }

    private func startMockGame() {
        let seats = ([app.account.displayName] + opponents).enumerated().map { index, name in
            SetupPlayer(id: index + 1, name: name, colorHex: Theme.playerColors[index])
        }
        app.start(GameConfig(mode: .onlineMock, boardSize: boardSize, timerSeconds: timer, players: seats))
    }
}

struct OpenRoomsView: View {
    var body: some View {
        List {
            Section {
                ContentUnavailableView("No open rooms (mock)", systemImage: "rectangle.stack",
                                       description: Text("This list will come from GET /matcher/open."))
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Open rooms")
    }
}

struct MockBadge: View {
    var body: some View {
        Label("Mock: online play isn't connected yet", systemImage: "hammer")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 4)
    }
}
