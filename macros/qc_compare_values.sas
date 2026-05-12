/*=============================================================================
  MACRO : %qc_compare_values
  PURPOSE: For keys matched between raw and SDTM, compare values of
           COMPARE_VARS and write discrepancies to OUTVAL.
           Uses a transposed comparison approach to avoid wide dataset issues.

  PARAMETERS:
    RAW_MATCHED  - Raw dataset filtered to matched keys (has COMP_KEY)
    SDTM_MATCHED - SDTM dataset filtered to matched keys (has COMP_KEY)
    COMPARE_VARS - Space-separated list of variables to compare
    MAP_ROW      - Mapping row identifier (numeric)
    RAW_MEMBER   - Raw dataset name (for labeling)
    SDTM_DS      - SDTM dataset name (for labeling)
    OUTVAL       - Append-target output dataset for discrepancies
    RUN_LABEL    - Run label string
    RUN_TS       - Run timestamp string
=============================================================================*/

%macro qc_compare_values(
    raw_matched  =,
    sdtm_matched =,
    compare_vars =,
    map_row      =,
    raw_member   =,
    sdtm_ds      =,
    outval       =,
    run_label    =,
    run_ts       =
);

    %local c cv;
    %let c = 1;
    %let cv = %scan(&compare_vars., &c., %str( ));

    %do %while (&cv. ne );

        /* Merge matched datasets on COMP_KEY for this variable */
        proc sort data=&raw_matched.  out=_cmp_raw_s_  (keep=COMP_KEY &cv.) nodupkey;
            by COMP_KEY;
        run;
        proc sort data=&sdtm_matched. out=_cmp_sdtm_s_ (keep=COMP_KEY &cv.) nodupkey;
            by COMP_KEY;
        run;

        data _cmp_merged_;
            merge _cmp_raw_s_  (in=inr rename=(&cv.=_RAW_V_))
                  _cmp_sdtm_s_ (in=ins rename=(&cv.=_SDTM_V_));
            by COMP_KEY;
            if inr and ins;
        run;

        /* Detect discrepancies — convert to character for uniform handling */
        data _cmp_disc_;
            set _cmp_merged_;
            length RUN_LABEL $200 RUN_TS $20
                   VARNAME $32 RAW_VALUE $500 SDTM_VALUE $500;
            RUN_LABEL  = "&run_label.";
            RUN_TS     = "&run_ts.";
            MAP_ROW    = &map_row.;
            RAW_MEMBER = "&raw_member.";
            SDTM_DS    = "&sdtm_ds.";
            VARNAME    = "&cv.";

            /* Handle numeric and character dynamically via vtype */
            %local vtype_raw;
            proc sql noprint;
                select type into :vtype_raw trimmed
                from dictionary.columns
                where libname = 'WORK' and
                      memname = upcase("&raw_matched.") and
                      upcase(name) = "%upcase(&cv.)"
                ;
            quit;

            %if &vtype_raw. = num %then %do;
                RAW_VALUE  = strip(put(_RAW_V_,  best32.));
                SDTM_VALUE = strip(put(_SDTM_V_, best32.));
            %end;
            %else %do;
                RAW_VALUE  = strip(_RAW_V_);
                SDTM_VALUE = strip(_SDTM_V_);
            %end;

            if RAW_VALUE ne SDTM_VALUE;
            keep RUN_LABEL RUN_TS MAP_ROW RAW_MEMBER SDTM_DS COMP_KEY VARNAME RAW_VALUE SDTM_VALUE;
        run;

        proc append base=&outval. data=_cmp_disc_ force; run;

        %let c = %eval(&c. + 1);
        %let cv = %scan(&compare_vars., &c., %str( ));
    %end;

%mend qc_compare_values;
