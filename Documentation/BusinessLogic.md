# Business Logic and Calculation Design

AssetFlow derives portfolio values, performance, and allocation plans from dated snapshots. This document defines the domain rules, financial units, boundary cases, and validation decisions. [`SPEC.md`](SPEC.md) owns product requirements, [`DataModel.md`](DataModel.md) owns stored fields and relationships, [`APIDesign.md`](APIDesign.md) owns CSV and service contracts, and [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns presentation and interaction.

## Core Concept: Snapshot-Based Portfolio Model

A snapshot contains only asset values and external cash flows recorded for its date. A missing asset entry is absent, not zero, and values never carry forward automatically. A user may explicitly seed a new snapshot from a prior one in Bulk Entry or copy selected prior-platform values during CSV import. Snapshots can later be edited or deleted; an import into an existing date may add records but cannot silently replace a recorded nonzero asset value or an existing cash flow.

## Asset Identity and Matching

An asset's import identity is its name and platform after trimming outer whitespace, collapsing repeated internal spaces, and comparing without case. A matching asset record is reused across snapshots. Importing a different name or platform creates another asset; editing an existing asset's identity changes the same record across its history and must not collide with another asset. An asset may be deleted only when no snapshot values refer to it. Removing an asset from one snapshot removes that recorded value, not the asset record.

An asset is **stale** when it has no entry in the latest snapshot. A latest value of zero is present and is not stale. The asset-list visibility control and its persistence belong in [`UserInterfaceDesign.md`](UserInterfaceDesign.md#assets-screen).

## Calculation Logic

### Currency Conversion

Monetary amounts and rates use `Decimal`. Portfolio values, cash flows, and minimum goals have currency units; performance returns are ratios (for example, `0.09` means 9%). Category targets and allocation shares use percentage-point units on a 0–100 scale. Calculations use unrounded values; display rounding never feeds back into a financial decision.

An asset or cash flow with an empty stored currency inherits the **current display currency for conversion**. This is distinct from an explicit currency and from a missing rate. For a snapshot, conversion requires a positive, finite rate for every required non-display currency, an exchange-rate record with the display currency as its base, and a Gregorian rate date matching the snapshot date. The base-currency rate is 1. Cross-currency conversion is:

```text
converted amount = native amount / rate[native currency] × rate[display currency]
```

### Portfolio Total Value

The converted snapshot total is the sum of its directly recorded asset values after conversion. If any required asset rate is missing or unusable, the converted total is unavailable. Native totals remain available **separately by currency**; a mixed-currency sum is never a single-currency total. Net cash flow likewise sums converted external-flow amounts only when its required rates are available. No cash-flow operations means a net cash flow of zero.

Availability depends on the calculation:

| Result                             | Required conversion and valid inputs                                                                                                                                                                                                |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Snapshot total and category shares | Asset values at that snapshot; shares also require a positive converted total.                                                                                                                                                      |
| Net cash flow                      | Cash-flow amounts at that snapshot; asset-rate availability is independent.                                                                                                                                                         |
| Period growth                      | Asset totals at the resolved beginning and ending snapshots.                                                                                                                                                                        |
| Period Modified Dietz              | Asset and cash-flow conversion status at the beginning, ending, and intervening snapshots used by the dashboard; the beginning snapshot's flows are excluded from the period even though its combined conversion status is checked. |
| Cumulative TWR                     | Every consecutive interval's Modified Dietz result across the history.                                                                                                                                                              |
| CAGR                               | Asset totals at the first and latest snapshots, plus a positive time interval and positive endpoint values.                                                                                                                         |
| Rebalancing                        | Latest-snapshot asset values and each configured minimum's currency conversion; a missing goal rate can disable the plan while the asset total remains available.                                                                   |

A missing rate disables the affected converted result, not unrelated metrics. The service also retains native totals by currency for diagnosis. Exchange-rate fetching may fill missing records later; it does not justify substituting native amounts for converted amounts.

### Category Allocation

For a snapshot with a positive converted total:

```text
category value = sum of converted values of directly recorded assets in that category
category share (%) = category value / converted portfolio total × 100
```

Uncategorized assets form their own group. A category with no recorded assets has zero value and a 0% share when the total is positive. If every recorded asset is uncategorized, that group has 100% of a positive total. For a zero or negative total, or incomplete asset conversion, a meaningful share is unavailable rather than inferred from a partial or mixed-currency total.

## Portfolio Performance

Performance calculations are portfolio-level. Category-level external flows are not recorded, so the app does not calculate category returns.

### Growth Rate

For 1M, 3M, and 1Y metrics, subtract the selected number of months from the latest snapshot date to get a target date. Choose the closest **other** snapshot on either side of that date. There is no 14-day or other distance cutoff; ties choose the earlier snapshot. The selected beginning snapshot and the latest snapshot define the **actual interval**, which can be shorter or longer than the named period. Fewer than two snapshots leave period metrics unavailable.

Simple growth includes contributions and withdrawals; it does not isolate investment performance:

```text
growth ratio = (ending converted value - beginning converted value)
               / beginning converted value
```

The beginning value must be positive. Growth needs conversion of the two endpoint asset totals, not every historical snapshot or cash flow.

### Net Cash Flow

An **external cash flow** moves money into or out of the portfolio. Positive amounts are contributions; negative amounts are withdrawals. Dividend reinvestment within the portfolio is not an external contribution. Operations are portfolio-level and are assigned to their snapshot date, regardless of the platform involved. Amounts are converted to the display currency at that snapshot before aggregation. If no operations are recorded, the calculation treats net external flow as zero.

### Modified Dietz Return

For a period from `begin` to `end`, include cash flows from snapshots in **`(begin, end]`**. A flow on the beginning date is excluded by the dashboard's aggregation rule; a flow on the ending date is included. A flow's weight uses the calendar days remaining after its assigned date:

```text
R  = (EMV - BMV - Σ CFᵢ) / (BMV + Σ(wᵢ × CFᵢ))
wᵢ = (period calendar days - days since begin) / period calendar days
```

`BMV` and `EMV` are beginning and ending converted portfolio values; each `CFᵢ` is a signed converted external flow. The period must contain a positive number of calendar days, `BMV` must be positive, and the denominator must be positive. A flow on the ending date has weight zero. The pure formula would give a day-zero flow weight one, but the app excludes beginning-date flows from this period.

**Worked example:** Over 90 days, begin with 100,000, record a +100,000 contribution on day 30, and end with 215,000 in the same currency. The flow weight is `60/90 = 2/3`, so its weighted contribution is approximately 66,666.67. The numerator is 15,000; the full-precision denominator is `100,000 + (2/3 × 100,000)`. The expected return is **`0.09` (9%)**. The displayed 66,666.67 is rounded for reading, not used as the calculation input. This matches the synthetic mid-period case in [`CalculationServiceTests.swift`](../AssetFlowTests/Services/CalculationServiceTests.swift).

Modified Dietz estimates cash-flow-adjusted performance from available valuations and assumed flow dates. It does not reconstruct a valuation at every actual transaction time. The [GIPS Standards Handbook for Firms](https://www.gipsstandards.org/wp-content/uploads/2021/04/gips-standards-handbook-firms.pdf) describes the method as an estimate; this description does not claim GIPS compliance.

### Cumulative Time-Weighted Return (TWR)

The app chains Modified Dietz estimates between consecutive snapshots:

```text
cumulative TWR ratio = ∏(1 + interval return) - 1
```

For example, consecutive estimated returns of +10% and -5% produce `1.10 × 0.95 - 1 = 0.045`, or 4.5%. The chain remains an estimate under the snapshot-date assumptions. If any required interval return is undefined, the all-time cumulative result and its history are unavailable; an empty set of intervals is not a reported 0% result.

For a selected range other than All, filter the cumulative history first. Let `Cₖ` be the inception-based return at its first visible point and `Cᵢ` the return at another visible point. Rebase each point as:

```text
range returnᵢ = (1 + Cᵢ) / (1 + Cₖ) - 1
```

The first visible point becomes 0% when `1 + Cₖ` is nonzero. For example, inception returns of 50% at the first visible point and 65% later become 0% and 10% for that range. All retains the inception-based series. If `Cₖ = -100%`, the divisor is zero; the current calculation retains the original points because it cannot rebase them.

### CAGR

CAGR annualizes the change from the first to the latest converted portfolio value:

```text
years = calendar days between snapshots / 365.25
CAGR ratio = (ending value / beginning value) ^ (1 / years) - 1
```

Both values and the interval must be positive. Fractional years are allowed, including periods shorter than one year. CAGR includes the effect of external flows, unlike Modified Dietz. Its ratio and fractional exponent are evaluated using `Decimal` arithmetic rather than converting portfolio values through `Double`.

### Edge Cases

| Condition                                                      | Domain result                                                                                                                    |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Fewer than two snapshots                                       | Growth, period return, cumulative TWR, and CAGR unavailable.                                                                     |
| Nonpositive beginning value                                    | Growth, Modified Dietz, and CAGR unavailable.                                                                                    |
| Nonpositive Modified Dietz denominator or nonpositive interval | That interval return and a chain requiring it unavailable.                                                                       |
| Nonpositive ending value for CAGR                              | CAGR unavailable.                                                                                                                |
| Missing conversion                                             | Only results requiring the missing asset, flow, or goal rate are unavailable.                                                    |
| Zero or negative converted portfolio total                     | Category shares and effective target shares unavailable; positive minimum shortfalls can still be assessed where values convert. |

## Category Management

### Target Allocation and Minimum Balance Rules

A category may have a percentage target, a currency-denominated minimum balance, both, or neither. Goal fields are edited as one draft and validated together on save. Category names must be nonempty and unique without case. A present percentage must be finite and within 0–100. Minimum amount and currency must be both present or both absent; a present amount must be finite and nonnegative, and zero is valid. The chosen currency must be valid for the goal editor. A newly created category has no goal unless one is supplied.

The suggested minimum currency is the single currency shared by the category's assets, or the display currency when its assets are mixed or absent. The saved minimum keeps its original denomination when the display currency changes. Changing the goal currency changes what the entered amount means; it does not convert the amount. A category's persisted user order and stored fields are defined in [`DataModel.md`](DataModel.md#category). Infeasible goals can be saved so the assessment can explain their shortfall. Ordinary asset and cash-flow imports do not change goals.

### Goal Assessment and Warnings

For a category with a converted minimum, its **current minimum shortfall** is `max(0, minimum - current balance)`. Every strictly positive shortfall warrants a warning, including a minimum-only goal or an infeasible whole-portfolio plan. This is different from the **external funding shortfall** needed to make all category goals feasible.

Current and effective allocation shares both use the **whole converted portfolio** as denominator. Only a category with a percentage target receives an allocation-deviation warning, and only when the absolute difference from its effective share is **greater than 5 percentage points**; exactly 5 does not warn. A category with both issues reports both reasons. A minimum-only category protects its current surplus and does not receive a surplus-deviation warning. A no-goal category has no effective target. Zero-total shares, infeasible effective targets, missing conversion, and absent snapshots are unavailable states, not proof of compliance or shortfall. Comparisons use full `Decimal` precision.

## Rebalancing Engine

### Inputs and Feasibility

Rebalancing is a read-only preview using the latest snapshot's directly recorded assets. Missing assets do not carry forward. Let:

- `V` be the converted portfolio total.
- `cᵢ` be category `i`'s current converted balance and `mᵢ` its converted minimum, or zero.
- `u` be the converted uncategorized balance.
- `qᵢ = max(cᵢ, mᵢ)` for a category **without** a percentage target; this protects its current holding and minimum.
- `Q = u + Σqᵢ` be protected funds, and `A = V - Q` be the pool for percentage-target categories.
- `F` be the sum of minimums on percentage-target categories.

Invalid balances, goal fields, or arithmetic make the plan unavailable without targets. For valid inputs, funding and goal statuses are assessed in this order:

1. If `Σmᵢ > V`, all minimums cannot fit; the global funding shortfall is `Σmᵢ - V`.
1. If `Q + F > V`, protected funds leave insufficient room for percentage-category minimums; the shortfall is `Q + F - V`. This can occur even if total minimums alone fit.
1. If any percentage targets exist, their sum must equal **exactly 100%** for an actionable percentage plan. Goals may be saved before the sum reaches 100%.
1. If no goals exist, there is no plan.

When only minimums exist, current surpluses remain protected. The app does not invent a donor to fund an unmet minimum. A zero-valued portfolio can still report a positive funding shortfall; a feasible zero total does not supply meaningful percentage shares.

### Constrained Allocation

An explicit 0% target receives its minimum, or zero if it has none. A missing percentage protects `qᵢ` instead. For positive percentages, find a scale `λ` such that:

```text
effective targetᵢ = max(mᵢ, λ × percentage targetᵢ)
sum of percentage-category targets = A
adjustmentᵢ = effective targetᵢ - current balanceᵢ
```

Distribute the remaining pool in proportion to remaining positive percentage weights. Fix any category whose proportional share falls below its minimum, then redistribute among the others. A feasible plan preserves the whole portfolio value, leaves protected and uncategorized holdings in place, and meets every minimum. Requested percentages describe the allocation **pool**; effective shares use `V`.

| Synthetic case                                                                                                                    | Expected domain result                                                                                                                                    |
| --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `V = 1,000`: minimum-only balance 200 with minimum 100, no-goal balance 100, uncategorized 200, and one 100% category holding 500 | Protected funds `Q = 500`; the 100% category receives the remaining 500. The minimum-only surplus remains 200.                                            |
| `V = 1,000,000`: reserve 200,000 at 10% with minimum 300,000; equities 600,000 at 60%; bonds 200,000 at 30%                       | Targets are approximately 300,000 / 466,666.67 / 233,333.33. The reserve minimum binds; the other targets retain their 60:30 ratio.                       |
| `V = 1,000`: minimum-only category holds 200 and requires 300; a no-goal category holds 800                                       | Total minimums fit, but protected requirements total 1,100. The plan reports insufficient available funds of 100 and gives no transfers.                  |
| `V = 100`: current balances 40 / 20.5 / 39.5 / 0, targets 30% / 20% / 49.8% / 0.2%, last category minimum 0.2                     | Fund its mandatory 0.2 first, then use 9.8 of the same donor's reduction for the larger increase. Two optional 0.5 differences remain as a residual of 1. |

The cases correspond to [`RebalancingCalculatorTests.swift`](../AssetFlowTests/Services/RebalancingCalculatorTests.swift) and [`RebalancingTransferPlannerTests.swift`](../AssetFlowTests/Services/RebalancingTransferPlannerTests.swift). Approximate figures in the table are for reading; requirements and targets are compared before display rounding.

### Precision and Suggested Transfers

Balance arithmetic uses checked `Decimal` operations. Finite results with normal precision loss can be used; overflow, underflow, invalid values, and division by zero make the plan unavailable. Percentage aggregation requires exact arithmetic. When summing nonnegative minimum or protected requirements loses precision, a strict funding decision is accepted only if it is unambiguous outside a conservative bound of `max(required total, budget, 1) × component count × 10⁻³⁷`. A budget inside that bound is **unavailable**, never presumed sufficient. Original requirements enter the combined comparison so rounded subtotals cannot hide a deficit.

Independently grouped portfolio and category totals may differ by at most `max(V, 1) × 10⁻²⁸` from `Decimal` arithmetic. This tolerance is solely for consistency and allocation remainder reconciliation; it never relaxes minimums or genuine funding deficits. Remainders may go only to a flexible positive-weight category without violating its minimum. No monetary value is converted through `Double` or rounded to display precision to decide feasibility.

Transfer eligibility is separate from funding order. An adjustment with an absolute value of at least one display-currency unit is eligible. A smaller positive adjustment is also eligible when its category has any current minimum shortfall; the **whole target increase** can then be funded. Smaller donor reductions become eligible when donors reducing by at least one unit cannot cover the total mandatory shortfall. Other subunit adjustments are suppressed.

The planner first funds only **actual current minimum shortfalls** of eligible recipients, including subunit amounts. It then uses remaining donor and recipient capacity for their other target increases. For example, a recipient increasing by 0.8 with a minimum shortfall of 0.2 can receive 0.2 first and the remaining 0.6 if donor capacity allows; the optional 0.6 does not count as mandatory demand. Transfers cannot exceed donor or recipient capacity. Suppressed or unmatched differences remain visible as a residual. Invalid, infeasible, or conversion-unavailable plans provide no actionable transfers.

Historical goal comparisons use current goal settings with each snapshot's rates; they do not reconstruct historical goal settings.

## CSV Import System

[`APIDesign.md`](APIDesign.md#csv-import-format-specification) owns exact headers, encoding, mapping, and interchange examples. Asset CSV requires an asset name and market value; platform and currency are optional. Cash-flow CSV requires a description and amount; currency is optional. The file contains no snapshot date: the user selects a target date no later than today. Required headers are detected without case or surrounding whitespace, and unresolved columns can be mapped before import.

A malformed file, no data rows, missing required fields, an empty required identity, or an unparseable amount blocks import. A supplied asset currency absent from the app's supported currency list also blocks the standard asset import. The cash-flow import does not currently reject a supplied code solely because it is absent from that list; a needed but unavailable rate can later make converted cash-flow results unavailable. Zero or negative asset market values and zero cash-flow amounts are warnings in the standard import; they are not parser errors. A file with blocking errors does not partially import valid rows.

### Platform, Category, and Currency Resolution

With no import-level platform selected, each asset row keeps its CSV platform or an empty one. With a selection, **Override All** assigns it to every row; **Fill Empty Only** assigns it only where the CSV platform is empty. Identity and duplicate checks use the resulting platform.

With no import-level category selected, existing assets keep their categories and new assets remain uncategorized. A selected category applies to all imported assets in **Override All** mode, or only to uncategorized assets in **Fill Empty Only** mode. A newly entered category name reuses an existing category when the names match without case; otherwise it creates a category without a goal.

An explicit asset CSV currency changes the matched asset's stored currency. A blank currency preserves an existing asset's currency; a new asset remains blank and inherits the display currency when converted. An explicit cash-flow CSV currency is stored on the new operation; a blank one remains blank and inherits the display currency when converted. Bulk Entry's manually added asset rows start without a currency, and included rows require a choice before saving; new cash-flow rows start with the current display currency. New assets from a Bulk Entry CSV use a recognized CSV currency or remain blank until the user selects one.

### Duplicate and Replacement Policy

Two included asset rows with the same normalized name and resolved platform conflict. A matching **nonzero** asset value already recorded on the selected snapshot date also blocks import. A matching **zero** value is a placeholder and is replaced in place by asset CSV import; this does not permit silent replacement of a nonzero value. Zero values imported through the standard asset import remain subject to that placeholder rule on a later import.

Cash-flow descriptions must be unique within the included CSV rows and against existing operations on the target snapshot date, without case. There is no zero-amount replacement exception. Excluding a conflicting preview row triggers duplicate revalidation.

An import may create a snapshot or append records to one already present. Copy-forward applies only when creating a new date and only to selected platforms from the latest earlier snapshot; it avoids adding an asset already recorded on the target date. CSV import does not update category goals.

## Snapshot Lifecycle

A manually created snapshot uses a unique date no later than today. An empty start has no asset values. A Bulk Entry start seeds **only assets recorded in the latest snapshot before the chosen date**, grouped by platform; the user may add further platforms and assets. It is a draft until saved. The draft starts with no cash-flow operations, even when the prior snapshot had them.

Editing a saved snapshot may add, change, or remove directly recorded asset values and cash flows, subject to per-snapshot identity and value validation. Deleting a snapshot requires confirmation and removes its recorded values and cash flows; asset records remain. Category deletion requires its assets to be reassigned or removed first; asset deletion requires no recorded snapshot values. [`DataModel.md`](DataModel.md#relationships-and-integrity) owns the relationship and delete-rule details.

## Bulk Entry

For an included Bulk Entry asset row, a valid nonzero entered amount becomes its recorded value. An included row with a **blank pending value** saves a zero-value placeholder after confirmation. An **explicit zero** in a manual or CSV-filled Bulk Entry row blocks save until corrected or excluded. Unparseable nonempty value text also blocks save; it is not a pending zero. An included new asset with no supported currency also blocks save, even when its value is valid. An excluded row creates no snapshot value. At least one asset row must be included. New asset names must be nonempty; duplicate normalized names within one platform block save. New categories named on asset rows resolve case-insensitively when the draft is saved.

An included cash-flow row needs a nonempty description and a parseable amount; zero is valid for a cash flow. Descriptions must be unique within the saved snapshot. Excluded rows create no operation. Cash flows are portfolio-level and are never copied from the previous snapshot.

Bulk Entry CSV import changes **draft** rows rather than a saved snapshot. For assets, a valid CSV replaces the prior CSV-sourced values for its selected platform and fills matching draft rows by normalized name; rows for other platforms are skipped with feedback. A mismatched explicit currency on an existing saved asset is skipped with feedback. For a new asset, a recognized currency in the latest CSV takes precedence; a change from a user-selected currency is reported. A missing or unrecognized CSV currency leaves a new asset's currency blank unless the user already chose one for that asset in the same draft, including before reimport. A currency supplied only by an earlier CSV is not retained when the latest file omits it. Unrecognized codes produce a warning. For cash flows, a valid CSV replaces prior CSV-sourced rows across the whole draft and matches descriptions to existing draft rows. Parser or row-validation errors reject the replacement before prior CSV draft data changes; valid rows in a mixed-validity file are not applied separately. An imported asset value of zero becomes an explicit-zero draft row and prevents saving until resolved.

## Calculation and validation outcomes

Domain results distinguish **zero** (a valid numeric value or pending placeholder), **absent** (no row or goal), **invalid** (bad input or arithmetic), **unavailable** (missing required conversion or inputs), and **stale** (asset absent from the latest snapshot). An unavailable result must not be replaced with a mixed native-currency total or a compliant-looking goal state. Imported and edited data remain the source of truth; totals, shares, returns, and plans are recomputed from it. User-facing messages and controls belong in [`UserInterfaceDesign.md`](UserInterfaceDesign.md), while app-lock behavior belongs in [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md#app-lock-optional) and [`Architecture.md`](Architecture.md).
