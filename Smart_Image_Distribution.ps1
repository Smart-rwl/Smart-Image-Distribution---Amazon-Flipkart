#requires -Version 5.1
<#
    SMART IMAGE DISTRIBUTION TOOL v3.2  (SmartRWL)
    Distributes model images into marketplace-ready folders.

      Amazon  : <ASIN>\<ASIN>.MAIN.jpg, <ASIN>.PT01.jpg ...
      Flipkart: <FSN>\<FSN>_0.jpg ...  (or _1 ...)

    Source layouts:
      ModelFolders : Source\<model>\*.jpg
      DirectFiles  : Source\<model>.jpg  or  <model>_1.jpg, <model>-2.jpg, "<model> (3).jpg" ...

    Mapping CSV: a model column (model / model_code) plus ASIN and/or FSN.
#>

$ErrorActionPreference = 'Stop'

# ------------------------------ Settings ------------------------------
$Version    = '3.2'
$Extensions = @('.jpg', '.jpeg', '.png', '.webp')
$MaxImages  = @{ Amazon = 13; Flipkart = 13 }   # per-listing limit; lower it to match your category
$MinSide    = 500                               # px; smaller images get a quality warning

$Root       = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ConfigPath = Join-Path $Root 'Smart_Image_Distribution_LastConfig.json'
$StatePath  = Join-Path $Root 'Smart_Image_Distribution_State.json'
$script:ImageCache = @{}
$script:HashCache  = @{}
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# ------------------------------ Console helpers ------------------------------
function Say([string]$Text, [string]$Color = 'White') { Write-Host $Text -ForegroundColor $Color }
function Pause-Tool { Read-Host 'Press Enter to continue' | Out-Null }
function Yes([string]$Text) { (Read-Host "$Text [Y/N]") -match '^(?i)y(es)?$' }

function Clean-Path([string]$p) {
    if (-not $p) { return '' }
    # Accept paths pasted with quotes, including Windows smart quotes
    $p.Trim().Trim([char[]]@([char]'"', [char]0x201C, [char]0x201D)).Trim()
}

function Read-Choice([string]$Prompt, [string[]]$Allowed, [string]$Default) {
    $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    while ($true) {
        $v = ([string](Read-Host $label)).Trim()
        if (-not $v -and $Default) { return $Default }
        if ($Allowed -contains $v) { return $v }
        Say "Choose one of: $($Allowed -join ', ')" Red
    }
}

function Read-Path([string]$Prompt, [ValidateSet('Folder', 'Csv', 'Output')][string]$Kind, [string]$Default) {
    $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    while ($true) {
        $p = Clean-Path (Read-Host $label)
        if (-not $p) { $p = $Default }
        if (-not $p) { Say 'Path cannot be empty.' Red; continue }
        switch ($Kind) {
            'Folder' { if (Test-Path -LiteralPath $p -PathType Container) { return (Resolve-Path -LiteralPath $p).Path } }
            'Csv'    { if ((Test-Path -LiteralPath $p -PathType Leaf) -and $p -like '*.csv') { return (Resolve-Path -LiteralPath $p).Path } }
            'Output' { try { New-Item -ItemType Directory -Path $p -Force | Out-Null; return (Resolve-Path -LiteralPath $p).Path } catch { Say $_.Exception.Message Red } }
        }
        Say "Not a valid $Kind path: $p" Red
    }
}

function Read-Json([string]$Path) {
    if (Test-Path -LiteralPath $Path) { try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch {} }
    $null
}
function Save-Json([string]$Path, $Data) { $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8 }

function Show-Banner([string]$Title) {
    Clear-Host
    Say ('=' * 62) Cyan
    Say "  SMART IMAGE DISTRIBUTION TOOL v$Version   |   SmartRWL" Cyan
    Say '  Amazon: ID.MAIN, ID.PT01...     Flipkart: ID_0 / ID_1...'
    Say ('=' * 62) Cyan
    if ($Title) { Say "`n$Title`n" Yellow }
}

# ------------------------------ Source discovery ------------------------------
function Test-Image($f) { (-not $f.PSIsContainer) -and ($Extensions -contains $f.Extension.ToLowerInvariant()) }

