<img src="https://raw.githubusercontent.com/Smart-rwl/Smart-Image-Distribution-Tool/main/assets/smart-image-distribution-banner.png"
     alt="Smart Image Distribution Tool"
     width="100%">


# Smart Image Distribution Tool

A Windows PowerShell tool that renames and sorts product images into **Amazon** and **Flipkart** upload-ready folders from one mapping CSV. It is safe to re-run, can resume after a crash, and verifies every file it writes.

```
Source\M1234\front.jpg, side.jpg, back.jpg        Output\B0ABC12345\B0ABC12345.MAIN.jpg
Mapping.csv:  model=M1234, ASIN=B0ABC12345   ──►                 B0ABC12345.PT01.jpg
                                                                  B0ABC12345.PT02.jpg
```

## Features

- **Amazon, Flipkart, or both** in one run from a single CSV.
- **Amazon naming:** `ASIN.MAIN`, `ASIN.PT01` … **Flipkart naming:** `FSN_0` … or `FSN_1` … (you choose).
- **Two source layouts:** one folder per model, or loose files named after the model.
- **Natural sorting,** so `img2` comes before `img10`.
- **Pre-flight validation:** missing IDs, missing images, image limits, duplicate rows, and one ID mapped to several models.
- **Dry run** writes the plan and reports without touching any files.
- **Smart update** copies only new or changed files (SHA-256) and removes stale images.
- **Backup & replace** backs up only the affected folders first.
- **Resume** continues an interrupted run where it stopped.
- **Verification:** every output file is hash-checked against its source.
- **Reports:** CSV reports for the plan, job results, verification, duplicate images, and image quality.
- **Remembers** your last paths and settings.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in) or PowerShell 7+
- No installs or modules needed

## Quick start

1. Download or clone this repository.
2. Prepare your source images and a mapping CSV (see [`examples/`](examples/)).
3. Double-click **`Run_Smart_Image_Distribution.cmd`**.
4. Choose **1. New distribution**. Run a **Dry run** first, then **Run**.

Command-line alternative:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Smart_Image_Distribution.ps1
```

## Source layouts

The layout is detected automatically.

| Layout | Structure | Image order |
|---|---|---|
| Model folders | `Source\<model>\*.jpg` | Natural sort of file names. The first image becomes MAIN / `_0`. |
| Direct files | `Source\<model>.jpg`, `<model>_1.jpg`, `<model>-2.jpg`, `<model> (3).jpg` | The plain `<model>` file comes first, then the numbered files. |

Supported formats: `.jpg`, `.jpeg`, `.png`, `.webp`. The original extension is kept.

## Mapping CSV

| Column | Required for | Accepted header names (case-insensitive) |
|---|---|---|
| Model | always | `model`, `model_code`, `model code`, `modelcode` |
| ASIN | Amazon / Both | `asin` |
| FSN | Flipkart / Both | `fsn` |

```csv
model,ASIN,FSN
M1234,B0ABC12345,LMPGH7ZQXYZ12345
M5678,B0DEF67890,LMPGH7ZQXYZ67890
```

## Output layout

| Platform | Folder | File names |
|---|---|---|
| Amazon | `Output\<ASIN>\` | `<ASIN>.MAIN.jpg`, `<ASIN>.PT01.jpg` … |
| Flipkart | `Output\<FSN>\` | `<FSN>_0.jpg` … or `<FSN>_1.jpg` … |
| Both | `Output\Amazon\<ASIN>\` and `Output\Flipkart\<FSN>\` | as above |

Reports are written to `Output\Reports\<RunId>\`, and backups to `Output\_Backup\<RunId>\`.

## Menu

| Option | What it does |
|---|---|
| 1. New distribution | Validate, preview, then run or dry run. |
| 2. Resume previous distribution | Continue unfinished or failed jobs from the last run. |
| 3. Validate mapping only | Check the CSV and source without an output folder. |
| 4. Scan image quality | Dimensions, size, and zero-byte check for any folder. |
| 5. Compare source vs output | Hash-compare an existing output against the source. |
| 6. Exit | Close the tool. |

## Documentation

- [User guide](docs/USER_GUIDE.md): full walkthrough, collision options, resume, reports, and settings
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Changelog](CHANGELOG.md)

## Project structure

```
├── Smart_Image_Distribution.ps1       # the tool
├── Run_Smart_Image_Distribution.cmd   # one-click launcher
├── examples/
│   └── mapping_sample.csv
├── docs/
│   ├── USER_GUIDE.md
│   └── TROUBLESHOOTING.md
├── CHANGELOG.md
├── LICENSE
├── .gitignore
└── .gitattributes
```

## License

MIT. See [LICENSE](LICENSE).
