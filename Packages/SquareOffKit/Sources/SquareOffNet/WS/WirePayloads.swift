import Foundation
import SquareOffCore

// Loosely typed JSON the server's `/ws` route exchanges (server/src/routes/websocket.py,
// hero-client/src/hooks/use-game-socket.ts). Every field the server might omit is optional
// and numeric ids tolerate strings/doubles, because the server echoes whatever dicts clients sent.

public enum OnlineRole: String, Codable, Sendable {
    case host, guest, spectator
}

/// Decodes an Int that the server may have serialised as Int, Double or numeric String.
enum LenientInt {
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Int? {
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? c.decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }
}

/// The web's `WsPlayerPayload` / serialised `Player`. `id` is the board slot (1…4).
public struct PlayerPayload: Codable, Sendable, Equatable, Identifiable {
    public static let defaultColors = ["#0583D2", "#FF3131", "#50C878", "#EE8329"]

    public var id: Int
    public var name: String?
    public var fillStyle: String?
    public var playerId: String?
    public var participantId: Int?
    public var isCPU: Bool?
    public var cpuType: String?
    public var currentScore: Int?
    public var currentMultiplier: Int?
    public var multiplierIncrease: Int?
    public var scoreIncrease: Int?
    public var newSquareCount: Int?
    public var newDiamondCount: Int?
    public var scoreHistory: [Int]?

    public init(id: Int, name: String? = nil, fillStyle: String? = nil, playerId: String? = nil,
                participantId: Int? = nil, isCPU: Bool? = nil, cpuType: String? = nil,
                currentScore: Int? = nil, currentMultiplier: Int? = nil, multiplierIncrease: Int? = nil,
                scoreIncrease: Int? = nil, newSquareCount: Int? = nil, newDiamondCount: Int? = nil,
                scoreHistory: [Int]? = nil) {
        self.id = id
        self.name = name
        self.fillStyle = fillStyle
        self.playerId = playerId
        self.participantId = participantId
        self.isCPU = isCPU
        self.cpuType = cpuType
        self.currentScore = currentScore
        self.currentMultiplier = currentMultiplier
        self.multiplierIncrease = multiplierIncrease
        self.scoreIncrease = scoreIncrease
        self.newSquareCount = newSquareCount
        self.newDiamondCount = newDiamondCount
        self.scoreHistory = scoreHistory
    }

    /// What `CREATE_ROOM` / `JOIN_ROOM` / `PUT /update/players` send for a seat. `isCPU` is always
    /// explicit because the server's `Player` defaults it to **true** when the key is missing.
    public static func seat(id: Int, name: String, colorHex: String, playerID: String?,
                            isCPU: Bool = false, cpuType: String? = nil) -> PlayerPayload {
        PlayerPayload(id: id, name: name, fillStyle: colorHex, playerId: playerID, isCPU: isCPU,
                      cpuType: cpuType, currentScore: 0, currentMultiplier: 1)
    }

