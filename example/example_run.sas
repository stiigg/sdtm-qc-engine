/*=============================================================================
  EXAMPLE : End-to-end worked example — AE (ONE2ONE) + LB (ONE2MANY)
  PURPOSE : Demonstrates the full %search_raw_dir engine using synthetic data.
            AE: 1-to-1 raw->SDTM with 2 purposeful value discrepancies.
            LB: 1-to-many raw->SDTM (one raw record expands to multiple tests).

  USAGE   : Update PATH_ROOT to your own working directory before running.
            Ensure all macro files are %included or placed in SASAUTOS.
=============================================================================*/

/* ---- 0. Configuration ---- */
%let path_root = /your/project/path;   /* <--- UPDATE THIS */
%let raw_path  = &path_root./raw;
%let sdtm_path = &path_root./sdtm;
%let map_file  = &path_root./mapping_sheet.xlsx;

/* ---- 1. Include macros ---- */
%include "&path_root./macros/qc_normalize_key.sas";
%include "&path_root./macros/qc_compare_values.sas";
%include "&path_root./macros/qc_validate_meta.sas";
%include "&path_root./macros/qc_run_mapping.sas";
%include "&path_root./macros/search_raw_dir.sas";

/* ---- 2. Create synthetic raw and SDTM libraries ---- */
libname RAW  "&raw_path.";
libname SDTM "&sdtm_path.";

/*--- Synthetic RAW AE (10 subjects, 1 AE each) ---*/
data raw.ae;
    infile datalines dsd;
    input USUBJID $12. AESTDTC $10. AETERM $40. AEBODSYS $60. AESEV $6. AESER $1.;
datalines;
STUDY-001-001,2024-01-10,HEADACHE,NERVOUS SYSTEM DISORDERS,MILD,N
STUDY-001-002,2024-01-12,NAUSEA,GASTROINTESTINAL DISORDERS,MILD,N
STUDY-001-003,2024-01-15,FATIGUE,GENERAL DISORDERS,MODERATE,N
STUDY-001-004,2024-01-18,DIZZINESS,NERVOUS SYSTEM DISORDERS,MILD,N
STUDY-001-005,2024-01-20,RASH,SKIN AND SUBCUTANEOUS TISSUE DISORDERS,MILD,N
STUDY-001-006,2024-01-22,VOMITING,GASTROINTESTINAL DISORDERS,MODERATE,N
STUDY-001-007,2024-01-25,INSOMNIA,PSYCHIATRIC DISORDERS,MILD,N
STUDY-001-008,2024-01-28,BACK PAIN,MUSCULOSKELETAL DISORDERS,MODERATE,N
STUDY-001-009,2024-01-30,COUGH,RESPIRATORY DISORDERS,MILD,N
STUDY-001-010,2024-02-01,ANAEMIA,BLOOD AND LYMPHATIC SYSTEM DISORDERS,SEVERE,Y
;
run;

/*--- Synthetic SDTM AE ---
  Purposeful discrepancies:
  Row 3: AESEV changed MODERATE->MILD
  Row 10: AEBODSYS slightly different (coding difference)
---*/
data sdtm.ae;
    infile datalines dsd;
    input USUBJID $12. AESTDTC $10. AETERM $40. AEBODSYS $60. AESEV $6. AESER $1.;
datalines;
STUDY-001-001,2024-01-10,HEADACHE,NERVOUS SYSTEM DISORDERS,MILD,N
STUDY-001-002,2024-01-12,NAUSEA,GASTROINTESTINAL DISORDERS,MILD,N
STUDY-001-003,2024-01-15,FATIGUE,GENERAL DISORDERS,MILD,N
STUDY-001-004,2024-01-18,DIZZINESS,NERVOUS SYSTEM DISORDERS,MILD,N
STUDY-001-005,2024-01-20,RASH,SKIN AND SUBCUTANEOUS TISSUE DISORDERS,MILD,N
STUDY-001-006,2024-01-22,VOMITING,GASTROINTESTINAL DISORDERS,MODERATE,N
STUDY-001-007,2024-01-25,INSOMNIA,PSYCHIATRIC DISORDERS,MILD,N
STUDY-001-008,2024-01-28,BACK PAIN,MUSCULOSKELETAL DISORDERS,MODERATE,N
STUDY-001-009,2024-01-30,COUGH,RESPIRATORY DISORDERS,MILD,N
STUDY-001-010,2024-02-01,ANAEMIA,BLOOD AND LYMPHATIC SYSTEM DISORDERS - HAEMATOLOGY,SEVERE,Y
;
run;

