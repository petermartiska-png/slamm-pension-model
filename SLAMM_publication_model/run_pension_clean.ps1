[CmdletBinding()]
param(
    [string]$Liam2Exe = $env:LIAM2_EXE
)

$ErrorActionPreference = "Stop"

$modelDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputDir = Join-Path $modelDir "INPUT_DATA"

if ([string]::IsNullOrWhiteSpace($Liam2Exe)) {
    $legacyLiam2Path = Join-Path $modelDir "..\..\..\1_LIAM2_v0.12.0\liam2\main.exe"
    if (Test-Path -LiteralPath $legacyLiam2Path) {
        $Liam2Exe = $legacyLiam2Path
    } else {
        throw "LIAM2 was not found. Set `$env:LIAM2_EXE or pass -Liam2Exe. See README.txt."
    }
}
$liam2Exe = (Resolve-Path -LiteralPath $Liam2Exe).Path

# Fail before changing old outputs if the restricted bundle is incomplete.
$requiredInputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[void]$requiredInputs.Add('simulation_retospective_calibrated.csv')
$authorAwgInputs = @(
    'awg_net_migration_5y_sample_20.csv',
    'awg_participation_rates.csv',
    'awg_population_stock_targets_sample_20.csv',
    'awg_unemployment_rates.csv',
    'fertility_EUROPOP.csv',
    'global_5_41_sample_20_awg.csv',
    'globaltable_slopem_indexed_2024.csv',
    'mortality_female_EUROPOP.csv',
    'mortality_male_EUROPOP.csv'
)
$authorAwgInputs | ForEach-Object { [void]$requiredInputs.Add($_) }
$baselineModelFiles = @(
    'import_retrospective.yml', 'pension_cenzus_01.yml',
    'demo_cenzus_2021_01.yml', 'edu_cenzus_2021_01.yml',
    'ea_cenzus_2021_01.yml', 'empl_cenzus_2021_01.yml', 'premenne_dopyt.yml'
)
$baselineModelFiles | ForEach-Object {
    $modelFile = Join-Path $modelDir $_
    Get-Content -LiteralPath $modelFile | Where-Object {
        $_ -notmatch '^\s*#' -and $_ -notmatch '\bfname\s*='
    } | ForEach-Object {
        [regex]::Matches($_, '["'']([^"'']+\.csv)["'']') | ForEach-Object {
            [void]$requiredInputs.Add($_.Groups[1].Value)
        }
    }
}

$generatedDemographyInputs = @(
    'fertility_EUROPOP_stock_year_aligned.csv',
    'mortality_female_EUROPOP_stock_year_aligned.csv',
    'mortality_male_EUROPOP_stock_year_aligned.csv',
    'awg_net_migration_5y_sample_20_stock_year_aligned.csv'
)
$missingInputs = $requiredInputs | Where-Object {
    $_ -notin $generatedDemographyInputs -and
    -not (Test-Path -LiteralPath (Join-Path $inputDir $_))
} | Sort-Object
if ($missingInputs) {
    Write-Host 'The Census/donor and author-supplied AWG bundles are missing required files:' -ForegroundColor Yellow
    $missingInputs | ForEach-Object { Write-Host "  INPUT_DATA\$_" }
    throw "Input preflight failed. Add the authorised files and run again."
}

