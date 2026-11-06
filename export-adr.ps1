#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Path = 'docs/decisions',

    [string]$OutPath,

    [string]$SiteTitle = 'دفتر تصمیم‌های معماری',

    [ValidateSet('fa', 'en')]
    [string]$Language = 'fa'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Intentionally limited, encode-by-default Markdown renderer.
# Raw HTML is always encoded.

function Html {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Inline-Markdown {
    param(
        [AllowEmptyString()]
        [string]$Text,

        [int]$Depth = 0
    )

    if ($Depth -gt 4) {
        return (Html $Text)
    }

    $pattern = '`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)|\*\*(.+?)\*\*|__(.+?)__|\*([^*]+)\*|_([^_]+)_'
    $regex = [regex]::new($pattern)
    $builder = [System.Text.StringBuilder]::new()
    $position = 0

    foreach ($match in $regex.Matches($Text)) {
        $plainText = $Text.Substring(
            $position,
            $match.Index - $position
        )

        [void]$builder.Append((Html $plainText))

        if ($match.Groups[1].Success) {
            [void]$builder.Append(
                '<code>' +
                (Html $match.Groups[1].Value) +
                '</code>'
            )
        }
        elseif ($match.Groups[2].Success) {
            $label = Inline-Markdown `
                -Text $match.Groups[2].Value `
                -Depth ($Depth + 1)

            $url = $match.Groups[3].Value.Trim()
            $href = $null

            $internalLink = [regex]::Match(
                $url,
                '^#adr-([0-9]{4})$'
            )

            $markdownLink = [regex]::Match(
                $url,
                '^(?:\./)?([0-9]{4})-[a-z0-9]+(?:-[a-z0-9]+)*\.md(?:#.*)?$'
            )

            if ($internalLink.Success) {
                $href = '#adr-' + $internalLink.Groups[1].Value
            }
            elseif (
                $url -match '^(?i:https?|mailto):' -and
                $url -notmatch '[\x00-\x20"<>\\]'
            ) {
                $href = $url
            }
            elseif ($markdownLink.Success) {
                $href = '#adr-' + $markdownLink.Groups[1].Value
            }

            if ($null -ne $href) {
                [void]$builder.Append(
                    '<a href="' +
                    (Html $href) +
                    '" rel="noopener noreferrer">' +
                    $label +
                    '</a>'
                )
            }
            else {
                [void]$builder.Append($label)
            }
        }
        elseif (
            $match.Groups[4].Success -or
            $match.Groups[5].Success
        ) {
            $value = if ($match.Groups[4].Success) {
                $match.Groups[4].Value
            }
            else {
                $match.Groups[5].Value
            }

            $rendered = Inline-Markdown `
                -Text $value `
                -Depth ($Depth + 1)

            [void]$builder.Append(
                '<strong>' + $rendered + '</strong>'
            )
        }
        else {
            $value = if ($match.Groups[6].Success) {
                $match.Groups[6].Value
            }
            else {
                $match.Groups[7].Value
            }

            $rendered = Inline-Markdown `
                -Text $value `
                -Depth ($Depth + 1)

            [void]$builder.Append(
                '<em>' + $rendered + '</em>'
            )
        }

        $position = $match.Index + $match.Length
    }

    [void]$builder.Append(
        (Html $Text.Substring($position))
    )

    return $builder.ToString()
}

function Render-Body {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $output = [System.Collections.Generic.List[string]]::new()
    $paragraph = [System.Collections.Generic.List[string]]::new()
    $codeLines = [System.Collections.Generic.List[string]]::new()

    # A shared mutable state avoids child-scope assignment issues
    # in the local helper functions.
    $state = @{
        ListType = ''
        Quote    = $false
    }

    $inCode = $false
    $fenceCharacter = ''
    $fenceLength = 0

    function Flush-Paragraph {
        if ($paragraph.Count -gt 0) {
            $rendered = Inline-Markdown -Text ($paragraph -join ' ')
            $output.Add('<p>' + $rendered + '</p>')
            $paragraph.Clear()
        }
    }

    function Close-List {
        if ($state.ListType) {
            $output.Add('</' + $state.ListType + '>')
            $state.ListType = ''
        }
    }

    function Close-Quote {
        if ($state.Quote) {
            $output.Add('</blockquote>')
            $state.Quote = $false
        }
    }

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]

        if ($inCode) {
            $closingFence = [regex]::Match(
                $line,
                '^\s{0,3}(`{3,}|~{3,})\s*$'
            )

            $closesCode = (
                $closingFence.Success -and
                $closingFence.Groups[1].Value[0] -eq $fenceCharacter -and
                $closingFence.Groups[1].Length -ge $fenceLength
            )

            if ($closesCode) {
                $output.Add(
                    '<pre dir="ltr"><code>' +
                    (Html ($codeLines -join "`n")) +
                    '</code></pre>'
                )

                $codeLines.Clear()
                $inCode = $false
            }
            else {
                $codeLines.Add($line)
            }

            continue
        }

        $openingFence = [regex]::Match(
            $line,
            '^\s{0,3}(`{3,}|~{3,})(.*)$'
        )

        if ($openingFence.Success) {
            Flush-Paragraph
            Close-List
            Close-Quote

            $inCode = $true
            $fenceCharacter = $openingFence.Groups[1].Value[0]
            $fenceLength = $openingFence.Groups[1].Length

            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            Flush-Paragraph
            Close-List
            Close-Quote

            continue
        }

        # Pipe tables require a header and a delimiter row.
        # Escaped pipes and nested Markdown blocks are unsupported.
        $isTable = (
            $line.Contains('|') -and
            $index + 1 -lt $Lines.Count -and
            $Lines[$index + 1] -match
                '^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$'
        )

        if ($isTable) {
            Flush-Paragraph
            Close-List
            Close-Quote

            $headers = @(
                $line.Trim().Trim('|').Split('|')
            )

            $output.Add(
                '<div class="table-wrap"><table><thead><tr>'
            )

            foreach ($header in $headers) {
                $output.Add(
                    '<th>' +
                    (Inline-Markdown -Text $header.Trim()) +
                    '</th>'
                )
            }

            $output.Add('</tr></thead><tbody>')
            $index += 2

            while (
                $index -lt $Lines.Count -and
                $Lines[$index].Contains('|') -and
                -not [string]::IsNullOrWhiteSpace($Lines[$index])
            ) {
                $cells = @(
                    $Lines[$index].Trim().Trim('|').Split('|')
                )

                $output.Add('<tr>')

                for (
                    $column = 0
                    $column -lt $headers.Count
                    $column++
                ) {
                    $value = if ($column -lt $cells.Count) {
                        $cells[$column].Trim()
                    }
                    else {
                        ''
                    }

                    $output.Add(
                        '<td>' +
                        (Inline-Markdown -Text $value) +
                        '</td>'
                    )
                }

                $output.Add('</tr>')
                $index++
            }

            $output.Add('</tbody></table></div>')
            $index--

            continue
        }

        $heading = [regex]::Match(
            $line,
            '^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$'
        )

        if ($heading.Success) {
            Flush-Paragraph
            Close-List
            Close-Quote

            $level = $heading.Groups[1].Length
            $content = Inline-Markdown -Text $heading.Groups[2].Value

            $output.Add(
                "<h$level>" + $content + "</h$level>"
            )

            continue
        }

        if ($line -match '^\s{0,3}([-*_])(?:\s*\1){2,}\s*$') {
            Flush-Paragraph
            Close-List
            Close-Quote

            $output.Add('<hr>')

            continue
        }

        $quote = [regex]::Match(
            $line,
            '^\s{0,3}>\s?(.*)$'
        )

        if ($quote.Success) {
            Flush-Paragraph
            Close-List

            if (-not $state.Quote) {
                $output.Add('<blockquote>')
                $state.Quote = $true
            }

            $output.Add(
                '<p>' +
                (Inline-Markdown -Text $quote.Groups[1].Value) +
                '</p>'
            )

            continue
        }

        $listItem = [regex]::Match(
            $line,
            '^\s{0,3}([-+*]|\d+[.)])\s+(.+)$'
        )

        if ($listItem.Success) {
            Flush-Paragraph
            Close-Quote

            $marker = $listItem.Groups[1].Value
            $itemText = $listItem.Groups[2].Value

            $listType = if ($marker -match '^\d') {
                'ol'
            }
            else {
                'ul'
            }

            if ($state.ListType -ne $listType) {
                Close-List

                $output.Add("<$listType>")
                $state.ListType = $listType
            }

            $output.Add(
                '<li>' +
                (Inline-Markdown -Text $itemText) +
                '</li>'
            )

            continue
        }

        Close-List
        Close-Quote

        $paragraph.Add($line)
    }

    if ($inCode) {
        $output.Add(
            '<pre dir="ltr"><code>' +
            (Html ($codeLines -join "`n")) +
            '</code></pre>'
        )
    }

    Flush-Paragraph
    Close-List
    Close-Quote

    return ($output -join "`n")
}

