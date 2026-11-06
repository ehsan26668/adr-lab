[CmdletBinding(DefaultParameterSetName = 'New')]
param(
    [Parameter(ParameterSetName = 'New', Position = 0, Mandatory = $true)]
    [string]$Title,

    [Parameter(ParameterSetName = 'New')]
    [string]$Slug,

    [Parameter(ParameterSetName = 'New')]
    [string]$Template,

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

    [Parameter(ParameterSetName = 'VerifyLinks', Mandatory = $true)]
    [switch]$VerifyLinks,

    [string]$Path = 'docs/decisions'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# This legacy default is intentionally embedded only;
# it is not installed into the repository.
$builtInTemplate = @'
# ADR-{{ID}}: {{TITLE}}

**Status**: {{STATUS}}
**Date**: {{DATE}}
**Author**: {{AUTHOR}}

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
'@

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

function Read-TemplateFile ([string]$LiteralPath) {
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return $null
    }

    $item = Get-Item -LiteralPath $LiteralPath -ErrorAction Stop

    if ($item.PSProvider.Name -cne 'FileSystem') {
        throw "قالب باید در فایل‌سیستم باشد: $LiteralPath"
    }

    if ($item.PSIsContainer) {
        throw "مسیر قالب یک پوشه است، نه فایل: $LiteralPath"
    }

    return [System.IO.File]::ReadAllText(
        $item.FullName,
        [System.Text.Encoding]::UTF8
    )
}

function Resolve-AdrTemplate (
    [string]$AdrPath,
    [bool]$WasSpecified,
    [string]$TemplateValue
) {
    $templateText = $null

    if ($WasSpecified) {
        if ([string]::IsNullOrWhiteSpace($TemplateValue)) {
            throw 'مقدار -Template نمی‌تواند خالی یا فقط شامل فاصله باشد.'
        }

        $explicitPath = [System.IO.Path]::IsPathRooted($TemplateValue) -or
            $TemplateValue.Contains('/') -or
            $TemplateValue.Contains('\')

        if ($explicitPath) {
            $location = Get-Location

            if ($location.Provider.Name -cne 'FileSystem') {
                throw 'مسیر قالب نسبی فقط از یک پوشهٔ فایل‌سیستمی قابل resolve است.'
            }

            $resolved = if ([System.IO.Path]::IsPathRooted($TemplateValue)) {
                $TemplateValue
            }
            else {
                Join-Path -Path $location.Path -ChildPath $TemplateValue
            }

            $leaf = [System.IO.Path]::GetFileName($TemplateValue)

            if ($leaf -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*\.md$') {
                throw 'نام فایل قالب صریح باید kebab-case انگلیسی کوچک و دارای پسوند .md باشد.'
            }

            $templateText = Read-TemplateFile -LiteralPath $resolved

            if ($null -eq $templateText) {
                throw "فایل قالب پیدا نشد: $resolved"
            }
        }
        else {
            $name = $TemplateValue

            if ($name.EndsWith('.md', [System.StringComparison]::Ordinal)) {
                $name = $name.Substring(0, $name.Length - 3)
            }

            if ($name -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
                throw 'نام قالب باید kebab-case انگلیسی کوچک باشد (پسوند .md اختیاری است).'
            }

            $fileName = "$name.md"

            $candidates = @(
                (
                    Join-Path -Path $AdrPath -ChildPath (
                        Join-Path 'templates' $fileName
                    )
                ),
                (
                    Join-Path -Path (Get-Location).Path -ChildPath (
                        Join-Path '.adr-templates' $fileName
                    )
                )
            )

            foreach ($candidate in $candidates) {
                $candidateText = Read-TemplateFile -LiteralPath $candidate

                if ($null -ne $candidateText) {
                    $templateText = $candidateText
                    break
                }
            }

            if ($null -eq $templateText) {
                throw "قالب نام‌گذاری‌شده پیدا نشد: $name"
            }
        }
    }
    else {
        $candidates = @(
            (
                Join-Path -Path $AdrPath -ChildPath (
                    Join-Path 'templates' 'default.md'
                )
            ),
            (
                Join-Path -Path (Get-Location).Path -ChildPath (
                    Join-Path '.adr-templates' 'default.md'
                )
            )
        )

        foreach ($candidate in $candidates) {
            $candidateText = Read-TemplateFile -LiteralPath $candidate

            if ($null -ne $candidateText) {
                $templateText = $candidateText
                break
            }
        }

        if ($null -eq $templateText) {
            $templateText = $builtInTemplate
        }
    }

    if ([string]::IsNullOrWhiteSpace($templateText)) {
        throw 'محتوای قالب نمی‌تواند خالی یا فقط شامل فاصله باشد.'
    }

    Assert-AdrTemplate -Content $templateText
    return $templateText
}

function Assert-AdrTemplate ([string]$Content) {
    $adrHeadings = [regex]::Matches(
        $Content,
        '(?m)^# ADR(?:[ \t-]|$)[^\r\n]*\r?$'
    )

    $validHeading = [regex]::Matches(
        $Content,
        '(?m)^# ADR-\{\{(?:ID|ADR_ID)\}\}: \{\{TITLE\}\}[ \t]*\r?$'
    )

    if ($adrHeadings.Count -ne 1 -or $validHeading.Count -ne 1) {
        throw 'قالب باید دقیقاً یک سربرگ ADR به فرم # ADR-{{ID}}: {{TITLE}} داشته باشد.'
    }

    $status = Get-StatusMatch $Content

    if ($status.Groups[1].Value -cne '{{STATUS}}') {
        throw 'خط Status قالب باید دقیقاً مقدار {{STATUS}} داشته باشد.'
    }

    $dates = [regex]::Matches(
        $Content,
        '(?m)^\*\*Date\*\*:[ \t]*\{\{DATE\}\}[ \t]*\r?$'
    )

    if ($dates.Count -ne 1) {
        throw 'قالب باید دقیقاً یک خط **Date**: {{DATE}} داشته باشد.'
    }

    if ([regex]::IsMatch($Content, '(?m)^\*\*Superseded by\*\*:')) {
        throw 'قالب نباید خط **Superseded by** داشته باشد.'
    }

    $allowed = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::Ordinal
    )

    foreach ($token in @('ID', 'ADR_ID', 'TITLE', 'DATE', 'AUTHOR', 'STATUS')) {
        $allowed.Add($token, '')
    }

    $tokens = [regex]::Matches(
        $Content,
        '\{\{(?<Name>[^{}\r\n]*)\}\}'
    )

    foreach ($token in $tokens) {
        if (-not $allowed.ContainsKey($token.Groups['Name'].Value)) {
            throw "توکن قالب پشتیبانی نمی‌شود: {{ $($token.Groups['Name'].Value) }}"
        }
    }
}

