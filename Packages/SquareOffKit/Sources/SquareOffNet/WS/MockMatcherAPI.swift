import Foundation
import SquareOffCore

/// Simulates `/api/matcher/*` on top of `MockRoomServer`: a lobby of bot-hosted rooms and
/// quick-match tickets that resolve to one of them after a short wait (so the polling path runs).
public actor MockMatcherAPI: MatcherAPI {
    private let server: MockRoomServer
    private let ticketDelay: Duration
    private var tickets: [String: (boardSize: Int, timer: Int, requester: String, created: ContinuousClock.Instant)] = [:]
    private var seeded = false

    public init(server: MockRoomServer, ticketDelay: Duration = .seconds(1.5)) {
        self.server = server
        self.ticketDelay = ticketDelay
    }

    public func openRooms(boardSize: Int?, timer: Int?, limit: Int, offset: Int) async throws -> [OpenRoomDTO] {
        await ensureSeeded()
        let rooms = await server.listedRooms(boardSize: boardSize, timer: timer)
        return Array(rooms.dropFirst(max(offset, 0)).prefix(max(limit, 1)))
    }

    public func advertise(_ request: AdvertiseRoomRequest) async throws -> AdvertiseRoomResponse {
        guard let response = await server.upsertListing(code: request.roomCode, listed: request.listed,
                                                        hostLabel: request.hostLabel, hostKey: request.hostKey) else {
            throw APIError.http(status: 404, body: #"{"detail":"Room not found"}"#)
        }
        return response
    }

    public func delist(roomCode: Int) async throws {
        await server.delist(code: roomCode)
    }

    public func quickMatch(_ request: QuickMatchRequest) async throws -> QuickMatchResult {
        await ensureSeeded()
        let ticket = UUID().uuidString.lowercased()
        tickets[ticket] = (request.boardSize, request.timer, request.requesterId, .now)
        return QuickMatchResult(status: .pending, action: .queued, ticketId: ticket)
    }

    public func quickMatchStatus(ticketID: String, requesterID: String) async throws -> QuickMatchResult {
        guard let ticket = tickets[ticketID], ticket.requester == requesterID else {
            throw APIError.http(status: 404, body: #"{"detail":"Ticket not found"}"#)
        }
        guard ContinuousClock.now - ticket.created >= ticketDelay else {
            return QuickMatchResult(status: .pending, action: .queued, ticketId: ticketID)
        }
        tickets[ticketID] = nil
        let code = await server.botRoom(boardSize: ticket.boardSize, timer: ticket.timer)
        return QuickMatchResult(status: .matched, action: .joinRoom, ticketId: ticketID, roomCode: code)
    }

    public func cancelQuickMatch(ticketID: String, requesterID: String) async throws {
        tickets[ticketID] = nil
    }

    private func ensureSeeded() async {
        guard !seeded else { return }
        seeded = true
        await server.seedBotRoom(code: 48213, boardSize: 6, timer: 0, hostLevel: .maxRandom)
        await server.seedBotRoom(code: 73055, boardSize: 8, timer: 20, hostLevel: .maxMin)
        await server.seedBotRoom(code: 19740, boardSize: 10, timer: 30, hostLevel: .maxMinOptimal)
    }
}
