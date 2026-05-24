import Foundation

// MARK: - QUICStreamProtocol

/// Abstracts one bidirectional QUIC stream carrying one gRPC request/response.
///
/// Two implementations:
/// - `H3Stream` (iOS 18.5+): backed by `NWConnection` with `NWProtocolQUIC`
/// - `QUICNativeStream` (iOS 26+): backed by `QUIC.Stream<QUICStream>`
protocol QUICStreamProtocol: Sendable {
    /// Activates the underlying network connection. No-op for `QUICNativeStream`
    /// (stream is ready as soon as `openStream()` returns).
    func connect() async throws
    /// Encodes H3 HEADERS + DATA frames and half-closes the send side.
    func sendRequest(headers: [(name: String, value: String)], grpcBody: Data) async throws
    /// Reads H3 frames until response headers + body + FIN.
    func receiveResponse() async throws -> H3Response
    /// Cancels the stream immediately (resets without graceful close).
    func cancel()
}

// MARK: - QUICSessionProtocol

/// Abstracts a QUIC session (one connection to a remote host) that vends streams.
///
/// Two implementations:
/// - `H3Session` (iOS 18.5+): backed by `NWProtocolQUIC`
/// - `QUICNativeSession` (iOS 26+): backed by `NetworkConnection<QUIC>`
protocol QUICSessionProtocol: AnyObject, Sendable {
    /// Establishes the QUIC connection and H3 control stream. Idempotent.
    func connect() async throws
    /// Opens a new bidirectional stream for one gRPC call.
    func openStream() async throws -> any QUICStreamProtocol
    /// Tears down the session gracefully.
    func close() async
}
