import Foundation

/// Everything the server pushes over `/ws`, keyed by its `type` field. Unknown types decode to
/// `.unknown` so a newer server never breaks the receive loop.
public enum ServerMessage: Sendable, Equatable, Decodable {
    case roomCreated(RoomCreatedPayload)
    case playerJoined(PlayerPayload?)
    case gameState(GameSnapshotPayload)
    case gameUpdate(GameSnapshotPayload)
    case gameStart(spectatorCount: Int?)
    case gameReset(GameResetPayload)
    case playerSlotAssigned(id: Int, color: String?)
    case spectatorAssigned
    case promotedToPlayer(id: Int, color: String?)
    case spectatorCount(Int)
    case hostAway
    case hostDisconnected
    case guestAway(playerId: Int?)
    case guestDisconnected(playerId: Int?)
    case playerRejoined(playerId: Int?, role: OnlineRole?)
    case rejoinFailed(reason: String)
    case joinError(message: String)
    /// Added by the iOS server branch: the move was ignored (`not_your_turn`, `occupied`, `game_over`).
    case moveRejected(reason: String)
    case unknown(type: String)

    public var typeName: String {
        switch self {
        case .roomCreated: "ROOM_CREATED"
        case .playerJoined: "PLAYER_JOINED"
        case .gameState: "GAME_STATE"
        case .gameUpdate: "GAME_UPDATE"
        case .gameStart: "GAME_START"
        case .gameReset: "GAME_RESET"
        case .playerSlotAssigned: "PLAYER_SLOT_ASSIGNED"
        case .spectatorAssigned: "SPECTATOR_ASSIGNED"
        case .promotedToPlayer: "PROMOTED_TO_PLAYER"
        case .spectatorCount: "SPECTATOR_COUNT"
        case .hostAway: "HOST_AWAY"
        case .hostDisconnected: "HOST_DISCONNECTED"
        case .guestAway: "GUEST_AWAY"
        case .guestDisconnected: "GUEST_DISCONNECTED"
        case .playerRejoined: "PLAYER_REJOINED"
        case .rejoinFailed: "REJOIN_FAILED"
        case .joinError: "JOIN_ERROR"
        case .moveRejected: "MOVE_REJECTED"
        case let .unknown(type): type
        }
    }

    struct Keys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static let type = Keys(stringValue: "type")
        static let id = Keys(stringValue: "id")
        static let color = Keys(stringValue: "color")
        static let player = Keys(stringValue: "player")
        static let playerId = Keys(stringValue: "playerId")
        static let role = Keys(stringValue: "role")
        static let reason = Keys(stringValue: "reason")
        static let message = Keys(stringValue: "message")
        static let spectatorCount = Keys(stringValue: "spectatorCount")
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "ROOM_CREATED":
            self = .roomCreated(try RoomCreatedPayload(from: decoder))
        case "PLAYER_JOINED":
            self = .playerJoined(try? c.decodeIfPresent(PlayerPayload.self, forKey: .player))
        case "GAME_STATE":
            self = .gameState(try GameSnapshotPayload(from: decoder))
        case "GAME_UPDATE":
            self = .gameUpdate(try GameSnapshotPayload(from: decoder))
        case "GAME_START":
            self = .gameStart(spectatorCount: try LenientInt.decode(c, .spectatorCount))
        case "GAME_RESET":
            self = .gameReset(try GameResetPayload(from: decoder))
        case "PLAYER_SLOT_ASSIGNED":
            self = .playerSlotAssigned(id: try LenientInt.decode(c, .id) ?? 0, color: try? c.decodeIfPresent(String.self, forKey: .color))
        case "SPECTATOR_ASSIGNED":
            self = .spectatorAssigned
        case "PROMOTED_TO_PLAYER":
            self = .promotedToPlayer(id: try LenientInt.decode(c, .id) ?? 0, color: try? c.decodeIfPresent(String.self, forKey: .color))
        case "SPECTATOR_COUNT":
            self = .spectatorCount(try LenientInt.decode(c, .spectatorCount) ?? 0)
        case "HOST_AWAY":
            self = .hostAway
        case "HOST_DISCONNECTED":
            self = .hostDisconnected
        case "GUEST_AWAY":
            self = .guestAway(playerId: try LenientInt.decode(c, .playerId))
        case "GUEST_DISCONNECTED":
            self = .guestDisconnected(playerId: try LenientInt.decode(c, .playerId))
        case "PLAYER_REJOINED":
            self = .playerRejoined(playerId: try LenientInt.decode(c, .playerId),
                                  role: (try? c.decodeIfPresent(String.self, forKey: .role)).flatMap(OnlineRole.init(rawValue:)))
        case "REJOIN_FAILED":
            self = .rejoinFailed(reason: (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? "unknown")
        case "JOIN_ERROR":
            self = .joinError(message: (try? c.decodeIfPresent(String.self, forKey: .message)) ?? "Room full or not found")
        case "MOVE_REJECTED":
            self = .moveRejected(reason: (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? "rejected")
        default:
            self = .unknown(type: type)
        }
    }

    public static func decode(_ data: Data) throws -> ServerMessage {
        try JSONDecoder().decode(ServerMessage.self, from: data)
    }

    public static func decode(_ text: String) throws -> ServerMessage {
        try decode(Data(text.utf8))
    }
}
