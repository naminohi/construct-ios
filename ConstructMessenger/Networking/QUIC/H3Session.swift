import Foundation
import Network
import os

// MARK: - H3QUICParamsPool

/// Process-wide singleton that manages ONE `NWParameters` + ONE `NWListener` per endpoint.
///
/// **Why this exists**: iOS enforces a hard limit (~4–5) on QUIC connection group listeners
/// per process. Creating a new `NWListener` per `H3Session` burns through this budget on
/// every reconnect, causing POSIX 12 (ENOMEM) when a new listener cannot be allocated.
///
/// The fix: share a single `NWParameters` instance AND a single `NWListener` for all
/// `H3Session` objects that connect to the same host:port. QUIC session coalescing
/// in NWProtocolQUIC guarantees that connections using the **same** `NWParameters`
/// instance share one QUIC session, and server-initiated streams route to the one listener.
final class H3QUICParamsPool: @unchecked Sendable {

    static let shared = H3QUICParamsPool()

    private struct Entry {
        let params: NWParameters
        let listener: NWListener
    }

    private let lock = NSLock()
    private var pool: [String: Entry] = [:]

    private init() {}

    /// Returns (and lazily creates) shared `NWParameters` for `host:port`.
    /// The companion `NWListener` is started when the entry is first created —
    /// before any outgoing connection is made — so the QUIC handshake already
    /// advertises the `initial_max_streams_uni` transport parameter.
    func params(host: String, port: UInt16, tlsVerification: Bool = true) -> NWParameters {
        let key = "\(host):\(port)"
        return lock.withLock {
            if let existing = pool[key] { return existing.params }
            let entry = makeEntry(host: host, port: port, tlsVerification: tlsVerification)
            pool[key] = entry
            return entry.params
        }
    }

    // MARK: - Private

    private func makeEntry(host: String, port: UInt16, tlsVerification: Bool) -> Entry {
        let options = NWProtocolQUIC.Options(alpn: ["h3"])
        options.initialMaxStreamsUnidirectional = 3
        if !tlsVerification {
            sec_protocol_options_set_verify_block(
                options.securityProtocolOptions,
                { _, _, done in done(true) },
                .global(qos: .userInitiated)
            )
        }
        let params = NWParameters(quic: options)
        params.serviceClass = .responsiveData

        guard let listener = try? NWListener(using: params, on: .any) else {
            // Fallback: return params without listener — connection may still work if
            // the server tolerates missing control stream (non-H3-compliant servers).
            return Entry(params: params, listener: NWListener.__placeholder)
        }
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global(qos: .utility))
            H3QUICParamsPool.drainOnce(conn)
        }
        listener.stateUpdateHandler = { _ in }
        listener.start(queue: .global(qos: .utility))
        return Entry(params: params, listener: listener)
    }

    private static func drainOnce(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, isComplete, _ in
            if !isComplete { drainOnce(conn) }
        }
    }
}

// Used as a sentinel when NWListener creation fails — avoids Optional<NWListener>.
private extension NWListener {
    static var __placeholder: NWListener {
        // swiftlint:disable:next force_try
        try! NWListener(using: .tcp)
    }
}

// MARK: - H3Session state

private enum SessionState: Sendable {
    case idle
    case connecting
    case ready
    case failed(Error)
    case closed
}

// MARK: - H3Session