/*--- Synthetic RAW LB (5 subjects x 1 visit, multi-test expansion) ---*/
data raw.lb;
    infile datalines dsd;
    input USUBJID $12. VISITNUM 8. VISIT $8. HGB 8. WBC 8. PLT 8.;
datalines;
STUDY-001-001,1,WEEK 1,13.5,6.2,210
STUDY-001-002,1,WEEK 1,14.1,5.8,195
STUDY-001-003,1,WEEK 1,12.9,7.1,230
STUDY-001-004,1,WEEK 1,13.8,6.5,220
STUDY-001-005,1,WEEK 1,14.5,5.9,200
;
run;

/*--- Synthetic SDTM LB (one row per test — 3 tests per raw record = 15 rows) ---*/
data sdtm.lb;
    infile datalines dsd;
    input USUBJID $12. VISITNUM 8. VISIT $8. LBTESTCD $8. LBTEST $30. LBORRES $10.;
datalines;
STUDY-001-001,1,WEEK 1,HGB,Hemoglobin,13.5
STUDY-001-001,1,WEEK 1,WBC,White Blood Cells,6.2
STUDY-001-001,1,WEEK 1,PLT,Platelets,210
STUDY-001-002,1,WEEK 1,HGB,Hemoglobin,14.1
STUDY-001-002,1,WEEK 1,WBC,White Blood Cells,5.8
STUDY-001-002,1,WEEK 1,PLT,Platelets,195
STUDY-001-003,1,WEEK 1,HGB,Hemoglobin,12.9
STUDY-001-003,1,WEEK 1,WBC,White Blood Cells,7.1
STUDY-001-003,1,WEEK 1,PLT,Platelets,230
STUDY-001-004,1,WEEK 1,HGB,Hemoglobin,13.8
STUDY-001-004,1,WEEK 1,WBC,White Blood Cells,6.5
STUDY-001-004,1,WEEK 1,PLT,Platelets,220
STUDY-001-005,1,WEEK 1,HGB,Hemoglobin,14.5
STUDY-001-005,1,WEEK 1,WBC,White Blood Cells,5.9
STUDY-001-005,1,WEEK 1,PLT,Platelets,200
;
run;

/* ---- 3. Build mapping metadata in-memory (simulates Excel sheet read) ---- */
/* In production, the engine reads this from mapping_sheet.xlsx via LIBNAME XLSX.
   For this demo we create it directly in WORK so the example runs without Excel. */
data work.mappings;
    infile datalines dsd;
    length RAW_MEMBER $32 SDTM_DS $32 KEYVARS $200 COMPARE_VARS $200
           WHERE_RAW $200 WHERE_SDTM $200 REQUIRED_FL $1 EXPECTED_MULT $10;
    input RAW_MEMBER $ SDTM_DS $ KEYVARS $ COMPARE_VARS $ WHERE_RAW $
          WHERE_SDTM $ REQUIRED_FL $ EXPECTED_MULT $;
    MAP_ROW = _N_;
datalines;
AE,AE,USUBJID AESTDTC AETERM,AEBODSYS AESEV AESER,AETERM ne '',.,Y,ONE2ONE
LB,LB,USUBJID VISITNUM LBTESTCD,LBORRES,.,.,Y,ONE2MANY
;
run;

/* ---- 4. Run the QC engine ---- */
/* Note: in this demo we pass the work.mappings dataset directly by bypassing
   the Excel read inside %search_raw_dir. A production call uses map_file=.
   Here we call the sub-macros directly to show the full workflow. */

/* Initialize output datasets */
data work.qc_summary; length RUN_LABEL $200 RUN_TS $20 MAP_ROW 8 RAW_MEMBER $32 SDTM_DS $32
     EXPECTED_MULT $10 REQUIRED_FL $1 RAW_N 8 SDTM_N 8 COUNT_DIFF 8
     KEYS_ONLY_RAW 8 KEYS_ONLY_SDTM 8 MULT_STATUS $8 VALUE_DISC 8
     OVERALL $8 MESSAGE $500; stop; run;
