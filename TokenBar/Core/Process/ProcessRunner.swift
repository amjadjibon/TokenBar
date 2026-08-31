import Foundation

nonisolated struct ProcessOutput: Sendable {
    let stdout: String
    let exitCode: Int32
}

/// Runs a provider CLI once and collects its output.
///
/// Arguments are always passed as an array — TokenBar never builds a shell
/// command string out of provider data.
actor ProcessRunner {
    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration = .seconds(20)
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        // Dropped rather than captured: CLI diagnostics are not worth the risk of
        // writing anything credential-shaped into a log.
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        // Streamed rather than read at the end, so a child that outgrows the pipe
        // buffer cannot deadlock waiting for us to drain it.
        let (chunks, continuation) = AsyncStream<Data>.makeStream()
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

        let watchdog = Task {
            try await Task.sleep(for: timeout)
            process.terminate()
        }
        defer {
            watchdog.cancel()
            reader.readabilityHandler = nil
        }

        var data = Data()
        for await chunk in chunks {
            data.append(chunk)
        }
        process.waitUntilExit()

        return ProcessOutput(
            stdout: String(decoding: data, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}
