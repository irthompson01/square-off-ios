import SwiftUI

/// Navigation targets pushed on the Play tab.
enum PlayRoute: Hashable {
    case play
    case stats
}

/// Home (web `/`): the wordmark, the tagline, the Continue card and the four neon tiles.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var signIn: SignInView.Mode?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: sizeClass == .regular ? 32 : 24) {
                        VStack(spacing: 16) {
                            Wordmark(size: .hero)
                                .accessibilityAddTraits(.isHeader)
                            Text("A Strategic Battle of Shapes")
                                .font(.system(size: sizeClass == .regular ? 20 : 17, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(Theme.foregroundSecondary)
                        }
                        if let session = app.activeGame, !session.isOver {
                            ContinueGameCard(session: session).frame(maxWidth: 448)
                        }
                        tiles
                            .frame(maxWidth: sizeClass == .regular ? 320 : 256)
                    }
                    .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                    Text("Music by Missy Cundiff")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 24)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .appBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $signIn) { mode in SignInView(initialMode: mode) }
    }

    private var tiles: some View {
        let signedIn = app.account.isSignedIn
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                NeonTile(tone: .sky, symbol: "gamecontroller", title: "Play now") { app.pendingPlayRoute = .play }
                NeonTile(tone: .rose, symbol: "book", title: "How to play") { app.selectedTab = .learn }
            }
            GridRow {
                if signedIn {
                    NeonTile(tone: .emerald, symbol: "person", title: "Profile") { app.selectedTab = .profile }
                    NeonTile(tone: .amber, symbol: "chart.bar", title: "Stats") { app.pendingPlayRoute = .stats }
                } else {
                    NeonTile(tone: .emerald, symbol: "arrow.right.to.line", title: "Log in") { signIn = .signIn }
                    NeonTile(tone: .amber, symbol: "person.badge.plus", title: "Register") { signIn = .register }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Start")
    }
}
