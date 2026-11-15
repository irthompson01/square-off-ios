import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// Hosting, joining, quick match and rejoin: everything before (and between) online games.
/// Owns the socket while in the lobby and hands it to an `OnlineGameSession` when play starts.
@Observable
@MainActor
final class RoomCoordinator {
    struct RoomInfo: Equatable {
        var code: Int
        var boardSize: Int
        var timer: Int
        var seats: [PlayerPayload]
        var spectatorCount: Int
        var role: OnlineRole
        var mySeat: Int?
        var listed: Bool
        var gameID: Int?
        var inviteURL: URL
        var awaySeats: Set<Int> = []
        var hostAway = false
    }

    enum OnlineError: Error, Equatable {
        case roomNotFound
        case roomFull
        case hostLeft
        case rejoinFailed(String)
        /// This session already holds a seat in the room (another device, or a stale tab).
        case alreadySeated
        /// The slot was filled by someone else between `PLAYER_SLOT_ASSIGNED` and `JOIN_ROOM`.
        case seatTaken
        case network(String)
        case matchTimeout
        case badRoomState

        var message: String {
            switch self {
            case .roomNotFound: "That room doesn't exist (or was closed)."
            case .roomFull: "That room is full or doesn't exist."
            case .hostLeft: "The host ended the room."
            case .rejoinFailed(let reason):
                switch reason {
                case "not_your_seat": "Couldn't rejoin: that seat belongs to another player."
                case "player_not_found", "slot_in_use": "You were away too long and your seat was released."
                default: "Couldn't rejoin the room."
                }
            case .alreadySeated: "You already have a seat in this room on another device. Leave it there first."
            case .seatTaken: "That seat was just taken. Try joining again."
            case .network(let text): text
            case .matchTimeout: "Quick match failed. Please retry."
            case .badRoomState: "The room sent a state this app can't play."
            }
        }
    }

