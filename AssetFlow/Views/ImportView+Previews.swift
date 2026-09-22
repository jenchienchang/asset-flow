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
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Hover Popover Icon

private struct HoverPopoverIcon: View {
  let systemName: String
  let color: Color
  let message: String
  @Binding var activeRowID: UUID?
  let rowID: UUID
  @Environment(\.isAppLocked) private var isLocked

  var body: some View {
    Image(systemName: systemName)
      .font(.caption2)
      .foregroundStyle(color)
      .onHoverWhenUnlocked { hovering in
        activeRowID = hovering ? rowID : nil
      }
      .popover(
        isPresented: Binding(
          get: { !isLocked && activeRowID == rowID },
          set: { if !$0 { activeRowID = nil } }
        ),
        arrowEdge: .bottom
      ) {
        Text(message)
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
          .frame(idealWidth: 300, alignment: .leading)
          .padding()
      }
  }
}

// MARK: - Preview Tables and File Handling

extension ImportView {

  var assetPreviewTable: some View {
    VStack(spacing: 0) {
      // Header row — CSV column names are intentionally non-localizable
      HStack {
        Text(verbatim: "Asset Name")
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(verbatim: "Market Value")
          .fontWeight(.semibold)
          .frame(width: 120, alignment: .trailing)
        Text(verbatim: "Currency")
          .fontWeight(.semibold)
          .frame(width: 80, alignment: .leading)
        Text(verbatim: "Platform")
          .fontWeight(.semibold)
          .frame(width: 150, alignment: .leading)
        Text(verbatim: "Category")
          .fontWeight(.semibold)
          .frame(width: 120, alignment: .leading)
        Text("")
          .frame(width: 30)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(.fill.quaternary)

      Divider()

      // Data rows
      ForEach(
        Array(viewModel.assetPreviewRows.enumerated()), id: \.element.id
      ) { index, row in
        if row.isIncluded {
          HStack {
            HStack(spacing: 4) {
              Text(row.csvRow.assetName)
              if let error = row.duplicateError {
                HoverPopoverIcon(
                  systemName: "xmark.circle.fill",
                  color: .red,
                  message: error,
                  activeRowID: $activeDuplicateErrorRowID,
                  rowID: row.id
                )
              }
              if let error = row.snapshotDuplicateError {
                HoverPopoverIcon(
                  systemName: "xmark.circle.fill",
                  color: .red,
                  message: error,
                  activeRowID: $activeSnapshotDuplicateErrorRowID,
                  rowID: row.id
                )
              }
              if let warning = row.categoryWarning {
                HoverPopoverIcon(
                  systemName: "exclamationmark.triangle.fill",
                  color: .yellow,
                  message: warning,
                  activeRowID: $activeCategoryWarningRowID,
                  rowID: row.id
                )
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
              Text(row.csvRow.marketValue.formatted())
                .monospacedDigit()
              if let warning = row.marketValueWarning {
                HoverPopoverIcon(
                  systemName: "exclamationmark.triangle.fill",
                  color: .yellow,
                  message: warning,
                  activeRowID: $activeMarketValueWarningRowID,
                  rowID: row.id
                )
              }
            }
            .frame(width: 120, alignment: .trailing)

            HStack(spacing: 4) {
              Text(row.effectiveCurrency.isEmpty ? "-" : row.effectiveCurrency)
                .foregroundStyle(row.effectiveCurrency.isEmpty ? .tertiary : .primary)
              if let error = row.currencyError {
                HoverPopoverIcon(
                  systemName: "xmark.circle.fill",
                  color: .red,
                  message: error,
                  activeRowID: $activeCurrencyErrorRowID,
                  rowID: row.id
                )
              } else if let warning = row.currencyWarning {
                HoverPopoverIcon(
                  systemName: "exclamationmark.triangle.fill",
                  color: .yellow,
                  message: warning,
                  activeRowID: $activeCurrencyWarningRowID,
                  rowID: row.id
                )
              }
            }
            .frame(width: 80, alignment: .leading)

            Text(row.csvRow.platform.isEmpty ? "-" : row.csvRow.platform)
              .frame(width: 150, alignment: .leading)
              .foregroundStyle(row.csvRow.platform.isEmpty ? .tertiary : .primary)

            Text(row.effectiveCategory.isEmpty ? "-" : row.effectiveCategory)
              .frame(width: 120, alignment: .leading)
              .foregroundStyle(row.effectiveCategory.isEmpty ? .tertiary : .primary)

            Button {
              viewModel.removeAssetPreviewRow(at: index)
            } label: {
              Image(systemName: "minus.circle")
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 30)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)

          Divider()
        }
      }
    }
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(.separator, lineWidth: 1)
    )
  }

  var cashFlowPreviewTable: some View {
    VStack(spacing: 0) {
      // Header row — CSV column names are intentionally non-localizable
      HStack {
        Text(verbatim: "Description")
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(verbatim: "Amount")
          .fontWeight(.semibold)
          .frame(width: 120, alignment: .trailing)
        Text("")
          .frame(width: 30)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(.fill.quaternary)

      Divider()

      // Data rows
      ForEach(
        Array(viewModel.cashFlowPreviewRows.enumerated()), id: \.element.id
      ) { index, row in
        if row.isIncluded {
          HStack {
            HStack(spacing: 4) {
              Text(row.csvRow.description)
              if let error = row.duplicateError {
                HoverPopoverIcon(
                  systemName: "xmark.circle.fill",
                  color: .red,
                  message: error,
                  activeRowID: $activeCFDuplicateErrorRowID,
                  rowID: row.id
                )
              }
              if let error = row.snapshotDuplicateError {
                HoverPopoverIcon(
                  systemName: "xmark.circle.fill",
                  color: .red,
                  message: error,
                  activeRowID: $activeCFSnapshotDuplicateErrorRowID,
                  rowID: row.id
                )
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
              Text(row.csvRow.amount.formatted())
                .monospacedDigit()
                .foregroundStyle(row.csvRow.amount < 0 ? .red : .primary)
              if let warning = row.amountWarning {
                HoverPopoverIcon(
                  systemName: "exclamationmark.triangle.fill",
                  color: .yellow,
                  message: warning,
                  activeRowID: $activeCFAmountWarningRowID,
                  rowID: row.id
                )
              }
            }
            .frame(width: 120, alignment: .trailing)

            Button {
              viewModel.removeCashFlowPreviewRow(at: index)
            } label: {
              Image(systemName: "minus.circle")
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 30)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)

          Divider()
        }
      }
    }
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(.separator, lineWidth: 1)
    )
  }

  func handleFileImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      startImportTask { @MainActor in
        await viewModel.loadFile(url)
      }

    case .failure(let error):
      guard !isUserCancellation(error) else { return }
      viewModel.reportFileLoadFailure()
    }
  }

  func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    let fileName = provider.suggestedName

    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) {
        url, _ in
        guard let url else {
          Task { @MainActor in viewModel.reportFileLoadFailure() }
          return
        }
        Task { @MainActor in
          startImportTask { @MainActor in
            await viewModel.loadFile(url)
          }
        }
      }
      return true
    }

    if provider.hasItemConformingToTypeIdentifier(UTType.commaSeparatedText.identifier) {
      provider.loadDataRepresentation(
        forTypeIdentifier: UTType.commaSeparatedText.identifier
      ) { data, _ in
        guard let data else {
          Task { @MainActor in
            viewModel.reportFileLoadFailure()
          }
          return
        }
        Task { @MainActor in
          startImportTask { @MainActor in
            await viewModel.loadDroppedData(data, fileName: fileName)
          }
        }
      }
      return true
    }

    return false
  }

  private func isUserCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let nsError = error as NSError
    return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
  }
}