data work.qc_detail;  length RUN_LABEL $200 MAP_ROW 8 RAW_MEMBER $32 SDTM_DS $32 COMP_KEY $500 IN_RAW 8 IN_SDTM 8; stop; run;
data work.qc_values;  length RUN_LABEL $200 MAP_ROW 8 RAW_MEMBER $32 SDTM_DS $32 COMP_KEY $500 VARNAME $32 RAW_VALUE $500 SDTM_VALUE $500; stop; run;
data work.qc_meta;    length RUN_LABEL $200 MAP_ROW 8 RAW_MEMBER $32 SDTM_DS $32 ISSUE_TYPE $30 ISSUE_MSG $500 SEVERITY $8; stop; run;

libname _RAWLIB_ "&raw_path.";
libname _SDTMLIB "&sdtm_path.";

/* Run AE mapping */
%qc_run_mapping(
    map_row      = 1,
    raw_member   = AE,
    sdtm_ds      = AE,
    keyvars      = USUBJID AESTDTC AETERM,
    compare_vars = AEBODSYS AESEV AESER,
    where_raw    = AETERM ne '',
    where_sdtm   = ,
    required_fl  = Y,
    exp_mult     = ONE2ONE,
    rawlib       = _RAWLIB_,
    sdtmlib      = _SDTMLIB,
    outsum       = work.qc_summary,
    outdet       = work.qc_detail,
    outval       = work.qc_values,
    outmeta      = work.qc_meta,
    compare      = Y,
    run_label    = EXAMPLE_RUN_AE_LB,
    run_ts       = %sysfunc(datetime(), datetime20.),
    debug        = N
);

/* Run LB mapping */
%qc_run_mapping(
    map_row      = 2,
    raw_member   = LB,
    sdtm_ds      = LB,
    keyvars      = USUBJID VISITNUM LBTESTCD,
    compare_vars = LBORRES,
    where_raw    = ,
    where_sdtm   = ,
    required_fl  = Y,
    exp_mult     = ONE2MANY,
    rawlib       = _RAWLIB_,
    sdtmlib      = _SDTMLIB,
    outsum       = work.qc_summary,
    outdet       = work.qc_detail,
    outval       = work.qc_values,
    outmeta      = work.qc_meta,
    compare      = Y,
    run_label    = EXAMPLE_RUN_AE_LB,
    run_ts       = %sysfunc(datetime(), datetime20.),
    debug        = N
);

/* ---- 5. Review outputs ---- */
title 'QC Summary — one row per mapping';
proc print data=work.qc_summary noobs; run;

title 'QC Detail — presence/absence discrepancies';
proc print data=work.qc_detail  noobs; run;

title 'QC Values — variable-level discrepancies';
proc print data=work.qc_values  noobs; run;

title 'QC Meta — structural/spec issues';
proc print data=work.qc_meta    noobs; run;
title;

/*
  EXPECTED RESULTS:

  qc_summary row 1 (AE):
    RAW_N=10, SDTM_N=10, COUNT_DIFF=0, KEYS_ONLY_RAW=0, KEYS_ONLY_SDTM=0
    MULT_STATUS=PASS, VALUE_DISC=2, OVERALL=WARN
    MESSAGE: 2 value discrepancies found (AESEV row 3, AEBODSYS row 10)

  qc_summary row 2 (LB):
    RAW_N=5, SDTM_N=15, COUNT_DIFF=-10, KEYS_ONLY_RAW=0, KEYS_ONLY_SDTM=0
    MULT_STATUS=PASS, VALUE_DISC=0, OVERALL=PASS
    (SDTM > RAW is expected for ONE2MANY — no warning triggered)

  qc_values (2 rows):
    COMP_KEY=STUDY-001-003|2024-01-15|FATIGUE, VARNAME=AESEV,
      RAW_VALUE=MODERATE, SDTM_VALUE=MILD
    COMP_KEY=STUDY-001-010|2024-02-01|ANAEMIA, VARNAME=AEBODSYS,
      RAW_VALUE=BLOOD AND LYMPHATIC SYSTEM DISORDERS,
      SDTM_VALUE=BLOOD AND LYMPHATIC SYSTEM DISORDERS - HAEMATOLOGY
*/