& python (Join-Path $modelDir "prepare_awg_stock_year_demography.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$tmpDir = Join-Path $modelDir "LIAM2_TMP"
$mplDir = Join-Path $modelDir "MPLCONFIG"

New-Item -ItemType Directory -Force -Path $tmpDir, $mplDir | Out-Null

$env:TMP = (Resolve-Path $tmpDir).Path
$env:TEMP = (Resolve-Path $tmpDir).Path
$env:MPLCONFIGDIR = (Resolve-Path $mplDir).Path

$outputsToDelete = @(
    "INPUT_DATA\prospective_input.h5",
    "OUTPUT_DATA\simulation.h5",
    "OUTPUT_DATA\simulation_prospective_pens_sample.csv",
    "OUTPUT_DATA\pension_expenditure_summary.csv",
    "OUTPUT_DATA\pension_expenditure_summary_labeled.csv",
    "OUTPUT_DATA\pension_expenditure_summary_formatted.csv",
    "OUTPUT_DATA\benefit_replacement_detail.csv",
    "OUTPUT_DATA\distribution_new_retirees_by_quintile.csv",
    "OUTPUT_DATA\distribution_new_retirees_by_quintile_sex.csv",
    "OUTPUT_DATA\distribution_all_oldage_pensioners_by_pension_income_quintile.csv",
    "OUTPUT_DATA\distribution_all_oldage_pensioners_by_pension_income_quintile_sex.csv",
    "OUTPUT_DATA\gini_oldage_pensioners_by_period.csv",
    "OUTPUT_DATA\gini_new_retirees_by_period.csv",
    "OUTPUT_DATA\replacement_dead.csv",
    "OUTPUT_DATA\replacement_leave.csv",
    "OUTPUT_DATA\awg_initial_population_calibration_summary.csv",
    "OUTPUT_DATA\awg_initial_population_calibration_cells.csv",
    "OUTPUT_DATA\student_idem_domov.csv"
)

foreach ($relativePath in $outputsToDelete) {
    $path = Join-Path $modelDir $relativePath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-Host "Deleted old output: $relativePath"
    }
}

