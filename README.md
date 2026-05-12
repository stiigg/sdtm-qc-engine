# SDTM QC Engine

A **metadata-driven, directory-aware SAS macro engine** for raw-to-SDTM reconciliation quality control.

## Key Features

- Zero hardcoded dataset names, keys, or file paths
- Fully controlled by a mapping Excel workbook (`mapping_sheet.xlsx`)
- Supports ONE2ONE, ONE2MANY, MANY2ONE, MANY2MANY multiplicity
- Four standardized output datasets: OUTSUM, OUTDET, OUTVAL, OUTMETA
- Dynamic SAS library setup via `LIBNAME XLSX` and directory functions
- Optional value-level comparison for declared COMPARE_VARS
- Modes: RUN (full QC), CHECK_META_ONLY (spec validation only)

## Repository Structure

```
sdtm-qc-engine/
├── macros/
│   ├── %search_raw_dir.sas       ← Main orchestration macro
│   ├── %qc_validate_meta.sas     ← Spec/metadata validation
│   ├── %qc_run_mapping.sas       ← Per-mapping QC engine (10-step)
│   ├── %qc_normalize_key.sas     ← Key normalization utility
│   └── %qc_compare_values.sas    ← Value-level comparison utility
├── templates/
│   └── mapping_sheet_template.xlsx  ← Blank mapping sheet template
├── example/
│   ├── example_run.sas           ← End-to-end AE + LB worked example
│   ├── raw/                      ← Synthetic raw data (AE, LB)
│   └── sdtm/                     ← Synthetic SDTM data (AE, LB)
└── README.md
```

## Mapping Sheet Columns

| Column | Description |
|---|---|
| `RAW_MEMBER` | Raw SAS dataset member name |
| `SDTM_DS` | SDTM domain dataset name |
| `KEYVARS` | Space-separated reconciliation key variables |
| `COMPARE_VARS` | Space-separated variables for value comparison (optional) |
| `WHERE_RAW` | SAS WHERE clause to filter raw data |
| `WHERE_SDTM` | SAS WHERE clause to filter SDTM data |
| `REQUIRED_FL` | Y/N — flag mapping as mandatory |
| `EXPECTED_MULT` | ONE2ONE / ONE2MANY / MANY2ONE / MANY2MANY |

## Quick Start

```sas
%include 'macros/%search_raw_dir.sas';
%include 'macros/%qc_validate_meta.sas';
%include 'macros/%qc_run_mapping.sas';
%include 'macros/%qc_normalize_key.sas';
%include 'macros/%qc_compare_values.sas';

%search_raw_dir(
    raw_path   = /path/to/raw,
    sdtm_path  = /path/to/sdtm,
    map_file   = /path/to/mapping_sheet.xlsx,
    map_sheet  = MAPPINGS,
    outsum     = work.qc_summary,
    outdet     = work.qc_detail,
    outval     = work.qc_values,
    outmeta    = work.qc_meta,
    compare    = Y,
    mode       = RUN,
    debug      = N
);
```

## Output Datasets

| Dataset | Contents |
|---|---|
| `OUTSUM` | One row per mapping: domain, counts, mult status, overall pass/warn/fail |
| `OUTDET` | Record-level presence/absence by composite key |
| `OUTVAL` | Variable-level value discrepancies for matched keys |
| `OUTMETA` | Structural/spec issues: missing datasets, variables, invalid filters |

## License

MIT License — free to use and adapt for internal or published work.
