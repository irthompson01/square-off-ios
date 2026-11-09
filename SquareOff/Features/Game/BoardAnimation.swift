import SquareOffCore

/// A spin request for one tile (web `triggerRotation`). `id` changes every move so the same tile
/// can spin again; the angle accumulates on the tile and never snaps back.
struct SpinEvent: Equatable {
    let id: Int
    /// Quarter turns: `2 × new shapes in the move`, so 180° per shape formed.
    let turns: Int
    /// Seconds before the spin starts (stagger, plus the flip time for the tapped tile).
    let delay: Double

    init(id: Int, turns: Int, delay: Double = 0) {
        self.id = id
        self.turns = max(turns, 1)
        self.delay = delay
    }

    var degrees: Double { 90 * Double(turns) }
    /// 360 ms per quarter turn, like the web.
    var duration: Double { 0.36 * Double(turns) }
}

/// Builds the per-tile spin schedule for a move (web `triggerShapeFlips`).
enum SpinSchedule {
    static let stagger = 0.045
    static let flipDuration = 0.32

    /// One event per unique corner of the move's new shapes, staggered 45 ms apart in order of
    /// first appearance: square corners TL, TR, BL, BR, then diamond corners top, left, bottom,
    /// right. Local games restart the index for the diamond batch (the web calls the helper
    /// once per kind); online games run one continuous index. The tapped tile waits for its
    /// claim flip first. A plain placement spins nothing: the flip is its animation.
    static func events(for move: MoveResult, sequence: Int, continuousIndex: Bool) -> [Cell: SpinEvent] {
        guard move.newShapeCount > 0 else { return [:] }
        let turns = 2 * move.newShapeCount
        var events: [Cell: SpinEvent] = [:]
        var index = 0
        for batch in [move.newSquares, move.newDiamonds] {
            if !continuousIndex { index = 0 }
            for shape in batch {
                for corner in staggerOrder(shape) where events[corner] == nil {
                    let delay = Double(index) * stagger + (corner == move.cell ? flipDuration : 0)
                    events[corner] = SpinEvent(id: sequence, turns: turns, delay: delay)
                    index += 1
                }
            }
        }
        return events
    }

    /// When the last spin of a move's schedule ends (a plain placement only flips).
    static func completion(of events: [Cell: SpinEvent]) -> Double {
        events.values.map { $0.delay + $0.duration }.max() ?? flipDuration
    }

    /// The pause before the results sheet covers the board: the web's 1.6 s, or a little
    /// longer when the final move's spins would still be running (two shapes take ~2.1 s).
    static func resultsDelay(for events: [Cell: SpinEvent], reduceMotion: Bool = false) -> Double {
        reduceMotion ? 1.6 : max(1.6, completion(of: events) + 0.3)
    }

    /// `BoardShape.corners` is clockwise (TL, TR, BR, BL / top, right, bottom, left); the web
    /// staggers in reading order for squares and top, left, bottom, right for diamonds.
    static func staggerOrder(_ shape: BoardShape) -> [Cell] {
        let c = shape.corners
        return shape.kind == .square ? [c[0], c[1], c[3], c[2]] : [c[0], c[3], c[2], c[1]]
    }
}

/// Age and density fading for the shape overlay (web `getShapeOpacityByOrder` +
/// `getDensitySoftenAmount`): the newest few stay bright, older ones fade back, and a crowded
/// board softens everything a little so tiles stay readable.
enum ShapeAge {
    static func opacity(order: Int, newest: Int, visibleCount: Int) -> Double {
        let soften = min(max(Double(visibleCount - 18) / 24, 0), 1)
        let age = newest - order
        if age <= 5 { return 1 - 0.12 * soften }
        let fadeT = min(1, Double(age - 5) / Double(max(1, newest - 5)))
        let base = 1 - 0.6 * fadeT
        return max(0.25, base * (1 - 0.2 * soften))
    }
}
