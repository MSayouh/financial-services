*&---------------------------------------------------------------------*
*& Report  ZFI_IMLC_EXTRACT
*& IMLC – Intercompany Movement Local Currency Extraction Report
*&
*& Purpose : Extract IC FI line items from BKPF/BSEG and prepare
*&           a BPC-style output file for intercompany consolidation.
*&
*& Design  : Read-only extraction.  No posting, no data modification.
*&           All amounts in local currency (DMBTR).
*&           Debit = positive (F_INC), Credit = negative (F_DEC).
*&           Reverse this in FORM derive_signed_amount if BPC requires
*&           the opposite sign convention.
*&
*& Z Tables: ZFI_IMLC_ICMAP  – IC partner → BPC_IC mapping
*&           ZFI_IMLC_ACMAP  – GL account  → BPC_ACCOUNT mapping
*&           Both tables are optional; the report runs without them
*&           using placeholder values (I_<kunnr>, A_<hkont>).
*&           See documentation section at the bottom for DDic specs.
*&
*& ECC compat: Tested against ECC 6.0 EhP7 classic GL (GLT0).
*&             New GL (FAGLFLEXT) opening-balance path is provided
*&             as a commented alternative in FORM calculate_opening_balance.
*&
*& Transport: Assign to a Z development package; no automatic transport.
*& Author  : [Set before transport to production]
*& Date    : 2026-05-16
*& Version : 1.0
*&---------------------------------------------------------------------*
REPORT zfi_imlc_extract
  NO STANDARD PAGE HEADING
  LINE-SIZE 255.

*&---------------------------------------------------------------------*
*& TYPE DEFINITIONS
*&---------------------------------------------------------------------*

"--- BPC-style output row (normal movement + exception rows) -----------
TYPES: BEGIN OF ty_output,
  " BPC dimensions
  time               TYPE char10,   " YYYY.PP  e.g. 2024.03
  statement_type     TYPE char10,   " IMLC (constant)
  category           TYPE char20,   " ACTUAL_MGM or overridden by selection
  entity             TYPE char20,   " BPC entity (defaults to company code)
  company_code       TYPE bukrs,
  gl_account         TYPE hkont,
  bpc_account        TYPE char20,   " From ZFI_IMLC_ACMAP or A_<hkont>
  account_desc       TYPE char50,   " Short text from SKAT
  customer           TYPE kunnr,
  vendor             TYPE lifnr,
  bpc_intercompany   TYPE char20,   " From ZFI_IMLC_ICMAP or I_<kunnr/lifnr>
  currency           TYPE char10,   " LC (constant)
  cost_center        TYPE char20,   " KOSTL or CC_NONE
  detail_op_unit     TYPE char20,   " DT_NONE (placeholder)
  bd1                TYPE char20,   " B_NONE unless mapping added
  bd2                TYPE char20,
  bd3                TYPE char20,
  bd4                TYPE char20,
  bd5                TYPE char20,
  bd6                TYPE char20,
  bd7                TYPE char20,
  bd8                TYPE char20,
  " Financials
  amount             TYPE dmbtr,    " Signed: debit + / credit -
  movement_flag      TYPE char10,   " F_INC (>=0) or F_DEC (<0)
  " Audit trail
  document_number    TYPE belnr_d,
  line_item          TYPE buzei,
  posting_date       TYPE budat,
  text               TYPE sgtxt,
  " Validation / quality
  validation_status  TYPE char20,   " OK / FAILED
  exception_reason   TYPE char50,   " MISSING_IC_PARTNER etc.
  diff_amount        TYPE dmbtr,    " Opening+Movement-Closing (0 = OK)
  " Internal (hidden in ALV)
  row_type           TYPE char10,   " NORMAL / EXCEPTION
END OF ty_output.

TYPES: tt_output TYPE STANDARD TABLE OF ty_output.

"--- Working structure for FI line items (BKPF + BSEG joined) ---------
TYPES: BEGIN OF ty_fi_item,
  bukrs  TYPE bukrs,
  belnr  TYPE belnr_d,
  gjahr  TYPE gjahr,
  buzei  TYPE buzei,
  budat  TYPE budat,
  bldat  TYPE bldat,
  monat  TYPE monat,    " posting period
  blart  TYPE blart,
  xblnr  TYPE xblnr,
  stblg  TYPE bkpf-stblg,  " reversal document (blank = not reversed)
  hkont  TYPE hkont,
  kunnr  TYPE kunnr,
  lifnr  TYPE lifnr,
  shkzg  TYPE shkzg,
  dmbtr  TYPE dmbtr,
  sgtxt  TYPE sgtxt,
  kostl  TYPE kostl,
END OF ty_fi_item.

TYPES: tt_fi_item TYPE STANDARD TABLE OF ty_fi_item.

"--- GL balance per company code + account for validation -------------
TYPES: BEGIN OF ty_gl_balance,
  bukrs      TYPE bukrs,
  hkont      TYPE hkont,
  gjahr      TYPE gjahr,
  open_bal   TYPE dmbtr,
  period_mov TYPE dmbtr,
  close_bal  TYPE dmbtr,
  diff       TYPE dmbtr,
  val_status TYPE char10,   " OK / FAILED
END OF ty_gl_balance.

TYPES: tt_gl_balance TYPE STANDARD TABLE OF ty_gl_balance.

"--- Opening balance aggregation per account --------------------------
TYPES: BEGIN OF ty_open_bal,
  bukrs  TYPE bukrs,
  racct  TYPE hkont,
  ryear  TYPE gjahr,
  amount TYPE dmbtr,
END OF ty_open_bal.

TYPES: tt_open_bal TYPE STANDARD TABLE OF ty_open_bal.

"--- IC partner mapping (mirrors ZFI_IMLC_ICMAP) ---------------------
TYPES: BEGIN OF ty_ic_map,
  bukrs      TYPE bukrs,
  koart      TYPE koart,    " D=customer, K=vendor
  kunnr      TYPE kunnr,
  lifnr      TYPE lifnr,
  bpc_ic     TYPE char20,
  valid_from TYPE dats,
  valid_to   TYPE dats,
  active_flag TYPE xfeld,
END OF ty_ic_map.

TYPES: tt_ic_map TYPE STANDARD TABLE OF ty_ic_map.

"--- BPC account mapping (mirrors ZFI_IMLC_ACMAP) --------------------
TYPES: BEGIN OF ty_ac_map,
  bukrs       TYPE bukrs,
  hkont       TYPE hkont,
  bpc_account TYPE char20,
  active_flag TYPE xfeld,
END OF ty_ac_map.

TYPES: tt_ac_map TYPE STANDARD TABLE OF ty_ac_map.

"--- Account description cache (from SKAT) ----------------------------
TYPES: BEGIN OF ty_acct_desc,
  saknr TYPE saknr,
  txt50 TYPE txt50,
END OF ty_acct_desc.

TYPES: tt_acct_desc TYPE STANDARD TABLE OF ty_acct_desc.

*&---------------------------------------------------------------------*
*& CONSTANTS
*&---------------------------------------------------------------------*

