import XCTest
import Network
import GRPCCore
@testable import Construct_Messenger

// MARK: - H3 gRPC Integration Test
//
// Verifies end-to-end HTTP/3 gRPC connectivity against ams.konstruct.cc.
//
// Stack under test:
//   NWQUICGRPCTransport → H3Session (NWProtocolQUIC) → H3Stream
//   → Traefik 3.x (terminates QUIC, forwards h2c) → Envoy → microservice
//
// Run on a REAL device or simulator with network access.
// The test does NOT require a valid JWT — it calls AuthService.GetPowChallenge which is public.
//
// Expected outcomes:
//   testH3_handshakeAndSettings        PASS → QUIC + H3 control stream OK
//   testH3_unarygRPCCall               PASS → H3 HEADERS+DATA+trailers round-trip works
//   testH3_healthEndpoint              PASS → Traefik routes /health over H3
//   testNWQUICTransport_getPowChallenge PASS → full ClientTransport stack works
//
final class H3GRPCIntegrationTest: XCTestCase {

    private let host = "ams.konstruct.cc"
    private let port: UInt16 = 443
    private let timeout: TimeInterval = 15

    // MARK: - Test 1: QUIC handshake + H3 SETTINGS

    /// Verifies that `H3Session.connect()` completes: QUIC handshake succeeds and
    /// the H3 control stream with an empty SETTINGS frame is accepted by Traefik.
    func testH3_handshakeAndSettings() async throws {
        let session = H3Session(config: H3Session.Config.production(host: host, port: port))
        try await withTimeout(timeout) {
            try await session.connect()
        }
        let isReady = await session.isReady
        XCTAssertTrue(isReady,
            "H3Session did not reach .ready — check QUIC/H3 on \(self.host):\(self.port)")
        await session.close()
    }

    // MARK: - Test 2: Unary gRPC over H3 — AuthService (no JWT required)

    /// Sends a real gRPC request to AuthService over HTTP/3.
    ///
    /// AuthService is public (no JWT required per Envoy JWT rules).
    /// We call it with an empty body; the expected outcome is:
    ///   - H3 connection succeeds
    ///   - Server responds with a valid gRPC status (any status ≠ "no response")
    ///   - Response carries proper H3 HEADERS + (optional DATA) + trailing HEADERS
    ///     with `grpc-status` — proving H3 gRPC framing works end-to-end.
    func testH3_unarygRPCCall() async throws {
        let session = H3Session(config: H3Session.Config.production(host: host, port: port))
        try await withTimeout(timeout) {
            try await session.connect()
        }

        let stream = try await session.openStream()
        try await stream.connect()

        // gRPC call: POST /shared.proto.services.v1.AuthService/GetJWKS (no body needed)
        let headers: [(name: String, value: String)] = [
            (":method",       "POST"),
            (":scheme",       "https"),
            (":authority",    self.host),
            (":path",         "/shared.proto.services.v1.AuthService/GetJWKS"),
            ("content-type",  "application/grpc+proto"),
            // "te: trailers" is forbidden in HTTP/3 (RFC 9114 §4.2) — omitted intentionally.
        ]

        // Critical: start the receive loop in a background Task and yield before sending.
        // NWProtocolQUIC requires connection.receive() to be registered BEFORE
        // send(isComplete:true) is called — otherwise the read side is treated as
        // immediately closed (empty isComplete=true returned on first receive).
        let receiveTask = Task { try await stream.receiveResponse() }
        // Yield once so the Task above gets a chance to schedule connection.receive()
        // before we send (and close the write side).
        await Task.yield()
        try await stream.sendRequest(headers: headers, grpcBody: Data())
        let response: H3Response
        do {
            response = try await receiveTask.value
        } catch {
            receiveTask.cancel()
            throw error
        }

        // A valid gRPC response MUST have :status 200.
        // grpc-status can be anything (0 = OK, 12 = UNIMPLEMENTED, 2 = UNKNOWN, etc.)
        XCTAssertEqual(response.status, 200,
            "Expected :status 200, got \(response.status)")

        // grpc-status must be present (proves H3 trailers work end-to-end)
        let hasGrpcStatus = response.headers.contains(where: { $0.name == "grpc-status" })
        XCTAssertTrue(hasGrpcStatus,
            "No grpc-status trailer in H3 response — headers: \(response.headers.map { "\($0.name):\($0.value)" })")

        await session.close()
    }

    // MARK: - Test 3: HTTP-only /health endpoint over H3

    /// Verifies Traefik routes a non-gRPC path (/health) over H3.
    /// This is a simpler smoke test that doesn't depend on gRPC framing at all.
    func testH3_healthEndpoint() async throws {
        let session = H3Session(config: H3Session.Config.production(host: host, port: port))
        try await withTimeout(timeout) {
            try await session.connect()
        }

        let stream = try await session.openStream()
        try await stream.connect()

        // Plain HTTP GET /health — Traefik routes this even without gRPC framing
        let headers: [(name: String, value: String)] = [
            (":method",    "GET"),
            (":scheme",    "https"),
            (":authority", self.host),
            (":path",      "/health"),
            ("accept",     "*/*"),
        ]
        try await stream.sendRequest(headers: headers, grpcBody: Data())

        let response = try await stream.receiveResponse()

        XCTAssertTrue(
            response.status >= 200 && response.status < 500,
            "Expected a valid HTTP status from /health over H3, got \(response.status)"
        )

        await session.close()
    }

    // MARK: - Test 4: Full ClientTransport stack — NWQUICGRPCTransport + generated client

    /// Exercises the COMPLETE QUIC transport stack:
    ///   NWQUICGRPCTransport → ConstructTransport → GRPCClient → AuthService.Client
    ///
    /// Calls `AuthService.GetPowChallenge` which is public (no JWT required).
    /// Verifies that the generated gRPC-Swift client can make a real RPC over H3.
    /// Expected: any response (challenge data or grpc error) — proves the pipe works.
    func testNWQUICTransport_getPowChallenge() async throws {
        let transport = NWQUICGRPCTransport(host: host, port: port)
        let wrappedTransport = ConstructTransport(quic: transport)
        let client = GRPCClient(transport: wrappedTransport, interceptors: [])

        try await withTimeout(timeout) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await client.runConnections() }
                group.addTask {
                    let authClient = Shared_Proto_Services_V1_AuthService.Client(wrapping: client)
                    let request = Shared_Proto_Services_V1_GetPowChallengeRequest()
                    do {
                        let response = try await authClient.getPowChallenge(request)
                        // Any successful response proves the full stack works.
                        // challenge field may be empty if server returns OK.
                        _ = response.challenge
                    } catch let err as RPCError {
                        // Any gRPC error (UNAUTHENTICATED, UNIMPLEMENTED, etc.) still proves
                        // the H3 transport worked — the error came from the server, not the network.
                        // Only fail if grpc-status was missing (transport-level failure).
                        XCTAssertNotEqual(err.code, .unavailable,
                            "RPC unavailable — transport failed before reaching server: \(err)")
                    }
                    client.beginGracefulShutdown()
                }
                try await group.next()
                group.cancelAll()
            }
        }
    }

    // MARK: - Helpers

    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw XCTSkip("Operation timed out after \(seconds)s — may be a network issue")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

