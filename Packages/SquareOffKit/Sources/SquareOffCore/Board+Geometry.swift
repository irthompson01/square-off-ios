/// Geometry helpers used by the CPU heuristics. Ports of `Board.get_non_adjacent_moves` and
/// `Board.get_closest_move_to_board_center` in the server's `modules/board.py`.
extension Board {
    /// Candidates that are not orthogonally (up/down/left/right) next to a tile owned by `playerID`.
    /// `playerID == nil` checks against every occupied tile (`all_players=True`). Order is preserved.
    public func nonAdjacentCells(_ candidates: [Cell], toTilesOf playerID: Int?) -> [Cell] {
        candidates.filter { cell in
            !neighbours(of: cell).contains { neighbour in
                guard let owner = self[neighbour] else { return false }
                return playerID == nil || owner == playerID
            }
        }
    }

    /// Every candidate tied for the shortest distance to the board's geometric centre `(N−1)/2`,
    /// in input order. On even boards that is up to four cells. Python's random pick among the ties
    /// is left to the caller.
    public func cellsClosestToCenter(_ candidates: [Cell]) -> [Cell] {
        // Integer form of Python's squared Euclidean distance (×4), so no epsilon is needed.
        let offset = size - 1
        func distance(_ cell: Cell) -> Int {
            let dr = 2 * cell.row - offset
            let dc = 2 * cell.col - offset
            return dr * dr + dc * dc
        }
        var best: [Cell] = []
        var bestDistance = Int.max
        for cell in candidates {
            let d = distance(cell)
            if d < bestDistance {
                bestDistance = d
                best = [cell]
            } else if d == bestDistance {
                best.append(cell)
            }
        }
        return best
    }

    private func neighbours(of cell: Cell) -> [Cell] {
        var result: [Cell] = []
        if cell.row > 0 { result.append(Cell(row: cell.row - 1, col: cell.col)) }
        if cell.row < size - 1 { result.append(Cell(row: cell.row + 1, col: cell.col)) }
        if cell.col > 0 { result.append(Cell(row: cell.row, col: cell.col - 1)) }
        if cell.col < size - 1 { result.append(Cell(row: cell.row, col: cell.col + 1)) }
        return result
    }
}
