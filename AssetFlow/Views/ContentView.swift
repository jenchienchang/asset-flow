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

// MARK: - Focused Value Keys

struct NewSnapshotActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

struct ImportCSVActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var newSnapshotAction: (() -> Void)? {
    get { self[NewSnapshotActionKey.self] }
    set { self[NewSnapshotActionKey.self] = newValue }
  }

  var importCSVAction: (() -> Void)? {
    get { self[ImportCSVActionKey.self] }
    set { self[ImportCSVActionKey.self] = newValue }
  }
}

// MARK: - SidebarSection

/// Sidebar navigation sections for the main app window.
enum SidebarSection: String, CaseIterable, Identifiable {
  case dashboard
  case snapshots
  case assets
  case categories
  case platforms
  case rebalancing
  case bulkEntry
  case importCSV

  var id: String { rawValue }

  var label: String {
    switch self {
    case .dashboard: return String(localized: "Dashboard")
    case .snapshots: return String(localized: "Snapshots")
    case .assets: return String(localized: "Assets")
    case .categories: return String(localized: "Categories")
    case .platforms: return String(localized: "Platforms")
    case .rebalancing: return String(localized: "Rebalancing")
    case .bulkEntry: return String(localized: "New Snapshot")
    case .importCSV: return String(localized: "Import CSV")
    }
  }

  var systemImage: String {
    switch self {
    case .dashboard: return "chart.bar"
    case .snapshots: return "calendar"
    case .assets: return "tray"
    case .categories: return "folder"
    case .platforms: return "building.columns"
    case .rebalancing: return "chart.bar.doc.horizontal"
    case .bulkEntry: return "square.and.pencil"
    case .importCSV: return "square.and.arrow.down"
    }
  }
}

// MARK: - ContentView