# Validate all inputs before creating output directories or files.

if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'Path must not be empty.'
}

if ([string]::IsNullOrWhiteSpace($SiteTitle)) {
    throw 'SiteTitle must not be empty.'
}

if (
    $PSBoundParameters.ContainsKey('OutPath') -and
    [string]::IsNullOrWhiteSpace($OutPath)
) {
    throw 'OutPath must not be empty when supplied.'
}

$resolvedSource = Resolve-Path `
    -LiteralPath $Path `
    -ErrorAction Stop

if ($resolvedSource.Provider.Name -ne 'FileSystem') {
    throw 'Path must be a FileSystem directory.'
}

$source = Get-Item `
    -LiteralPath $resolvedSource.ProviderPath `
    -ErrorAction Stop

if (-not $source.PSIsContainer) {
    throw 'Path must be a FileSystem directory.'
}

if (-not $PSBoundParameters.ContainsKey('OutPath')) {
    $OutPath = Join-Path `
        (Join-Path $source.FullName 'site') `
        'index.html'
}

$outputExtension = [System.IO.Path]::GetExtension($OutPath)
$outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($OutPath)

if (
    $outputExtension -cne '.html' -or
    $outputBaseName -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$'
) {
    throw 'OutPath must end in .html and use an ASCII lowercase kebab-case basename.'
}

