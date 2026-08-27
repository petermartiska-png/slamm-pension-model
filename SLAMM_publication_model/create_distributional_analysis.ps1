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
    Write-Warning "Distributional analysis skipped: $samplePath was not found."
    return
}

$pythonScript = Join-Path $modelDir "create_distributional_analysis.py"
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath $pythonScript) -and $null -ne $pythonCommand) {
    & $pythonCommand.Source $pythonScript --output-dir $resolvedOutputDir
    if ($LASTEXITCODE -ne 0) {
        throw "Python distributional analysis failed with exit code $LASTEXITCODE."
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

function New-SummaryRow {
    param(
        [int]$Period,
        [string]$Quintile,
        [object[]]$Rows,
        [int]$YearSampleCount,
        [double]$LowPensionThreshold,
        [string]$Sex = ""
    )

    $sampleCount = $Rows.Count
    $populationCount = $sampleCount * 5
    $share = if ($YearSampleCount -gt 0) { $sampleCount / $YearSampleCount } else { "" }
    $pensions = @($Rows | ForEach-Object { $_.pension })
    $replacementRates = @($Rows | ForEach-Object { $_.replacementRate } | Where-Object { (Test-Finite $_) -and $_ -gt 0 })
    $lowPensionCount = @($Rows | Where-Object { (Test-Finite $_.pension) -and $_.pension -lt $LowPensionThreshold }).Count

    $row = [ordered]@{
        year = $Period
        income_quintile = $Quintile
        n = $populationCount
        share = $share
        avg_pomb_raw = Get-Mean @($Rows | ForEach-Object { $_.pombRaw })
        med_pomb_raw = Get-Percentile @($Rows | ForEach-Object { $_.pombRaw }) 50
        avg_pomb_formula = Get-Mean @($Rows | ForEach-Object { $_.pombFormula })
        med_pomb_formula = Get-Percentile @($Rows | ForEach-Object { $_.pombFormula }) 50
        avg_odp_pension = Get-Mean @($Rows | ForEach-Object { $_.odpPension })
        med_odp_pension = Get-Percentile @($Rows | ForEach-Object { $_.odpPension }) 50
        avg_odp = Get-Mean @($Rows | ForEach-Object { $_.odp })
        med_odp = Get-Percentile @($Rows | ForEach-Object { $_.odp }) 50
        avg_pension = Get-Mean $pensions
        med_pension = Get-Percentile $pensions 50
        p10_pension = Get-Percentile $pensions 10
        p25_pension = Get-Percentile $pensions 25
        p75_pension = Get-Percentile $pensions 75
        p90_pension = Get-Percentile $pensions 90
        replacement_rate_n = $replacementRates.Count * 5
        avg_replacement_rate = Get-Mean $replacementRates
        med_replacement_rate = Get-Percentile $replacementRates 50
        p25_replacement_rate = Get-Percentile $replacementRates 25
        p75_replacement_rate = Get-Percentile $replacementRates 75
        low_pension_threshold = $LowPensionThreshold
        low_pension_share = if ($sampleCount -gt 0) { $lowPensionCount / $sampleCount } else { "" }
    }

    if ($Sex -ne "") {
        $withSex = [ordered]@{ year = $row.year; sex = $Sex; income_quintile = $row.income_quintile }
        foreach ($key in $row.Keys) {
            if ($key -notin @("year", "income_quintile")) {
                $withSex[$key] = $row[$key]
            }
        }
        return [pscustomobject]$withSex
    }

    return [pscustomobject]$row
}

function New-StockSummaryRow {
    param(
        [int]$Period,
        [string]$Quintile,
        [object[]]$Rows,
        [int]$YearSampleCount,
        [double]$LowIncomeThreshold,
        [string]$Sex = ""
    )

    $sampleCount = $Rows.Count
    $populationCount = $sampleCount * 5
    $share = if ($YearSampleCount -gt 0) { $sampleCount / $YearSampleCount } else { "" }
    $incomes = @($Rows | ForEach-Object { $_.income })
    $lowIncomeCount = @($Rows | Where-Object { (Test-Finite $_.income) -and $_.income -lt $LowIncomeThreshold }).Count

    $row = [ordered]@{
        year = $Period
        income_quintile = $Quintile
        n = $populationCount
        share = $share
        avg_income = Get-Mean $incomes
        med_income = Get-Percentile $incomes 50
        p10_income = Get-Percentile $incomes 10
        p25_income = Get-Percentile $incomes 25
        p75_income = Get-Percentile $incomes 75
        p90_income = Get-Percentile $incomes 90
        avg_pomb_raw = Get-Mean @($Rows | ForEach-Object { $_.pombRaw })
        med_pomb_raw = Get-Percentile @($Rows | ForEach-Object { $_.pombRaw }) 50
        avg_pomb_formula = Get-Mean @($Rows | ForEach-Object { $_.pombFormula })
        med_pomb_formula = Get-Percentile @($Rows | ForEach-Object { $_.pombFormula }) 50
        avg_odp_pension = Get-Mean @($Rows | ForEach-Object { $_.odpPension })
        med_odp_pension = Get-Percentile @($Rows | ForEach-Object { $_.odpPension }) 50
        avg_odp = Get-Mean @($Rows | ForEach-Object { $_.odp })
        med_odp = Get-Percentile @($Rows | ForEach-Object { $_.odp }) 50
        low_income_threshold = $LowIncomeThreshold
        low_income_share = if ($sampleCount -gt 0) { $lowIncomeCount / $sampleCount } else { "" }
    }

    if ($Sex -ne "") {
        $withSex = [ordered]@{ year = $row.year; sex = $Sex; income_quintile = $row.income_quintile }
        foreach ($key in $row.Keys) {
            if ($key -notin @("year", "income_quintile")) {
                $withSex[$key] = $row[$key]
            }
        }
        return [pscustomobject]$withSex
    }

    return [pscustomobject]$row
}

function Get-QuintileGroups {
    param(
        [object[]]$Rows,
        [string]$SortProperty = "pombRaw"
    )

    $sorted = @($Rows | Sort-Object -Property $SortProperty, id)
    $n = $sorted.Count
    $groups = [ordered]@{
        Q1 = New-Object System.Collections.Generic.List[object]
        Q2 = New-Object System.Collections.Generic.List[object]
        Q3 = New-Object System.Collections.Generic.List[object]
        Q4 = New-Object System.Collections.Generic.List[object]
        Q5 = New-Object System.Collections.Generic.List[object]
    }

    for ($i = 0; $i -lt $n; $i++) {
        $q = [int][math]::Floor(($i * 5) / $n) + 1
        if ($q -gt 5) {
            $q = 5
        }
        $groups["Q$q"].Add($sorted[$i])
    }

    return $groups
}

$rowsByPeriod = @{}
$stockRowsByPeriod = @{}
$headerIndex = $null
$requiredColumns = @(
    "id", "period", "sex", "retired", "retired_early", "retired_new", "disabled",
    "cumulative_omb", "pomb", "odp", "odp_pension", "roky_pomb",
    "pension_new", "pension_total", "replacement_rate"
)

Write-Host "Reading new retirees from $samplePath"

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
    $cumulativeOmb = Convert-ToDoubleOrNaN $values[$headerIndex["cumulative_omb"]]
    $rokyPomb = Convert-ToDoubleOrNaN $values[$headerIndex["roky_pomb"]]
    $rawDenominator = if ((Test-Finite $cumulativeOmb) -and (Test-Finite $rokyPomb)) {
        [math]::Max($rokyPomb, $cumulativeOmb / 3.0)
    }
    else {
        [double]::NaN
    }
    $pombRaw = if ((Test-Finite $rawDenominator) -and $rawDenominator -gt 0) {
        $cumulativeOmb / $rawDenominator
    }
    else {
        0.0
    }

    if ($values[$headerIndex["retired_new"]] -eq "True") {
        $pensionNew = Convert-ToDoubleOrNaN $values[$headerIndex["pension_new"]]
        if ((Test-Finite $pensionNew) -and $pensionNew -gt 0) {
            if (-not $rowsByPeriod.ContainsKey($period)) {
                $rowsByPeriod[$period] = New-Object System.Collections.Generic.List[object]
            }

            $rowsByPeriod[$period].Add([pscustomobject]@{
                id = [long]$values[$headerIndex["id"]]
                period = $period
                sex = $values[$headerIndex["sex"]]
                pombRaw = $pombRaw
                pombFormula = Convert-ToDoubleOrNaN $values[$headerIndex["pomb"]]
                odp = Convert-ToDoubleOrNaN $values[$headerIndex["odp"]]
                odpPension = Convert-ToDoubleOrNaN $values[$headerIndex["odp_pension"]]
                pension = $pensionNew
                replacementRate = Convert-ToDoubleOrNaN $values[$headerIndex["replacement_rate"]]
            })
        }
    }

    if ($values[$headerIndex["retired"]] -eq "True" -and
        $values[$headerIndex["retired_early"]] -ne "True" -and
        $values[$headerIndex["disabled"]] -ne "True") {
        $pensionTotal = Convert-ToDoubleOrNaN $values[$headerIndex["pension_total"]]
        if ((Test-Finite $pensionTotal) -and $pensionTotal -gt 0) {
            if (-not $stockRowsByPeriod.ContainsKey($period)) {
                $stockRowsByPeriod[$period] = New-Object System.Collections.Generic.List[object]
            }

            $stockRowsByPeriod[$period].Add([pscustomobject]@{
                id = [long]$values[$headerIndex["id"]]
                period = $period
                sex = $values[$headerIndex["sex"]]
                income = $pensionTotal
                pombRaw = $pombRaw
                pombFormula = Convert-ToDoubleOrNaN $values[$headerIndex["pomb"]]
                odp = Convert-ToDoubleOrNaN $values[$headerIndex["odp"]]
                odpPension = Convert-ToDoubleOrNaN $values[$headerIndex["odp_pension"]]
            })
        }
    }
}

$summaryRows = New-Object System.Collections.Generic.List[object]
$summarySexRows = New-Object System.Collections.Generic.List[object]
$stockSummaryRows = New-Object System.Collections.Generic.List[object]
$stockSummarySexRows = New-Object System.Collections.Generic.List[object]

foreach ($period in @($rowsByPeriod.Keys | Sort-Object)) {
    $periodRows = $rowsByPeriod[$period].ToArray()
    if ($periodRows.Count -eq 0) {
        continue
    }

    $lowPensionThreshold = 0.6 * (Get-Percentile @($periodRows | ForEach-Object { $_.pension }) 50)
    $groups = Get-QuintileGroups $periodRows

    foreach ($quintile in $groups.Keys) {
        $quintileRows = $groups[$quintile].ToArray()
        if ($quintileRows.Count -eq 0) {
            continue
        }

        $summaryRows.Add((New-SummaryRow -Period $period -Quintile $quintile -Rows $quintileRows -YearSampleCount $periodRows.Count -LowPensionThreshold $lowPensionThreshold))

        foreach ($sex in @("1", "2")) {
            $sexRows = @($quintileRows | Where-Object { $_.sex -eq $sex })
            if ($sexRows.Count -eq 0) {
                continue
            }
            $sexLabel = if ($sex -eq "1") { "male" } else { "female" }
            $summarySexRows.Add((New-SummaryRow -Period $period -Quintile $quintile -Rows $sexRows -YearSampleCount $periodRows.Count -LowPensionThreshold $lowPensionThreshold -Sex $sexLabel))
        }
    }
}

foreach ($period in @($stockRowsByPeriod.Keys | Sort-Object)) {
    $periodRows = $stockRowsByPeriod[$period].ToArray()
    if ($periodRows.Count -eq 0) {
        continue
    }

    $lowIncomeThreshold = 0.6 * (Get-Percentile @($periodRows | ForEach-Object { $_.income }) 50)
    $groups = Get-QuintileGroups -Rows $periodRows -SortProperty "income"

    foreach ($quintile in $groups.Keys) {
        $quintileRows = $groups[$quintile].ToArray()
        if ($quintileRows.Count -eq 0) {
            continue
        }

        $stockSummaryRows.Add((New-StockSummaryRow -Period $period -Quintile $quintile -Rows $quintileRows -YearSampleCount $periodRows.Count -LowIncomeThreshold $lowIncomeThreshold))

        foreach ($sex in @("1", "2")) {
            $sexRows = @($quintileRows | Where-Object { $_.sex -eq $sex })
            if ($sexRows.Count -eq 0) {
                continue
            }
            $sexLabel = if ($sex -eq "1") { "male" } else { "female" }
            $stockSummarySexRows.Add((New-StockSummaryRow -Period $period -Quintile $quintile -Rows $sexRows -YearSampleCount $periodRows.Count -LowIncomeThreshold $lowIncomeThreshold -Sex $sexLabel))
        }
    }
}

$distributionPath = Join-Path $resolvedOutputDir "distribution_new_retirees_by_quintile.csv"
$distributionSexPath = Join-Path $resolvedOutputDir "distribution_new_retirees_by_quintile_sex.csv"
$stockDistributionPath = Join-Path $resolvedOutputDir "distribution_all_oldage_pensioners_by_pension_income_quintile.csv"
$stockDistributionSexPath = Join-Path $resolvedOutputDir "distribution_all_oldage_pensioners_by_pension_income_quintile_sex.csv"

$summaryRows | Export-Csv -LiteralPath $distributionPath -NoTypeInformation -Encoding UTF8
$summarySexRows | Export-Csv -LiteralPath $distributionSexPath -NoTypeInformation -Encoding UTF8
$stockSummaryRows | Export-Csv -LiteralPath $stockDistributionPath -NoTypeInformation -Encoding UTF8
$stockSummarySexRows | Export-Csv -LiteralPath $stockDistributionSexPath -NoTypeInformation -Encoding UTF8

Write-Host "Created distributional analysis outputs:"
Write-Host "  $distributionPath"
Write-Host "  $distributionSexPath"
Write-Host "  $stockDistributionPath"
Write-Host "  $stockDistributionSexPath"
