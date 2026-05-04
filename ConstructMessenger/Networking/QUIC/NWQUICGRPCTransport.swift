import Foundation
import Network
import os
import GRPCCore
import GRPCNIOTransportHTTP2

// MARK: - NWQUICGRPCTransport

/// A `GRPCCore.ClientTransport` that sends gRPC requests over HTTP/3 using Apple's
/// `NWProtocolQUIC` networking stack (iOS 15+) or `NetworkConnection<QUIC>` (iOS 26+).
///
/// Uses the same `Bytes` type (`GRPCNIOTransportBytes`) as `HTTP2ClientTransport.TransportServices`
/// so that it can be wrapped alongside the TCP transport in `ConstructTransport` without
/// any conversion of the `RPCStream` types.
///
/// **Thread safety**: the transport itself is `Sendable`. State is isolated inside the
/// session actor and an `OSAllocatedUnfairLock`-protected state machine.
final class NWQUICGRPCTransport: ClientTransport, @unchecked Sendable {

    typealias Bytes = GRPCNIOTransportBytes

    // MARK: - Types

    typealias Inbound  = RPCAsyncSequence<RPCResponsePart<Bytes>, any Error>
    typealias Outbound = RPCWriter<RPCRequestPart<Bytes>>.Closable

    // MARK: - State

    private enum State {
        case notStarted
        case running(any QUICSessionProtocol)
        case stopped
    }
    private let stateLock = OSAllocatedUnfairLock<State>(initialState: .notStarted)
    private let host: String
    private let port: UInt16

    // Shutdown signal: connect() (first call, from runConnections()) waits on this stream.
    // beginGracefulShutdown() finishes it, which unblocks the for-await in connect() and
    // allows GRPCClient.runConnections() to return normally.
    //
    // Root cause of clientIsStopped:
    //   GRPCClient.runConnections() calls transport.connect() then exits immediately when
    //   connect() returns. If connect() returns right after starting the QUIC session,
    //   the GRPCClient transitions to .stopped and every subsequent RPC throws clientIsStopped.
    //   Solution: connect() (first call only) suspends here until shutdown is signalled.
    private let shutdownSignal = AsyncStream<Void>.makeStream()

    // MARK: - Init

    init(host: String, port: UInt16 = 443) {
        self.host = host
        self.port = port
    }

    // MARK: - ClientTransport

    var retryThrottle: RetryThrottle? { nil }

    func config(forMethod descriptor: MethodDescriptor) -> MethodConfig? { nil }

    /// Establishes the QUIC session.
    ///
    /// **First call** (from `GRPCClient.runConnections()`): starts the session, then suspends
    /// until `beginGracefulShutdown()` is called. This keeps `runConnections()` alive and the
    /// `GRPCClient` in `.running` state so RPCs can be made.
    ///
    /// **Subsequent calls** (lazy re-connect from `withStream()`): returns immediately after
    /// the session's own `connect()` confirms readiness.
    func connect() async throws {
        enum ConnectResult {
            case session(any QUICSessionProtocol, isFirstCall: Bool)
            case stopped
        }
        let result: ConnectResult = stateLock.withLockUnchecked { state in
            switch state {
            case .notStarted:
                let s = makeSession()
                state = .running(s)
                return .session(s, isFirstCall: true)
            case .running(let s):
                return .session(s, isFirstCall: false)
            case .stopped:
                return .stopped
            }
        }
        switch result {
        case .session(let s, let isFirstCall):
            try await s.connect()
            if isFirstCall {
                // Suspend until beginGracefulShutdown() finishes the stream.
                // If shutdown was called before we reach this point, the stream is already
                // finished and the loop exits immediately — no deadlock.
                for await _ in shutdownSignal.stream {}
            }
        case .stopped:
            throw RPCError(code: .unavailable, message: "NWQUICGRPCTransport: transport stopped")
        }
    }

    func beginGracefulShutdown() {
        stateLock.withLockUnchecked { state in
            if case .running = state { state = .stopped }
        }
        // Wake up the for-await in connect() so runConnections() can exit cleanly.
        shutdownSignal.continuation.finish()
        // Sessions on iOS 26+ are owned by QUICNativeSessionPool and must not be closed
        // by individual transports — the pool keeps the NetworkConnection<QUIC> alive for
        // the next reconnect, avoiding a new listener-group allocation (POSIX 12).
        // H3Session.close() on iOS 15–25 is also a no-op today (the NWListener in
        // H3QUICParamsPool stays alive regardless), so skipping it is safe there too.
    }

    /// Opens one QUIC stream, drives the gRPC request/response lifecycle, then calls `closure`.
    ///
    /// Lazily calls `connect()` if the session isn't running yet (per-call client pattern).
    func withStream<T: Sendable>(
        descriptor: MethodDescriptor,
        options: CallOptions,
        _ closure: (RPCStream<Inbound, Outbound>, ClientContext) async throws -> T
    ) async throws -> T {
        try await connect()
        let session = try activeSession()
        let h3 = try await session.openStream()
        try await h3.connect()

        let (inboundStream, inboundCont) =
            AsyncThrowingStream<RPCResponsePart<Bytes>, any Error>.makeStream()

        let writer = NWQUICRequestWriter(
            descriptor: descriptor,
            h3Stream: h3,
            host: host,
            port: port,
            inboundContinuation: inboundCont
        )

        let rpcStream = RPCStream(
            descriptor: descriptor,
            inbound: RPCAsyncSequence(wrapping: inboundStream),
            outbound: RPCWriter.Closable(wrapping: writer)
        )
        let context = ClientContext(
            descriptor: descriptor,
            remotePeer: "quic:\(host):\(port)",
            localPeer: "quic-client"
        )

        defer { h3.cancel() }
        return try await closure(rpcStream, context)
    }

