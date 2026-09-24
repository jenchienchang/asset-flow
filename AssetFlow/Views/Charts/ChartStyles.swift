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

import AppKit
import Charts
import SwiftUI

/// Shared chart layout constants and color palette.
enum ChartConstants {
  /// Standard chart height for detail views.
  static let standardChartHeight: CGFloat = 250

  /// Compact chart height for dashboard cards.
  static let dashboardChartHeight: CGFloat = 200

  /// Color palette for multi-category charts using distinct SwiftUI standard
  /// colors (excluding .gray for Uncategorized, .black/.white for visibility,
  /// and .pink which is too similar to .red in dark mode).
  /// Ordered so each successive color fills the largest perceptual gap while
  /// maintaining visual comfort — high-intensity colors (red) are deferred so
  /// small category counts produce harmonious charts.
  static let categoryColors: [Color] = [
    .blue, .green, .orange, .purple, .red,
    .cyan, .yellow, .indigo, .brown,
    .teal, .mint,
  ]

  /// Standard card corner radius for dashboard cards.
  static let cardCornerRadius: CGFloat = 12

  /// Compact badge horizontal padding (for platform badges).
  static let compactBadgePaddingH: CGFloat = 5

  /// Compact badge vertical padding (for platform badges).
  static let compactBadgePaddingV: CGFloat = 2

  /// Standard badge horizontal padding (for asset count badges).
  static let badgePaddingH: CGFloat = 6

  /// Standard badge vertical padding (for asset count badges).
  static let badgePaddingV: CGFloat = 2

  /// Returns a color for a category at the given index. Uses the curated palette
  /// for the first 11 indices, then generates distinct colors via golden angle
  /// hue distribution for any index beyond that.
  static func color(forIndex index: Int) -> Color {
    if index < categoryColors.count {
      return categoryColors[index]
    }
    // Golden angle (~137.5°) produces well-separated hues for any count.
    let hue = Double(index) * 0.381966011250105  // (√5 - 1) / 2
    return Color(hue: hue.truncatingRemainder(dividingBy: 1.0), saturation: 0.65, brightness: 0.8)
  }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content
        .glassEffect(in: RoundedRectangle(cornerRadius: ChartConstants.cardCornerRadius))
    } else {
      content
        .background(reduceTransparency ? .regularMaterial : .ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ChartConstants.cardCornerRadius))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 4)
        .overlay(
          RoundedRectangle(cornerRadius: ChartConstants.cardCornerRadius)
            .stroke(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .overlay(
          RoundedRectangle(cornerRadius: ChartConstants.cardCornerRadius)
            .stroke(.white.opacity(0.05), lineWidth: 1)
            .blendMode(.plusLighter)
        )
    }
  }
}

extension View {
  /// Applies the glass card treatment: material background, rounded corners, shadows, and border.
  func glassCard() -> some View {
    modifier(GlassCardModifier())
  }
}

// MARK: - Metric Card Surface

struct MetricCardSurfaceModifier: ViewModifier {
  var isHero = false

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: ChartConstants.cardCornerRadius)
  }

  @ViewBuilder
  private var cardBackground: some View {
    ZStack {
      shape.fill(Color(nsColor: .controlBackgroundColor))
      if isHero {
        shape.fill(.tint.opacity(0.09))
      }
    }
  }

  func body(content: Content) -> some View {
    content
      .background { cardBackground }
      .overlay {
        if isHero {
          shape.strokeBorder(.tint.opacity(0.22), lineWidth: 1)
        } else {
          shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
      }
  }
}

extension View {
  /// Applies a stable, appearance-adaptive fill to dashboard summary metric cards.
  func metricCardSurface(isHero: Bool = false) -> some View {
    modifier(MetricCardSurfaceModifier(isHero: isHero))
  }
}

// MARK: - Chart Helpers

/// Shared utility functions for chart interactions.
enum ChartHelpers {
  /// Finds the nearest data point date to a cursor location in a chart.
  static func findNearestDate<T>(
    at location: CGPoint, in proxy: ChartProxy,
    points: [T], dateKeyPath: KeyPath<T, Date>
  ) -> Date? {
    guard let date: Date = proxy.value(atX: location.x) else { return nil }

    return points.min(by: {
      abs($0[keyPath: dateKeyPath].timeIntervalSince(date))
        < abs($1[keyPath: dateKeyPath].timeIntervalSince(date))
    })?[keyPath: dateKeyPath]
  }
}

// MARK: - Shared Chart Views

/// Empty state message for charts when no data is available.
struct ChartEmptyMessage: View {
  let text: LocalizedStringKey
  let height: CGFloat

  var body: some View {
    Text(text)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
      .frame(height: height)
  }
}

/// Generic tooltip wrapper with consistent styling across all charts.
struct ChartTooltipView<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 2) {
      content()
    }
    .padding(6)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}
