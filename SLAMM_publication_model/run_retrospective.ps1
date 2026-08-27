[CmdletBinding()]
param([string]$Liam2Exe = $env:LIAM2_EXE)

$ErrorActionPreference = 'Stop'
$modelDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $modelDir

if ([string]::IsNullOrWhiteSpace($Liam2Exe) -or -not (Test-Path -LiteralPath $Liam2Exe)) {
    throw 'LIAM2 was not found. Set LIAM2_EXE or pass -Liam2Exe. See README.txt.'
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw 'Python 3 is required for retrospective panel post-processing.'
}
$census = Join-Path $modelDir 'INPUT_DATA\cenzus_2021_sample_20.csv'
if (-not (Test-Path -LiteralPath $census)) {
    throw 'Missing INPUT_DATA\cenzus_2021_sample_20.csv. See README.txt for the required Census schema.'
}
$retrospectiveAwgInputs = @(
    'fertility_EUROPOP.csv',
    'mortality_female_EUROPOP.csv',
    'mortality_male_EUROPOP.csv'
)
$missingAwg = $retrospectiveAwgInputs | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $modelDir "INPUT_DATA\$_"))
}
if ($missingAwg) {
    throw 'The author-supplied AWG assumption bundle is missing. See README.txt.'
}

New-Item -ItemType Directory -Force -Path (Join-Path $modelDir 'OUTPUT_DATA') | Out-Null
& $Liam2Exe import import_cenzus_2021_01.yml
if ($LASTEXITCODE -ne 0) { throw 'Census import failed.' }
& $Liam2Exe run retrospective_income_03.yml
if ($LASTEXITCODE -ne 0) { throw 'Retrospective simulation failed.' }

$panel = Join-Path $modelDir 'OUTPUT_DATA\simulation_retrospective_test.csv'
$base = Join-Path $modelDir 'INPUT_DATA\simulation_retospective_modified.csv'
if (-not (Test-Path -LiteralPath $panel)) { throw "Expected retrospective export was not created: $panel" }
& python (Join-Path $modelDir 'prepare_retrospective_base.py') $panel $base
if ($LASTEXITCODE -ne 0) { throw 'Retrospective panel collapse failed.' }

Write-Host 'Retrospective stage complete.' -ForegroundColor Green
Write-Warning 'The Social Insurance Agency donor-cell enrichment is intentionally omitted. Send the modified base to the authors, then place the returned simulation_retospective_calibrated.csv in INPUT_DATA before the prospective run.'