# Resolve relative output against PowerShell's current location.
# This also supports filesystem-backed PSDrive paths.
$outputProvider = $null
$outputDrive = $null

$outFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $OutPath,
    [ref]$outputProvider,
    [ref]$outputDrive
)

if ($outputProvider.Name -ne 'FileSystem') {
    throw 'OutPath must use the FileSystem provider.'
}

if (Test-Path -LiteralPath $outFull -PathType Container) {
    throw 'OutPath points to a directory.'
}

$files = @(
    Get-ChildItem -LiteralPath $source.FullName -File |
        Where-Object {
            $_.Name -cmatch
                '^[0-9]{4}-[a-z0-9]+(?:-[a-z0-9]+)*\.md$'
        } |
        Sort-Object -Property Name
)

$encoding = [System.Text.UTF8Encoding]::new($false, $true)
$adrs = [System.Collections.Generic.List[object]]::new()
$seen = @{}

foreach ($file in $files) {
    $id = $file.Name.Substring(0, 4)

    if ($id -eq '0000') {
        throw "Reserved ADR identifier 0000: $($file.Name)"
    }

    if ($seen.ContainsKey($id)) {
        throw "Duplicate ADR identifier: $id"
    }

    $seen[$id] = $true

    $text = [System.IO.File]::ReadAllText(
        $file.FullName,
        $encoding
    )

    $lines = [regex]::Split($text, "\r?\n")

    $headings = @(
        $lines |
            Where-Object {
                $_ -match '^# ADR-[0-9]{4}: .+$'
            }
    )

    if ($headings.Count -ne 1) {
        throw "Expected exactly one matching ADR H1 in $($file.Name)."
    }

    $headingMatch = [regex]::Match(
        $headings[0],
        "^# ADR-$($id): (.+)$"
    )

    if (-not $headingMatch.Success) {
        throw "Expected exactly one matching ADR H1 in $($file.Name)."
    }

    $title = $headingMatch.Groups[1].Value

    $statusLines = @(
        $lines |
            Where-Object {
                $_ -match '^\*\*Status\*\*: .*?$'
            }
    )

    if ($statusLines.Count -ne 1) {
        throw "Invalid or duplicate status in $($file.Name)."
    }

    $statusMatch = [regex]::Match(
        $statusLines[0],
        '^\*\*Status\*\*: (Proposed|Accepted|Rejected|Superseded)$'
    )

    if (-not $statusMatch.Success) {
        throw "Invalid or duplicate status in $($file.Name)."
    }

    $status = $statusMatch.Groups[1].Value

    $dateLines = @(
        $lines |
            Where-Object {
                $_ -match '^\*\*Date\*\*: .*?$'
            }
    )

    if ($dateLines.Count -ne 1) {
        throw "Invalid or duplicate ISO Date in $($file.Name)."
    }

    $dateText = $dateLines[0] -replace '^\*\*Date\*\*: ', ''
    $date = [datetime]::MinValue

    $validDate = [datetime]::TryParseExact(
        $dateText,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$date
    )

    if (-not $validDate) {
        throw "Invalid or duplicate ISO Date in $($file.Name)."
    }

    $supersededLines = @(
        $lines |
            Where-Object {
                $_ -match '^\*\*Superseded by\*\*: .*?$'
            }
    )

    if (
        $supersededLines.Count -gt 1 -or
        (
            $status -ne 'Superseded' -and
            $supersededLines.Count -gt 0
        )
    ) {
        throw "Unexpected or duplicate Superseded by in $($file.Name)."
    }

    if (
        $status -eq 'Superseded' -and
        $supersededLines.Count -ne 1
    ) {
        throw "Superseded ADR requires exactly one Superseded by line in $($file.Name)."
    }

    $target = $null

    if ($supersededLines.Count -eq 1) {
        $targetMatch = [regex]::Match(
            $supersededLines[0],
            '^\*\*Superseded by\*\*: ADR-([0-9]{4})$'
        )

        if (-not $targetMatch.Success) {
            throw "Malformed Superseded by in $($file.Name)."
        }

        $target = $targetMatch.Groups[1].Value

        if ($target -eq $id) {
            throw "ADR cannot supersede itself: $id"
        }
    }

    $body = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        if ($line -match '^# ADR-[0-9]{4}: ') {
            continue
        }

        if ($line -match '^\*\*(Status|Date|Superseded by)\*\*:') {
            continue
        }

        $body.Add($line)
    }

    $adrs.Add(
        [pscustomobject]@{
            Id     = $id
            File   = $file.Name
            Title  = $title
            Status = $status
            Date   = $date.ToString(
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            Target = $target
            Body   = Render-Body -Lines $body.ToArray()
        }
    )
}

