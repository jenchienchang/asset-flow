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

import SwiftData
import SwiftUI

/// Snapshot list view with creation workflow.
///
/// Displays all snapshots sorted by date (newest first) with totals,
/// asset counts, and platform indicators. Supports creating new snapshots
/// (empty or copy-from-latest) and deletion with confirmation.
struct SnapshotListView: View {
  @State private var viewModel: SnapshotListViewModel
  @Binding var selectedSnapshot: Snapshot?
  @Environment(\.isAppLocked) private var isAppLocked

  @Query(sort: \Snapshot.date, order: .reverse) private var snapshots: [Snapshot]

  @Binding var showNewSnapshotSheet: Bool
  @State private var snapshotToDelete: Snapshot?
  @State private var showDeleteConfirmation = false
  @State private var expandedSections: Set<SnapshotTimeBucket> = Set(SnapshotTimeBucket.allCases)

  var onNavigateToImport: (() -> Void)?
  var onBulkEntry: ((Date) -> Void)?

  init(
    modelContext: ModelContext,
    selectedSnapshot: Binding<Snapshot?>,
    showNewSnapshotSheet: Binding<Bool> = .constant(false),
    onNavigateToImport: (() -> Void)? = nil,
    onBulkEntry: ((Date) -> Void)? = nil
  ) {
    _viewModel = State(wrappedValue: SnapshotListViewModel(modelContext: modelContext))
    _selectedSnapshot = selectedSnapshot
    _showNewSnapshotSheet = showNewSnapshotSheet
    self.onNavigateToImport = onNavigateToImport
    self.onBulkEntry = onBulkEntry
  }

  var body: some View {
    Group {
      if snapshots.isEmpty {
        emptyState
          .transition(.opacity)
      } else {
        snapshotList
          .transition(.opacity)
      }
    }
    .navigationTitle("Snapshots")
    .animation(AnimationConstants.standard, value: snapshots.isEmpty)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          showNewSnapshotSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .disabled(isAppLocked)
        .helpWhenUnlocked("Create a new snapshot")
        .accessibilityIdentifier("New Snapshot Button")
      }
    }
    .onAppear {
      viewModel.loadRowData(snapshots: snapshots)
    }
    .onChange(of: snapshots) {
      viewModel.loadRowData(snapshots: snapshots)
    }
    .sheet(isPresented: $showNewSnapshotSheet) {
      NewSnapshotSheet(
        viewModel: viewModel,
        onCreate: { snapshot in
          viewModel.loadRowData()
          selectedSnapshot = snapshot
        },
        onBulkEntry: { date in
          onBulkEntry?(date)
        }
      )
    }
    .confirmationDialog(
      "Delete Snapshot",
      isPresented: $showDeleteConfirmation,
      presenting: snapshotToDelete
    ) { snapshot in
      Button("Delete", role: .destructive) {
        viewModel.deleteSnapshot(snapshot)
        if selectedSnapshot?.id == snapshot.id {
          selectedSnapshot = nil
        }
        viewModel.loadRowData()
      }
      Button("Cancel", role: .cancel) {}
    } message: { snapshot in
      let data = viewModel.confirmationData(for: snapshot)
      let dateStr = data.date.settingsFormatted()
      let assetCount = data.assetCount
      let cfCount = data.cashFlowCount
      Text(
        "Delete snapshot from \(dateStr)? This will remove all \(assetCount) asset values and \(cfCount) cash flow operations. This action cannot be undone."
      )
    }
  }

  // MARK: - Snapshot List

  private var groupedSnapshots: [(bucket: SnapshotTimeBucket, snapshots: [Snapshot])] {
    let grouped = Dictionary(grouping: snapshots) { SnapshotTimeBucket.bucket(for: $0.date) }
    return SnapshotTimeBucket.allCases.compactMap { bucket in
      guard let items = grouped[bucket], !items.isEmpty else { return nil }
      return (bucket: bucket, snapshots: items)
    }
  }

  private func sectionBinding(for bucket: SnapshotTimeBucket) -> Binding<Bool> {
    Binding(
      get: { expandedSections.contains(bucket) },
      set: { isExpanded in
        if isExpanded { expandedSections.insert(bucket) } else { expandedSections.remove(bucket) }
      }
    )
  }

  private var snapshotList: some View {
    List(selection: $selectedSnapshot) {
      ForEach(groupedSnapshots, id: \.bucket) { group in
        Section(isExpanded: sectionBinding(for: group.bucket)) {
          ForEach(group.snapshots) { snapshot in
            snapshotRow(snapshot)
              .tag(snapshot)
          }
        } header: {
          Text(group.bucket.localizedName)
        }
      }
    }
    .onDeleteCommand {
      deleteSelectedSnapshot()
    }
    .accessibilityIdentifier("Snapshot List")
  }

  private func deleteSelectedSnapshot() {
    guard let snapshot = selectedSnapshot else { return }
    snapshotToDelete = snapshot
    showDeleteConfirmation = true
  }

  private func snapshotRow(_ snapshot: Snapshot) -> some View {
    let rowData = viewModel.rowDataMap[snapshot.id]

    return HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(snapshot.date.settingsFormatted())
          .font(.body)

        if let rowData = rowData {
          platformBadges(rowData: rowData)
        }
      }

      Spacer()

      HStack(spacing: 12) {
        if let rowData = rowData {
          if rowData.hasZeroValueAssets {
            HoverWarningIcon(
              message: String(
                localized: "This snapshot contains assets with a value of 0.",
                table: "Snapshot"))
          }

          if rowData.conversionStatus.isComplete {
            Text(
              rowData.totalValue.formatted(
                currency: SettingsService.shared.mainCurrency)
            )
            .font(.body)
            .monospacedDigit()
          } else {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
              .helpWhenUnlocked(
                rowData.conversionStatus.unavailableMessage
                  ?? "Conversion is incomplete for this snapshot.")
            VStack(alignment: .trailing, spacing: 1) {
              ForEach(
                rowData.nativeCurrencyTotals.sorted(by: { $0.key < $1.key }),
                id: \.key
              ) { code, value in
                Text(value.formatted(currency: code))
                  .font(.caption)
                  .monospacedDigit()
              }
            }
          }

          Text("\(rowData.assetCount)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, ChartConstants.badgePaddingH)
            .padding(.vertical, ChartConstants.badgePaddingV)
            .background(.quaternary)
            .clipShape(Capsule())
            .accessibilityLabel("\(rowData.assetCount) assets")
        }
      }
    }
    .contextMenu {
      Button("Delete", role: .destructive) {
        snapshotToDelete = snapshot
        showDeleteConfirmation = true
      }
    }
  }

  @ViewBuilder
  private func platformBadges(
    rowData: SnapshotRowData
  ) -> some View {
    let maxVisible = 3
    let allPlatforms = rowData.platforms
    let overflow = max(0, allPlatforms.count - maxVisible)

    HStack(spacing: 4) {
      ForEach(allPlatforms.prefix(maxVisible), id: \.self) { platform in
        Text(platform)
          .font(.caption2)
          .padding(.horizontal, ChartConstants.compactBadgePaddingH)
          .padding(.vertical, ChartConstants.compactBadgePaddingV)
          .background(.quaternary)
          .clipShape(Capsule())
      }

      if overflow > 0 {
        Text("+\(overflow)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No Snapshots", systemImage: "calendar")
    } description: {
      Text("No snapshots yet. Create your first snapshot or import a CSV to get started.")
    } actions: {
      Button("New Snapshot") {
        showNewSnapshotSheet = true
      }
      Button("Import CSV") {
        onNavigateToImport?()
      }
    }
  }

}

