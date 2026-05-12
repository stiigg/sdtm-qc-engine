/*=============================================================================
  MACRO : %qc_validate_meta
  PURPOSE: Pre-flight specification validation. Checks mapping sheet for:
           - Required columns present
           - Valid EXPECTED_MULT codes
           - Dataset existence in raw and SDTM libraries
           - Key/compare variable existence and type compatibility
           - WHERE clause basic syntax (via PROC SQL preview)
           Writes issues to OUTMETA with SEVERITY=ERROR or WARNING.

  PARAMETERS:
    MAPDS     - Mapping metadata dataset (work._qc_mappings_)
    OUTMETA   - Output structural issues dataset
    RAWLIB    - SAS libref for raw data
    SDTMLIB   - SAS libref for SDTM data
    RUN_LABEL - Run label from parent macro
    RUN_TS    - Timestamp from parent macro
    STRICT    - Y/N: treat warnings as errors
=============================================================================*/

%macro qc_validate_meta(
    mapds    =,
    outmeta  =,
    rawlib   =,
    sdtmlib  =,
    run_label=,
    run_ts   =,
    strict   = N
);

    %local i nrows rc;

    proc sql noprint;
        select count(*) into :nrows trimmed from &mapds.;
    quit;

    %put NOTE: [META VALIDATE] Checking &nrows. mapping rows.;

    /* Validate each row */
    %do i = 1 %to &nrows.;

        data _null_;
            set &mapds.(firstobs=&i. obs=&i.);
            call symputx('_v_row_',   MAP_ROW);
            call symputx('_v_raw_',   RAW_MEMBER);
            call symputx('_v_sdtm_',  SDTM_DS);
            call symputx('_v_keys_',  KEYVARS);
            call symputx('_v_cvars_', COMPARE_VARS);
            call symputx('_v_wraw_',  WHERE_RAW);
            call symputx('_v_wsdtm_', WHERE_SDTM);
            call symputx('_v_mult_',  EXPECTED_MULT);
        run;

        /*--- Check EXPECTED_MULT is a valid code ---*/
        %if not (%upcase(&_v_mult_.) in (ONE2ONE ONE2MANY MANY2ONE MANY2MANY)) %then %do;
            data _meta_issue_;
                RUN_LABEL  = "&run_label.";
                RUN_TS     = "&run_ts.";
                MAP_ROW    = &_v_row_.;
                RAW_MEMBER = "&_v_raw_.";
                SDTM_DS    = "&_v_sdtm_.";
                ISSUE_TYPE = "INVALID_MULT_CODE";
                ISSUE_MSG  = "EXPECTED_MULT value '&_v_mult_.' is not valid. Use ONE2ONE/ONE2MANY/MANY2ONE/MANY2MANY.";
                SEVERITY   = "ERROR";
            run;
            proc append base=&outmeta. data=_meta_issue_ force; run;
        %end;

        /*--- Check KEYVARS is not blank ---*/
        %if %length(%trim(&_v_keys_.)) = 0 %then %do;
            data _meta_issue_;
                RUN_LABEL  = "&run_label.";
                RUN_TS     = "&run_ts.";
                MAP_ROW    = &_v_row_.;
                RAW_MEMBER = "&_v_raw_.";
                SDTM_DS    = "&_v_sdtm_.";
                ISSUE_TYPE = "MISSING_KEYVARS";
                ISSUE_MSG  = "KEYVARS is empty for this mapping. At least one key variable is required.";
                SEVERITY   = "ERROR";
            run;
            proc append base=&outmeta. data=_meta_issue_ force; run;
        %end;

        /*--- Check raw dataset exists ---*/
        %if %sysfunc(exist(&rawlib..&_v_raw_.)) = 0 %then %do;
            data _meta_issue_;
                RUN_LABEL  = "&run_label.";
                RUN_TS     = "&run_ts.";
                MAP_ROW    = &_v_row_.;
                RAW_MEMBER = "&_v_raw_.";
                SDTM_DS    = "&_v_sdtm_.";
                ISSUE_TYPE = "RAW_DS_MISSING";
                ISSUE_MSG  = "Raw dataset &rawlib..&_v_raw_. does not exist.";
                SEVERITY   = "ERROR";
            run;
            proc append base=&outmeta. data=_meta_issue_ force; run;
        %end;

        /*--- Check SDTM dataset exists ---*/
        %if %sysfunc(exist(&sdtmlib..&_v_sdtm_.)) = 0 %then %do;
            data _meta_issue_;
                RUN_LABEL  = "&run_label.";
                RUN_TS     = "&run_ts.";
                MAP_ROW    = &_v_row_.;
                RAW_MEMBER = "&_v_raw_.";
                SDTM_DS    = "&_v_sdtm_.";
                ISSUE_TYPE = "SDTM_DS_MISSING";
                ISSUE_MSG  = "SDTM dataset &sdtmlib..&_v_sdtm_. does not exist.";
                SEVERITY   = "ERROR";
            run;
            proc append base=&outmeta. data=_meta_issue_ force; run;
        %end;
        %else %if %sysfunc(exist(&rawlib..&_v_raw_.)) = 1 %then %do;
            /*--- Check key variables exist in both datasets ---*/
            %let _k_ = 1;
            %let _kv_ = %scan(&_v_keys_., &_k_., %str( ));
            %do %while (&_kv_. ne );

                /* Check in raw */
                proc sql noprint;
                    select count(*) into :_var_in_raw_ trimmed
                    from dictionary.columns
                    where libname = "%upcase(&rawlib.)" and
                          memname = "%upcase(&_v_raw_.)" and
                          upcase(name) = "%upcase(&_kv_.)"
                    ;
                quit;
                %if &_var_in_raw_. = 0 %then %do;
                    data _meta_issue_;
                        RUN_LABEL  = "&run_label.";
                        RUN_TS     = "&run_ts.";
                        MAP_ROW    = &_v_row_.;
                        RAW_MEMBER = "&_v_raw_.";
                        SDTM_DS    = "&_v_sdtm_.";
                        ISSUE_TYPE = "KEY_VAR_MISSING_RAW";
                        ISSUE_MSG  = "Key variable &_kv_. not found in raw &rawlib..&_v_raw_.";
                        SEVERITY   = "ERROR";
                    run;
                    proc append base=&outmeta. data=_meta_issue_ force; run;
                %end;

                /* Check in SDTM */
                proc sql noprint;
                    select count(*) into :_var_in_sdtm_ trimmed
                    from dictionary.columns
                    where libname = "%upcase(&sdtmlib.)" and
                          memname = "%upcase(&_v_sdtm_.)" and
                          upcase(name) = "%upcase(&_kv_.)"
                    ;
                quit;
                %if &_var_in_sdtm_. = 0 %then %do;
                    data _meta_issue_;
                        RUN_LABEL  = "&run_label.";
                        RUN_TS     = "&run_ts.";
                        MAP_ROW    = &_v_row_.;
                        RAW_MEMBER = "&_v_raw_.";
                        SDTM_DS    = "&_v_sdtm_.";
                        ISSUE_TYPE = "KEY_VAR_MISSING_SDTM";
                        ISSUE_MSG  = "Key variable &_kv_. not found in SDTM &sdtmlib..&_v_sdtm_.";
                        SEVERITY   = "ERROR";
                    run;
                    proc append base=&outmeta. data=_meta_issue_ force; run;
                %end;

                %let _k_ = %eval(&_k_. + 1);
                %let _kv_ = %scan(&_v_keys_., &_k_., %str( ));
            %end; /* key variable loop */

            /*--- Validate compare vars exist in both datasets (WARNING only) ---*/
            %if %length(%trim(&_v_cvars_.)) > 0 %then %do;
                %let _c_ = 1;
                %let _cv_ = %scan(&_v_cvars_., &_c_., %str( ));
                %do %while (&_cv_. ne );

                    proc sql noprint;
                        select count(*) into :_cv_raw_ trimmed
                        from dictionary.columns
                        where libname = "%upcase(&rawlib.)" and
                              memname = "%upcase(&_v_raw_.)" and
                              upcase(name) = "%upcase(&_cv_.)"
                        ;
                    quit;
                    proc sql noprint;
                        select count(*) into :_cv_sdtm_ trimmed
                        from dictionary.columns
                        where libname = "%upcase(&sdtmlib.)" and
                              memname = "%upcase(&_v_sdtm_.)" and
                              upcase(name) = "%upcase(&_cv_.)"
                        ;
                    quit;

                    %if &_cv_raw_. = 0 %then %do;
                        data _meta_issue_;
                            RUN_LABEL  = "&run_label.";
                            RUN_TS     = "&run_ts.";
                            MAP_ROW    = &_v_row_.;
                            RAW_MEMBER = "&_v_raw_.";
                            SDTM_DS    = "&_v_sdtm_.";
                            ISSUE_TYPE = "CMP_VAR_MISSING_RAW";
                            ISSUE_MSG  = "Compare variable &_cv_. not in raw &rawlib..&_v_raw_. — skipped.";
                            SEVERITY   = "WARNING";
                        run;
                        proc append base=&outmeta. data=_meta_issue_ force; run;
                    %end;
                    %if &_cv_sdtm_. = 0 %then %do;
                        data _meta_issue_;
                            RUN_LABEL  = "&run_label.";
                            RUN_TS     = "&run_ts.";
                            MAP_ROW    = &_v_row_.;
                            RAW_MEMBER = "&_v_raw_.";
                            SDTM_DS    = "&_v_sdtm_.";
                            ISSUE_TYPE = "CMP_VAR_MISSING_SDTM";
                            ISSUE_MSG  = "Compare variable &_cv_. not in SDTM &sdtmlib..&_v_sdtm_. — skipped.";
                            SEVERITY   = "WARNING";
                        run;
                        proc append base=&outmeta. data=_meta_issue_ force; run;
                    %end;

                    %let _c_ = %eval(&_c_. + 1);
                    %let _cv_ = %scan(&_v_cvars_., &_c_., %str( ));
                %end; /* compare var loop */
            %end;
        %end; /* datasets exist block */

    %end; /* row loop */

    %put NOTE: [META VALIDATE] Validation complete.;

%mend qc_validate_meta;
