[CmdletBinding(DefaultParameterSetName = 'New')]
param(
    [Parameter(ParameterSetName = 'New', Position = 0, Mandatory = $true)]
    [string]$Title,

    [Parameter(ParameterSetName = 'New')]
    [string]$Slug,

    [Parameter(ParameterSetName = 'Edit', Mandatory = $true)]
    [switch]$Edit,

    [Parameter(ParameterSetName = 'Edit')]
    [string]$NewTitle,

    [Parameter(ParameterSetName = 'SetStatus', Mandatory = $true)]
    [switch]$SetStatus,

    [Alias('Id')]
    [Parameter(ParameterSetName = 'Edit', Mandatory = $true)]
    [Parameter(ParameterSetName = 'SetStatus', Mandatory = $true)]
    [ValidateRange(1, 9999)]
    [int]$AdrId,

    [Parameter(ParameterSetName = 'SetStatus', Mandatory = $true)]
    [ValidateSet('Accepted', 'Rejected', 'Superseded')]
    [string]$Status,

    [Parameter(ParameterSetName = 'SetStatus')]
    [ValidateRange(1, 9999)]
    [int]$SupersededBy,

    [Parameter(ParameterSetName = 'GenerateIndex', Mandatory = $true)]
    [switch]$GenerateIndex,

    [Parameter(ParameterSetName = 'VerifyIndex', Mandatory = $true)]
    [switch]$VerifyIndex,

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

function Get-AdrFile ([int]$number) {
    $formattedNumber = '{0:D4}' -f $number
    $pattern = '^' + $formattedNumber + '-.+\.md$'

    $files = @(
        Get-ChildItem -LiteralPath $targetDir.FullName -Filter '*.md' -File |
            Where-Object { $_.Name -match $pattern }
    )

    if ($files.Count -ne 1) {
        throw "برای ADR-$formattedNumber باید دقیقاً یک فایل وجود داشته باشد؛ تعداد یافت‌شده: $($files.Count)."
    }

    return $files[0]
}

function Get-StatusMatch ([string]$content) {
    $found = [regex]::Matches(
        $content,
        '(?m)^\*\*Status\*\*:[ \t]*([^\r\n]*?)[ \t]*\r?$'
    )

    if ($found.Count -ne 1) {
        throw 'هر ADR باید دقیقاً یک خط معتبر **Status** داشته باشد.'
    }

    return $found[0]
}

if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'مقدار -Path نمی‌تواند خالی یا فقط شامل فاصله باشد.'
}