CONSTANTS:
  gc_imlc       TYPE char10 VALUE 'IMLC',
  gc_lc         TYPE char10 VALUE 'LC',
  gc_cc_none    TYPE char20 VALUE 'CC_NONE',
  gc_dt_none    TYPE char20 VALUE 'DT_NONE',
  gc_b_none     TYPE char20 VALUE 'B_NONE',
  gc_f_inc      TYPE char10 VALUE 'F_INC',
  gc_f_dec      TYPE char10 VALUE 'F_DEC',
  gc_ok         TYPE char20 VALUE 'OK',
  gc_failed     TYPE char20 VALUE 'FAILED',
  gc_normal     TYPE char10 VALUE 'NORMAL',
  gc_exception  TYPE char10 VALUE 'EXCEPTION',
  gc_miss_ic    TYPE char50 VALUE 'MISSING_IC_PARTNER',
  gc_miss_bpc   TYPE char50 VALUE 'MISSING_BPC_IC_MAPPING',
  gc_miss_acct  TYPE char50 VALUE 'MISSING_BPC_ACCOUNT_MAPPING',
  gc_icmap_tab  TYPE char30 VALUE 'ZFI_IMLC_ICMAP',
  gc_acmap_tab  TYPE char30 VALUE 'ZFI_IMLC_ACMAP'.

*&---------------------------------------------------------------------*
*& GLOBAL DATA
*&---------------------------------------------------------------------*

DATA:
  gt_fi_items   TYPE tt_fi_item,
  gt_output     TYPE tt_output,
  gt_exceptions TYPE tt_output,
  gt_gl_balance TYPE tt_gl_balance,
  gt_ic_map     TYPE tt_ic_map,
  gt_ac_map     TYPE tt_ac_map,
  gt_open_bal   TYPE tt_open_bal,
  gt_acct_desc  TYPE tt_acct_desc,
  gv_ktopl      TYPE ktopl,          " chart of accounts from T001
  gv_date_from  TYPE budat,
  gv_date_to    TYPE budat,
  gv_tabix      TYPE sytabix.

*&---------------------------------------------------------------------*
*& SELECTION SCREEN
*&---------------------------------------------------------------------*

SELECTION-SCREEN BEGIN OF BLOCK blk1 WITH FRAME TITLE TEXT-b01.
  SELECT-OPTIONS:
    s_bukrs FOR bkpf-bukrs OBLIGATORY,
    s_gjahr FOR bkpf-gjahr OBLIGATORY NO INTERVALS,
    s_poper FOR bkpf-monat,
    s_hkont FOR bkpf-hkont.
SELECTION-SCREEN END OF BLOCK blk1.

SELECTION-SCREEN BEGIN OF BLOCK blk2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS:
    p_categ TYPE char20        DEFAULT 'ACTUAL_MGM',
    p_ledgr TYPE char2         DEFAULT '0L'.  " ledger (0L = leading; ECC: leave blank)
  SELECT-OPTIONS:
    s_budat FOR bkpf-budat.    " Optional override; derived from GJAHR/POPER if blank
SELECTION-SCREEN END OF BLOCK blk2.

SELECTION-SCREEN BEGIN OF BLOCK blk3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS:
    p_zero  AS CHECKBOX DEFAULT ' ',  " Include zero-amount lines
    p_excep AS CHECKBOX DEFAULT ' ',  " Show exception rows only
    p_test  AS CHECKBOX DEFAULT ' '.  " Test mode – informational messages
SELECTION-SCREEN END OF BLOCK blk3.

SELECTION-SCREEN BEGIN OF BLOCK blk4 WITH FRAME TITLE TEXT-b04.
  PARAMETERS:
    p_down  AS CHECKBOX DEFAULT ' ',
    p_file  TYPE string LOWER CASE DEFAULT 'C:\TEMP\IMLC_EXTRACT.txt'.
SELECTION-SCREEN END OF BLOCK blk4.

*&---------------------------------------------------------------------*
*& INITIALIZATION
*&---------------------------------------------------------------------*

INITIALIZATION.
  " Pre-populate GL account range with IMLC core accounts.
  " Business may clear and enter their own range on the selection screen.
  " Excluded accounts (13006030, 20003020, 40000010) are NOT pre-populated.
  " Accounts needing business review (50004231, 13008035, 13007065) are
  " NOT pre-populated because their IC assignment depends on posting method.
  PERFORM set_default_accounts.

  " Selection screen text elements – maintain in SE38 under Text Elements
  " b01 = 'Selection Criteria'
  " b02 = 'BPC Parameters'
  " b03 = 'Display Options'
  " b04 = 'Download Settings'
  TEXT-b01 = 'Selection Criteria'.
  TEXT-b02 = 'BPC Parameters'.
  TEXT-b03 = 'Display Options'.
  TEXT-b04 = 'Download Settings'.

*&---------------------------------------------------------------------*
*& AT SELECTION-SCREEN
*&---------------------------------------------------------------------*

AT SELECTION-SCREEN.
  PERFORM validate_selection.

*&---------------------------------------------------------------------*
*& START-OF-SELECTION
*&---------------------------------------------------------------------*

START-OF-SELECTION.

  " 1. Derive posting date range from fiscal year / period
  PERFORM get_selection_dates.

  " 2. Read FI line items from BKPF + BSEG
  PERFORM get_fi_documents.

  IF gt_fi_items IS INITIAL.
    MESSAGE 'No FI documents found for the selected criteria.' TYPE 'I'.
    RETURN.
  ENDIF.

  " 3. Load Z mapping tables (IC partner + BPC account)
  PERFORM load_mapping_tables.

  " 4. Pre-load account descriptions from SKAT
  PERFORM load_account_descriptions.

  " 5. Map each FI item to BPC output row (includes IC partner derivation)
  PERFORM map_to_bpc_dimensions.

  " 6. Calculate opening balance (prior periods in same fiscal year)
  PERFORM calculate_opening_balance.

  " 7. Aggregate period movements per GL account
  PERFORM calculate_period_movement.

  " 8. Compute closing balance = opening + movement
  PERFORM calculate_closing_balance.

  " 9. Validate: opening + movement = closing
  PERFORM validate_gl_balance.

  " 10. Stamp validation status onto output rows; merge exception rows
  PERFORM build_output.

  " 11. Display ALV grid
  IF p_excep = abap_true.
    PERFORM display_alv USING gc_exception.
  ELSE.
    PERFORM display_alv USING gc_normal.
  ENDIF.

  " 12. Download file (only when checkbox selected)
  IF p_down = abap_true.
    PERFORM download_file.
  ENDIF.

*&---------------------------------------------------------------------*
*& FORM set_default_accounts
*&---------------------------------------------------------------------*

FORM set_default_accounts.

  " Core IMLC accounts defaulted at startup.
  " User can clear and adjust on the selection screen.
  IF s_hkont IS INITIAL.
    DATA: ls_range LIKE LINE OF s_hkont.

    ls_range-sign   = 'I'.
    ls_range-option = 'EQ'.

    ls_range-low = '13006010'.   " IC Accounts Receivable
    APPEND ls_range TO s_hkont.

    ls_range-low = '20003010'.   " IC Accounts Payable
    APPEND ls_range TO s_hkont.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM validate_selection
*&---------------------------------------------------------------------*

FORM validate_selection.

  IF s_gjahr IS INITIAL.
    MESSAGE 'Fiscal year is required.' TYPE 'E'.
  ENDIF.

  " Single-value fiscal year (NO INTERVALS on s_gjahr)
  IF s_gjahr-low IS INITIAL.
    MESSAGE 'Enter a fiscal year.' TYPE 'E'.
  ENDIF.

  IF p_down = abap_true AND p_file IS INITIAL.
    MESSAGE 'Enter a file path for the download.' TYPE 'E'.
  ENDIF.

  IF s_hkont IS INITIAL.
    MESSAGE 'No GL accounts selected – all FI accounts will be read (may be slow).' TYPE 'W'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM get_selection_dates