function Get-AdrAuthor {
    $author = 'Unknown'

    try {
        $gitOutput = @(& git config user.name 2>$null)
        $gitExitCode = $LASTEXITCODE

        if ($gitExitCode -eq 0 -and $gitOutput.Count -gt 0) {
            $candidate = [string]::Join("`n", [string[]]$gitOutput)

            if ($candidate -match '[\r\n]') {
                throw 'مقدار git user.name باید تک‌خطی باشد.'
            }

            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $author = $candidate.Trim()
            }
        }
    }
    catch {
        if ($_.Exception.Message -match 'باید تک‌خطی باشد') {
            throw
        }

        $author = 'Unknown'
    }

    if ($author -match '[\r\n]') {
        throw 'مقدار git user.name باید تک‌خطی باشد.'
    }

    return $author
}

function ConvertFrom-AdrTemplate (
    [string]$Content,
    [System.Collections.Generic.Dictionary[string, string]]$Values
) {
    $pattern = '\{\{(?<Name>[^{}\r\n]*)\}\}'

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $Values[$match.Groups['Name'].Value]
    }

    return [regex]::Replace($Content, $pattern, $evaluator)
}

function Get-AdrLinkScanText ([string]$Content) {
    # Remove fenced code while retaining line boundaries.
    $lines = [regex]::Split($Content, '\r\n|\n|\r')
    $result = [System.Collections.Generic.List[string]]::new()
    $fenceCharacter = ''
    $fenceLength = 0

    foreach ($line in $lines) {
        if ($fenceLength -gt 0) {
            $closingPattern = '^[ ]{0,3}' +
                [regex]::Escape($fenceCharacter) +
                '{' + $fenceLength + ',}[ \t]*$'

            if ([regex]::IsMatch($line, $closingPattern)) {
                $fenceCharacter = ''
                $fenceLength = 0
            }

            $result.Add('')
            continue
        }

        $opening = [regex]::Match(
            $line,
            '^[ ]{0,3}(?<Fence>`{3,}|~{3,})(?<Info>.*)$'
        )

        if ($opening.Success) {
            $fence = $opening.Groups['Fence'].Value
            $info = $opening.Groups['Info'].Value

            # A backtick fence cannot have backticks in its info string.
            if ($fence[0] -ne [char]96 -or -not $info.Contains('`')) {
                $fenceCharacter = [string]$fence[0]
                $fenceLength = $fence.Length
                $result.Add('')
                continue
            }
        }

        # Indented Markdown code blocks are outside link-validation scope.
        if ($line -match '^(?: {4}|\t)') {
            $result.Add('')
            continue
        }

        $result.Add($line)
    }

    $scanText = [string]::Join("`n", $result.ToArray())

    # Remove HTML comments and inline code spans.
    $scanText = [regex]::Replace(
        $scanText,
        '(?s)<!--.*?(?:-->|$)',
        ''
    )

    $scanText = [regex]::Replace(
        $scanText,
        '(?s)(?<!`)(?<Ticks>`+)(?!`).*?(?<!`)\k<Ticks>(?!`)',
        ''
    )

    return $scanText
}

