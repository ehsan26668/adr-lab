#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRoot = Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop
if ($resolvedRoot.Provider.Name -ne 'FileSystem') {
    throw "RepoRoot must be a FileSystem path: '$RepoRoot'"
}
$rootPath = $resolvedRoot.ProviderPath

$adrScript = Join-Path $rootPath 'adr.ps1'
$exporterScript = Join-Path $rootPath 'export-adr.ps1'

if (-not (Test-Path -LiteralPath $adrScript -PathType Leaf)) {
    throw "Target script 'adr.ps1' not found in '$rootPath'."
}

if (-not (Test-Path -LiteralPath $exporterScript -PathType Leaf)) {
    throw "Exporter script 'export-adr.ps1' not found in '$rootPath'."
}

$content = [System.IO.File]::ReadAllText($adrScript, [System.Text.Encoding]::UTF8)

# 1. Idempotency check: if marker already exists, do not touch anything
$beginMarker = '# BEGIN ADR HTML EXPORT'
$endMarker = '# END ADR HTML EXPORT'
if ($content -match [regex]::Escape($beginMarker)) {
    Write-Verbose "ADR HTML export integration is already installed in '$adrScript'."
    return
}

# 2. Parse check on original file
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count -gt 0) {
    throw "adr.ps1 has PowerShell parse errors; refusing edit: $($parseErrors[0].Message)"
}

# 3. Parameter collision check
$hasOutPathParam = $false
if ($null -ne $ast.ParamBlock -and $null -ne $ast.ParamBlock.Parameters) {
    foreach ($p in $ast.ParamBlock.Parameters) {
        $name = $p.Name.VariablePath.UserPath
        if ($name -ieq 'ExportHtml') {
            throw "adr.ps1 already contains an -ExportHtml parameter."
        }
        if ($name -ieq 'OutPath') {
            $hasOutPathParam = $true
        }
    }
}

# 4. Backup safety check
$backupFile = "$adrScript.bak"
if (Test-Path -LiteralPath $backupFile) {
    throw "Backup file '$backupFile' already exists. Refusing to overwrite existing backup."
}

# 5. Inject [switch]$ExportHtml (and [string]$OutPath if not present) into param(...) safely
$paramsToInject = @('[switch]$ExportHtml')
if (-not $hasOutPathParam) {
    $paramsToInject += '[string]$OutPath'
}
$injectedText = $paramsToInject -join ', '

if ($null -ne $ast.ParamBlock) {
    $paramText = $ast.ParamBlock.Extent.Text
    $lastParenIdx = $paramText.LastIndexOf(')')
    if ($lastParenIdx -ge 0) {
        $beforeParen = $paramText.Substring(0, $lastParenIdx).TrimEnd()
        $afterParen = $paramText.Substring($lastParenIdx)

        $separator = if ($beforeParen -match '(?:,|\()\s*$') { '' } else { ', ' }
        $modifiedParamBlock = "$beforeParen$separator$injectedText$afterParen"

        $content = $content.Substring(0, $ast.ParamBlock.Extent.StartOffset) + $modifiedParamBlock + $content.Substring($ast.ParamBlock.Extent.EndOffset)
    } else {
        throw "Could not locate closing parenthesis in param block of adr.ps1."
    }
} else {
    # No param block exists at all
    $content = "param($injectedText)`n" + $content
}

# 6. Inject dispatch logic block at the bottom of the script
$dispatchBlock = @"

$beginMarker
if (`$ExportHtml) {
    `$exporter = Join-Path `$PSScriptRoot 'export-adr.ps1'
    if (-not (Test-Path -LiteralPath `$exporter -PathType Leaf)) {
        throw "export-adr.ps1 was not found alongside adr.ps1 at '`$exporter'."
    }
    `$exportArgs = @{}
    if (`$PSBoundParameters.ContainsKey('Path')) {
        `$exportArgs['Path'] = `$PSBoundParameters['Path']
    }
    if (`$PSBoundParameters.ContainsKey('OutPath')) {
        `$exportArgs['OutPath'] = `$PSBoundParameters['OutPath']
    }
    return (& `$exporter @exportArgs)
}
$endMarker
"@

$newContent = ($content.TrimEnd() + "`n" + $dispatchBlock + "`n") -replace "`r`n", "`n"

# 7. Final sanity check on AST of newly generated code before writing
$newTokens = $null
$newParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($newContent, [ref]$newTokens, [ref]$newParseErrors)
if ($newParseErrors -and $newParseErrors.Count -gt 0) {
    throw "Modified adr.ps1 failed syntax validation: $($newParseErrors[0].Message)"
}

# 8. Create backup and write file atomically as UTF-8 without BOM
[System.IO.File]::Copy($adrScript, $backupFile, $false)
[System.IO.File]::WriteAllText($adrScript, $newContent, [System.Text.UTF8Encoding]::new($false))
Write-Verbose "ADR HTML export integration installed successfully into '$adrScript'."