function Sort-Natural {
    $input | Sort-Object @{ Expression = { [regex]::Replace($_.BaseName, '\d+', { param($m) $m.Value.PadLeft(12, '0') }) } }, Name
}

function Get-SourceMode([string]$Source) {
    $items = @(Get-ChildItem -LiteralPath $Source -Force)
    if (@($items | Where-Object { $_.PSIsContainer }).Count) { return 'ModelFolders' }
    if (@($items | Where-Object { Test-Image $_ }).Count) { return 'DirectFiles' }
    'Unknown'
}

function Get-ModelImages([string]$Source, [string]$Model, [string]$Mode) {
    $key = "$Mode|$Source|$Model"
    if (-not $script:ImageCache.ContainsKey($key)) {
        $imgs = @()
        if ($Mode -eq 'ModelFolders') {
            $dir = Join-Path $Source $Model
            if (Test-Path -LiteralPath $dir -PathType Container) {
                $imgs = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { Test-Image $_ } | Sort-Natural)
            }
        } else {
            $listKey = "#list|$Source"
            if (-not $script:ImageCache.ContainsKey($listKey)) {
                $script:ImageCache[$listKey] = @(Get-ChildItem -LiteralPath $Source -File | Where-Object { Test-Image $_ })
            }
            $rx = '^' + [regex]::Escape($Model) + '([ _-]\(?\d+\)?)?$'
            $imgs = @($script:ImageCache[$listKey] | Where-Object { $_.BaseName -match $rx } | Sort-Natural)
        }
        $script:ImageCache[$key] = $imgs
    }
    $script:ImageCache[$key]
}

function Get-Hash([string]$Path, [switch]$Cache) {
    if ($Cache -and $script:HashCache.ContainsKey($Path)) { return $script:HashCache[$Path] }
    $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Cache) { $script:HashCache[$Path] = $h }
    $h
}

# ------------------------------ Mapping + plan ------------------------------
function Get-Columns($Rows, [string]$Platform) {
    $props = @($Rows[0].PSObject.Properties.Name)
    $find  = { param($names) $names | Where-Object { $props -contains $_ } | Select-Object -First 1 }   # -contains is case-insensitive
    $cols  = @{ Model = (& $find @('model', 'model_code', 'model code', 'modelcode')) }
    if (-not $cols.Model) { throw 'CSV needs a model column (model / model_code).' }
    if ($Platform -ne 'Flipkart') { $cols.Amazon   = & $find @('asin'); if (-not $cols.Amazon)   { throw 'CSV needs an ASIN column.' } }
    if ($Platform -ne 'Amazon')   { $cols.Flipkart = & $find @('fsn');  if (-not $cols.Flipkart) { throw 'CSV needs an FSN column.' } }
    $cols
}

function Get-OutputName([string]$Platform, [string]$Id, [int]$Pos, [int]$Start, [string]$Ext) {
    if ($Platform -eq 'Amazon') {
        if ($Pos -eq 1) { return "$Id.MAIN$Ext" }
        return ('{0}.PT{1:D2}{2}' -f $Id, ($Pos - 1), $Ext)
    }
    '{0}_{1}{2}' -f $Id, ($Pos - 1 + $Start), $Ext
}