// MARK: - New Snapshot Sheet

enum SnapshotCreationMode: String, CaseIterable {
  case emptySnapshot
  case bulkEntry
}

struct NewSnapshotSheet: View {
  var viewModel: SnapshotListViewModel?
  var onCreate: ((Snapshot) -> Void)?
  let onBulkEntry: (Date) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \Snapshot.date) private var allSnapshots: [Snapshot]

  @FocusState private var focusedField: Field?
  enum Field { case date }

  @State private var snapshotDate = Date()
  @State private var creationMode: SnapshotCreationMode = .bulkEntry
  @State private var showError = false
  @State private var errorMessage = ""

  private var hasDateConflict: Bool {
    allSnapshots.contains(where: {
      Calendar.current.isDate($0.date, inSameDayAs: snapshotDate)
    })
  }

  var body: some View {
    NavigationStack {
      Form {
        DatePicker(
          "Snapshot Date",
          selection: $snapshotDate,
          in: ...Date(),
          displayedComponents: .date
        )
        .focused($focusedField, equals: .date)
        .accessibilityIdentifier("Snapshot Date Picker")

        if hasDateConflict {
          Label(
            "A snapshot already exists for \(snapshotDate.settingsFormatted()). Go to the Snapshots screen to view and edit it.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }

        Picker("Creation Mode", selection: $creationMode) {
          Text("Empty Snapshot").tag(SnapshotCreationMode.emptySnapshot)
          Text("Bulk Entry").tag(SnapshotCreationMode.bulkEntry)
        }
        .pickerStyle(.radioGroup)
      }
      .formStyle(.grouped)
      .navigationTitle("New Snapshot")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            createSnapshot()
          }
          .disabled(hasDateConflict)
        }
      }
    }
    .frame(minWidth: 350, minHeight: 220)
    .onAppear { focusedField = .date }
    .alert("Error", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
  }

  private func createSnapshot() {
    if creationMode == .bulkEntry {
      onBulkEntry(snapshotDate)
      dismiss()
      return
    }
    do {
      let snapshot: Snapshot
      if let viewModel {
        snapshot = try viewModel.createSnapshot(
          date: snapshotDate, copyFromLatest: false)
      } else {
        // Sidebar context: create empty snapshot directly via modelContext
        let normalizedDate = Calendar.current.startOfDay(for: snapshotDate)
        snapshot = Snapshot(date: normalizedDate)
        modelContext.insert(snapshot)
      }
      onCreate?(snapshot)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }
}

// MARK: - Previews

#Preview("Snapshot List") {
  NavigationStack {
    SnapshotListView(
      modelContext: PreviewContainer.container.mainContext,
      selectedSnapshot: .constant(nil)
    )
  }
}
