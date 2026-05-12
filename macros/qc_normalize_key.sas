/*=============================================================================
  MACRO : %qc_normalize_key
  PURPOSE: Build a stable composite key from one or more key variables.
           - Numeric variables are converted to BEST32. character representation
           - Character variables are stripped and left-aligned
           - Components are concatenated with a pipe delimiter '|'
           - Result is stored in variable COMP_KEY in the output dataset

  PARAMETERS:
    INDS     - Input dataset
    OUTDS    - Output dataset (INDS with COMP_KEY added)
    KEYVARS  - Space-separated list of key variable names
    LIBREF   - Library where INDS resides (used for type lookup)
=============================================================================*/

%macro qc_normalize_key(
    inds    =,
    outds   =,
    keyvars =,
    libref  =
);

    %local k kv ktype concat_expr;
    %let concat_expr = ;

    /* Build concatenation expression dynamically based on variable types */
    %let k = 1;
    %let kv = %scan(&keyvars., &k., %str( ));

    %do %while (&kv. ne );

        /* Look up variable type */
        proc sql noprint;
            select type into :ktype trimmed
            from dictionary.columns
            where libname = "%upcase(&libref.)" and
                  memname = "%upcase(%scan(&inds., 2, '.'))" and
                  upcase(name) = "%upcase(&kv.)"
            ;
        quit;

        %if &ktype. = num %then %do;
            %if %length(&concat_expr.) > 0 %then
                %let concat_expr = &concat_expr. || '|' ||;
            %let concat_expr = &concat_expr. strip(put(&kv., best32.));
        %end;
        %else %do;
            %if %length(&concat_expr.) > 0 %then
                %let concat_expr = &concat_expr. || '|' ||;
            %let concat_expr = &concat_expr. strip(&kv.);
        %end;

        %let k = %eval(&k. + 1);
        %let kv = %scan(&keyvars., &k., %str( ));
    %end;

    data &outds.;
        set &inds.;
        length COMP_KEY $500;
        COMP_KEY = &concat_expr.;
    run;

%mend qc_normalize_key;
