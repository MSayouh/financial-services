# ZFI_IMLC_EXTRACT – Simulated Mock Run
**Date:** 2024-03-31 | **System:** ECC 6.0 EhP7 | **Client:** 100

---

## 1. Selection Screen Input

```
╔══════════════════════════════════════════════════════════════════╗
║  ZFI_IMLC_EXTRACT – IMLC Extraction Report for BPC Upload       ║
╠══════════════════════════════════════════════════════════════════╣
║  [Selection Criteria]                                            ║
║  Company Code    : 1000  to  ____                                ║
║  Fiscal Year     : 2024                                          ║
║  Posting Period  : 003   to  003                                 ║
║  GL Account      : 13006010  to  ____                            ║
║                    20003010  to  ____                            ║
║                                                                  ║
║  [BPC Parameters]                                                ║
║  Category        : ACTUAL_MGM                                    ║
║  Ledger          : 0L                                            ║
║  Posting Date    : (auto-derived from period)                    ║
║                                                                  ║
║  [Display Options]                                               ║
║  Include zero balances : [ ]                                     ║
║  Show exception only   : [ ]                                     ║
║  Test mode             : [X]                                     ║
║                                                                  ║
║  [Download Settings]                                             ║
║  Download file         : [ ]                                     ║
║  File path             : C:\TEMP\IMLC_EXTRACT.txt                ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## 2. Test Mode Information Messages (pop-up sequence)

```
[I] Date range derived: 01.03.2024 to 31.03.2024
[I] Step 2: Reading FI documents from BKPF/BSEG...
[I] 7 line items read from BSEG.
[W] ZFI_IMLC_ICMAP not in data dictionary – placeholder IC codes will be used.
[W] ZFI_IMLC_ACMAP not in data dictionary – placeholder account codes will be used.
[I] Opening balance computed for 2 GL accounts.
[I] 7 output rows built; 1 exceptions.
```

---

## 3. Simulated Source Data (what SAP tables contain)

### BKPF – Document Headers

| BUKRS | BELNR      | GJAHR | MONAT | BUDAT      | BLART | STBLG      | Note                         |
|-------|------------|-------|-------|------------|-------|------------|------------------------------|
| 1000  | 1800000001 | 2024  | 003   | 15.03.2024 | DR    |            | IC AR invoice – customer     |
| 1000  | 1800000002 | 2024  | 003   | 15.03.2024 | KR    |            | IC AP invoice – vendor       |
| 1000  | 1800000003 | 2024  | 003   | 18.03.2024 | DR    |            | IC AR invoice – customer     |
| 1000  | 1800000004 | 2024  | 003   | 22.03.2024 | SA    |            | Direct JE – NO customer/vendor ← EXCEPTION |
| 1000  | 1800000005 | 2024  | 003   | 25.03.2024 | KR    |            | IC AP invoice – vendor       |
| 1000  | 1800000006 | 2024  | 003   | 28.03.2024 | DR    |            | IC AR – no BPC IC mapping    |
| 1000  | 1800000099 | 2024  | 003   | 31.03.2024 | RV    | 1800000001 | REVERSED – excluded by STBLG |

### BSEG – Line Items (IMLC accounts only, after reversal exclusion)

| BUKRS | BELNR      | BUZEI | HKONT    | KUNNR   | LIFNR   | SHKZG | DMBTR      | SGTXT                        |
|-------|------------|-------|----------|---------|---------|-------|------------|------------------------------|
| 1000  | 1800000001 | 001   | 13006010 | 0001001 |         | S     | 50,000.00  | IC AR – ACME Singapore       |
| 1000  | 1800000002 | 001   | 20003010 |         | 0002001 | H     | 75,000.00  | IC AP – ACME Germany         |
| 1000  | 1800000003 | 001   | 13006010 | 0001002 |         | S     | 120,000.00 | IC AR – ACME Australia       |
| 1000  | 1800000004 | 001   | 13006010 |         |         | S     | 15,000.00  | Manual JE – IC recharge adj  |
| 1000  | 1800000005 | 001   | 20003010 |         | 0002002 | H     | 30,000.00  | IC AP – ACME France          |
| 1000  | 1800000006 | 001   | 13006010 | 0001003 |         | S     | 25,000.00  | IC AR – ACME Japan (no map)  |

### Prior-Period BSEG (Jan–Feb 2024, for opening balance)

| HKONT    | SHKZG | DMBTR      | Signed Amount |
|----------|-------|------------|---------------|
| 13006010 | S     | 200,000.00 | +200,000.00   |
| 20003010 | H     | 150,000.00 | -150,000.00   |

---

## 4. ALV Grid Output – Main View (Normal Mode)

> Columns split into two display bands for readability (same rows, same grid).

### Band A – BPC Dimensions

| # | TIME    | STMT_TYPE | CATEGORY   | ENTITY | CO_CD | GL_ACCOUNT | BPC_ACCOUNT | ACCT_DESC              |
|---|---------|-----------|------------|--------|-------|------------|-------------|------------------------|
| 1 | 2024.03 | IMLC      | ACTUAL_MGM | 1000   | 1000  | 13006010   | A_13006010  | IC Accounts Receivable |
| 2 | 2024.03 | IMLC      | ACTUAL_MGM | 1000   | 1000  | 13006010   | A_13006010  | IC Accounts Receivable |
| 3 | 2024.03 | IMLC      | ACTUAL_MGM | 1000   | 1000  | 13006010   | A_13006010  | IC Accounts Receivable |
| 4 | 2024.03 | IMLC      | ACTUAL_MGM | 1000   | 1000  | 20003010   | A_20003010  | IC Accounts Payable    |
| 5 | 2024.03 | IMLC      | ACTUAL_MGM | 1000   | 1000  | 20003010   | A_20003010  | IC Accounts Payable    |
| 6 | 2024.03 | IMLC      | ACTUAL_MGM | 1000   | 1000  | 13006010   | A_13006010  | IC Accounts Receivable |
| E | 2024.03 | IMLC      | ACTUAL_MGM | 1000   | 1000  | 13006010   | A_13006010  | IC Accounts Receivable |

> Row E = exception row (appended at bottom after normal rows).

### Band B – Partner, Amount, Audit & Validation

| # | CUSTOMER | VENDOR  | BPC_INTERCOMPANY      | CURR | COST_CTR | AMOUNT      | MVT_FLAG | DOC_NO     | ITM | POST_DATE  | TEXT                         | VAL_STATUS | VAL_DIFF | EXCEPTION_REASON      |
|---|----------|---------|-----------------------|------|----------|-------------|----------|------------|-----|------------|------------------------------|------------|----------|-----------------------|
| 1 | 0001001  |         | I_0001001             | LC   | CC_NONE  |  50,000.00  | F_INC    | 1800000001 | 001 | 15.03.2024 | IC AR – ACME Singapore       | OK         | 0.00     |                       |
| 2 | 0001002  |         | I_0001002             | LC   | CC_NONE  | 120,000.00  | F_INC    | 1800000003 | 001 | 18.03.2024 | IC AR – ACME Australia       | OK         | 0.00     |                       |
| 3 | 0001003  |         | MISSING_BPC_IC_MAPPING| LC   | CC_NONE  |  25,000.00  | F_INC    | 1800000006 | 001 | 28.03.2024 | IC AR – ACME Japan (no map)  | OK         | 0.00     |                       |
| 4 |          | 0002001 | I_0002001             | LC   | CC_NONE  | -75,000.00  | F_DEC    | 1800000002 | 001 | 15.03.2024 | IC AP – ACME Germany         | OK         | 0.00     |                       |
| 5 |          | 0002002 | I_0002002             | LC   | CC_NONE  | -30,000.00  | F_DEC    | 1800000005 | 001 | 25.03.2024 | IC AP – ACME France          | OK         | 0.00     |                       |
| 6 | 0001001  |         | I_0001001             | LC   | CC_NONE  |  50,000.00  | F_INC    | 1800000001 | 001 | 15.03.2024 | IC AR – ACME Singapore       | OK         | 0.00     |                       |
| E |          |         | MISSING_IC_PARTNER    | LC   | CC_NONE  |  15,000.00  | F_INC    | 1800000004 | 001 | 22.03.2024 | Manual JE – IC recharge adj  | FAILED     | 0.00     | MISSING_IC_PARTNER    |

> **Row 3**: Customer exists (0001003) but ZFI_IMLC_ICMAP has no entry → `MISSING_BPC_IC_MAPPING`.
> **Row E**: No KUNNR or LIFNR on BSEG → `MISSING_IC_PARTNER` exception.
> **VAL_STATUS OK on normal rows**: GL balance equation holds for the rows included in movement calc.
> **VAL_DIFF = 0**: Because closing is computed as opening + movement (self-consistent).

---

## 5. GL Balance Validation Summary

*(Internally computed in gt_gl_balance – not a separate screen but shown here for transparency)*

| CO_CD | GL_ACCOUNT | ACCT_DESC              | OPENING     | PERIOD_MOV   | CLOSING     | DIFF | STATUS |
|-------|------------|------------------------|-------------|--------------|-------------|------|--------|
| 1000  | 13006010   | IC Accounts Receivable | 200,000.00  | +195,000.00  | 395,000.00  | 0.00 | **OK** |
| 1000  | 20003010   | IC Accounts Payable    | -150,000.00 | -105,000.00  | -255,000.00 | 0.00 | **OK** |

**Movement calculation detail:**

| GL       | Doc        | IC Partner      | Amount      | Included in MOV? |
|----------|------------|-----------------|-------------|-----------------|
| 13006010 | 1800000001 | I_0001001       | +50,000.00  | ✓ Normal         |
| 13006010 | 1800000003 | I_0001002       | +120,000.00 | ✓ Normal         |
| 13006010 | 1800000006 | MISSING_BPC_MAP | +25,000.00  | ✓ Normal         |
| 13006010 | 1800000004 | MISSING_IC_PART | +15,000.00  | ✗ Exception      |
| 20003010 | 1800000002 | I_0002001       | -75,000.00  | ✓ Normal         |
| 20003010 | 1800000005 | I_0002002       | -30,000.00  | ✓ Normal         |

> **Important note**: The 15,000 direct journal entry (exception row) is **excluded** from the
> period movement total because it has no IC partner (row_type = EXCEPTION). The GL movement
> shown in SAP (e.g. from FS10N) will show 210,000 for 13006010, not 195,000. This is by
> design – the 15,000 must be business-corrected and re-posted with a customer/vendor before
> it can be included in the BPC IMLC upload. Consider surfacing this gap in the report header
> or a separate reconciliation row.

---

## 6. Exception-Only ALV (if "Show exception rows only" is ticked)

```
╔══════════════════════════════════════════════════════════════════════════════════════╗
║  IMLC Exceptions – Missing IC Partner                                               ║
╠═══════════╦════════════╦══════════╦══════╦═════════════╦════════╦═══════════════════╣
║ TIME      ║ GL ACCOUNT ║ AMOUNT   ║ CURR ║ DOC NUMBER  ║ ITMBR  ║ EXCEPTION REASON  ║
╠═══════════╬════════════╬══════════╬══════╬═════════════╬════════╬═══════════════════╣
║ 2024.03   ║ 13006010   ║ 15,000   ║ LC   ║ 1800000004  ║ 001    ║ MISSING_IC_PARTNER║
╠═══════════╬════════════╬══════════╬══════╬═════════════╬════════╬═══════════════════╣
║           ║ POST DATE  ║ 22.03.2024                                                 ║
║           ║ TEXT       ║ Manual JE – IC recharge adj                                ║
║           ║ DOC TYPE   ║ SA (General Ledger Posting)                                ║
║           ║ ACTION     ║ Business must re-post with correct intercompany customer   ║
╚═══════════╩════════════╩══════════╩══════╩═════════════╩════════╩═══════════════════╝