/// Manages a single QUIC session to a remote host, exposing it as a factory of H3 streams.
///
/// **Session setup**:
/// 1. Retrieves shared `NWParameters` from `H3QUICParamsPool` (one per endpoint, process-wide).
///    The pool also owns the `NWListener` that accepts server-initiated H3 control streams,
///    so only ONE listener group is ever created per endpoint regardless of reconnects.
/// 2. Opens a probe NWConnection (bidirectional) using the shared params to trigger the handshake.
/// 3. Sends client H3 SETTINGS on a unidirectional NWConnection (proper H3 control stream).
///
/// **Stream creation** (after ready):
/// `openStream()` returns an `H3Stream` backed by a fresh bidirectional NWConnection
/// using the same shared `NWParameters` — all streams share one QUIC session.
///
/// **Thread safety**: actor-isolated. All public methods are `async`.
actor H3Session: QUICSessionProtocol {

    // MARK: - Configuration

    struct Config: Sendable {
        let host: String
        let port: UInt16
        let tlsVerification: Bool   // false = allow self-signed (debug only)

        static func production(host: String, port: UInt16 = 443) -> Config {
            Config(host: host, port: port, tlsVerification: true)
        }
    }

    // MARK: - State

    private let config: Config
    private var state: SessionState = .idle
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var probeConnection: NWConnection?
    private var controlConnection: NWConnection?

    // MARK: - Init

    init(config: Config) {
        self.config = config
    }

    // MARK: - Connect

    /// Establishes the QUIC session and H3 control stream.
    /// Safe to call multiple times — only the first call does work.
    func connect() async throws {
        switch state {
        case .ready:   return
        case .failed(let e): throw e
        case .closed:  throw H3Error.sessionNotReady
        case .connecting:
            try await withCheckedThrowingContinuation { cont in
                readyContinuations.append(cont)
            }
            return
        case .idle:
            break
        }

        state = .connecting

        do {
            // Shared params from the pool — one NWParameters + NWListener per host:port
            // across the entire process. Reusing the same instance ensures QUIC session
            // coalescing and avoids burning through iOS's QUIC listener group limit.
            let params = H3QUICParamsPool.shared.params(
                host: config.host,
                port: config.port,
                tlsVerification: config.tlsVerification
            )
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(config.host),
                port: NWEndpoint.Port(rawValue: config.port)!
            )

            // Probe connection: triggers the actual QUIC handshake.
            // The pool's NWListener was already started when params were first created,
            // so the QUIC transport parameters already advertise initialMaxStreamsUnidirectional=3.
            let probe = NWConnection(to: endpoint, using: params)
            probeConnection = probe
            try await awaitReady(probe)

            // Client H3 control stream (RFC 9114 §6.2.1).
            // Uses a unidirectional NWConnection so the QUIC stream type is correct.
            try await openControlStream(to: endpoint, using: makeUnidirectionalParams())

            state = .ready
            let continuations = readyContinuations
            readyContinuations = []
            for c in continuations { c.resume() }

        } catch {
            state = .failed(error)
            let continuations = readyContinuations
            readyContinuations = []
            for c in continuations { c.resume(throwing: error) }
            throw error
        }
    }

    // MARK: - Open stream

    /// Opens a new bidirectional QUIC stream (= one gRPC request).
    /// Caller must ensure `connect()` completed successfully first.
    func openStream() async throws -> any QUICStreamProtocol {
        guard case .ready = state else { throw H3Error.sessionNotReady }
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(config.host),
            port: NWEndpoint.Port(rawValue: config.port)!
        )
        // Use pool params → same QUIC session as probe and control.
        let params = H3QUICParamsPool.shared.params(
            host: config.host, port: config.port, tlsVerification: config.tlsVerification)
        return H3Stream(to: endpoint, parameters: params)
    }

    // MARK: - Shutdown

    func close() async {
        state = .closed
        probeConnection?.cancel()
        controlConnection?.cancel()
        probeConnection = nil
        controlConnection = nil
        // NOTE: do NOT cancel H3QUICParamsPool's listener — it is shared across all sessions.
    }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var failureError: Error? {
        if case .failed(let e) = state { return e }
        return nil
    }

    // MARK: - Private: NWParameters (unidirectional only)

    /// Creates fresh `NWParameters` for the client-initiated unidirectional control stream.
    /// This uses a separate params instance (not the pool's) because `direction = .unidirectional`
    /// must not be set on bidirectional request streams.
    private func makeUnidirectionalParams() -> NWParameters {
        let options = NWProtocolQUIC.Options(alpn: ["h3"])
        options.direction = .unidirectional
        applyTLSOptions(to: options)
        let params = NWParameters(quic: options)
        params.serviceClass = .responsiveData
        return params
    }

    private func applyTLSOptions(to options: NWProtocolQUIC.Options) {
        guard !config.tlsVerification else { return }
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, _, sec_complete in sec_complete(true) },
            .global(qos: .userInitiated)
        )
    }

    // MARK: - Private: await connection ready

    private func awaitReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // OSAllocatedUnfairLock guards the once-resume contract.
            // stateUpdateHandler is called from the global concurrent queue, so a plain
            // `var resumed = false` would be a Swift 6 data race (concurrent mutation).
            let once = OSAllocatedUnfairLock<Bool>(initialState: false)
            connection.stateUpdateHandler = { state in
                let should = once.withLockUnchecked { done -> Bool in
                    guard !done else { return false }; done = true; return true
                }
                guard should else { return }
                switch state {
                case .ready:               cont.resume()
                case .failed(let e):       cont.resume(throwing: e)
                case .cancelled:           cont.resume(throwing: CancellationError())
                default:                   break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Private: H3 control stream (client-initiated, unidirectional)

    private func openControlStream(to endpoint: NWEndpoint, using params: NWParameters) async throws {
        let ctrl = NWConnection(to: endpoint, using: params)
        controlConnection = ctrl

        try await awaitReady(ctrl)

        // Stream type byte (0x00) + empty SETTINGS frame — first bytes on the control stream.
        var controlBytes = H3FrameEncoder.controlStreamHeader()
        controlBytes.append(H3FrameEncoder.emptySettings())

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ctrl.send(content: controlBytes, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }
}
