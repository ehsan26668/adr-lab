Describe 'ADR link and reference validation tests' {
    BeforeAll {
        $script:LabRoot = Split-Path $PSScriptRoot -Parent
        $script:AdrScript = Join-Path $script:LabRoot 'adr.ps1'
    }

    BeforeEach {
        $script:TestDocDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestDocDir | Out-Null
    }

    Context 'Valid ADR repository state' {
        It 'passes on an empty directory without errors' {
            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Not -Throw
        }

        It 'passes when ADRs have valid status transitions and supersession links' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            & $script:AdrScript -SetStatus -Id 1 -Status Accepted -Path $script:TestDocDir | Out-Null

            & $script:AdrScript -Title 'Second Decision' -Slug 'second-decision' -Path $script:TestDocDir | Out-Null
            & $script:AdrScript -SetStatus -Id 2 -Status Accepted -Path $script:TestDocDir | Out-Null

            & $script:AdrScript -SetStatus -Id 1 -Status Superseded -SupersededBy 2 -Path $script:TestDocDir | Out-Null

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Not -Throw
        }

        It 'passes when valid markdown links reference existing ADR files' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            & $script:AdrScript -Title 'Second Decision' -Slug 'second-decision' -Path $script:TestDocDir | Out-Null

            $secondAdrPath = Join-Path $script:TestDocDir '0002-second-decision.md'
            $content = Get-Content -LiteralPath $secondAdrPath -Raw
            $content += "`n## Related`nSee also [ADR-0001](./0001-first-decision.md) and [Anchor Link](0001-first-decision.md#context).`n"
            [System.IO.File]::WriteAllText($secondAdrPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Not -Throw
        }

        It 'ignores external HTTP/HTTPS links and mailto schemes' {
            & $script:AdrScript -Title 'External Links Decision' -Slug 'external-links' -Path $script:TestDocDir | Out-Null
            $adrPath = Join-Path $script:TestDocDir '0001-external-links.md'
            $content = Get-Content -LiteralPath $adrPath -Raw
            $content += "`n## Docs`nCheck [RFC](https://example.com/spec.md) and [Feedback](mailto:team@example.com).`n"
            [System.IO.File]::WriteAllText($adrPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Not -Throw
        }

        It 'ignores broken link patterns inside fenced code blocks and inline code spans' {
            & $script:AdrScript -Title 'Code Examples Decision' -Slug 'code-examples' -Path $script:TestDocDir | Out-Null
            $adrPath = Join-Path $script:TestDocDir '0001-code-examples.md'
            $content = Get-Content -LiteralPath $adrPath -Raw

            $bt = [string][char]96
            $snippet = "$bt[broken link](9999-missing.md)$bt"
            $fenced = ($bt * 3) + "markdown`n[fake](8888-non-existent.md)`n" + ($bt * 3)
            $tildeFence = ('~' * 3) + "markdown`n[another-fake](7777-non-existent.md)`n" + ('~' * 3)

            $content += "`nHere is an inline snippet: $snippet.`n`n$fenced`n`n$tildeFence`n"
            [System.IO.File]::WriteAllText($adrPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Not -Throw
        }
    }

    Context 'Invalid supersession references' {
        It 'throws when a superseded ADR references a non-existent target' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            & $script:AdrScript -SetStatus -Id 1 -Status Accepted -Path $script:TestDocDir | Out-Null

            $filePath = Join-Path $script:TestDocDir '0001-first-decision.md'
            $content = Get-Content -LiteralPath $filePath -Raw
            $content = $content -replace '(?m)^\*\*Status\*\*: Accepted', "**Status**: Superseded`n**Superseded by**: ADR-9999"
            [System.IO.File]::WriteAllText($filePath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Throw -ExpectedMessage '*فایل هدف جایگزینی ADR-9999 وجود ندارد*'
        }

        It 'throws when target of Superseded by is in Proposed status' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            & $script:AdrScript -Title 'Second Decision' -Slug 'second-decision' -Path $script:TestDocDir | Out-Null

            $firstPath = Join-Path $script:TestDocDir '0001-first-decision.md'
            $content = Get-Content -LiteralPath $firstPath -Raw
            $content = $content -replace '(?m)^\*\*Status\*\*: Proposed', "**Status**: Superseded`n**Superseded by**: ADR-0002"
            [System.IO.File]::WriteAllText($firstPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Throw -ExpectedMessage '*باید Accepted یا Superseded باشد*'
        }

        It 'throws when target replacement ID is smaller than or equal to current ADR ID' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            & $script:AdrScript -Title 'Second Decision' -Slug 'second-decision' -Path $script:TestDocDir | Out-Null

            $secondPath = Join-Path $script:TestDocDir '0002-second-decision.md'
            $content = Get-Content -LiteralPath $secondPath -Raw
            $content = $content -replace '(?m)^\*\*Status\*\*: Proposed', "**Status**: Superseded`n**Superseded by**: ADR-0001"
            [System.IO.File]::WriteAllText($secondPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Throw -ExpectedMessage '*شناسهٔ ADR جایگزین باید بزرگ‌تر از*'
        }

        It 'throws when a non-superseded ADR has a Superseded by header' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            $firstPath = Join-Path $script:TestDocDir '0001-first-decision.md'
            $content = Get-Content -LiteralPath $firstPath -Raw
            $content = $content -replace '(?m)^\*\*Status\*\*: Proposed', "**Status**: Accepted`n**Superseded by**: ADR-0002"
            [System.IO.File]::WriteAllText($firstPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Throw -ExpectedMessage '*خط Superseded by فقط برای وضعیت Superseded مجاز است*'
        }
    }

    Context 'Broken Markdown file links' {
        It 'throws when an inline relative markdown link points to a non-existent file' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            $adrPath = Join-Path $script:TestDocDir '0001-first-decision.md'
            $content = Get-Content -LiteralPath $adrPath -Raw
            $content += "`n[Broken Link](./0005-missing-file.md)`n"
            [System.IO.File]::WriteAllText($adrPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Throw -ExpectedMessage "*لینک شکسته './0005-missing-file.md'*"
        }

        It 'throws when a reference-style markdown link target does not exist' {
            & $script:AdrScript -Title 'First Decision' -Slug 'first-decision' -Path $script:TestDocDir | Out-Null
            $adrPath = Join-Path $script:TestDocDir '0001-first-decision.md'
            $content = Get-Content -LiteralPath $adrPath -Raw
            $content += "`nSee [this decision][ref-decision]`n`n[ref-decision]: 0009-ghost.md`n"
            [System.IO.File]::WriteAllText($adrPath, $content, [System.Text.UTF8Encoding]::new($false))

            {
                & $script:AdrScript -VerifyLinks -Path $script:TestDocDir
            } | Should -Throw -ExpectedMessage "*لینک شکسته '0009-ghost.md'*"
        }
    }

    Context 'Folder and Path Edge Cases' {
        It 'throws when target directory does not exist' {
            $missingPath = Join-Path $TestDrive 'non-existent-folder'
            {
                & $script:AdrScript -VerifyLinks -Path $missingPath
            } | Should -Throw -ExpectedMessage '*پوشهٔ ADR وجود ندارد*'
        }
    }
}
