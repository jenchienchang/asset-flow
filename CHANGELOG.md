# Changelog

## [0.7.0](https://github.com/jenchienchang/asset-flow/compare/v0.6.0...v0.7.0) (2026-09-24)


### Features

* **csv:** use TabularData for RFC-compliant parsing ([eb42b7d](https://github.com/jenchienchang/asset-flow/commit/eb42b7d08ea825e4ef83b9532d0fce7aee00e529))
* **dashboard:** refine hero card styling ([2a8b8e4](https://github.com/jenchienchang/asset-flow/commit/2a8b8e4fbbec16675a079a2ef9e9f87f168647d4))
* **import:** surface CSV failures and preserve prior imports ([7de46c0](https://github.com/jenchienchang/asset-flow/commit/7de46c0a1611982e09320f8ba76f1387d376b48c))


### Bug Fixes

* **backup:** accept enclosing folder in restore archives ([e48c7c7](https://github.com/jenchienchang/asset-flow/commit/e48c7c74a2979723a9bc4e7e94c60856df8d54a7))
* **backup:** prevent malformed and partial restores ([67e59b9](https://github.com/jenchienchang/asset-flow/commit/67e59b9ff8a8aad3a54bd8c050ea66b882418376))
* **ci:** resolve lint tool versions dynamically ([745f1fc](https://github.com/jenchienchang/asset-flow/commit/745f1fc7824423971c7a4f88e09b70fdc27b888e))
* **data-sync:** keep views in sync with stored data ([aa1caee](https://github.com/jenchienchang/asset-flow/commit/aa1caee16e54ecea2067eb29a4c522b1bb53415d))
* **exchange-rates:** harden fetching, caching, and conversion ([0d74f21](https://github.com/jenchienchang/asset-flow/commit/0d74f21e4cc1f4443265ef299afd2d559a907450))
* **financial:** preserve Decimal precision in calculations ([a2ff412](https://github.com/jenchienchang/asset-flow/commit/a2ff412fce2f1870bedbfc4cd35848339ee69d43))
* **import:** use operation-scoped persistence lookups ([ecb9715](https://github.com/jenchienchang/asset-flow/commit/ecb97157c20bdd97c10f7bd125f555d464a075a2))
* **import:** validate CSV duplicates before applying rows ([520e1a4](https://github.com/jenchienchang/asset-flow/commit/520e1a4df733289dbff303e76279e791f9c58d54))
* **links:** update repository URLs ([b3bff19](https://github.com/jenchienchang/asset-flow/commit/b3bff1908b0ec0b631d46a9dea74a4cc5053839a))
* **persistence:** propagate SwiftData fetch failures ([14a5825](https://github.com/jenchienchang/asset-flow/commit/14a5825f7c91100607300dea2a20a8b83e0e7d15))
* **snapshots:** remove non-Sendable model capture ([afbdd16](https://github.com/jenchienchang/asset-flow/commit/afbdd169f6ff56b2cab7e5248aa020b4e639cd21))

## [0.6.0](https://github.com/jenchienchang/asset-flow/compare/v0.5.0...v0.6.0) (2026-05-08)

### Features

- **asset-list:** add Hide Stale Assets toggle ([0c7b0ca](https://github.com/jenchienchang/asset-flow/commit/0c7b0ca0f99b3c38a5250d163943a4184e1dcea9))
- **bulk-entry:** size CSV mapping preview to content ([5c97ca9](https://github.com/jenchienchang/asset-flow/commit/5c97ca9c188d9991c4b3db6d09f0564ff58c7209))
- **sidebar:** adopt system Liquid Glass background on macOS 26+ ([37d46be](https://github.com/jenchienchang/asset-flow/commit/37d46be86257384f0b03db9bcd231486cd79569f))

### Bug Fixes

- **bulk-entry:** left-align text-categorical column headers ([146decc](https://github.com/jenchienchang/asset-flow/commit/146decccf1113d8ae20b45982e20781b3d43d697))
- **bulk-entry:** paint updated-row tint as a contiguous strip ([4456875](https://github.com/jenchienchang/asset-flow/commit/44568759d671e02394b9bd76ee54c963a3696def))
- **docs:** support Chinese anchors and search in zh-TW pages ([e0daf34](https://github.com/jenchienchang/asset-flow/commit/e0daf34e75131dac7b763738741bab8c39a4e1b3))
- **docs:** track included file's git history for include-only pages ([ff225a6](https://github.com/jenchienchang/asset-flow/commit/ff225a69636b9b73bdc506176df42b2f17cfb2d4))
- **settings:** set initial settings window size ([7847236](https://github.com/jenchienchang/asset-flow/commit/7847236070f9121a963017f21c07b358dc509fcb))

### Performance Improvements

- **viewmodels:** share snapshot summary aggregation ([9f56f0a](https://github.com/jenchienchang/asset-flow/commit/9f56f0a6c0d97636c5083f3daf37c4d043543337))

## [0.5.0](https://github.com/jenchienchang/asset-flow/compare/v0.4.1...v0.5.0) (2026-04-18)

### Features

- **bulk-entry:** add bulk entry workflow for snapshot creation ([#26](https://github.com/jenchienchang/asset-flow/issues/26)) ([50b9c8e](https://github.com/jenchienchang/asset-flow/commit/50b9c8e08897409e42067ad8fa617bb0685df171))
- **bulk-entry:** add cash flow support for snapshot creation ([0e82259](https://github.com/jenchienchang/asset-flow/commit/0e822594175df7f081d3ff6dcd9b6ba1e36c6fcf))
- **bulk-entry:** add keyboard navigation, auto-focus, and summary to cash flow section ([6909c5e](https://github.com/jenchienchang/asset-flow/commit/6909c5e40bff4029fc52ab212612675cd0f758e5)), closes [#30](https://github.com/jenchienchang/asset-flow/issues/30)
- **bulk-entry:** show full-precision previous values with fill button ([08f3521](https://github.com/jenchienchang/asset-flow/commit/08f352148547ed3fd795850a3e5f3efbb598ee1e))
- **csv:** add column mapping for CSV imports ([#28](https://github.com/jenchienchang/asset-flow/issues/28)) ([6b04e1c](https://github.com/jenchienchang/asset-flow/commit/6b04e1c590b239e242337260e63aacb4e96385bf))
- **parsing:** add locale-aware decimal parsing for number fields ([c854267](https://github.com/jenchienchang/asset-flow/commit/c854267b05eb520202afb81be94f20f1638e7189))
- **ui:** apply explicit button styles to HStack popovers ([ac3a014](https://github.com/jenchienchang/asset-flow/commit/ac3a01467e5a63ab0e72c8c5c7b9af5c61fb79c9))

### Bug Fixes

- **bulk-entry:** commit field values on focus change despite .equatable() ([f1db3f1](https://github.com/jenchienchang/asset-flow/commit/f1db3f1a18e1285eb0e45bab86e4278283f9972d))
- **bulk-entry:** consolidate duplicate .fileImporter into single modifier ([a7155ab](https://github.com/jenchienchang/asset-flow/commit/a7155ab93f11406e67916dee40f24be8ccfd2025))
- **bulk-entry:** preserve field values when rows scroll off-screen ([f120c20](https://github.com/jenchienchang/asset-flow/commit/f120c203576730d7f2858e75897ab6ad1d882446))
- **bulk-entry:** preserve field values when toggling row exclusion ([9405a73](https://github.com/jenchienchang/asset-flow/commit/9405a7376e208964e800f5b8d7ee705cc611274d))

### Performance Improvements

- **bulk-entry:** eliminate input latency from redundant view recomputation ([33f3bf7](https://github.com/jenchienchang/asset-flow/commit/33f3bf77a3f8ac45a500811ad4dfc6c39c268e2a)), closes [#29](https://github.com/jenchienchang/asset-flow/issues/29)
- **bulk-entry:** reduce SwiftUI invalidation cascades and redundant iterations ([a076a40](https://github.com/jenchienchang/asset-flow/commit/a076a40468827a2e323ad026e1b0f187857b7384))
- **bulk-entry:** reduce unnecessary work in focus advance and CSV import ([a4caafd](https://github.com/jenchienchang/asset-flow/commit/a4caafd525dc2dd90e242e4c0eadafe7aefe1bb9))
- **snapshot:** use #Predicate and fetchLimit for snapshot lookups ([28ad9fd](https://github.com/jenchienchang/asset-flow/commit/28ad9fde230a0e4a0209a1907156d4b09cceab88))

## [0.4.1](https://github.com/jenchienchang/asset-flow/compare/v0.4.0...v0.4.1) (2026-03-15)

### Continuous Integration

- **docs:** move release docs deployment into release-please workflow ([faa08e0](https://github.com/jenchienchang/asset-flow/commit/faa08e018255d78b4dea0479719a640e3b9601d8))

## [0.4.0](https://github.com/jenchienchang/asset-flow/compare/v0.3.0...v0.4.0) (2026-03-15)

### Features

- Add documentation links and dev-aware version suffix ([a5e9ab9](https://github.com/jenchienchang/asset-flow/commit/a5e9ab99437f4cce2836db80d7703a59d6ee41d9))
- Add multi-currency support with exchange rate conversion ([#22](https://github.com/jenchienchang/asset-flow/issues/22)) ([36b58f9](https://github.com/jenchienchang/asset-flow/commit/36b58f99ad78abc34a99769703a81d2544e55d63))
- **asset:** Add converted value column and chart to asset detail view ([70ebf17](https://github.com/jenchienchang/asset-flow/commit/70ebf17ee88de9c8a9da70172a0d6816977b953b))
- **assets:** Add inline value editing to asset detail history table ([144da63](https://github.com/jenchienchang/asset-flow/commit/144da63873e58d4582470e02d0af3842093a7807))
- **categories:** Add configurable category order via drag-and-drop ([687066a](https://github.com/jenchienchang/asset-flow/commit/687066a5e1c781192817091ef36623328e380ba6))
- **chart:** Add dynamic multi-column legend to pie chart ([568cf75](https://github.com/jenchienchang/asset-flow/commit/568cf7534e0a63ccfadcfb7452ce243635dfa08c))
- **charts:** Add target allocation line and dynamic y-axis to category allocation chart ([851c45c](https://github.com/jenchienchang/asset-flow/commit/851c45c3b34cbfbd532b007d33f44b7c1670647e))
- **dashboard:** Elevate UI to premium FinTech aesthetic ([5cc344b](https://github.com/jenchienchang/asset-flow/commit/5cc344b3cbd87c4b1d36db3d97d2f8b7e0c6aad4))
- **dashboard:** Replace 14-day backward lookback with bidirectional closest-snapshot matching ([9135f6f](https://github.com/jenchienchang/asset-flow/commit/9135f6fbdd11fcdf393ce725b621c85d1af77b84))
- **dashboard:** Smooth pie chart angle animation and improved color palette ([76a0f67](https://github.com/jenchienchang/asset-flow/commit/76a0f6729677a212192ebb1c608b14a9c78ca4df))
- **exchange-rate:** Auto-fetch missing exchange rates for all snapshots ([ba64bee](https://github.com/jenchienchang/asset-flow/commit/ba64beeb465c2f57191503e5477081fcfa711aba))
- **import:** Add currency column support with validation and auth-aware popovers ([852d887](https://github.com/jenchienchang/asset-flow/commit/852d88793d028ce6c371a52b2600fa5694357608))
- **import:** Move validation to per-row errors and add category apply mode ([e803c30](https://github.com/jenchienchang/asset-flow/commit/e803c30cf5c0431a3b428572d2392ef04ab3cbaf))
- **security:** Add lock-aware hover modifiers to prevent data leakage ([107eecb](https://github.com/jenchienchang/asset-flow/commit/107eecbe9acdef510605552af9e07f25beacf187))
- **security:** Add optional app lock with Touch ID and system password ([833de3b](https://github.com/jenchienchang/asset-flow/commit/833de3b8b239861e74cd710f6e66df53c4a6ffc9))
- **settings:** Make settings window resizable ([464a76c](https://github.com/jenchienchang/asset-flow/commit/464a76c7d13a826f2f3e7f2729d6f5f6031794d2))
- **settings:** Use adaptive text alignment for privacy disclaimer ([36c427c](https://github.com/jenchienchang/asset-flow/commit/36c427c2bc1f7a7485d3fe7a22bfdd956bb13fc8))
- **ui:** Add exchange rate display section to snapshot detail ([399355e](https://github.com/jenchienchang/asset-flow/commit/399355e8bda6b2f99c5edbd261986880de1ed3b4))
- **ui:** Add platform list reordering and category deviation help messages ([5a78c9f](https://github.com/jenchienchang/asset-flow/commit/5a78c9f3c735956808423925e2b5c5d970aeb92f))
- **ui:** Add shared animation constants with Reduce Motion support ([cc34621](https://github.com/jenchienchang/asset-flow/commit/cc34621a6affe60d81cef97cdfdc619e29b3dff6))

### Bug Fixes

- **asset:** Initialize picker caches in init to prevent invalid selection warnings ([10b9816](https://github.com/jenchienchang/asset-flow/commit/10b98161da40783791e69d1e09d1bc0ebc74ad6d))
- **charts:** Use idiomatic RuleMark annotation for category chart tooltip ([1454f85](https://github.com/jenchienchang/asset-flow/commit/1454f85c3ce7697100ebde9df99aaad50d9e115a))
- **dashboard:** Prevent stat card labels from wrapping or truncating ([daa0c6e](https://github.com/jenchienchang/asset-flow/commit/daa0c6e9bd92b54d13a74bf0174bf79a7753036b))
- **docs:** Exclude CLAUDE.md and README.md from MkDocs build output ([bb915de](https://github.com/jenchienchang/asset-flow/commit/bb915de8dcc484409ef071eff9b284be64643d88))
- **docs:** Fix language switcher on home pages for mike versioning ([e5f037c](https://github.com/jenchienchang/asset-flow/commit/e5f037cc09cae3979f89f1db5b6bdc98508e1698))
- **l10n:** Add missing zh-Hant translations for charts, toolbars, and buttons ([7fdc4d7](https://github.com/jenchienchang/asset-flow/commit/7fdc4d78fe4a70148abd0784959ab802f79ac93c))
- **l10n:** Localize privacy disclaimer in native About panel ([aefc6c8](https://github.com/jenchienchang/asset-flow/commit/aefc6c81a3fffd4efb55dca36b9ef64cc7876c0c))
- **reactivity:** Refresh list views after detail view edits ([3ac18d3](https://github.com/jenchienchang/asset-flow/commit/3ac18d3cea2813f886a7b6b0ce64d728719c5c40))
- **tables:** Add visible column resize handles to detail view tables ([ec51c14](https://github.com/jenchienchang/asset-flow/commit/ec51c140b5dbfffe1ad93f9303f11e3e4a354e82))
- **test:** Replace flaky Task.sleep with deterministic Task.value await ([e1477c8](https://github.com/jenchienchang/asset-flow/commit/e1477c8a1588488b6d0ef3c30a4971d0d4ea7f85))

## [0.3.0](https://github.com/jenchienchang/asset-flow/compare/v0.2.0...v0.3.0) (2026-02-21)

### Features

- **charts:** Upgrade asset detail sparkline to full line chart ([5d51754](https://github.com/jenchienchang/asset-flow/commit/5d51754350f58b0f69d66def9a164d3f6dd98297))
- **dashboard:** Rebase cumulative TWR chart to 0% on period selection ([3406577](https://github.com/jenchienchang/asset-flow/commit/34065774bda15122d7ccd34550350249b0f4d644))
- **ui:** Modernize UI patterns with native macOS conventions ([8a5c309](https://github.com/jenchienchang/asset-flow/commit/8a5c3093a707e8bf34471a31bd57f98785937bf7))

### Bug Fixes

- **charts:** Pin axes and fix tooltip clipping in detail view charts ([d505c91](https://github.com/jenchienchang/asset-flow/commit/d505c915c845c964a7ae4420472dc074eecd7c3b))
- **charts:** Pin Y-axis domain to prevent axis shift during hover ([c02d963](https://github.com/jenchienchang/asset-flow/commit/c02d963a62a1fa47f4f8e713c831de00a7e2e372))
- **dashboard:** Add 0% origin point to TWR history for consistent rebasing ([44ad4ca](https://github.com/jenchienchang/asset-flow/commit/44ad4ca0666fece4305060c64f719162746925e3))
- **i18n:** Add missing zh-Hant translations for empty state views ([1137cb9](https://github.com/jenchienchang/asset-flow/commit/1137cb96d10c3e456e35d12fa962409773e934d1))
- **l10n:** Make CSV column names non-localizable in import view ([470ec97](https://github.com/jenchienchang/asset-flow/commit/470ec97f16609baf4383730fa196bd099fb61a28))

## [0.2.0](https://github.com/jenchienchang/asset-flow/compare/v0.1.0...v0.2.0) (2026-02-20)

### Features

- **import:** Add platform apply mode for CSV import ([af70a67](https://github.com/jenchienchang/asset-flow/commit/af70a67d8141a0bd5481e13f634ffffdae115585))
- **ui:** Make sidebar always visible and non-collapsible ([275db37](https://github.com/jenchienchang/asset-flow/commit/275db37ae892e676cb9ff45baa61b669adcb5e63))

### Bug Fixes

- **import:** Cache CSV file data to fix platform selection after file load ([5d8b1e6](https://github.com/jenchienchang/asset-flow/commit/5d8b1e613cd3489ddec87f9489b44b9e527e5284))
- **import:** Improve CSV import reliability and UX ([#15](https://github.com/jenchienchang/asset-flow/issues/15)) ([d58be4d](https://github.com/jenchienchang/asset-flow/commit/d58be4d33de42ad2737ae2859efef93189f6ec11))
- **import:** Preserve excluded rows when platform or category changes ([13c9aef](https://github.com/jenchienchang/asset-flow/commit/13c9aefa5292a1b9589225cf4e834c8a4764725b))
- **import:** Reset import form after successful CSV import ([5b80783](https://github.com/jenchienchang/asset-flow/commit/5b807830542c614b7756a88dee912a3c66e4810c))
