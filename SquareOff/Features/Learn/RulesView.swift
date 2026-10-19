import SquareOffCore
import SwiftUI

/// How to Play, condensed from the web rulebook (`data/rulebook-content.ts`).
struct RulesView: View {
    enum Section: String, CaseIterable, Identifiable {
        case basics = "Basics"
        case scoring = "Scoring"
        case multipliers = "Multipliers"
        var id: String { rawValue }
    }

    @State private var section: Section = .basics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch section {
                case .basics: basics
                case .scoring: scoring
                case .multipliers: multipliers
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("How to Play")
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Take turns claiming one tile at a time. Claim four tiles that make a square or a diamond to score. When every tile is taken, the highest score wins.")
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 12) {
                ShapeExample(kind: .square, color: Color(hex: "#0583D2"), caption: "4×4 = 16 pts")
                ShapeExample(kind: .diamond, color: Color(hex: "#FF3131"), caption: "3×3 = 18 pts (2× area)")
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("One tile per turn, and no undo.", systemImage: "hand.tap")
                Label("Rectangles don't count.", systemImage: "rectangle.slash")
                Label("Tie? Whoever formed the most shapes wins.", systemImage: "equal.circle")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var scoring: some View {
        HStack(alignment: .top, spacing: 12) {
            table("Squares", tint: "#8FCBF2", rows: (2...8).reversed().map { ("\($0)×\($0)", $0 * $0) })
            VStack(alignment: .leading, spacing: 8) {
                table("Diamonds", tint: "#FF8F8F", rows: (2...4).reversed().map { ("\($0)×\($0)", 2 * $0 * $0) })
                Text("Diamonds score double their area.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var multipliers: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Form two or more shapes with one tile and your multiplier grows. Form fewer than two and it resets to ×1.")
                .foregroundStyle(.white.opacity(0.85))
            VStack(spacing: 10) {
                Text("2 + 3 − 1 = 4").font(.system(size: 28, weight: .bold, design: .monospaced))
                HStack {
                    Text("Current ×"); Spacer(); Text("New shapes"); Spacer(); Text("New ×")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(18)
            .card()
            VStack(alignment: .leading, spacing: 6) {
                Text("Blue: (16 + 16) × 2 = 64 pts")
                Text("Red: (18 + 9) × 2 = 54 pts")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func table(_ title: String, tint: String, rows: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).foregroundStyle(Color(hex: tint)).padding(.bottom, 8)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(row.1)").bold().monospacedDigit()
                }
                .frame(minHeight: 32)
                Divider().overlay(Theme.hairline)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .card()
    }
}

private struct ShapeExample: View {
    let kind: ShapeKind
    let color: Color
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let gap: CGFloat = 3
                let tile = (proxy.size.width - gap * 4) / 5
                let layout = BoardLayout(tile: tile, gap: gap)
                let shape = kind == .square
                    ? BoardShape(kind: .square, row: 0, col: 0, num: 3, ownerID: 1)
                    : BoardShape(kind: .diamond, row: 0, col: 0, num: 2, ownerID: 1)
                let corners = Set(shape.corners)
                ZStack(alignment: .topLeading) {
                    VStack(spacing: gap) {
                        ForEach(0..<5, id: \.self) { r in
                            HStack(spacing: gap) {
                                ForEach(0..<5, id: \.self) { c in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(corners.contains(Cell(row: r, col: c)) ? color : Theme.tileEmpty)
                                        .frame(width: tile, height: tile)
                                }
                            }
                        }
                    }
                    ShapeOverlay(shape: shape, color: color, layout: layout, startCorner: nil)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            Text(kind == .square ? "Square" : "Diamond").font(.headline)
            Text(caption).font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .card()
        .accessibilityElement(children: .combine)
    }
}
