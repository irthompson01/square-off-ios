import SquareOffCore

// Wire types for the FastAPI server. Field names match exactly what the web client sends
// (hero-client/src/services/*.ts) — snake_case at the top level, camelCase inside `players`
// because the web serialises its `Player` objects as-is and the server maps both spellings.

// MARK: Auth

public struct GuestsResponse: Codable, Sendable, Equatable {
    public let guests: [String]
}

public struct CPUPlayerResponse: Codable, Sendable, Equatable {
    public let id: Int
    public let cpuType: String
    public let displayName: String
    public let color: String?

    enum CodingKeys: String, CodingKey {
        case id, color
        case cpuType = "cpu_type"
        case displayName = "display_name"
    }
}

public struct LoginRequest: Codable, Sendable, Equatable {
    public let emailOrUsername: String
    public let password: String

    public init(emailOrUsername: String, password: String) {
        self.emailOrUsername = emailOrUsername
        self.password = password
    }

    enum CodingKeys: String, CodingKey {
        case emailOrUsername = "email_or_username"
        case password
    }
}

public struct RegisterRequest: Codable, Sendable, Equatable {
    public let username: String
    public let email: String
    public let password: String
    public let registered: Bool

    public init(username: String, email: String, password: String) {
        self.username = username
        self.email = email
        self.password = password
        self.registered = true
    }
}

// MARK: Games

/// One seat in `POST /start` (`players[]`), same keys as the web's setup page builds.
public struct StartPlayer: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let color: String
    public let playerId: String?
    public let isCPU: Bool
    public let cpuType: String?

    public init(_ player: PlayerState) {
        id = player.id
        name = player.name
        color = player.colorHex
        playerId = player.serverPlayerID
        isCPU = player.isCPU
        cpuType = player.cpuLevel?.cpuType
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, playerId, isCPU, cpuType
    }
}

public struct StartGameRequest: Codable, Sendable, Equatable {
    public let boardSize: Int
    public let timer: Int
    public let players: [StartPlayer]
    public let type: String
    public let isCPU: Bool
    public let cpuType: String?

    /// Mirrors `gameAPI.startGame`: `is_cpu`/`cpu_type` come from the (last) CPU seat.
    public init(boardSize: Int, timer: Int, players: [PlayerState], type: GameType) {
        self.boardSize = boardSize
        self.timer = timer
        self.players = players.map(StartPlayer.init)
        self.type = type.rawValue
        let cpu = players.last(where: \.isCPU)
        self.isCPU = cpu != nil
        self.cpuType = cpu?.cpuLevel?.cpuType
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(boardSize, forKey: .boardSize)
        try c.encode(timer, forKey: .timer)
        try c.encode(players, forKey: .players)
        try c.encode(type, forKey: .type)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
    }

    enum CodingKeys: String, CodingKey {
        case timer, players, type
        case boardSize = "board_size"
        case isCPU = "is_cpu"
        case cpuType = "cpu_type"
    }
}

public enum GameType: String, Codable, Sendable {
    case local
    case online
}

public struct StartGameResponse: Codable, Sendable, Equatable {
    public struct Participant: Codable, Sendable, Equatable {
        public let playerId: String
        public let participantId: Int

        enum CodingKeys: String, CodingKey {
            case playerId = "player_id"
            case participantId = "participant_id"
        }
    }

    public let gameId: Int
    public let participants: [Participant]

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case participants
    }
}

/// `POST /{gameId}/turns` body, as built in `game-board.tsx`.
public struct GameTurnRequest: Codable, Sendable, Equatable {
    public let rowIndex: Int
    public let colIndex: Int
    public let playerId: String
    public let currentScore: Int
    public let currentMultiplier: Int
    public let multiplierIncrease: Int
    public let scoreIncrease: Int
    public let newDiamondCount: Int
    public let newSquareCount: Int
    public let isCPU: Bool
    public let cpuType: String?
    public let participantId: Int?

