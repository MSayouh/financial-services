# SKILL: IMLC Extract – SAP ABAP Report (ZFI_IMLC_EXTRACT)

## Overview

This skill covers the deployment, configuration, and operation of `ZFI_IMLC_EXTRACT`, a
classic ABAP executable report that extracts Intercompany Movement Local Currency (IMLC)
data from SAP ERP/ECC for BPC upload preparation.

The report is **read-only**. It reads SAP FI tables directly (no API, OData, RFC, or external
integration). Output is an ALV grid and/or a TAB-delimited flat file suitable for BPC upload.

---

## Code Structure

| Section | Location | Purpose |
|---|---|---|
| Type definitions | `TYPES:` blocks | All internal structures and table types |
| Constants | `CONSTANTS:` | BPC dimension defaults, flag values, Z table names |
| Selection screen | `SELECTION-SCREEN` blocks | User input (company code, year, period, accounts) |
| INITIALIZATION | Event | Pre-populates default GL account range |
| AT SELECTION-SCREEN | Event | Input validation |
| START-OF-SELECTION | Event | Orchestrates 12 processing steps |
| `set_default_accounts` | FORM | Seeds s_hkont with 13006010, 20003010 |
| `validate_selection` | FORM | Guards required fields |
| `get_selection_dates` | FORM | Derives posting date range from GJAHR+POPER via T009B |
| `get_fi_documents` | FORM | SELECTs BKPF then BSEG; excludes reversed docs (STBLG) |
| `load_mapping_tables` | FORM | Loads ZFI_IMLC_ICMAP and ZFI_IMLC_ACMAP (placeholder SELECTs) |
| `load_account_descriptions` | FORM | Bulk reads SKAT before the main LOOP |
| `map_to_bpc_dimensions` | FORM | Core transform: FI item → BPC row; IC partner + sign |
| `derive_signed_amount` | FORM | Sign convention (debit+, credit-); reversible |
| `calculate_opening_balance` | FORM | Prior-period BSEG sum; GLT0/FAGLFLEXT option commented |
| `calculate_period_movement` | FORM | Aggregates period amounts per BUKRS+HKONT |
| `calculate_closing_balance` | FORM | Opening + Movement = Closing |
| `validate_gl_balance` | FORM | Flags non-zero diff as FAILED |
| `build_output` | FORM | Stamps validation status; merges exceptions |
| `display_alv` | FORM | CL_SALV_TABLE with REUSE_ALV_GRID_DISPLAY fallback |
| `display_alv_classic` | FORM | Fallback ALV via REUSE_ALV_GRID_DISPLAY |
| `download_file` | FORM | GUI_DOWNLOAD → TAB-delimited flat file |

---

## IMLC Account Scope

### Core IC accounts (pre-populated on selection screen)
| GL Account | Description |
|---|---|
| 13006010 | IC Accounts Receivable |
| 20003010 | IC Accounts Payable |

### Excluded by default (add manually if needed)
| GL Account | Description | Reason |
|---|---|---|
| 13006030 | IC AR Revaluation | FX revaluation; separate treatment in BPC |
| 20003020 | IC AP Revaluation | FX revaluation; separate treatment |
| 40000010 | Dividends proceeds | Not a movement account |

### Requiring business review (not pre-populated)
| GL Account | Description | Note |
|---|---|---|
| 50004231 | Impairment IC | May be posted without customer/vendor → exception |
| 13008035 | PUI – Impairment | Same risk |
| 13007065 | Impairment – Invest | Same risk |

---

## Z Table Setup

### ZFI_IMLC_ICMAP – IC Partner Mapping

| Field | Type | Key | Description |
|---|---|---|---|
| MANDT | CLNT | ✓ | Client |
| BUKRS | BUKRS | ✓ | Company code |
| KOART | KOART | ✓ | D = customer, K = vendor |
| KUNNR | KUNNR | ✓ | Customer number |
| LIFNR | LIFNR | ✓ | Vendor number |
| BPC_IC | CHAR20 | | BPC intercompany entity |
| VALID_FROM | DATS | | Validity start |
| VALID_TO | DATS | | Validity end |
| ACTIVE_FLAG | XFELD | | X = active |

**Activation**: Uncomment the SELECT block in `FORM load_mapping_tables` once the table is deployed.

### ZFI_IMLC_ACMAP – BPC Account Mapping

| Field | Type | Key | Description |
|---|---|---|---|
| MANDT | CLNT | ✓ | Client |
| BUKRS | BUKRS | ✓ | Company code |
| HKONT | SAKNR | ✓ | GL account |
| BPC_ACCOUNT | CHAR20 | | BPC account dimension |
| ACTIVE_FLAG | XFELD | | X = active |

**Activation**: Uncomment the SELECT block in `FORM load_mapping_tables` once the table is deployed.

### Placeholder behaviour (tables not yet deployed)
- IC partner → `I_<KUNNR>` or `I_<LIFNR>`
- BPC account → `A_<HKONT>`
- Missing IC partner (no KUNNR/LIFNR) → `MISSING_IC_PARTNER` exception row

---

## Exception Flags

