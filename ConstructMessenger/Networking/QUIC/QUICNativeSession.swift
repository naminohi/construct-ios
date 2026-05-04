import Foundation
import Network

// MARK: - QUICNativeSessionPool (iOS 26+)

/// Process-wide singleton that vends exactly one `QUICNativeSession` per host:port.
///
/// Sharing a single `NetworkConnection<QUIC>` per endpoint across all reconnects prevents
/// the per-process QUIC connection-group listener limit (POSIX 12 / ENOMEM) that fires
/// when each `GRPCChannelManager` reconnect creates a fresh `NetworkConnection`.
///
/// Each `NWQUICGRPCTransport` calls `QUICNativeSessionPool.shared.session(for:port:)` in
/// `makeSession()`. The returned session is never closed by individual transports —
/// the pool owns its lifetime for the duration of the process.
@available(iOS 26, macOS 26, *)
final class QUICNativeSessionPool: @unchecked Sendable {
    static let shared = QUICNativeSessionPool()
    private let lock = NSLock()
    private var sessions: [String: QUICNativeSession] = [:]

    private init() {}

    func session(for host: String, port: UInt16) -> QUICNativeSession {
        let key = "\(host):\(port)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = sessions[key] { return existing }
        let s = QUICNativeSession(host: host, port: port)
        sessions[key] = s
        return s
    }
}

// MARK: - QUICNativeSession (iOS 26+)

/// A QUIC session backed by the iOS 26+ `NetworkConnection<QUIC>` API.
///
/// Apple's `NetworkConnection<QUIC>` exposes a proper multiplexed-stream model
/// (`openStream()`, `inboundStreams`) — no NWConnection tricks needed.
/// Each call to `openStream()` yields a real QUIC bidirectional stream.
///
/// Instances are owned by `QUICNativeSessionPool` and shared across `NWQUICGRPCTransport`
/// reconnects. The actor state machine handles concurrent `connect()` calls and
/// recovers from failures by resetting to `.idle` on the next `connect()` call.
@available(iOS 26, macOS 26, *)
actor QUICNativeSession: QUICSessionProtocol {

    // MARK: - State

    private enum SessionState {
        case idle
        case connecting
        case ready
        case failed(Error)
        case closed
    }

    private let host: String
    private let port: UInt16
    private var state: SessionState = .idle
    private var connection: NetworkConnection<QUIC>?
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var inboundTask: Task<Void, Never>?

    // MARK: - Init

    init(host: String, port: UInt16 = 443) {
        self.host = host
        self.port = port
    }

    // MARK: - QUICSessionProtocol

    func connect() async throws {
        switch state {
        case .ready:        return
        case .connecting:
            try await withCheckedThrowingContinuation { cont in
                waiters.append(cont)
            }
            return
        case .failed, .closed:
            state = .idle
            connection = nil
        case .idle:
            break
        }

        state = .connecting

        do {
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!
            )
            // Advertise initial_max_streams_uni = 3 in QUIC transport parameters so the server
            // can open its H3 control stream (stream ID 3, RFC 9114 §6.2.1) immediately after
            // the handshake. Without this, the client implicitly advertises 0, which means the
            // server isn't supposed to open any unidirectional streams — yet H3 requires it to.
            // iOS's QUIC stack still receives stream ID 3 in that case, but logs
            // "No listener registered" because it has nowhere to dispatch the stream. The connection
            // group then fails with H3_CLOSED_CRITICAL_STREAM, causing all RPCs to time out.
            let conn = NetworkConnection(to: endpoint) {
                QUIC(alpn: ["h3"]).initialMaxUnidirectionalStreams(3)
            }

            // Register the inbound-stream handler BEFORE calling conn.start().
            // We store the Task so it can be cancelled when the session closes.
            inboundTask = Task { [weak self] in
                guard let self else { return }
                try? await conn.inboundStreams { [weak self] stream in
                    await self?.drainStream(stream)
                }
            }

            // 10 ms pause: gives Network.framework's internal dispatch queue a chance to
            // install the OS-level accept handler before the QUIC handshake begins.
            // Task.yield() is insufficient — it only cooperatively yields within Swift's
            // concurrency scheduler and doesn't guarantee NW's C-level queue has run.
            try await Task.sleep(nanoseconds: 10_000_000)

            // Start the QUIC handshake NOW — accept handler is already registered.
            // start() returns Self; we store it to match the type expected by openStream().
            connection = conn.start()
            state = .ready
            let pending = waiters; waiters = []
            for c in pending { c.resume() }

        } catch {
            state = .failed(error)
            let pending = waiters; waiters = []
            for c in pending { c.resume(throwing: error) }
            throw error
        }
    }

    func openStream() async throws -> any QUICStreamProtocol {
        guard case .ready = state, let conn = connection else {
            throw H3Error.sessionNotReady
        }
        let stream = try await conn.openStream(directionality: .bidirectional)
        return QUICNativeStream(stream: stream)
    }

    func close() async {
        inboundTask?.cancel()
        inboundTask = nil
        state = .closed
        connection = nil    // ARC releases the NetworkConnection
    }

    // MARK: - Private

    private func drainStream(_ stream: QUIC.Stream<QUICStream>) async {
        while true {
            guard let msg = try? await stream.receive(atLeast: 1, atMost: 4096) else { return }
            if msg.metadata.endOfStream { return }
        }
    }
}

