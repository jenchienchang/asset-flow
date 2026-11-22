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

extension BackupService {
  nonisolated static func parsePlatforms(
    _ document: BackupCSVDocument?, issues: inout [BackupValidationIssue]
  ) -> [BackupPlatformRecord] {
    let file = BackupCSV.Platforms.fileName
    var result: [BackupPlatformRecord] = []
    var ids: Set<UUID> = []
    var names: Set<String> = []
    for record in document?.records ?? [] {
      guard validateArity(record, expected: 3, file: file, issues: &issues) else { continue }
      let id = parseUUID(
        record.fields[0], file: file, record: record, column: "id", issues: &issues)
      let name = record.fields[1].collapsingWhitespace
      if name.isEmpty || !names.insert(name.normalizedForIdentity).inserted {
        issues.append(
          issue(
            file: file, record: record, column: "name",
            detail: localizedBackupMessage("Expected a nonempty, unique normalized platform name."))
        )
      }
      let order = Int(scalar(record.fields[2]))
      if order.map({ $0 < 0 }) ?? true {
        issues.append(
          issue(
            file: file, record: record, column: "displayOrder",
            detail: localizedBackupMessage("Expected a nonnegative integer.")))
      }
      guard let id, let order, order >= 0 else { continue }
      validateUniqueID(id, ids: &ids, file: file, record: record, issues: &issues)
      result.append(BackupPlatformRecord(id: id, name: name, displayOrder: order))
    }
    return result
  }
}
