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

@Model
final class Category {
  #Unique<Category>([\.name])

  var id: UUID
  var name: String
  var targetAllocationPercentage: Decimal?
  var minimumBalanceAmount: Decimal?
  var minimumBalanceCurrency: String?
  var displayOrder: Int

  @Relationship(deleteRule: .deny, inverse: \Asset.category)
  var assets: [Asset]?

  init(
    name: String,
    targetAllocationPercentage: Decimal? = nil
  ) {
    self.id = UUID()
    self.name = name
    self.targetAllocationPercentage = targetAllocationPercentage
    self.displayOrder = 0
    self.assets = []
  }
}
