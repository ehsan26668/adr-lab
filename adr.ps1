[CmdletBinding(DefaultParameterSetName = 'New')]
param(
    [Parameter(ParameterSetName = 'New', Position = 0, Mandatory = $true)]
    [string]$Title,

    [Parameter(ParameterSetName = 'New')]
    [string]$Slug,

    [Parameter(ParameterSetName = 'Index')]
    [switch]$GenerateIndex,

    [Parameter(ParameterSetName = 'New')]
    [Parameter(ParameterSetName = 'Index')]
    [string]$Path = 'docs/decisions'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Slug ([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $clean = $text.ToLowerInvariant()
    $clean = [regex]::Replace($clean, '[^a-z0-9\s-]', '')
    $clean = [regex]::Replace($clean, '\s+', '-')
    $clean = [regex]::Replace($clean, '-+', '-')
    return $clean.Trim('-')
}

# Validate New inputs before creating a destination directory or ADR file.
if (-not $GenerateIndex) {
    if ([string]::IsNullOrWhiteSpace($Title)) {
        throw 'عنوان ADR نمی‌تواند خالی یا فقط شامل فاصله باشد.'
    }

    if ($PSBoundParameters.ContainsKey('Slug')) {
        if ($Slug -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw 'مقدار -Slug باید فقط شامل حروف کوچک انگلیسی، رقم و خط تیره بین بخش‌ها باشد.'
        }
        $finalSlug = $Slug
    }
    else {
        if ($Title -match '[^\x00-\x7F]') {
            throw 'برای عنوان دارای نویسهٔ غیراَسکی، وارد کردن -Slug الزامی است.'
        }

        $finalSlug = Get-Slug $Title
        if ([string]::IsNullOrWhiteSpace($finalSlug)) {
            throw 'از عنوان، Slug معتبر ساخته نشد؛ پارامتر -Slug را مشخص کنید.'
        }
    }
}

$resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    $targetDir = New-Item -ItemType Directory -Path $Path -Force
}
else {
    $targetDir = Get-Item -LiteralPath $resolvedPath.Path
}

if ($GenerateIndex) {
    $adrFiles = Get-ChildItem -LiteralPath $targetDir.FullName -Filter '*.md' |
        Where-Object { $_.Name -match '^\d{4}-.+\.md$' } |
        Sort-Object Name

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Architecture Decision Records')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| ID | Title | Status | Last Updated |')
    [void]$sb.AppendLine('|---|---|---|---|')

    foreach ($file in $adrFiles) {
        $lines = Get-Content -LiteralPath $file.FullName -Encoding utf8
        $idStr = $file.Name.Substring(0, 4)

        $titleLine = $lines |
            Where-Object { $_ -match '^#\s+ADR-\d{4}:\s*(.+)$' } |
            Select-Object -First 1
        $extractedTitle = if ($titleLine) {
            $Matches[1].Trim()
        }
        else {
            'Untitled'
        }

        $statusLine = $lines |
            Where-Object { $_ -match '^\*\*Status\*\*:\s*`?([^`\s]+)`?' } |
            Select-Object -First 1
        $extractedStatus = if ($statusLine) {
            $Matches[1].Trim()
        }
        else {
            'Unknown'
        }

        $relPath = $file.Name
        [void]$sb.AppendLine((
            '| {0} | [{1}]({2}) | {3} | {4} |' -f
            $idStr, $extractedTitle, $relPath, $extractedStatus,
            $file.LastWriteTime.ToString('yyyy-MM-dd')
        ))
    }

    $indexPath = Join-Path $targetDir.FullName 'readme.md'
    [System.IO.File]::WriteAllText($indexPath, $sb.ToString(), $utf8NoBom)
    Write-Host "Index generated at: $indexPath" -ForegroundColor Green
    return
}

$existing = Get-ChildItem -LiteralPath $targetDir.FullName -Filter '*.md' |
    Where-Object { $_.Name -match '^\d{4}-.+\.md$' }

$maxId = 0
foreach ($f in $existing) {
    if ($f.Name -match '^(\d{4})-') {
        $num = [int]$Matches[1]
        if ($num -gt $maxId) { $maxId = $num }
    }
}

$nextId = $maxId + 1
if ($nextId -gt 9999) {
    throw 'ظرفیت شناسه‌های چهاررقمی ADR به پایان رسیده است (حداکثر 9999).'
}

$formattedId = '{0:D4}' -f $nextId
$fileName = "${formattedId}-${finalSlug}.md"
$filePath = Join-Path $targetDir.FullName $fileName

if (Test-Path -LiteralPath $filePath) {
    throw "فایلی با این نام از قبل وجود دارد: $filePath"
}

$template = @"
# ADR-${formattedId}: ${Title}

**Status**: Proposed
**Date**: $(Get-Date -Format 'yyyy-MM-dd')
**Author**: $(git config user.name)

## Context
[زمینه و مسئله‌ای که نیازمند تصمیم‌گیری است را اینجا بنویسید]

## Decision Drivers
- [عامل تصمیم‌گیری ۱]
- [عامل تصمیم‌گیری ۲]

## Considered Options
- [گزینه ۱]
- [گزینه ۲]

## Decision Outcome
Chosen option: "[گزینه انتخاب شده]", because [علت اصلی انتخاب].

### Consequences
- **Positive**: [پیامد مثبت]
- **Negative**: [پیامد منفی یا ریسک]

## References
- [لینک به مدارک یا مستندات مرتبط]
"@

[System.IO.File]::WriteAllText($filePath, $template, $utf8NoBom)
Write-Host "ADR successfully created: $filePath" -ForegroundColor Green