# Validation and planning in one pass: returns ready jobs + issues
function Get-Jobs($Cfg) {
    $rows = @(Import-Csv -LiteralPath $Cfg.Csv)
    if (-not $rows.Count) { throw 'Mapping CSV is empty.' }
    $cols    = Get-Columns $rows $Cfg.Platform
    $targets = if ($Cfg.Platform -eq 'Both') { @('Amazon', 'Flipkart') } else { @($Cfg.Platform) }
    $out     = if ($Cfg.Output) { $Cfg.Output } else { $Cfg.Source }
    $issues  = New-Object System.Collections.Generic.List[string]
    $jobs    = @(); $seen = @{}; $rowNo = 1

    foreach ($r in $rows) {
        $rowNo++
        $model = ([string]$r.($cols.Model)).Trim()
        if (-not $model) { $issues.Add("Row ${rowNo}: missing model"); continue }
        $imgs = @(Get-ModelImages $Cfg.Source $model $Cfg.Mode)
        if (-not $imgs.Count) { $issues.Add("Row ${rowNo}: no images found for model '$model'") }

        foreach ($p in $targets) {
            $id = ([string]$r.($cols[$p])).Trim()
            if (-not $id) { $issues.Add("Row ${rowNo}: missing $p ID for '$model'"); continue }
            if (-not $imgs.Count) { continue }
            if ($imgs.Count -gt $MaxImages[$p]) { $issues.Add("Row ${rowNo}: '$model' has $($imgs.Count) images; $p limit is $($MaxImages[$p])"); continue }
            $key = "$p|$model|$id"
            if ($seen.ContainsKey($key)) { $issues.Add("Row ${rowNo}: duplicate row '$model' -> $p $id (ignored)"); continue }
            $seen[$key] = $true
            $dest  = if ($Cfg.Platform -eq 'Both') { Join-Path (Join-Path $out $p) $id } else { Join-Path $out $id }
            $names = @(0..($imgs.Count - 1) | ForEach-Object { Get-OutputName $p $id ($_ + 1) $Cfg.StartIndex $imgs[$_].Extension.ToLowerInvariant() })
            $jobs += [pscustomobject]@{ Key = $key; Platform = $p; Model = $model; ID = $id; Images = $imgs; Names = $names; Destination = $dest }
        }
    }

    # Different models mapped to the same ID would overwrite each other: block them
    $clash = @{}
    foreach ($g in @($jobs | Group-Object Platform, ID | Where-Object { $_.Count -gt 1 })) {
        $issues.Add(("{0} ID '{1}' is mapped to several models: {2}" -f $g.Group[0].Platform, $g.Group[0].ID, ($g.Group.Model -join ', ')))
        foreach ($j in $g.Group) { $clash[$j.Key] = $true }
    }
    $jobs = @($jobs | Where-Object { -not $clash[$_.Key] })

    [pscustomobject]@{
        Rows   = $rows.Count
        Jobs   = $jobs
        Images = @($jobs | ForEach-Object { $_.Images } | ForEach-Object { $_.FullName } | Select-Object -Unique).Count
        Issues = @($issues)
    }
}

function Show-Check($Cfg, $Check) {
    Say ''
    Say "Platform      : $($Cfg.Platform)"
    Say "Source mode   : $($Cfg.Mode)"
    Say "CSV rows      : $($Check.Rows)"
    Say "Ready jobs    : $($Check.Jobs.Count)"
    Say "Source images : $($Check.Images)"
    if ($Check.Issues.Count) {
        Say "Issues        : $($Check.Issues.Count)" Yellow
        $Check.Issues | Select-Object -First 20 | ForEach-Object { Say "  - $_" Yellow }
        if ($Check.Issues.Count -gt 20) { Say '  ... full list in Validation_Issues.csv' Yellow }
    } else { Say 'Result        : PASS' Green }
}

# ------------------------------ Checks / reports ------------------------------
function Get-HashDuplicates($Jobs) {
    $files = @{}
    foreach ($j in $Jobs) { foreach ($f in $j.Images) { if (-not $files.ContainsKey($f.FullName)) { $files[$f.FullName] = "$($j.Model)\$($f.Name)" } } }
    @($files.Keys | ForEach-Object { [pscustomobject]@{ Hash = (Get-Hash $_ -Cache); File = $files[$_] } } |
        Group-Object Hash | Where-Object { $_.Count -gt 1 } |
        ForEach-Object { [pscustomobject]@{ Hash = $_.Name; Count = $_.Count; Files = ($_.Group.File -join '; ') } })
}