/// Root navigation shell with sidebar and detail pane.
///
/// Provides an 8-section sidebar (Dashboard, Snapshots, Assets, Categories,
/// Platforms, Rebalancing, New Snapshot, Import CSV) with list-detail splits for
/// Snapshots, Assets, and Categories. Manages import discard confirmation and
/// post-import navigation to the created snapshot.
struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.isAppLocked) private var isAppLocked

  @State private var selectedSection: SidebarSection? = .dashboard
  @State private var selectedSnapshot: Snapshot?
  @State private var selectedAsset: Asset?
  @State private var selectedCategory: Category?
  @State private var selectedPlatform: String?

  @State private var showNewSnapshotSheet = false
  @State private var importViewModel: ImportViewModel?
  @State private var bulkEntryViewModel: BulkEntryViewModel?
  @State private var showBulkEntrySheet = false
  @State private var pendingSection: SidebarSection?
  @State private var pendingIsGoBack = false
  @State private var showDiscardConfirmation = false
  @State private var persistenceError: String?

  // Navigation history
  @State private var sectionHistory: [SidebarSection] = [.dashboard]
  @State private var historyIndex: Int = 0
  @State private var isNavigatingHistory = false

  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      sidebar
        .navigationTitle("AssetFlow")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        .toolbar(removing: .sidebarToggle)
    } detail: {
      detailPane
    }
    .frame(minWidth: 900, minHeight: 600)
    .focusedValue(\.newSnapshotAction) {
      pushHistory(.snapshots)
      showNewSnapshotSheet = true
    }
    .focusedValue(\.importCSVAction) { navigateToImport() }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button(action: goBack) {
          Image(systemName: "chevron.left")
        }
        .disabled(!canGoBack || isAppLocked)
        .helpWhenUnlocked("Go back")
        .accessibilityIdentifier("Go Back Button")
      }
      ToolbarItem(placement: .navigation) {
        Button(action: goForward) {
          Image(systemName: "chevron.right")
        }
        .disabled(!canGoForward || isAppLocked)
        .helpWhenUnlocked("Go forward")
        .accessibilityIdentifier("Go Forward Button")
      }
    }
    .confirmationDialog(
      "Discard unsaved changes?",
      isPresented: $showDiscardConfirmation
    ) {
      Button("Discard", role: .destructive) {
        if selectedSection == .importCSV {
          importViewModel?.reset()
        } else if selectedSection == .bulkEntry {
          bulkEntryViewModel = nil
        }
        if pendingIsGoBack {
          performGoBack()
        } else if let pending = pendingSection {
          pushHistory(pending)
        }
        pendingSection = nil
        pendingIsGoBack = false
      }
      Button("Cancel", role: .cancel) {
        pendingSection = nil
        pendingIsGoBack = false
      }
    } message: {
      if selectedSection == .bulkEntry {
        Text("The entered values have not been saved yet.")
      } else {
        Text("The selected file has not been imported yet.")
      }
    }
    .sheet(isPresented: $showBulkEntrySheet) {
      NewSnapshotSheet(
        viewModel: SnapshotListViewModel(modelContext: modelContext),
        onCreate: { snapshot in
          pushHistory(.snapshots)
          selectedSnapshot = snapshot
        },
        onBulkEntry: { date in
          bulkEntryViewModel = BulkEntryViewModel(
            modelContext: modelContext, date: date)
          pushHistory(.bulkEntry)
        }
      )
    }
    .onChange(of: importViewModel?.importedSnapshot?.id) { _, newValue in
      if newValue != nil, let snapshot = importViewModel?.importedSnapshot {
        pushHistory(.snapshots)
        selectedSnapshot = snapshot
        importViewModel?.importedSnapshot = nil
        importViewModel?.reset()
      }
    }
    .onAppear {
      if importViewModel == nil {
        importViewModel = ImportViewModel(modelContext: modelContext)
      }
    }
    .task {
      await CurrencyService.shared.loadFromAPI()
      let service = ExchangeRateService()
      do {
        let snapshots = try fetchModels(
          FetchDescriptor<Snapshot>(),
          from: ModelContextFetcher(modelContext: modelContext),
          operation: "load snapshots for exchange rates")
        _ = await service.fetchMissingRates(
          snapshots: snapshots,
          displayCurrency: SettingsService.shared.mainCurrency,
          modelContext: modelContext
        )
      } catch {
        persistenceError = error.localizedDescription
      }
    }
    .alert(
      "Data Error",
      isPresented: .init(
        get: { persistenceError != nil },
        set: { if !$0 { persistenceError = nil } }
      )
    ) {
      Button("OK") { persistenceError = nil }
    } message: {
      if let persistenceError {
        Text(persistenceError)
      }
    }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    List(selection: sidebarBinding) {
      Section("Overview") {
        sidebarLabel(for: .dashboard)
      }
      Section("Portfolio") {
        ForEach(
          [SidebarSection.snapshots, .assets, .categories, .platforms], id: \.self
        ) { section in
          sidebarLabel(for: section)
        }
      }
      Section("Tools") {
        ForEach([SidebarSection.rebalancing, .bulkEntry, .importCSV], id: \.self) { section in
          sidebarLabel(for: section)
        }
      }
    }
    .legacySidebarBackground()
    .tint(Color.accentColor.opacity(0.9))
  }

  private func sidebarLabel(for section: SidebarSection) -> some View {
    Label {
      Text(section.label)
    } icon: {
      Image(systemName: section.systemImage)
        .opacity(0.9)
    }
    .tag(section)
  }

  /// Custom binding that intercepts sidebar selection changes to check for unsaved import data.
  private var sidebarBinding: Binding<SidebarSection?> {
    Binding(
      get: { selectedSection },
      set: { newSection in
        guard let newSection, newSection != selectedSection else { return }

        // Check if navigating away from section with unsaved changes
        if selectedSection == .importCSV,
          importViewModel?.hasUnsavedChanges == true
        {
          pendingSection = newSection
          showDiscardConfirmation = true
        } else if selectedSection == .bulkEntry,
          bulkEntryViewModel?.hasUnsavedChanges == true
        {
          pendingSection = newSection
          showDiscardConfirmation = true
        } else if newSection == .bulkEntry {
          // Bulk entry: show date picker sheet instead of navigating
          showBulkEntrySheet = true
        } else {
          if selectedSection == .bulkEntry {
            bulkEntryViewModel = nil
          }
          pushHistory(newSection)
        }
      }
    )
  }

  // MARK: - Detail Pane

  @ViewBuilder
  private var detailPane: some View {
    switch selectedSection {
    case .dashboard:
      DashboardView(
        modelContext: modelContext,
        onNavigateToSnapshots: { pushHistory(.snapshots) },
        onNavigateToImport: { navigateToImport() },
        onSelectSnapshot: { date in
          navigateToSnapshotByDate(date)
        },
        onNavigateToCategory: { name in
          navigateToCategoryByName(name)
        }
      )

    case .snapshots:
      GeometryReader { geometry in
        HStack(spacing: 0) {
          SnapshotListView(
            modelContext: modelContext,
            selectedSnapshot: $selectedSnapshot,
            showNewSnapshotSheet: $showNewSnapshotSheet,
            onNavigateToImport: { navigateToImport() },
            onBulkEntry: { date in
              bulkEntryViewModel = BulkEntryViewModel(modelContext: modelContext, date: date)
              pushHistory(.bulkEntry)
            }
          )
          .frame(width: max(250, geometry.size.width * 0.4))

          Divider()

          if let snapshot = selectedSnapshot {
            SnapshotDetailView(
              snapshot: snapshot,
              modelContext: modelContext,
              onDelete: {
                selectedSnapshot = nil
              }
            )
            .id(snapshot.id)
            .frame(maxWidth: .infinity)
          } else {
            placeholderView("Select a snapshot", systemImage: "calendar")
          }
        }
      }

    case .assets:
      HStack(spacing: 0) {
        AssetListView(
          modelContext: modelContext,
          selectedAsset: $selectedAsset
        )
        .frame(minWidth: 250, idealWidth: 300)

        Divider()

        if let asset = selectedAsset {
          AssetDetailView(
            asset: asset,
            modelContext: modelContext,
            onDelete: {
              selectedAsset = nil
            }
          )
          .id(asset.id)
          .frame(maxWidth: .infinity)
        } else {
          placeholderView("Select an asset", systemImage: "tray")
        }
      }

    case .categories:
      GeometryReader { geometry in
        HStack(spacing: 0) {
          CategoryListView(
            modelContext: modelContext,
            selectedCategory: $selectedCategory
          )
          .frame(width: max(250, geometry.size.width * 0.35))

          Divider()

          if let category = selectedCategory {
            CategoryDetailView(
              category: category,
              modelContext: modelContext,
              onDelete: {
                selectedCategory = nil
              }
            )
            .id(category.id)
            .frame(maxWidth: .infinity)
          } else {
            placeholderView("Select a category", systemImage: "folder")
          }
        }
      }

    case .platforms:
      GeometryReader { geometry in
        HStack(spacing: 0) {
          PlatformListView(modelContext: modelContext, selectedPlatform: $selectedPlatform)
            .frame(width: max(250, geometry.size.width * 0.35))

          Divider()

          if let platform = selectedPlatform {
            PlatformDetailView(
              platformName: platform,
              modelContext: modelContext,
              onRename: { selectedPlatform = $0 }
            )
            .id(platform)
            .frame(maxWidth: .infinity)
          } else {
            placeholderView("Select a platform", systemImage: "building.columns")
          }
        }
      }

    case .rebalancing:
      RebalancingView(modelContext: modelContext)

    case .importCSV:
      if let viewModel = importViewModel {
        ImportView(viewModel: viewModel)
      } else {
        ProgressView()
      }

    case .bulkEntry:
      if let viewModel = bulkEntryViewModel {
        BulkEntryView(viewModel: viewModel) { savedSnapshot in
          pushHistory(.snapshots)
          selectedSnapshot = savedSnapshot
          bulkEntryViewModel = nil
        }
      } else {
        // No ViewModel yet — user should not have landed here without one.
        // Redirect to dashboard.
        ContentUnavailableView(
          "New Snapshot",
          systemImage: "square.and.pencil",
          description: Text("Use the sidebar to create a new snapshot.")
        )
        .onAppear {
          goBack()
        }
      }

    case nil:
      placeholderView("Select a section", systemImage: "sidebar.left")
    }
  }

  // MARK: - Helpers

  private func placeholderView(_ title: LocalizedStringKey, systemImage: String) -> some View {
    ContentUnavailableView(title, systemImage: systemImage)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Navigates to the import section, checking for unsaved changes if already there.
  private func navigateToImport() {
    // If already on import with unsaved changes, offer to discard and restart
    if selectedSection == .importCSV,
      importViewModel?.hasUnsavedChanges == true
    {
      pendingSection = .importCSV
      showDiscardConfirmation = true
      return
    }

    // If already on import without unsaved changes, nothing to do
    if selectedSection == .importCSV { return }

    // Navigate to import
    pushHistory(.importCSV)
  }

  /// Navigates to a category by looking up its name.
  /// Guards against "Uncategorized" which is not a real Category.
  private func navigateToCategoryByName(_ name: String) {
    guard name != "Uncategorized" else { return }

    do {
      let allCategories = try fetchModels(
        FetchDescriptor<Category>(),
        from: ModelContextFetcher(modelContext: modelContext),
        operation: "navigate to category")
      if let match = allCategories.first(where: {
        $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
      }) {
        pushHistory(.categories)
        selectedCategory = match
      }
    } catch {
      persistenceError = error.localizedDescription
    }
  }

  /// Navigates to a snapshot by looking up its date.
  private func navigateToSnapshotByDate(_ date: Date) {
    let targetDate = Calendar.current.startOfDay(for: date)
    var descriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date == targetDate }
    )
    descriptor.fetchLimit = 1
    do {
      if let match = try fetchModels(
        descriptor,
        from: ModelContextFetcher(modelContext: modelContext),
        operation: "navigate to snapshot"
      ).first {
        pushHistory(.snapshots)
        selectedSnapshot = match
      }
    } catch {
      persistenceError = error.localizedDescription
    }
  }

  // MARK: - Navigation History

  private var canGoBack: Bool { historyIndex > 0 }
  private var canGoForward: Bool { historyIndex < sectionHistory.count - 1 }

  private func goBack() {
    guard canGoBack else { return }

    // Check for unsaved changes before navigating back
    if selectedSection == .bulkEntry,
      bulkEntryViewModel?.hasUnsavedChanges == true
    {
      pendingSection = sectionHistory[historyIndex - 1]
      pendingIsGoBack = true
      showDiscardConfirmation = true
      return
    }
    if selectedSection == .importCSV,
      importViewModel?.hasUnsavedChanges == true
    {
      pendingSection = sectionHistory[historyIndex - 1]
      pendingIsGoBack = true
      showDiscardConfirmation = true
      return
    }

    performGoBack()
  }

  private func performGoBack() {
    guard canGoBack else { return }
    if selectedSection == .bulkEntry {
      bulkEntryViewModel = nil
      // Truncate forward history so goForward() can't navigate back
      // to .bulkEntry with a nil ViewModel.
      sectionHistory = Array(sectionHistory.prefix(historyIndex + 1))
    }
    isNavigatingHistory = true
    historyIndex -= 1
    selectedSection = sectionHistory[historyIndex]
    isNavigatingHistory = false
  }

  private func goForward() {
    guard canGoForward else { return }
    isNavigatingHistory = true
    historyIndex += 1
    selectedSection = sectionHistory[historyIndex]
    isNavigatingHistory = false
  }

  private func pushHistory(_ section: SidebarSection) {
    guard !isNavigatingHistory else {
      selectedSection = section
      return
    }
    // Don't push if same as current
    guard section != selectedSection else {
      selectedSection = section
      return
    }
    // Truncate forward history
    if historyIndex < sectionHistory.count - 1 {
      sectionHistory = Array(sectionHistory.prefix(historyIndex + 1))
    }
    sectionHistory.append(section)
    historyIndex = sectionHistory.count - 1
    selectedSection = section
  }
}

/// Shared full-screen state for a failed SwiftData read.
struct DataLoadErrorView: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Unable to load data", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("Retry", action: retry)
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Legacy Sidebar Background

extension View {
  /// Brightened flat background for macOS 15; macOS 26+ uses Liquid Glass.
  @ViewBuilder
  fileprivate func legacySidebarBackground() -> some View {
    if #unavailable(macOS 26) {
      self
        .scrollContentBackground(.hidden)
        .background {
          Color(nsColor: .windowBackgroundColor)
            .brightness(0.03)
            .ignoresSafeArea()
        }
    } else {
      self
    }
  }
}
