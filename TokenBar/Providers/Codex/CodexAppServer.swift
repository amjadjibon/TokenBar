import Foundation
import OSLog

/// One session with `codex app-server`, speaking newline-delimited JSON-RPC
/// over the process's stdio.
///
/// Two behaviours of the server shape this code: replies omit the `jsonrpc`
/// field, and the server shuts down as soon as its stdin closes — so stdin is
/// held open until `stop()`.
actor CodexAppServer {
    private let executable: URL
    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "codex")

    private var process: Process?
    private var stdin: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var nextID = 1

    init(executable: URL) {
        self.executable = executable
    }

    func start() throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        // Dropped rather than logged: the server's diagnostics are not worth the
        // risk of writing anything credential-shaped into the system log.
        process.standardError = FileHandle.nullDevice

        let (lines, continuation) = AsyncStream<Data>.makeStream()
        let reader = output.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        process.terminationHandler = { _ in continuation.finish() }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            continuation.finish()
            throw ProviderError.executableNotFound
        }

        self.process = process
        self.stdin = input.fileHandleForWriting
        self.readerTask = Task { [weak self] in
            await self?.consume(lines)
        }
    }

    func stop() {
        readerTask?.cancel()
        readerTask = nil
        try? stdin?.close()
        stdin = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        failPending(with: ProviderError.unavailable)
    }

    func request<Result: Decodable & Sendable>(
        _ method: String,
        params: some Encodable & Sendable,
        as type: Result.Type
    ) async throws -> Result {
        let id = nextID
        nextID += 1

        let payload = try JSONEncoder().encode(RPCRequest(id: id, method: method, params: params))

        let resultData = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try send(payload)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }

        guard let decoded = try? JSONDecoder().decode(Result.self, from: resultData) else {
            throw ProviderError.invalidResponse
        }
        return decoded
    }

    func notify(_ method: String) throws {
        try send(try JSONEncoder().encode(RPCNotification(method: method)))
    }

    // MARK: - Transport

    private func send(_ payload: Data) throws {
        guard let stdin else { throw ProviderError.unavailable }
        var line = payload
        line.append(0x0A)
        do {
            try stdin.write(contentsOf: line)
        } catch {
            throw ProviderError.unavailable
        }
    }

    /// Frames the byte stream into lines and routes each reply to its waiter.
    /// `AsyncStream` preserves the order chunks were read in, which line framing
    /// depends on.
    private func consume(_ lines: AsyncStream<Data>) async {
        var buffer = Data()

        for await chunk in lines {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty {
                    handle(line: Data(line))
                }
            }
        }

        // Stream ended: the server exited or stdin closed. Nothing else will
        // arrive, so no caller should keep waiting.
        failPending(with: ProviderError.invalidResponse)
    }

    /// Replies are `{"id":N,"result":{...}}` or `{"id":N,"error":{...}}`; anything
    /// without an `id` is a server notification TokenBar does not subscribe to.
    private func handle(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = object["id"] as? Int,
              let continuation = pending.removeValue(forKey: id)
        else { return }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown error"
            logger.error("Request \(id) failed: \(message, privacy: .public)")
            continuation.resume(throwing: ProviderError.invalidResponse)
            return
        }

        guard let result = object["result"],
              let data = try? JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed)
        else {
            continuation.resume(throwing: ProviderError.invalidResponse)
            return
        }
        continuation.resume(returning: data)
    }

    private func failPending(with error: any Error) {
        let waiters = pending.values
        pending.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    deinit {
        readerTask?.cancel()
        if let process, process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Envelopes

    private struct RPCRequest<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: Params
    }

    private struct RPCNotification: Encodable {
        let jsonrpc = "2.0"
        let method: String
    }

}
