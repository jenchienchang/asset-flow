# Categories

Categories group related assets and can have a percentage target, a minimum balance, both, or neither. Assets keep their own currencies; a category minimum has its own currency because the category can contain several currencies.

## Creating and editing goals

1. Open **Categories** and choose **+**, or select an existing category.
1. Enter the name and optionally a percentage between 0 and 100.
1. Enable **Minimum balance** to enter a nonnegative amount and select its currency in separate labeled rows. For existing categories, the default is the shared asset currency; mixed or empty categories default to your display currency.
1. Choose **Create** or **Save Changes**. Invalid input leaves the saved category unchanged.

Save Changes saves the name and both goals together. Return saves when the name, percentage, or minimum amount text field has focus; it is not a global Save key. You can also press ++cmd+s++. Revert restores all saved fields. Both buttons are disabled until you make edits. Leaving a category with edits offers Save, Discard, or Cancel. Information buttons explain the goal settings; the footer assesses the saved minimum at the latest snapshot, excluding unsaved edits.

The percentage and minimum are independent. Clear the percentage to remove it; disable the minimum to remove both its amount and currency. Changing the currency changes the denomination of the entered amount without converting it. Changing the app's display currency preserves your original goal.

If you open New Snapshot from the sidebar while editing a category, resolve the current edits first. Cancelling the snapshot date chooser returns to the same editor; any new edits still receive the usual Save, Discard, or Cancel protection.

![Save, Discard, and Cancel when leaving an edited category](../../../assets/images/category-unsaved-changes-en.png)

## Understanding your goals

A minimum means **keep at least this amount**, rather than an exact balance or progress milestone. Exceeding it is healthy and does not by itself produce a sell suggestion.

Percentage targets distribute the **available allocation pool** after protected balances are reserved. Categories without a percentage target keep their current balances. A minimum-only category retains its surplus or requires a top-up to its minimum. Uncategorized assets also remain protected.

Percentage targets must total 100% before percentage rebalancing suggestions are available. You can save them incrementally; minimum-only categories do not need a percentage. A specified 0% is different from leaving it blank: 0% targets the minimum, or zero if no minimum exists.

## Category list and details

![Category list with minimum balances met and below minimum](../../../assets/images/category-list-minimum-en.png)

![Category details with a percentage target and minimum balance](../../../assets/images/category-minimum-en.png)

Minimum amounts use the same secondary styling as other category metadata. Rows show current value, labelled Current and Effective target shares of the whole portfolio, requested pool percentage, asset count, and minimum status where applicable. A shortfall shows the amount missing in your display currency. Missing exchange rates show an unavailable status instead of zero. Empty categories can still have minimum requirements.

The warning indicator appears for **any minimum balance shortfall**, or when Current differs from Effective target by **more than 5 percentage points**. Hover over it for the applicable reasons. Pool target describes your configured preference; Effective target shows the result after minimums and protected balances are considered.

Minimum-only categories show an effective share when the plan is feasible and retain balances above their minimum. Categories without goals have no effective target. An unavailable or infeasible plan shows an em dash for effective targets; known minimum shortfalls still warn. Percentages are unavailable when the portfolio total is zero. Data changes and arriving exchange rates refresh the displays without discarding unsaved category edits.

Select a category to inspect its assets, edit goals, and view value and allocation history. Drag categories to change their order. A category can be deleted only after its assets have been reassigned.

## History and currencies

![Category minimum compared across three snapshots](../../../assets/images/category-minimum-history-en.png)

Value history includes an orange comparison with the **current minimum**, converted using each snapshot's exchange rates. Gaps mean a rate is missing. This comparison does not claim that today's minimum applied at that time. Historical values also use current category assignments.

Allocation history and the dashboard pie chart continue to show shares of the whole portfolio. A pool percentage is not a whole-portfolio chart reference. A missing goal rate does not hide otherwise valid asset values or portfolio charts.

## See also

- [Rebalancing](rebalancing.md): Calculate effective targets and understand shortfalls
- [Assets](assets.md): Assign investments to categories
- [Currencies](../reference/currencies.md): Snapshot conversion and missing rates
