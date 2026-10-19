/// CPU difficulty, numbered exactly like the web's `CPU_LEVEL_OPTIONS`.
/// `rawValue` is the server's `cpu_type` string, which is what stats and saved games key on.
public enum CPULevel: String, CaseIterable, Sendable, Codable, Identifiable {
    case random = "random"
    case maxRandom = "max-random"
    case cnn = "cnn"
    case maxMin = "max-min"
    case maxMinOptimal = "max-min-optimal"
    case maxMinIO = "max-min-io"

    public var id: String { rawValue }

    public var number: Int {
        switch self {
        case .random: 1
        case .maxRandom: 2
        case .cnn: 3
        case .maxMin: 4
        case .maxMinOptimal: 5
        case .maxMinIO: 6
        }
    }

    /// Short name used in the setup UI (`getCpuLevelShortName`).
    public var shortName: String {
        switch self {
        case .random: "Random"
        case .maxRandom: "Max-Random"
        case .cnn: "CNN"
        case .maxMin: "Max-Min"
        case .maxMinOptimal: "Max-Min-Optimal"
        case .maxMinIO: "Max-Min-IO"
        }
    }

    public var cpuType: String { rawValue }

    public init?(number: Int) {
        guard let level = Self.allCases.first(where: { $0.number == number }) else { return nil }
        self = level
    }
}
