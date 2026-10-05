# CSV Format

Reference for the CSV file formats accepted by AssetFlow's import tool.

## Asset CSV

### Required Columns

| Column           | Description                                                             |
| ---------------- | ----------------------------------------------------------------------- |
| **Asset Name**   | The name of the asset (e.g., "AAPL", "Vanguard Total Stock Market ETF") |
| **Market Value** | The current market value as a number (e.g., 15000, 1234.56)             |

### Optional Columns

| Column       | Description                                                                                  |
| ------------ | -------------------------------------------------------------------------------------------- |
| **Platform** | The platform/brokerage where the asset is held                                               |
| **Currency** | Three-letter currency code (e.g., USD, EUR, TWD). Defaults to your main currency if omitted. |

### Example

```csv
Asset Name,Market Value,Platform,Currency
AAPL,15000,Interactive Brokers,USD
VTI,28000,Interactive Brokers,USD
Bitcoin,5000,Coinbase,USD
台積電,120000,永豐金證券,TWD
```

---

## Cash Flow CSV

### Required Columns

| Column          | Description                                                                  |
| --------------- | ---------------------------------------------------------------------------- |
| **Description** | A label for the cash flow (e.g., "Monthly savings", "Dividend reinvestment") |
| **Amount**      | The amount as a number. Positive = deposit, negative = withdrawal.           |

### Optional Columns

| Column       | Description                                                            |
| ------------ | ---------------------------------------------------------------------- |
| **Currency** | Three-letter currency code. Defaults to your main currency if omitted. |

### Example

```csv
Description,Amount,Currency
Monthly savings,5000,USD
Emergency withdrawal,-2000,USD
年終獎金投入,100000,TWD
```

---

## Common Issues

| Issue                     | Cause                                                | Solution                                          |
| ------------------------- | ---------------------------------------------------- | ------------------------------------------------- |
| "Missing required column" | CSV doesn't have Asset Name or Market Value header   | Check column headers match exactly                |
| "Duplicate asset"         | Same Asset Name + Platform combination appears twice | Remove duplicate rows or change the platform      |
| "Unparsable value"        | Market Value contains non-numeric characters         | Remove currency symbols, commas in numbers        |
| "Unsupported currency"    | Currency code not recognized                         | Use standard ISO 4217 codes (e.g., USD, EUR, TWD) |

!!! tip

    Export your spreadsheet as UTF-8 CSV to ensure special characters (like Chinese) are handled correctly.

## Goals and CSV imports

Ordinary asset/cash-flow CSV imports do not set or change category goals. The category CSV inside a ZIP backup is a separate internal format; v4 includes minimum amount and currency.

## See also

- [Import CSV](../guide/import-csv.md): Step-by-step guide for importing data
- [Currencies & Exchange Rates](currencies.md): Supported currencies and how exchange rates work
