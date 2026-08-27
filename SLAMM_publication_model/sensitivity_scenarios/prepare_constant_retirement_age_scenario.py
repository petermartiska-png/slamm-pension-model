from __future__ import annotations

import csv
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile


SCENARIO_DIR = Path(__file__).resolve().parent
ROOT = SCENARIO_DIR.parent
INPUT = ROOT / "INPUT_DATA"
BASE_GLOBAL = INPUT / "globaltable_slopem_indexed_2024.csv"
CONSTANT_GLOBAL = INPUT / "globaltable_slopem_indexed_2024_constant_retirement_age.csv"
NO_REFORM_WORKBOOK = INPUT / "0_AWG" / "AWG Budgetary projections (2024 AR)_no_reform - r - SK.xlsm"
BASE_PARTICIPATION = INPUT / "awg_participation_rates.csv"
NO_REFORM_PARTICIPATION = INPUT / "awg_participation_rates_no_reform.csv"
BASE_EMPLOYMENT = INPUT / "global_5_41_sample_20_awg.csv"
NO_REFORM_EMPLOYMENT = INPUT / "global_5_41_sample_20_awg_no_reform.csv"
BASE_EA = ROOT / "ea_cenzus_2021_01.yml"
CONSTANT_EA = SCENARIO_DIR / "ea_cenzus_2021_01_constant_retirement_age.generated.yml"
BASE_IMPORT = ROOT / "import_retrospective.yml"
CONSTANT_IMPORT = SCENARIO_DIR / "import_retrospective_constant_retirement_age.generated.yml"
BASE_MODEL = ROOT / "pension_cenzus_01.yml"
CONSTANT_MODEL = SCENARIO_DIR / "pension_cenzus_01_constant_retirement_age.generated.yml"
OUTPUT_DIR = "OUTPUT_DATA_constant_retirement_age"
PROSPECTIVE_INPUT = "prospective_input_constant_retirement_age.h5"
ANCHOR_YEAR = 2022
RETIREMENT_AGE_ROWS = (
    "MALE_RA",
    "FEMALE_RA_0",
    "FEMALE_RA_1",
    "FEMALE_RA_2",
    "FEMALE_RA_3_4",
    "FEMALE_RA_5",
)

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def column_name(number: int) -> str:
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(65 + remainder) + result
    return result


def workbook_sheets() -> dict[str, dict[str, str]]:
    with ZipFile(NO_REFORM_WORKBOOK) as zf:
        try:
            root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
            strings = ["".join(t.text or "" for t in item.findall(".//m:t", NS)) for item in root.findall("m:si", NS)]
        except KeyError:
            strings = []
        workbook = ET.fromstring(zf.read("xl/workbook.xml"))
        relationships = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
        targets = {rel.attrib["Id"]: rel.attrib["Target"] for rel in relationships}
        sheets: dict[str, dict[str, str]] = {}
        for sheet in workbook.find("m:sheets", NS):
            name = sheet.attrib["name"]
            if name not in {"PR(M)", "PR(F)", "EM(T)"}:
                continue
            target = targets[sheet.attrib[f"{{{REL_NS}}}id"]].lstrip("/")
            path = target if target.startswith("xl/") else "xl/" + target
            values: dict[str, str] = {}
            for cell in ET.fromstring(zf.read(path)).findall(".//m:c", NS):
                value = cell.find("m:v", NS)
                if value is None or value.text is None:
                    continue
                values[cell.attrib["r"]] = strings[int(value.text)] if cell.attrib.get("t") == "s" else value.text
            sheets[name] = values
    return sheets


