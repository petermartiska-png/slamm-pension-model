[CmdletBinding()]
param([string]$Liam2Exe = $env:LIAM2_EXE)

$ErrorActionPreference = 'Stop'
$modelDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $modelDir 'run_retrospective.ps1') -Liam2Exe $Liam2Exe

$calibrated = Join-Path $modelDir 'INPUT_DATA\simulation_retospective_calibrated.csv'
if (-not (Test-Path -LiteralPath $calibrated)) {
    Write-Warning 'Paused at the confidential donor-cell checkpoint. See README.txt, step 3.'
    exit 2
}
& (Join-Path $modelDir 'run_pension_clean.ps1') -Liam2Exe $Liam2Exe
