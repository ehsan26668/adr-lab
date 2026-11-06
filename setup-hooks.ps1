<#
.SYNOPSIS
    Configures repository Git hooks for adr-lab.
.DESCRIPTION
    Sets core.hooksPath to .githooks so Git automatically executes
    pre-commit and pre-push validations.
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hooksDir = '.githooks'

if ($Uninstall) {
    git config --unset core.hooksPath
    Write-Host "Git hooks uninstalled (core.hooksPath unset)." -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path -Path $hooksDir)) {
    throw "Hooks directory '$hooksDir' was not found."
}

git config core.hooksPath $hooksDir

if ($LASTEXITCODE -eq 0) {
    Write-Host " Git hooks enabled successfully! (core.hooksPath = $hooksDir)" -ForegroundColor Green
    Write-Host "   - pre-commit: verifies ADR status, references, links, and index"
    Write-Host "   - pre-push: runs full Pester test suite"
} else {
    throw "Failed to configure Git hooks via git config."
}
