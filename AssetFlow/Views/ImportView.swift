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
import UniformTypeIdentifiers

/// CSV Import screen — unified import workflow for asset and cash flow CSVs.
///
/// Occupies the full content area without a list-detail split (SPEC Section 3.1).
struct ImportView: View {
  @State var viewModel: ImportViewModel
  @State private var showFileImporter = false
  @State private var showDiscardAlert = false
  @State private var newPlatformName = ""
  @State private var showNewPlatformField = false
  @State private var newCategoryName = ""
  @State private var showNewCategoryField = false
  // internal (not private) because these are used from the extension in ImportView+Previews.swift
  @State var activeCategoryWarningRowID: UUID?
  @State var activeCurrencyWarningRowID: UUID?
  @State var activeCurrencyErrorRowID: UUID?
  @State var activeDuplicateErrorRowID: UUID?
  @State var activeSnapshotDuplicateErrorRowID: UUID?
  @State var activeMarketValueWarningRowID: UUID?
  @State var activeCFDuplicateErrorRowID: UUID?
  @State var activeCFSnapshotDuplicateErrorRowID: UUID?
  @State var activeCFAmountWarningRowID: UUID?

  init(viewModel: ImportViewModel) {
    _viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        importTypeSelector
        fileSelector
        if viewModel.selectedFileName != nil || viewModel.selectedFileData != nil
          || !previewRowsEmpty || !viewModel.validationErrors.isEmpty
        {
          configurationSection
          copyForwardSection
          validationSummary
          previewTable
          importButton
        }
      }
      .padding()
    }
    .navigationTitle("Import")
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [UTType.commaSeparatedText],
      allowsMultipleSelection: false
    ) { result in
      handleFileImport(result)
    }
    .sheet(isPresented: $viewModel.showColumnMappingSheet) {
      ColumnMappingSheet(
        rawHeaders: viewModel.pendingRawHeaders,
        schema: viewModel.importType == .assets ? .asset : .cashFlow,
        sampleRows: viewModel.pendingSampleRows,
        initialMapping: viewModel.pendingPartialMapping,
        onConfirm: { mapping in
          viewModel.confirmColumnMapping(mapping)
        },
        onCancel: {
          viewModel.showColumnMappingSheet = false
        }
      )
    }
    .alert("Discard import?", isPresented: $showDiscardAlert) {
      Button("Discard", role: .destructive) {
        viewModel.reset()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The selected file has not been imported yet.")
    }
    .alert(
      "Import Error",
      isPresented: .init(
        get: { viewModel.importError != nil || viewModel.persistenceError != nil },
        set: {
          if !$0 {
            viewModel.importError = nil
            viewModel.persistenceError = nil
          }
        }
      )
    ) {
      Button("OK") {
        viewModel.importError = nil
        viewModel.persistenceError = nil
      }
    } message: {
      if let error = viewModel.importError ?? viewModel.persistenceError {
        Text(error)
      }
    }
    .onAppear {
      viewModel.refreshPickerOptions()
    }
  }

  private var previewRowsEmpty: Bool {
    viewModel.assetPreviewRows.isEmpty && viewModel.cashFlowPreviewRows.isEmpty
  }

  // MARK: - Import Type Selector

  private var importTypeSelector: some View {
    Picker("Import Type", selection: $viewModel.importType) {
      Text("Assets").tag(ImportType.assets)
      Text("Cash Flows").tag(ImportType.cashFlows)
    }
    .pickerStyle(.segmented)
    .frame(maxWidth: 300)
  }

  // MARK: - File Selector

  private var fileSelector: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("CSV File")
        .font(.headline)

      VStack(spacing: 12) {
        if let fileName = viewModel.selectedFileName {
          HStack {
            Image(systemName: "doc.text")
              .foregroundStyle(.secondary)
            Text(fileName)
              .lineLimit(1)
            Spacer()
            Button("Change") {
              showFileImporter = true
            }
          }
          .padding()
          .background(.fill.quaternary)
          .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
            Text("Drop a CSV file here or click Browse")
              .foregroundStyle(.secondary)
            Button("Browse...") {
              showFileImporter = true
            }
            .helpWhenUnlocked("Browse for a CSV file to import")
          }
          .frame(maxWidth: .infinity, minHeight: 180)
          .background(.fill.quaternary)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(
                style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
              )
              .foregroundStyle(.tertiary)
          )
          .onDrop(of: [UTType.commaSeparatedText, UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
          }
        }
      }

      expectedSchemaHint
    }
  }

  private var expectedSchemaHint: some View {
    Group {
      switch viewModel.importType {
      case .assets:
        VStack(alignment: .leading, spacing: 4) {
          Text("Expected columns:")
            .font(.caption)
            .foregroundStyle(.secondary)
          // CSV column names are intentionally non-localizable
          Text(
            verbatim:
              "Asset Name (required), Market Value (required), "
              + "Platform (optional), Currency (optional)"
          )
          .font(.caption)
          .foregroundStyle(.tertiary)
        }

      case .cashFlows:
        VStack(alignment: .leading, spacing: 4) {
          Text("Expected columns:")
            .font(.caption)
            .foregroundStyle(.secondary)
          // CSV column names are intentionally non-localizable — they must match parsing expectations
          Text(verbatim: "Description (required), Amount (required), Currency (optional)")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    }
  }

  // MARK: - Configuration Section

  private var configurationSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configuration")
        .font(.headline)

      HStack {
        // Snapshot date picker
        DatePicker(
          "Snapshot Date",
          selection: $viewModel.snapshotDate,
          in: ...Date(),
          displayedComponents: .date
        )
        .fixedSize()

        Spacer()

        if viewModel.importType == .assets {
          platformPicker
          Spacer()
          categoryPicker
          Spacer()
        }
      }
    }
  }

  private var platformPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      if showNewPlatformField {
        HStack {
          TextField("New platform name", text: $newPlatformName)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)
            .onSubmit {
              commitNewPlatform()
            }
          Button("OK") { commitNewPlatform() }
          Button("Cancel") {
            showNewPlatformField = false
            newPlatformName = ""
          }
        }
        .transition(.opacity)
      } else {
        HStack(spacing: 4) {
          Text("Platform:")
            .foregroundStyle(.secondary)
          Picker("Platform", selection: platformBinding) {
            Text("None").tag("")
            ForEach(viewModel.availablePlatforms, id: \.self) { platform in
              Text(platform).tag(platform)
            }
            Divider()
            Text("New Platform...").tag("__new__")
          }
          .labelsHidden()
          .fixedSize()

          if viewModel.hasMixedPlatforms {
            Toggle("All Rows", isOn: overrideAllBinding)
              .toggleStyle(.checkbox)
              .fixedSize()
              .disabled(viewModel.selectedPlatform == nil)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transition(.opacity)
      }
    }
    .animation(AnimationConstants.standard, value: showNewPlatformField)
  }

  private var overrideAllBinding: Binding<Bool> {
    Binding(
      get: { viewModel.platformApplyMode == .overrideAll },
      set: { viewModel.platformApplyMode = $0 ? .overrideAll : .fillEmptyOnly }
    )
  }

  private var platformBinding: Binding<String> {
    Binding(
      get: { viewModel.selectedPlatform ?? "" },
      set: { newValue in
        if newValue == "__new__" {
          showNewPlatformField = true
          newPlatformName = ""
        } else if newValue.isEmpty {
          viewModel.selectedPlatform = nil
        } else {
          viewModel.selectedPlatform = newValue
        }
      }
    )
  }

  private func commitNewPlatform() {
    let trimmed = newPlatformName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }

    // Check if it matches an existing platform (case-insensitive)
    let existing = viewModel.availablePlatforms
    if let match = existing.first(where: { $0.lowercased() == trimmed.lowercased() }) {
      viewModel.selectedPlatform = match
    } else {
      viewModel.selectedPlatform = trimmed
    }

    showNewPlatformField = false
    newPlatformName = ""
  }

  private var categoryPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      if showNewCategoryField {
        HStack {
          TextField("New category name", text: $newCategoryName)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)
            .onSubmit {
              commitNewCategory()
            }
          Button("OK") { commitNewCategory() }
          Button("Cancel") {
            showNewCategoryField = false
            newCategoryName = ""
          }
        }
        .transition(.opacity)
      } else {
        HStack(spacing: 4) {
          Text("Category:")
            .foregroundStyle(.secondary)
          Picker("Category", selection: categoryBinding) {
            Text("None").tag("")
            ForEach(viewModel.availableCategories) { category in
              Text(category.name).tag(category.id.uuidString)
            }
            Divider()
            Text("New Category...").tag("__new__")
          }
          .labelsHidden()
          .fixedSize()

          if viewModel.hasMixedCategories {
            Toggle("All Rows", isOn: categoryOverrideAllBinding)
              .toggleStyle(.checkbox)
              .fixedSize()
              .disabled(viewModel.selectedCategory == nil)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transition(.opacity)
      }
    }
    .animation(AnimationConstants.standard, value: showNewCategoryField)
  }

  private var categoryOverrideAllBinding: Binding<Bool> {
    Binding(
      get: { viewModel.categoryApplyMode == .overrideAll },
      set: { viewModel.categoryApplyMode = $0 ? .overrideAll : .fillEmptyOnly }
    )
  }

  private var categoryBinding: Binding<String> {
    Binding(
      get: { viewModel.selectedCategory?.id.uuidString ?? "" },
      set: { newValue in
        if newValue == "__new__" {
          showNewCategoryField = true
          newCategoryName = ""
        } else if newValue.isEmpty {
          viewModel.selectedCategory = nil
        } else {
          let categories = viewModel.availableCategories
          viewModel.selectedCategory = categories.first {
            $0.id.uuidString == newValue
          }
        }
      }
    )
  }

  private func commitNewCategory() {
    let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }

    do {
      let resolved = try viewModel.resolveCategory(name: trimmed)
      viewModel.refreshPickerOptions()
      viewModel.selectedCategory = resolved

      showNewCategoryField = false
      newCategoryName = ""
    } catch {
      viewModel.persistenceError = error.localizedDescription
    }
  }

  // MARK: - Copy Forward Section

  @ViewBuilder
  private var copyForwardSection: some View {
    if viewModel.importType == .assets && !viewModel.copyForwardPlatforms.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("Copy from other platforms")
          .font(.headline)

        Text(
          "Include assets from these platforms (values from most recent snapshot):"
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        Toggle("Enable copy-forward", isOn: $viewModel.copyForwardEnabled)

        if viewModel.copyForwardEnabled {
          VStack(alignment: .leading, spacing: 6) {
            ForEach($viewModel.copyForwardPlatforms) { $info in
              Toggle(isOn: $info.isSelected) {
                HStack {
                  Text(info.platformName)
                  Text(
                    "\u{2014} \(info.assetCount) assets (from \(info.sourceSnapshotDate.settingsFormatted()))"
                  )
                  .font(.callout)
                  .foregroundStyle(.secondary)
                }
              }
            }
          }
          .padding(.leading, 20)
          .transition(.opacity)
        }
      }
      .animation(AnimationConstants.standard, value: viewModel.copyForwardEnabled)
    }
  }

  // MARK: - Validation Summary

  private var validationSummary: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !viewModel.validationErrors.isEmpty {
        ForEach(
          Array(viewModel.validationErrors.enumerated()), id: \.offset
        ) { _, error in
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.red)
            VStack(alignment: .leading) {
              if error.row > 0 {
                Text("Row \(error.row)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(error.message)
                .font(.callout)
            }
          }
        }
      }

      if !viewModel.validationWarnings.isEmpty {
        ForEach(
          Array(viewModel.validationWarnings.enumerated()), id: \.offset
        ) { _, warning in
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
              if warning.row > 0 {
                Text("Row \(warning.row)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(warning.message)
                .font(.callout)
            }
          }
        }
      }
    }
  }

  // MARK: - Preview Table

  private var previewTable: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Preview")
        .font(.headline)

      switch viewModel.importType {
      case .assets:
        assetPreviewTable

      case .cashFlows:
        cashFlowPreviewTable
      }
    }
  }

  // MARK: - Import Button

  private var importButton: some View {
    HStack {
      Spacer()
      Button("Import") {
        _ = viewModel.executeImport()
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isImportDisabled)
      .helpWhenUnlocked("Import the CSV data into a snapshot")
    }
  }

}
