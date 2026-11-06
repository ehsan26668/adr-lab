Describe 'ADR lifecycle integration tests' {
    BeforeAll {
        $script:LabRoot = Split-Path $PSScriptRoot -Parent
        $script:AdrScript = Join-Path $script:LabRoot 'adr.ps1'
    }

    BeforeEach {
        $script:TestDocDir = Join-Path $TestDrive (
            [System.Guid]::NewGuid().ToString('N')
        )

        New-Item -ItemType Directory -Path $script:TestDocDir |
            Out-Null
    }

    Context 'Editing a proposed ADR' {
        It 'changes the title without renaming the file or changing other content' {
            & $script:AdrScript `
                -Title 'Original Decision' `
                -Path $script:TestDocDir |
                Out-Null

            $adrPath = Join-Path $script:TestDocDir (
                '0001-original-decision.md'
            )
            $before = Get-Content -LiteralPath $adrPath -Raw

            & $script:AdrScript `
                -Edit `
                -Id 1 `
                -NewTitle 'Revised Decision' `
                -Path $script:TestDocDir |
                Out-Null

            $after = Get-Content -LiteralPath $adrPath -Raw

            Test-Path -LiteralPath $adrPath |
                Should -BeTrue
            $after |
                Should -Match '(?m)^# ADR-0001: Revised Decision\r?$'
            $after.Replace(
                '# ADR-0001: Revised Decision',
                '# ADR-0001: Original Decision'
            ) |
                Should -Be $before
        }

        It 'returns the file path when no new title is supplied' {
            & $script:AdrScript `
                -Title 'Editable Decision' `
                -Path $script:TestDocDir |
                Out-Null

            $adrPath = Join-Path $script:TestDocDir (
                '0001-editable-decision.md'
            )
            $before = Get-Content -LiteralPath $adrPath -Raw

            $result = & $script:AdrScript `
                -Edit `
                -Id 1 `
                -Path $script:TestDocDir

            $result |
                Should -Be ([System.IO.Path]::GetFullPath($adrPath))
            (Get-Content -LiteralPath $adrPath -Raw) |
                Should -Be $before
        }

        It 'does not edit the title after acceptance' {
            & $script:AdrScript `
                -Title 'Accepted Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            $adrPath = Join-Path $script:TestDocDir (
                '0001-accepted-decision.md'
            )
            $before = Get-Content -LiteralPath $adrPath -Raw

            {
                & $script:AdrScript `
                    -Edit `
                    -Id 1 `
                    -NewTitle 'Changed Too Late' `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw

            (Get-Content -LiteralPath $adrPath -Raw) |
                Should -Be $before
        }
    }

    Context 'Valid status transitions' {
        It 'moves a proposed ADR to Accepted' {
            & $script:AdrScript `
                -Title 'Accept This Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            $adrPath = Join-Path $script:TestDocDir (
                '0001-accept-this-decision.md'
            )

            (Get-Content -LiteralPath $adrPath -Raw) |
                Should -Match '(?m)^\*\*Status\*\*: Accepted\r?$'
        }

        It 'moves a proposed ADR to Rejected' {
            & $script:AdrScript `
                -Title 'Reject This Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Rejected `
                -Path $script:TestDocDir |
                Out-Null

            $adrPath = Join-Path $script:TestDocDir (
                '0001-reject-this-decision.md'
            )

            (Get-Content -LiteralPath $adrPath -Raw) |
                Should -Match '(?m)^\*\*Status\*\*: Rejected\r?$'
        }

        It 'supersedes an accepted ADR with a newer accepted ADR' {
            & $script:AdrScript `
                -Title 'Original Architecture' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -Title 'Replacement Architecture' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 2 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Superseded `
                -SupersededBy 2 `
                -Path $script:TestDocDir |
                Out-Null

            $adrPath = Join-Path $script:TestDocDir (
                '0001-original-architecture.md'
            )
            $content = Get-Content -LiteralPath $adrPath -Raw

            $content |
                Should -Match (
                    '(?m)^\*\*Status\*\*: Superseded\r?\n' +
                    '\*\*Superseded by\*\*: ADR-0002\r?$'
                )

            (
                [regex]::Matches(
                    $content,
                    '(?m)^\*\*Superseded by\*\*:'
                )
            ).Count |
                Should -Be 1
        }
    }

    Context 'Invalid status transitions' {
        It 'does not supersede a proposed ADR directly' {
            & $script:AdrScript `
                -Title 'First Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -Title 'Second Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 2 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Superseded `
                    -SupersededBy 2 `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw
        }

        It 'does not reject an already accepted ADR' {
            & $script:AdrScript `
                -Title 'Accepted Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Rejected `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw
        }

        It 'treats Rejected as a final status' {
            & $script:AdrScript `
                -Title 'Rejected Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Rejected `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Accepted `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw
        }

        It 'treats Superseded as a final status' {
            & $script:AdrScript `
                -Title 'Original Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -Title 'Replacement Decision' `
                -Path $script:TestDocDir |
                Out-Null

            foreach ($id in 1, 2) {
                & $script:AdrScript `
                    -SetStatus `
                    -Id $id `
                    -Status Accepted `
                    -Path $script:TestDocDir |
                    Out-Null
            }

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Superseded `
                -SupersededBy 2 `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Accepted `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw
        }

        It 'requires SupersededBy when superseding an ADR' {
            & $script:AdrScript `
                -Title 'Accepted Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Superseded `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw
        }

        It 'does not supersede an ADR with a proposed replacement' {
            & $script:AdrScript `
                -Title 'Original Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -Title 'Proposed Replacement' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            $adrPath = Join-Path $script:TestDocDir (
                '0001-original-decision.md'
            )
            $before = Get-Content -LiteralPath $adrPath -Raw

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Superseded `
                    -SupersededBy 2 `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw

            (Get-Content -LiteralPath $adrPath -Raw) |
                Should -Be $before
        }

        It 'does not allow an ADR to supersede itself' {
            & $script:AdrScript `
                -Title 'Self Reference' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Superseded `
                    -SupersededBy 1 `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw
        }

        It 'rejects SupersededBy with a different target status' {
            & $script:AdrScript `
                -Title 'First Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -Title 'Second Decision' `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -SetStatus `
                    -Id 1 `
                    -Status Accepted `
                    -SupersededBy 2 `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw
        }
    }

    Context 'Index consistency' {
        It 'detects a stale index after a status change and verifies regeneration' {
            & $script:AdrScript `
                -Title 'Indexed Decision' `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -GenerateIndex `
                -Path $script:TestDocDir |
                Out-Null

            & $script:AdrScript `
                -SetStatus `
                -Id 1 `
                -Status Accepted `
                -Path $script:TestDocDir |
                Out-Null

            $indexPath = Join-Path $script:TestDocDir 'readme.md'
            $staleIndex = Get-Content -LiteralPath $indexPath -Raw

            {
                & $script:AdrScript `
                    -VerifyIndex `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Throw

            (Get-Content -LiteralPath $indexPath -Raw) |
                Should -Be $staleIndex

            & $script:AdrScript `
                -GenerateIndex `
                -Path $script:TestDocDir |
                Out-Null

            {
                & $script:AdrScript `
                    -VerifyIndex `
                    -Path $script:TestDocDir |
                    Out-Null
            } |
                Should -Not -Throw

            (Get-Content -LiteralPath $indexPath -Raw) |
                Should -Match (
                    '\| 0001 \| ' +
                    '\[Indexed Decision\]\(0001-indexed-decision\.md\)' +
                    ' \| Accepted \|'
                )
        }
    }
}
