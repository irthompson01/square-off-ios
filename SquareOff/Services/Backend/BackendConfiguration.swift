import Foundation
import SquareOffNet

/// Which server the app talks to. `production` is square-off.com (the only kind a Release
/// build knows); `local` is the docker stack on this Mac and `mock` the in-app simulation,
/// both Debug-only developer choices.
nonisolated enum BackendKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case production, local, mock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .production: "Production"
        case .local: "Local docker"
        case .mock: "Mock (in-app)"
        }
    }

    /// The kinds this build can run. A Release build cannot be flipped to the mock or the
    /// docker stack through defaults or launch arguments.
    static var available: [BackendKind] {
        #if DEBUG
        [.production, .local, .mock]
        #else
        [.production]
        #endif
    }

    static var `default`: BackendKind {
        #if DEBUG
        .mock
        #else
        .production
        #endif
    }

    /// Persisted value → kind. `live` is the name `.local` had before production existed, so
    /// existing installs and `-backend live` keep working.
    init?(persisted raw: String) {
        if raw == "live" { self = .local; return }
        guard let kind = BackendKind(rawValue: raw) else { return nil }
        self = kind
    }
}

/// Everything that depends on the chosen backend. Persisted in UserDefaults; the `-backend`
/// launch argument (`production` | `local` | `mock`) wins for one launch because it lands in
/// the argument domain.
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

    static let production = BackendConfiguration(kind: .production, environment: .production)
    static let mock = BackendConfiguration(kind: .mock, environment: .local)
    static let localDocker = BackendConfiguration(kind: .local, environment: .local)

    static func standard(for kind: BackendKind) -> BackendConfiguration {
        switch kind {
        case .production: production
        case .local: localDocker
        case .mock: mock
        }
    }

    /// Guards persisted online sessions and guest ids against a backend switch.
    var id: String { "\(kind.rawValue)|\(environment.baseURL.host() ?? "")" }

    /// Where shared invite links point. The mock has no web client of its own, so its links
    /// (like production's) go to square-off.com; only the docker stack links to the Vite client.
    var inviteOrigin: URL {
        kind == .local ? environment.webOrigin : APIEnvironment.production.webOrigin
    }

    static func load(from defaults: UserDefaults = .standard,
                     available: [BackendKind] = BackendKind.available) -> BackendConfiguration {
        let persisted = defaults.string(forKey: Keys.kind).flatMap(BackendKind.init(persisted:))
        let fallback = available.contains(.default) ? BackendKind.default : (available.first ?? .production)
        let kind = persisted.flatMap { available.contains($0) ? $0 : nil } ?? fallback
        var configuration = standard(for: kind)
        #if DEBUG
        if kind == .local,
           let override = defaults.string(forKey: Keys.apiBaseURL),
           let url = URL(string: override), let host = url.host(), let port = url.port {
            configuration.environment = .host(host, port: port, secure: url.scheme != "http",
                                              webOrigin: APIEnvironment.local.webOrigin)
        }
        #endif
        configuration.cpuMovesFromServer = defaults.bool(forKey: Keys.cpuMovesFromServer)
        return configuration
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: Keys.kind)
        defaults.set(cpuMovesFromServer, forKey: Keys.cpuMovesFromServer)
    }
}