function Get-AdrMarkdownTargets ([string]$Content) {
    $scanText = Get-AdrLinkScanText $Content

    # Inline links, including angle-bracket destinations, optional titles,
    # and one level of balanced parentheses in an unquoted destination.
    $inlinePattern = @'
(?x)
(?<!!)\[[^\]\r\n]*\]
\(
    [ \t]*
    (?:
        <(?<Target>[^>\r\n]+)>
        |
        (?<Target>(?:\\.|[^\s()\\]|\((?:\\.|[^()\\])*\))+)
    )
    (?:
        [ \t]+
        (?:
            "[^"\r\n]*"
            |
            '[^'\r\n]*'
            |
            \([^)\r\n]*\)
        )
    )?
    [ \t]*
\)
'@

    foreach ($link in [regex]::Matches($scanText, $inlinePattern)) {
        $link.Groups['Target'].Value
    }

    # Check destinations declared by reference-style link definitions.
    # This also checks definitions that are not currently used.
    $definitionPattern = @'
(?mx)
^[ ]{0,3}\[[^\]\r\n]+\]:[ \t]*
(?:
    <(?<Target>[^>\r\n]+)>
    |
    (?<Target>\S+)
)
'@

    foreach ($definition in [regex]::Matches($scanText, $definitionPattern)) {
        $definition.Groups['Target'].Value
    }
}

