import Foundation
import SquareOffNet

/// Server timestamps come in two flavours: naive UTC (`2025-10-18T12:00:00`, the `games.*`
/// and `users.created_at` columns) and offset-aware (`…+00:00`, timestamptz). Both parse to
/// the right instant here; the web does the same in `parseIsoUtc`.
nonisolated enum ServerDate {
    // ISO8601DateFormatter isn't Sendable; building one per parse is cheap enough here.
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    static func parse(_ raw: String?) -> Date? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.contains(" ") && !text.contains("T") { text = text.replacingOccurrences(of: " ", with: "T") }
        let hasOffset = text.hasSuffix("Z") || text.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        if !hasOffset { text += "Z" }
        if text.hasSuffix("+0000") { text = String(text.dropLast(5)) + "Z" }
        return formatter(fractional: true).date(from: text) ?? formatter(fractional: false).date(from: text)
    }

    /// "Oct 18" for a `YYYY-MM-DD` bucket, formatted in UTC so the day never shifts.
    static func shortDay(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: components) else { return day }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

nonisolated enum AdminFormat {
    /// "6 min 40 s", "42 s", "1 h 3 min".
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        return secs > 0 ? "\(minutes) min \(secs) s" : "\(minutes) min"
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// "63.6%" or "—".
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    /// "3 min ago" / "2 h ago" / "Oct 18" for a server timestamp; "—" when missing.
    static func relative(_ raw: String?, now: Date = .now) -> String {
        guard let date = ServerDate.parse(raw) else { return "—" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400)) d ago" }
        return absolute(date, time: false)
    }

    /// "Oct 18, 2026, 2:05 PM" (local time zone).
    static func absolute(_ date: Date?, time: Bool = true) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: time ? .shortened : .omitted)
    }

    static func absolute(_ raw: String?, time: Bool = true) -> String {
        absolute(ServerDate.parse(raw), time: time)
    }

    /// "ISO date" for the `from` / `to` query parameters (UTC midnight).
    static func queryDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// The overview's 30-day comparison (web `overview-metrics.ts`).
nonisolated enum OverviewMetrics {
    static let windowDays = 30

    struct Totals: Equatable {
        var started = 0, local = 0, online = 0, cpu = 0, completed = 0, newUsers = 0, guestSessions = 0

        var completionRate: Double? {
            started > 0 ? (Double(completed) / Double(started) * 1000).rounded() / 10 : nil
        }
    }

    struct Trend: Equatable {
        enum Direction { case up, down, neutral }
        let direction: Direction
        /// "+28.6%", "-4%", "+1.2 pt", "0%".
        let label: String
    }

    static func totals(_ points: [AdminTimeseriesPoint]) -> Totals {
        points.reduce(into: Totals()) { t, p in
            t.started += p.gamesStarted.total
            t.local += p.gamesStarted.local
            t.online += p.gamesStarted.online
            t.cpu += p.gamesStarted.cpu
            t.completed += p.gamesCompleted
            t.newUsers += p.newUsers
            t.guestSessions += p.newGuestSessions
        }
    }

    /// The last `days` points and the `days` before them (oldest first, as the API sends them).
    static func splitWindows(_ series: [AdminTimeseriesPoint], days: Int = windowDays) -> (current: [AdminTimeseriesPoint], previous: [AdminTimeseriesPoint]) {
        let current = Array(series.suffix(days))
        let previousEnd = max(0, series.count - days)
        let previousStart = max(0, series.count - 2 * days)
        return (current, Array(series[previousStart..<previousEnd]))
    }

    private static func signed(_ value: Double, digits: Int, unit: String) -> String {
        let factor = pow(10.0, Double(digits))
        let rounded = (value * factor).rounded() / factor
        if rounded == 0 { return "0\(unit)" }
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.\(digits)f", rounded)
        return "\(rounded > 0 ? "+" : "")\(text)\(unit)"
    }

    private static func direction(_ delta: Double) -> Trend.Direction {
        delta > 0 ? .up : (delta < 0 ? .down : .neutral)
    }

    /// Relative change of a count; nil when there is nothing to compare against.
    static func percentTrend(current: Int, previous: Int) -> Trend? {
        guard previous > 0 else { return nil }
        let change = Double(current - previous) / Double(previous) * 100
        let label = signed(change, digits: 1, unit: "%")
        return Trend(direction: label == "0%" ? .neutral : direction(change), label: label)
    }

    /// Change of a percentage in points ("+1.2 pt"); nil when either side is unknown.
    static func pointTrend(current: Double?, previous: Double?) -> Trend? {
        guard let current, let previous else { return nil }
        let change = current - previous
        let label = signed(change, digits: 1, unit: " pt")
        return Trend(direction: label == "0 pt" ? .neutral : direction(change), label: label)
    }
}
