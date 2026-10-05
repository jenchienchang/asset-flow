# Dashboard

The Dashboard is the first thing you see when you open AssetFlow — it's your home screen (found under **Overview > Dashboard** in the sidebar). It gives you a high-level summary of your entire portfolio at a glance.

## Summary Cards

At the top of the Dashboard, you'll find a set of summary cards:

- **Total Portfolio Value** — the hero card front and center, showing your portfolio's current total value.
- **Latest Snapshot Date** — the date of your most recent snapshot.
- **Asset Count** — how many assets are in your portfolio.
- **Cumulative TWR** — your all-time time-weighted return (the industry-standard measure of investment performance).
- **CAGR** — your compound annual growth rate, so you can compare your performance year-over-year.

## Period Performance Cards

Below the summary, you can select a time period — **1M**, **3M**, or **1Y** — to see how your portfolio performed over that window. Each performance card shows:

- **Growth Rate**: The simple percentage change in your portfolio's value. This includes the effect of any deposits or withdrawals you made.
- **Return Rate**: The cash-flow-adjusted return using the Modified Dietz method. This isolates your actual investment performance by accounting for when money was added or removed.
- A **date range subtitle** showing exactly which period is covered.

![Performance cards](../../assets/images/dashboard-performance.png)

!!! tip

    Not sure what the difference between Growth Rate and Return Rate is? Head over to the [Performance Metrics](performance-metrics.md) page for a plain-language explanation.

## Charts

The Dashboard includes several interactive charts to help you visualize your portfolio:

- **Category Allocation Pie Chart** — see how your portfolio is divided across categories. Click a category slice to jump directly to that category's detail page.
- **Portfolio Value Line Chart** — tracks your total portfolio value over time. Click any data point to navigate to that snapshot.
- **Cumulative TWR Line Chart** — shows your time-weighted returns over time, so you can see how your investment performance has trended.
- **Category Value Line Chart** — tracks how each category's value changes over time, making it easy to spot which parts of your portfolio are growing.

All charts support **hover tooltips** — just move your cursor over any data point to see the exact date and value.

![Dashboard overview](../../assets/images/app-overview.png)

## Recent Snapshots

At the bottom of the Dashboard, you'll find a list of your latest snapshots. Each entry shows the snapshot date, total value, and asset count. Click any row to jump straight to that snapshot's detail view.

## Empty State

If you haven't created any snapshots yet, the Dashboard will show a friendly prompt to help you get started — either by importing a CSV file or by creating your first snapshot manually.

![Empty dashboard](../../assets/images/dashboard-empty-state.png)

## Category minimums and portfolio composition

All assets, including protected and minimum-only categories, remain in total value and the pie chart. Percentage goals use the available allocation pool in Rebalancing; chart percentages show the whole portfolio.

## See also

- [Performance Metrics](performance-metrics.md): Understand what each metric means
- [Snapshots](snapshots.md): Learn how to create and manage snapshots
- [Categories](categories.md): Organize your assets by type