*& Derive posting date range from GJAHR + POPER using T009B.
*& If s_budat is already populated (user override) this FORM returns
*& immediately without touching s_budat.
*&---------------------------------------------------------------------*

FORM get_selection_dates.

  DATA:
    lt_t009b   TYPE STANDARD TABLE OF t009b,
    ls_t009b   TYPE t009b,
    ls_prev    TYPE t009b,
    ls_budat   LIKE LINE OF s_budat,
    lv_periv   TYPE periv,
    lv_gjahr   TYPE gjahr,
    lv_min_p   TYPE poper,
    lv_max_p   TYPE poper,
    lv_prev_p  TYPE i.

  " User-supplied date range takes full precedence
  IF s_budat IS NOT INITIAL.
    RETURN.
  ENDIF.

  lv_gjahr = s_gjahr-low.

  " Read fiscal year variant for the first company code in the range
  SELECT SINGLE periv
    INTO lv_periv
    FROM t001
    WHERE bukrs = s_bukrs-low.

  IF sy-subrc <> 0.
    MESSAGE |Cannot derive fiscal year variant for { s_bukrs-low }. Enter posting date manually.|
      TYPE 'W'.
    RETURN.
  ENDIF.

  " Determine the period boundaries from the selection
  IF s_poper IS INITIAL.
    lv_min_p = '001'.
    lv_max_p = '012'.
  ELSE.
    lv_min_p = s_poper-low.
    lv_max_p = COND #(
      WHEN s_poper-high IS NOT INITIAL THEN s_poper-high
      ELSE                                  s_poper-low ).
  ENDIF.

  " Read T009B: fiscal-year-variant period boundaries
  " BUTAG = last calendar day of each period
  SELECT *
    INTO TABLE lt_t009b
    FROM t009b
    WHERE periv = lv_periv
      AND bdatj = lv_gjahr.

  IF sy-subrc <> 0.
    " Fallback: calendar-month interpretation (period 1 = January, etc.)
    CONCATENATE lv_gjahr lv_min_p(2) '01' INTO gv_date_from.
    CALL FUNCTION 'LAST_DAY_OF_MONTHS'
      EXPORTING  day_in            = gv_date_from
      IMPORTING  last_day_of_month = gv_date_to
      EXCEPTIONS OTHERS            = 1.
    IF sy-subrc <> 0.
      CONCATENATE lv_gjahr '1231' INTO gv_date_to.
    ENDIF.
  ELSE.
    " Start date: day after the end of period (lv_min_p - 1)
    lv_prev_p = lv_min_p - 1.
    IF lv_prev_p <= 0.
      " First period of the fiscal year: start = first day of year
      " T009B does not store the opening day directly; approximate from
      " the BDATJ and the fiscal year variant's offset if calendar year.
      " Safe default for standard calendar fiscal year:
      CONCATENATE lv_gjahr '0101' INTO gv_date_from.
    ELSE.
      READ TABLE lt_t009b INTO ls_prev
        WITH KEY poper = lv_prev_p.
      IF sy-subrc = 0.
        gv_date_from = ls_prev-butag + 1.
      ELSE.
        CONCATENATE lv_gjahr '0101' INTO gv_date_from.
      ENDIF.
    ENDIF.

    " End date: last day of lv_max_p
    READ TABLE lt_t009b INTO ls_t009b
      WITH KEY poper = lv_max_p.
    IF sy-subrc = 0.
      gv_date_to = ls_t009b-butag.
    ELSE.
      CONCATENATE lv_gjahr '1231' INTO gv_date_to.
    ENDIF.
  ENDIF.

  " Populate s_budat so the SELECT in get_fi_documents can use a range
  ls_budat-sign   = 'I'.
  ls_budat-option = 'BT'.
  ls_budat-low    = gv_date_from.
  ls_budat-high   = gv_date_to.
  APPEND ls_budat TO s_budat.

  IF p_test = abap_true.
    MESSAGE |Date range derived: { gv_date_from } to { gv_date_to }| TYPE 'I'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM get_fi_documents
*& Read BKPF headers then BSEG line items for IMLC GL accounts.
*& Reversed documents (STBLG filled) are excluded from extraction.
*&---------------------------------------------------------------------*

FORM get_fi_documents.

  DATA:
    lt_bkpf  TYPE STANDARD TABLE OF bkpf,
    ls_bkpf  TYPE bkpf,
    lt_bseg  TYPE STANDARD TABLE OF bseg,
    ls_bseg  TYPE bseg,
    ls_item  TYPE ty_fi_item.

  IF p_test = abap_true.
    MESSAGE 'Step 2: Reading FI documents from BKPF/BSEG...' TYPE 'I'.
  ENDIF.

  CLEAR gt_fi_items.

  " --- Read document headers ----------------------------------------
  " MONAT = posting period in BKPF; filter both by period and budat
  " to ensure alignment with the derived date range.
  SELECT belnr bukrs gjahr budat bldat monat blart xblnr stblg
    INTO CORRESPONDING FIELDS OF TABLE lt_bkpf
    FROM bkpf
    WHERE bukrs IN s_bukrs
      AND gjahr IN s_gjahr
      AND budat IN s_budat
      AND monat IN s_poper.

  IF sy-subrc <> 0 OR lt_bkpf IS INITIAL.
    MESSAGE 'No document headers found for the selected criteria.' TYPE 'I'.
    RETURN.
  ENDIF.

  " Exclude reversed/cancelled documents.
  " A non-blank STBLG means this document has been reversed by STBLG.
  " We remove it so it does not inflate movements.
  DELETE lt_bkpf WHERE stblg IS NOT INITIAL.

  IF lt_bkpf IS INITIAL.
    MESSAGE 'All documents in the selection have been reversed – nothing to extract.' TYPE 'I'.
    RETURN.
  ENDIF.

  " --- Read BSEG line items for IMLC GL accounts only ---------------
  " FOR ALL ENTRIES is safe here: lt_bkpf is confirmed non-initial above.
  SELECT belnr bukrs gjahr buzei hkont kunnr lifnr shkzg dmbtr sgtxt kostl
    INTO CORRESPONDING FIELDS OF TABLE lt_bseg
    FROM bseg
    FOR ALL ENTRIES IN lt_bkpf
    WHERE bukrs = lt_bkpf-bukrs
      AND belnr = lt_bkpf-belnr
      AND gjahr = lt_bkpf-gjahr
      AND hkont IN s_hkont.

  IF sy-subrc <> 0 OR lt_bseg IS INITIAL.
    MESSAGE 'No GL line items found for the selected IMLC accounts.' TYPE 'I'.
    RETURN.
  ENDIF.

  " --- Join BSEG with BKPF to produce the working table gt_fi_items -
  " Use SORT + binary READ to avoid nested loops with linear scan.
  SORT lt_bkpf BY bukrs belnr gjahr.

  LOOP AT lt_bseg INTO ls_bseg.
    READ TABLE lt_bkpf INTO ls_bkpf
      WITH KEY bukrs = ls_bseg-bukrs
               belnr = ls_bseg-belnr
               gjahr = ls_bseg-gjahr
      BINARY SEARCH.

    IF sy-subrc = 0.
      CLEAR ls_item.
      ls_item-bukrs = ls_bseg-bukrs.
      ls_item-belnr = ls_bseg-belnr.
      ls_item-gjahr = ls_bseg-gjahr.
      ls_item-buzei = ls_bseg-buzei.
      ls_item-budat = ls_bkpf-budat.
      ls_item-bldat = ls_bkpf-bldat.
      ls_item-monat = ls_bkpf-monat.
      ls_item-blart = ls_bkpf-blart.
      ls_item-xblnr = ls_bkpf-xblnr.
      ls_item-stblg = ls_bkpf-stblg.
      ls_item-hkont = ls_bseg-hkont.
      ls_item-kunnr = ls_bseg-kunnr.
      ls_item-lifnr = ls_bseg-lifnr.
      ls_item-shkzg = ls_bseg-shkzg.
      ls_item-dmbtr = ls_bseg-dmbtr.
      ls_item-sgtxt = ls_bseg-sgtxt.
      ls_item-kostl = ls_bseg-kostl.
      APPEND ls_item TO gt_fi_items.
    ENDIF.
  ENDLOOP.

  IF p_test = abap_true.
    MESSAGE |{ LINES( gt_fi_items ) } line items read from BSEG.| TYPE 'I'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM load_mapping_tables
