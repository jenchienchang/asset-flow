//  AssetFlow — snapshot-based portfolio management for macOS.
//  Copyright (C) 2026 Jen-Chien Chang
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Darwin
import Foundation

// MARK: - Validation

extension BackupService {

  /// Resolves the directory containing the backup files after extraction.
  ///
  /// Backups exported by AssetFlow place files at the extraction root. Some
  /// archive tools preserve the selected folder as one enclosing directory,
  /// so accept exactly one immediate child directory containing a manifest.
  /// Deeper recursive searches are intentionally not supported because they
  /// could accept an ambiguous or unrelated manifest.
  nonisolated static func resolveBackupRoot(at extractionDir: URL) throws -> URL {
    let manifestPath =
      extractionDir
      .appending(path: BackupCSV.manifestFileName)
    if FileManager.default.fileExists(atPath: manifestPath.path) {
      return extractionDir
    }

    let children = try FileManager.default.contentsOfDirectory(
      at: extractionDir,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      options: [])
    let candidates = children.filter { child in
      guard
        let values = try? child.resourceValues(
          forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
        values.isDirectory == true,
        values.isSymbolicLink != true
      else {
        return false
      }
      return FileManager.default.fileExists(
        atPath: child.appending(path: BackupCSV.manifestFileName).path)
    }

    guard candidates.count == 1 else {
      if candidates.count > 1 {
        throw BackupError.invalidArchiveLayout
      }
      throw BackupError.missingFile(BackupCSV.manifestFileName)
    }
    return candidates[0]
  }

  /// Validates an already-extracted backup directory.
  ///
  /// - Parameter dir: Path to the extracted backup directory.
  /// - Returns: The parsed `BackupManifest` on success.
  /// - Throws: `BackupError` if the contents are invalid.
  nonisolated static func validateExtractedBackup(
    at dir: URL
  ) throws -> BackupManifest {
    try loadValidatedBackup(at: dir).manifest
  }
}

// MARK: - ZIP Operations

extension BackupService {

  nonisolated static func createZip(from dir: URL, to zipURL: URL) async throws {
    try await runDitto(
      arguments: ["-c", "-k", "--sequesterRsrc", dir.path, zipURL.path])

    guard FileManager.default.fileExists(atPath: zipURL.path) else {
      throw BackupError.archiveCreationFailed(nil)
    }
  }

  nonisolated static func extractZip(from zipURL: URL, to dir: URL) async throws {
    do {
      try await runDitto(arguments: ["-x", "-k", zipURL.path, dir.path])
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw BackupError.invalidArchive
    }
  }

  private nonisolated static func runDitto(arguments: [String]) async throws {
    try await runProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
      arguments: arguments)
  }

  /// Internal process seam for synthetic stderr and cancellation tests.
  nonisolated static func runProcess(
    executableURL: URL,
    arguments: [String]
  ) async throws {
    try Task.checkCancellation()

    let box = DittoProcessBox()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardError = pipe
        let diagnostics = DittoStderrCapture(handle: pipe.fileHandleForReading)
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
          diagnostics.drain()
          reader.leave()
        }

        process.terminationHandler = { process in
          diagnostics.stop()
          reader.notify(queue: .global(qos: .utility)) {
            if box.cancellationRequested {
              box.resume(continuation, with: .failure(CancellationError()))
            } else if process.terminationStatus == 0 {
              box.resume(continuation, with: .success(()))
            } else {
              box.resume(
                continuation,
                with: .failure(BackupError.archiveCreationFailed(diagnostics.message)))
            }
          }
        }

        do {
          try process.run()
          try? pipe.fileHandleForWriting.close()
          box.install(process)
        } catch {
          try? pipe.fileHandleForWriting.close()
          diagnostics.stop()
          box.resume(continuation, with: .failure(error))
        }
      }
    } onCancel: {
      box.cancel()
    }

    try Task.checkCancellation()
  }
}