Push-Location $modelDir
try {
    & $liam2Exe import import_retrospective.yml
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $liam2Exe run pension_cenzus_01.yml
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $summaryPath = Join-Path $modelDir "OUTPUT_DATA\pension_expenditure_summary.csv"
    if (Test-Path -LiteralPath $summaryPath) {
        $headers = @(
            "period",
            "old_age_and_survivor_pension_expenditure_legacy_pension_annual",
            "total_pension_expenditure_annual",
            "old_age_pension_expenditure_annual",
            "survivor_pension_expenditure_paid_annual",
            "survivor_pension_expenditure_full_annual",
            "overlap_concurrency_reduction_expenditure_annual",
            "survivor_pension_overlap_paid_annual",
            "survivor_pension_standalone_paid_annual",
            "widow_pension_expenditure_paid_annual",
            "widow_pension_overlap_paid_annual",
            "widow_pension_standalone_paid_annual",
            "widower_pension_expenditure_paid_annual",
            "widower_pension_overlap_paid_annual",
            "widower_pension_standalone_paid_annual",
            "early_pension_expenditure_annual",
            "early_oldage_pension_expenditure_annual",
            "disability_pension_expenditure_annual",
            "minimum_pension_benefit_expenditure_annual",
            "material_need_pension_benefit_expenditure_annual",
            "old_age_pension_recipients",
            "early_pension_recipients",
            "disability_pension_recipients",
            "survivor_pension_recipients",
            "widow_pension_recipients",
            "widower_pension_recipients",
            "old_age_survivor_overlap_recipients",
            "survivor_pension_standalone_recipients",
            "widow_pension_overlap_recipients",
            "widow_pension_standalone_recipients",
            "widower_pension_overlap_recipients",
            "widower_pension_standalone_recipients",
            "survivor_pension_stock",
            "new_survivor_pension_awards",
            "new_widow_pension_awards",
            "new_widower_pension_awards",
            "minimum_pension_benefit_recipients",
            "material_need_pension_benefit_recipients",
            "average_legacy_pension_monthly",
            "average_total_pension_monthly",
            "average_old_age_pension_monthly",
            "average_survivor_pension_all_oldage_retirees_monthly",
            "average_survivor_pension_recipients_monthly",
            "average_survivor_full_pension_recipients_monthly",
            "average_widow_pension_recipients_monthly",
            "average_widower_pension_recipients_monthly",
            "average_total_pension_overlap_recipients_monthly",
            "average_oldage_pension_overlap_recipients_monthly",
            "average_survivor_pension_overlap_recipients_monthly",
            "average_survivor_pension_standalone_recipients_monthly",
            "average_widow_pension_overlap_recipients_monthly",
            "average_widow_pension_standalone_recipients_monthly",
            "average_widower_pension_overlap_recipients_monthly",
            "average_widower_pension_standalone_recipients_monthly",
            "average_overlap_concurrency_reduction_monthly",
            "average_early_pension_monthly",
            "average_disability_pension_monthly",
            "average_minimum_pension_benefit_monthly",
            "average_material_need_pension_benefit_monthly",
            "average_replacement_rate_new_oldage_retirees",
            "average_benefit_ratio_oldage_beneficiaries",
            "oldage_insurance_contributions_annual",
            "disability_insurance_contributions_annual",
            "reserve_fund_contributions_annual",
            "pension_relevant_contributions_annual",
            "pillar2_contributions_annual",
            "first_pillar_oldage_contributions_after_pillar2_annual",
            "social_insurance_contributions_annual",
            "employed_count",
            "contributors_count",
            "oldage_pensioners_with_second_pillar_reduction_count",
            "active_second_pillar_contributors_count"
        )

        $labels = [ordered]@{
            old_age_and_survivor_pension_expenditure_legacy_pension_annual = @("Expenditure", "Old-age and survivor pension expenditure - legacy pension variable", "annual amount")
            total_pension_expenditure_annual = @("Expenditure", "Total old-age and survivor pension expenditure", "annual amount")
            old_age_pension_expenditure_annual = @("Expenditure", "Old-age pension expenditure", "annual amount")
            survivor_pension_expenditure_paid_annual = @("Expenditure", "Survivor pension expenditure - paid", "annual amount")
            survivor_pension_expenditure_full_annual = @("Expenditure", "Survivor pension expenditure - full entitlement", "annual amount")
            overlap_concurrency_reduction_expenditure_annual = @("Expenditure", "Old-age/survivor concurrency reduction", "annual amount")
            survivor_pension_overlap_paid_annual = @("Expenditure", "Survivor pension expenditure among old-age overlap recipients - paid", "annual amount")
            survivor_pension_standalone_paid_annual = @("Expenditure", "Standalone survivor pension expenditure - paid", "annual amount")
            widow_pension_expenditure_paid_annual = @("Expenditure", "Widow pension expenditure - paid", "annual amount")
            widow_pension_overlap_paid_annual = @("Expenditure", "Widow pension expenditure among old-age overlap recipients - paid", "annual amount")
            widow_pension_standalone_paid_annual = @("Expenditure", "Standalone widow pension expenditure - paid", "annual amount")
            widower_pension_expenditure_paid_annual = @("Expenditure", "Widower pension expenditure - paid", "annual amount")
            widower_pension_overlap_paid_annual = @("Expenditure", "Widower pension expenditure among old-age overlap recipients - paid", "annual amount")
            widower_pension_standalone_paid_annual = @("Expenditure", "Standalone widower pension expenditure - paid", "annual amount")
            early_pension_expenditure_annual = @("Expenditure", "Early pension expenditure", "annual amount")
            early_oldage_pension_expenditure_annual = @("Expenditure", "Early old-age pension expenditure", "annual amount")
            disability_pension_expenditure_annual = @("Expenditure", "Disability pension expenditure", "annual amount")
            minimum_pension_benefit_expenditure_annual = @("Expenditure", "Minimum pension benefit expenditure", "annual amount")
            material_need_pension_benefit_expenditure_annual = @("Expenditure", "Material need pension benefit expenditure", "annual amount")
            old_age_pension_recipients = @("Recipients", "Old-age pension recipients", "persons")
            early_pension_recipients = @("Recipients", "Early pension recipients", "persons")
            disability_pension_recipients = @("Recipients", "Disability pension recipients", "persons")
            survivor_pension_recipients = @("Recipients", "Survivor pension recipients", "persons")
            widow_pension_recipients = @("Recipients", "Widow pension recipients", "persons")
            widower_pension_recipients = @("Recipients", "Widower pension recipients", "persons")
            old_age_survivor_overlap_recipients = @("Recipients", "Old-age and survivor overlap recipients", "persons")
            survivor_pension_standalone_recipients = @("Recipients", "Standalone survivor pension recipients", "persons")
            widow_pension_overlap_recipients = @("Recipients", "Widow pension recipients with old-age pension overlap", "persons")
            widow_pension_standalone_recipients = @("Recipients", "Standalone widow pension recipients", "persons")
            widower_pension_overlap_recipients = @("Recipients", "Widower pension recipients with old-age pension overlap", "persons")
            widower_pension_standalone_recipients = @("Recipients", "Standalone widower pension recipients", "persons")
            survivor_pension_stock = @("Recipients", "Survivor pension stock after inflow", "persons")
            new_survivor_pension_awards = @("Recipients", "New survivor pension awards", "persons")
            new_widow_pension_awards = @("Recipients", "New widow pension awards", "persons")
            new_widower_pension_awards = @("Recipients", "New widower pension awards", "persons")
            minimum_pension_benefit_recipients = @("Recipients", "Minimum pension benefit recipients", "persons")
            material_need_pension_benefit_recipients = @("Recipients", "Material need pension benefit recipients", "persons")
            average_legacy_pension_monthly = @("Average benefit", "Average legacy pension variable", "monthly amount")
            average_total_pension_monthly = @("Average benefit", "Average total old-age and survivor pension", "monthly amount")
            average_old_age_pension_monthly = @("Average benefit", "Average old-age pension", "monthly amount")
            average_survivor_pension_all_oldage_retirees_monthly = @("Average benefit", "Average survivor pension among all old-age retirees", "monthly amount")
            average_survivor_pension_recipients_monthly = @("Average benefit", "Average survivor pension among survivor recipients", "monthly amount")
            average_survivor_full_pension_recipients_monthly = @("Average benefit", "Average full survivor pension among survivor recipients", "monthly amount")
            average_widow_pension_recipients_monthly = @("Average benefit", "Average widow pension among widow recipients", "monthly amount")
            average_widower_pension_recipients_monthly = @("Average benefit", "Average widower pension among widower recipients", "monthly amount")
            average_total_pension_overlap_recipients_monthly = @("Average benefit", "Average total pension among overlap recipients", "monthly amount")
            average_oldage_pension_overlap_recipients_monthly = @("Average benefit", "Average old-age pension among overlap recipients", "monthly amount")
            average_survivor_pension_overlap_recipients_monthly = @("Average benefit", "Average survivor pension among overlap recipients", "monthly amount")
            average_survivor_pension_standalone_recipients_monthly = @("Average benefit", "Average survivor pension among standalone survivor recipients", "monthly amount")
            average_widow_pension_overlap_recipients_monthly = @("Average benefit", "Average widow pension among old-age overlap recipients", "monthly amount")
            average_widow_pension_standalone_recipients_monthly = @("Average benefit", "Average widow pension among standalone widow recipients", "monthly amount")
            average_widower_pension_overlap_recipients_monthly = @("Average benefit", "Average widower pension among old-age overlap recipients", "monthly amount")
            average_widower_pension_standalone_recipients_monthly = @("Average benefit", "Average widower pension among standalone widower recipients", "monthly amount")
            average_overlap_concurrency_reduction_monthly = @("Average benefit", "Average old-age/survivor concurrency reduction", "monthly amount")
            average_early_pension_monthly = @("Average benefit", "Average early pension", "monthly amount")
            average_disability_pension_monthly = @("Average benefit", "Average disability pension", "monthly amount")
            average_minimum_pension_benefit_monthly = @("Average benefit", "Average minimum pension benefit", "monthly amount")
            average_material_need_pension_benefit_monthly = @("Average benefit", "Average material need pension benefit", "monthly amount")
            average_replacement_rate_new_oldage_retirees = @("Adequacy", "Average replacement rate among new old-age retirees", "ratio")
            average_benefit_ratio_oldage_beneficiaries = @("Adequacy", "Average old-age benefit ratio among old-age beneficiaries", "ratio")
            oldage_insurance_contributions_annual = @("Income", "Old-age insurance contributions - effective collection adjusted", "annual amount")
            disability_insurance_contributions_annual = @("Income", "Disability insurance contributions - effective collection adjusted", "annual amount")
            reserve_fund_contributions_annual = @("Income", "Reserve fund of solidarity contributions - effective collection adjusted", "annual amount")
            pension_relevant_contributions_annual = @("Income", "Pension-relevant contributions before second-pillar subtraction - effective collection adjusted", "annual amount")
            pillar2_contributions_annual = @("Income", "Second-pillar contributions - effective collection adjusted", "annual amount")
            first_pillar_oldage_contributions_after_pillar2_annual = @("Income", "Old-age insurance contributions after second-pillar subtraction - effective collection adjusted", "annual amount")
            social_insurance_contributions_annual = @("Income", "Social insurance contributions - effective collection adjusted", "annual amount")
            employed_count = @("Income", "Employed count", "persons")
            contributors_count = @("Income", "Paying contributors count", "persons")
            oldage_pensioners_with_second_pillar_reduction_count = @("Second pillar", "Old-age pensioners with a first-pillar benefit reduction for second-pillar participation", "persons")
            active_second_pillar_contributors_count = @("Second pillar", "Active workers paying contributions into the second pillar", "persons")
        }

        $summaryData = Import-Csv -LiteralPath $summaryPath -Header $headers
        $summaryData | Export-Csv -LiteralPath (Join-Path $modelDir "OUTPUT_DATA\pension_expenditure_summary_labeled.csv") -NoTypeInformation -Encoding UTF8

        $formattedRows = foreach ($record in $summaryData) {
            foreach ($name in $headers | Select-Object -Skip 1) {
                $meta = $labels[$name]
                [pscustomobject]@{
                    period = $record.period
                    category = $meta[0]
                    measure = $meta[1]
                    unit = $meta[2]
                    value = $record.$name
                }
            }
        }
        $formattedRows | Export-Csv -LiteralPath (Join-Path $modelDir "OUTPUT_DATA\pension_expenditure_summary_formatted.csv") -NoTypeInformation -Delimiter ";" -Encoding UTF8
    }

    $benefitReplacementPath = Join-Path $modelDir "OUTPUT_DATA\benefit_replacement_detail.csv"
    if (Test-Path -LiteralPath $benefitReplacementPath) {
        $benefitReplacementHeaders = @(
            "period",
            "new_oldage_replacement_rate_count_all",
            "new_oldage_replacement_rate_average_all",
            "new_oldage_replacement_rate_count_male",
            "new_oldage_replacement_rate_average_male",
            "new_oldage_replacement_rate_count_female",
            "new_oldage_replacement_rate_average_female",
            "oldage_benefit_ratio_count_all",
            "oldage_benefit_ratio_average_all",
            "oldage_benefit_ratio_count_male",
            "oldage_benefit_ratio_average_male",
            "oldage_benefit_ratio_count_female",
            "oldage_benefit_ratio_average_female",
            "oldage_benefit_ratio_count_age_under65",
            "oldage_benefit_ratio_average_age_under65",
            "oldage_benefit_ratio_count_age_65_69",
            "oldage_benefit_ratio_average_age_65_69",
            "oldage_benefit_ratio_count_age_70_74",
            "oldage_benefit_ratio_average_age_70_74",
            "oldage_benefit_ratio_count_age_75_79",
            "oldage_benefit_ratio_average_age_75_79",
            "oldage_benefit_ratio_count_age_80_84",
            "oldage_benefit_ratio_average_age_80_84",
            "oldage_benefit_ratio_count_age_85plus",
            "oldage_benefit_ratio_average_age_85plus"
        )

        $benefitReplacementData = Import-Csv -LiteralPath $benefitReplacementPath -Header $benefitReplacementHeaders
        $benefitReplacementData | Export-Csv -LiteralPath $benefitReplacementPath -NoTypeInformation -Encoding UTF8
    }

    & (Join-Path $modelDir "create_distributional_analysis.ps1") -OutputDir (Join-Path $modelDir "OUTPUT_DATA")
    & (Join-Path $modelDir "create_pension_inequality_analysis.ps1") -OutputDir (Join-Path $modelDir "OUTPUT_DATA")

}
finally {
    Pop-Location
}