foreach ($adr in $adrs) {
    if (
        $null -ne $adr.Target -and
        -not $seen.ContainsKey($adr.Target)
    ) {
        throw "ADR-$($adr.Id) references missing ADR-$($adr.Target)."
    }
}

$isPersian = $Language -eq 'fa'
$direction = if ($isPersian) { 'rtl' } else { 'ltr' }

$labels = if ($isPersian) {
    @{
        Kicker     = 'تصمیم‌های معماری'
        Description = 'تصمیم‌ها، زمینه و مسیر تکامل سامانه در یک نمای آفلاین.'
        Search     = 'جست‌وجو در عنوان، شناسه و متن'
        SearchLabel = 'جست‌وجو'
        Status     = 'وضعیت'
        All        = 'همه وضعیت‌ها'
        Clear      = 'پاک‌کردن فیلترها'
        Print      = 'چاپ / ذخیره PDF'
        Toc        = 'فهرست تصمیم‌ها'
        Warn       = 'برای تجربه کامل، جاوااسکریپت را فعال کنید.'
        Date       = 'تاریخ'
        Items      = 'تصمیم‌ها'
        Skip       = 'رفتن به تصمیم‌ها'
        Filters    = 'فیلتر تصمیم‌ها'
        Empty      = 'هیچ تصمیمی با این فیلترها پیدا نشد.'
        Superseded = 'جایگزین‌شده با '
        Footer     = 'فایل مستقل و آفلاین · برای PDF از قابلیت چاپ مرورگر استفاده کنید.'
    }
}
else {
    @{
        Kicker     = 'Architecture decisions'
        Description = 'Decisions, context and system evolution in one offline view.'
        Search     = 'Search title, ID and text'
        SearchLabel = 'Search'
        Status     = 'Status'
        All        = 'All statuses'
        Clear      = 'Clear filters'
        Print      = 'Print / Save PDF'
        Toc        = 'Decisions'
        Warn       = 'Enable JavaScript for filtering.'
        Date       = 'Date'
        Items      = 'Decisions'
        Skip       = 'Skip to decisions'
        Filters    = 'Decision filters'
        Empty      = 'No decisions match these filters.'
        Superseded = 'Superseded by '
        Footer     = 'Standalone offline file · Use your browser print dialog to save as PDF.'
    }
}

