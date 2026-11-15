import Foundation

/// `/api/matcher/*` (hero-client/src/services/matcherAPI.ts). Open-room listing, host heartbeat
/// and quick-match tickets. Every route needs a player session (user or guest token); the
/// server takes the requester and the room's host from that session, so nothing here names them.
public protocol MatcherAPI: Sendable {
    func openRooms(boardSize: Int?, timer: Int?, limit: Int, offset: Int) async throws -> [OpenRoomDTO]
    /// 403 `not_room_host` unless the session is the room's host.
    func advertise(_ request: AdvertiseRoomRequest) async throws -> AdvertiseRoomResponse
    func delist(roomCode: Int) async throws
    func quickMatch(_ request: QuickMatchRequest) async throws -> QuickMatchResult
    func quickMatchStatus(ticketID: String) async throws -> QuickMatchResult
    func cancelQuickMatch(ticketID: String) async throws
}

public struct OpenRoomDTO: Codable, Sendable, Equatable, Identifiable {
    public let roomCode: Int
    public let boardSize: Int
    public let timer: Int
    public let slotsFilled: Int
    public let slotsMax: Int
    public let listed: Bool
    public let hostLabel: String
    /// Still returned by the server (the host's player id); informational only.
    public let hostKey: String
    /// Unix seconds.
    public let createdAt: Double
    public let lastHeartbeat: Double
    public let gameId: Int?

    public var id: Int { roomCode }

    public init(roomCode: Int, boardSize: Int, timer: Int, slotsFilled: Int, slotsMax: Int = 4, listed: Bool,
                hostLabel: String, hostKey: String, createdAt: Double, lastHeartbeat: Double, gameId: Int?) {
        self.roomCode = roomCode
        self.boardSize = boardSize
        self.timer = timer
        self.slotsFilled = slotsFilled
        self.slotsMax = slotsMax
        self.listed = listed
        self.hostLabel = hostLabel
        self.hostKey = hostKey
        self.createdAt = createdAt
        self.lastHeartbeat = lastHeartbeat
        self.gameId = gameId
    }

    enum CodingKeys: String, CodingKey {
        case timer, listed
        case roomCode = "room_code"
        case boardSize = "board_size"
        case slotsFilled = "slots_filled"
        case slotsMax = "slots_max"
        case hostLabel = "host_label"
        case hostKey = "host_key"
        case createdAt = "created_at"
        case lastHeartbeat = "last_heartbeat"
        case gameId = "game_id"
    }
}

public struct OpenRoomsResponse: Codable, Sendable, Equatable {
    public let rooms: [OpenRoomDTO]

    public init(rooms: [OpenRoomDTO]) { self.rooms = rooms }
}

public struct AdvertiseRoomRequest: Codable, Sendable, Equatable {
    public let roomCode: Int
    public let listed: Bool
    public let hostLabel: String

    public init(roomCode: Int, listed: Bool = true, hostLabel: String) {
        self.roomCode = roomCode
        self.listed = listed
        self.hostLabel = String(hostLabel.prefix(80))
    }

    enum CodingKeys: String, CodingKey {
        case listed
        case roomCode = "room_code"
        case hostLabel = "host_label"
    }
}

public struct AdvertiseRoomResponse: Codable, Sendable, Equatable {
    public let roomCode: Int
    public let listed: Bool
    public let slotsFilled: Int

    public init(roomCode: Int, listed: Bool, slotsFilled: Int) {
        self.roomCode = roomCode
        self.listed = listed
        self.slotsFilled = slotsFilled
    }

    enum CodingKeys: String, CodingKey {
        case listed
        case roomCode = "room_code"
        case slotsFilled = "slots_filled"
    }
}

public struct QuickMatchRequest: Codable, Sendable, Equatable {
    public let boardSize: Int
    public let timer: Int

    public init(boardSize: Int, timer: Int) {
        self.boardSize = boardSize
        self.timer = timer
    }

    enum CodingKeys: String, CodingKey {
        case timer
        case boardSize = "board_size"
    }
}

public struct QuickMatchResult: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case pending, matched }
    public enum Action: String, Codable, Sendable {
        case queued
        case waitForHost = "wait_for_host"
        case joinRoom = "join_room"
        case createRoom = "create_room"
    }

    public let status: Status
    public let action: Action
    public let ticketId: String?
    public let roomCode: Int?

    public init(status: Status, action: Action, ticketId: String? = nil, roomCode: Int? = nil) {
        self.status = status
        self.action = action
        self.ticketId = ticketId
        self.roomCode = roomCode
    }

    enum CodingKeys: String, CodingKey {
        case status, action
        case ticketId = "ticket_id"
        case roomCode = "room_code"
    }
}

public struct QuickMatchCancelRequest: Codable, Sendable, Equatable {
    public let ticketId: String

    public init(ticketId: String) {
        self.ticketId = ticketId
    }

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id"
    }
}

public struct LiveMatcherAPI: MatcherAPI {
    private let client: RESTClient

    public init(environment: APIEnvironment, session: URLSession = .shared, tokenProvider: (any TokenProvider)? = nil,
                sessionRecovery: SessionRecovery? = nil) {
        client = RESTClient(baseURL: environment.baseURL, session: session, tokenProvider: tokenProvider,
                            sessionRecovery: sessionRecovery)
    }

    public func openRooms(boardSize: Int?, timer: Int?, limit: Int, offset: Int) async throws -> [OpenRoomDTO] {
        var query = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
        if let boardSize { query.append(URLQueryItem(name: "board_size", value: String(boardSize))) }
        if let timer { query.append(URLQueryItem(name: "timer", value: String(timer))) }
        let response: OpenRoomsResponse = try await client.send("GET", "matcher/open", query: query)
        return response.rooms
    }

    public func advertise(_ request: AdvertiseRoomRequest) async throws -> AdvertiseRoomResponse {
        try await client.send("POST", "matcher/advertise", body: request)
    }

    public func delist(roomCode: Int) async throws {
        try await client.data("DELETE", "matcher/advertise/\(roomCode)")
    }

    public func quickMatch(_ request: QuickMatchRequest) async throws -> QuickMatchResult {
        try await client.send("POST", "matcher/quick-match", body: request)
    }

    public func quickMatchStatus(ticketID: String) async throws -> QuickMatchResult {
        try await client.send("GET", "matcher/quick-match/\(ticketID)")
    }

    public func cancelQuickMatch(ticketID: String) async throws {
        try await client.data("POST", "matcher/quick-match/cancel", body: QuickMatchCancelRequest(ticketId: ticketID))
    }
}
