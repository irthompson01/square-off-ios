import SwiftUI

/// Placeholder until the stats screen lands (Part G).
struct StatsView: View {
    var body: some View {
        ScrollView {
            PageHeading(title: "Game stats", description: "Your record across every game, by opponent type.")
                .padding(16)
        }
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
