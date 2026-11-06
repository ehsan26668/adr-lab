Describe "ADR Automation Tool Integration Tests" {
    BeforeAll {
        $script:LabRoot = $PSScriptRoot | Split-Path -Parent
        $script:AdrScript = Join-Path $script:LabRoot 'adr.ps1'
        $script:TestDocDir = Join-Path $script:LabRoot 'docs/test-decisions'
    }

    BeforeEach {
        if (Test-Path -LiteralPath $script:TestDocDir) {
            Remove-Item -LiteralPath $script:TestDocDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:TestDocDir | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:TestDocDir) {
            Remove-Item -LiteralPath $script:TestDocDir -Recurse -Force
        }
    }

    Context "Creating new ADRs" {
        It "creates a new ADR with 4-digit prefix and correct slug" {
            & $script:AdrScript -Title "Use PostgreSQL Database" -Path $script:TestDocDir

            $file = Get-ChildItem -Path $script:TestDocDir -Filter "0001-use-postgresql-database.md"
            $file | Should -Not -BeNullOrEmpty

            $content = Get-Content -LiteralPath $file.FullName -Encoding utf8 -Raw
            $content | Should -Match "# ADR-0001: Use PostgreSQL Database"
            $content | Should -Match "\*\*Status\*\*: Proposed"
        }

        It "handles Persian titles using the explicit -Slug parameter" {
            & $script:AdrScript -Title "استفاده از معماری پیاز" -Slug "use-onion-architecture" -Path $script:TestDocDir

            $file = Get-ChildItem -Path $script:TestDocDir -Filter "0001-use-onion-architecture.md"
            $file | Should -Not -BeNullOrEmpty

            $content = Get-Content -LiteralPath $file.FullName -Encoding utf8 -Raw
            $content | Should -Match "# ADR-0001: استفاده از معماری پیاز"
        }

        It "fails when Persian title is provided without a Slug" {
            { & $script:AdrScript -Title "استفاده از سیستم جدید" -Path $script:TestDocDir } | Should -Throw
        }

        It "increments sequence numbers sequentially" {
            & $script:AdrScript -Title "First Decision" -Path $script:TestDocDir
            & $script:AdrScript -Title "Second Decision" -Path $script:TestDocDir

            Test-Path (Join-Path $script:TestDocDir "0001-first-decision.md") | Should -Be $true
            Test-Path (Join-Path $script:TestDocDir "0002-second-decision.md") | Should -Be $true
        }
    }

    Context "Index Generation" {
        It "generates a valid readme.md index table" {
            & $script:AdrScript -Title "Architecture One" -Slug "arch-one" -Path $script:TestDocDir
            & $script:AdrScript -Title "Architecture Two" -Slug "arch-two" -Path $script:TestDocDir
            & $script:AdrScript -GenerateIndex -Path $script:TestDocDir

            $indexPath = Join-Path $script:TestDocDir "readme.md"
            Test-Path $indexPath | Should -Be $true

            $indexContent = Get-Content -LiteralPath $indexPath -Encoding utf8 -Raw
            $indexContent | Should -Match "\| 0001 \| \[Architecture One\]\(0001-arch-one\.md\) \| Proposed \|"
            $indexContent | Should -Match "\| 0002 \| \[Architecture Two\]\(0002-arch-two\.md\) \| Proposed \|"
        }
    }
}
