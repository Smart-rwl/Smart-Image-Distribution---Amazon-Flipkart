# Changelog

## [3.2] - 2026-09-28
### Fixed
- The Exit menu option no longer loops forever (`break` inside `switch`).
- The `Write-Progress -Completed` prompt on Windows PowerShell 5.1.
- Reusing the previous output path by pressing Enter.
- Different models mapped to the same ASIN/FSN silently overwrote each other; these jobs are now blocked.
- Smart Replace left stale images, which caused false verification failures.
- Success counts ignored updated and unchanged files; the job log lost columns in CSV.
- Resume re-processed folders the user had chosen to skip.
- Smart-quote handling broke when the script was saved without a BOM.

### Added
- Direct-files mode supports several images per model (`MODEL_1`, `MODEL-2`, `MODEL (3)`).
- An option to run only the valid jobs when validation finds issues.
- SHA-256 verification of every output file.
- Per-run report folders (`Reports\<RunId>\`).
- Backups of only the affected folders (`_Backup\<RunId>\`).

### Changed
- Removed the Safe / Standard / Fast processing modes; there is now one reliable mode.
- Validation and planning happen in a single cached pass, which is much faster on large catalogs.
- The quality scan no longer writes into the source folder.
- Default values are shown in `[brackets]` instead of a separate "use previous config?" question.

## [3.1]
- Initial public version: Amazon/Flipkart/Both, dry run, resume, collision handling, reports.
