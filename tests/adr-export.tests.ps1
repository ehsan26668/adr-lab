#requires -Version 7.0
# Pester 5.5.0; self-contained and offline.

Describe 'ADR export test suite' {
    BeforeAll {
        $script:Exporter = Join-Path (
            Split-Path $PSScriptRoot -Parent
        ) 'export-adr.ps1'

        $script:Installer = Join-Path (
            Split-Path $PSScriptRoot -Parent
        ) 'install-adr-export.ps1'

        function Write-FixtureText {
            param(
                [Parameter(Mandatory)]
                [string]$File,

                [Parameter(Mandatory)]
                [AllowEmptyString()]
                [string]$Text
            )

            $parent = Split-Path -Parent $File

            if (-not (Test-Path -LiteralPath $parent)) {
                [void][System.IO.Directory]::CreateDirectory($parent)
            }

            [System.IO.File]::WriteAllText(
                $File,
                $Text,
                [System.Text.UTF8Encoding]::new($false)
            )
        }

        function New-Fixture {
            param(
                [Parameter(Mandatory)]
                [string]$Dir,

                [string]$Name = '0001-sample.md',

                [string]$Body = "## Context`nHello **world**"
            )

            [void][System.IO.Directory]::CreateDirectory($Dir)

            $id = $Name.Substring(0, 4)

            $text = @"
# ADR-$($id): Sample $id

**Status**: Proposed
**Date**: 2026-11-06

$Body
"@

            Write-FixtureText `
                -File (Join-Path $Dir $Name) `
                -Text $text
        }
    }

    BeforeEach {
        $script:D = Join-Path `
            $TestDrive `
            ([guid]::NewGuid().ToString('N'))

        [void][System.IO.Directory]::CreateDirectory($script:D)

        $script:Src = Join-Path $script:D 'decisions'

        [void][System.IO.Directory]::CreateDirectory($script:Src)

        New-Fixture -Dir $script:Src
    }

    Describe 'ADR HTML exporter' {
        It 'exports to default site/index.html and returns the file' {
            $file = & $script:Exporter -Path $script:Src

            $file | Should -BeOfType ([System.IO.FileInfo])
            $file.Name | Should -Be 'index.html'
            $file.Exists | Should -BeTrue

            $expectedPath = Join-Path $script:Src 'site/index.html'

            $file.FullName |
                Should -Be ([System.IO.Path]::GetFullPath($expectedPath))
        }

        It 'accepts explicit output and English language' {
            $output = Join-Path $script:D 'out/report.html'

            $file = & $script:Exporter `
                -Path $script:Src `
                -OutPath $output `
                -Language en

            $file.Exists | Should -BeTrue

            $file.FullName |
                Should -Be ([System.IO.Path]::GetFullPath($output))

            (Get-Content -LiteralPath $output -Raw) |
                Should -Match 'lang="en"\s+dir="ltr"'
        }

        It 'writes UTF-8 without BOM and LF only' {
            $file = & $script:Exporter -Path $script:Src

            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

            $hasBom = (
                $bytes.Length -ge 3 -and
                $bytes[0] -eq 239 -and
                $bytes[1] -eq 187 -and
                $bytes[2] -eq 191
            )

            $hasBom | Should -BeFalse

            # Throw if the generated file contains invalid UTF-8.
            $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
            $html = $utf8.GetString($bytes)

            $html | Should -Not -Match "`r"
        }

        It 'embeds no external resources and includes offline CSS and JavaScript' {
            $file = & $script:Exporter -Path $script:Src
            $html = Get-Content -LiteralPath $file.FullName -Raw

            $html | Should -Match '<style>'
            $html | Should -Match '<script>'
            $html | Should -Not -Match '(?i)(src|href)="https?://'
        }

        It 'filters only immediate valid ADR filenames' {
            New-Fixture -Dir $script:Src -Name '0002-two-words.md'

            Write-FixtureText `
                -File (Join-Path $script:Src 'README.md') `
                -Text 'ignored'

            $nested = Join-Path $script:Src 'nested'

            New-Fixture -Dir $nested -Name '0003-hidden.md'

            $file = & $script:Exporter -Path $script:Src
            $html = Get-Content -LiteralPath $file.FullName -Raw

            $html | Should -Match 'ADR-0001'
            $html | Should -Match 'ADR-0002'
            $html | Should -Not -Match 'ADR-0003'
        }

        It 'supports an empty source folder' {
            Get-ChildItem -LiteralPath $script:Src -Filter '*.md' -File |
                Remove-Item -Force

            $file = & $script:Exporter `
                -Path $script:Src `
                -Language en

            $file.Exists | Should -BeTrue

            $html = Get-Content -LiteralPath $file.FullName -Raw

            $html | Should -Match 'No decisions match'
        }

        It 'does not modify source files' {
            $sourceFile = Join-Path $script:Src '0001-sample.md'
            $before = (Get-FileHash -LiteralPath $sourceFile).Hash

            $null = & $script:Exporter -Path $script:Src

            $after = (Get-FileHash -LiteralPath $sourceFile).Hash

            $after | Should -Be $before
        }

        It 'escapes HTML in fenced code' {
            $body = @'
```html
<script>alert(1)</script> &
'@

        New-Fixture -Dir $script:Src -Body $body

        $file = & $script:Exporter -Path $script:Src
        $html = Get-Content -LiteralPath $file.FullName -Raw

        $html | Should -Match '&lt;script&gt;'
        $html | Should -Match '&amp;'
        $html | Should -Not -Match '<script>alert'
    }

    It 'rejects missing source before creating output' {
        $outputDirectory = Join-Path $script:D 'absent'
        $output = Join-Path $outputDirectory 'x.html'
        $missingSource = Join-Path $script:D 'missing'

        {
            $null = & $script:Exporter `
                -Path $missingSource `
                -OutPath $output
        } | Should -Throw

        Test-Path -LiteralPath $output | Should -BeFalse

        Test-Path -LiteralPath $outputDirectory |
            Should -BeFalse
    }

    It 'rejects blank path, title, output, and a bad output extension' {
        $cases = @(
            @{ Path = ' ' }
            @{ Path = $script:Src; SiteTitle = ' ' }
            @{ Path = $script:Src; OutPath = ' ' }
            @{
                Path    = $script:Src
                OutPath = (Join-Path $script:D 'x.txt')
            }
        )

        foreach ($parameters in $cases) {
            {
                $null = & $script:Exporter @parameters
            } | Should -Throw
        }
    }

    It 'rejects invalid ADR metadata' {
        $sourceFile = Join-Path $script:Src '0001-sample.md'
        $original = Get-Content -LiteralPath $sourceFile -Raw

        $invalidDocuments = @(
            (
                $original -replace `
                    '2026-11-06', `
                    '2026-02-30'
            )
            (
                $original + "`n**Status**: Accepted`n"
            )
            (
                $original -replace `
                    '# ADR-0001: Sample 0001', `
                    '# ADR-0002: Wrong'
            )
        )

        try {
            foreach ($invalidDocument in $invalidDocuments) {
                Write-FixtureText `
                    -File $sourceFile `
                    -Text $invalidDocument

                {
                    $null = & $script:Exporter -Path $script:Src
                } | Should -Throw
            }
        }
        finally {
            Write-FixtureText -File $sourceFile -Text $original
        }
    }

    It 'is deterministic and preserves prior output on validation failure' {
        $output = Join-Path $script:D 'stable.html'

        $null = & $script:Exporter `
            -Path $script:Src `
            -OutPath $output

        $originalHash = (Get-FileHash -LiteralPath $output).Hash

        $null = & $script:Exporter `
            -Path $script:Src `
            -OutPath $output

        (Get-FileHash -LiteralPath $output).Hash |
            Should -Be $originalHash

        Write-FixtureText `
            -File (Join-Path $script:Src '0001-sample.md') `
            -Text 'broken'

        {
            $null = & $script:Exporter `
                -Path $script:Src `
                -OutPath $output
        } | Should -Throw

        (Get-FileHash -LiteralPath $output).Hash |
            Should -Be $originalHash
    }

    It 'has static print-all and Persian normalization logic' {
        $source = Get-Content -LiteralPath $script:Exporter -Raw

        $printRule = (
            '\.adr-card\[hidden\]\s*\{' +
            '\s*display\s*:\s*block\s*!\s*important\s*;?\s*\}'
        )

        $source | Should -Match $printRule
        $source | Should -Match '\\u064A'
    }

    It 'validates superseded cross-reference and renders a link' {
        New-Fixture -Dir $script:Src -Name '0002-next.md'

        $sourceFile = Join-Path $script:Src '0001-sample.md'
        $text = Get-Content -LiteralPath $sourceFile -Raw

        $text = $text.Replace(
            '**Status**: Proposed',
            '**Status**: Superseded'
        )

        Write-FixtureText `
            -File $sourceFile `
            -Text ($text + "`n**Superseded by**: ADR-0002`n")

        $file = & $script:Exporter -Path $script:Src
        $html = Get-Content -LiteralPath $file.FullName -Raw

        $html | Should -Match 'href="#adr-0002"'
    }

    It 'rejects a missing supersession target and a self target' {
        $sourceFile = Join-Path $script:Src '0001-sample.md'
        $text = Get-Content -LiteralPath $sourceFile -Raw

        $text = $text.Replace(
            '**Status**: Proposed',
            '**Status**: Superseded'
        )

        foreach ($id in @('9999', '0001')) {
            Write-FixtureText `
                -File $sourceFile `
                -Text ($text + "`n**Superseded by**: ADR-$id`n")

            {
                $null = & $script:Exporter -Path $script:Src
            } | Should -Throw
        }
    }

    It 'shows all four status counts in the page' {
        $names = @(
            '0002-two.md'
            '0003-three.md'
            '0004-four.md'
        )

        $statuses = @(
            'Accepted'
            'Rejected'
            'Superseded'
        )

        for ($index = 0; $index -lt $names.Count; $index++) {
            New-Fixture `
                -Dir $script:Src `
                -Name $names[$index]

            $filePath = Join-Path $script:Src $names[$index]
            $text = Get-Content -LiteralPath $filePath -Raw

            $text = $text.Replace(
                '**Status**: Proposed',
                "**Status**: $($statuses[$index])"
            )

            if ($statuses[$index] -eq 'Superseded') {
                $text += "`n**Superseded by**: ADR-0002`n"
            }

            Write-FixtureText -File $filePath -Text $text
        }

        $file = & $script:Exporter `
            -Path $script:Src `
            -Language en

        $html = Get-Content -LiteralPath $file.FullName -Raw

        foreach ($status in @(
            'Proposed'
            'Accepted'
            'Rejected'
            'Superseded'
        )) {
            $pattern = (
                '<b>\s*1\s*</b>\s*' +
                [regex]::Escape($status)
            )

            $html | Should -Match $pattern
        }
    }
}

Describe 'Installer integration' {
    BeforeEach {
        $script:Repo = Join-Path `
            $TestDrive `
            ([guid]::NewGuid().ToString('N'))

        [void][System.IO.Directory]::CreateDirectory($script:Repo)

        Copy-Item `
            -LiteralPath $script:Exporter `
            -Destination (Join-Path $script:Repo 'export-adr.ps1')

        Copy-Item `
            -LiteralPath $script:Installer `
            -Destination (Join-Path $script:Repo 'install-adr-export.ps1')

                $stub = @'
param([string]$Path='docs/decisions',[switch]$New,[switch]$Edit)
Set-StrictMode -Version Latest
if($New){'existing-action'}
'@

        Write-FixtureText `
            -File (Join-Path $script:Repo 'adr.ps1') `
            -Text $stub

        $script:DecisionDirectory = Join-Path `
            $script:Repo `
            'docs/decisions'

        [void][System.IO.Directory]::CreateDirectory(
            $script:DecisionDirectory
        )

        New-Fixture -Dir $script:DecisionDirectory
    }

    It 'installs, backs up, dispatches, and is idempotent' {
        $installerPath = Join-Path `
            $script:Repo `
            'install-adr-export.ps1'

        $adrPath = Join-Path $script:Repo 'adr.ps1'
        $backupPath = "$adrPath.bak"

        $originalHash = (Get-FileHash -LiteralPath $adrPath).Hash

        $null = & $installerPath -RepoRoot $script:Repo

        Test-Path -LiteralPath $backupPath |
            Should -BeTrue

        (Get-FileHash -LiteralPath $backupPath).Hash |
            Should -Be $originalHash

        $output = Join-Path $script:Repo 'site/index.html'

        $file = & $adrPath `
            -ExportHtml `
            -Path $script:DecisionDirectory `
            -OutPath $output

        $file | Should -BeOfType ([System.IO.FileInfo])
        $file.Exists | Should -BeTrue

        $file.FullName |
            Should -Be ([System.IO.Path]::GetFullPath($output))

        # The original action must still work after installation.
        (& $adrPath -New) | Should -Be 'existing-action'

        $installedHash = (Get-FileHash -LiteralPath $adrPath).Hash

        $null = & $installerPath -RepoRoot $script:Repo

        (Get-FileHash -LiteralPath $adrPath).Hash |
            Should -Be $installedHash

        (Get-FileHash -LiteralPath $backupPath).Hash |
            Should -Be $originalHash

        $installedText = Get-Content -LiteralPath $adrPath -Raw

        $markerCount = [regex]::Matches(
            $installedText,
            '(?m)^[ \t]*# BEGIN ADR HTML EXPORT[ \t]*\r?$'
        ).Count

        $markerCount | Should -Be 1
    }

    It 'preserves the file on parameter collision' {
        $adrPath = Join-Path $script:Repo 'adr.ps1'

        Write-FixtureText `
            -File $adrPath `
            -Text "param([switch]`$ExportHtml)`n"

        $originalHash = (Get-FileHash -LiteralPath $adrPath).Hash

        {
            $null = & (
                Join-Path $script:Repo 'install-adr-export.ps1'
            ) -RepoRoot $script:Repo
        } | Should -Throw

        (Get-FileHash -LiteralPath $adrPath).Hash |
            Should -Be $originalHash
    }

    It 'refuses a preexisting backup without changing the source' {
        $adrPath = Join-Path $script:Repo 'adr.ps1'
        $backupPath = "$adrPath.bak"

        Write-FixtureText -File $backupPath -Text 'keep'

        $originalHash = (Get-FileHash -LiteralPath $adrPath).Hash
        $backupHash = (Get-FileHash -LiteralPath $backupPath).Hash

        {
            $null = & (
                Join-Path $script:Repo 'install-adr-export.ps1'
            ) -RepoRoot $script:Repo
        } | Should -Throw

        (Get-FileHash -LiteralPath $adrPath).Hash |
            Should -Be $originalHash

        (Get-FileHash -LiteralPath $backupPath).Hash |
            Should -Be $backupHash
    }
}
}