$cards = [System.Text.StringBuilder]::new()
$navigation = [System.Text.StringBuilder]::new()

$counts = @{
    Proposed   = 0
    Accepted   = 0
    Rejected   = 0
    Superseded = 0
}

foreach ($adr in $adrs) {
    $counts[$adr.Status]++

    $statusHtml = Html $adr.Status
    $titleHtml = Html $adr.Title
    $id = $adr.Id
    $statusClass = $adr.Status.ToLowerInvariant()

    $supersededHtml = ''

    if ($null -ne $adr.Target) {
        $supersededHtml = (
            '<span class="supersedes">' +
            (Html $labels.Superseded) +
            '<a href="#adr-' +
            $adr.Target +
            '">ADR-' +
            $adr.Target +
            '</a></span>'
        )
    }

    [void]$navigation.Append(
        '<a class="toc-link" href="#adr-' +
        $id +
        '"><span>ADR-' +
        $id +
        '</span> ' +
        $titleHtml +
        '</a>'
    )

    [void]$cards.Append(
        '<article class="adr-card" id="adr-' +
        $id +
        '" data-id="ADR-' +
        $id +
        '" data-title="' +
        $titleHtml +
        '" data-status="' +
        $statusHtml +
        '"><header class="card-head"><div><span class="adr-id">ADR-' +
        $id +
        '</span><h2>' +
        $titleHtml +
        '</h2></div><span class="badge status-' +
        $statusClass +
        '">' +
        $statusHtml +
        '</span></header><div class="meta"><span>' +
        (Html $labels.Date) +
        ': <time>' +
        $adr.Date +
        '</time></span>' +
        $supersededHtml +
        '</div><div class="markdown">' +
        $adr.Body +
        '</div></article>'
    )
}

$template = @'
<!doctype html>
<html lang="__LANG__" dir="__DIR__">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<title>__TITLE__</title>
<style>
:root {
    --navy: #14263e;
    --teal: #087f83;
    --paper: #f3f6f8;
    --ink: #26364a;
    --muted: #617185;
    --line: #dce4ea;
    --card: #fff;
}

* { box-sizing: border-box; }
html { scroll-behavior: smooth; }

body {
    margin: 0;
    background: var(--paper);
    color: var(--ink);
    font: 16px/1.75 Tahoma, "Segoe UI", sans-serif;
}

a { color: var(--teal); }

a:focus-visible,
button:focus-visible,
input:focus-visible,
select:focus-visible {
    outline: 3px solid #e49a41;
    outline-offset: 3px;
}

.skip {
    position: absolute;
    inset-block-start: -8rem;
    inset-inline-start: 1rem;
    background: #fff;
    padding: .7rem;
    z-index: 10;
}

.skip:focus { inset-block-start: 1rem; }

