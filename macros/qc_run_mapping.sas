/*=============================================================================
  MACRO : %qc_run_mapping
  PURPOSE: 10-step QC engine for a single mapping row.
           Called iteratively by %search_raw_dir for each row in the mapping sheet.

  STEPS:
    1  Dataset existence check (abort early if missing)
    2  Variable existence / type compatibility check
    3  Apply WHERE filters (raw and SDTM)
    4  Key normalization — build COMP_KEY
    5  Duplicate / uniqueness analysis vs EXPECTED_MULT
    6  Count comparison (raw N vs SDTM N)
    7  Presence / absence analysis (keys only in raw, only in SDTM)
    8  Multiplicity ratio check
    9  Value comparison (if COMPARE=Y and COMPARE_VARS not blank)
   10  Summarize into OUTSUM

  All parameters passed from %search_raw_dir — see that macro for descriptions.
=============================================================================*/

%macro qc_run_mapping(
    map_row     =,
    raw_member  =,
    sdtm_ds     =,
    keyvars     =,
    compare_vars=,
    where_raw   =,
    where_sdtm  =,
    required_fl =,
    exp_mult    =,
    rawlib      =,
    sdtmlib     =,
    outsum      =,
    outdet      =,
    outval      =,
    outmeta     =,
    compare     = Y,
    run_label   =,
    run_ts      =,
    debug       = N
);

    %local raw_n sdtm_n count_diff keys_only_raw keys_only_sdtm
           mult_status value_disc overall msg abort_flag
           dup_raw dup_sdtm;

    %let abort_flag = 0;
    %let value_disc = 0;
    %let mult_status = PASS;
    %let overall = PASS;
    %let msg = ;

    /*================================================================
      STEP 1 : Dataset existence — if either missing, abort this row
    ================================================================*/
    %if %sysfunc(exist(&rawlib..&raw_member.)) = 0 %then %do;
        %put WARNING: [ROW &map_row.] Raw dataset &rawlib..&raw_member. missing — skipping.;
        %let abort_flag = 1;
        %let overall = FAIL;
        %let msg = Raw dataset &rawlib..&raw_member. does not exist.;
    %end;
    %if %sysfunc(exist(&sdtmlib..&sdtm_ds.)) = 0 and &abort_flag. = 0 %then %do;
        %put WARNING: [ROW &map_row.] SDTM dataset &sdtmlib..&sdtm_ds. missing — skipping.;
        %let abort_flag = 1;
        %let overall = FAIL;
        %let msg = SDTM dataset &sdtmlib..&sdtm_ds. does not exist.;
    %end;

    %if &abort_flag. = 1 %then %do;
        data _sum_row_;
            RUN_LABEL     = "&run_label.";
            RUN_TS        = "&run_ts.";
            MAP_ROW       = &map_row.;
            RAW_MEMBER    = "&raw_member.";
            SDTM_DS       = "&sdtm_ds.";
            EXPECTED_MULT = "&exp_mult.";
            REQUIRED_FL   = "&required_fl.";
            RAW_N         = .;
            SDTM_N        = .;
            COUNT_DIFF    = .;
            KEYS_ONLY_RAW = .;
            KEYS_ONLY_SDTM= .;
            MULT_STATUS   = "N/A";
            VALUE_DISC    = .;
            OVERALL       = "&overall.";
            MESSAGE       = "&msg.";
        run;
        proc append base=&outsum. data=_sum_row_ force; run;
        %goto end_mapping;
    %end;

    /*================================================================
      STEP 2 : Variable checks (already done in qc_validate_meta;
               here we log per-row context if a key is still missing)
    ================================================================*/
    /* Handled upstream — proceed */

    /*================================================================
      STEP 3 : Apply WHERE filters
    ================================================================*/
    %if %length(%trim(&where_raw.)) > 0 %then %do;
        data work._qc_raw_sub_;
            set &rawlib..&raw_member.;
            where &where_raw.;
        run;
    %end;
    %else %do;
        data work._qc_raw_sub_;
            set &rawlib..&raw_member.;
        run;
    %end;

    %if %length(%trim(&where_sdtm.)) > 0 %then %do;
        data work._qc_sdtm_sub_;
            set &sdtmlib..&sdtm_ds.;
            where &where_sdtm.;
        run;
    %end;
    %else %do;
        data work._qc_sdtm_sub_;
            set &sdtmlib..&sdtm_ds.;
        run;
    %end;

    /*================================================================
      STEP 4 : Key normalization — build COMP_KEY on each side
    ================================================================*/
    %qc_normalize_key(
        inds    = work._qc_raw_sub_,
        outds   = work._qc_raw_keys_,
        keyvars = &keyvars.,
        libref  = work
    );
    %qc_normalize_key(
        inds    = work._qc_sdtm_sub_,
        outds   = work._qc_sdtm_keys_,
        keyvars = &keyvars.,
        libref  = work
    );

    /*================================================================
      STEP 5 : Duplicate analysis
    ================================================================*/
    proc sql noprint;
        select count(*) - count(distinct COMP_KEY)
            into :dup_raw trimmed
        from work._qc_raw_keys_;

        select count(*) - count(distinct COMP_KEY)
            into :dup_sdtm trimmed
        from work._qc_sdtm_keys_;
    quit;

    /* ONE2ONE: duplicates on either side are unexpected */
    %if &exp_mult. = ONE2ONE %then %do;
        %if &dup_raw. > 0 or &dup_sdtm. > 0 %then %do;
            %let mult_status = WARN;
            %let msg = ONE2ONE mapping: &dup_raw. duplicate keys in raw, &dup_sdtm. in SDTM.;
        %end;
    %end;
    /* For other multiplicities duplicates are expected — only flag if counter-intuitive side is duplicated */
    %else %if &exp_mult. = ONE2MANY %then %do;
        %if &dup_raw. > 0 %then %do;
            %let mult_status = WARN;
            %let msg = ONE2MANY: unexpected duplicates on raw side (&dup_raw. extra keys).;
        %end;
    %end;
    %else %if &exp_mult. = MANY2ONE %then %do;
        %if &dup_sdtm. > 0 %then %do;
            %let mult_status = WARN;
            %let msg = MANY2ONE: unexpected duplicates on SDTM side (&dup_sdtm. extra keys).;
        %end;
    %end;

    /*================================================================
      STEP 6 : Count comparison
    ================================================================*/
    proc sql noprint;
        select count(*) into :raw_n  trimmed from work._qc_raw_keys_;
        select count(*) into :sdtm_n trimmed from work._qc_sdtm_keys_;
    quit;
    %let count_diff = %eval(&raw_n. - &sdtm_n.);

    /*================================================================
      STEP 7 : Presence / absence analysis
    ================================================================*/
    proc sort data=work._qc_raw_keys_  (keep=COMP_KEY) out=work._qc_rk_sort_  nodupkey; by COMP_KEY; run;
    proc sort data=work._qc_sdtm_keys_ (keep=COMP_KEY) out=work._qc_sk_sort_  nodupkey; by COMP_KEY; run;

    data work._qc_presence_;
        merge work._qc_rk_sort_ (in=inr)
              work._qc_sk_sort_ (in=ins);
        by COMP_KEY;
        IN_RAW  = inr;
        IN_SDTM = ins;
        if not (inr and ins);
    run;

    proc sql noprint;
        select count(*) into :keys_only_raw   trimmed from work._qc_presence_ where IN_RAW=1  and IN_SDTM=0;
        select count(*) into :keys_only_sdtm  trimmed from work._qc_presence_ where IN_RAW=0  and IN_SDTM=1;
    quit;

    /* Append presence/absence detail to OUTDET */
    %if &keys_only_raw. > 0 or &keys_only_sdtm. > 0 %then %do;
        data _det_rows_;
            set work._qc_presence_;
            RUN_LABEL  = "&run_label.";
            RUN_TS     = "&run_ts.";
            MAP_ROW    = &map_row.;
            RAW_MEMBER = "&raw_member.";
            SDTM_DS    = "&sdtm_ds.";
        run;
        proc append base=&outdet. data=_det_rows_ force; run;
    %end;

    /*================================================================
      STEP 8 : Multiplicity ratio check
    ================================================================*/
    %local mult_ratio;
    %if &raw_n. > 0 %then
        %let mult_ratio = %sysevalf(&sdtm_n. / &raw_n., float);
    %else
        %let mult_ratio = .;

    %if &exp_mult. = ONE2ONE %then %do;
        %if &raw_n. ne &sdtm_n. %then %do;
            %if &mult_status. = PASS %then %let mult_status = WARN;
            %let msg = &msg. ONE2ONE count mismatch: raw=&raw_n., SDTM=&sdtm_n..;
        %end;
    %end;
    %else %if &exp_mult. = ONE2MANY %then %do;
        %if %sysevalf(&sdtm_n. < &raw_n.) %then %do;
            %if &mult_status. = PASS %then %let mult_status = WARN;
            %let msg = &msg. ONE2MANY: SDTM count (&sdtm_n.) less than raw (&raw_n.) — unexpected.;
        %end;
    %end;
    %else %if &exp_mult. = MANY2ONE %then %do;
        %if %sysevalf(&sdtm_n. > &raw_n.) %then %do;
            %if &mult_status. = PASS %then %let mult_status = WARN;
            %let msg = &msg. MANY2ONE: SDTM count (&sdtm_n.) greater than raw (&raw_n.) — unexpected.;
        %end;
    %end;

    /*================================================================
      STEP 9 : Value comparison (if enabled and compare vars present)
    ================================================================*/
    %if &compare. = Y and %length(%trim(&compare_vars.)) > 0 %then %do;

        /* Get matched keys on both sides */
        data work._qc_matched_raw_;
            merge work._qc_raw_keys_  (in=inr)
                  work._qc_rk_sort_   (in=ins);
            by COMP_KEY;
            if inr and ins;
        run;
        data work._qc_matched_sdtm_;
            merge work._qc_sdtm_keys_ (in=inr)
                  work._qc_sk_sort_   (in=ins);
            by COMP_KEY;
            if inr and ins;
        run;

        %qc_compare_values(
            raw_matched  = work._qc_matched_raw_,
            sdtm_matched = work._qc_matched_sdtm_,
            compare_vars = &compare_vars.,
            map_row      = &map_row.,
            raw_member   = &raw_member.,
            sdtm_ds      = &sdtm_ds.,
            outval       = &outval.,
            run_label    = &run_label.,
            run_ts       = &run_ts.
        );

        proc sql noprint;
            select count(*) into :value_disc trimmed
            from &outval.
            where MAP_ROW = &map_row.;
        quit;
    %end;

    /*================================================================
      STEP 10 : Determine OVERALL status and write OUTSUM
    ================================================================*/
    %if &keys_only_raw. > 0 or &keys_only_sdtm. > 0 or &value_disc. > 0 %then %do;
        %if &overall. = PASS %then %let overall = WARN;
    %end;
    %if &mult_status. = WARN or &mult_status. = FAIL %then %do;
        %if &overall. = PASS %then %let overall = WARN;
    %end;
    %if &required_fl. = Y and &sdtm_n. = 0 %then %do;
        %let overall = FAIL;
        %let msg = &msg. REQUIRED mapping but SDTM dataset has 0 records after filter.;
    %end;

    data _sum_row_;
        RUN_LABEL     = "&run_label.";
        RUN_TS        = "&run_ts.";
        MAP_ROW       = &map_row.;
        RAW_MEMBER    = "&raw_member.";
        SDTM_DS       = "&sdtm_ds.";
        EXPECTED_MULT = "&exp_mult.";
        REQUIRED_FL   = "&required_fl.";
        RAW_N         = &raw_n.;
        SDTM_N        = &sdtm_n.;
        COUNT_DIFF    = &count_diff.;
        KEYS_ONLY_RAW = &keys_only_raw.;
        KEYS_ONLY_SDTM= &keys_only_sdtm.;
        MULT_STATUS   = "&mult_status.";
        VALUE_DISC    = &value_disc.;
        OVERALL       = "&overall.";
        MESSAGE       = substr("&msg.", 1, 500);
    run;
    proc append base=&outsum. data=_sum_row_ force; run;

    %put NOTE: [ROW &map_row.] &raw_member.->%trim(&sdtm_ds.) | RAW=&raw_n. SDTM=&sdtm_n. DIFF=&count_diff. ONLY_R=&keys_only_raw. ONLY_S=&keys_only_sdtm. DISC=&value_disc. STATUS=&overall.;

    %end_mapping:

%mend qc_run_mapping;