    // MARK: - Private

    private func makeSession() -> any QUICSessionProtocol {
        if #available(iOS 26, macOS 26, *) {
            // Use the process-wide pool to return the single shared session for this
            // endpoint. This ensures only one NetworkConnection<QUIC> (and therefore
            // one QUIC listener group) is ever created per host:port, regardless of
            // how many times GRPCChannelManager creates a new transport on reconnect.
            return QUICNativeSessionPool.shared.session(for: host, port: port)
        } else {
            return H3Session(config: H3Session.Config.production(host: host, port: port))
        }
    }

    private func activeSession() throws -> any QUICSessionProtocol {
        let s: (any QUICSessionProtocol)? = stateLock.withLockUnchecked { state in
            if case .running(let s) = state { return s }
            return nil
        }
        guard let s else {
            throw RPCError(code: .failedPrecondition, message: "NWQUICGRPCTransport: transport not running")
        }
        return s
    }
}

// MARK: - Request writer (outbound)

/// Buffers `RPCRequestPart` values written by the gRPC layer, then sends the complete
/// request over H3 when `finish()` is called.
///
/// After sending, reads the H3 response and feeds `RPCResponsePart` values into the
/// inbound stream continuation.
private final class NWQUICRequestWriter: ClosableRPCWriterProtocol, @unchecked Sendable {
    typealias Element = RPCRequestPart<GRPCNIOTransportBytes>

    private let h3Stream: any QUICStreamProtocol
    private let descriptor: MethodDescriptor
    private let host: String
    private let port: UInt16
    private let inboundContinuation: AsyncThrowingStream<RPCResponsePart<GRPCNIOTransportBytes>, any Error>.Continuation
    private var metadata: Metadata = Metadata()
    private var bodyAccumulator = Data()
    private var isFinished = false

    init(descriptor: MethodDescriptor,
         h3Stream: any QUICStreamProtocol,
         host: String,
         port: UInt16,
         inboundContinuation: AsyncThrowingStream<RPCResponsePart<GRPCNIOTransportBytes>, any Error>.Continuation)
    {
        self.descriptor = descriptor
        self.h3Stream = h3Stream
        self.host = host
        self.port = port
        self.inboundContinuation = inboundContinuation
    }

    func write(_ element: RPCRequestPart<GRPCNIOTransportBytes>) async throws {
        switch element {
        case .metadata(let md):
            metadata = md
        case .message(let bytes):
            bytes.withUnsafeBytes { bodyAccumulator.append(Data($0)) }
        }
    }

    func write(contentsOf elements: some Sequence<RPCRequestPart<GRPCNIOTransportBytes>>) async throws {
        for element in elements { try await write(element) }
    }

    func finish() async {
        guard !isFinished else { return }
        isFinished = true
        do {
            let headers = buildH3Headers()
            try await h3Stream.sendRequest(headers: headers, grpcBody: bodyAccumulator)
            let response = try await h3Stream.receiveResponse()
            pushResponse(response)
        } catch {
            inboundContinuation.finish(throwing: error)
        }
    }

    func finish(throwing error: any Error) async {
        isFinished = true
        h3Stream.cancel()
        inboundContinuation.finish(throwing: error)
    }

    // MARK: - Header construction

    private func buildH3Headers() -> [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = [
            (":method", "POST"),
            (":scheme", "https"),
            (":authority", port == 443 ? host : "\(host):\(port)"),
            (":path", "/\(descriptor.service.fullyQualifiedService)/\(descriptor.method)"),
            ("content-type", "application/grpc+proto"),
            // "te: trailers" is forbidden in HTTP/3 (RFC 9114 §4.2) — intentionally omitted.
        ]
        for (key, value) in metadata {
            switch value {
            case .string(let s):
                guard !key.hasPrefix(":") else { continue }
                headers.append((key, s))
            case .binary:
                break
            }
        }
        return headers
    }

    // MARK: - Response → inbound parts

    private func pushResponse(_ response: H3Response) {
        var initialMD = Metadata()
        for field in response.headers {
            guard !field.name.hasPrefix(":"), field.name != "grpc-status", field.name != "grpc-message" else { continue }
            initialMD.addString(field.value, forKey: field.name)
        }
        inboundContinuation.yield(.metadata(initialMD))

        if !response.body.isEmpty {
            let bytes = GRPCNIOTransportBytes(response.body)
            inboundContinuation.yield(.message(bytes))
        }

        let status: Status
        if let code = Status.Code(rawValue: response.grpcStatus) {
            status = Status(code: code, message: response.grpcMessage)
        } else {
            status = Status(code: .unknown, message: "unknown grpc-status \(response.grpcStatus)")
        }
        var trailersMD = Metadata()
        trailersMD.addString(String(response.grpcStatus), forKey: "grpc-status")
        if !response.grpcMessage.isEmpty {
            trailersMD.addString(response.grpcMessage, forKey: "grpc-message")
        }
        inboundContinuation.yield(.status(status, trailersMD))
        inboundContinuation.finish()
    }
}
