[CmdletBinding()]
param([string]$Liam2Exe = $env:LIAM2_EXE)

$ErrorActionPreference = "Stop"

$scenarioDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modelDir = Split-Path -Parent $scenarioDir
if (-not (Test-Path -LiteralPath (Join-Path $modelDir 'INPUT_DATA\simulation_retospective_calibrated.csv'))) {
    throw 'Missing restricted input: INPUT_DATA\simulation_retospective_calibrated.csv. See README.txt.'
}
$noReformWorkbook = Join-Path $modelDir 'INPUT_DATA\0_AWG\AWG Budgetary projections (2024 AR)_no_reform - r - SK.xlsm'
if (-not (Test-Path -LiteralPath $noReformWorkbook)) {
    throw 'The author-supplied AWG sensitivity assumption bundle is missing. See README.txt.'
}
if ([string]::IsNullOrWhiteSpace($Liam2Exe)) {
    $Liam2Exe = Join-Path $modelDir "..\..\..\1_LIAM2_v0.12.0\liam2\main.exe"
}
$liam2Exe = (Resolve-Path -LiteralPath $Liam2Exe).Path
$tmpDir = Join-Path $modelDir "LIAM2_TMP"
$mplDir = Join-Path $modelDir "MPLCONFIG"
$outputDir = Join-Path $modelDir "OUTPUT_DATA_constant_retirement_age"

New-Item -ItemType Directory -Force -Path $tmpDir, $mplDir, $outputDir | Out-Null
$env:TMP = (Resolve-Path $tmpDir).Path
$env:TEMP = (Resolve-Path $tmpDir).Path
$env:MPLCONFIGDIR = (Resolve-Path $mplDir).Path

Push-Location $modelDir
try {
    & python (Join-Path $modelDir "prepare_awg_stock_year_demography.py")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & python (Join-Path $scenarioDir "prepare_constant_retirement_age_scenario.py")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $outputsToDelete = @(
        "simulation.h5", "simulation_prospective_pens_sample.csv",
        "pension_expenditure_summary.csv", "pension_expenditure_summary_labeled.csv",
        "pension_expenditure_summary_formatted.csv", "benefit_replacement_detail.csv",
        "replacement_dead.csv", "replacement_leave.csv", "student_idem_domov.csv"
    )
    foreach ($name in $outputsToDelete) {
        $path = Join-Path $outputDir $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }

    $scenarioProspectiveInput = Join-Path $modelDir "INPUT_DATA\prospective_input_constant_retirement_age.h5"
    if (Test-Path -LiteralPath $scenarioProspectiveInput) { Remove-Item -LiteralPath $scenarioProspectiveInput -Force }
    & $liam2Exe import sensitivity_scenarios/import_retrospective_constant_retirement_age.generated.yml
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $liam2Exe run sensitivity_scenarios/pension_cenzus_01_constant_retirement_age.generated.yml
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & python (Join-Path $modelDir "postprocess_pension_outputs.py") --output-dir $outputDir --baseline-dir (Join-Path $modelDir "OUTPUT_DATA")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & (Join-Path $modelDir "create_distributional_analysis.ps1") -OutputDir $outputDir
    & (Join-Path $modelDir "create_pension_inequality_analysis.ps1") -OutputDir $outputDir

}
finally {
    Pop-Location
}