def create_no_reform_participation(sheets: dict[str, dict[str, str]]) -> None:
    years = list(range(2022, 2071))
    header = ["PERIOD", *(f"PR_M_{age}" for age in range(15, 75)), *(f"PR_F_{age}" for age in range(15, 75))]
    rows: list[list[object]] = [header]
    for year in years:
        values: list[object] = [year]
        for sheet_name in ("PR(M)", "PR(F)"):
            cells = sheets[sheet_name]
            year_columns = {int(float(value)): ref for ref, value in cells.items() if ref.endswith("5") and value.replace(".", "", 1).isdigit()}
            if year not in year_columns:
                raise ValueError(f"Year {year} not found in {sheet_name}")
            column = re.match(r"[A-Z]+", year_columns[year]).group()
            for age in range(15, 75):
                row = age - 9
                value = float(cells[f"{column}{row}"])
                values.append(value)
        rows.append(values)
    with NO_REFORM_PARTICIPATION.open("w", newline="", encoding="utf-8") as handle:
        csv.writer(handle, lineterminator="\n").writerows(rows)


def create_no_reform_employment(sheets: dict[str, dict[str, str]]) -> dict[int, int]:
    cells = sheets["EM(T)"]
    year_columns = {int(float(value)): re.match(r"[A-Z]+", ref).group() for ref, value in cells.items() if ref.endswith("5") and value.replace(".", "", 1).isdigit()}
    aggregate_row = next(int(re.search(r"\d+", ref).group()) for ref, value in cells.items() if ref.startswith("C") and value == "15_74")
    targets = {year: round(float(cells[f"{year_columns[year]}{aggregate_row}"]) / 5) for year in range(2022, 2071)}

    with BASE_EMPLOYMENT.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.reader(handle))
    years = [int(value) for value in rows[0][1:]]
    for year in range(2022, 2071):
        column = years.index(year) + 1
        current = [int(row[column]) for row in rows[1:]]
        total = sum(current)
        raw = [value * targets[year] / total for value in current]
        rounded = [math.floor(value) for value in raw]
        remainder = targets[year] - sum(rounded)
        order = sorted(range(len(raw)), key=lambda index: (raw[index] - rounded[index], current[index]), reverse=True)
        for index in order[:remainder]:
            rounded[index] += 1
        for row, value in zip(rows[1:], rounded):
            row[column] = str(value)
    with NO_REFORM_EMPLOYMENT.open("w", newline="", encoding="utf-8") as handle:
        csv.writer(handle, lineterminator="\n").writerows(rows)
    return targets


def create_constant_retirement_age_table() -> dict[str, str]:
    with BASE_GLOBAL.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.reader(handle))
    if not rows or rows[0][0] != "PERIOD":
        raise ValueError("The baseline global table does not start with PERIOD")
    years = [int(value) for value in rows[0][1:]]
    if years != list(range(2011, 2071)):
        raise ValueError(f"Unexpected global-table years: {years[0]}-{years[-1]}")
    anchor_column = years.index(ANCHOR_YEAR) + 1
    first_scenario_column = anchor_column
    anchors: dict[str, str] = {}
    found: set[str] = set()
    for row in rows[1:]:
        if row and row[0] in RETIREMENT_AGE_ROWS:
            if len(row) != len(rows[0]):
                raise ValueError(f"Unexpected length for {row[0]}: {len(row)}")
            anchor = row[anchor_column]
            anchors[row[0]] = anchor
            found.add(row[0])
            for column in range(first_scenario_column, len(row)):
                row[column] = anchor
    missing = set(RETIREMENT_AGE_ROWS) - found
    if missing:
        raise ValueError(f"Missing retirement-age rows: {sorted(missing)}")
    with CONSTANT_GLOBAL.open("w", newline="", encoding="utf-8") as handle:
        csv.writer(handle, lineterminator="\n").writerows(rows)
    return anchors