// MARK: - QUICNativeStream (iOS 26+)

/// A single gRPC call stream backed by `QUIC.Stream<QUICStream>`.
@available(iOS 26, macOS 26, *)
final class QUICNativeStream: QUICStreamProtocol, @unchecked Sendable {

    private let stream: QUIC.Stream<QUICStream>

    init(stream: QUIC.Stream<QUICStream>) {
        self.stream = stream
    }

    // MARK: - QUICStreamProtocol

    /// No-op: `NetworkConnection.openStream()` only resolves after the connection is ready,
    /// so the stream is already usable on return from `QUICNativeSession.openStream()`.
    func connect() async throws {}

    func sendRequest(headers: [(name: String, value: String)], grpcBody: Data) async throws {
        let encodedHeaders = QPACKLite.encodeHeaders(headers)
        let headersFrame = H3FrameEncoder.headers(encodedHeaders)
        let grpcFramed = GRPCFraming.encode(grpcBody)
        let dataFrame = H3FrameEncoder.data(grpcFramed)

        var requestBytes = headersFrame
        requestBytes.append(dataFrame)

        try await stream.send(requestBytes, endOfStream: true)
    }

    func receiveResponse() async throws -> H3Response {
        var reader = H3FrameReader()
        var responseHeaders: [QPACKLite.HeaderField] = []
        var grpcBodyAccumulator = Data()

        while true {
            let msg: QUICStream.Message<Foundation.Data>
            do {
                msg = try await stream.receive(atLeast: 1, atMost: 65536)
            } catch {
                // Stream reset or error — if we already have some data, build the response.
                if !grpcBodyAccumulator.isEmpty || !responseHeaders.isEmpty { break }
                throw error
            }

            if !msg.content.isEmpty {
                reader.append(msg.content)
            }

            while let frame = reader.next() {
                switch frame.type {
                case H3FrameType.headers.rawValue:
                    guard let fields = QPACKLite.decodeHeaders(frame.payload) else {
                        throw H3Error.malformedHeaders
                    }
                    responseHeaders.append(contentsOf: fields)  // append — trailers arrive as a second HEADERS frame
                case H3FrameType.data.rawValue:
                    var remaining = frame.payload
                    while let (body, consumed) = GRPCFraming.decode(remaining) {
                        grpcBodyAccumulator.append(body)
                        remaining = remaining.dropFirst(consumed)
                    }
                default:
                    break   // ignore unknown frame types (RFC 9114 §9)
                }
            }

            if msg.metadata.endOfStream { break }
        }

        let status = responseHeaders.first(where: { $0.name == ":status" }).flatMap { Int($0.value) } ?? 200
        let grpcStatus = responseHeaders.first(where: { $0.name == "grpc-status" }).flatMap { Int($0.value) } ?? 0
        let grpcMessage = responseHeaders.first(where: { $0.name == "grpc-message" })?.value ?? ""
        return H3Response(
            status: status, grpcStatus: grpcStatus, grpcMessage: grpcMessage,
            headers: responseHeaders, body: grpcBodyAccumulator
        )
    }

    func cancel() {
        // H3_REQUEST_CANCELLED (RFC 9114 §8.1) — resets the stream.
        stream.streamApplicationErrorCode = 0x010c
    }
}