function Get-ImageInfo([IO.FileInfo]$File) {
    $w = $null; $h = $null
    try {
        $fs = [IO.File]::OpenRead($File.FullName)
        try { $img = [Drawing.Image]::FromStream($fs, $false, $false); $w = $img.Width; $h = $img.Height; $img.Dispose() } finally { $fs.Dispose() }
    } catch {}
    $status = if ($File.Length -eq 0) { 'ERROR_ZERO_BYTE' } elseif ($null -eq $w) { 'NO_DIMENSIONS (e.g. webp)' } elseif ([math]::Min($w, $h) -lt $MinSide) { 'WARNING_SMALL' } else { 'PASS' }
    [pscustomobject]@{ File = $File.FullName; MB = [math]::Round($File.Length / 1MB, 2); Width = $w; Height = $h; Status = $status }
}

function Get-SourceQuality($Jobs) {
    $files = @{}
    foreach ($j in $Jobs) { foreach ($f in $j.Images) { $files[$f.FullName] = $f } }
    @($files.Values | ForEach-Object { Get-ImageInfo $_ })
}

# File-level comparison of expected output vs what is actually on disk (SHA-256)
function Compare-Jobs($Jobs) {
    foreach ($j in $Jobs) {
        $actual = @()
        if (Test-Path -LiteralPath $j.Destination) { $actual = @(Get-ChildItem -LiteralPath $j.Destination -File | Where-Object { Test-Image $_ } | ForEach-Object { $_.Name }) }
        for ($i = 0; $i -lt $j.Images.Count; $i++) {
            $dst = Join-Path $j.Destination $j.Names[$i]
            $status = if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { 'MISSING' } elseif ((Get-Hash $j.Images[$i].FullName -Cache) -eq (Get-Hash $dst)) { 'MATCH' } else { 'CHANGED' }
            [pscustomobject]@{ Platform = $j.Platform; Model = $j.Model; ID = $j.ID; Image = $j.Names[$i]; Source = $j.Images[$i].FullName; Status = $status }
        }
        foreach ($x in @($actual | Where-Object { $j.Names -notcontains $_ })) {
            [pscustomobject]@{ Platform = $j.Platform; Model = $j.Model; ID = $j.ID; Image = $x; Source = ''; Status = 'UNEXPECTED' }
        }
    }
}

function Get-Verification($Compare) {
    @($Compare | Group-Object Platform, ID | ForEach-Object {
        $bad = @($_.Group | Where-Object { $_.Status -ne 'MATCH' })
        [pscustomobject]@{ Platform = $_.Group[0].Platform; Model = $_.Group[0].Model; ID = $_.Group[0].ID; Files = $_.Count; Problems = $bad.Count; Status = $(if ($bad.Count) { 'FAIL' } else { 'PASS' }) }
    })
}

function Get-PlanRows($Jobs)    { $Jobs | Select-Object Platform, Model, ID, @{ n = 'Images'; e = { $_.Images.Count } }, Destination }
function Get-IssueRows($Issues) { $Issues | ForEach-Object { [pscustomobject]@{ Issue = $_ } } }
function Get-Sum($Items, [string]$Prop) { [int](($Items | Measure-Object -Property $Prop -Sum).Sum) }

function Save-Reports([string]$Dir, [hashtable]$Reports) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    foreach ($name in $Reports.Keys) {
        $data = @($Reports[$name] | Where-Object { $_ })
        if ($data.Count) { $data | Export-Csv -LiteralPath (Join-Path $Dir "$name.csv") -NoTypeInformation -Encoding UTF8 }
    }
    Say "Reports: $Dir" Cyan
}

# ------------------------------ Copy engine ------------------------------
function Get-Collisions($Jobs) {
    @($Jobs | Where-Object { (Test-Path -LiteralPath $_.Destination) -and @(Get-ChildItem -LiteralPath $_.Destination -File | Where-Object { Test-Image $_ }).Count })
}