def generate_model_config() -> None:
    ea = BASE_EA.read_text(encoding="utf-8")
    if ea.count("path: awg_participation_rates.csv") != 1:
        raise ValueError("Unexpected AWG participation declaration in economic-activity configuration")
    CONSTANT_EA.write_text(ea.replace("path: awg_participation_rates.csv", "path: awg_participation_rates_no_reform.csv"), encoding="utf-8")

    importer = BASE_IMPORT.read_text(encoding="utf-8")
    importer = importer.replace("output: INPUT_DATA/prospective_input.h5", f"output: INPUT_DATA/{PROSPECTIVE_INPUT}")
    importer = importer.replace("path: INPUT_DATA/global_5_41_sample_20_awg.csv", "path: INPUT_DATA/global_5_41_sample_20_awg_no_reform.csv")
    CONSTANT_IMPORT.write_text(importer, encoding="utf-8")

    model = BASE_MODEL.read_text(encoding="utf-8")
    old_table = "path: globaltable_slopem_indexed_2024.csv"
    new_table = "path: globaltable_slopem_indexed_2024_constant_retirement_age.csv"
    if model.count(old_table) != 1:
        raise ValueError(f"Expected exactly one active baseline global table, found {model.count(old_table)}")
    model = model.replace(old_table, new_table)
    model = model.replace("- ea_cenzus_2021_01.yml", "- sensitivity_scenarios/ea_cenzus_2021_01_constant_retirement_age.generated.yml")
    model = model.replace("path: awg_participation_rates.csv", "path: awg_participation_rates_no_reform.csv")
    model = model.replace('file:   "prospective_input.h5"', f'file:   "{PROSPECTIVE_INPUT}"')
    output_pattern = re.compile(r'(?m)^(\s*path:\s*)"OUTPUT_DATA"\s*$')
    model, replacements = output_pattern.subn(rf'\1"{OUTPUT_DIR}"', model)
    if replacements != 1:
        raise ValueError(f"Expected exactly one simulation output path, found {replacements}")
    CONSTANT_MODEL.write_text(model, encoding="utf-8")


def validate(anchors: dict[str, str], employment_targets: dict[int, int]) -> None:
    with CONSTANT_GLOBAL.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    years = [int(value) for value in rows[0][1:]]
    start = years.index(ANCHOR_YEAR) + 1
    for row in rows[1:]:
        if row and row[0] in RETIREMENT_AGE_ROWS:
            expected = anchors[row[0]]
            if any(value != expected for value in row[start:]):
                raise ValueError(f"Retirement age is not constant for {row[0]}")
    print(f"Retirement ages fixed at their {ANCHOR_YEAR} baseline values:")
    for name in RETIREMENT_AGE_ROWS:
        print(f"  {name}={float(anchors[name]):.6f}")
    with NO_REFORM_EMPLOYMENT.open(newline="", encoding="utf-8") as handle:
        employment_rows = list(csv.reader(handle))
    employment_years = [int(value) for value in employment_rows[0][1:]]
    for year, target in employment_targets.items():
        column = employment_years.index(year) + 1
        if sum(int(row[column]) for row in employment_rows[1:]) != target:
            raise ValueError(f"Employment target mismatch in {year}")
    with NO_REFORM_PARTICIPATION.open(newline="", encoding="utf-8") as handle:
        participation_rows = list(csv.reader(handle))
    if len(participation_rows) != 50 or len(participation_rows[0]) != 121:
        raise ValueError("No-reform participation table has an unexpected shape")
    print(f"Wrote {CONSTANT_GLOBAL.relative_to(ROOT)}")
    print(f"Wrote {NO_REFORM_PARTICIPATION.relative_to(ROOT)}")
    print(f"Wrote {NO_REFORM_EMPLOYMENT.relative_to(ROOT)}")
    print(f"Wrote {CONSTANT_EA.name}")
    print(f"Wrote {CONSTANT_IMPORT.name}")
    print(f"Wrote {CONSTANT_MODEL.name}")


if __name__ == "__main__":
    scenario_sheets = workbook_sheets()
    create_no_reform_participation(scenario_sheets)
    no_reform_employment_targets = create_no_reform_employment(scenario_sheets)
    retirement_age_anchors = create_constant_retirement_age_table()
    generate_model_config()
    validate(retirement_age_anchors, no_reform_employment_targets)
