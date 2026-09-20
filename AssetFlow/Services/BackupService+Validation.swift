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
  static func resolveBackupRoot(at extractionDir: URL) throws -> URL {
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
  static func validateExtractedBackup(
    at dir: URL
  ) throws -> BackupManifest {
    try loadValidatedBackup(at: dir).manifest
  }
}

// MARK: - ZIP Operations

extension BackupService {

  static func createZip(from dir: URL, to zipURL: URL) throws {
    // Remove existing file if present
    try? FileManager.default.removeItem(at: zipURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc", dir.path, zipURL.path]

    let pipe = Pipe()
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
      let errorMsg =
        String(data: errorData, encoding: .utf8)
        ?? localizedBackupMessage("Unknown ditto error")
      throw BackupError.corruptedData(
        localizedBackupMessage("Failed to create ZIP: \(errorMsg)"))
    }
  }

  static func extractZip(from zipURL: URL, to dir: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", zipURL.path, dir.path]

    let pipe = Pipe()
    process.standardError = pipe

    do {
      try process.run()
    } catch {
      throw BackupError.invalidArchive
    }
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw BackupError.invalidArchive
    }
  }
}
