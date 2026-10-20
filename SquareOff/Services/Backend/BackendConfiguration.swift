import Foundation
import SquareOffNet

/// Which server the app talks to. `mock` is the in-app simulation (default); `live` is the
/// docker stack on this Mac.
nonisolated enum BackendKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case mock, live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: "Mock (in-app)"
        case .live: "Local docker"
        }
    }
}

/// Everything that depends on the chosen backend. Persisted in UserDefaults; the `-backend`
/// launch argument (`mock` | `live`) wins for one launch because it lands in the argument domain.
nonisolated struct BackendConfiguration: Equatable, Sendable {
    enum Keys {
        static let kind = "backend"
        static let apiBaseURL = "backendAPIBaseURL"
        static let cpuMovesFromServer = "backendCPUMovesFromServer"
    }

    var kind: BackendKind
    var environment: APIEnvironment
    /// Developer toggle: route every CPU level through `POST /cpu_move`, not only the CNN.
    var cpuMovesFromServer = false

    static let mock = BackendConfiguration(kind: .mock, environment: .local)
    static let localDocker = BackendConfiguration(kind: .live, environment: .local)

    /// Guards persisted online sessions and guest ids against a backend switch.
    var id: String { "\(kind.rawValue)|\(environment.baseURL.host() ?? "")" }

    static func load(from defaults: UserDefaults = .standard) -> BackendConfiguration {
        let kind = defaults.string(forKey: Keys.kind).flatMap(BackendKind.init(rawValue:)) ?? .mock
        var configuration = kind == .live ? localDocker : mock
        if kind == .live,
           let override = defaults.string(forKey: Keys.apiBaseURL),
           let url = URL(string: override), let host = url.host(), let port = url.port {
            configuration.environment = .host(host, port: port, secure: url.scheme != "http",
                                              webOrigin: APIEnvironment.local.webOrigin)
        }
        configuration.cpuMovesFromServer = defaults.bool(forKey: Keys.cpuMovesFromServer)
        return configuration
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: Keys.kind)
        defaults.set(cpuMovesFromServer, forKey: Keys.cpuMovesFromServer)
    }
}
