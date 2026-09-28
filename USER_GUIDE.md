# User Guide

## 1. Before you start

1. Put all product images in one **source folder**. Use either one sub-folder per model, or loose files named after the model (see the README).
2. Create a **mapping CSV** with a `model` column plus `ASIN` and/or `FSN`. Save it as CSV (UTF-8 is recommended) from Excel or Google Sheets.
3. Pick an **output folder**. It must be different from the source folder.

Image order matters. On Amazon, the first image becomes `MAIN`. On Flipkart, it becomes `_0` (or `_1`). Prefix file names with numbers if needed, such as `01_front.jpg` and `02_side.jpg`. Natural sorting keeps `2` before `10`.

## 2. Running a distribution

Double-click `Run_Smart_Image_Distribution.cmd` and choose **1. New distribution**.

1. **Platform:** 1 = Amazon, 2 = Flipkart, 3 = Both.
2. **Paths:** source folder, mapping CSV, and output folder. Paths can be pasted with or without quotes. Values in `[brackets]` come from your last run; press Enter to reuse them.
3. **Flipkart numbering** (Flipkart / Both): `0` gives `FSN_0, FSN_1…`, and `1` gives `FSN_1, FSN_2…`.
4. **Pre-flight summary:** rows, ready jobs, source images, and any issues.
5. **Choose an action:**
   - `1` Run. If there are issues, only the valid jobs run.
   - `2` Dry run. Writes reports only and changes no files. This is the default when issues exist.
   - `3` Cancel.
6. **Existing destinations:** you are asked this only if some output folders already contain images (see section 3).
7. **Confirm.** The tool copies, verifies, and writes reports.

## 3. When output folders already exist

| Option | Behaviour | Use when |
|---|---|---|
| 1. Smart update (default) | Copies new and changed files (SHA-256 compare), skips identical ones, and deletes images that no longer belong. | Updating a previous run. |
| 2. Backup & replace | Copies the affected folders to `Output\_Backup\<RunId>\`, clears their images, and copies everything fresh. | You want a clean rebuild with a safety copy. |
| 3. Skip them | Leaves those folders untouched and processes the rest. | Only new listings should be added. |
| 4. Cancel | Stops without changes. | |

Only image files (`.jpg .jpeg .png .webp`) are ever removed from destination folders. Other files are left alone.

## 4. What validation checks

| Check | Result |
|---|---|
| Missing model value | Row skipped |
| Missing ASIN / FSN | That platform skipped for the row |
| No images found for a model | Row skipped |
| More images than the platform limit | Job skipped |
| Exact duplicate row (same model → same ID) | Extra rows ignored |
| One ID mapped to **different** models | All those jobs blocked, because they would overwrite each other |
| Identical image content in several places | Warning only (`Duplicate_Images.csv`) |

## 5. Resume and retry

The tool saves progress after every job to `Smart_Image_Distribution_State.json`, next to the script. If a run is interrupted or some jobs fail, choose **2. Resume previous distribution**. It:

- re-reads the same CSV and source,
- skips jobs that already completed and folders you chose to skip,
- runs the rest with the same collision option,
- writes reports to `Reports\<RunId>_resume_<time>\`.

## 6. Reports

Each run writes CSVs to `Output\Reports\<RunId>\`. A file is only created if it has rows.

| Report | Contents |
|---|---|
| `Plan.csv` | Every job: platform, model, ID, image count, destination |
| `Job_Results.csv` | Per job: copied / updated / unchanged / removed counts, status, error |
| `Verification.csv` | Per job: PASS or FAIL after hash verification |
| `File_Comparison.csv` | Per file: `MATCH`, `CHANGED`, `MISSING`, `UNEXPECTED` |
| `Validation_Issues.csv` | Everything found in pre-flight |
| `Duplicate_Images.csv` | Groups of source files with identical content |
| `Image_Quality.csv` | Width, height, size in MB, and status for each source image |

Image quality statuses:

| Status | Meaning |
|---|---|
| `PASS` | Fine |
| `WARNING_SMALL` | The shortest side is below the minimum (500 px by default) |
| `ERROR_ZERO_BYTE` | Empty file |
| `NO_DIMENSIONS` | Could not be read. This is normal for `.webp`, because Windows' imaging library doesn't decode it |

A dry run writes `Plan`, `Validation_Issues`, `Duplicate_Images`, and `Image_Quality`.

## 7. Other menu options

- **Validate mapping only:** runs the pre-flight without asking for an output folder.
- **Scan image quality:** scans any folder recursively. The report is saved to `Reports\` next to the script.
- **Compare source vs output:** hash-checks an existing output against the source and CSV without copying anything. Useful before uploading.

## 8. Settings

Edit the top of `Smart_Image_Distribution.ps1`:

```powershell
$Extensions = @('.jpg', '.jpeg', '.png', '.webp')   # accepted image types
$MaxImages  = @{ Amazon = 13; Flipkart = 13 }       # per-listing image limit
$MinSide    = 500                                   # quality warning threshold (px)
```

Image limits differ by marketplace category, so set `$MaxImages` to match yours.

## 9. Files created next to the script

| File | Purpose |
|---|---|
| `Smart_Image_Distribution_LastConfig.json` | Last platform, paths, and numbering (used as defaults) |
| `Smart_Image_Distribution_State.json` | Progress of the last run (used by Resume) |

Both are local. They are excluded from Git by `.gitignore`, and you can delete them at any time.