*& Attempt to load ZFI_IMLC_ICMAP and ZFI_IMLC_ACMAP.
*& If the tables do not exist, gt_ic_map / gt_ac_map remain empty and
*& placeholder IC codes are used in map_to_bpc_dimensions.
*&---------------------------------------------------------------------*

FORM load_mapping_tables.

  DATA: lv_tabname TYPE dd02l-tabname.

  " ------------------------------------------------------------------
  " IC PARTNER MAPPING  →  ZFI_IMLC_ICMAP
  " Recommended DDic definition:
  "   MANDT  CLNT  (key)
  "   BUKRS  BUKRS (key)
  "   KOART  KOART (key)  'D' = customer, 'K' = vendor
  "   KUNNR  KUNNR (key)
  "   LIFNR  LIFNR (key)
  "   BPC_IC CHAR20
  "   VALID_FROM DATS
  "   VALID_TO   DATS
  "   ACTIVE_FLAG XFELD
  " ------------------------------------------------------------------
  SELECT SINGLE tabname
    INTO lv_tabname
    FROM dd02l
    WHERE tabname  = gc_icmap_tab
      AND tabstate = 'A'.            " A = active in data dictionary

  IF sy-subrc = 0.
    " *---------------------------------------------------------------*
    " * Activate by removing the comment markers below once           *
    " * ZFI_IMLC_ICMAP has been created and transported.              *
    " *---------------------------------------------------------------*
    "SELECT bukrs koart kunnr lifnr bpc_ic valid_from valid_to active_flag
    "  INTO CORRESPONDING FIELDS OF TABLE gt_ic_map
    "  FROM zfi_imlc_icmap
    "  WHERE bukrs      IN s_bukrs
    "    AND active_flag = abap_true
    "    AND valid_from <= sy-datum
    "    AND valid_to   >= sy-datum.

    IF p_test = abap_true.
      MESSAGE |IC mapping table { gc_icmap_tab } found; activate SELECT in load_mapping_tables.|
        TYPE 'I'.
    ENDIF.
  ELSE.
    IF p_test = abap_true.
      MESSAGE |{ gc_icmap_tab } not in data dictionary – placeholder IC codes will be used.|
        TYPE 'W'.
    ENDIF.
  ENDIF.

  " ------------------------------------------------------------------
  " BPC ACCOUNT MAPPING  →  ZFI_IMLC_ACMAP
  " Recommended DDic definition:
  "   MANDT       CLNT  (key)
  "   BUKRS       BUKRS (key)
  "   HKONT       SAKNR (key)
  "   BPC_ACCOUNT CHAR20
  "   ACTIVE_FLAG XFELD
  " ------------------------------------------------------------------
  SELECT SINGLE tabname
    INTO lv_tabname
    FROM dd02l
    WHERE tabname  = gc_acmap_tab
      AND tabstate = 'A'.

  IF sy-subrc = 0.
    "SELECT bukrs hkont bpc_account active_flag
    "  INTO CORRESPONDING FIELDS OF TABLE gt_ac_map
    "  FROM zfi_imlc_acmap
    "  WHERE bukrs      IN s_bukrs
    "    AND active_flag = abap_true.
    IF p_test = abap_true.
      MESSAGE |Account mapping table { gc_acmap_tab } found; activate SELECT in load_mapping_tables.|
        TYPE 'I'.
    ENDIF.
  ELSE.
    IF p_test = abap_true.
      MESSAGE |{ gc_acmap_tab } not in data dictionary – placeholder account codes will be used.|
        TYPE 'W'.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM load_account_descriptions
*& Bulk-reads account short texts from SKAT to avoid SELECT in LOOP.
*& Also reads T001-KTOPL for the chart of accounts.
*&---------------------------------------------------------------------*

FORM load_account_descriptions.

  DATA: lt_hkont  TYPE STANDARD TABLE OF hkont,
        ls_hkont  TYPE hkont,
        ls_desc   TYPE ty_acct_desc,
        lv_ktopl  TYPE ktopl.

  CLEAR gt_acct_desc.

  " Chart of accounts from T001 (needed for SKAT key)
  SELECT SINGLE ktopl
    INTO lv_ktopl
    FROM t001
    WHERE bukrs = s_bukrs-low.

  gv_ktopl = lv_ktopl.

  IF gv_ktopl IS INITIAL.
    RETURN.
  ENDIF.

  " Collect distinct GL accounts from working set
  LOOP AT gt_fi_items ASSIGNING FIELD-SYMBOL(<item>).
    APPEND <item>-hkont TO lt_hkont.
  ENDLOOP.
  SORT lt_hkont.
  DELETE ADJACENT DUPLICATES FROM lt_hkont.

  IF lt_hkont IS INITIAL.
    RETURN.
  ENDIF.

  " Bulk SELECT from SKAT (account text table)
  " SKAT key: SPRAS, KTOPL, SAKNR
  SELECT saknr txt50
    INTO CORRESPONDING FIELDS OF TABLE gt_acct_desc
    FROM skat
    FOR ALL ENTRIES IN lt_hkont
    WHERE spras = sy-langu
      AND ktopl = gv_ktopl
      AND saknr = lt_hkont-table_line.

  SORT gt_acct_desc BY saknr.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM map_to_bpc_dimensions
*& Core transformation: FI item → BPC output row.
*& Derives IC partner (KUNNR or LIFNR), maps to BPC dimensions,
*& computes signed amount, and flags exceptions.
*&---------------------------------------------------------------------*

