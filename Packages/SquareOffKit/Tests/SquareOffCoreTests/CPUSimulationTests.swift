import Testing
@testable import SquareOffCore

/// Plays a CPU-vs-CPU game to the end and returns the moves in order.
private func playOut(size: Int, first: CPUStrategy, second: CPUStrategy, seed: UInt64) throws -> [Cell] {
    var rng = SplitMix64(seed: seed)
    var game = Game(boardSize: size, players: [
        PlayerState(id: 1, name: "A", colorHex: "#000", isCPU: true, cpuLevel: first.level),
        PlayerState(id: 2, name: "B", colorHex: "#fff", isCPU: true, cpuLevel: second.level),
    ])
    var moves: [Cell] = []
    while !game.isOver {
        let strategy = game.currentPlayerIndex == 0 ? first : second
        let cell = strategy.chooseMove(in: game, using: &rng)
        #expect(game.board[cell] == nil, "\(strategy) chose an occupied cell")
        try game.place(at: cell)
        moves.append(cell)
    }
    #expect(moves.count == size * size)
    return moves
}

@Suite("CPU simulations")
struct CPUSimulationTests {
    @Test func sameSeedGivesTheSameGame() throws {
        for strategy in CPUStrategy.allCases {
            let a = try playOut(size: 6, first: strategy, second: strategy, seed: 42)
            let b = try playOut(size: 6, first: strategy, second: strategy, seed: 42)
            #expect(a == b, "\(strategy) is not deterministic under a fixed seed")
        }
    }

    @Test(arguments: [6, 8])
    func everyPairingFinishesLegally(size: Int) throws {
        for first in CPUStrategy.allCases {
            for second in CPUStrategy.allCases {
                try playOut(size: size, first: first, second: second, seed: UInt64(size))
            }
        }
    }

    @Test(arguments: [10, 12])
    func largeBoardsFinishLegally(size: Int) throws {
        for strategy in CPUStrategy.allCases {
            try playOut(size: size, first: strategy, second: .maxMinIO, seed: 1)
        }
    }

    @Test func strongerLevelsBeatRandomMostOfTheTime() throws {
        var wins = 0
        let games = 20
        for seed in 0..<games {
            var rng = SplitMix64(seed: UInt64(seed))
            var game = Game(boardSize: 8, players: [
                PlayerState(id: 1, name: "Random", colorHex: "#000", isCPU: true, cpuLevel: .random),
                PlayerState(id: 2, name: "Optimal", colorHex: "#fff", isCPU: true, cpuLevel: .maxMinOptimal),
            ])
            while !game.isOver {
                let strategy: CPUStrategy = game.currentPlayerIndex == 0 ? .random : .maxMinOptimal
                try game.place(at: strategy.chooseMove(in: game, using: &rng))
            }
            if game.standings.first?.id == 2 { wins += 1 }
        }
        #expect(wins >= games * 3 / 4, "Max-Min-Optimal won only \(wins)/\(games) against Random")
    }

    @Test func emptyTwelveByTwelveChoosesQuickly() {
        let game = Game(boardSize: 12, players: [
            PlayerState(id: 1, name: "A", colorHex: "#000"),
            PlayerState(id: 2, name: "B", colorHex: "#fff", isCPU: true, cpuLevel: .maxMinIO),
        ])
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = CPUStrategy.maxMinIO.chooseMove(in: game) }
        #expect(elapsed < .milliseconds(200), "Took \(elapsed)")
    }
}
