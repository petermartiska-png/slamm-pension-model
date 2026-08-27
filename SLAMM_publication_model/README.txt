SLAMM PENSION MICROSIMULATION — PUBLICATION MODEL
=================================================

This is the code and non-confidential assumption package for the AWG-aligned
baseline used in the accompanying paper. It covers the workflow from an
authorised 20% Slovak 2021 Population and Housing Census extract through the
retrospective reconstruction and 2022–2070 prospective pension simulation.

No Census records, Social Insurance Agency records, donor-cell lookups, AWG
assumption files, generated HDF5 states, person-level exports, or logs are
included. Exact paper reproduction requires the two author/data inputs described
below.

SOFTWARE
--------
* Windows PowerShell 5.1 or PowerShell 7
* LIAM2 v0.12.0 (main.exe)
* Python 3 (standard library suffices for the core workflow)
* Sufficient disk space for person-level HDF5 and CSV output

Stata is not needed for the public retrospective collapse; the original Stata
logic is reproduced by prepare_retrospective_base.py. Confidential donor-cell
processing remains with the authors.

DATA TO REQUEST
---------------
Request an authorised 20% microdata extract of the 2021 Census from the
Statistical Office of the Slovak Republic and save it as:

  INPUT_DATA\cenzus_2021_sample_20.csv

The comma-separated file must have one person per row and these integer-coded
fields: pohlavie, vzdelanie, isco, trv_pobyt, suc_pobyt, vek, nace,
ekon_status, country_b. Coding must match the research extract and model
classifications. Access, disclosure control, and secure processing remain the
user's responsibility. Never publish or synchronise the completed work folder.

The AWG assumptions used for the paper also cannot be redistributed. Request
the exact paper-version AWG input bundle from the authors. Copy the bundle into
INPUT_DATA while preserving all paths and filenames. The distributed
INPUT_DATA\0_AWG folder is intentionally empty; after the author bundle is
installed it contains the source AWG workbooks. The bundle also supplies the
derived AWG demographic, participation, employment, unemployment, and
macroeconomic CSV tables referenced by the model.

RUNNING THE MODEL
-----------------
1. Obtain and install both required input sets:

   a. the authorised Census extract described above; and
   b. the AWG assumption bundle supplied by the authors.

2. Open PowerShell here and identify LIAM2:

     $env:LIAM2_EXE = 'C:\path\to\liam2\main.exe'

   If scripts are blocked, enable them for this process only:

     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

3. Run the retrospective stage:

     .\run_retrospective.ps1

   This imports the Census with import_cenzus_2021_01.yml, reconstructs 50
   historical years with retrospective_income_03.yml, and collapses the panel
   to INPUT_DATA\simulation_retospective_modified.csv with
   prepare_retrospective_base.py.

4. Confidential donor-cell checkpoint (required for paper consistency):

   Starting pension amounts and components were assigned and calibrated using
   donor cells built from Social Insurance Agency microdata. Those data and
   lookup cells may be sensitive and are deliberately omitted. Send
   simulation_retospective_modified.csv to the authors for secure processing,
   or ask the authors to run this step. Place the returned file at:

     INPUT_DATA\simulation_retospective_calibrated.csv

   Without it, the prospective run cannot reproduce the paper's starting
   pension distribution. No synthetic substitute is silently used.

5. Run the prospective AWG baseline:

     .\run_pension_clean.ps1

   It checks inputs, rebuilds INPUT_DATA\prospective_input.h5, runs 2022–2070,
   and post-processes the main pension outputs.

The convenience command below runs both stages and pauses safely at step 4 if
the author-processed file is absent:

  .\run_all.ps1

OPTIONAL SENSITIVITY SCENARIOS
------------------------------
Run the baseline first, then either:

  .\sensitivity_scenarios\run_pension_lower_fertility.ps1
  .\sensitivity_scenarios\run_pension_constant_retirement_age.ps1

The first applies the AWG lower-fertility path. The second fixes statutory
retirement ages at 2022 values and uses the AWG no-reform labour-market path.

MAIN OUTPUTS
------------
  OUTPUT_DATA\simulation.h5
  OUTPUT_DATA\pension_expenditure_summary.csv
  OUTPUT_DATA\pension_expenditure_summary_labeled.csv
  OUTPUT_DATA\benefit_replacement_detail.csv

Generated person-level files are restricted. Do not publish simulation.h5,
prospective_input.h5, retrospective exports, or files with individual IDs.

MODEL STRUCTURE
---------------
* import_cenzus_2021_01.yml — Census CSV to LIAM2 HDF5
* retrospective_income_03.yml — career/contribution reconstruction
* prepare_retrospective_base.py — non-confidential retrospective collapse
* import_retrospective.yml — author-enriched base to prospective HDF5
* demo_cenzus_2021_01.yml — fertility, mortality, migration, population
* edu_cenzus_2021_01.yml — education transitions
* ea_cenzus_2021_01.yml — economic activity transitions
* empl_cenzus_2021_01.yml — employment and sector allocation
* pension_cenzus_01.yml — integrated prospective pension simulation
* INPUT_DATA — public transition tables plus author-supplied AWG assumptions
* sensitivity_scenarios — sensitivity runners and scenario-specific code
* prepare_awg_stock_year_demography.py — shared demographic-input preparation

The baseline aligns demographic stocks/flows and participation with AWG
assumptions. Its unemployment/matching mechanism does not exactly target the
AWG unemployment series.

PUBLICATION SAFETY CHECK
------------------------
Before sharing a fresh copy, remove generated inputs/outputs and run:

  .\audit_shareable_package.ps1

The scan supplements, but does not replace, disclosure review by the data
owners and paper authors.
