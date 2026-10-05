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

/// Category list view with add sheet and target allocation warning.
///
/// Displays all categories with their target allocation, current allocation,
/// current value, and asset count. Supports adding and deleting categories.
struct CategoryListView: View {
  @State private var viewModel: CategoryListViewModel
  @Binding var selectedCategory: Category?
  @Query private var categories: [Category]
  @Query private var snapshots: [Snapshot]
  @Environment(\.isAppLocked) private var isAppLocked

  @State private var showAddSheet = false
  @State private var showDeleteError = false
  @State private var deleteErrorMessage = ""

  init(modelContext: ModelContext, selectedCategory: Binding<Category?>) {
    _viewModel = State(wrappedValue: CategoryListViewModel(modelContext: modelContext))
    _selectedCategory = selectedCategory
  }

  var body: some View {
    VStack(spacing: 0) {
      if case .failed(let message) = viewModel.loadState {
        DataLoadErrorView(message: message) { viewModel.loadCategories() }
      } else {
        if let warning = viewModel.targetAllocationSumWarning {
          warningBanner(warning)
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        if viewModel.categoryRows.contains(where: \.hasWarning) {
          deviationInfoBanner
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        if let message = viewModel.goalAssessment.goalConversion.unavailableMessage {
          warningBanner(message)
        }
        if let message = CategoryGoalPresentation.diagnostic(
          viewModel.goalAssessment.plan, currency: SettingsService.shared.mainCurrency),
          viewModel.goalAssessment.plan?.status != .noGoals
        {
          warningBanner(message)
        }
        if let message = viewModel.conversionStatus.unavailableMessage {
          warningBanner(message)
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        if viewModel.categoryRows.isEmpty {
          emptyState
        } else {
          categoryList
        }
      }
    }
    .navigationTitle("Categories")
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          showAddSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .disabled(isAppLocked)
        .helpWhenUnlocked("Create a new category")
        .accessibilityIdentifier("Add Category Button")
      }
    }
    .refreshOnStoreChanges { viewModel.requestRefresh() }
    .onAppear {
      viewModel.loadCategories()
    }
    .onChange(of: queryRevision) {
      withAnimation(AnimationConstants.standard) {
        viewModel.requestRefresh()
      }
      selectedCategory = ModelSelectionResolver.resolve(
        selectedCategory, among: categories, id: \.id)
    }
    .sheet(isPresented: $showAddSheet) {
      AddCategorySheet { name, targetAllocation, minimum, currency in
        try viewModel.createCategory(
          name: name, targetAllocation: targetAllocation, minimumBalance: minimum,
          minimumCurrency: currency)
        viewModel.loadCategories()
      }
    }
    .alert("Cannot Delete Category", isPresented: $showDeleteError) {
      Button("OK") {}
    } message: {
      Text(deleteErrorMessage)
    }
  }

  private var queryRevision: ModelQueryRevision {
    ModelQueryRevision(snapshots: snapshots, categories: categories)
  }

  // MARK: - Warning Banner

  private func warningBanner(_ warning: String) -> some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(warning)
        .font(.caption)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.yellow.opacity(0.15))
  }

  private var deviationInfoBanner: some View {
    HStack {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(.blue)
      Text(
        // swiftlint:disable:next line_length
        "Categories marked with ⚠ have a minimum balance shortfall or differ from their effective target by more than 5 percentage points."
      )
      .font(.caption)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.blue.opacity(0.08))
  }

  // MARK: - Category List

  private var categoryList: some View {
    List(selection: $selectedCategory) {
      ForEach(viewModel.categoryRows) { rowData in
        categoryRow(rowData)
          .tag(rowData.category)
      }
      .onMove { source, destination in
        withAnimation(AnimationConstants.list) {
          viewModel.moveCategories(from: source, to: destination)
        }
      }
    }
    .onDeleteCommand {
      deleteSelectedCategory()
    }
    .accessibilityIdentifier("Category List")
  }

  private func deleteSelectedCategory() {
    guard let category = selectedCategory else { return }
    deleteCategory(category)
  }

  private func categoryRow(_ rowData: CategoryRowData) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(rowData.category.name)
          .font(.body)

        if let target = rowData.targetAllocation {
          Text("Pool target: \(target.formattedPercentage())")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if rowData.category.minimumBalanceAmount == nil {
          Text("No target")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let amount = rowData.category.minimumBalanceAmount,
          let currency = rowData.category.minimumBalanceCurrency
        {
          Text("Minimum: \(CategoryGoalPresentation.amount(amount, currency: currency))")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(
            CategoryGoalPresentation.minimumStatus(
              rowData.minimumStatus, currency: SettingsService.shared.mainCurrency)
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }

      Spacer()

      HStack(spacing: 12) {
        if rowData.hasWarning {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.caption)
            .helpWhenUnlocked(rowData.warningMessage)
            .accessibilityLabel(rowData.warningMessage)
        }

        VStack(alignment: .trailing, spacing: 2) {
          Text("Current: \(rowData.currentAllocation?.formattedPercentage() ?? "—")")
            .font(.body)
            .monospacedDigit()
          if rowData.category.targetAllocationPercentage != nil
            || rowData.category.minimumBalanceAmount != nil
          {
            Text(
              "Effective target: \(rowData.effectiveTargetAllocation?.formattedPercentage() ?? "—")"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .helpWhenUnlocked(
              "Effective targets are shares of the whole portfolio. Minimum-only categories retain any balance above their minimum."
            )
          }
          if viewModel.conversionStatus.isComplete {
            Text(rowData.currentValue.formatted(currency: SettingsService.shared.mainCurrency))
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } else {
            Text("—")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Text("\(rowData.assetCount)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, ChartConstants.badgePaddingH)
          .padding(.vertical, ChartConstants.badgePaddingV)
          .background(.quaternary)
          .clipShape(Capsule())
      }
    }
    .contextMenu {
      if (rowData.category.assets ?? []).isEmpty {
        Button("Delete", role: .destructive) {
          deleteCategory(rowData.category)
        }
      }
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No Categories", systemImage: "folder")
    } description: {
      Text(
        "No categories yet. Create categories to organize your assets and set target allocations."
      )
    } actions: {
      Button("Create Category") {
        showAddSheet = true
      }
      .buttonStyle(.borderedProminent)
    }
  }

  // MARK: - Actions

  private func deleteCategory(_ category: Category) {
    do {
      try viewModel.deleteCategory(category)
      if selectedCategory?.id == category.id {
        selectedCategory = nil
      }
      withAnimation(AnimationConstants.standard) {
        viewModel.loadCategories()
      }
    } catch {
      deleteErrorMessage = error.localizedDescription
      showDeleteError = true
    }
  }
}

// MARK: - Add Category Sheet

private struct AddCategorySheet: View {
  let onCreate: (String, Decimal?, Decimal?, String?) throws -> Void

  @Environment(\.dismiss) private var dismiss
  @FocusState private var focusedField: Field?
  enum Field { case name, targetAllocation }

  @State private var name = ""
  @State private var targetAllocationText = ""
  @State private var minimumEnabled = false
  @State private var minimumBalanceText = ""
  @State private var minimumCurrency = SettingsService.shared.mainCurrency
  @State private var showError = false
  @State private var errorMessage = ""

  var body: some View {
    NavigationStack {
      Form {
        TextField("Category Name", text: $name)
          .focused($focusedField, equals: .name)
          .accessibilityIdentifier("Category Name Field")

        HStack {
          TextField("Allocation target (%)", text: $targetAllocationText)
            .focused($focusedField, equals: .targetAllocation)
            .accessibilityIdentifier("Target Allocation Field")
          GoalHelpButton(title: "Allocation target (%)") {
            Text("Optional. Enter a value between 0 and 100.")
            Text(
              "Percentage targets apply to the available allocation pool after protected balances are reserved."
            )
          }
        }
        CategoryGoalEditor(
          minimumEnabled: $minimumEnabled, amountText: $minimumBalanceText,
          currency: $minimumCurrency, onSubmit: createCategory)
      }
      .formStyle(.grouped)
      .navigationTitle("New Category")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            createCategory()
          }
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .frame(minWidth: 420, minHeight: 420)
    .onAppear { focusedField = .name }
    .alert("Error", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
  }

  private func createCategory() {
    do {
      let target = try CategoryGoalValidator.parse(targetAllocationText)
      let minimum = minimumEnabled ? try CategoryGoalValidator.parse(minimumBalanceText) : nil
      if minimumEnabled && minimum == nil { throw CategoryGoalValidationError.minimum }
      try onCreate(name, target, minimum, minimumEnabled ? minimumCurrency : nil)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }
}

// MARK: - Previews

#Preview("Category List") {
  NavigationStack {
    CategoryListView(
      modelContext: PreviewContainer.container.mainContext,
      selectedCategory: .constant(nil)
    )
  }
}