FORM map_to_bpc_dimensions.

  DATA:
    ls_item    TYPE ty_fi_item,
    ls_out     TYPE ty_output,
    ls_ic_map  TYPE ty_ic_map,
    ls_ac_map  TYPE ty_ac_map,
    ls_desc    TYPE ty_acct_desc,
    lv_signed  TYPE dmbtr,
    lv_period  TYPE char2.

  CLEAR gt_output.
  CLEAR gt_exceptions.

  " Sort mapping tables for binary READ
  SORT gt_ic_map BY bukrs koart kunnr lifnr.
  SORT gt_ac_map BY bukrs hkont.
  SORT gt_acct_desc BY saknr.

  LOOP AT gt_fi_items INTO ls_item.

    CLEAR ls_out.

    " --- BPC TIME dimension (YYYY.PP) --------------------------------
    lv_period = |{ ls_item-monat }|.
    CONDENSE lv_period NO-GAPS.
    IF strlen( lv_period ) < 2.
      lv_period = |0{ lv_period }|.
    ENDIF.
    ls_out-time = |{ ls_item-gjahr }.{ lv_period }|.

    " --- Fixed BPC header fields -------------------------------------
    ls_out-statement_type = gc_imlc.
    ls_out-category       = p_categ.
    ls_out-company_code   = ls_item-bukrs.
    ls_out-entity         = ls_item-bukrs.   " Extend: add BPC entity mapping table
    ls_out-currency       = gc_lc.
    ls_out-cost_center    = COND #(
      WHEN ls_item-kostl IS NOT INITIAL THEN ls_item-kostl
      ELSE gc_cc_none ).
    ls_out-detail_op_unit = gc_dt_none.
    ls_out-bd1 = gc_b_none.
    ls_out-bd2 = gc_b_none.
    ls_out-bd3 = gc_b_none.
    ls_out-bd4 = gc_b_none.
    ls_out-bd5 = gc_b_none.
    ls_out-bd6 = gc_b_none.
    ls_out-bd7 = gc_b_none.
    ls_out-bd8 = gc_b_none.

    " --- GL account and description ----------------------------------
    ls_out-gl_account = ls_item-hkont.
    READ TABLE gt_acct_desc INTO ls_desc
      WITH KEY saknr = ls_item-hkont BINARY SEARCH.
    IF sy-subrc = 0.
      ls_out-account_desc = ls_desc-txt50.
    ENDIF.

    " --- BPC account mapping -----------------------------------------
    READ TABLE gt_ac_map INTO ls_ac_map
      WITH KEY bukrs = ls_item-bukrs
               hkont = ls_item-hkont
      BINARY SEARCH.

    IF sy-subrc = 0 AND ls_ac_map-active_flag = abap_true.
      ls_out-bpc_account = ls_ac_map-bpc_account.
    ELSEIF gt_ac_map IS INITIAL.
      " Mapping table not loaded – derive placeholder
      ls_out-bpc_account = |A_{ ls_item-hkont }|.
    ELSE.
      " Table loaded but no mapping entry exists for this account
      ls_out-bpc_account = gc_miss_acct.
    ENDIF.

    " --- Document audit fields ---------------------------------------
    ls_out-document_number = ls_item-belnr.
    ls_out-line_item       = ls_item-buzei.
    ls_out-posting_date    = ls_item-budat.
    ls_out-text            = ls_item-sgtxt.
    ls_out-customer        = ls_item-kunnr.
    ls_out-vendor          = ls_item-lifnr.

    " --- Signed amount -----------------------------------------------
    " FORM derive_signed_amount encapsulates the sign convention.
    " BPC convention: debit positive (F_INC), credit negative (F_DEC).
    PERFORM derive_signed_amount
      USING    ls_item-shkzg ls_item-dmbtr
      CHANGING lv_signed.

    ls_out-amount         = lv_signed.
    ls_out-movement_flag  = COND #( WHEN lv_signed >= 0 THEN gc_f_inc ELSE gc_f_dec ).

    " --- Zero filter --------------------------------------------------
    IF p_zero = abap_false AND lv_signed = 0.
      CONTINUE.
    ENDIF.

    " --- IC partner derivation ---------------------------------------
    " Priority: KUNNR > LIFNR > exception
    " Direct journal entries to IC GL accounts without KUNNR/LIFNR
    " cannot be assigned to an intercompany partner and MUST be flagged.

    IF ls_item-kunnr IS NOT INITIAL.
      " Customer line: look up in IC mapping table
      READ TABLE gt_ic_map INTO ls_ic_map
        WITH KEY bukrs = ls_item-bukrs
                 koart = 'D'
                 kunnr = ls_item-kunnr
        BINARY SEARCH.

      IF sy-subrc = 0 AND ls_ic_map-active_flag = abap_true.
        ls_out-bpc_intercompany = ls_ic_map-bpc_ic.
      ELSEIF gt_ic_map IS INITIAL.
        ls_out-bpc_intercompany = |I_{ ls_item-kunnr }|.   " placeholder
      ELSE.
        ls_out-bpc_intercompany = gc_miss_bpc.
      ENDIF.

      ls_out-row_type          = gc_normal.
      ls_out-validation_status = gc_ok.

    ELSEIF ls_item-lifnr IS NOT INITIAL.
      " Vendor line: look up in IC mapping table
      READ TABLE gt_ic_map INTO ls_ic_map
        WITH KEY bukrs = ls_item-bukrs
                 koart = 'K'
                 lifnr = ls_item-lifnr
        BINARY SEARCH.

      IF sy-subrc = 0 AND ls_ic_map-active_flag = abap_true.
        ls_out-bpc_intercompany = ls_ic_map-bpc_ic.
      ELSEIF gt_ic_map IS INITIAL.
        ls_out-bpc_intercompany = |I_{ ls_item-lifnr }|.   " placeholder
      ELSE.
        ls_out-bpc_intercompany = gc_miss_bpc.
      ENDIF.

      ls_out-row_type          = gc_normal.
      ls_out-validation_status = gc_ok.

    ELSE.
      " *** EXCEPTION: direct posting without IC partner ***
      " This document line has no KUNNR or LIFNR in BSEG.
      " It must not be silently dropped – it is captured as an exception
      " so the business can investigate and correct the posting.
      ls_out-bpc_intercompany  = gc_miss_ic.
      ls_out-row_type          = gc_exception.
      ls_out-validation_status = gc_failed.
      ls_out-exception_reason  = gc_miss_ic.
      APPEND ls_out TO gt_exceptions.
    ENDIF.

    APPEND ls_out TO gt_output.

  ENDLOOP.

  IF p_test = abap_true.
    MESSAGE |{ LINES( gt_output ) } output rows built; { LINES( gt_exceptions ) } exceptions.|
      TYPE 'I'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM derive_signed_amount
*& Encapsulates the debit/credit sign convention for BPC.
*& BPC convention: Debit (S = Soll) = positive, Credit (H = Haben) = neg.
*& To reverse (credit positive / debit negative), swap the two branches.
*&---------------------------------------------------------------------*

FORM derive_signed_amount
  USING    iv_shkzg TYPE shkzg
           iv_dmbtr TYPE dmbtr
  CHANGING cv_signed TYPE dmbtr.

  " BSEG-DMBTR is always stored as an absolute value.
  " SHKZG S = Soll = Debit   → positive movement
  " SHKZG H = Haben = Credit → negative movement
  IF iv_shkzg = 'S'.
    cv_signed = iv_dmbtr.
  ELSE.
    cv_signed = iv_dmbtr * -1.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM calculate_opening_balance
*& Computes opening balance for each IMLC GL account as the sum of all
*& movements in the same fiscal year for periods BEFORE the first
*& selected period.  This mirrors "period start balance".
*&
*& Alternative (New GL / FAGLFLEXT): See commented block below.
*& Alternative (GLT0 carry-forward):  KSLVT field if period = 001.
*&---------------------------------------------------------------------*