function Backup-Folders($Jobs, [string]$Output, [string]$RunId) {
    $root = Join-Path $Output "_Backup\$RunId"
    foreach ($j in $Jobs) {
        $to = Join-Path $root $j.Destination.Substring($Output.Length).TrimStart('\')
        New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $j.Destination -Destination $to -Recurse -Force
    }
    $root
}

# Collision = 'SmartReplace' (copy new/changed, drop stale images) or 'Replace' (clear images, copy all)
function Invoke-Jobs($Jobs, $State) {
    $n = 0
    foreach ($j in $Jobs) {
        $n++
        Write-Progress -Activity 'Distributing images' -Status "$n/$($Jobs.Count)  $($j.Platform): $($j.Model) -> $($j.ID)" -PercentComplete ([int](100 * $n / $Jobs.Count))
        $r = [ordered]@{ RunId = $State.RunId; Platform = $j.Platform; Model = $j.Model; ID = $j.ID; Images = $j.Images.Count; Copied = 0; Updated = 0; Unchanged = 0; Removed = 0; Status = 'OK'; Error = '' }
        try {
            New-Item -ItemType Directory -Path $j.Destination -Force | Out-Null
            foreach ($old in @(Get-ChildItem -LiteralPath $j.Destination -File | Where-Object { Test-Image $_ })) {
                if ($State.Collision -eq 'Replace' -or $j.Names -notcontains $old.Name) { Remove-Item -LiteralPath $old.FullName -Force; $r.Removed++ }
            }
            for ($i = 0; $i -lt $j.Images.Count; $i++) {
                $src = $j.Images[$i]
                $dst = Join-Path $j.Destination $j.Names[$i]
                if (Test-Path -LiteralPath $dst -PathType Leaf) {
                    if ((Get-Item -LiteralPath $dst).Length -eq $src.Length -and (Get-Hash $src.FullName -Cache) -eq (Get-Hash $dst)) { $r.Unchanged++; continue }
                    $r.Updated++
                } else { $r.Copied++ }
                Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
            }
            $State.Completed += $j.Key
        } catch {
            $r.Status = 'FAILED'; $r.Error = $_.Exception.Message
        }
        Save-Json $StatePath $State
        [pscustomobject]$r
    }
    Write-Progress -Activity 'Distributing images' -Completed
}

function Complete-Run($State, $RunJobs, $AllJobs, $Check, [string]$ReportDir) {
    $results = @(Invoke-Jobs $RunJobs $State)
    Say 'Verifying output (SHA-256)...' Cyan
    $compare = @(Compare-Jobs $AllJobs)
    $verify  = @(Get-Verification $compare)
    $quality = @(Get-SourceQuality $AllJobs)
    $failed  = @($results | Where-Object { $_.Status -eq 'FAILED' }).Count
    $vfail   = @($verify  | Where-Object { $_.Status -eq 'FAIL' }).Count
    $qwarn   = @($quality | Where-Object { $_.Status -ne 'PASS' }).Count

    Save-Reports $ReportDir @{
        Job_Results       = $results
        Verification      = $verify
        File_Comparison   = $compare
        Image_Quality     = $quality
        Duplicate_Images  = (Get-HashDuplicates $AllJobs)
        Validation_Issues = (Get-IssueRows $Check.Issues)
        Plan              = (Get-PlanRows $AllJobs)
    }

    Say ''
    Say ('=' * 62) Green
    Say '  DISTRIBUTION COMPLETE' Green
    Say ('=' * 62) Green
    Say "Run ID        : $($State.RunId)"
    Say ("Jobs          : {0} run, {1} failed" -f $results.Count, $failed) $(if ($failed) { 'Red' } else { 'Green' })
    Say ("Files         : {0} copied, {1} updated, {2} unchanged, {3} removed" -f (Get-Sum $results Copied), (Get-Sum $results Updated), (Get-Sum $results Unchanged), (Get-Sum $results Removed))
    Say ("Verification  : {0} PASS, {1} FAIL" -f ($verify.Count - $vfail), $vfail) $(if ($vfail) { 'Red' } else { 'Green' })
    if ($qwarn) { Say "Quality notes : $qwarn image(s) - see Image_Quality.csv" Yellow }
    if ($failed) { Say 'Tip: choose "Resume" from the menu to retry failed jobs.' Yellow }
}

# ------------------------------ Menu actions ------------------------------
function Get-RunConfig([switch]$NeedOutput) {
    $last  = Read-Json $ConfigPath
    $codes = @{ Amazon = '1'; Flipkart = '2'; Both = '3' }
    $def   = if ($last -and $last.Platform -and $codes.ContainsKey([string]$last.Platform)) { $codes[[string]$last.Platform] } else { '' }
    Say '1 = Amazon   2 = Flipkart   3 = Both (CSV with model + ASIN + FSN)'
    Say 'Press Enter to reuse the value shown in [brackets].' DarkGray
    $platform = @{ '1' = 'Amazon'; '2' = 'Flipkart'; '3' = 'Both' }[(Read-Choice 'Platform' @('1', '2', '3') $def)]
    $source   = Read-Path 'Source folder' Folder ([string]$last.Source)
    $csv      = Read-Path 'Mapping CSV' Csv ([string]$last.Csv)
    $output   = if ($NeedOutput) { Read-Path 'Output folder' Output ([string]$last.Output) } else { $null }
    if ($output -and $output -eq $source) { throw 'Output folder must be different from the source folder.' }
    $start = 0
    if ($platform -ne 'Amazon') { $start = [int](Read-Choice 'Flipkart numbering (0 = FSN_0, 1 = FSN_1)' @('0', '1') ([string]$last.StartIndex)) }
    $mode = Get-SourceMode $source
    if ($mode -eq 'Unknown') { throw 'No images or model folders found in the source folder.' }
    $cfg = [pscustomobject]@{ Platform = $platform; Source = $source; Csv = $csv; Output = $output; StartIndex = $start; Mode = $mode }
    if ($NeedOutput) { Save-Json $ConfigPath ($cfg | Select-Object Platform, Source, Csv, Output, StartIndex) }
    $cfg
}

function Start-Distribution {
    Show-Banner 'NEW DISTRIBUTION'
    $cfg   = Get-RunConfig -NeedOutput
    $check = Get-Jobs $cfg
    Show-Check $cfg $check
    if (-not $check.Jobs.Count) { Say 'Nothing to distribute.' Red; return }

    $dupes = Get-HashDuplicates $check.Jobs
    if ($dupes.Count) { Say "Identical images used in several places: $($dupes.Count) group(s)" Yellow }
    $runId     = Get-Date -Format 'yyyyMMdd_HHmmss'
    $reportDir = Join-Path $cfg.Output "Reports\$runId"

    Say ''
    if ($check.Issues.Count) { Say "1 = Run the $($check.Jobs.Count) valid job(s) only   2 = Dry run (reports only)   3 = Cancel" Yellow }
    else { Say '1 = Run   2 = Dry run (reports only)   3 = Cancel' }
    $choice = Read-Choice 'Select' @('1', '2', '3') $(if ($check.Issues.Count) { '2' } else { '1' })
    if ($choice -eq '3') { return }
    if ($choice -eq '2') {
        Save-Reports $reportDir @{ Plan = (Get-PlanRows $check.Jobs); Validation_Issues = (Get-IssueRows $check.Issues); Duplicate_Images = $dupes; Image_Quality = (Get-SourceQuality $check.Jobs) }
        Say 'DRY RUN COMPLETE - no files were changed.' Green
        return
    }

    $jobs = $check.Jobs; $collision = 'SmartReplace'; $skipped = @()
    $existing = Get-Collisions $jobs
    if ($existing.Count) {
        Say "`n$($existing.Count) destination folder(s) already contain images." Yellow
        Say '1 = Smart update (copy new/changed, remove stale)   2 = Backup & replace   3 = Skip them   4 = Cancel'
        switch (Read-Choice 'Select' @('1', '2', '3', '4') '1') {
            '2' { $collision = 'Replace' }
            '3' { $skipped = @($existing | ForEach-Object { $_.Key }); $jobs = @($jobs | Where-Object { $skipped -notcontains $_.Key }) }
            '4' { return }
        }
    }
    if (-not $jobs.Count) { Say 'Nothing left to do.' Yellow; return }
    if (-not (Yes "Proceed with $($jobs.Count) job(s)?")) { return }
    if ($collision -eq 'Replace') { Say "Backup: $(Backup-Folders $existing $cfg.Output $runId)" Cyan }

    $state = [pscustomobject]@{ RunId = $runId; Platform = $cfg.Platform; Source = $cfg.Source; Csv = $cfg.Csv; Output = $cfg.Output; StartIndex = $cfg.StartIndex; Collision = $collision; Completed = @(); Skipped = $skipped }
    Save-Json $StatePath $state
    Complete-Run $state $jobs $jobs $check $reportDir
}

function Resume-Distribution {
    Show-Banner 'RESUME PREVIOUS RUN'
    $s = Read-Json $StatePath
    if (-not $s) { Say 'No previous run found.' Yellow; return }
    foreach ($p in 'Completed', 'Skipped') { $s | Add-Member NoteProperty $p @($s.$p | Where-Object { $_ }) -Force }
    if (-not $s.PSObject.Properties['Collision']) { $s | Add-Member NoteProperty Collision 'SmartReplace' -Force }

    Say "Run $($s.RunId)  |  $($s.Platform)  |  $($s.Completed.Count) job(s) done"
    Say "Source : $($s.Source)"; Say "CSV    : $($s.Csv)"; Say "Output : $($s.Output)"
    if (-not (Test-Path -LiteralPath $s.Source) -or -not (Test-Path -LiteralPath $s.Csv)) { throw 'Source folder or CSV no longer exists.' }

    $cfg   = [pscustomobject]@{ Platform = $s.Platform; Source = $s.Source; Csv = $s.Csv; Output = $s.Output; StartIndex = [int]$s.StartIndex; Mode = (Get-SourceMode $s.Source) }
    $check = Get-Jobs $cfg
    $all   = @($check.Jobs | Where-Object { $s.Skipped -notcontains $_.Key })
    $todo  = @($all | Where-Object { $s.Completed -notcontains $_.Key })
    if (-not $todo.Count) { Say 'Nothing left to resume.' Green; return }
    if (-not (Yes "Resume $($todo.Count) remaining job(s)?")) { return }
    Complete-Run $s $todo $all $check (Join-Path $s.Output ("Reports\$($s.RunId)_resume_" + (Get-Date -Format 'HHmmss')))
}

function Test-MappingOnly {
    Show-Banner 'VALIDATE MAPPING'
    $cfg   = Get-RunConfig
    $check = Get-Jobs $cfg
    Show-Check $cfg $check
    Say "Identical image groups: $(@(Get-HashDuplicates $check.Jobs).Count)"
}

function Compare-Output {
    Show-Banner 'COMPARE SOURCE vs OUTPUT'
    $cfg  = Get-RunConfig -NeedOutput
    $rows = @(Compare-Jobs (Get-Jobs $cfg).Jobs)
    $rows | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
    Save-Reports (Join-Path $cfg.Output ('Reports\Compare_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))) @{ File_Comparison = $rows; Verification = (Get-Verification $rows) }
}

function Scan-Quality {
    Show-Banner 'SCAN IMAGE QUALITY'
    $src  = Read-Path 'Folder to scan' Folder ([string](Read-Json $ConfigPath).Source)
    $rows = @(Get-ChildItem -LiteralPath $src -File -Recurse | Where-Object { Test-Image $_ } | ForEach-Object { Get-ImageInfo $_ })
    Say "Images found: $($rows.Count)" Green
    $rows | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
    Save-Reports (Join-Path $Root ('Reports\Quality_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))) @{ Image_Quality = $rows }
}

# ------------------------------ Main menu ------------------------------
while ($true) {
    Show-Banner 'MAIN MENU'
    Say '1. New distribution'
    Say '2. Resume previous distribution'
    Say '3. Validate mapping only'
    Say '4. Scan image quality'
    Say '5. Compare source vs output'
    Say '6. Exit'
    $c = Read-Choice 'Select' @('1', '2', '3', '4', '5', '6')
    if ($c -eq '6') { break }
    $script:ImageCache = @{}; $script:HashCache = @{}
    try {
        switch ($c) {
            '1' { Start-Distribution }
            '2' { Resume-Distribution }
            '3' { Test-MappingOnly }
            '4' { Scan-Quality }
            '5' { Compare-Output }
        }
    } catch {
        Say "`nERROR: $($_.Exception.Message)" Red
        Say ("Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) DarkYellow
    }
    Pause-Tool
}
