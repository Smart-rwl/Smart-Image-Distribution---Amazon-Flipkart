# Troubleshooting

### Double-clicking the .cmd opens and closes instantly
- Keep `Run_Smart_Image_Distribution.cmd` and `Smart_Image_Distribution.ps1` in the **same folder**.
- Don't rename the `.ps1` file. If you do, update the `SCRIPT=` line in the `.cmd`.
- Run the `.cmd` from an open Command Prompt to see the message.

### "Running scripts is disabled on this system"
The launcher already uses `-ExecutionPolicy Bypass`, which applies to that window only. If you run the `.ps1` directly instead, either use the launcher or run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Smart_Image_Distribution.ps1
```

### Windows SmartScreen / "file came from another computer"
Files downloaded as a ZIP from GitHub are marked as coming from the internet. To clear that: right-click each file → **Properties** → tick **Unblock** → OK. Or run this in PowerShell:
```powershell
Get-ChildItem -Path . -Recurse | Unblock-File
```

### "CSV needs a model column / ASIN column / FSN column"
- Check the header row: `model`, `ASIN`, `FSN` (any letter case).
- Make sure the file is really comma-separated. Some regional Excel settings save with `;`. Re-save as **CSV UTF-8 (Comma delimited)**.
- **Both** mode needs ASIN *and* FSN columns.

### "No images found for model"
- **Model folders:** the folder name must equal the CSV model value exactly (spaces included).
- **Direct files:** the file must be named `MODEL.jpg`, `MODEL_1.jpg`, `MODEL-1.jpg` or `MODEL (1).jpg`.
- Check the extension. Only `.jpg .jpeg .png .webp` are read.

### The wrong source layout was detected
If the source folder contains **any** sub-folder, it is treated as *model folders*. For direct files, move stray sub-folders out of the source folder.

### An ID is "mapped to several models"
Two different models point to the same ASIN/FSN, which would overwrite each other's images. Fix the CSV. All affected jobs are held back until it is fixed.

### Wrong image became MAIN / _0
Order follows natural file-name sort. Rename files with number prefixes (`01_`, `02_` …). For direct files, the un-numbered `MODEL.jpg` is always first.

### Verification FAIL
Open `File_Comparison.csv`:
- `MISSING`: the copy failed. See the `Error` column in `Job_Results.csv`, then use **Resume**.
- `CHANGED`: the destination differs from the source. Re-run and choose **Smart update**.
- `UNEXPECTED`: an extra image is in the destination. **Smart update** removes it.

### A file is "being used by another process"
Close any image viewer, Explorer preview pane, or sync client (OneDrive or Google Drive) that is holding the file, then **Resume**.

### Paths with special characters
Paths with spaces, brackets `[ ]` and apostrophes are supported. Paste them with or without quotes.

### Reset the tool
Delete `Smart_Image_Distribution_LastConfig.json` and `Smart_Image_Distribution_State.json` next to the script.