.hero {
    background: linear-gradient(125deg, #14263e, #1b4457 72%, #087f83);
    color: white;
    padding: 2.5rem max(1.25rem, calc((100% - 1200px)/2));
    position: relative;
    overflow: hidden;
}

.hero:after {
    content: "";
    position: absolute;
    width: 20rem;
    height: 20rem;
    border: 1px solid #ffffff25;
    border-radius: 50%;
    inset-inline-end: -6rem;
    top: -10rem;
    box-shadow: 0 0 0 30px #ffffff08, 0 0 0 60px #ffffff08;
}

.hero-inner { position: relative; z-index: 1; }

.eyebrow {
    color: #9de6d8;
    font-size: .85rem;
    letter-spacing: .08em;
}

.hero h1 {
    font-size: clamp(1.8rem, 4vw, 3rem);
    line-height: 1.25;
    margin: .3rem 0;
}

.hero p { color: #d5e4ea; margin: .4rem 0; }

.stats {
    display: flex;
    gap: .7rem;
    flex-wrap: wrap;
    margin-top: 1.2rem;
}

.stat {
    border: 1px solid #ffffff30;
    background: #ffffff12;
    border-radius: 12px;
    padding: .45rem .8rem;
    min-width: 7rem;
}

.stat b { font-size: 1.25rem; margin-inline-end: .35rem; }

.toolbar {
    max-width: 1200px;
    margin: 1.3rem auto;
    padding: 0 1.2rem;
    display: flex;
    align-items: end;
    gap: .7rem;
    flex-wrap: wrap;
}

.field {
    display: grid;
    gap: .2rem;
    flex: 1 1 16rem;
    color: var(--muted);
    font-size: .9rem;
}

.field input,
.field select,
button {
    font: inherit;
    border: 1px solid #cbd6df;
    border-radius: 9px;
    background: white;
    color: var(--ink);
    padding: .65rem .8rem;
}

.field input { min-width: 0; }
button { cursor: pointer; font-weight: 600; }
button:hover { border-color: var(--teal); color: var(--teal); }

.layout {
    max-width: 1200px;
    margin: 0 auto 4rem;
    padding: 0 1.2rem;
    display: grid;
    grid-template-columns: 250px minmax(0, 1fr);
    gap: 1.4rem;
}

.sidebar {
    position: sticky;
    top: 1rem;
    align-self: start;
    background: #fff;
    border: 1px solid var(--line);
    border-radius: 14px;
    padding: 1rem;
    max-height: 75vh;
    overflow: auto;
}

.sidebar h2 { font-size: 1rem; margin: 0 0 .6rem; }

.toc-link {
    display: block;
    text-decoration: none;
    padding: .4rem .5rem;
    border-radius: 7px;
    font-size: .9rem;
}

.toc-link span {
    font-weight: bold;
    color: var(--teal);
    white-space: nowrap;
}

.toc-link:hover { background: #edf6f5; }
.toc-link[hidden] { display: none; }

.cards { min-width: 0; display: grid; gap: 1rem; }

.adr-card {
    background: var(--card);
    border: 1px solid var(--line);
    border-radius: 15px;
    padding: clamp(1rem, 3vw, 1.6rem);
    box-shadow: 0 5px 18px #1c35440b;
    scroll-margin-top: 1rem;
}

.adr-card[hidden] { display: none; }

.card-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 1rem;
    border-bottom: 1px solid #edf0f3;
    padding-bottom: .8rem;
}

.card-head h2 {
    margin: .1rem 0;
    font-size: clamp(1.2rem, 2vw, 1.65rem);
    line-height: 1.45;
}

.adr-id {
    font: 600 .85rem/1.4 ui-monospace, Consolas, monospace;
    color: var(--teal);
    direction: ltr;
    display: inline-block;
}

.badge {
    border-radius: 999px;
    padding: .22rem .7rem;
    font-size: .8rem;
    font-weight: bold;
    white-space: nowrap;
    background: #e9eef4;
    color: #42536a;
}

.status-accepted { background: #dff4eb; color: #176748; }
.status-rejected { background: #fde8e6; color: #9f3931; }
.status-superseded { background: #eee8fc; color: #6545a3; }
.status-proposed { background: #fff0d8; color: #89520b; }

.meta {
    display: flex;
    gap: 1rem;
    flex-wrap: wrap;
    color: var(--muted);
    font-size: .9rem;
    padding: .65rem 0;
}

.markdown { overflow-wrap: anywhere; }
.markdown h1, .markdown h2, .markdown h3 { line-height: 1.4; }

.markdown pre {
    overflow: auto;
    max-width: 100%;
    background: #152238;
    color: #edf4fa;
    padding: 1rem;
    border-radius: 9px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
}

.markdown code {
    font: .92em ui-monospace, Consolas, monospace;
    background: #eef2f5;
    padding: .12em .3em;
    border-radius: 4px;
}

.markdown pre code { background: none; padding: 0; }

.markdown blockquote {
    margin-inline: 0;
    border-inline-start: 4px solid #56aaa0;
    padding: .1rem 1rem;
    color: #506176;
    background: #f7fafb;
}

.markdown .table-wrap { max-width: 100%; overflow: auto; }
.markdown table { border-collapse: collapse; width: 100%; }

.markdown th, .markdown td {
    border: 1px solid var(--line);
    padding: .45rem .7rem;
}

.empty {
    display: none;
    text-align: center;
    padding: 2rem;
    color: var(--muted);
    background: #fff;
    border-radius: 12px;
}

.empty.show { display: block; }
.noscript { background: #fff2cf; padding: .7rem 1rem; text-align: center; }

.footer {
    text-align: center;
    color: var(--muted);
    font-size: .85rem;
    padding: 1rem;
}

@media(max-width: 800px) {
    .layout { grid-template-columns: 1fr; }
    .sidebar { position: static; max-height: 14rem; }
    .toolbar { margin-top: 1rem; }
    .hero { padding-top: 1.6rem; padding-bottom: 1.6rem; }
}

@media(max-width: 480px) {
    .toolbar { display: grid; grid-template-columns: 1fr; }
    .field { min-width: 0; }
    .card-head { display: grid; }
    .hero:after { opacity: .4; }
}

@media(prefers-reduced-motion: reduce) {
    *, *:before, *:after {
        scroll-behavior: auto !important;
        transition: none !important;
    }
}

@page { size: A4; margin: 15mm; }

@media print {
    body { background: #fff; color: #111; font-size: 10.5pt; }

    .hero {
        background: #fff;
        color: #111;
        padding: 0 0 8mm;
        border-bottom: 2px solid #333;
    }

    .hero:after, .toolbar, .sidebar, .skip, .noscript, .footer {
        display: none !important;
    }

    .hero p, .eyebrow { color: #333; }
    .layout { display: block; max-width: none; margin: 0; padding: 0; }
    .cards { display: block; }

    .adr-card {
        display: block !important;
        box-shadow: none;
        border: 1px solid #aaa;
        border-radius: 0;
        margin: 0 0 8mm;
        padding: 7mm;
        break-inside: auto;
    }

    .adr-card[hidden]{display:block!important}

    .card-head { break-after: avoid; }
    .markdown p { orphans: 3; widows: 3; }

    .markdown pre {
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        background: #f3f3f3;
        color: #111;
    }

    .empty { display: none !important; }
    a { color: #111; text-decoration: none; }
}
</style>
</head>
<body>
<a class="skip" href="#main">__SKIP__</a>

<header class="hero">
    <div class="hero-inner">
        <div class="eyebrow">__KICKER__</div>
        <h1>__TITLE__</h1>
        <p>__DESC__</p>
        <div class="stats">
            <div class="stat"><b>__TOTAL__</b>__ITEMS__</div>
            <div class="stat"><b>__PROPOSED__</b>Proposed</div>
            <div class="stat"><b>__ACCEPTED__</b>Accepted</div>
            <div class="stat"><b>__REJECTED__</b>Rejected</div>
            <div class="stat"><b>__SUPERSEDED__</b>Superseded</div>
        </div>
    </div>
</header>

<noscript><div class="noscript">__WARN__</div></noscript>

<main id="main">
    <section class="toolbar" aria-label="__FILTERS__">
        <label class="field">
            <span>__SEARCH_LABEL__</span>
            <input
                id="search"
                type="search"
                placeholder="__SEARCH__"
                aria-label="__SEARCH_LABEL__"
            >
        </label>

        <label class="field">
            <span>__STATUS_LABEL__</span>
            <select id="status" aria-label="__STATUS_LABEL__">
                <option value="">__ALL__</option>
                <option>Proposed</option>
                <option>Accepted</option>
                <option>Rejected</option>
                <option>Superseded</option>
            </select>
        </label>

        <button id="clear" type="button">__CLEAR__</button>
        <button id="print" type="button">__PRINT__</button>
        <span id="result-count" aria-live="polite"></span>
    </section>

    <div class="layout">
        <aside class="sidebar">
            <h2>__TOC__</h2>
            <nav id="toc">__NAV__</nav>
        </aside>

        <section class="cards" id="cards" aria-label="__ITEMS__">
            __CARDS__
            <div class="empty" id="empty">__EMPTY__</div>
        </section>
    </div>
</main>

<footer class="footer">__FOOTER__</footer>

<script>
(() => {
    'use strict';

    const search = document.getElementById('search');
    const status = document.getElementById('status');
    const cards = [...document.querySelectorAll('.adr-card')];
    const links = [...document.querySelectorAll('.toc-link')];
    const empty = document.getElementById('empty');
    const count = document.getElementById('result-count');

    const norm = value => String(value ?? '')
        .toLowerCase()
        .normalize('NFKC')
        .replace(/[\u064B-\u065F\u0670\u0640\u200c\u200d]/g, '')
        .replace(/[\u064A\u0649]/g, '\u06CC')
        .replace(/\u0643/g, '\u06A9')
        .replace(/\s+/g, ' ')
        .trim();

    const index = cards.map(card => norm(card.textContent));

    function filter() {
        let visibleCount = 0;
        const query = norm(search.value);
        const selectedStatus = status.value;

        cards.forEach((card, position) => {
            const matches = (
                (!query || index[position].includes(query)) &&
                (!selectedStatus || card.dataset.status === selectedStatus)
            );

            card.hidden = !matches;

            if (matches) {
                visibleCount++;
            }
        });

        links.forEach(link => {
            const targetId = link.getAttribute('href').slice(1);
            const card = document.getElementById(targetId);
            link.hidden = Boolean(card?.hidden);
        });

        empty.classList.toggle('show', visibleCount === 0);
        count.textContent = visibleCount + ' / ' + cards.length;
    }

    function revealHash() {
        const hash = location.hash;

        if (!/^#adr-\d{4}$/.test(hash)) {
            return;
        }

        const target = document.getElementById(hash.slice(1));

        if (target?.hidden) {
            search.value = '';
            status.value = '';
            filter();
        }

        requestAnimationFrame(() => target?.scrollIntoView());
    }

    search.addEventListener('input', filter);
    status.addEventListener('change', filter);

    document.getElementById('clear').addEventListener('click', () => {
        search.value = '';
        status.value = '';
        filter();
        search.focus();
    });

    document.getElementById('print').addEventListener('click', () => {
        window.print();
    });

    window.addEventListener('hashchange', revealHash);

    filter();
    revealHash();

    window.adrSearchNormalize = norm;
})();
</script>
</body>
</html>
'@

$replacements = @{
    '__LANG__'         = $Language
    '__DIR__'          = $direction
    '__TITLE__'        = Html $SiteTitle
    '__KICKER__'       = Html $labels.Kicker
    '__DESC__'         = Html $labels.Description
    '__TOTAL__'        = $adrs.Count
    '__ITEMS__'        = Html $labels.Items
    '__PROPOSED__'     = $counts.Proposed
    '__ACCEPTED__'     = $counts.Accepted
    '__REJECTED__'     = $counts.Rejected
    '__SUPERSEDED__'   = $counts.Superseded
    '__SKIP__'         = Html $labels.Skip
    '__WARN__'         = Html $labels.Warn
    '__FILTERS__'      = Html $labels.Filters
    '__SEARCH_LABEL__' = Html $labels.SearchLabel
    '__SEARCH__'       = Html $labels.Search
    '__STATUS_LABEL__' = Html $labels.Status
    '__ALL__'          = Html $labels.All
    '__CLEAR__'        = Html $labels.Clear
    '__PRINT__'        = Html $labels.Print
    '__TOC__'          = Html $labels.Toc
    '__NAV__'          = $navigation.ToString()
    '__CARDS__'        = $cards.ToString()
    '__EMPTY__'        = Html $labels.Empty
    '__FOOTER__'       = Html $labels.Footer
}

# One-pass replacement prevents user text from being interpreted
# as another template token.
$evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
    param($match)

    if ($replacements.ContainsKey($match.Value)) {
        return [string]$replacements[$match.Value]
    }

    return $match.Value
}

$built = [regex]::Replace(
    $template,
    '__[A-Z_]+__',
    $evaluator
)

# Ensure LF-only output and exactly one final newline.
$built = $built.Replace("`r`n", "`n").Replace("`r", "`n")
$built = $built.TrimEnd([char[]]"`n") + "`n"

$parent = [System.IO.Path]::GetDirectoryName($outFull)
$temporaryFile = $null

try {
    if (-not (Test-Path -LiteralPath $parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }

    $temporaryFile = Join-Path `
        $parent `
        ('.adr-export-' + [guid]::NewGuid().ToString('N') + '.tmp')

    [System.IO.File]::WriteAllText(
        $temporaryFile,
        $built,
        [System.Text.UTF8Encoding]::new($false)
    )

    Move-Item `
        -LiteralPath $temporaryFile `
        -Destination $outFull `
        -Force

    Get-Item -LiteralPath $outFull
}
finally {
    if (
        $null -ne $temporaryFile -and
        (Test-Path -LiteralPath $temporaryFile)
    ) {
        Remove-Item -LiteralPath $temporaryFile -Force
    }
}
`