    public var colorHex: String { fillStyle ?? Self.defaultColors[(max(id, 1) - 1) % Self.defaultColors.count] }
    public var displayName: String { name ?? "Player \(id)" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try LenientInt.decode(c, .id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "player id"))
        }
        self.id = id
        name = try c.decodeIfPresent(String.self, forKey: .name)
        fillStyle = try c.decodeIfPresent(String.self, forKey: .fillStyle)
        playerId = try? c.decodeIfPresent(String.self, forKey: .playerId)
        participantId = try LenientInt.decode(c, .participantId)
        isCPU = try? c.decodeIfPresent(Bool.self, forKey: .isCPU)
        cpuType = try? c.decodeIfPresent(String.self, forKey: .cpuType)
        currentScore = try LenientInt.decode(c, .currentScore)
        currentMultiplier = try LenientInt.decode(c, .currentMultiplier)
        multiplierIncrease = try LenientInt.decode(c, .multiplierIncrease)
        scoreIncrease = try LenientInt.decode(c, .scoreIncrease)
        newSquareCount = try LenientInt.decode(c, .newSquareCount)
        newDiamondCount = try LenientInt.decode(c, .newDiamondCount)
        scoreHistory = try? c.decodeIfPresent([Int].self, forKey: .scoreHistory)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(fillStyle, forKey: .fillStyle)
        try c.encodeIfPresent(playerId, forKey: .playerId)
        try c.encodeIfPresent(participantId, forKey: .participantId)
        try c.encode(isCPU ?? false, forKey: .isCPU)
        try c.encodeIfPresent(cpuType, forKey: .cpuType)
        try c.encodeIfPresent(currentScore, forKey: .currentScore)
        try c.encodeIfPresent(currentMultiplier, forKey: .currentMultiplier)
        try c.encodeIfPresent(multiplierIncrease, forKey: .multiplierIncrease)
        try c.encodeIfPresent(scoreIncrease, forKey: .scoreIncrease)
        try c.encodeIfPresent(newSquareCount, forKey: .newSquareCount)
        try c.encodeIfPresent(newDiamondCount, forKey: .newDiamondCount)
        try c.encodeIfPresent(scoreHistory, forKey: .scoreHistory)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, fillStyle, playerId, participantId, isCPU, cpuType, currentScore, currentMultiplier
        case multiplierIncrease, scoreIncrease, newSquareCount, newDiamondCount, scoreHistory
    }
}

/// An occupied board cell. The server writes the whole player dict; only the slot id matters.
public struct BoardCellPayload: Codable, Sendable, Equatable {
    public let id: Int

    public init(id: Int) { self.id = id }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try LenientInt.decode(c, .id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "cell id"))
        }
        self.id = id
    }

    enum CodingKeys: String, CodingKey { case id }
}

/// `squares[]` / `diamonds[]` / `newShapes.*[]` entries (`Game._serialise_shapes`).
public struct ShapePayload: Codable, Sendable, Equatable {
    public let occupantId: Int
    public let row: Int
    public let col: Int
    public let num: Int
    public let size: Int?
    public let points: Int?
    public let type: String?

    public init(occupantId: Int, row: Int, col: Int, num: Int, size: Int? = nil, points: Int? = nil, type: String? = nil) {
        self.occupantId = occupantId
        self.row = row
        self.col = col
        self.num = num
        self.size = size
        self.points = points
        self.type = type
    }

    public init(_ shape: BoardShape) {
        self.init(occupantId: shape.ownerID, row: shape.row, col: shape.col, num: shape.num,
                  size: shape.size, points: shape.points, type: shape.kind.rawValue)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        occupantId = try LenientInt.decode(c, .occupantId) ?? 0
        row = try LenientInt.decode(c, .row) ?? 0
        col = try LenientInt.decode(c, .col) ?? 0
        num = try LenientInt.decode(c, .num) ?? 1
        size = try LenientInt.decode(c, .size)
        points = try LenientInt.decode(c, .points)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
    }

    public func boardShape(_ kind: ShapeKind) -> BoardShape {
        BoardShape(kind: kind, row: row, col: col, num: num, ownerID: occupantId)
    }

    enum CodingKeys: String, CodingKey { case occupantId, row, col, num, size, points, type }
}

public struct NewShapesPayload: Codable, Sendable, Equatable {
    public let squares: [ShapePayload]?
    public let diamonds: [ShapePayload]?
    public let count: Int?

    public init(squares: [ShapePayload]?, diamonds: [ShapePayload]?, count: Int?) {
        self.squares = squares
        self.diamonds = diamonds
        self.count = count
    }

    public var all: [BoardShape] {
        (squares ?? []).map { $0.boardShape(.square) } + (diamonds ?? []).map { $0.boardShape(.diamond) }
    }
}

/// `Game.to_state()` plus the extras `make_move` adds after a move.
public struct GameStatePayload: Codable, Sendable, Equatable {
    public var boardState: [[BoardCellPayload?]]
    public var players: [PlayerPayload]?
    public var currentPlayerIndex: Int?
    public var gameOver: Bool?
    public var squares: [ShapePayload]?
    public var diamonds: [ShapePayload]?
    // GAME_UPDATE only
    public var rowIndex: Int?
    public var colIndex: Int?
    public var scoreIncrease: Int?
    public var multiplierIncrease: Int?
    public var newShapes: NewShapesPayload?