1 exception row.  Normal rows: 5.  Total SAP items read: 6 (1 reversed doc excluded).
```

---

## 7. Download File Preview (TAB-delimited, first 4 rows)

*What the file looks like when opened in Excel:*

```
TIME     STATEMENT_TYPE  CATEGORY    ENTITY  COMPANY_CODE  GL_ACCOUNT  BPC_ACCOUNT  ACCOUNT_DESC            CUSTOMER  VENDOR   BPC_INTERCOMPANY        CURRENCY  COST_CENTER  DETAIL_OP_UNIT  BD1     ...  AMOUNT      MOVEMENT_FLAG  DOCUMENT_NUMBER  LINE_ITEM  POSTING_DATE  TEXT                          VALIDATION_STATUS  EXCEPTION_REASON
2024.03  IMLC            ACTUAL_MGM  1000    1000          13006010    A_13006010   IC Accounts Receivable  0001001             I_0001001               LC        CC_NONE      DT_NONE         B_NONE  ...   50000.00   F_INC          1800000001       001        20240315      IC AR - ACME Singapore        OK
2024.03  IMLC            ACTUAL_MGM  1000    1000          13006010    A_13006010   IC Accounts Receivable  0001002             I_0001002               LC        CC_NONE      DT_NONE         B_NONE  ...  120000.00   F_INC          1800000003       001        20240318      IC AR - ACME Australia        OK
2024.03  IMLC            ACTUAL_MGM  1000    1000          13006010    A_13006010   IC Accounts Receivable  0001003             MISSING_BPC_IC_MAPPING  LC        CC_NONE      DT_NONE         B_NONE  ...   25000.00   F_INC          1800000006       001        20240328      IC AR - ACME Japan (no map)   OK
2024.03  IMLC            ACTUAL_MGM  1000    1000          20003010    A_20003010   IC Accounts Payable               0002001  I_0002001               LC        CC_NONE      DT_NONE         B_NONE  ...  -75000.00   F_DEC          1800000002       001        20240315      IC AP - ACME Germany          OK
2024.03  IMLC            ACTUAL_MGM  1000    1000          20003010    A_20003010   IC Accounts Payable               0002002  I_0002002               LC        CC_NONE      DT_NONE         B_NONE  ...  -30000.00   F_DEC          1800000005       001        20240325      IC AP - ACME France           OK
2024.03  IMLC            ACTUAL_MGM  1000    1000          13006010    A_13006010   IC Accounts Receivable            (blank)  MISSING_IC_PARTNER      LC        CC_NONE      DT_NONE         B_NONE  ...   15000.00   F_INC          1800000004       001        20240322      Manual JE - IC recharge adj   FAILED             MISSING_IC_PARTNER
```

*BD2 through BD8 all default to B_NONE (omitted above for width).*

---

## 8. Flag Summary Panel

```
╔══════════════════════════════════════════════════════════════╗
║  RUN SUMMARY                                                 ║
╠══════════════════════════════════════════════════════════════╣
║  Total SAP docs read           :   7                         ║
║  Reversed docs excluded        :   1  (STBLG filled)         ║
║  BSEG line items processed     :   6                         ║
║  Zero-amount lines skipped     :   0                         ║
║                                                              ║
║  Normal rows (extraction-ready):   5                         ║
║  Exception rows (action needed):   1                         ║
║  Total output rows in ALV      :   6                         ║
║                                                              ║
║  MISSING_IC_PARTNER            :   1  → doc 1800000004       ║
║  MISSING_BPC_IC_MAPPING        :   1  → customer 0001003     ║
║  MISSING_BPC_ACCOUNT_MAPPING   :   0  (placeholder active)   ║
║  VALIDATION_STATUS FAILED      :   1  → exception row        ║
║                                                              ║
║  GL accounts validated         :   2                         ║
║  Validation PASSED (diff = 0)  :   2                         ║
║  Validation FAILED (diff ≠ 0)  :   0                         ║
║                                                              ║
║  Download file                 :   NOT SELECTED              ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 9. Things to Review / Potential Amendments

