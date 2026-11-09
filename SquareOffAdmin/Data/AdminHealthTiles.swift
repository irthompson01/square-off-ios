import Foundation
import SquareOffNet

/// The Overview's five health tiles, in the web's order (`health-strip.tsx`). An older server
/// without the engine probe shows "Unknown" rather than a false alarm.
struct HealthTile: Equatable, Identifiable {
    let title: String
    let state: AdminChips.HealthState
    let detail: String
    let note: String?

    var id: String { title }
}

nonisolated enum HealthTiles {
    static func tiles(for health: AdminHealth) -> [HealthTile] {
        [database(health.db), model(health.model), engine(health.engine), mail(health.mail), app(health.app)]
    }

    private static func latency(_ ms: Double?) -> String { ms.map { String(format: "%.0f ms", $0) } ?? "—" }

    static func database(_ db: AdminHealth.Database) -> HealthTile {
        HealthTile(title: "Database", state: db.ok ? .ok : .down, detail: db.ok ? latency(db.latencyMs) : (db.error ?? "Unreachable"),
                   note: db.pool.map { "Pool \($0.inUse) of \($0.max) in use" })
    }

    static func model(_ model: AdminHealth.Model) -> HealthTile {
        HealthTile(title: "Neural model", state: model.ok ? .ok : .down, detail: model.ok ? latency(model.latencyMs) : (model.error ?? "Probe failed"),
                   note: model.cached ? "Cached probe" : nil)
    }

    static func engine(_ engine: AdminHealth.Engine?) -> HealthTile {
        guard let engine else { return HealthTile(title: "Engine", state: .unknown, detail: "No engine probe", note: nil) }
        let note = [engine.version.map { "v\($0)" }, engine.cached ? "Cached probe" : nil].compactMap { $0 }.joined(separator: " · ")
        return HealthTile(title: "Engine", state: engine.ok ? .ok : .down, detail: engine.ok ? latency(engine.latencyMs) : (engine.error ?? "Down"),
                          note: note.isEmpty ? nil : note)
    }

    static func mail(_ mail: AdminHealth.Mail) -> HealthTile {
        HealthTile(title: "Mail", state: mail.configured ? .ok : .off, detail: mail.server ?? "Not configured", note: nil)
    }

    static func app(_ app: AdminHealth.App) -> HealthTile {
        HealthTile(title: "App", state: .ok, detail: "v\(app.version)\(app.buildSha.map { " · \($0.prefix(7))" } ?? "")",
                   note: "\(app.env) · up \(AdminFormat.duration(app.uptimeS))")
    }
}