    public init(boardState: [[BoardCellPayload?]], players: [PlayerPayload]? = nil, currentPlayerIndex: Int? = nil,
                gameOver: Bool? = nil, squares: [ShapePayload]? = nil, diamonds: [ShapePayload]? = nil,
                rowIndex: Int? = nil, colIndex: Int? = nil, scoreIncrease: Int? = nil,
                multiplierIncrease: Int? = nil, newShapes: NewShapesPayload? = nil) {
        self.boardState = boardState
        self.players = players
        self.currentPlayerIndex = currentPlayerIndex
        self.gameOver = gameOver
        self.squares = squares
        self.diamonds = diamonds
        self.rowIndex = rowIndex
        self.colIndex = colIndex
        self.scoreIncrease = scoreIncrease
        self.multiplierIncrease = multiplierIncrease
        self.newShapes = newShapes
    }

    /// An empty N×N board.
    public static func empty(boardSize: Int, players: [PlayerPayload]? = nil) -> GameStatePayload {
        GameStatePayload(boardState: Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize),
                         players: players, currentPlayerIndex: 0, gameOver: false, squares: [], diamonds: [])
    }

    public var boardSize: Int { boardState.count }

    public var moveCell: Cell? {
        guard let rowIndex, let colIndex else { return nil }
        return Cell(row: rowIndex, col: colIndex)
    }

    /// Mirrors the web's `snapshotLooksLikeMatchInProgress`: tiles on the board or a finished game.
    public var looksInProgress: Bool {
        gameOver == true || boardState.contains { $0.contains { $0 != nil } }
    }

    /// Every existing shape as the rules engine sees it (per seat, formation order within a seat).
    public var allShapes: [BoardShape] {
        (squares ?? []).map { $0.boardShape(.square) } + (diamonds ?? []).map { $0.boardShape(.diamond) }
    }
}

/// The envelope shared by `GAME_STATE` and `GAME_UPDATE`.
public struct GameSnapshotPayload: Codable, Sendable, Equatable {
    public var gameState: GameStatePayload
    public var players: [PlayerPayload]?
    public var timer: Int?
    public var boardSize: Int?
    public var currentPlayerIndex: Int?
    public var gameId: Int?
    public var spectatorCount: Int?

    public init(gameState: GameStatePayload, players: [PlayerPayload]? = nil, timer: Int? = nil,
                boardSize: Int? = nil, currentPlayerIndex: Int? = nil, gameId: Int? = nil, spectatorCount: Int? = nil) {
        self.gameState = gameState
        self.players = players
        self.timer = timer
        self.boardSize = boardSize
        self.currentPlayerIndex = currentPlayerIndex
        self.gameId = gameId
        self.spectatorCount = spectatorCount
    }

    /// Seats in turn order: the state's players (authoritative, with live scores) else the envelope's.
    public var seats: [PlayerPayload] { gameState.players ?? players ?? [] }
}

public struct RoomCreatedPayload: Codable, Sendable, Equatable {
    public let roomCode: Int
    public let timer: Int
    public let boardSize: Int
    public let currentPlayerIndex: Int?
    public let gameId: Int?

    public init(roomCode: Int, timer: Int, boardSize: Int, currentPlayerIndex: Int? = 0, gameId: Int?) {
        self.roomCode = roomCode
        self.timer = timer
        self.boardSize = boardSize
        self.currentPlayerIndex = currentPlayerIndex
        self.gameId = gameId
    }
}

public struct GameResetPayload: Codable, Sendable, Equatable {
    public let boardSize: Int
    public let timer: Int
    public let players: [PlayerPayload]
    public let spectatorCount: Int?

    public init(boardSize: Int, timer: Int, players: [PlayerPayload], spectatorCount: Int?) {
        self.boardSize = boardSize
        self.timer = timer
        self.players = players
        self.spectatorCount = spectatorCount
    }
}
