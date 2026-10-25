/// Square grid of player IDs (`nil` = empty). Port of `board-logic.ts`.
public struct Board: Hashable, Sendable {
    public let size: Int
    private var cells: [Int?]

    public init(size: Int) {
        precondition(size >= 2, "Board must be at least 2×2")
        self.size = size
        self.cells = Array(repeating: nil, count: size * size)
    }

    public subscript(row: Int, col: Int) -> Int? {
        get { cells[row * size + col] }
        set { cells[row * size + col] = newValue }
    }

    public subscript(cell: Cell) -> Int? {
        get { self[cell.row, cell.col] }
        set { self[cell.row, cell.col] = newValue }
    }

    public var isFull: Bool { !cells.contains(where: { $0 == nil }) }

    /// Whether `cell` lies on the board (the subscripts trap on an out-of-range index).
    public func contains(_ cell: Cell) -> Bool {
        (0..<size).contains(cell.row) && (0..<size).contains(cell.col)
    }

    public var emptyCells: [Cell] {
        cells.indices.compactMap { i in
            cells[i] == nil ? Cell(row: i / size, col: i % size) : nil
        }
    }

    /// All squares on the board not already in `existing`. Same loop order as `checkForSquares`.
    public func findNewSquares(excluding existing: Set<String>) -> [BoardShape] {
        var result: [BoardShape] = []
        for num in 1..<size {
            for col in 0..<(size - num) {
                for row in 0..<(size - num) {
                    guard let tl = self[row, col],
                          let tr = self[row, col + num],
                          let bl = self[row + num, col],
                          let br = self[row + num, col + num],
                          tl == tr, tr == bl, bl == br else { continue }
                    let shape = BoardShape(kind: .square, row: row, col: col, num: num, ownerID: bl)
                    if !existing.contains(shape.dedupeKey) { result.append(shape) }
                }
            }
        }
        return result
    }

    /// All diamonds on the board not already in `existing`. Same loop order as `checkForDiamonds`.
    public func findNewDiamonds(excluding existing: Set<String>) -> [BoardShape] {
        var result: [BoardShape] = []
        let maxNum = (size + 1) / 2 // Math.ceil(gridSize / 2)
        guard maxNum > 1 else { return result }
        for num in 1..<maxNum {
            guard size - 2 * num > 0 else { continue }
            for row in 0..<(size - 2 * num) {
                for col in 0..<(size - 2 * num) {
                    guard let top = self[row, col + num],
                          let left = self[row + num, col],
                          let bottom = self[row + 2 * num, col + num],
                          let right = self[row + num, col + 2 * num],
                          top == left, left == bottom, bottom == right else { continue }
                    let shape = BoardShape(kind: .diamond, row: row, col: col, num: num, ownerID: bottom)
                    if !existing.contains(shape.dedupeKey) { result.append(shape) }
                }
            }
        }
        return result
    }
}
