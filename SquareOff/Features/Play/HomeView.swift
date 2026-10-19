import SwiftUI

enum PlayMode: String, CaseIterable, Identifiable {
    case cpu, passAndPlay, online

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "Vs Computer"
        case .passAndPlay: "Pass & Play"
        case .online: "Online"
        }
    }

    var subtitle: String {
        switch self {
        case .cpu: "Six AI levels, from Random to Max-Min-IO"
        case .passAndPlay: "2–4 friends sharing this device"
        case .online: "Quick match, room code or open lobby"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .passAndPlay: "iphone"
        case .online: "globe"
        }
    }

    var tint: Color { Color(hex: Theme.playerColors[PlayMode.allCases.firstIndex(of: self) ?? 0]) }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isSignInPresented = false
    @State private var selectedMode: PlayMode = .cpu

    var body: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $isSignInPresented) { SignInView() }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero.padding(.vertical, 28)
                NavigationLink { PlayModeView() } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                NavigationLink { OnlineHubView() } label: {
                    Label("Quick Match Online", systemImage: "globe")
                }
                .buttonStyle(SecondaryButtonStyle())
                continueCard.padding(.top, 10)
                if app.account == .guest { signInPrompt }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: iPad

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Play").font(.largeTitle.bold())
                ForEach(PlayMode.allCases) { mode in
                    Button { selectedMode = mode } label: {
                        ModeCard(mode: mode, isSelected: selectedMode == mode, showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
                continueCard.padding(.top, 8)
                if app.account == .guest { signInPrompt }
                Spacer()
            }
            .frame(width: 380)

            Group {
                switch selectedMode {
                case .cpu: SetupForm(kind: .cpu)
                case .passAndPlay: SetupForm(kind: .passAndPlay)
                case .online: OnlineHubView()
                }
            }
            .id(selectedMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(28)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Shared pieces

    private var hero: some View {
        VStack(spacing: 14) {
            LogoMark().frame(width: 72, height: 72)
            Text("SQUARE OFF").font(Theme.display(40)).minimumScaleFactor(0.7).lineLimit(1)
            Text("A Strategic Battle of Shapes").font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var continueCard: some View {
        if let session = app.activeGame, !session.isOver {
            Button { app.isGamePresented = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: session.currentPlayer.colorHex))
                        .frame(width: 44, height: 44)
                        .background(Theme.tileEmpty, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONTINUE GAME").font(.caption.weight(.semibold)).foregroundStyle(Theme.link)
                        Text(session.config.title).font(.headline).lineLimit(1)
                        Text("\(session.turnLabel) · Move \(session.game.moves.count + 1)").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
                }
                .padding(14)
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save your stats").font(.headline)
            Text("You're playing as a guest. Sign in to track wins and play online under your name.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Button("Sign in") { isSignInPresented = true }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct PlayModeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("2–4 players. Fill the grid, form squares and diamonds, and score the most points.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 8)
                NavigationLink { SetupForm(kind: .cpu) } label: { ModeCard(mode: .cpu) }
                NavigationLink { SetupForm(kind: .passAndPlay) } label: { ModeCard(mode: .passAndPlay) }
                NavigationLink { OnlineHubView() } label: { ModeCard(mode: .online) }
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Play")
    }
}

struct ModeCard: View {
    let mode: PlayMode
    var isSelected = true
    var showsChevron = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: mode.symbol)
                .font(.title2)
                .foregroundStyle(mode.tint.mix(with: .white, by: 0.4))
                .frame(width: 56, height: 56)
                .background(mode.tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title).font(.headline)
                Text(mode.subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if showsChevron { Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary) }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(isSelected && !showsChevron ? mode.tint.opacity(0.14) : Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? mode.tint.opacity(0.5) : Theme.hairline, lineWidth: isSelected && !showsChevron ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}

/// Four coloured tiles joined by a square outline.
struct LogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width
            let tile = s * 0.36
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: tile * 0.23, style: .continuous)
                        .fill(Color(hex: Theme.playerColors[i]))
                        .frame(width: tile, height: tile)
                        .position(x: i % 2 == 0 ? tile / 2 + s * 0.05 : s - tile / 2 - s * 0.05,
                                  y: i < 2 ? tile / 2 + s * 0.05 : s - tile / 2 - s * 0.05)
                }
                Rectangle()
                    .stroke(.white, lineWidth: 2.5)
                    .frame(width: s - tile - s * 0.1, height: s - tile - s * 0.1)
            }
        }
        .accessibilityHidden(true)
    }
}
