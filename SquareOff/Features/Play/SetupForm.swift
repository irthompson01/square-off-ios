import SquareOffCore
import SwiftUI

/// Game setup for Vs Computer and Pass & Play. Options match the web (`components/setup/options.ts`).
struct SetupForm: View {
    enum Kind { case cpu, passAndPlay }

    let kind: Kind
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var boardSize = 8
    @State private var level: CPULevel = .maxMin
    @State private var timer = 0
    @State private var playerCount = 2
    @State private var players: [SetupPlayer] = (1...4).map {
        SetupPlayer(id: $0, name: "Player \($0)", colorHex: Theme.playerColors[$0 - 1])
    }

    static let boardSizes = Array(6...12)
    static let timers = [0, 10, 20, 30, 60]
    @State private var debugColorSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                boardSection
                if kind == .cpu { levelSection }
                if kind == .passAndPlay { playerCountSection }
                timerSection
                playersSection
            }
            .padding(16)
        }
        .appBackground()
        .safeAreaInset(edge: .bottom) {
            Button(action: startGame) {
                Label("Start Game", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.go))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.background.opacity(0.95))
        }
        .navigationTitle(kind == .cpu ? "Vs Computer" : "Pass & Play")
        .sheet(isPresented: $debugColorSheet) {
            ColorSwatchSheet(selection: $players[0].colorHex)
                .presentationDetents([.height(340)])
                .presentationBackground(Theme.surface)
        }
        .onAppear {
            if app.pendingColorPicker {
                app.pendingColorPicker = false
                debugColorSheet = true
            }
        }
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SectionLabel("Board size")
                Spacer()
                BoardPreview(size: boardSize).frame(width: 34, height: 34)
                Text(tileNote).font(.footnote).foregroundStyle(tilePoints < 40 ? Theme.warning : Theme.textSecondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Self.boardSizes, id: \.self) { size in
                    ChipButton(title: "\(size)×\(size)", isSelected: boardSize == size) { boardSize = size }
                }
            }
        }
        .padding(14)
        .card()
    }

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("CPU level")
                Spacer()
                Text(level.shortName).font(.subheadline.weight(.semibold))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(CPULevel.allCases) { option in
                    let enabled = option != .cnn || cnnSelectable
                    ChipButton(title: "\(option.number)", isSelected: level == option, height: 44) { level = option }
                        .disabled(!enabled)
                        .opacity(enabled ? 1 : 0.35)
                        .accessibilityLabel("Level \(option.number), \(option.shortName)\(enabled ? "" : ", only on 8×8 boards")")
                }
            }
            HStack {
                Text("Easier")
                Spacer()
                Text("Harder")
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            Label(CPUAvailability.footnote(kind: app.backend.configuration.kind, boardSize: boardSize), systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .card()
        .onChange(of: boardSize) { _, _ in
            if level == .cnn, !cnnSelectable { level = .maxMin }
        }
    }

    private var cnnSelectable: Bool {
        app.backend.supportsServerCPU(boardSize: boardSize, playerCount: 2)
    }

    private var playerCountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Players")
            Picker("Players", selection: $playerCount) {
                ForEach(2...4, id: \.self) { Text("\($0) players").tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .card()
    }

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Turn timer")
            Picker("Turn timer", selection: $timer) {
                ForEach(Self.timers, id: \.self) { Text($0 == 0 ? "Off" : "\($0)s").tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .card()
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(kind == .cpu ? "Your color" : "Names & colors")
            ForEach(0..<(kind == .cpu ? 1 : playerCount), id: \.self) { index in
                HStack(spacing: 10) {
                    TextField("Player \(index + 1)", text: $players[index].name)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                    ColorSwatchPicker(selection: $players[index].colorHex)
                }
            }
        }
        .padding(14)
        .card()
    }

    /// iPhone board ≈ 358pt wide with 4pt gaps; iPad landscape ≈ 760pt with 6pt gaps.
    private var tilePoints: Int {
        let (width, gap): (CGFloat, CGFloat) = sizeClass == .regular ? (760, 6) : (358, 4)
        return Int((width - CGFloat(boardSize - 1) * gap) / CGFloat(boardSize))
    }

    private var tileNote: String {
        "≈\(tilePoints)pt tiles" + (tilePoints < 40 ? " · pinch to zoom" : "")
    }

    private func startGame() {
        let seats = Array(players.prefix(kind == .cpu ? 1 : playerCount)).map { seat in
            var seat = seat
            if seat.name.trimmingCharacters(in: .whitespaces).isEmpty { seat.name = "Player \(seat.id)" }
            return seat
        }
        app.start(GameConfig(
            mode: kind == .cpu ? .cpu(level) : .passAndPlay,
            boardSize: boardSize,
            timerSeconds: timer,
            players: seats
        ))
    }
}

struct ChipButton: View {
    let title: String
    let isSelected: Bool
    var height: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: height)
                .foregroundStyle(isSelected ? .white : Color(hex: "#C8C8D6"))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color(hex: "#0583D2").opacity(0.28) : Theme.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color(hex: "#0583D2") : Theme.hairline)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Player colour: the eight preset swatches, or any colour from the system colour wheel.
struct ColorSwatchPicker: View {
    @Binding var selection: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: selection))
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.6), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color \(selection)")
        .sheet(isPresented: $isPresented) {
            ColorSwatchSheet(selection: $selection)
                .presentationDetents([.height(340)])
                .presentationBackground(Theme.surface)
        }
    }
}

struct ColorSwatchSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var custom: Color

    init(selection: Binding<String>) {
        _selection = selection
        _custom = State(initialValue: Color(hex: selection.wrappedValue))
    }

    private var isPreset: Bool { Theme.swatches.contains(selection.uppercased()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Pick a color").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.font(.headline)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Theme.swatches, id: \.self) { hex in
                    Button {
                        selection = hex
                        custom = Color(hex: hex)
                    } label: {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: hex))
                            .aspectRatio(1.4, contentMode: .fit)
                            .overlay {
                                if selection.uppercased() == hex {
                                    Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white).shadow(radius: 2)
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(selection.uppercased() == hex ? 0.9 : 0.15), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
            }
            HStack(spacing: 12) {
                ColorPicker(selection: $custom, supportsOpacity: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom color").font(.subheadline.weight(.semibold))
                        Text(isPreset ? "Open the color wheel to pick any shade" : "Using \(selection.uppercased())")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .onChange(of: custom) { _, color in
                    let hex = color.hexString
                    if hex != selection.uppercased() { selection = hex }
                }
            }
            .padding(14)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

struct BoardPreview: View {
    let size: Int

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(0..<size, id: \.self) { _ in
                GridRow {
                    ForEach(0..<size, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: "#34344A"))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: size)
        .accessibilityHidden(true)
    }
}
