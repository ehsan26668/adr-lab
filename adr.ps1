[CmdletBinding(DefaultParameterSetName = 'New')]
param(
    [Parameter(ParameterSetName = 'New', Position = 0, Mandatory = $true)]
    [string]$Title,

    [Parameter(ParameterSetName = 'New')]
    [string]$Slug,

    [Parameter(ParameterSetName = 'GenerateIndex', Mandatory = $true)]
    [switch]$GenerateIndex,

    [Parameter(ParameterSetName = 'VerifyIndex', Mandatory = $true)]
    [switch]$VerifyIndex,

    [Parameter(ParameterSetName = 'New')]
    [Parameter(ParameterSetName = 'GenerateIndex')]
    [Parameter(ParameterSetName = 'VerifyIndex')]
    [string]$Path = 'docs/decisions'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Slug ([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    $clean = $text.ToLowerInvariant()
    $clean = [regex]::Replace($clean, '[^a-z0-9\s-]', '')
    $clean = [regex]::Replace($clean, '\s+', '-')
    $clean = [regex]::Replace($clean, '-+', '-')

    return $clean.Trim('-')
}

if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'مقدار -Path نمی‌تواند خالی یا فقط شامل فاصله باشد.'
}

# اعتبارسنجی ورودی‌های ساخت ADR، پیش از ایجاد پوشه یا فایل.
if ($PSCmdlet.ParameterSetName -eq 'New') {
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

# Verify نباید مسیر یا فایل جدیدی ایجاد کند.
if (Test-Path -LiteralPath $Path) {
    $targetDir = Get-Item -LiteralPath $Path

    if (-not $targetDir.PSIsContainer) {
        throw "مسیر مشخص‌شده یک پوشه نیست: $Path"
    }
}
elseif ($PSCmdlet.ParameterSetName -eq 'VerifyIndex') {
    throw "پوشهٔ ADR برای بررسی وجود ندارد: $Path"
}
else {
    $targetDir = New-Item -ItemType Directory -Path $Path -Force
}

if (
    $PSCmdlet.ParameterSetName -eq 'GenerateIndex' -or
    $PSCmdlet.ParameterSetName -eq 'VerifyIndex'
) {
    $adrFiles = Get-ChildItem -LiteralPath $targetDir.FullName -Filter '*.md' -File |
        Where-Object { $_.Name -match '^\d{4}-.+\.md$' } |
        Sort-Object Name

    $indexLines = [System.Collections.Generic.List[string]]::new()
    $indexLines.Add('# Architecture Decision Records')
    $indexLines.Add('')
    $indexLines.Add('| ID | Title | Status | Date |')
    $indexLines.Add('|---|---|---|---|')

    foreach ($file in $adrFiles) {
        $content = [System.IO.File]::ReadAllText($file.FullName, $utf8NoBom)
        $id = $file.Name.Substring(0, 4)

        $titleMatch = [regex]::Match(
            $content,
            '(?m)^#\s+ADR-\d{4}:\s*(.+?)\s*$'
        )

        if ($titleMatch.Success) {
            $adrTitle = $titleMatch.Groups[1].Value.Trim()
        }
        else {
            $adrTitle = 'Untitled'
        }

        # جلوگیری از خراب‌شدن ساختار جدول Markdown.
        $adrTitle = $adrTitle -replace '\|', '\|'

        $statusMatch = [regex]::Match(
            $content,
            '(?m)^\*\*Status\*\*:\s*(.*?)\s*$'
        )

        if ($statusMatch.Success) {
            $status = $statusMatch.Groups[1].Value.Trim().Trim([char]96)
        }
        else {
            $status = 'Unknown'
        }

        $status = $status -replace '\|', '\|'

        $dateMatch = [regex]::Match(
            $content,
            '(?m)^\*\*Date\*\*:\s*(\d{4}-\d{2}-\d{2})\s*$'
        )

        if ($dateMatch.Success) {
            $adrDate = $dateMatch.Groups[1].Value
        }
        else {
            $adrDate = 'Unknown'
        }

        $indexLines.Add(
            ('| {0} | [{1}]({2}) | {3} | {4} |' -f
                $id, $adrTitle, $file.Name, $status, $adrDate)
        )
    }

    # استفاده از LF مستقل از سیستم‌عامل میزبان.
    $indexContent = [string]::Join("`n", $indexLines.ToArray()) + "`n"
    $indexPath = Join-Path $targetDir.FullName 'readme.md'

    if ($PSCmdlet.ParameterSetName -eq 'VerifyIndex') {
        if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
            throw 'فایل فهرست (readme.md) وجود ندارد. ابتدا دستور -GenerateIndex را اجرا کنید.'
        }

        $existingIndexContent = [System.IO.File]::ReadAllText(
            $indexPath,
            $utf8NoBom
        )

        # تفاوت CRLF و LF نباید باعث شکست مقایسه شود.
        $normalizedExpected = $indexContent -replace "`r`n?", "`n"
        $normalizedExisting = $existingIndexContent -replace "`r`n?", "`n"

        if ($normalizedExpected -cne $normalizedExisting) {
            throw 'فهرست ADRها با فایل‌های موجود همگام نیست. دستور .\adr.ps1 -GenerateIndex را اجرا و تغییرات را ثبت کنید.'
        }

        Write-Host 'Index verification passed: readme.md is up-to-date.' -ForegroundColor Green
        return
    }

    [System.IO.File]::WriteAllText(
        $indexPath,
        $indexContent,
        $utf8NoBom
    )

    Write-Host "Index generated at: $indexPath" -ForegroundColor Green
    return
}

$existing = Get-ChildItem -LiteralPath $targetDir.FullName -Filter '*.md' -File |
    Where-Object { $_.Name -match '^\d{4}-.+\.md$' }

$maxId = 0

foreach ($file in $existing) {
    if ($file.Name -match '^(\d{4})-') {
        $number = [int]$Matches[1]

        if ($number -gt $maxId) {
            $maxId = $number
        }
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

[System.IO.File]::WriteAllText(
    $filePath,
    $template,
    $utf8NoBom
)

Write-Host "ADR successfully created: $filePath" -ForegroundColor Green
