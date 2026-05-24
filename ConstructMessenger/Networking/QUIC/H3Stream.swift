import Foundation
import Network
import os

// MARK: - H3 Response

struct H3Response {
    let status: Int
    let grpcStatus: Int
    let grpcMessage: String
    let headers: [QPACKLite.HeaderField]
    let body: Data
}

// MARK: - H3Stream

/// A single bidirectional QUIC stream carrying one gRPC request/response.
///
/// Each instance wraps one NWConnection opened with NWProtocolQUIC in bidirectional mode.
/// The system automatically coalesces multiple streams to the same host:port onto one QUIC session.
///
/// Lifecycle:
/// 1. `connect()` — establishes the stream (QUIC handshake happens on first stream in session)
/// 2. `sendRequest(headers:grpcBody:)` — writes H3 HEADERS + H3 DATA, then closes the send half
/// 3. `receiveResponse()` — reads H3 frames until HEADERS + DATA + FIN, returns `H3Response`
/// 4. The stream is cancelled automatically on deinit.
final class H3Stream: QUICStreamProtocol, @unchecked Sendable {

    private let connection: NWConnection
    private let readySignal = AsyncStream<Result<Void, Error>>.makeStream()
    private var didSendReady = false

    // MARK: - Init

    init(to endpoint: NWEndpoint, parameters: NWParameters) {
        connection = NWConnection(to: endpoint, using: parameters)
    }

    // MARK: - Connect

    func connect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // OSAllocatedUnfairLock guards the once-resume contract.
            // stateUpdateHandler is called from the global concurrent queue, so a plain
            // `var resumed = false` would be a Swift 6 data race (concurrent mutation).
            // The [weak self] capture was also removed — self is never used in this closure.
            let once = OSAllocatedUnfairLock<Bool>(initialState: false)
            connection.stateUpdateHandler = { state in
                let should = once.withLockUnchecked { done -> Bool in
                    guard !done else { return false }; done = true; return true
                }
                guard should else { return }
                switch state {
                case .ready:               cont.resume()
                case .failed(let err):     cont.resume(throwing: err)
                case .cancelled:           cont.resume(throwing: CancellationError())
                default:                   break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Send request

    /// Sends H3 HEADERS frame + H3 DATA frame on the stream.
    /// Uses `isComplete: false` — the server closes the stream after sending its response
    /// (it sees the request is complete from the H3 framing), so we do not need to
    /// send a write-side FIN. Sending `nil` with `isComplete: true` would close BOTH
    /// directions (NWProtocolQUIC treats it as full stream close → ENOTCONN on receive).
    func sendRequest(headers: [(name: String, value: String)], grpcBody: Data) async throws {
        let encodedHeaders = QPACKLite.encodeHeaders(headers)
        let headersFrame = H3FrameEncoder.headers(encodedHeaders)
        let grpcFramed = GRPCFraming.encode(grpcBody)
        let dataFrame = H3FrameEncoder.data(grpcFramed)

        var requestBytes = headersFrame
        requestBytes.append(dataFrame)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: requestBytes,
                contentContext: .defaultMessage,
                isComplete: false,
                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            )
        }
    }

    // MARK: - Receive response

    /// Reads H3 frames until a complete gRPC response is received.
    /// A unary gRPC response consists of:
    ///   - HEADERS frame  (:status, content-type, ...)
    ///   - DATA frame     (gRPC 5-byte framing + protobuf body; may be absent for status-only responses)
    ///   - HEADERS frame  (trailers: grpc-status, grpc-message)
    ///   - FIN            (isComplete = true from NWConnection)
    ///
    /// Both HEADERS frames are appended to the same `responseHeaders` array so callers
    /// can search for `:status` and `grpc-status` in one place.
    func receiveResponse() async throws -> H3Response {
        var reader = H3FrameReader()
        var responseHeaders: [QPACKLite.HeaderField] = []
        var grpcBodyAccumulator = Data()

        while true {
            let (data, isComplete, error) = await receiveChunk()

            // Always process data BEFORE checking error/FIN — the final chunk carrying
            // gRPC trailers may arrive together with isComplete=true or POSIX 57.
            if let chunk = data, !chunk.isEmpty {
                reader.append(chunk)
            }

            while let frame = reader.next() {
                switch frame.type {
                case H3FrameType.headers.rawValue:
                    guard let fields = QPACKLite.decodeHeaders(frame.payload) else {
                        throw H3Error.malformedHeaders
                    }
                    responseHeaders.append(contentsOf: fields)

                case H3FrameType.data.rawValue:
                    var remaining = frame.payload
                    while let (msg, consumed) = GRPCFraming.decode(remaining) {
                        grpcBodyAccumulator.append(msg)
                        remaining = remaining.dropFirst(consumed)
                    }

                default:
                    break   // ignore unknown frame types (RFC 9114 §9)
                }
            }

            if let err = error {
                // POSIX 57 after FIN is normal — the stream has closed.
                let hasTrailers = responseHeaders.contains(where: { $0.name == "grpc-status" })
                if hasTrailers || isComplete { break }
                if grpcBodyAccumulator.isEmpty && responseHeaders.isEmpty { throw err }
                break
            }

            if isComplete { break }
        }

        return try buildResponse(headers: responseHeaders, body: grpcBodyAccumulator)
    }

    // MARK: - Cancel

    func cancel() {
        connection.cancel()
    }

    // MARK: - Private

    private func receiveChunk() async -> (data: Data?, isComplete: Bool, error: Error?) {
        await withCheckedContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                cont.resume(returning: (data, isComplete, error))
            }
        }
    }

    private func buildResponse(headers: [QPACKLite.HeaderField], body: Data) throws -> H3Response {
        let status = headers.first(where: { $0.name == ":status" }).flatMap { Int($0.value) } ?? 200
        let grpcStatus = headers.first(where: { $0.name == "grpc-status" }).flatMap { Int($0.value) } ?? 0
        let grpcMessage = headers.first(where: { $0.name == "grpc-message" })?.value ?? ""
        return H3Response(status: status, grpcStatus: grpcStatus, grpcMessage: grpcMessage,
                          headers: headers, body: body)
    }
}

// MARK: - Errors

enum H3Error: Error, LocalizedError {
    case malformedHeaders
    case sessionNotReady
    case streamFailed(Error)

    var errorDescription: String? {
        switch self {
        case .malformedHeaders:     return "H3: malformed response headers"
        case .sessionNotReady:      return "H3: session not ready"
        case .streamFailed(let e):  return "H3: stream failed — \(e)"
        }
    }
}