Based on this mock output, consider the following before going live:

### A. Sign convention – confirm with BPC team
- Current: Debit = positive (F_INC), Credit = negative (F_DEC)
- IC AP row 4: -75,000 and row 5: -30,000
- BPC may expect AP balances posted as positive with a sign flip at the BPC model level.
- If so, flip the two branches in `FORM derive_signed_amount`.

### B. MISSING_BPC_ACCOUNT_MAPPING placeholder
- Because ZFI_IMLC_ACMAP does not exist, BPC_ACCOUNT shows `A_13006010` and `A_20003010`.
- BPC will reject these unless the BPC account dimension contains values like `A_13006010`.
- **Action**: Create ZFI_IMLC_ACMAP and map GL → proper BPC account codes (e.g. `3.13006010`).

### C. Exception row gap in GL movement total
- The 15,000 direct journal entry is excluded from the period movement calculation.
- SAP FS10N for 13006010 will show +210,000 movement; this report shows +195,000.
- This is intentional (exception rows cannot be IC-assigned) but must be clearly communicated.
- **Consider**: Adding a "GL vs Extracted" reconciliation row to the output footer.

### D. BPC_ENTITY defaults to company code
- Entity column shows `1000`.
- If BPC uses a different entity naming (e.g. `ACME_UK`, `ENT_1000`), add ZFI_IMLC_ENTITY table.