FORM calculate_opening_balance.

  DATA:
    lt_prior_bkpf  TYPE STANDARD TABLE OF bkpf,
    ls_prior_bkpf  TYPE bkpf,
    lt_bseg_ob     TYPE STANDARD TABLE OF bseg,
    ls_bseg_ob     TYPE bseg,
    ls_ob          TYPE ty_open_bal,
    lv_poper_start TYPE poper,
    lv_gjahr       TYPE gjahr,
    lv_signed      TYPE dmbtr.

  CLEAR gt_open_bal.
  lv_gjahr = s_gjahr-low.

  " If extracting from period 001 (first period), opening balance is the
  " carry-forward from the previous fiscal year.  Calculating that requires
  " reading prior-year closing or KSLVT from GLT0.  This is left as a
  " placeholder; for BPC reconciliation the carry-forward is usually loaded
  " separately via a balance sheet extract, so returning zero is safe here.
  IF s_poper IS INITIAL.
    lv_poper_start = '001'.
  ELSE.
    lv_poper_start = s_poper-low.
  ENDIF.

  IF lv_poper_start <= 1.
    " Period 1 selected: opening balance = prior-year carry-forward.
    " To implement: read GLT0-KSLVT for lv_gjahr - 1 per GL account.
    " Leaving as zero for now; add GL T0 logic here if required.

    " ------- GLT0 CARRY-FORWARD OPTION (ECC classic GL) ----------
    " DATA: lt_glt0 TYPE STANDARD TABLE OF glt0.
    " SELECT rcomp racct ryear kslvt              " KSLVT = balance c/f
    "   INTO CORRESPONDING FIELDS OF TABLE lt_glt0
    "   FROM glt0
    "   WHERE rcomp IN s_bukrs
    "     AND ryear  = lv_gjahr - 1
    "     AND racct IN s_hkont.
    " LOOP AT lt_glt0 ASSIGNING FIELD-SYMBOL(<g>).
    "   ls_ob-bukrs  = <g>-rcomp.
    "   ls_ob-racct  = <g>-racct.
    "   ls_ob-ryear  = lv_gjahr.
    "   ls_ob-amount = <g>-kslvt.
    "   APPEND ls_ob TO gt_open_bal.
    " ENDLOOP.
    " ------- END GLT0 OPTION --------------------------------------

    " ------- FAGLFLEXT OPTION (New GL) ---------------------------
    " SELECT rbukrs racct ryear hsl              " HSL = local currency
    "   INTO CORRESPONDING FIELDS OF TABLE lt_newgl
    "   FROM faglflext
    "   WHERE rbukrs IN s_bukrs
    "     AND ryear   = lv_gjahr - 1
    "     AND racct  IN s_hkont
    "     AND rldnr   = p_ledgr
    "     AND poper   = '016'.                   " period 16 = closing balance
    " ------- END FAGLFLEXT OPTION ---------------------------------
    RETURN.
  ENDIF.

  " --- Compute prior-period opening balance from raw BSEG movements ---
  " Read all document headers in the fiscal year before the first period
  SELECT belnr bukrs gjahr monat stblg
    INTO CORRESPONDING FIELDS OF TABLE lt_prior_bkpf
    FROM bkpf
    WHERE bukrs IN s_bukrs
      AND gjahr  = lv_gjahr
      AND monat  < lv_poper_start.

  DELETE lt_prior_bkpf WHERE stblg IS NOT INITIAL.   " exclude reversed

  IF lt_prior_bkpf IS INITIAL.
    RETURN.
  ENDIF.

  SELECT belnr bukrs gjahr hkont shkzg dmbtr
    INTO CORRESPONDING FIELDS OF TABLE lt_bseg_ob
    FROM bseg
    FOR ALL ENTRIES IN lt_prior_bkpf
    WHERE bukrs = lt_prior_bkpf-bukrs
      AND belnr = lt_prior_bkpf-belnr
      AND gjahr = lt_prior_bkpf-gjahr
      AND hkont IN s_hkont.

  " Aggregate signed amounts per BUKRS + HKONT
  SORT lt_bseg_ob BY bukrs hkont.

  LOOP AT lt_bseg_ob INTO ls_bseg_ob.

    PERFORM derive_signed_amount
      USING    ls_bseg_ob-shkzg ls_bseg_ob-dmbtr
      CHANGING lv_signed.

    READ TABLE gt_open_bal INTO ls_ob
      WITH KEY bukrs = ls_bseg_ob-bukrs
               racct = ls_bseg_ob-hkont
               ryear = lv_gjahr.

    IF sy-subrc = 0.
      ls_ob-amount = ls_ob-amount + lv_signed.
      MODIFY gt_open_bal FROM ls_ob
        TRANSPORTING amount
        WHERE bukrs = ls_ob-bukrs
          AND racct = ls_ob-racct
          AND ryear = ls_ob-ryear.
    ELSE.
      CLEAR ls_ob.
      ls_ob-bukrs  = ls_bseg_ob-bukrs.
      ls_ob-racct  = ls_bseg_ob-hkont.
      ls_ob-ryear  = lv_gjahr.
      ls_ob-amount = lv_signed.
      APPEND ls_ob TO gt_open_bal.
    ENDIF.

  ENDLOOP.

  IF p_test = abap_true.
    MESSAGE |Opening balance computed for { LINES( gt_open_bal ) } GL accounts.|
      TYPE 'I'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM calculate_period_movement
*& Aggregates the signed period amounts from gt_output (normal rows only)
*& into gt_gl_balance per BUKRS + HKONT + GJAHR.
*&---------------------------------------------------------------------*

FORM calculate_period_movement.

  DATA:
    ls_out TYPE ty_output,
    ls_bal TYPE ty_gl_balance.

  CLEAR gt_gl_balance.

  LOOP AT gt_output INTO ls_out
    WHERE row_type = gc_normal.

    READ TABLE gt_gl_balance INTO ls_bal
      WITH KEY bukrs = ls_out-company_code
               hkont = ls_out-gl_account
               gjahr = s_gjahr-low.

    IF sy-subrc = 0.
      gv_tabix          = sy-tabix.
      ls_bal-period_mov = ls_bal-period_mov + ls_out-amount.
      MODIFY gt_gl_balance FROM ls_bal INDEX gv_tabix.
    ELSE.
      CLEAR ls_bal.
      ls_bal-bukrs      = ls_out-company_code.
      ls_bal-hkont      = ls_out-gl_account.
      ls_bal-gjahr      = s_gjahr-low.
      ls_bal-period_mov = ls_out-amount.
      APPEND ls_bal TO gt_gl_balance.
    ENDIF.

  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM calculate_closing_balance
*& Closing balance = Opening balance + Period movement
*&---------------------------------------------------------------------*

FORM calculate_closing_balance.

  DATA:
    ls_bal TYPE ty_gl_balance,
    ls_ob  TYPE ty_open_bal.

  LOOP AT gt_gl_balance INTO ls_bal.
    gv_tabix = sy-tabix.

    READ TABLE gt_open_bal INTO ls_ob
      WITH KEY bukrs = ls_bal-bukrs
               racct = ls_bal-hkont
               ryear = ls_bal-gjahr.

    ls_bal-open_bal  = COND #( WHEN sy-subrc = 0 THEN ls_ob-amount ELSE 0 ).
    ls_bal-close_bal = ls_bal-open_bal + ls_bal-period_mov.

    MODIFY gt_gl_balance FROM ls_bal INDEX gv_tabix.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM validate_gl_balance
*& Validates the accounting equation:
*&   Opening Balance + Period Movement = Closing Balance
*& A non-zero difference is flagged as FAILED.
*& In this BSEG-based extraction, the difference should always be zero
*& because closing is derived from opening + movement.  A non-zero result
*& would indicate data integrity issues (e.g., GLT0 carry-forward mismatch).
*&---------------------------------------------------------------------*

FORM validate_gl_balance.

  DATA: ls_bal TYPE ty_gl_balance.

  LOOP AT gt_gl_balance INTO ls_bal.
    gv_tabix = sy-tabix.

    " Validate with zero tolerance
    ls_bal-diff = ls_bal-open_bal + ls_bal-period_mov - ls_bal-close_bal.

    ls_bal-val_status = COND #( WHEN ls_bal-diff = 0 THEN gc_ok ELSE gc_failed ).

    MODIFY gt_gl_balance FROM ls_bal INDEX gv_tabix.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM build_output
