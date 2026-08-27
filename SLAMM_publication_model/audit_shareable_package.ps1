[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modelDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$findings = [System.Collections.Generic.List[string]]::new()

$forbiddenNames = @(
    'simulation_retospective_calibrated.csv',
    'simulation_retospective_modified.csv',
    'simulation_retrospective_test.csv',
    'prospective_input.h5',
    'simulation.h5',
    'cenzus_2021.csv',
    'cenzus_2021_sample_20.csv',
    'cenzus_2021_sample_20.dta',
    'cenzus2021.h5'
)

Get-ChildItem -LiteralPath $modelDir -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($modelDir.Length).TrimStart('\')
    $lower = $_.Name.ToLowerInvariant()
    if ($lower -eq '.gitkeep') { return }
    if ($forbiddenNames -contains $lower) { $findings.Add("forbidden data file: $relative") }
    if ($lower -match '(?i)(^awg_|awg.*\.(xlsx|xlsm)$|europop|slopem_indexed|_awg\.csv$|_awg_no_reform\.csv$)') {
        $findings.Add("AWG assumption file: $relative")
    }
    # Documentation may name the deliberately omitted donor-cell checkpoint.
    # Actual donor data containers and person-level inputs are caught above.
    if ($_.Extension -in @('.h5', '.hdf5', '.dta', '.sav', '.parquet', '.feather')) { $findings.Add("data container: $relative") }
    if ($lower -match '(\.log$|\.bak$|\.pyc$|^error\.log$)') { $findings.Add("temporary/history file: $relative") }
    if ($relative -match '(^|\\)(__pycache__|LIAM2_TMP|MPLCONFIG|OUTPUT_DATA|OUTPUT_publ|\.git)(\\|$)') { $findings.Add("generated directory content: $relative") }
}

$credentialPattern = '(?i)(password\s*[:=]|passwd\s*[:=]|api[_-]?key\s*[:=]|client[_-]?secret\s*[:=]|BEGIN [A-Z ]+PRIVATE KEY)'
Get-ChildItem -LiteralPath $modelDir -Recurse -File -Include *.yml,*.yaml,*.py,*.ps1,*.txt,*.csv | ForEach-Object {
    $match = Select-String -LiteralPath $_.FullName -Pattern $credentialPattern -AllMatches
    if ($match) {
        $relative = $_.FullName.Substring($modelDir.Length).TrimStart('\')
        $findings.Add("credential-like text: $relative")
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object -Unique | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Shareability audit failed with $($findings.Count) finding(s)."
}

Write-Host 'Shareability audit passed: no known sensitive/generated artifacts were found.' -ForegroundColor Green
