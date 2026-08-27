param(
    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "OUTPUT_DATA"
)

$ErrorActionPreference = "Stop"
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = $invariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $invariantCulture
[System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $invariantCulture
[System.Globalization.CultureInfo]::DefaultThreadCurrentUICulture = $invariantCulture

$modelDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
}
else {
    Join-Path $modelDir $OutputDir
}

$samplePath = Join-Path $resolvedOutputDir "simulation_prospective_pens_sample.csv"
if (-not (Test-Path -LiteralPath $samplePath)) {
    Write-Warning "Pension inequality analysis skipped: $samplePath was not found."
    return
}

$pythonScript = Join-Path $modelDir "create_pension_inequality_analysis.py"
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath $pythonScript) -and $null -ne $pythonCommand) {
    & $pythonCommand.Source $pythonScript --output-dir $resolvedOutputDir
    if ($LASTEXITCODE -ne 0) {
        throw "Python pension inequality analysis failed with exit code $LASTEXITCODE."
    }
    return
}

function Convert-ToDoubleOrNaN {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq "nan") {
        return [double]::NaN
    }

    return [double]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-Finite {
    param([double]$Value)

    return -not ([double]::IsNaN($Value) -or [double]::IsInfinity($Value))
}

function Get-Mean {
    param([double[]]$Values)

    $valid = @($Values | Where-Object { Test-Finite $_ })
    if ($valid.Count -eq 0) {
        return ""
    }

    return ($valid | Measure-Object -Average).Average
}

function Get-Percentile {
    param(
        [double[]]$Values,
        [double]$Percentile
    )

    $valid = @($Values | Where-Object { Test-Finite $_ } | Sort-Object)
    $n = $valid.Count
    if ($n -eq 0) {
        return ""
    }
    if ($n -eq 1) {
        return $valid[0]
    }

    $rank = ($Percentile / 100.0) * ($n - 1)
    $lower = [int][math]::Floor($rank)
    $upper = [int][math]::Ceiling($rank)
    if ($lower -eq $upper) {
        return $valid[$lower]
    }

    $weight = $rank - $lower
    return $valid[$lower] + (($valid[$upper] - $valid[$lower]) * $weight)
}

function Get-Gini {
    param([double[]]$Values)

    $valid = @($Values | Where-Object { (Test-Finite $_) -and $_ -ge 0 } | Sort-Object)
    $n = $valid.Count
    if ($n -eq 0) {
        return ""
    }

    $sum = ($valid | Measure-Object -Sum).Sum
    if ($sum -le 0) {
        return 0
    }

    $rankedSum = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $rankedSum += ($i + 1) * $valid[$i]
    }

    return ((2.0 * $rankedSum) / ($n * $sum)) - (($n + 1.0) / $n)
}

function New-InequalityRow {
    param(
        [int]$Period,
        [double[]]$Incomes,
        [string]$IncomeMeasure
    )

    $p10 = Get-Percentile $Incomes 10
    $p90 = Get-Percentile $Incomes 90

    return [pscustomobject][ordered]@{
        year = $Period
        population = $Incomes.Count * 5
        income_measure = $IncomeMeasure
        mean_income = Get-Mean $Incomes
        median_income = Get-Percentile $Incomes 50
        gini = Get-Gini $Incomes
        p10 = $p10
        p90 = $p90
        p90_p10_ratio = if ((Test-Finite $p10) -and $p10 -gt 0) { $p90 / $p10 } else { "" }
    }
}

$rowsByPeriod = @{}
$newRetireeRowsByPeriod = @{}
$headerIndex = $null
$requiredColumns = @(
    "period", "retired", "retired_early", "retired_new", "disabled", "pension_new", "pension_total"
)

Write-Host "Reading old-age pensioner incomes from $samplePath"

foreach ($line in [System.IO.File]::ReadLines($samplePath)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\d{4}$') {
        continue
    }

    if ($line.StartsWith("id,period,")) {
        if ($null -eq $headerIndex) {
            $columns = $line.Split(",")
            $headerIndex = @{}
            for ($i = 0; $i -lt $columns.Count; $i++) {
                $headerIndex[$columns[$i]] = $i
            }
            foreach ($column in $requiredColumns) {
                if (-not $headerIndex.ContainsKey($column)) {
                    throw "Required column '$column' is missing from $samplePath."
                }
            }
        }
        continue
    }

    if ($null -eq $headerIndex) {
        continue
    }

    $values = $line.Split(",")
    $period = [int]$values[$headerIndex["period"]]

    if ($values[$headerIndex["retired_new"]] -eq "True") {
        $newIncome = Convert-ToDoubleOrNaN $values[$headerIndex["pension_new"]]
        if ((Test-Finite $newIncome) -and $newIncome -gt 0) {
            if (-not $newRetireeRowsByPeriod.ContainsKey($period)) {
                $newRetireeRowsByPeriod[$period] = New-Object System.Collections.Generic.List[double]
            }

            $newRetireeRowsByPeriod[$period].Add($newIncome)
        }
    }

    if ($values[$headerIndex["retired"]] -ne "True" -or
        $values[$headerIndex["retired_early"]] -eq "True" -or
        $values[$headerIndex["disabled"]] -eq "True") {
        continue
    }

    $income = Convert-ToDoubleOrNaN $values[$headerIndex["pension_total"]]
    if (-not (Test-Finite $income) -or $income -le 0) {
        continue
    }

    if (-not $rowsByPeriod.ContainsKey($period)) {
        $rowsByPeriod[$period] = New-Object System.Collections.Generic.List[double]
    }

    $rowsByPeriod[$period].Add($income)
}

$summaryRows = foreach ($period in @($rowsByPeriod.Keys | Sort-Object)) {
    $incomes = [double[]]$rowsByPeriod[$period].ToArray()
    New-InequalityRow -Period $period -Incomes $incomes -IncomeMeasure "pension_total"
}

$newRetireeSummaryRows = foreach ($period in @($newRetireeRowsByPeriod.Keys | Sort-Object)) {
    $incomes = [double[]]$newRetireeRowsByPeriod[$period].ToArray()
    New-InequalityRow -Period $period -Incomes $incomes -IncomeMeasure "pension_new"
}

$inequalityPath = Join-Path $resolvedOutputDir "gini_oldage_pensioners_by_period.csv"
$newRetireeInequalityPath = Join-Path $resolvedOutputDir "gini_new_retirees_by_period.csv"
$summaryRows | Export-Csv -LiteralPath $inequalityPath -NoTypeInformation -Encoding UTF8
$newRetireeSummaryRows | Export-Csv -LiteralPath $newRetireeInequalityPath -NoTypeInformation -Encoding UTF8

Write-Host "Created pension inequality output:"
Write-Host "  $inequalityPath"
Write-Host "  $newRetireeInequalityPath"
