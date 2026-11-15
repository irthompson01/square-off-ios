import Foundation
import SquareOffCore

/// Everything a client sends over `/ws`. Encodes to exactly the keys the web client sends
/// (hero-client/src/hooks/use-game-socket.ts) so the unchanged server handler accepts them.
public enum ClientMessage: Sendable, Equatable, Encodable {
    case createRoom(player: PlayerPayload, boardSize: Int, timer: Int, gameID: Int?, roomCode: Int?)
    case joinRoom(roomCode: Int, player: PlayerPayload)
    case requestPlayerSlot(roomCode: Int)
    case joinAsSpectator(roomCode: Int)
    case rejoinRoom(roomCode: Int, playerID: Int, role: OnlineRole)
    case gameStart
    case gameUpdate(cell: Cell)
    case turnComplete
    case gameReset(boardSize: Int, timer: Int, gameID: Int?)

    public var typeName: String {
        switch self {
        case .createRoom: "CREATE_ROOM"
        case .joinRoom: "JOIN_ROOM"
        case .requestPlayerSlot: "REQUEST_PLAYER_SLOT"
        case .joinAsSpectator: "JOIN_AS_SPECTATOR"
        case .rejoinRoom: "REJOIN_ROOM"
        case .gameStart: "GAME_START"
        case .gameUpdate: "GAME_UPDATE"
        case .turnComplete: "TURN_COMPLETE"
        case .gameReset: "GAME_RESET"
        }
    }

    struct Keys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static func k(_ s: String) -> Keys { Keys(stringValue: s) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(typeName, forKey: .k("type"))
        switch self {
        case let .createRoom(player, boardSize, timer, gameID, roomCode):
            try c.encode(player, forKey: .k("player"))
            var state = c.nestedContainer(keyedBy: Keys.self, forKey: .k("gameState"))
            try state.encode(boardSize, forKey: .k("boardSize"))
            let empty: [[Int?]] = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
            try state.encode(empty, forKey: .k("boardState"))
            try c.encode(timer, forKey: .k("timer"))
            try c.encodeIfPresent(gameID, forKey: .k("gameId"))
            try c.encodeIfPresent(roomCode, forKey: .k("roomCode"))
        case let .joinRoom(roomCode, player):
            try c.encode(roomCode, forKey: .k("roomCode"))
            try c.encode(player, forKey: .k("player"))
        case let .requestPlayerSlot(roomCode), let .joinAsSpectator(roomCode):
            try c.encode(roomCode, forKey: .k("roomCode"))
        case let .rejoinRoom(roomCode, playerID, role):
            try c.encode(roomCode, forKey: .k("roomCode"))
            try c.encode(playerID, forKey: .k("playerId"))
            try c.encode(role.rawValue, forKey: .k("role"))
        case .gameStart, .turnComplete:
            break
        case let .gameUpdate(cell):
            var state = c.nestedContainer(keyedBy: Keys.self, forKey: .k("gameState"))
            try state.encode(cell.row, forKey: .k("rowIndex"))
            try state.encode(cell.col, forKey: .k("colIndex"))
        case let .gameReset(boardSize, timer, gameID):
            try c.encode(boardSize, forKey: .k("boardSize"))
            try c.encode(timer, forKey: .k("timer"))
            try c.encodeIfPresent(gameID, forKey: .k("gameId"))
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
