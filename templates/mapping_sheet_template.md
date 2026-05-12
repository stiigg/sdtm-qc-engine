# Mapping Sheet Template

Create an Excel file named `mapping_sheet.xlsx` with a sheet named `MAPPINGS`.
The sheet must contain the following columns as the first row (header row).

## Required Columns

| Column Name    | Type    | Description |
|---|---|---|
| `RAW_MEMBER`   | Text    | Name of the raw SAS dataset member (e.g., `AE`, `LB`, `VS`) |
| `SDTM_DS`      | Text    | Name of the SDTM domain dataset (e.g., `AE`, `LB`, `VS`) |
| `KEYVARS`      | Text    | Space-separated list of reconciliation key variables (e.g., `USUBJID AESTDTC AETERM`) |
| `COMPARE_VARS` | Text    | Space-separated list of variables for value comparison. Leave blank to skip value comparison for this row. |
| `WHERE_RAW`    | Text    | SAS WHERE clause to filter raw data (e.g., `AETERM ne ''`). Leave blank for no filter. |
| `WHERE_SDTM`   | Text    | SAS WHERE clause to filter SDTM data. Leave blank for no filter. |
| `REQUIRED_FL`  | Text    | `Y` if this mapping is mandatory (SDTM must not be empty). `N` otherwise. |
| `EXPECTED_MULT`| Text    | Expected multiplicity: `ONE2ONE`, `ONE2MANY`, `MANY2ONE`, or `MANY2MANY` |

## Example Rows

| RAW_MEMBER | SDTM_DS | KEYVARS                     | COMPARE_VARS         | WHERE_RAW      | WHERE_SDTM | REQUIRED_FL | EXPECTED_MULT |
|---|---|---|---|---|---|---|---|
| AE         | AE      | USUBJID AESTDTC AETERM      | AEBODSYS AESEV AESER | AETERM ne ''   |            | Y           | ONE2ONE       |
| LB         | LB      | USUBJID VISITNUM LBTESTCD   | LBORRES              |                |            | Y           | ONE2MANY      |
| VS         | VS      | USUBJID VISITNUM VSTESTCD   | VSORRES              |                |            | Y           | ONE2MANY      |
| CM         | CM      | USUBJID CMSTDTC CMTRT       | CMDOSE CMDOSU        | CMTRT ne ''    |            | Y           | ONE2ONE       |
| DM_RAW     | DM      | USUBJID                     | DMDTC COUNTRY        |                |            | Y           | ONE2ONE       |

## Notes

- All column headers are case-insensitive; the macro uppercases them on read.
- Blank rows in the sheet are automatically skipped.
- The `LIBNAME XLSX` engine is used to read this file — no `PROC IMPORT` needed.
- The sheet name must match the `MAP_SHEET` parameter passed to `%search_raw_dir` (default: `MAPPINGS`).