private nonisolated final class DittoStderrCapture: @unchecked Sendable {
  private static let maximumDiagnosticBytes = 4 * 1_024
  private static let maximumDisplayedScalars = 240
  private let handle: FileHandle
  private let lock = NSLock()
  private var stopRequested = false
  private var tail = Data()
  private var omittedEarlierOutput = false

  nonisolated init(handle: FileHandle) {
    self.handle = handle
  }

  nonisolated func drain() {
    defer { try? handle.close() }
    let descriptor = handle.fileDescriptor
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
      return
    }

    var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
    while true {
      if shouldStop {
        _ = readAvailable(from: descriptor, into: &buffer, maximumChunks: 128)
        return
      }

      var descriptorState = pollfd(
        fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
      let result = Darwin.poll(&descriptorState, 1, 50)
      if result < 0 {
        if errno == EINTR { continue }
        return
      }
      if result > 0,
        !readAvailable(from: descriptor, into: &buffer, maximumChunks: 16)
      {
        return
      }
    }
  }

  nonisolated func stop() {
    lock.lock()
    stopRequested = true
    lock.unlock()
  }

  private nonisolated var shouldStop: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopRequested
  }

  private nonisolated func readAvailable(
    from descriptor: Int32,
    into buffer: inout [UInt8],
    maximumChunks: Int
  ) -> Bool {
    for _ in 0..<maximumChunks {
      let count = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(descriptor, bytes.baseAddress!, bytes.count)
      }
      if count > 0 {
        append(Data(buffer.prefix(count)))
      } else if count == 0 {
        return false
      } else if errno == EAGAIN || errno == EWOULDBLOCK {
        return true
      } else if errno != EINTR {
        return false
      }
    }
    return true
  }

  private nonisolated func append(_ chunk: Data) {
    if chunk.count >= Self.maximumDiagnosticBytes {
      tail = Data(chunk.suffix(Self.maximumDiagnosticBytes))
      omittedEarlierOutput = true
      return
    }

    let excess = max(0, tail.count + chunk.count - Self.maximumDiagnosticBytes)
    if excess > 0 {
      tail.removeFirst(excess)
      omittedEarlierOutput = true
    }
    tail.append(chunk)
  }

  nonisolated var message: String? {
    // The reader group must finish before this value is accessed.
    let lines = String(decoding: tail, as: UTF8.self)
      .split(whereSeparator: \.isNewline)
    let cleaned = lines.reversed().lazy.compactMap { line -> String? in
      let value = line.unicodeScalars.map { scalar in
        CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
      }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }.first
    guard let cleaned else { return nil }

    let clipped = cleaned.unicodeScalars.suffix(Self.maximumDisplayedScalars)
      .map(String.init).joined()
    let omitted =
      omittedEarlierOutput || lines.count > 1
      || cleaned.unicodeScalars.count > Self.maximumDisplayedScalars
    if omitted {
      return
        "\(clipped)\n\(BackupService.localizedBackupMessage("Some error details were omitted."))"
    }
    return clipped
  }
}

private nonisolated final class DittoProcessBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?
  private(set) var isCancellationRequested = false
  private var didResume = false

  nonisolated var cancellationRequested: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isCancellationRequested
  }

  nonisolated func install(_ process: Process) {
    lock.lock()
    guard !didResume else {
      lock.unlock()
      return
    }
    self.process = process
    let shouldTerminate = isCancellationRequested
    lock.unlock()

    if shouldTerminate && process.isRunning {
      process.terminate()
    }
  }

  nonisolated func cancel() {
    lock.lock()
    isCancellationRequested = true
    let process = self.process
    lock.unlock()

    if process?.isRunning == true {
      process?.terminate()
    }
  }

  nonisolated func resume(
    _ continuation: CheckedContinuation<Void, Error>,
    with result: Result<Void, Error>
  ) {
    lock.lock()
    let shouldResume = !didResume
    didResume = true
    process = nil
    lock.unlock()

    if shouldResume {
      continuation.resume(with: result)
    }
  }
}