*& Stamps each normal output row with the validation status and
*& diff_amount from gt_gl_balance.
*& Appends exception rows to gt_output unless exception-only mode.
*&---------------------------------------------------------------------*

FORM build_output.

  DATA:
    ls_out TYPE ty_output,
    ls_bal TYPE ty_gl_balance.

  SORT gt_gl_balance BY bukrs hkont gjahr.

  " Stamp validation status on normal rows
  LOOP AT gt_output INTO ls_out
    WHERE row_type = gc_normal.

    gv_tabix = sy-tabix.

    READ TABLE gt_gl_balance INTO ls_bal
      WITH KEY bukrs = ls_out-company_code
               hkont = ls_out-gl_account
               gjahr = s_gjahr-low
      BINARY SEARCH.

    IF sy-subrc = 0.
      ls_out-validation_status = ls_bal-val_status.
      ls_out-diff_amount       = ls_bal-diff.
    ENDIF.

    MODIFY gt_output FROM ls_out INDEX gv_tabix.

  ENDLOOP.

  " In normal mode, merge exception rows into the single output table
  " so the ALV shows everything in one grid.
  IF p_excep = abap_false.
    APPEND LINES OF gt_exceptions TO gt_output.
  ENDIF.

  " Final sort: entity, account, period, partner
  SORT gt_output BY
    company_code gl_account time bpc_intercompany row_type.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM display_alv
*& Renders the output table in CL_SALV_TABLE.
*& Falls back to REUSE_ALV_GRID_DISPLAY if CL_SALV_TABLE raises an error.
*&---------------------------------------------------------------------*

FORM display_alv USING iv_mode TYPE char10.

  DATA:
    lo_salv    TYPE REF TO cl_salv_table,
    lo_funcs   TYPE REF TO cl_salv_functions_list,
    lo_columns TYPE REF TO cl_salv_columns_table,
    lo_column  TYPE REF TO cl_salv_column_table,
    lo_display TYPE REF TO cl_salv_display_settings,
    lx_msg     TYPE REF TO cx_salv_msg,
    lv_title   TYPE lvc_title.

  " Point to the correct data set
  IF iv_mode = gc_exception.
    IF gt_exceptions IS INITIAL.
      MESSAGE 'No exception rows found.' TYPE 'I'.
      RETURN.
    ENDIF.
    lv_title = 'IMLC Exceptions – Missing IC Partner'.
    TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_salv
        CHANGING  t_table      = gt_exceptions ).
    CATCH cx_salv_msg INTO lx_msg.
      MESSAGE lx_msg->get_text( ) TYPE 'W'.
      PERFORM display_alv_classic USING iv_mode.
      RETURN.
    ENDTRY.
  ELSE.
    IF gt_output IS INITIAL.
      MESSAGE 'No output rows to display.' TYPE 'I'.
      RETURN.
    ENDIF.
    lv_title = 'ZFI_IMLC_EXTRACT – Intercompany Movement (Local Currency)'.
    TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_salv
        CHANGING  t_table      = gt_output ).
    CATCH cx_salv_msg INTO lx_msg.
      MESSAGE lx_msg->get_text( ) TYPE 'W'.
      PERFORM display_alv_classic USING iv_mode.
      RETURN.
    ENDTRY.
  ENDIF.

  " Enable standard toolbar (sort, filter, Excel export)
  lo_funcs = lo_salv->get_functions( ).
  lo_funcs->set_all( abap_true ).

  " Title bar and zebra striping
  lo_display = lo_salv->get_display_settings( ).
  lo_display->set_list_header( lv_title ).
  lo_display->set_striped_pattern( abap_true ).

  " Optimize column widths
  lo_columns = lo_salv->get_columns( ).
  lo_columns->set_optimize( abap_true ).

  " Hide internal tracking column
  TRY.
    lo_column ?= lo_columns->get_column( 'ROW_TYPE' ).
    lo_column->set_visible( abap_false ).
  CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  " Human-readable header for diff_amount
  TRY.
    lo_column ?= lo_columns->get_column( 'DIFF_AMOUNT' ).
    lo_column->set_long_text( 'Validation Diff' ).
    lo_column->set_medium_text( 'Val Diff' ).
  CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  " Human-readable header for validation_status
  TRY.
    lo_column ?= lo_columns->get_column( 'VALIDATION_STATUS' ).
    lo_column->set_long_text( 'Validation Status' ).
  CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  lo_salv->display( ).

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM display_alv_classic
*& Fallback ALV using REUSE_ALV_GRID_DISPLAY (available on all ECC).
*&---------------------------------------------------------------------*

FORM display_alv_classic USING iv_mode TYPE char10.

  DATA:
    lt_fcat TYPE slis_t_fieldcat_alv,
    ls_fcat TYPE slis_fieldcat_alv,
    ls_layo TYPE slis_layout_alv.

  " -- Build field catalog --
  DEFINE _field.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1.
    ls_fcat-seltext_m = &2.
    ls_fcat-outputlen = &3.
    IF &4 = 'X'.
      ls_fcat-no_out = abap_true.
    ENDIF.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.

  "         Fieldname            Label               Len  Hidden
  _field    'TIME'               'Period'             10   ''.
  _field    'STATEMENT_TYPE'     'Stmt Type'           8   ''.
  _field    'CATEGORY'           'Category'           14   ''.
  _field    'ENTITY'             'Entity'             10   ''.
  _field    'COMPANY_CODE'       'CoCd'                6   ''.
  _field    'GL_ACCOUNT'         'GL Account'         10   ''.
  _field    'BPC_ACCOUNT'        'BPC Account'        20   ''.
  _field    'ACCOUNT_DESC'       'Account Description' 40  ''.
  _field    'CUSTOMER'           'Customer'           10   ''.
  _field    'VENDOR'             'Vendor'             10   ''.
  _field    'BPC_INTERCOMPANY'   'BPC IC'             20   ''.
  _field    'CURRENCY'           'Curr'                5   ''.
  _field    'COST_CENTER'        'Cost Center'        15   ''.
  _field    'DETAIL_OP_UNIT'     'Detail OU'          15   ''.
  _field    'BD1'                'BD1'                15   ''.
  _field    'BD2'                'BD2'                15   ''.
  _field    'BD3'                'BD3'                15   ''.
  _field    'BD4'                'BD4'                15   ''.
  _field    'BD5'                'BD5'                15   ''.
  _field    'BD6'                'BD6'                15   ''.
  _field    'BD7'                'BD7'                15   ''.
  _field    'BD8'                'BD8'                15   ''.
  _field    'AMOUNT'             'Amount'             18   ''.
  _field    'MOVEMENT_FLAG'      'Mvt Flag'            8   ''.
  _field    'DOCUMENT_NUMBER'    'Doc Number'         10   ''.
  _field    'LINE_ITEM'          'Item'                4   ''.
  _field    'POSTING_DATE'       'Posting Date'       10   ''.
  _field    'TEXT'               'Text'               30   ''.
  _field    'VALIDATION_STATUS'  'Val Status'         12   ''.
  _field    'EXCEPTION_REASON'   'Exception Reason'   40   ''.
  _field    'DIFF_AMOUNT'        'Val Diff'           18   ''.
  _field    'ROW_TYPE'           'Row Type'           10   'X'.  " hidden

  ls_layo-colwidth_optimize = abap_true.
  ls_layo-zebra             = abap_true.

  IF iv_mode = gc_exception.
    CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
      EXPORTING
        it_fieldcat = lt_fcat
        is_layout   = ls_layo
        i_callback_program = sy-repid
      TABLES
        t_outtab    = gt_exceptions
      EXCEPTIONS
        OTHERS      = 1.
  ELSE.
    CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
      EXPORTING
        it_fieldcat = lt_fcat
        is_layout   = ls_layo
        i_callback_program = sy-repid
      TABLES
        t_outtab    = gt_output
      EXCEPTIONS
        OTHERS      = 1.
  ENDIF.

  IF sy-subrc <> 0.
    MESSAGE 'ALV display error – check field catalog.' TYPE 'E'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM download_file