    public init(move: MoveResult, player: PlayerState) {
        rowIndex = move.cell.row
        colIndex = move.cell.col
        playerId = player.serverPlayerID ?? ""
        currentScore = move.scoreAfter
        currentMultiplier = move.multiplierAfter
        multiplierIncrease = move.multiplierIncrease
        scoreIncrease = move.scoreIncrease
        newDiamondCount = move.newDiamonds.count
        newSquareCount = move.newSquares.count
        isCPU = player.isCPU
        cpuType = player.cpuLevel?.cpuType
        participantId = player.participantID
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rowIndex, forKey: .rowIndex)
        try c.encode(colIndex, forKey: .colIndex)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(currentScore, forKey: .currentScore)
        try c.encode(currentMultiplier, forKey: .currentMultiplier)
        try c.encode(multiplierIncrease, forKey: .multiplierIncrease)
        try c.encode(scoreIncrease, forKey: .scoreIncrease)
        try c.encode(newDiamondCount, forKey: .newDiamondCount)
        try c.encode(newSquareCount, forKey: .newSquareCount)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
        try c.encode(participantId, forKey: .participantId)
    }

    enum CodingKeys: String, CodingKey {
        case rowIndex = "row_index"
        case colIndex = "col_index"
        case playerId = "player_id"
        case currentScore = "current_score"
        case currentMultiplier = "current_multiplier"
        case multiplierIncrease = "multiplier_increase"
        case scoreIncrease = "score_increase"
        case newDiamondCount = "new_diamond_count"
        case newSquareCount = "new_square_count"
        case isCPU = "is_cpu"
        case cpuType = "cpu_type"
        case participantId = "participant_id"
    }
}

public struct GameTurnResponse: Codable, Sendable, Equatable {
    public let turnId: Int

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
    }
}

// MARK: CPU

/// A board cell as the server reads it: only `id` (the seat number) matters.
public struct BoardCellDTO: Codable, Sendable, Equatable {
    public let id: Int
}

/// Existing shapes must be sent, or the server re-counts them as new when it evaluates moves.
public struct ShapeDTO: Codable, Sendable, Equatable {
    public let row: Int
    public let col: Int
    public let num: Int
    public let size: Int

    public init(_ shape: BoardShape) {
        row = shape.row
        col = shape.col
        num = shape.num
        size = shape.size
    }
}

public struct CPUMovePlayer: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let fillStyle: String
    public let playerId: String?
    public let participantId: Int?
    public let isCPU: Bool
    public let cpuType: String?
    public let currentScore: Int
    public let currentMultiplier: Int
    public let squares: [ShapeDTO]
    public let diamonds: [ShapeDTO]

    public init(_ player: PlayerState) {
        id = player.id
        name = player.name
        fillStyle = player.colorHex
        playerId = player.serverPlayerID
        participantId = player.participantID
        isCPU = player.isCPU
        cpuType = player.cpuLevel?.cpuType
        currentScore = player.score
        currentMultiplier = player.multiplier
        squares = player.squares.map(ShapeDTO.init)
        diamonds = player.diamonds.map(ShapeDTO.init)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(fillStyle, forKey: .fillStyle)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(participantId, forKey: .participantId)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
        try c.encode(currentScore, forKey: .currentScore)
        try c.encode(currentMultiplier, forKey: .currentMultiplier)
        try c.encode(squares, forKey: .squares)
        try c.encode(diamonds, forKey: .diamonds)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, fillStyle, playerId, participantId, isCPU, cpuType
        case currentScore, currentMultiplier, squares, diamonds
    }
}

public struct CPUMoveRequest: Codable, Sendable, Equatable {
    public let gameId: Int
    public let boardState: [[BoardCellDTO?]]
    public let currentPlayer: CPUMovePlayer
    public let gamePlayers: [CPUMovePlayer]
    public let cpuType: String

    public init(gameID: Int, game: Game) {
        gameId = gameID
        let board = game.board
        boardState = (0..<board.size).map { row in
            (0..<board.size).map { col in board[row, col].map(BoardCellDTO.init(id:)) }
        }
        currentPlayer = CPUMovePlayer(game.currentPlayer)
        gamePlayers = game.players.map(CPUMovePlayer.init)
        cpuType = game.currentPlayer.cpuLevel?.cpuType ?? CPULevel.random.cpuType
    }

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case boardState = "board_state"
        case currentPlayer = "current_player"
        case gamePlayers = "game_players"
        case cpuType = "cpu_type"
    }
}

public struct CPUMoveResponse: Codable, Sendable, Equatable {
    public let row: Int
    public let col: Int

    public var cell: Cell { Cell(row: row, col: col) }
}
