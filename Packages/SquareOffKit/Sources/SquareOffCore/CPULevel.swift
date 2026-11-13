/// CPU difficulty, numbered exactly like the web's `CPU_LEVEL_OPTIONS` (eight levels since the
/// 2026-10-29 AI engine release). `rawValue` is the server's `cpu_type` string, which is what
/// stats and saved games key on.
public enum CPULevel: String, CaseIterable, Sendable, Codable, Identifiable {
    case random = "random"
    case maxRandom = "max-random"
    case maxMin = "max-min"
    case maxMinPlus = "max-min-plus"
    case maxMinOptimal = "max-min-optimal"
    case maxMinIO = "max-min-io"
    /// Rust alpha-beta search with an exact endgame; server only, 6×6 to 12×12.
    case grandmaster = "grandmaster"
    /// Neural network + search; server only, 6×6 to 12×12.
    case impossible = "impossible"
    /// Retired 2026-10-29 (it was level 3). Kept so saved games, replays and stats rows still
    /// decode; the server answers `cpu_move` for it with max-min, and so does the device.
    case cnn = "cnn"

    /// The ladder the setup screen offers, in order.
    public static let selectable: [CPULevel] = [.random, .maxRandom, .maxMin, .maxMinPlus, .maxMinOptimal, .maxMinIO, .grandmaster, .impossible]

    public var id: String { rawValue }

    public var number: Int {
        switch self {
        case .random: 1
        case .maxRandom: 2
        case .maxMin, .cnn: 3
        case .maxMinPlus: 4
        case .maxMinOptimal: 5
        case .maxMinIO: 6
        case .grandmaster: 7
        case .impossible: 8
        }
    }

    /// Short name used in the setup UI (`getCpuLevelShortName`).
    public var shortName: String {
        switch self {
        case .random: "Random"
        case .maxRandom: "Max-Random"
        case .maxMin: "Max-Min"
        case .maxMinPlus: "Max-Min Plus"
        case .maxMinOptimal: "Max-Min-Optimal"
        case .maxMinIO: "Max-Min-IO"
        case .grandmaster: "Grandmaster"
        case .impossible: "Impossible"
        case .cnn: "CNN"
        }
    }

    /// The stats filter's spelling (`components/profile/stats-filters.tsx`), which differs for two levels.
    public var statsLabel: String {
        switch self {
        case .maxMinOptimal: "Max-Min Optimal"
        case .maxMinIO: "Max-Min IO"
        default: shortName
        }
    }

    /// One line under the picker for the levels that need explaining (the CPU definitions' text).
    public var description: String? {
        switch self {
        case .maxMinPlus: "Greedy with lookahead on the opponent's best shape"
        case .grandmaster: "Alpha-beta search with exact endgame"
        case .impossible: "Neural network + search"
        default: nil
        }
    }

    public var cpuType: String { rawValue }

    public var isRetired: Bool { self == .cnn }

    /// Levels 7 and 8 are the server's engine; nothing on the device approximates them.
    public var isServerOnly: Bool { self == .grandmaster || self == .impossible }

    public var isAvailableOffline: Bool { !isServerOnly }

    /// The on-device stand-in when a level can't be played locally: the strongest heuristic
    /// for the engine tiers, max-min for the retired CNN (what the server plays for it too).
    public var offlineFallback: CPULevel {
        switch self {
        case .grandmaster, .impossible: .maxMinIO
        case .cnn: .maxMin
        default: self
        }
    }

    /// Boards the level plays on. The engine is built for 6×6 to 12×12 (`src/ai/state.py`).
    public var supportedBoardSizes: ClosedRange<Int> { isServerOnly ? 6...12 : 2...20 }

    public init?(number: Int) {
        guard let level = Self.selectable.first(where: { $0.number == number }) else { return nil }
        self = level
    }
}
