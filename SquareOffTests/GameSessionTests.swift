import SquareOffCore
import SquareOffNet
import Testing
@testable import SquareOff

/// Records every call so tests can check the app follows the web's request order.
actor RecordingAPI: SquareOffAPI {
    private let mock = MockSquareOffAPI(latency: .zero)
    private(set) var calls: [String] = []

    func guests() async throws -> GuestsResponse { calls.append("guests"); return try await mock.guests() }
    func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse { calls.append("cpu_player/\(level.cpuType)"); return try await mock.cpuPlayer(level) }
    func login(_ request: LoginRequest) async throws { calls.append("login") }
    func register(_ request: RegisterRequest) async throws { calls.append("register") }
    func logout() async throws { calls.append("logout") }
    func checkAuth() async throws -> Bool { calls.append("check-auth"); return false }
    func startGame(_ request: StartGameRequest) async throws -> StartGameResponse { calls.append("start"); return try await mock.startGame(request) }
    func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse { calls.append("turns"); return try await mock.insertTurn(gameID: gameID, turn) }
    func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse { calls.append("cpu_move"); return try await mock.cpuMove(request) }
}

@MainActor
struct GameSessionTests {
    private func cpuConfig() -> GameConfig {
        GameConfig(mode: .cpu(.maxMin), boardSize: 6, timerSeconds: 0,
                   players: [SetupPlayer(id: 1, name: "Me", colorHex: Theme.playerColors[0])])
    }

    @Test func cpuGameFollowsTheWebRequestOrder() async throws {
        let api = RecordingAPI()
        let session = GameSession(config: cpuConfig(), api: api, account: .guest)
        await session.start()
        #expect(session.serverGameID != nil)
        #expect(session.game.players.allSatisfy { $0.participantID != nil })

        session.tap(Cell(row: 0, col: 0))
        // Wait for the CPU's reply (650ms think time + mock response).
        for _ in 0..<40 where session.game.moves.count < 2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(session.game.moves.count == 2)
        let calls = await api.calls
        #expect(Array(calls.prefix(3)) == ["guests", "cpu_player/max-min", "start"])
        #expect(calls.filter { $0 == "turns" }.count == 2)
        #expect(calls.contains("cpu_move"))
    }

    @Test func tappingIsIgnoredDuringCPUTurn() async throws {
        let session = GameSession(config: cpuConfig(), api: RecordingAPI(), account: .guest)
        await session.start()
        session.tap(Cell(row: 0, col: 0))
        session.tap(Cell(row: 0, col: 1))
        #expect(session.game.moves.count == 1)
    }

    @Test func placementSpinsTheTileOnce() async throws {
        let config = GameConfig(mode: .passAndPlay, boardSize: 6, players: [
            SetupPlayer(id: 1, name: "A", colorHex: Theme.playerColors[0]),
            SetupPlayer(id: 2, name: "B", colorHex: Theme.playerColors[1]),
        ])
        let session = GameSession(config: config, api: RecordingAPI(), account: .guest)
        await session.start()
        session.tap(Cell(row: 2, col: 3))
        #expect(session.spins[Cell(row: 2, col: 3)]?.turns == 1)
        #expect(session.placeCount == 1)
    }
}
