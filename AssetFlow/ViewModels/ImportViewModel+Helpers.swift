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
import SwiftData

// MARK: - Duplicate Detection, Revalidation, Import Execution, and Helpers

extension ImportViewModel {

  // MARK: - Revalidation

  /// Re-runs duplicate detection considering only included rows.
  func revalidate() {
    switch importType {
    case .assets:
      revalidateAssets()

    case .cashFlows:
      revalidateCashFlows()
    }
  }

  private func revalidateAssets() {
    // Clear per-row duplicate errors first (marketValueWarning is set during rebuild)
    for idx in assetPreviewRows.indices {
      assetPreviewRows[idx].duplicateError = nil
      assetPreviewRows[idx].snapshotDuplicateError = nil
    }

    // Detect within-CSV duplicates on included rows, assign per-row
    var seenIdentities: [String: Int] = [:]
    for (index, row) in assetPreviewRows.enumerated() where row.isIncluded {
      let identity = CSVParsingService.normalizedAssetIdentity(row: row.csvRow)
      if let firstIndex = seenIdentities[identity] {
        let firstRow = assetPreviewRows[firstIndex]
        let platformLabel =
          row.csvRow.platform.isEmpty
          ? String(localized: "None", table: "Import")
          : row.csvRow.platform
        assetPreviewRows[index].duplicateError = String(
          localized:
            "Duplicate asset '\(row.csvRow.assetName)' (platform: '\(platformLabel)') — first appeared as '\(firstRow.csvRow.assetName)'.",
          table: "Import")
      } else {
        seenIdentities[identity] = index
      }
    }

    // Detect CSV-vs-snapshot duplicates on included rows, assign per-row.
    // Note: uses String.normalizedForIdentity (equivalent to CSVParsingService.normalizedAssetIdentity)
    // because we compare against stored Asset.normalizedName/normalizedPlatform model properties.
    let normalizedDate = Calendar.current.startOfDay(for: snapshotDate)
    var snapshotDescriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date == normalizedDate }
    )
    snapshotDescriptor.fetchLimit = 1
    if let existingSnapshot = ((try? modelContext.fetch(snapshotDescriptor)) ?? []).first {
      let snapshotValueLookup = SnapshotAssetValueLookup(
        values: existingSnapshot.assetValues ?? [])
      for (index, row) in assetPreviewRows.enumerated() where row.isIncluded {
        let matchingSAV = snapshotValueLookup.value(
          forAssetNamed: row.csvRow.assetName, platform: row.csvRow.platform)
        if let matchingSAV {
          if matchingSAV.marketValue == 0 {
            // Zero-value SAVs are placeholders (e.g., from bulk entry pending rows).
            // The app's design assumes value=0 means the asset is not yet recorded;
            // if a snapshot should not hold an asset, the SAV should be removed.
            // Allow CSV import to overwrite these placeholders.
            assetPreviewRows[index].snapshotDuplicateError = nil
          } else {
            let platformLabel =
              row.csvRow.platform.isEmpty
              ? String(localized: "None", table: "Import")
              : row.csvRow.platform
            assetPreviewRows[index].snapshotDuplicateError = String(
              localized:
                "Asset '\(row.csvRow.assetName)' (platform: '\(platformLabel)') already exists in the snapshot for this date.",
              table: "Import")
          }
        }
      }
    }

    // Parsing errors stay in validationErrors — these represent rows that failed to parse
    // and don't appear in the preview (e.g., empty name, unparseable value, missing columns)
    validationErrors = parsingErrors

    // File-level warnings only (row <= 1) go into validationWarnings;
    // row-level warnings are shown as per-row popovers via marketValueWarning
    validationWarnings = baseAssetWarnings.filter { $0.row <= 1 }
  }

  private func revalidateCashFlows() {
    // Clear all per-row errors first
    for idx in cashFlowPreviewRows.indices {
      cashFlowPreviewRows[idx].duplicateError = nil
      cashFlowPreviewRows[idx].snapshotDuplicateError = nil
    }

    // Detect within-CSV duplicates on included rows, assign per-row
    var seenDescriptions: [String: Int] = [:]
    for (index, row) in cashFlowPreviewRows.enumerated() where row.isIncluded {
      let normalized = row.csvRow.description.lowercased()
        .trimmingCharacters(in: .whitespaces)
      if let firstIndex = seenDescriptions[normalized] {
        let firstRow = cashFlowPreviewRows[firstIndex]
        cashFlowPreviewRows[index].duplicateError = String(
          localized:
            "Duplicate description '\(row.csvRow.description)' — first appeared as '\(firstRow.csvRow.description)'.",
          table: "Import")
      } else {
        seenDescriptions[normalized] = index
      }
    }

    // Detect CSV-vs-snapshot duplicates on included rows, assign per-row
    let normalizedDate = Calendar.current.startOfDay(for: snapshotDate)
    var snapshotDescriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date == normalizedDate }
    )
    snapshotDescriptor.fetchLimit = 1
    if let existingSnapshot = ((try? modelContext.fetch(snapshotDescriptor)) ?? []).first {
      let cashFlowLookup = CashFlowDescriptionLookup(
        operations: existingSnapshot.cashFlowOperations ?? [])
      for (index, row) in cashFlowPreviewRows.enumerated() where row.isIncluded {
        if cashFlowLookup.contains(row.csvRow.description) {
          cashFlowPreviewRows[index].snapshotDuplicateError = String(
            localized:
              "Cash flow '\(row.csvRow.description)' already exists in the snapshot for this date.",
            table: "Import")
        }
      }
    }

    // Parsing errors stay in validationErrors — rows that failed to parse
    validationErrors = parsingErrors

    // File-level warnings only (row <= 1) go into validationWarnings;
    // row-level warnings are shown as per-row popovers via amountWarning
    validationWarnings = baseCashFlowWarnings.filter { $0.row <= 1 }
  }

  // MARK: - Import Execution

  func findOrCreateSnapshot(date: Date) -> Snapshot {
    var descriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date == date }
    )
    descriptor.fetchLimit = 1

    if let existing = ((try? modelContext.fetch(descriptor)) ?? []).first {
      return existing
    }

    let snapshot = Snapshot(date: date)
    modelContext.insert(snapshot)
    return snapshot
  }

  func executeAssetImport(snapshot: Snapshot) {
    let includedRows = assetPreviewRows.filter { $0.isIncluded }
    var assetLookup = AssetResolutionLookup(assets: fetchAllAssets())
    var snapshotValueLookup = SnapshotAssetValueLookup(values: snapshot.assetValues ?? [])

    for previewRow in includedRows {
      let row = previewRow.csvRow
      let asset = assetLookup.resolve(
        name: row.assetName, platform: row.platform, in: modelContext)

      // Assign currency only when the CSV explicitly provides one
      let rowCurrency = row.currency
      if !rowCurrency.isEmpty {
        asset.currency = rowCurrency
      }

      // Assign category based on apply mode
      if let category = selectedCategory {
        switch categoryApplyMode {
        case .overrideAll:
          asset.category = category

        case .fillEmptyOnly:
          if asset.category == nil {
            asset.category = category
          }
        }
      }

      // Update existing zero-value SAV (placeholder), or create new one.
      // Zero-value SAVs are treated as placeholders — the app assumes value=0 means
      // the asset is not yet recorded, so CSV import overwrites them in-place rather
      // than creating a duplicate entry.
      let existingSAV = snapshotValueLookup.value(for: asset)
      if let existingSAV {
        if existingSAV.marketValue == 0 {
          existingSAV.marketValue = row.marketValue
        } else {
          let sav = SnapshotAssetValue(marketValue: row.marketValue)
          sav.snapshot = snapshot
          sav.asset = asset
          modelContext.insert(sav)
          snapshotValueLookup.register(sav)
        }
      } else {
        let sav = SnapshotAssetValue(marketValue: row.marketValue)
        sav.snapshot = snapshot
        sav.asset = asset
        modelContext.insert(sav)
        snapshotValueLookup.register(sav)
      }
    }

    // Copy-forward: copy assets from selected platforms in prior snapshot
    if copyForwardEnabled {
      executeCopyForward(snapshot: snapshot)
    }
  }

  /// Copies asset values from selected platforms in the most recent prior snapshot.
  private func executeCopyForward(snapshot: Snapshot) {
    let selectedPlatforms = copyForwardPlatforms.filter { $0.isSelected }
    guard !selectedPlatforms.isEmpty else { return }

    let normalizedDate = Calendar.current.startOfDay(for: snapshotDate)

    guard
      let latestPrior = SnapshotSummaryService.fetchLatestSnapshot(
        before: normalizedDate,
        modelContext: modelContext)
    else { return }

    let selectedPlatformNames = Set(selectedPlatforms.map { $0.platformName.lowercased() })
    let priorValues = latestPrior.assetValues ?? []

    // Track assets already in the snapshot to avoid duplicates
    let existingAssetIDs = Set((snapshot.assetValues ?? []).compactMap { $0.asset?.id })

    for priorSAV in priorValues {
      guard let asset = priorSAV.asset else { continue }
      guard selectedPlatformNames.contains(asset.platform.lowercased()) else { continue }
      guard !existingAssetIDs.contains(asset.id) else { continue }

      let sav = SnapshotAssetValue(marketValue: priorSAV.marketValue)
      sav.snapshot = snapshot
      sav.asset = asset
      modelContext.insert(sav)
    }
  }

  func executeCashFlowImport(snapshot: Snapshot) {
    let includedRows = cashFlowPreviewRows.filter { $0.isIncluded }

    for previewRow in includedRows {
      let row = previewRow.csvRow
      let operation = CashFlowOperation(
        cashFlowDescription: row.description, amount: row.amount)
      let rowCurrency = row.currency
      if !rowCurrency.isEmpty {
        operation.currency = rowCurrency
      }
      operation.snapshot = snapshot
      modelContext.insert(operation)
    }
  }

  // MARK: - Helpers

  func clearLoadedData() {
    assetPreviewRows = []
    cashFlowPreviewRows = []
    validationErrors = []
    validationWarnings = []
    parsingErrors = []
    selectedFileURL = nil
    selectedFileData = nil
    importError = nil
    platformApplyMode = .overrideAll
    categoryApplyMode = .overrideAll
    copyForwardPlatforms = []
    baseAssetRows = []
    baseAssetParsingErrors = []
    baseAssetWarnings = []
    baseCashFlowWarnings = []
    excludedAssetIndices = []
    showColumnMappingSheet = false
    pendingRawHeaders = []
    pendingSampleRows = []
    pendingPartialMapping = [:]
  }

  func fetchAllAssets() -> [Asset] {
    let descriptor = FetchDescriptor<Asset>()
    return (try? modelContext.fetch(descriptor)) ?? []
  }

}
