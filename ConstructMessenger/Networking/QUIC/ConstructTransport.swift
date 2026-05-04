import GRPCCore
import GRPCNIOTransportHTTP2
import Network

// MARK: - ConstructTransport

/// A type-erasing `ClientTransport` that routes RPCs to either the TCP/HTTP-2 transport
/// or the QUIC/HTTP-3 transport, selected at construction time.
///
/// Both underlying transports share the same `Bytes` associated type (`GRPCNIOTransportBytes`),
/// so `Inbound` and `Outbound` stream types are structurally identical. The wrapper dispatches
/// every protocol method to the active implementation with zero type conversion.
///
/// This allows `GRPCCallExecutor` and all generated service clients to be typed against
/// `GRPCClient<ConstructTransport>` without modification — the transport choice is
/// encapsulated entirely inside `GRPCChannelManager.makeClient()`.
///
/// **Usage:**
/// ```swift
/// // TCP (current default)
/// let t = try HTTP2ClientTransport.TransportServices(target: ..., transportSecurity: .tls)
/// let client = GRPCClient(transport: ConstructTransport(tcp: t), interceptors: [...])
///
/// // QUIC (when FeatureFlags.useQUICTransport is true)
/// let q = NWQUICGRPCTransport(host: host, port: 443)
/// let client = GRPCClient(transport: ConstructTransport(quic: q), interceptors: [...])
/// ```
struct ConstructTransport: ClientTransport, Sendable {

    typealias Bytes = GRPCNIOTransportBytes

    // MARK: - Implementation selector

    private enum Impl: Sendable {
        case tcp(HTTP2ClientTransport.TransportServices)
        case quic(NWQUICGRPCTransport)
    }

    private let impl: Impl

    init(tcp: HTTP2ClientTransport.TransportServices) {
        self.impl = .tcp(tcp)
    }

    init(quic: NWQUICGRPCTransport) {
        self.impl = .quic(quic)
    }

    // MARK: - ClientTransport

    var retryThrottle: RetryThrottle? {
        switch impl {
        case .tcp(let t):  return t.retryThrottle
        case .quic(let t): return t.retryThrottle
        }
    }

    func config(forMethod descriptor: MethodDescriptor) -> MethodConfig? {
        switch impl {
        case .tcp(let t):  return t.config(forMethod: descriptor)
        case .quic(let t): return t.config(forMethod: descriptor)
        }
    }

    func connect() async throws {
        switch impl {
        case .tcp(let t):  try await t.connect()
        case .quic(let t): try await t.connect()
        }
    }

    func beginGracefulShutdown() {
        switch impl {
        case .tcp(let t):  t.beginGracefulShutdown()
        case .quic(let t): t.beginGracefulShutdown()
        }
    }

    /// Dispatches to the active transport. Because both implementations have
    /// `Bytes = GRPCNIOTransportBytes`, the `RPCStream<Inbound, Outbound>` closure
    /// type is identical for TCP and QUIC — no conversion, no overhead.
    func withStream<T: Sendable>(
        descriptor: MethodDescriptor,
        options: CallOptions,
        _ closure: (RPCStream<Inbound, Outbound>, ClientContext) async throws -> T
    ) async throws -> T {
        switch impl {
        case .tcp(let t):
            return try await t.withStream(descriptor: descriptor, options: options, closure)
        case .quic(let t):
            return try await t.withStream(descriptor: descriptor, options: options, closure)
        }
    }
}
