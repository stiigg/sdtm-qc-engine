/*=============================================================================
  MACRO : %search_raw_dir
  PURPOSE: Main orchestration macro for metadata-driven raw->SDTM QC engine.
           Reads mapping metadata from an Excel sheet, validates specs, then
           iterates over each mapping row executing the 10-step QC workflow.

  PARAMETERS:
    RAW_PATH    - Path to directory containing raw SAS datasets
    SDTM_PATH   - Path to directory containing SDTM SAS datasets
    MAP_FILE    - Full path to the Excel mapping workbook
    MAP_SHEET   - Sheet name inside the Excel workbook (default: MAPPINGS)
    OUTSUM      - Output dataset: summary results per mapping (default: work.qc_summary)
    OUTDET      - Output dataset: record-level presence/absence (default: work.qc_detail)
    OUTVAL      - Output dataset: value discrepancies (default: work.qc_values)
    OUTMETA     - Output dataset: structural/metadata issues (default: work.qc_meta)
    COMPARE     - Y/N enable value-level comparison (default: Y)
    MODE        - RUN = full QC | CHECK_META_ONLY = spec validation only (default: RUN)
    STRICT      - Y/N treat metadata warnings as errors (default: N)
    DEBUG       - Y/N retain intermediate work datasets and verbose log (default: N)
    RUN_LABEL   - Optional free-text label stamped on all output rows

  OUTPUT DATASETS (see README for column details):
    OUTSUM, OUTDET, OUTVAL, OUTMETA

  AUTHOR : Christian Baghai
  VERSION: 1.0
=============================================================================*/

