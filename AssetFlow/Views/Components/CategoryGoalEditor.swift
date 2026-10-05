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

import SwiftUI

/// Shared category goal fields. Currency changes alter denomination, not the entered amount.
struct CategoryGoalEditor: View {
  @Binding var minimumEnabled: Bool
  @Binding var amountText: String
  @Binding var currency: String

  var onSubmit: () -> Void = {}

  var body: some View {
    HStack {
      Toggle("Minimum balance", isOn: $minimumEnabled)
      GoalHelpButton(title: "Minimum balance") {
        Text("Keep at least this amount. The minimum takes priority over percentage targets.")
        Text(
          "Changing the currency changes the meaning of the entered amount; it does not convert it."
        )
      }
    }
    if minimumEnabled {
      amountField
      currencyPicker
    }
  }

  private var amountField: some View {
    TextField("Minimum balance amount", text: $amountText)
      .onSubmit(onSubmit)
      .accessibilityIdentifier("Minimum Balance Field")
  }

  private var currencyPicker: some View {
    Picker("Minimum balance currency", selection: $currency) {
      if CurrencyService.shared.currency(for: currency) == nil {
        Text(currency.uppercased()).tag(currency)
      }
      ForEach(CurrencyService.shared.currencies) { entry in
        Text(entry.displayName).tag(entry.code.uppercased())
      }
    }
    .accessibilityIdentifier("Minimum Balance Currency Picker")
  }
}

/// Keyboard-accessible contextual help that closes when the app locks.
struct GoalHelpButton<Content: View>: View {
  let title: LocalizedStringKey
  var showsTitle = true
  var fitsContent = false
  var systemImage = "info.circle"
  var symbolColor: Color?
  @ViewBuilder var content: () -> Content
  @Environment(\.isAppLocked) private var isAppLocked
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: systemImage)
        .foregroundStyle(symbolColor ?? .primary)
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(title)
    .helpWhenUnlocked(title)
    .disabled(isAppLocked)
    .popover(isPresented: $isPresented) {
      if !isAppLocked {
        VStack(alignment: .leading, spacing: 8) {
          if showsTitle { Text(title).font(.headline) }
          content()
        }
        .font(.callout)
        .lineLimit(nil)
        .padding(16)
        .frame(width: fitsContent ? nil : 360, alignment: .leading)
        .fixedSize(horizontal: fitsContent, vertical: true)
      }
    }
    .onChange(of: isAppLocked) { if isAppLocked { isPresented = false } }
  }
}