| Flag | Column | Meaning |
|---|---|---|
| `MISSING_IC_PARTNER` | EXCEPTION_REASON | BSEG line has no KUNNR or LIFNR |
| `MISSING_BPC_IC_MAPPING` | BPC_INTERCOMPANY | KUNNR/LIFNR exists but no ZFI_IMLC_ICMAP entry |
| `MISSING_BPC_ACCOUNT_MAPPING` | BPC_ACCOUNT | HKONT exists but no ZFI_IMLC_ACMAP entry |
| `FAILED` | VALIDATION_STATUS | Opening + Movement ≠ Closing |

---

## Sign Convention

| SHKZG | Meaning | Signed Amount | MOVEMENT_FLAG |
|---|---|---|---|
| S (Soll) | Debit | Positive | F_INC |
| H (Haben) | Credit | Negative | F_DEC |

To reverse (BPC expects credit positive), swap the two branches in `FORM derive_signed_amount`.

---

## Opening Balance Logic

The report derives the opening balance by summing all reversed-excluded BSEG movements
in the same fiscal year for periods **before** the first selected period.

**Period 001 selected**: opening balance = prior-year carry-forward.  
Commented alternatives in `FORM calculate_opening_balance`:
- GLT0-KSLVT (ECC classic GL)
- FAGLFLEXT period 016 (New GL)

Activate the relevant block when the prior-year carry-forward is required.

---

## Testing Checklist

### Scenario 1 – Normal IC AR/AP posting with customer/vendor
- Select company code and fiscal year with posted IC AR/AP items.
- BSEG-KUNNR or BSEG-LIFNR is populated.
- Expected: ROW_TYPE = NORMAL, BPC_INTERCOMPANY = `I_<code>` or mapped value.
- Validation status = OK.

### Scenario 2 – Direct posting without customer/vendor
- Find a GL posting directly to 13006010 or 20003010 without customer/vendor.
- Expected: ROW_TYPE = EXCEPTION, BPC_INTERCOMPANY = MISSING_IC_PARTNER.
- Row appears in gt_exceptions; visible in main grid unless "exception only" mode.

### Scenario 3 – Missing BPC intercompany mapping
- Load ZFI_IMLC_ICMAP without an entry for a known customer.
- Expected: BPC_INTERCOMPANY = MISSING_BPC_IC_MAPPING.
- Exception reason column shows the flag.

### Scenario 4 – Missing BPC account mapping
- Load ZFI_IMLC_ACMAP without an entry for the tested GL account.
- Expected: BPC_ACCOUNT = MISSING_BPC_ACCOUNT_MAPPING.

### Scenario 5 – Validation passes (Opening + Movement = Closing)
- Single period extraction; no prior-period movements.
- Opening = 0, movement = sum of period items.
- Closing = movement.
- Diff = 0 → VALIDATION_STATUS = OK.

### Scenario 6 – Validation fails
- If GLT0/FAGLFLEXT carry-forward is activated and shows a different opening than BSEG,
  the diff will be non-zero → VALIDATION_STATUS = FAILED with diff_amount populated.

### Scenario 7 – Download file selected
- Tick "Download file", enter valid path (e.g. `C:\TEMP\IMLC_EXTRACT.txt`).
- After ALV display, GUI_DOWNLOAD produces a TAB-delimited file with header row.
- Verify row count = LINES(gt_output).

### Scenario 8 – ALV only mode
- Leave "Download file" unchecked.
- Report runs through all steps and opens ALV without file I/O.
- No error messages expected.

### Scenario 9 – Exception-only display
- Tick "Show exception rows only".
- ALV shows only MISSING_IC_PARTNER rows.
- Normal rows are suppressed from ALV but still included in the download file.

### Scenario 10 – Zero balance filter
- Leave "Include zero balances" unchecked (default).
- BSEG lines with DMBTR = 0 are skipped.
- Tick the checkbox to include them (e.g. for audit completeness).

---

## Deployment Steps

1. Create the report in SE38 as `ZFI_IMLC_EXTRACT`.
2. Paste the ABAP code from `abap/ZFI_IMLC_EXTRACT.abap`.
3. Check and activate (F2 / Ctrl+F3).
4. Maintain text elements in SE38 → Goto → Text Elements:
   - b01 = `Selection Criteria`
   - b02 = `BPC Parameters`
   - b03 = `Display Options`
   - b04 = `Download Settings`
5. Create Z tables (ZFI_IMLC_ICMAP, ZFI_IMLC_ACMAP) in SE11.
6. Activate the SELECT blocks in `FORM load_mapping_tables`.
7. Transport through DEV → QAS → PRD via standard workbench request.

---

## Assumptions

1. ECC 6.0 EhP6+ with classic GL (GLT0) as primary totals source.
2. `BSEG-DMBTR` is always positive; sign is carried by `SHKZG`.
3. Fiscal year variant has standard T009B entries per year (not ledger-specific).
4. One chart of accounts per company code range (first BUKRS used for SKAT lookup).
5. Reversed documents have `BKPF-STBLG` populated (standard SAP reversal FM behaviour).
6. Local currency = first currency on the document (DMBTR = local currency amount).
7. BPC TIME format is `YYYY.PP` (e.g. `2024.03`).
8. `p_categ` defaults to `ACTUAL_MGM`; override on selection screen for budget/forecast.
9. `p_ledgr` parameter is stored but not yet used in ECC classic GL reads; reserved for
   New GL FAGLFLEXT activation.
10. The report does not handle multi-currency documents; DMBTR is extracted as-is.