### E. MISSING_BPC_IC_MAPPING on customer 0001003
- Customer 0001001 and 0001002 generate placeholder `I_0001001` etc. (no table loaded).
- Customer 0001003 would show `MISSING_BPC_IC_MAPPING` once ZFI_IMLC_ICMAP is loaded
  but 0001003 has no entry in it. The placeholder path bypasses this for now.
- Once ZFI_IMLC_ICMAP is activated, all unmapped customers/vendors will surface properly.

### F. BD1–BD8 all default to B_NONE
- If BPC requires profit centre, segment, or trading partner in these dimensions,
  the mapping logic needs extending in `FORM map_to_bpc_dimensions`.

### G. TIME format
- Output: `2024.03` (year.period, zero-padded)
- Confirm BPC expects this format vs `2024003` or `03.2024`.

### H. Reversed document 1800000099
- Excluded correctly because STBLG = 1800000001.
- Confirm: should the original doc also be excluded or only the reversal marker?
  Currently only docs where STBLG IS NOT INITIAL are removed. If the original doc
  1800000001 had been posted in the same period and is reversed in the same period,
  both entries should cancel. SAP handles this through double-entry so the net is zero
  – but if the original was in a prior period and the reversal is in the current period,
  only the reversal row is excluded. Review this logic against your reversal policy.
