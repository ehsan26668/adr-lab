Describe 'ADR edge cases' {
    BeforeAll {
        $script:AdrScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'adr.ps1'
    }

    BeforeEach {
        $script:Dir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Dir) {
            Remove-Item -LiteralPath $script:Dir -Recurse -Force
        }
    }

    It 'normalizes whitespace, punctuation, and case in an English title' {
        & $script:AdrScript -Title '  API / Data: Version 2  ' -Path $script:Dir
        (Test-Path -LiteralPath (Join-Path $script:Dir '0001-api-data-version-2.md')) |
            Should -Be $true
    }

    It 'requires an explicit slug for a mixed Persian and English title' {
        { & $script:AdrScript -Title 'Use سرویس' -Path $script:Dir } |
            Should -Throw
        @(Get-ChildItem -LiteralPath $script:Dir -Filter '*.md').Count |
            Should -Be 0
    }

    It 'rejects malformed explicit slug <Slug>' -TestCases @(
        @{ Slug = '../outside' }
        @{ Slug = 'Bad-Slug' }
        @{ Slug = 'bad_slug' }
        @{ Slug = 'دوست' }
        @{ Slug = '' }
    ) {
        param($Slug)

        { & $script:AdrScript -Title 'Valid Title' -Slug $Slug -Path $script:Dir } |
            Should -Throw

        @(Get-ChildItem -LiteralPath $script:Dir -Filter '*.md').Count |
            Should -Be 0
    }

    It 'rejects an empty title even when a slug is supplied' {
        { & $script:AdrScript -Title '   ' -Slug 'valid-slug' -Path $script:Dir } |
            Should -Throw
    }

    It 'creates a missing nested destination directory' {
        $nested = Join-Path $script:Dir 'nested/decisions'
        & $script:AdrScript -Title 'Nested Path' -Path $nested
        (Test-Path -LiteralPath (Join-Path $nested '0001-nested-path.md')) |
            Should -Be $true
    }

    It 'continues numbering from the highest existing ID despite gaps' {
        Set-Content -LiteralPath (Join-Path $script:Dir '0002-old.md') `
            -Value '# ADR-0002: Old' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $script:Dir '0007-newer.md') `
            -Value '# ADR-0007: Newer' -Encoding utf8NoBOM

        & $script:AdrScript -Title 'Next Decision' -Path $script:Dir
        (Test-Path -LiteralPath (Join-Path $script:Dir '0008-next-decision.md')) |
            Should -Be $true
    }

    It 'does not create a five-digit ADR after ID 9999' {
        Set-Content -LiteralPath (Join-Path $script:Dir '9999-last.md') `
            -Value '# ADR-9999: Last' -Encoding utf8NoBOM

        { & $script:AdrScript -Title 'Too Many' -Path $script:Dir } |
            Should -Throw
        (Test-Path -LiteralPath (Join-Path $script:Dir '10000-too-many.md')) |
            Should -Be $false
    }

    It 'generates the same empty index on repeated runs' {
        & $script:AdrScript -GenerateIndex -Path $script:Dir
        $index = Join-Path $script:Dir 'readme.md'
        $first = Get-Content -LiteralPath $index -Raw -Encoding utf8

        & $script:AdrScript -GenerateIndex -Path $script:Dir
        $second = Get-Content -LiteralPath $index -Raw -Encoding utf8

        $second | Should -BeExactly $first
        $second | Should -Match '\| ID \| Title \| Status \| Last Updated \|'
        $second | Should -Not -Match '\| 0001 \|'
    }

    It 'reads metadata without relying on stale regex matches' {
        Set-Content -LiteralPath (Join-Path $script:Dir '0001-first.md') `
            -Value @('# ADR-0001: First Decision', '**Status**: Accepted') `
            -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $script:Dir '0002-unknown.md') `
            -Value 'No ADR metadata' -Encoding utf8NoBOM

        & $script:AdrScript -GenerateIndex -Path $script:Dir
        $index = Get-Content -LiteralPath (Join-Path $script:Dir 'readme.md') `
            -Raw -Encoding utf8

        $index | Should -Match '\| 0001 \| \[First Decision\]\(0001-first\.md\) \| Accepted \|'
        $index | Should -Match '\| 0002 \| \[Untitled\]\(0002-unknown\.md\) \| Unknown \|'
    }

    It 'writes ADR and index files as UTF-8 without BOM' {
        & $script:AdrScript -Title 'عنوان فارسی' -Slug 'persian-title' -Path $script:Dir
        & $script:AdrScript -GenerateIndex -Path $script:Dir

        foreach ($name in @('0001-persian-title.md', 'readme.md')) {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:Dir $name))
            $bytes.Length | Should -BeGreaterThan 3
            [System.BitConverter]::ToString($bytes, 0, 3) |
                Should -Not -Be 'EF-BB-BF'
        }
    }

    It 'uses docs/decisions relative to the current directory by default' {
        Push-Location $script:Dir
        try {
            & $script:AdrScript -Title 'Default Location'
            (Test-Path -LiteralPath (
                Join-Path $script:Dir 'docs/decisions/0001-default-location.md'
            )) | Should -Be $true
        }
        finally {
            Pop-Location
        }
    }
}