%macro search_raw_dir(
    raw_path   =,
    sdtm_path  =,
    map_file   =,
    map_sheet  = MAPPINGS,
    outsum     = work.qc_summary,
    outdet     = work.qc_detail,
    outval     = work.qc_values,
    outmeta    = work.qc_meta,
    compare    = Y,
    mode       = RUN,
    strict     = N,
    debug      = N,
    run_label  =
);

    %local i n_maps rc mapping_ok run_ts;
    %let run_ts = %sysfunc(datetime(), datetime20.);
    %let compare = %upcase(&compare.);
    %let mode    = %upcase(&mode.);
    %let strict  = %upcase(&strict.);
    %let debug   = %upcase(&debug.);

    %put NOTE: ============================================================;
    %put NOTE: %search_raw_dir starting at &run_ts.;
    %put NOTE: RAW_PATH  = &raw_path.;
    %put NOTE: SDTM_PATH = &sdtm_path.;
    %put NOTE: MAP_FILE  = &map_file.;
    %put NOTE: MODE      = &mode.;
    %put NOTE: COMPARE   = &compare.;
    %put NOTE: ============================================================;

    /*------------------------------------------------------------------
      STEP 1 : Initialise output skeleton datasets
    ------------------------------------------------------------------*/
    data &outsum.;
        length RUN_LABEL      $200
               RUN_TS         $20
               MAP_ROW        8
               RAW_MEMBER     $32
               SDTM_DS        $32
               EXPECTED_MULT  $10
               REQUIRED_FL    $1
               RAW_N          8
               SDTM_N         8
               COUNT_DIFF     8
               KEYS_ONLY_RAW  8
               KEYS_ONLY_SDTM 8
               MULT_STATUS    $8
               VALUE_DISC     8
               OVERALL        $8
               MESSAGE        $500;
        stop;
    run;

    data &outdet.;
        length RUN_LABEL    $200
               MAP_ROW      8
               RAW_MEMBER   $32
               SDTM_DS      $32
               COMP_KEY     $500
               IN_RAW       8
               IN_SDTM      8;
        stop;
    run;

    data &outval.;
        length RUN_LABEL   $200
               MAP_ROW     8
               RAW_MEMBER  $32
               SDTM_DS     $32
               COMP_KEY    $500
               VARNAME     $32
               RAW_VALUE   $500
               SDTM_VALUE  $500;
        stop;
    run;

    data &outmeta.;
        length RUN_LABEL   $200
               MAP_ROW     8
               RAW_MEMBER  $32
               SDTM_DS     $32
               ISSUE_TYPE  $30
               ISSUE_MSG   $500
               SEVERITY    $8;
        stop;
    run;

    /*------------------------------------------------------------------
      STEP 2 : Assign dynamic libraries for raw and SDTM directories
    ------------------------------------------------------------------*/
    %if %sysfunc(libref(_RAWLIB_)) ne 0 %then %do;
        libname _RAWLIB_ "&raw_path.";
    %end;
    %if %sysfunc(libref(_SDTMLIB)) ne 0 %then %do;
        libname _SDTMLIB "&sdtm_path.";
    %end;

    %if %sysfunc(libref(_RAWLIB_)) ne 0 %then %do;
        %put ERROR: Cannot assign raw library at &raw_path. — aborting.;
        %goto exit_macro;
    %end;
    %if %sysfunc(libref(_SDTMLIB)) ne 0 %then %do;
        %put ERROR: Cannot assign SDTM library at &sdtm_path. — aborting.;
        %goto exit_macro;
    %end;

    /*------------------------------------------------------------------
      STEP 3 : Read mapping sheet via LIBNAME XLSX
    ------------------------------------------------------------------*/
    %if %sysfunc(fileexist(&map_file.)) = 0 %then %do;
        %put ERROR: Mapping file not found: &map_file.;
        %goto exit_meta_err;
    %end;

    libname _MAPXLS_ xlsx "&map_file.";

    %if %sysfunc(libref(_MAPXLS_)) ne 0 %then %do;
        %put ERROR: Cannot open mapping Excel file: &map_file.;
        %goto exit_meta_err;
    %end;

    /* Check sheet exists */
    %if %sysfunc(exist(_MAPXLS_.&map_sheet.)) = 0 %then %do;
        %put ERROR: Sheet &map_sheet. not found in &map_file.;
        %goto exit_meta_err;
    %end;

    data work._qc_mappings_;
        set _MAPXLS_.&map_sheet.;
        /* Standardise key columns */
        RAW_MEMBER    = upcase(strip(RAW_MEMBER));
        SDTM_DS       = upcase(strip(SDTM_DS));
        KEYVARS       = upcase(strip(KEYVARS));
        COMPARE_VARS  = upcase(strip(COMPARE_VARS));
        WHERE_RAW     = strip(WHERE_RAW);
        WHERE_SDTM    = strip(WHERE_SDTM);
        REQUIRED_FL   = upcase(strip(REQUIRED_FL));
        EXPECTED_MULT = upcase(strip(EXPECTED_MULT));
        MAP_ROW       = _N_;
        /* Skip blank rows */
        if RAW_MEMBER = '' and SDTM_DS = '' then delete;
    run;

    libname _MAPXLS_ clear;

    /* Validate mapping sheet — call spec validator */
    %qc_validate_meta(
        mapds    = work._qc_mappings_,
        outmeta  = &outmeta.,
        rawlib   = _RAWLIB_,
        sdtmlib  = _SDTMLIB,
        run_label= &run_label.,
        run_ts   = &run_ts.,
        strict   = &strict.
    );

    %if &mode. = CHECK_META_ONLY %then %do;
        %put NOTE: MODE=CHECK_META_ONLY — stopping after metadata validation.;
        %goto cleanup;
    %end;

    /*------------------------------------------------------------------
      STEP 4 : Iterate over each mapping row and run QC engine
    ------------------------------------------------------------------*/
    proc sql noprint;
        select count(*) into :n_maps trimmed
        from work._qc_mappings_;
    quit;

    %put NOTE: Found &n_maps. mapping rows to process.;

    %do i = 1 %to &n_maps.;

        /* Extract scalar parameters for this mapping row */
        data _null_;
            set work._qc_mappings_(firstobs=&i. obs=&i.);
            call symputx('_map_row_',     MAP_ROW);
            call symputx('_raw_mbr_',     RAW_MEMBER);
            call symputx('_sdtm_ds_',     SDTM_DS);
            call symputx('_keyvars_',     KEYVARS);
            call symputx('_compvars_',    COMPARE_VARS);
            call symputx('_where_raw_',   WHERE_RAW);
            call symputx('_where_sdtm_',  WHERE_SDTM);
            call symputx('_req_fl_',      REQUIRED_FL);
            call symputx('_exp_mult_',    EXPECTED_MULT);
        run;

        %put NOTE: ---- Processing row &i.: &_raw_mbr_. -> &_sdtm_ds_. (MULT=&_exp_mult_.) ----;

        %qc_run_mapping(
            map_row    = &_map_row_.,
            raw_member = &_raw_mbr_.,
            sdtm_ds    = &_sdtm_ds_.,
            keyvars    = &_keyvars_.,
            compare_vars= &_compvars_.,
            where_raw  = &_where_raw_.,
            where_sdtm = &_where_sdtm_.,
            required_fl= &_req_fl_.,
            exp_mult   = &_exp_mult_.,
            rawlib     = _RAWLIB_,
            sdtmlib    = _SDTMLIB,
            outsum     = &outsum.,
            outdet     = &outdet.,
            outval     = &outval.,
            outmeta    = &outmeta.,
            compare    = &compare.,
            run_label  = &run_label.,
            run_ts     = &run_ts.,
            debug      = &debug.
        );

    %end; /* mapping loop */

    %goto cleanup;

    %exit_meta_err:
        %put ERROR: Fatal metadata error — QC engine aborted.;

    %cleanup:
        %if &debug. = N %then %do;
            proc datasets library=work nolist;
                delete _qc_mappings_ _qc_raw_sub_ _qc_sdtm_sub_
                       _qc_raw_keys_ _qc_sdtm_keys_ _qc_matched_
                       _qc_raw_only_ _qc_sdtm_only_ _qc_val_base_;
            quit;
        %end;
        libname _RAWLIB_ clear;
        libname _SDTMLIB clear;

    %exit_macro:
    %put NOTE: %search_raw_dir complete.;

%mend search_raw_dir;
