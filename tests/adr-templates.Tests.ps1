# Pester 5.5 tests for ADR template customization.

Describe 'ADR template customization' {
    BeforeAll {
        $scriptPath = [System.IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '../adr.ps1')
        )

        function Write-FixtureText {
            param(
                [Parameter(Mandatory)]
                [string]$LiteralPath,

                [Parameter(Mandatory)]
                [AllowEmptyString()]
                [string]$Content
            )

            $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
                $LiteralPath
            )

            $parent = Split-Path -Parent $fullPath

            if (-not (Test-Path -LiteralPath $parent)) {
                [void](New-Item -ItemType Directory -Path $parent -Force)
            }

            [System.IO.File]::WriteAllText(
                $fullPath,
                $Content,
                [System.Text.UTF8Encoding]::new($false)
            )
        }

        function Read-FixtureText {
            param(
                [Parameter(Mandatory)]
                [string]$LiteralPath
            )

            $fullPath = (
                Resolve-Path -LiteralPath $LiteralPath -ErrorAction Stop
            ).ProviderPath

            [System.IO.File]::ReadAllText(
                $fullPath,
                [System.Text.Encoding]::UTF8
            )
        }

        function Get-CreatedAdrText {
            $files = @(
                Get-ChildItem -LiteralPath 'adrs' -Filter '*.md' -File
            )

            $files.Count | Should -Be 1

            Read-FixtureText -LiteralPath $files[0].FullName
        }

        function New-ValidTemplate {
            param(
                [string]$HeadingToken = 'ID',
                [string]$Body = '## Custom body'
            )

            return @"
# ADR-{{$HeadingToken}}: {{TITLE}}
**Status**: {{STATUS}}
**Date**: {{DATE}}
$Body
"@
        }

        function Invoke-NewAdr {
            param(
                [string]$Title = 'Testing',
                [string]$Target = 'adrs',

                [AllowEmptyString()]
                [string]$TemplateName,

                [string]$Slug = 'testing'
            )

            $parameters = @{
                Title = $Title
                Slug  = $Slug
                Path  = $Target
            }

            if ($PSBoundParameters.ContainsKey('TemplateName')) {
                $parameters.Template = $TemplateName
            }

            & $scriptPath @parameters
        }
    }

    BeforeEach {
        $sandbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))

        [void](New-Item -ItemType Directory -Path $sandbox -Force)

        Push-Location -LiteralPath $sandbox
    }

    AfterEach {
        Pop-Location
    }

    It 'uses the built-in template by default with Proposed and invariant Gregorian date' {
        Invoke-NewAdr

        $text = Get-CreatedAdrText

        $text | Should -Match '(?m)^# ADR-0001: Testing$'
        $text | Should -Match '(?m)^## Context$'
        $text | Should -Match '(?m)^## Decision Drivers$'
        $text | Should -Match '(?m)^## Considered Options$'
        $text | Should -Match '(?m)^## Decision Outcome$'
        $text | Should -Match '(?m)^### Consequences$'
        $text | Should -Match '(?m)^## References$'
        $text | Should -Match '(?m)^\*\*Status\*\*: Proposed$'

        $match = [regex]::Match(
            $text,
            '(?m)^\*\*Date\*\*: (\d{4}-\d{2}-\d{2})$'
        )

        $match.Success | Should -BeTrue

        $culture = [System.Globalization.CultureInfo]::InvariantCulture

        $parsedDate = [DateTime]::ParseExact(
            $match.Groups[1].Value,
            'yyyy-MM-dd',
            $culture
        )

        $parsedDate.ToString('yyyy-MM-dd', $culture) |
            Should -Be $match.Groups[1].Value
    }

    It 'selects Path/templates named template before CWD template and accepts optional md suffix' {
        Write-FixtureText 'adrs/templates/minimal.md' (
            New-ValidTemplate -Body 'PATH-VERSION'
        )

        Write-FixtureText '.adr-templates/minimal.md' (
            New-ValidTemplate -Body 'CWD-VERSION'
        )

        Invoke-NewAdr -TemplateName 'minimal.md'

        $text = Get-CreatedAdrText

        $text | Should -Match 'PATH-VERSION'
        $text | Should -Not -Match 'CWD-VERSION'
    }

    It 'uses CWD .adr-templates for a missing named template in Path/templates' {
        Write-FixtureText '.adr-templates/minimal.md' (
            New-ValidTemplate -Body 'CWD-VERSION'
        )

        Invoke-NewAdr -TemplateName 'minimal'

        Get-CreatedAdrText | Should -Match 'CWD-VERSION'
    }

    It 'uses Path default before CWD default and automatically selects either default' {
        Write-FixtureText 'adrs/templates/default.md' (
            New-ValidTemplate -Body 'PATH-DEFAULT'
        )

        Write-FixtureText '.adr-templates/default.md' (
            New-ValidTemplate -Body 'CWD-DEFAULT'
        )

        Invoke-NewAdr

        $text = Get-CreatedAdrText

        $text | Should -Match 'PATH-DEFAULT'
        $text | Should -Not -Match 'CWD-DEFAULT'
    }

    It 'automatically uses CWD default when Path default is absent' {
        Write-FixtureText '.adr-templates/default.md' (
            New-ValidTemplate -Body 'CWD-DEFAULT'
        )

        Invoke-NewAdr

        Get-CreatedAdrText | Should -Match 'CWD-DEFAULT'
    }

    It 'loads explicit relative and absolute template paths without extension guessing' {
        Write-FixtureText 'fixtures/explicit.md' (
            New-ValidTemplate -Body 'EXPLICIT-PATH'
        )

        Invoke-NewAdr -TemplateName './fixtures/explicit.md'

        Get-CreatedAdrText | Should -Match 'EXPLICIT-PATH'

        Remove-Item -LiteralPath 'adrs' -Recurse -Force

        $absolutePath = (
            Resolve-Path -LiteralPath 'fixtures/explicit.md'
        ).ProviderPath

        Invoke-NewAdr -TemplateName $absolutePath

        Get-CreatedAdrText | Should -Match 'EXPLICIT-PATH'

        Remove-Item -LiteralPath 'adrs' -Recurse -Force

        # The implementation must not append ".md" to an explicit path.
        { Invoke-NewAdr -TemplateName './fixtures/explicit' } |
            Should -Throw

        Test-Path -LiteralPath 'adrs' | Should -BeFalse
    }

    It 'errors for missing named and explicit templates without creating ADR output' {
        foreach ($name in @('missing', 'missing.md', './fixtures/missing.md')) {
            { Invoke-NewAdr -TemplateName $name } | Should -Throw

            Test-Path -LiteralPath 'adrs' | Should -BeFalse
        }
    }

    It 'rejects explicit empty or whitespace Template before output creation' {
        {
            & $scriptPath -Title 'Testing' -Slug 'testing' -Path 'adrs' -Template ''
        } | Should -Throw

        {
            & $scriptPath -Title 'Testing' -Slug 'testing' -Path 'adrs' -Template '   '
        } | Should -Throw

        Test-Path -LiteralPath 'adrs' | Should -BeFalse
    }

    It 'rejects a directory template candidate rather than falling through' {
        [void](
            New-Item -ItemType Directory `
                -Path 'adrs/templates/minimal.md' `
                -Force
        )

        Write-FixtureText '.adr-templates/minimal.md' (
            New-ValidTemplate -Body 'SHOULD-NOT-USE'
        )

        { Invoke-NewAdr -TemplateName 'minimal' } | Should -Throw

        Test-Path -LiteralPath 'adrs' | Should -BeTrue

        $createdAdrs = @(
            Get-ChildItem -LiteralPath 'adrs' -Recurse -File |
                Where-Object Name -Like '0001-*'
        )

        $createdAdrs.Count | Should -Be 0
    }

    It 'rejects invalid template names and explicit filename casing' {
        foreach ($name in @(
            'Minimal'
            'two_words'
            '../minimal'
            'minimal.MD'
            'has space'
        )) {
            { Invoke-NewAdr -TemplateName $name } | Should -Throw

            Test-Path -LiteralPath 'adrs' | Should -BeFalse
        }

        Write-FixtureText 'fixtures/Bad.md' (New-ValidTemplate)

        { Invoke-NewAdr -TemplateName './fixtures/Bad.md' } |
            Should -Throw

        Test-Path -LiteralPath 'adrs' | Should -BeFalse
    }

    It 'rejects unsupported and case-variant token names before output creation' {
        foreach ($token in @('{{FOO}}', '{{title}}', '{{ TITLE }}')) {
            $content = (New-ValidTemplate) + "`n$token`n"

            Write-FixtureText 'fixtures/minimal.md' $content

            { Invoke-NewAdr -TemplateName './fixtures/minimal.md' } |
                Should -Throw

            Test-Path -LiteralPath 'adrs' | Should -BeFalse
        }
    }

    It 'requires exactly one contractual ADR heading, Status, and Date and no Superseded by line' {
        $valid = New-ValidTemplate

        $badTemplates = @(
            (
                $valid -replace
                    '# ADR-\{\{ID\}\}: \{\{TITLE\}\}',
                    '# ADR-0001: {{TITLE}}'
            )
            ($valid + "`n# ADR-{{ID}}: {{TITLE}}")
            (
                $valid -replace
                    '\*\*Status\*\*: \{\{STATUS\}\}',
                    '**Status**: Proposed'
            )
            ($valid + "`n**Status**: {{STATUS}}")
            (
                $valid -replace
                    '\*\*Date\*\*: \{\{DATE\}\}',
                    '**Date**: 2020-01-01'
            )
            ($valid + "`n**Date**: {{DATE}}")
            ($valid + "`n**Superseded by**: ADR-0002")
        )

        foreach ($bad in $badTemplates) {
            Write-FixtureText 'fixtures/minimal.md' $bad

            { Invoke-NewAdr -TemplateName './fixtures/minimal.md' } |
                Should -Throw

            Test-Path -LiteralPath 'adrs' | Should -BeFalse
        }
    }

    It 'renders aliases and every supported placeholder while allowing omitted Author and custom body' {
        $fixture = @'
# ADR-{{ADR_ID}}: {{TITLE}}
**Status**: {{STATUS}}
**Date**: {{DATE}}
{{ID}}/{{ADR_ID}} {{TITLE}} {{DATE}} {{AUTHOR}} {{STATUS}}
'@

        Write-FixtureText 'adrs/templates/minimal.md' $fixture

        Invoke-NewAdr -Title 'Rendered title' -TemplateName 'minimal'

        $text = Get-CreatedAdrText

        $text | Should -Match '(?m)^# ADR-0001: Rendered title$'

        $text | Should -Match (
            '(?m)^0001/0001 Rendered title \d{4}-\d{2}-\d{2} .+ Proposed$'
        )

        $text | Should -Not -Match (
            '\{\{(?:ID|ADR_ID|TITLE|DATE|AUTHOR|STATUS)\}\}'
        )

        Remove-Item -LiteralPath 'adrs' -Recurse -Force

        Write-FixtureText 'adrs/templates/minimal.md' (
            New-ValidTemplate -Body 'No author token here'
        )

        Invoke-NewAdr -TemplateName 'minimal'

        Get-CreatedAdrText | Should -Match 'No author token here'
    }

    It 'inserts title values literally in one pass without interpolation or recursive token expansion' {
        $literalTitle = 'Literal {{STATUS}} $1 \path $(Get-Date)'

        Invoke-NewAdr -Title $literalTitle -Slug 'literal'

        $text = Get-CreatedAdrText

        $expectedHeading = '# ADR-0001: ' + $literalTitle

        $text | Should -Match (
            '(?m)^' + [regex]::Escape($expectedHeading) + '$'
        )

        $text | Should -Match '(?m)^\*\*Status\*\*: Proposed$'
    }

    It 'normalizes CRLF to LF, writes one final LF, and writes UTF-8 without BOM including Persian text' {
        $fixture = (New-ValidTemplate -Body 'متن فارسی') -replace "`r?`n", "`r`n"

        Write-FixtureText 'fixtures/crlf.md' $fixture

        Invoke-NewAdr -TemplateName './fixtures/crlf.md'

        $files = @(
            Get-ChildItem -LiteralPath 'adrs' -Filter '*.md' -File
        )

        $files.Count | Should -Be 1

        $bytes = [System.IO.File]::ReadAllBytes($files[0].FullName)

        $hasBom = (
            $bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
        )

        $hasBom | Should -BeFalse

        $text = [System.Text.Encoding]::UTF8.GetString($bytes)

        $text | Should -Match 'متن فارسی'
        $text | Should -Not -Match "`r"
        $text.EndsWith("`n") | Should -BeTrue
        $text.EndsWith("`n`n") | Should -BeFalse
    }

    It 'keeps existing ID numbering and interoperates with Edit, SetStatus, GenerateIndex, and VerifyIndex' {
        $existing = @'
# ADR-0003: Existing

**Status**: Proposed
**Date**: 2020-01-01
'@

        Write-FixtureText 'adrs/0003-existing.md' ($existing + "`n")

        Invoke-NewAdr -Title 'New' -Slug 'next'

        Test-Path -LiteralPath 'adrs/0004-next.md' -PathType Leaf |
            Should -BeTrue

        & $scriptPath -Edit -AdrId 4 -NewTitle 'Updated title' -Path 'adrs'
        & $scriptPath -SetStatus -AdrId 4 -Status 'Accepted' -Path 'adrs'
        & $scriptPath -GenerateIndex -Path 'adrs'
        & $scriptPath -VerifyIndex -Path 'adrs'

        $content = Read-FixtureText 'adrs/0004-next.md'

        $content | Should -Match '(?m)^# ADR-0004: Updated title$'
        $content | Should -Match '(?m)^\*\*Status\*\*: Accepted$'

        Read-FixtureText 'adrs/readme.md' |
            Should -Match '\| 0004 \| \[Updated title\]'
    }

    It 'does not bind Template on non-New parameter sets' {
        $command = Get-Command -Name $scriptPath -ErrorAction Stop

        $newParameterSets = @(
            $command.ParameterSets |
                Where-Object Name -EQ 'New'
        )

        $newParameterSets.Count | Should -Be 1
        $newParameterSets[0].Parameters.Name | Should -Contain 'Template'

        $otherParameterSets = @(
            $command.ParameterSets |
                Where-Object Name -NE 'New'
        )

        $otherParameterSets.Count | Should -BeGreaterThan 0

        foreach ($parameterSet in $otherParameterSets) {
            $parameterSet.Parameters.Name | Should -Not -Contain 'Template'
        }
    }
}
