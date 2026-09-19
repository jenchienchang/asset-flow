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

enum Constants {
  enum AppInfo {
    static let name = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "AssetFlow"
    static let version =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    static let buildNumber =
      Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    static let commit = Bundle.main.infoDictionary?["AppCommit"] as? String ?? "unknown"
    static let developerName = "Jen-Chien Chang"
    static let copyright = "Copyright © 2026 Jen-Chien Chang"
    static let license = "GNU General Public License v3.0"
    static let repositoryURL = URL(string: "https://github.com/jenchienchang/asset-flow")!
    static let issuesURL = repositoryURL.appending(path: "issues")

    static var documentationURL: URL {
      let baseURL = "https://jenchienchang.github.io/asset-flow"
      let versionPath = version.contains("-dev") ? "/dev/" : "/v\(version)/"
      let localePath: String
      switch Locale.current.language.languageCode?.identifier {
      case "zh": localePath = "zh-TW/"
      default: localePath = ""
      }
      return URL(string: baseURL + versionPath + localePath + "user-guide/")!
    }
  }

  enum DefaultValues {
    static let defaultCurrency = "USD"
    static let maxDecimalPlaces = 2
    static let defaultDateFormat = DateFormatStyle.abbreviated
    static let defaultPlatform = ""
    static let defaultAppLockEnabled = false
    static let defaultHideStaleAssets = true
  }

  enum UserDefaultsKeys {
    static let preferredCurrency = "preferredCurrency"
    static let dateFormat = "dateFormat"
    static let defaultPlatform = "defaultPlatform"
    static let appLockEnabled = "appLockEnabled"
    static let appSwitchTimeout = "appSwitchTimeout"
    static let screenLockTimeout = "screenLockTimeout"
    static let platformOrder = "platformOrder"
    static let hideStaleAssets = "hideStaleAssets"
  }

  enum Parsing {
    /// Currency symbols to strip from user-entered numeric strings.
    static let currencySymbols: Set<Character> = ["$", "€", "£", "¥", "₩", "₹"]
  }
}