    enum State: Equatable {
        case idle
        case connecting
        case matching(ticketID: String?, message: String)
        case creating
        case joining(code: Int)
        case waiting(RoomInfo)
        case starting(RoomInfo)
        case playing(OnlineGameSession)
        case failed(OnlineError)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.connecting, .connecting), (.creating, .creating): true
            case let (.matching(a, b), .matching(c, d)): a == c && b == d
            case let (.joining(a), .joining(b)): a == b
            case let (.waiting(a), .waiting(b)): a == b
            case let (.starting(a), .starting(b)): a == b
            case let (.playing(a), .playing(b)): a.id == b.id
            case let (.failed(a), .failed(b)): a == b
            default: false
            }
        }

        var roomInfo: RoomInfo? {
            switch self {
            case .waiting(let info), .starting(let info): info
            default: nil
            }
        }

        var isBusy: Bool {
            switch self {
            case .connecting, .matching, .creating, .joining, .starting: true
            default: false
            }
        }
    }

    private(set) var state: State = .idle
    /// A room this device can still rejoin (same backend, within the grace window).
    private(set) var rejoinable: OnlineSessionRecord?
    /// Set while the lobby socket is being re-established (1, 2, …); nil when connected.
    private(set) var reconnectAttempt: Int?
    /// Quick-match status polling cadence and the longest a ticket waits (tests shorten both).
    var pollInterval: Duration = .seconds(2)
    var matchWindow: Duration = .seconds(180)
    /// How long `startGame` waits for `PUT /update/players` before sending `GAME_START` anyway.
    var startTimeout: Duration = .seconds(5)
    /// The name and colour typed on the Play page; used for the seat instead of the account's defaults.
    var seatPreference: (name: String, colorHex: String)?
    /// The role of the room most recently joined or created, for error headings after `state` fails.
    var lastRole: OnlineRole? { state.roomInfo?.role ?? role }
    var onPlay: (OnlineGameSession) -> Void = { _ in }

    private let makeTransport: @MainActor () -> OnlineTransport
    private let identityProvider: @MainActor () async throws -> Identity
    private var transport: OnlineTransport?
    private var me: Identity?
    private var role: OnlineRole = .guest
    private var mySeat: Int?
    private struct PendingJoin {
        var code: Int
        var record: OnlineSessionRecord?
        /// `seat_taken` is retried once with a fresh slot request.
        var seatRetried = false
    }

    private var pendingHost: (boardSize: Int, timer: Int, listPublic: Bool, gameID: Int?)?
    private var pendingJoin: PendingJoin?
    private var advertiseTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var ticketID: String?
    /// Bumped by `leave()`, `cancelQuickMatch()` and `cancelStart()`: an entry point that
    /// resumes from an `await` after the user backed out must not touch `state` again.
    private var generation = 0

    init(makeTransport: @escaping @MainActor () -> OnlineTransport,
         identityProvider: @escaping @MainActor () async throws -> Identity) {
        self.makeTransport = makeTransport
        self.identityProvider = identityProvider
        refreshRejoinable()
    }

    // MARK: Entry points

    func host(boardSize: Int, timer: Int, listPublic: Bool, preferredCode: Int? = nil) async {
        await leave()
        let gen = generation
        state = .connecting
        do {
            let me = try await resolvedIdentity()
            guard generation == gen else { return }
            self.me = me
            let transport = try await connectedTransport()
            guard generation == gen else { return }
            role = .host
            mySeat = 1
            let seat = StartPlayer(id: 1, name: me.displayName, color: me.colorHex, playerId: me.playerID, isCPU: false, cpuType: nil)
            let start = try? await transport.api.startGame(StartGameRequest(boardSize: boardSize, timer: timer, seats: [seat], type: .online))
            guard generation == gen else { return }
            pendingHost = (boardSize, timer, listPublic, start?.gameId)
            state = .creating
            try await transport.connection.send(.createRoom(
                player: .seat(id: 1, name: me.displayName, colorHex: me.colorHex, playerID: me.playerID),
                boardSize: boardSize, timer: timer, gameID: start?.gameId, roomCode: preferredCode))
        } catch {
            guard generation == gen else { return }
            fail(.network(Self.describe(error)))
        }
    }

    func join(code: Int) async {
        await leave()
        let gen = generation
        state = .connecting
        do {
            let me = try await resolvedIdentity()
            guard generation == gen else { return }
            self.me = me
            let transport = try await connectedTransport()
            guard generation == gen else { return }
            let record = OnlineSessionRecord.load()
            state = .joining(code: code)
            // Seats belong to sessions: a record saved by a different session (the guest was
            // re-minted since) can't be rejoined, so ask for a fresh seat instead.
            if let record, record.roomCode == code, record.backendID == transport.backendID, record.isWithinGrace,
               record.playerID == nil || record.playerID == me.playerID {
                role = record.role
                mySeat = record.seat
                pendingJoin = PendingJoin(code: code, record: record)
                try await transport.connection.send(.rejoinRoom(roomCode: code, playerID: record.seat ?? 0, role: record.role))
            } else {
                role = .guest
                mySeat = nil
                pendingJoin = PendingJoin(code: code)
                try await transport.connection.send(.requestPlayerSlot(roomCode: code))
            }
        } catch {
            guard generation == gen else { return }
            fail(.network(Self.describe(error)))
        }
    }

    func rejoin(_ record: OnlineSessionRecord) async {
        await join(code: record.roomCode)
    }

    func quickMatch(boardSize: Int, timer: Int) async {
        await leave()
        let gen = generation
        state = .matching(ticketID: nil, message: "Finding a match…")
        do {
            let me = try await resolvedIdentity()
            guard generation == gen else { return }
            self.me = me
            let transport = ensureTransport()
            let result = try await transport.matcher.quickMatch(QuickMatchRequest(boardSize: boardSize, timer: timer))
            guard generation == gen else {
                // Cancelled while the request was in flight: don't leave a ticket in the queue.
                if let ticket = result.ticketId { await cancelTicket(ticket, transport) }
                return
            }
            await handleMatch(result, boardSize: boardSize, timer: timer, gen: gen)
        } catch {
            guard generation == gen else { return }
            fail(.network(Self.describe(error)))
        }
    }

    func cancelQuickMatch() async {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        if let ticketID, let transport {
            try? await transport.matcher.cancelQuickMatch(ticketID: ticketID)
        }
        ticketID = nil
        state = .idle
    }

    func setListed(_ listed: Bool) async {
        guard var info = state.roomInfo, info.role == .host else { return }
        info.listed = listed
        state = .waiting(info)
        if listed { startAdvertising(code: info.code) } else { await stopAdvertising(code: info.code) }
    }

    /// Host: `PUT /update/players` with the final seats, then `GAME_START`. The seat update is
    /// bounded by `startTimeout`: the room can start without it.
    func startGame() async {
        guard let info = state.roomInfo, info.role == .host, info.seats.count >= 2, let transport else { return }
        state = .starting(info)
        let gen = generation
        await stopAdvertising(code: info.code)
        guard generation == gen, case .starting = state else { return }
        if let gameID = info.gameID {
            let api = transport.api
            let seats = info.seats
            try? await withTimeout(startTimeout) { try await api.updatePlayers(gameID: gameID, players: seats) }
            guard generation == gen, case .starting = state else { return }
        }
        do {
            try await transport.connection.send(.gameStart)
        } catch {
            guard generation == gen else { return }
            fail(.network(Self.describe(error)))
        }
    }

    /// The start watchdog gives the host the button back when `GAME_START` never echoes.
    func cancelStart() {
        guard case .starting(let info) = state else { return }
        generation += 1
        state = .waiting(info)
    }

    func leave() async {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = nil
        if let info = state.roomInfo, info.role == .host { await stopAdvertising(code: info.code) }
        advertiseTask?.cancel()
        advertiseTask = nil
        if let transport {
            transport.connection.onEvent = nil
            if case .playing = state {} else { await transport.connection.close() }
        }
        if case .playing = state {} else { OnlineSessionRecord.clear() }
        transport = nil
        pendingHost = nil
        pendingJoin = nil
        ticketID = nil
        state = .idle
        refreshRejoinable()
    }

    /// Called when the game screen is dismissed: the socket belongs to the session, which has
    /// closed it; the coordinator just forgets the room.
    func gameEnded() {
        transport = nil
        state = .idle
        refreshRejoinable()
    }

    private func resolvedIdentity() async throws -> Identity {
        let me = try await identityProvider()
        guard let pref = seatPreference else { return me }
        return Identity(playerID: me.playerID, displayName: pref.name, colorHex: pref.colorHex)
    }

    func refreshRejoinable() {
        let record = OnlineSessionRecord.load()
        rejoinable = (record?.isWithinGrace ?? false) ? record : nil
    }

    /// Going to the background in a lobby: keep the rejoin window counting from now.
    func sceneDidEnterBackground() {
        if state.roomInfo != nil { OnlineSessionRecord.touch() }
    }

    func sceneDidBecomeActive() {
        refreshRejoinable()
        guard let transport, state.roomInfo != nil, !transport.connection.isConnected else { return }
        reconnectTask?.cancel()
        reconnectInLobby()
    }

    // MARK: Events

    private func handle(_ event: SocketEvent) {
        switch event {
        case .connected:
            break
        case .disconnected:
            if state.roomInfo != nil { reconnectInLobby() }
        case .message(let message):
            handle(message)
        }
    }

    private func handle(_ message: ServerMessage) {
        switch message {
        case .roomCreated(let created):
            guard let me, let pending = pendingHost, let transport else { return }
            let info = RoomInfo(
                code: created.roomCode, boardSize: created.boardSize, timer: created.timer,
                seats: [.seat(id: 1, name: me.displayName, colorHex: me.colorHex, playerID: me.playerID)],
                spectatorCount: 0, role: .host, mySeat: 1, listed: pending.listPublic,
                gameID: created.gameId ?? pending.gameID, inviteURL: transport.inviteURL(code: created.roomCode))
            state = .waiting(info)
            saveRecord(info)
            if pending.listPublic { startAdvertising(code: created.roomCode) }

        case .playerSlotAssigned(let slot, let color):
            guard let me, let pending = pendingJoin, let transport else { return }
            role = .guest
            mySeat = slot
            // The server picks a colour nobody in the room uses; our own might clash with the host's.
            Task {
                try? await transport.connection.send(.joinRoom(roomCode: pending.code, player: .seat(
                    id: slot, name: me.displayName, colorHex: color ?? me.colorHex, playerID: me.playerID)))
            }

        case .spectatorAssigned:
            guard let pending = pendingJoin, let transport else { return }
            role = .spectator
            mySeat = nil
            Task { try? await transport.connection.send(.joinAsSpectator(roomCode: pending.code)) }

        case .gameState(let snapshot):
            handleGameState(snapshot)

        case .playerJoined(let player):
            guard var info = state.roomInfo, let player else { return }
            if !info.seats.contains(where: { $0.id == player.id }) { info.seats.append(player) }
            state = .waiting(info)

        case .gameStart:
            guard let info = state.roomInfo else { return }
            beginPlay(info: info, snapshot: GameSnapshotPayload(gameState: .empty(boardSize: info.boardSize, players: info.seats),
                                                                timer: info.timer, boardSize: info.boardSize, gameId: info.gameID))

        case .gameReset(let reset):
            guard var info = state.roomInfo else { return }
            info.seats = reset.players
            info.boardSize = reset.boardSize
            info.timer = reset.timer
            info.spectatorCount = reset.spectatorCount ?? 0
            state = .waiting(info)

        case .promotedToPlayer(let seat, _):
            role = .guest
            mySeat = seat
            if var info = state.roomInfo {
                info.role = .guest
                info.mySeat = seat
                state = .waiting(info)
                saveRecord(info)
            }

        case .spectatorCount(let count):
            if var info = state.roomInfo { info.spectatorCount = count; state = .waiting(info) }

        case .guestAway(let seat):
            if var info = state.roomInfo, let seat { info.awaySeats.insert(seat); state = .waiting(info) }

        case .guestDisconnected(let seat):
            if var info = state.roomInfo, let seat {
                info.seats.removeAll { $0.id == seat }
                info.awaySeats.remove(seat)
                state = .waiting(info)
            }

        case .playerRejoined(let seat, _):
            if var info = state.roomInfo {
                if let seat { info.awaySeats.remove(seat) }
                info.hostAway = false
                state = .waiting(info)
            }

        case .hostAway:
            if var info = state.roomInfo { info.hostAway = true; state = .waiting(info) }

        case .hostDisconnected:
            fail(.hostLeft)

        case .joinError(let reason, let message):
            switch reason {
            case "already_seated":
                fail(.alreadySeated)
            case "seat_taken":
                // Somebody filled the slot first: ask once for another one.
                if var pending = pendingJoin, !pending.seatRetried, let transport {
                    pending.seatRetried = true
                    pendingJoin = pending
                    Task { try? await transport.connection.send(.requestPlayerSlot(roomCode: pending.code)) }
                } else {
                    fail(.seatTaken)
                }
            default:
                fail(message.lowercased().contains("full") && !message.lowercased().contains("not found") ? .roomFull : .roomNotFound)
            }

        case .rejoinFailed(let reason):
            OnlineSessionRecord.clear()
            refreshRejoinable()
            if let pending = pendingJoin, pending.record != nil, let transport {
                // Like the web: fall back to asking for a fresh seat (also when the old seat now
                // belongs to another session, `not_your_seat`).
                pendingJoin = PendingJoin(code: pending.code)
                role = .guest
                mySeat = nil
                Task { try? await transport.connection.send(.requestPlayerSlot(roomCode: pending.code)) }
            } else {
                fail(.rejoinFailed(reason))
            }

        case .gameUpdate, .moveRejected, .unknown:
            break
        }
    }

    private func handleGameState(_ snapshot: GameSnapshotPayload) {
        guard let transport else { return }
        if var info = state.roomInfo {
            info.seats = snapshot.seats
            info.spectatorCount = snapshot.spectatorCount ?? info.spectatorCount
            info.gameID = snapshot.gameId ?? info.gameID
            if snapshot.gameState.looksInProgress {
                beginPlay(info: info, snapshot: snapshot)
            } else {
                state = .waiting(info)
            }
            return
        }
        guard let pending = pendingJoin else { return }
        let info = RoomInfo(
            code: pending.code, boardSize: snapshot.boardSize ?? snapshot.gameState.boardSize,
            timer: snapshot.timer ?? pending.record?.timerSeconds ?? 0, seats: snapshot.seats,
            spectatorCount: snapshot.spectatorCount ?? 0, role: role, mySeat: mySeat, listed: false,
            gameID: snapshot.gameId, inviteURL: transport.inviteURL(code: pending.code))
        // SPECTATOR_ASSIGNED means "match in progress" or "four seats taken". With fewer than
        // four seats the game must be running (possibly with an empty board), so watch it now;
        // a full lobby waits for GAME_START / a promotion on reset.
        let inProgress = snapshot.gameState.looksInProgress || (pending.record?.started ?? false)
            || (role == .spectator && snapshot.seats.count < 4)
        if inProgress {
            beginPlay(info: info, snapshot: snapshot)
        } else {
            state = .waiting(info)
            saveRecord(info)
        }
    }

    private func beginPlay(info: RoomInfo, snapshot: GameSnapshotPayload) {
        guard let transport, let me else { return }
        advertiseTask?.cancel()
        advertiseTask = nil
        if info.role == .host {
            let matcher = transport.matcher
            Task { try? await matcher.delist(roomCode: info.code) }
        }
        guard let session = OnlineGameSession(transport: transport, me: me, roomCode: info.code, role: info.role,
                                              seat: info.mySeat, snapshot: snapshot, timerSeconds: info.timer, gameID: info.gameID) else {
            fail(.badRoomState)
            return
        }
        state = .playing(session)
        onPlay(session)
    }

    // MARK: Matching

    private func handleMatch(_ result: QuickMatchResult, boardSize: Int, timer: Int, gen: Int) async {
        switch result.action {
        case .joinRoom:
            ticketID = nil
            guard let code = result.roomCode else { return fail(.network("The matcher returned no room.")) }
            state = .matching(ticketID: nil, message: "Match found — joining…")
            await join(code: code)
        case .createRoom:
            ticketID = nil
            state = .matching(ticketID: nil, message: "Opening your room…")
            await host(boardSize: boardSize, timer: timer, listPublic: true, preferredCode: result.roomCode)
        case .queued, .waitForHost:
            ticketID = result.ticketId ?? ticketID
            state = .matching(ticketID: ticketID, message: result.action == .waitForHost ? "Matched — waiting for the host to open the room…" : "In queue — waiting for a compatible player…")
            guard let ticketID, let transport else { return fail(.network("The matcher returned no ticket.")) }
            pollTask?.cancel()
            let deadline = ContinuousClock.now + matchWindow
            pollTask = Task {
                // A blip (Wi-Fi to cellular) must not end the search: three polls in a row have
                // to fail. Whatever ends it, the ticket is cancelled so nobody gets matched to a
                // player who left.
                var failures = 0
                while !Task.isCancelled, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: pollInterval)
                    guard !Task.isCancelled, generation == gen else { return }
                    do {
                        let status = try await transport.matcher.quickMatchStatus(ticketID: ticketID)
                        guard !Task.isCancelled, generation == gen else {
                            await cancelTicket(ticketID, transport)
                            return
                        }
                        failures = 0
                        if status.status == .matched {
                            await handleMatch(status, boardSize: boardSize, timer: timer, gen: gen)
                            return
                        }
                    } catch {
                        failures += 1
                        guard failures >= 3 else { continue }
                        await cancelTicket(ticketID, transport)
                        guard generation == gen else { return }
                        fail(.network(Self.describe(error)))
                        return
                    }
                }
                guard !Task.isCancelled, generation == gen else { return }
                await cancelTicket(ticketID, transport)
                fail(.matchTimeout)
            }
        }
    }

    private func cancelTicket(_ ticketID: String, _ transport: OnlineTransport) async {
        try? await transport.matcher.cancelQuickMatch(ticketID: ticketID)
    }

    // MARK: Advertising

    private func startAdvertising(code: Int) {
        advertiseTask?.cancel()
        guard let transport, let me else { return }
        advertiseTask = Task {
            while !Task.isCancelled {
                _ = try? await transport.matcher.advertise(AdvertiseRoomRequest(roomCode: code, listed: true, hostLabel: me.displayName))
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func stopAdvertising(code: Int) async {
        advertiseTask?.cancel()
        advertiseTask = nil
        try? await transport?.matcher.delist(roomCode: code)
    }

    // MARK: Plumbing

    private func ensureTransport() -> OnlineTransport {
        if let transport { return transport }
        let transport = makeTransport()
        transport.connection.onEvent = { [weak self] event in self?.handle(event) }
        self.transport = transport
        return transport
    }

    private func connectedTransport() async throws -> OnlineTransport {
        let transport = ensureTransport()
        try await transport.connection.connect()
        return transport
    }

    private func reconnectInLobby() {
        guard let transport, let info = state.roomInfo else { return }
        reconnectTask?.cancel()
        let window: Duration = .seconds(info.role == .host ? 60 : 30)
        let seat = info.mySeat ?? 0
        let role = info.role
        reconnectAttempt = 1
        reconnectTask = Task {
            let ok = await transport.connection.reconnect(until: .now + window, onAttempt: { [weak self] attempt in
                self?.reconnectAttempt = attempt
            }) {
                try await transport.connection.send(.rejoinRoom(roomCode: info.code, playerID: seat, role: role))
            }
            guard !Task.isCancelled else { return }
            reconnectAttempt = nil
            if !ok { fail(.network("Lost the connection to the room.")) }
        }
    }

    private func fail(_ error: OnlineError) {
        advertiseTask?.cancel()
        pollTask?.cancel()
        reconnectAttempt = nil
        state = .failed(error)
    }

    /// The lobby socket (tests simulate drops on it).
    var debugSocket: (any GameSocket)? { transport?.connection.socket }

    private func saveRecord(_ info: RoomInfo) {
        guard let transport else { return }
        OnlineSessionRecord(roomCode: info.code, seat: info.mySeat, role: info.role, gameID: info.gameID, boardSize: info.boardSize,
                            timerSeconds: info.timer, started: false, savedAt: Date(), backendID: transport.backendID,
                            playerID: me?.playerID).save()
        refreshRejoinable()
    }

    /// A sentence for a toast or alert. Known codes get their own copy; a 5xx or a proxy page
    /// never reaches the user as "APIError error 0".
    static func describe(_ error: Error) -> String {
        if let api = error as? APIError {
            if api == .timeout { return "The server didn't answer in time." }
            if let status = api.status, status >= 500 { return "The game server is having trouble. Try again in a moment." }
            if api.status == 429 || api.detail == "rate_limited" { return "Too many attempts. Try again in a minute." }
            switch api.detail {
            case "not_room_host": return "Only the room's host can change its listing."
            case APIError.alreadySignedInCode: return "Your sign-in couldn't be confirmed. Check your connection and try again."
            case "room_not_found": return "That room doesn't exist (or was closed)."
            case "room_full": return "That room is full."
            case "ticket_not_found": return "Your quick-match ticket expired. Try again."
            case APIError.sessionRequiredCode, APIError.accountRequiredCode: return "Couldn't sign in to the game server. Try again."
            default: break
            }
            if let text = api.friendlyDetail { return text }
            if api.status == 404 { return "That room or match couldn't be found." }
            return "Something went wrong talking to the game server. Try again."
        }
        if case let SocketError.handshakeRefused(_, reason) = error {
            return reason == "origin_not_allowed"
                ? "The game server refused this app's connection."
                : "Couldn't sign in to the game server. Try again."
        }
        if error is URLError || error is SocketError {
            #if DEBUG
            return "Can't reach the game server. Check your connection (local docker: is it up and the mkcert CA trusted?)."
            #else
            return "Can't reach the game server. Check your connection."
            #endif
        }
        return error.localizedDescription
    }
}