*& Downloads gt_output to a TAB-delimited text file on the frontend
*& using GUI_DOWNLOAD.  Only called when p_down = abap_true.
*& The file is suitable for direct BPC flat-file upload.
*&---------------------------------------------------------------------*

FORM download_file.

  DATA:
    lt_lines  TYPE TABLE OF string,
    lv_line   TYPE string,
    ls_out    TYPE ty_output,
    lv_tab    TYPE c VALUE cl_abap_char_utilities=>horizontal_tab.

  " -- Header row --
  CONCATENATE
    'TIME'               lv_tab
    'STATEMENT_TYPE'     lv_tab
    'CATEGORY'           lv_tab
    'ENTITY'             lv_tab
    'COMPANY_CODE'       lv_tab
    'GL_ACCOUNT'         lv_tab
    'BPC_ACCOUNT'        lv_tab
    'ACCOUNT_DESC'       lv_tab
    'CUSTOMER'           lv_tab
    'VENDOR'             lv_tab
    'BPC_INTERCOMPANY'   lv_tab
    'CURRENCY'           lv_tab
    'COST_CENTER'        lv_tab
    'DETAIL_OP_UNIT'     lv_tab
    'BD1' lv_tab 'BD2' lv_tab 'BD3' lv_tab 'BD4' lv_tab
    'BD5' lv_tab 'BD6' lv_tab 'BD7' lv_tab 'BD8' lv_tab
    'AMOUNT'             lv_tab
    'MOVEMENT_FLAG'      lv_tab
    'DOCUMENT_NUMBER'    lv_tab
    'LINE_ITEM'          lv_tab
    'POSTING_DATE'       lv_tab
    'TEXT'               lv_tab
    'VALIDATION_STATUS'  lv_tab
    'EXCEPTION_REASON'
    INTO lv_line.

  APPEND lv_line TO lt_lines.

  " -- Data rows --
  LOOP AT gt_output INTO ls_out.
    CONCATENATE
      ls_out-time               lv_tab
      ls_out-statement_type     lv_tab
      ls_out-category           lv_tab
      ls_out-entity             lv_tab
      ls_out-company_code       lv_tab
      ls_out-gl_account         lv_tab
      ls_out-bpc_account        lv_tab
      ls_out-account_desc       lv_tab
      ls_out-customer           lv_tab
      ls_out-vendor             lv_tab
      ls_out-bpc_intercompany   lv_tab
      ls_out-currency           lv_tab
      ls_out-cost_center        lv_tab
      ls_out-detail_op_unit     lv_tab
      ls_out-bd1   lv_tab
      ls_out-bd2   lv_tab
      ls_out-bd3   lv_tab
      ls_out-bd4   lv_tab
      ls_out-bd5   lv_tab
      ls_out-bd6   lv_tab
      ls_out-bd7   lv_tab
      ls_out-bd8   lv_tab
      ls_out-amount             lv_tab
      ls_out-movement_flag      lv_tab
      ls_out-document_number    lv_tab
      ls_out-line_item          lv_tab
      ls_out-posting_date       lv_tab
      ls_out-text               lv_tab
      ls_out-validation_status  lv_tab
      ls_out-exception_reason
      INTO lv_line.

    APPEND lv_line TO lt_lines.
  ENDLOOP.

  " -- Trigger frontend download --
  CALL FUNCTION 'GUI_DOWNLOAD'
    EXPORTING
      filename                = p_file
      filetype                = 'ASC'
      codepage                = '4110'   " UTF-8; use '1100' for ANSI/Latin-1
      write_field_separator   = lv_tab
      append                  = ' '
      trunc_trailing_blanks   = 'X'
    TABLES
      data_tab                = lt_lines
    EXCEPTIONS
      file_write_error        = 1
      no_batch                = 2
      gui_refuse_filetransfer = 3
      invalid_type            = 4
      no_authority            = 5
      unknown_error           = 6
      header_not_allowed      = 7
      separator_not_allowed   = 8
      filesize_not_allowed    = 9
      header_too_long         = 10
      dp_error_create         = 11
      dp_error_send           = 12
      dp_error_write          = 13
      unknown_dp_error        = 14
      access_denied           = 15
      dp_out_of_memory        = 16
      disk_full               = 17
      dp_timeout              = 18
      file_not_found          = 19
      dataprovider_exception  = 20
      control_flush_error     = 21
      OTHERS                  = 22.

  IF sy-subrc = 0.
    MESSAGE |Download complete: { p_file } ({ LINES( lt_lines ) - 1 } data rows).|
      TYPE 'I'.
  ELSE.
    MESSAGE |GUI_DOWNLOAD failed (SY-SUBRC = { sy-subrc }). Check path and S_GUI authorisation.|
      TYPE 'E'.
  ENDIF.

ENDFORM.

*=======================================================================
* Z TABLE DDic RECOMMENDATIONS
*=======================================================================
*
* 1. ZFI_IMLC_ICMAP  –  IC Partner → BPC Entity mapping
* -------------------------------------------------------
* Field       Type   Length  Key  Description
* MANDT       CLNT      3    Yes  Client
* BUKRS       BUKRS     4    Yes  Company Code
* KOART       KOART     1    Yes  Account type: D=Customer, K=Vendor
* KUNNR       KUNNR    10    Yes  Customer number (blank if vendor)
* LIFNR       LIFNR    10    Yes  Vendor number   (blank if customer)
* BPC_IC      CHAR     20         BPC intercompany entity code
* VALID_FROM  DATS      8         Validity start date
* VALID_TO    DATS      8         Validity end date
* ACTIVE_FLAG XFELD     1         Active indicator (X = active)
*
* 2. ZFI_IMLC_ACMAP  –  GL Account → BPC Account mapping
* --------------------------------------------------------
* Field       Type   Length  Key  Description
* MANDT       CLNT      3    Yes  Client
* BUKRS       BUKRS     4    Yes  Company Code
* HKONT       SAKNR    10    Yes  G/L account number
* BPC_ACCOUNT CHAR     20         BPC account dimension value
* ACTIVE_FLAG XFELD     1         Active indicator
*
* 3. ZFI_IMLC_ENTITY (optional) –  BPC Entity mapping
* -----------------------------------------------------
* Field       Type   Length  Key  Description
* MANDT       CLNT      3    Yes  Client
* BUKRS       BUKRS     4    Yes  Company Code
* BPC_ENTITY  CHAR     20         BPC entity / consolidation unit
* ACTIVE_FLAG XFELD     1         Active indicator
*
*=======================================================================
* AUTHORISATION OBJECTS REQUIRED
*=======================================================================
* F_BKPF_BUK   – Company code (ACTVT 03)
* F_BKPF_KOA   – Account type (Debtors / Creditors)
* F_FAGLFLEXT  – Ledger access (if FAGLFLEXT is used)
* S_GUI        – Frontend file download
* S_TABU_DIS   – Display access to Z customising tables
*=======================================================================