function Invoke-AdrLinkVerification ([string]$TargetDirPath) {
    $files = @(
        Get-ChildItem -LiteralPath $TargetDirPath -Filter '*.md' -File |
            Where-Object { $_.Name -match '^[0-9]{4}-.+\.md$' } |
            Sort-Object -Property Name
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $records = [System.Collections.Generic.List[object]]::new()
    $byId = @{}

    # Read each ADR once and build an ID lookup.
    foreach ($file in $files) {
        $fileId = $file.Name.Substring(0, 4)

        if ($fileId -eq '0000') {
            $problems.Add(
                "$($file.Name): شناسهٔ ADR باید بین 0001 و 9999 باشد."
            )
        }

        $content = [System.IO.File]::ReadAllText(
            $file.FullName,
            $utf8NoBom
        )

        $recordStatus = $null

        try {
            $recordStatus = (Get-StatusMatch $content).Groups[1].Value.Trim()

            if ($recordStatus -cnotin @(
                'Proposed',
                'Accepted',
                'Rejected',
                'Superseded'
            )) {
                $problems.Add(
                    "$($file.Name): وضعیت ADR معتبر نیست: '$recordStatus'."
                )
            }
        }
        catch {
            $problems.Add(
                "$($file.Name): $($_.Exception.Message)"
            )
        }

        $record = [pscustomobject]@{
            File = $file
            Id = $fileId
            Content = $content
            Status = $recordStatus
        }

        $records.Add($record)

        if (-not $byId.ContainsKey($fileId)) {
            $byId[$fileId] = [System.Collections.Generic.List[object]]::new()
        }

        $byId[$fileId].Add($record)
    }

    foreach ($fileId in @($byId.Keys | Sort-Object)) {
        $sameIdRecords = $byId[$fileId]

        if ($sameIdRecords.Count -gt 1) {
            $names = @(
                $sameIdRecords | ForEach-Object { $_.File.Name }
            ) -join ', '

            $problems.Add(
                "شناسهٔ ADR-$fileId تکراری است: $names"
            )
        }
    }

    foreach ($record in $records) {
        $fileName = $record.File.Name

        $referenceLines = [regex]::Matches(
            $record.Content,
            '(?m)^\*\*Superseded by\*\*:[^\r\n]*'
        )

        if ($record.Status -ceq 'Superseded') {
            if ($referenceLines.Count -ne 1) {
                $problems.Add(
                    "${fileName}: ADR جایگزین‌شده باید دقیقاً یک خط Superseded by داشته باشد."
                )
            }
            else {
                $reference = [regex]::Match(
                    $referenceLines[0].Value,
                    '^\*\*Superseded by\*\*:[ \t]*ADR-([0-9]{4})[ \t]*$'
                )

                if (-not $reference.Success) {
                    $problems.Add(
                        "${fileName}: قالب ارجاع باید **Superseded by**: ADR-XXXX باشد."
                    )
                }
                else {
                    $replacementId = $reference.Groups[1].Value

                    if ([int]$replacementId -le [int]$record.Id) {
                        $problems.Add(
                            "${fileName}: شناسهٔ ADR جایگزین باید بزرگ‌تر از ADR-$($record.Id) باشد؛ هدف: ADR-$replacementId."
                        )
                    }

                    if (-not $byId.ContainsKey($replacementId)) {
                        $problems.Add(
                            "${fileName}: فایل هدف جایگزینی ADR-$replacementId وجود ندارد."
                        )
                    }
                    elseif ($byId[$replacementId].Count -ne 1) {
                        $problems.Add(
                            "${fileName}: هدف جایگزینی ADR-$replacementId یکتا نیست."
                        )
                    }
                    else {
                        $replacement = $byId[$replacementId][0]

                        if ($replacement.Status -cnotin @(
                            'Accepted',
                            'Superseded'
                        )) {
                            $problems.Add(
                                "${fileName}: هدف جایگزینی $($replacement.File.Name) باید Accepted یا Superseded باشد."
                            )
                        }
                    }
                }
            }
        }
        elseif ($referenceLines.Count -gt 0) {
            $problems.Add(
                "${fileName}: خط Superseded by فقط برای وضعیت Superseded مجاز است."
            )
        }

        $linkTargets = @(
            Get-AdrMarkdownTargets -Content $record.Content
        )

        # Avoid duplicate diagnostics for the same destination in one file.
        $checkedTargets = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )

        foreach ($rawTarget in $linkTargets) {
            $linkTarget = $rawTarget.Trim()

            if (-not $checkedTargets.Add($linkTarget)) {
                continue
            }

            if ([string]::IsNullOrWhiteSpace($linkTarget)) {
                continue
            }

            # Anchor-only links and external URI schemes are not fetched.
            if ($linkTarget.StartsWith('#')) {
                continue
            }

            if (
                $linkTarget.StartsWith('//') -or
                (
                    $linkTarget -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -and
                    $linkTarget -notmatch '^[a-zA-Z]:[\\/]'
                )
            ) {
                continue
            }

            # Strip query/fragment before decoding so an encoded # or ?
            # remains part of the filename.
            $pathPart = ($linkTarget -split '[?#]', 2)[0]

            if ([string]::IsNullOrWhiteSpace($pathPart)) {
                continue
            }

            try {
                $pathPart = [System.Uri]::UnescapeDataString($pathPart)

                # Handle commonly escaped characters in Markdown paths.
                $pathPart = [regex]::Replace(
                    $pathPart,
                    '\\([() ])',
                    '$1'
                )

                $pathPart = $pathPart.Replace(
                    '\',
                    [string][System.IO.Path]::DirectorySeparatorChar
                )

                $pathPart = $pathPart.Replace(
                    '/',
                    [string][System.IO.Path]::DirectorySeparatorChar
                )

                if (-not $pathPart.EndsWith(
                    '.md',
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                    continue
                }

                $resolvedTarget = [System.IO.Path]::GetFullPath(
                    $pathPart,
                    $record.File.DirectoryName
                )

                if (-not (Test-Path -LiteralPath $resolvedTarget -PathType Leaf)) {
                    $problems.Add(
                        "${fileName}: لینک شکسته '$linkTarget'؛ فایل مقصد وجود ندارد: $resolvedTarget"
                    )
                }
            }
            catch {
                $problems.Add(
                    "${fileName}: مسیر لینک '$linkTarget' قابل بررسی نیست: $($_.Exception.Message)"
                )
            }
        }
    }

    if ($problems.Count -gt 0) {
        throw (
            "اعتبارسنجی ارجاعات و لینک‌ها با شکست مواجه شد؛ تعداد خطاها: $($problems.Count).`n- " +
            ($problems -join "`n- ")
        )
    }

    Write-Host (
        "Link verification passed: checked $($files.Count) ADR file(s)."
    ) -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'مقدار -Path نمی‌تواند خالی یا فقط شامل فاصله باشد.'
}

# Validate creation inputs and load the template before creating anything.
if ($PSCmdlet.ParameterSetName -eq 'New') {
    if ([string]::IsNullOrWhiteSpace($Title) -or $Title -match '[\r\n]') {
        throw 'عنوان ADR نمی‌تواند خالی یا چندخطی باشد.'
    }

    $Title = $Title.Trim()

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

    $templateContent = Resolve-AdrTemplate `
        -AdrPath $Path `
        -WasSpecified ($PSBoundParameters.ContainsKey('Template')) `
        -TemplateValue $Template

    $author = Get-AdrAuthor
}

# Read/validation/edit operations must not create a missing directory.
if (Test-Path -LiteralPath $Path) {
    $targetDir = Get-Item -LiteralPath $Path

    if ($targetDir.PSProvider.Name -cne 'FileSystem') {
        throw "مسیر ADR باید در فایل‌سیستم باشد: $Path"
    }

    if (-not $targetDir.PSIsContainer) {
        throw "مسیر مشخص‌شده یک پوشه نیست: $Path"
    }
}
elseif ($PSCmdlet.ParameterSetName -in @(
    'VerifyIndex',
    'VerifyLinks',
    'Edit',
    'SetStatus'
)) {
    throw "پوشهٔ ADR وجود ندارد: $Path"
}
else {
    $targetDir = New-Item -ItemType Directory -Path $Path -Force
}

if ($PSCmdlet.ParameterSetName -eq 'VerifyLinks') {
    Invoke-AdrLinkVerification -TargetDirPath $targetDir.FullName
    return
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

    if ($currentStatus -cnotin @(
        'Proposed',
        'Accepted',
        'Rejected',
        'Superseded'
    )) {
        throw "وضعیت ADR-$formattedId معتبر نیست: $currentStatus"
    }

    if ($PSCmdlet.ParameterSetName -eq 'Edit') {
        if ($currentStatus -cne 'Proposed') {
            throw "فقط ADR با وضعیت Proposed قابل ویرایش است: ADR-$formattedId"
        }

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
        $headingPattern = '(?m)^# ADR-' + $formattedId + ':[^\r\n]*'
        $headings = [regex]::Matches($content, $headingPattern)

        if ($headings.Count -ne 1) {
            throw "عنوان ADR-$formattedId وجود ندارد یا تکراری است."
        }

        $heading = $headings[0]
        $newHeading = "# ADR-${formattedId}: $NewTitle"

        $updated = $content.Substring(0, $heading.Index) +
            $newHeading +
            $content.Substring($heading.Index + $heading.Length)

        if ($updated -cne $content) {
            [System.IO.File]::WriteAllText(
                $adrFile.FullName,
                $updated,
                $utf8NoBom
            )
        }

        return $adrFile.FullName
    }

    $newStatus = switch ($Status.ToLowerInvariant()) {
        'accepted' { 'Accepted' }
        'rejected' { 'Rejected' }
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

    if ([regex]::IsMatch($content, '(?m)^\*\*Superseded by\*\*:')) {
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
        "ADR-$formattedId status changed: $currentStatus -> $newStatus"
    ) -ForegroundColor Green

    return
}

if ($PSCmdlet.ParameterSetName -in @('GenerateIndex', 'VerifyIndex')) {
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

        $adrTitle = if ($titleMatch.Success) {
            $titleMatch.Groups[1].Value.Trim()
        }
        else {
            'Untitled'
        }

        $adrTitle = $adrTitle -replace '\|', '\|'

        $indexStatusMatch = [regex]::Match(
            $content,
            '(?m)^\*\*Status\*\*:[ \t]*([^\r\n]*?)[ \t]*\r?$'
        )

        $adrStatus = if ($indexStatusMatch.Success) {
            $indexStatusMatch.Groups[1].Value.Trim().Trim([char]96)
        }
        else {
            'Unknown'
        }

        $adrStatus = $adrStatus -replace '\|', '\|'

        $dateMatch = [regex]::Match(
            $content,
            '(?m)^\*\*Date\*\*:[ \t]*(\d{4}-\d{2}-\d{2})[ \t]*\r?$'
        )

        $adrDate = if ($dateMatch.Success) {
            $dateMatch.Groups[1].Value
        }
        else {
            'Unknown'
        }

        if ($PSCmdlet.ParameterSetName -eq 'VerifyIndex') {
            $checkedStatus = (
                Get-StatusMatch $content
            ).Groups[1].Value.Trim()

            if ($checkedStatus -cnotin @(
                'Proposed',
                'Accepted',
                'Rejected',
                'Superseded'
            )) {
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

                $replacementNumber = [int]$reference.Groups[1].Value

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

                if ($replacementStatus -cnotin @('Accepted', 'Superseded')) {
                    throw "ADR جایگزین باید Accepted یا Superseded باشد: $($replacementFile.Name)"
                }
            }
            elseif ($referenceLines.Count -gt 0) {
                throw "خط Superseded by برای این وضعیت مجاز نیست: $($file.Name)"
            }
        }

        $indexLines.Add(
            (
                '| {0} | [{1}]({2}) | {3} | {4} |' -f
                $fileId,
                $adrTitle,
                $file.Name,
                $adrStatus,
                $adrDate
            )
        )
    }

    $indexContent = [string]::Join(
        "`n",
        $indexLines.ToArray()
    ) + "`n"

    $indexPath = Join-Path $targetDir.FullName 'readme.md'

    if ($PSCmdlet.ParameterSetName -eq 'VerifyIndex') {
        if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
            throw 'فایل فهرست (readme.md) وجود ندارد. ابتدا دستور -GenerateIndex را اجرا کنید.'
        }

        $existingIndexContent = [System.IO.File]::ReadAllText(
            $indexPath,
            $utf8NoBom
        )

        $normalizedExpected = $indexContent -replace "`r`n?", "`n"
        $normalizedExisting = $existingIndexContent -replace "`r`n?", "`n"

        if ($normalizedExpected -cne $normalizedExisting) {
            throw 'فهرست ADRها با فایل‌های موجود همگام نیست. دستور .\adr.ps1 -GenerateIndex را اجرا و تغییرات را ثبت کنید.'
        }

        Write-Host (
            'Index verification passed: readme.md is up-to-date.'
        ) -ForegroundColor Green

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

$values = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::Ordinal
)

$values.Add('ID', $formattedId)
$values.Add('ADR_ID', $formattedId)
$values.Add('TITLE', $Title)
$values.Add(
    'DATE',
    [DateTime]::Now.ToString(
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture
    )
)
$values.Add('AUTHOR', $author)
$values.Add('STATUS', 'Proposed')

$rendered = ConvertFrom-AdrTemplate `
    -Content $templateContent `
    -Values $values

$rendered = $rendered -replace "`r`n?", "`n"
$rendered = $rendered.TrimEnd("`n") + "`n"

[System.IO.File]::WriteAllText(
    $filePath,
    $rendered,
    $utf8NoBom
)

Write-Host "ADR successfully created: $filePath" -ForegroundColor Green
return
