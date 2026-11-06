Describe 'Git hooks management and file integrity' {
    BeforeAll {
        $script:LabRoot = Split-Path $PSScriptRoot -Parent
        $script:HooksDir = Join-Path $script:LabRoot '.githooks'
        $script:SetupScript = Join-Path $script:LabRoot 'setup-hooks.ps1'
    }

    Context 'Hook files structure' {
        It 'contains .githooks directory' {
            Test-Path $script:HooksDir | Should -BeTrue
        }

        It 'contains valid pre-commit hook script' {
            $preCommit = Join-Path $script:HooksDir 'pre-commit'
            Test-Path $preCommit | Should -BeTrue
            $content = Get-Content -LiteralPath $preCommit -Raw
            $content | Should -Match 'VerifyLinks'
            $content | Should -Match 'VerifyIndex'
        }

        It 'contains valid pre-push hook script' {
            $prePush = Join-Path $script:HooksDir 'pre-push'
            Test-Path $prePush | Should -BeTrue
            $content = Get-Content -LiteralPath $prePush -Raw
            $content | Should -Match 'Invoke-Pester'
            $content | Should -Match 'FailedCount'
        }
    }

    Context 'setup-hooks script execution' {
        It 'enables and configures git core.hooksPath' {
            & $script:SetupScript
            $currentConfig = git config core.hooksPath
            $currentConfig | Should -Be '.githooks'
        }
    }
}