# اعتبارسنجی ورودی‌های ساخت ADR، پیش از ایجاد پوشه یا فایل.
if ($PSCmdlet.ParameterSetName -eq 'New') {
    if (
        [string]::IsNullOrWhiteSpace($Title) -or
        $Title -match '[\r\n]'
    ) {
        throw 'عنوان ADR نمی‌تواند خالی یا چندخطی باشد.'
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

# عملیات خواندن یا ویرایش نباید پوشهٔ مفقود را ایجاد کنند.
if (Test-Path -LiteralPath $Path) {
    $targetDir = Get-Item -LiteralPath $Path

    if (-not $targetDir.PSIsContainer) {
        throw "مسیر مشخص‌شده یک پوشه نیست: $Path"
    }
}
elseif (
    $PSCmdlet.ParameterSetName -in @(
        'VerifyIndex',
        'Edit',
        'SetStatus'
    )
) {
    throw "پوشهٔ ADR وجود ندارد: $Path"
}
else {
    $targetDir = New-Item -ItemType Directory -Path $Path -Force
}

if ($PSCmdlet.ParameterSetName -in @('Edit', 'SetStatus')) {
    $adrFile = Get-AdrFile $AdrId
    $content = [System.IO.File]::ReadAllText(
        $adrFile.FullName,
        $utf8NoBom
    )

    $statusMatch = Get-StatusMatch $content
    $currentStatus = $statusMatch.Groups[1].Value.Trim()
    $formattedId = '{0:D4}' -f $AdrId

    if (
        $currentStatus -cnotin @(
            'Proposed',
            'Accepted',
            'Rejected',
            'Superseded'
        )
    ) {
        throw "وضعیت ADR-$formattedId معتبر نیست: $currentStatus"
    }

    if ($PSCmdlet.ParameterSetName -eq 'Edit') {
        if ($currentStatus -cne 'Proposed') {
            throw "فقط ADR با وضعیت Proposed قابل ویرایش است: ADR-$formattedId"
        }

        # بدون NewTitle، مسیر فایل برای بازکردن و ویرایش دستی برگردانده می‌شود.
        if (-not $PSBoundParameters.ContainsKey('NewTitle')) {
            return $adrFile.FullName
        }

        if (
            [string]::IsNullOrWhiteSpace($NewTitle) -or
            $NewTitle -match '[\r\n]'
        ) {
            throw 'عنوان جدید نمی‌تواند خالی یا چندخطی باشد.'
        }

        $NewTitle = $NewTitle.Trim()
        $headingPattern = '(?m)^# ADR-' +
            $formattedId +
            ':[^\r\n]*'

        $headings = [regex]::Matches(
            $content,
            $headingPattern
        )

        if ($headings.Count -ne 1) {
            throw "عنوان ADR-$formattedId وجود ندارد یا تکراری است."
        }

        $heading = $headings[0]
        $newHeading = "# ADR-${formattedId}: $NewTitle"

        $updated = $content.Substring(0, $heading.Index) +
            $newHeading +
            $content.Substring(
                $heading.Index + $heading.Length
            )

        if ($updated -cne $content) {
            [System.IO.File]::WriteAllText(
                $adrFile.FullName,
                $updated,
                $utf8NoBom
            )
        }

        return $adrFile.FullName
    }

    # مقدار ذخیره‌شده را به نگارش استاندارد تبدیل می‌کنیم.
    $newStatus = switch ($Status.ToLowerInvariant()) {
        'accepted'   { 'Accepted' }
        'rejected'   { 'Rejected' }
        'superseded' { 'Superseded' }
    }

    if (
        $PSBoundParameters.ContainsKey('SupersededBy') -and
        $newStatus -cne 'Superseded'
    ) {
        throw '-SupersededBy فقط همراه با -Status Superseded مجاز است.'
    }

    if ($currentStatus -ceq 'Proposed') {
        if ($newStatus -cnotin @('Accepted', 'Rejected')) {
            throw 'ADR پیشنهادی فقط می‌تواند Accepted یا Rejected شود.'
        }
    }
    elseif ($currentStatus -ceq 'Accepted') {
        if ($newStatus -cne 'Superseded') {
            throw 'ADR پذیرفته‌شده فقط می‌تواند Superseded شود.'
        }
    }
    else {
        throw "وضعیت $currentStatus نهایی است و قابل تغییر نیست."
    }

    if (
        [regex]::IsMatch(
            $content,
            '(?m)^\*\*Superseded by\*\*:'
        )
    ) {
        throw 'خط Superseded by از قبل در این ADR وجود دارد.'
    }

    $supersededLine = $null

    if ($newStatus -ceq 'Superseded') {
        if (-not $PSBoundParameters.ContainsKey('SupersededBy')) {
            throw 'برای Superseded، پارامتر -SupersededBy الزامی است.'
        }

        if ($SupersededBy -le $AdrId) {
            throw 'شناسهٔ ADR جایگزین باید بزرگ‌تر از شناسهٔ ADR فعلی باشد.'
        }

        $replacementFile = Get-AdrFile $SupersededBy
        $replacementContent = [System.IO.File]::ReadAllText(
            $replacementFile.FullName,
            $utf8NoBom
        )

        $replacementStatus = (
            Get-StatusMatch $replacementContent
        ).Groups[1].Value.Trim()

        if ($replacementStatus -cne 'Accepted') {
            throw 'ADR جایگزین باید ابتدا Accepted شده باشد.'
        }

        $replacementId = '{0:D4}' -f $SupersededBy
        $supersededLine = "**Superseded by**: ADR-$replacementId"
    }

    # فقط خط وضعیت تغییر می‌کند؛ سایر محتوای ADR حفظ می‌شود.
    $statusLine = [regex]::Match(
        $content,
        '(?m)^\*\*Status\*\*:[^\r\n]*'
    )

    $updated = $content.Substring(0, $statusLine.Index) +
        "**Status**: $newStatus"

    if ($null -ne $supersededLine) {
        $lineEnding = if ($content.Contains("`r`n")) {
            "`r`n"
        }
        else {
            "`n"
        }

        $updated += $lineEnding + $supersededLine
    }

    $updated += $content.Substring(
        $statusLine.Index + $statusLine.Length
    )

    [System.IO.File]::WriteAllText(
        $adrFile.FullName,
        $updated,
        $utf8NoBom
    )

    Write-Host (
        "ADR-$formattedId status changed: " +
        "$currentStatus -> $newStatus"
    ) -ForegroundColor Green

    return
}

if (
    $PSCmdlet.ParameterSetName -eq 'GenerateIndex' -or
    $PSCmdlet.ParameterSetName -eq 'VerifyIndex'
) {
    $adrFiles = Get-ChildItem `
        -LiteralPath $targetDir.FullName `
        -Filter '*.md' `
        -File |
        Where-Object { $_.Name -match '^\d{4}-.+\.md$' } |
        Sort-Object -Property Name

    $indexLines = [System.Collections.Generic.List[string]]::new()
    $indexLines.Add('# Architecture Decision Records')
    $indexLines.Add('')
    $indexLines.Add('| ID | Title | Status | Date |')
    $indexLines.Add('| --- | --- | --- | --- |')

    foreach ($file in $adrFiles) {
        $content = [System.IO.File]::ReadAllText(
            $file.FullName,
            $utf8NoBom
        )

        $fileId = $file.Name.Substring(0, 4)

        $titleMatch = [regex]::Match(
            $content,
            '(?m)^#[ \t]+ADR-\d{4}:[ \t]*(.+?)[ \t]*\r?$'
        )

        if ($titleMatch.Success) {
            $adrTitle = $titleMatch.Groups[1].Value.Trim()
        }
        else {
            $adrTitle = 'Untitled'
        }

        # جلوگیری از خراب‌شدن ساختار جدول Markdown.
        $adrTitle = $adrTitle -replace '\|', '\|'

        $indexStatusMatch = [regex]::Match(
            $content,
            '(?m)^\*\*Status\*\*:[ \t]*([^\r\n]*?)[ \t]*\r?$'
        )

        if ($indexStatusMatch.Success) {
            $adrStatus = $indexStatusMatch.Groups[1].Value.Trim().Trim(
                [char]96
            )
        }
        else {
            $adrStatus = 'Unknown'
        }

        $adrStatus = $adrStatus -replace '\|', '\|'

        $dateMatch = [regex]::Match(
            $content,
            '(?m)^\*\*Date\*\*:[ \t]*(\d{4}-\d{2}-\d{2})[ \t]*\r?$'
        )

        if ($dateMatch.Success) {
            $adrDate = $dateMatch.Groups[1].Value
        }
        else {
            $adrDate = 'Unknown'
        }

        if ($PSCmdlet.ParameterSetName -eq 'VerifyIndex') {
            $checkedStatus = (
                Get-StatusMatch $content
            ).Groups[1].Value.Trim()

            if (
                $checkedStatus -cnotin @(
                    'Proposed',
                    'Accepted',
                    'Rejected',
                    'Superseded'
                )
            ) {
                throw "وضعیت ADR در فایل $($file.Name) معتبر نیست."
            }

            $referenceLines = [regex]::Matches(
                $content,
                '(?m)^\*\*Superseded by\*\*:[^\r\n]*'
            )

            if ($checkedStatus -ceq 'Superseded') {
                if ($referenceLines.Count -ne 1) {
                    throw "ADR جایگزین‌شده باید دقیقاً یک خط Superseded by داشته باشد: $($file.Name)"
                }

                $reference = [regex]::Match(
                    $content,
                    '(?m)^\*\*Superseded by\*\*:[ \t]*ADR-(\d{4})[ \t]*\r?$'
                )

                if (-not $reference.Success) {
                    throw "قالب ارجاع به ADR جایگزین معتبر نیست: $($file.Name)"
                }

                $replacementNumber = [int](
                    $reference.Groups[1].Value
                )

                if ($replacementNumber -le [int]$fileId) {
                    throw "شناسهٔ ADR جایگزین باید بزرگ‌تر باشد: $($file.Name)"
                }

                $replacementFile = Get-AdrFile $replacementNumber
                $replacementContent = [System.IO.File]::ReadAllText(
                    $replacementFile.FullName,
                    $utf8NoBom
                )

                $replacementStatus = (
                    Get-StatusMatch $replacementContent
                ).Groups[1].Value.Trim()

                # اگر ADR جایگزین بعداً خودش جایگزین شود،
                # زنجیرهٔ A -> B -> C همچنان معتبر می‌ماند.
                if (
                    $replacementStatus -cnotin @(
                        'Accepted',
                        'Superseded'
                    )
                ) {
                    throw "ADR جایگزین باید Accepted یا Superseded باشد: $($replacementFile.Name)"
                }
            }
            elseif ($referenceLines.Count -gt 0) {
                throw "خط Superseded by برای این وضعیت مجاز نیست: $($file.Name)"
            }
        }

        $indexLines.Add(
            ('| {0} | [{1}]({2}) | {3} | {4} |' -f
                $fileId,
                $adrTitle,
                $file.Name,
                $adrStatus,
                $adrDate)
        )
    }

    # ایندکس همیشه با LF تولید می‌شود.
    $indexContent = [string]::Join(
        "`n",
        $indexLines.ToArray()
    ) + "`n"

    $indexPath = Join-Path $targetDir.FullName 'readme.md'

    if ($PSCmdlet.ParameterSetName -eq 'VerifyIndex') {
        if (
            -not (
                Test-Path `
                    -LiteralPath $indexPath `
                    -PathType Leaf
            )
        ) {
            throw 'فایل فهرست (readme.md) وجود ندارد. ابتدا دستور -GenerateIndex را اجرا کنید.'
        }

        $existingIndexContent = [System.IO.File]::ReadAllText(
            $indexPath,
            $utf8NoBom
        )

        # تفاوت CRLF و LF نباید باعث شکست مقایسه شود.
        $normalizedExpected = $indexContent -replace "`r`n?", "`n"
        $normalizedExisting = (
            $existingIndexContent -replace "`r`n?", "`n"
        )

        if ($normalizedExpected -cne $normalizedExisting) {
            throw 'فهرست ADRها با فایل‌های موجود همگام نیست. دستور .\adr.ps1 -GenerateIndex را اجرا و تغییرات را ثبت کنید.'
        }

        Write-Host `
            'Index verification passed: readme.md is up-to-date.' `
            -ForegroundColor Green

        return
    }

    [System.IO.File]::WriteAllText(
        $indexPath,
        $indexContent,
        $utf8NoBom
    )

    Write-Host "Index generated at: $indexPath" `
        -ForegroundColor Green

    return
}

$existing = Get-ChildItem `
    -LiteralPath $targetDir.FullName `
    -Filter '*.md' `
    -File |
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

Write-Host "ADR successfully created: $filePath" `
    -ForegroundColor Green
