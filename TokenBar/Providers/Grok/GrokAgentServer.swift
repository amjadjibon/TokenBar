import Foundation

/// A short-lived ACP session with `grok agent stdio`.
actor GrokAgentServer {
    private let executable: URL
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
        process.arguments = ["agent", "stdio"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        // Grok can emit account-shaped diagnostics; never put those in logs.
        process.standardError = FileHandle.nullDevice

        let (chunks, continuation) = AsyncStream<Data>.makeStream()
        let reader = output.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { continuation.finish() } else { continuation.yield(data) }
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
        stdin = input.fileHandleForWriting
        readerTask = Task { [weak self] in await self?.consume(chunks) }
    }

    func stop() {
        readerTask?.cancel()
        readerTask = nil
        try? stdin?.close()
        stdin = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        failPending(with: ProviderError.unavailable)
    }

    func request<Result: Decodable & Sendable>(
        _ method: String,
        params: some Encodable & Sendable,
        as type: Result.Type,
        timeout: Duration = .seconds(7)
    ) async throws -> Result {
        let id = nextID
        nextID += 1
        let encoder = JSONEncoder()
        // Grok's extension dispatcher currently compares the encoded method
        // before normal JSON slash unescaping, so `x.ai\/billing` misses while
        // the literal `x.ai/billing` works.
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let payload = try encoder.encode(Request(id: id, method: method, params: params))

        let timer = Task { [weak self] in
            try await Task.sleep(for: timeout)
            await self?.expire(id)
        }
        defer { timer.cancel() }

        let resultData = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                do {
                    try send(payload)
                } catch {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.expire(id) }
        }

        guard let result = try? JSONDecoder().decode(Result.self, from: resultData) else {
            throw ProviderError.invalidResponse
        }
        return result
    }

    private func send(_ payload: Data) throws {
        guard let stdin else { throw ProviderError.unavailable }
        var line = payload
        line.append(0x0A)
        do { try stdin.write(contentsOf: line) } catch { throw ProviderError.unavailable }
    }

    private func consume(_ chunks: AsyncStream<Data>) async {
        var buffer = Data()
        for await chunk in chunks {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty { handle(line) }
            }
        }
        failPending(with: ProviderError.invalidResponse)
    }

    private func handle(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = object["id"] as? Int,
              let continuation = pending.removeValue(forKey: id)
        else { return }

        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String ?? "").lowercased()
            continuation.resume(
                throwing: message.contains("authentication")
                    ? ProviderError.authenticationRequired
                    : ProviderError.unavailable
            )
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

    private func expire(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: ProviderError.timeout)
    }

    private func failPending(with error: any Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
    }

    deinit {
        readerTask?.cancel()
        if let process, process.isRunning { process.terminate() }
    }

    private struct Request<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: Params
    }
}
