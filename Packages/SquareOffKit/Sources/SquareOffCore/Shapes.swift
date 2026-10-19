/// Grid coordinate. `row` 0 is the top row, `col` 0 the left column (same as the web and server).
public struct Cell: Hashable, Sendable, Codable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

public enum ShapeKind: String, Sendable, Codable {
    case square
    case diamond
}

/// A scored square or diamond. Mirrors `Square.ts` / `Diamond.ts`:
/// `num` is the corner distance, `size = num + 1`, squares score `size²`, diamonds `2 × size²`.
public struct BoardShape: Hashable, Sendable, Identifiable {
    public let kind: ShapeKind
    /// Top-left of the bounding box (square) or of the diamond's bounding box.
    public let row: Int
    public let col: Int
    public let num: Int
    public let ownerID: Int

    public var id: String { "\(kind.rawValue)-\(row)-\(col)-\(num)" }
    public var size: Int { num + 1 }

    public var points: Int {
        switch kind {
        case .square: size * size
        case .diamond: 2 * size * size
        }
    }

    /// Corners in drawing order (clockwise from top-left for squares, from top for diamonds).
    public var corners: [Cell] {
        switch kind {
        case .square:
            [
                Cell(row: row, col: col),
                Cell(row: row, col: col + num),
                Cell(row: row + num, col: col + num),
                Cell(row: row + num, col: col),
            ]
        case .diamond:
            [
                Cell(row: row, col: col + num),
                Cell(row: row + num, col: col + 2 * num),
                Cell(row: row + 2 * num, col: col + num),
                Cell(row: row + num, col: col),
            ]
        }
    }

    /// Same key the web uses to de-duplicate shapes (`row`, `col`, `num` per kind).
    var dedupeKey: String { id }

    public init(kind: ShapeKind, row: Int, col: Int, num: Int, ownerID: Int) {
        self.kind = kind
        self.row = row
        self.col = col
        self.num = num
        self.ownerID = ownerID
    }
}
