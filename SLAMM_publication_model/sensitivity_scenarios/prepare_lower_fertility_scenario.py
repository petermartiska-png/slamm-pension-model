from __future__ import annotations

import csv
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

SCENARIO_DIR = Path(__file__).resolve().parent
ROOT = SCENARIO_DIR.parent
sys.path.insert(0, str(ROOT))
from prepare_awg_stock_year_demography import shift_wide_flow_table

INPUT = ROOT / "INPUT_DATA"
FERT_WORKBOOK = INPUT / "0_AWG" / "AWG_DEMO" / "FERT_AWG_2023.xlsx"
BASE_FERTILITY = INPUT / "fertility_EUROPOP.csv"
LOWER_FERTILITY = INPUT / "fertility_AWG_2023_lower.csv"
LOWER_FERTILITY_STOCK_YEAR = INPUT / "fertility_AWG_2023_lower_stock_year_aligned.csv"
BASE_DEMO = ROOT / "demo_cenzus_2021_01.yml"
LOWER_DEMO = SCENARIO_DIR / "demo_cenzus_2021_01_lower_fertility.generated.yml"
BASE_MODEL = ROOT / "pension_cenzus_01.yml"
LOWER_MODEL = SCENARIO_DIR / "pension_cenzus_01_lower_fertility.generated.yml"
OUTPUT_DIR = "OUTPUT_DATA_lower_fertility"

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def shared_strings(zf: ZipFile) -> list[str]:
    try:
        root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    return ["".join(t.text or "" for t in item.findall(".//m:t", NS)) for item in root.findall("m:si", NS)]


def sheet_paths(zf: ZipFile) -> dict[str, str]:
    workbook = ET.fromstring(zf.read("xl/workbook.xml"))
    relationships = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    targets = {rel.attrib["Id"]: rel.attrib["Target"] for rel in relationships}
    result: dict[str, str] = {}
    for sheet in workbook.find("m:sheets", NS):
        target = targets[sheet.attrib[f"{{{REL_NS}}}id"]].lstrip("/")
        result[sheet.attrib["name"]] = target if target.startswith("xl/") else "xl/" + target
    return result


def cell_values(zf: ZipFile, path: str, strings: list[str]) -> dict[str, str]:
    root = ET.fromstring(zf.read(path))
    values: dict[str, str] = {}
    for cell in root.findall(".//m:c", NS):
        value = cell.find("m:v", NS)
        if value is None or value.text is None:
            continue
        text = strings[int(value.text)] if cell.attrib.get("t") == "s" else value.text
        values[cell.attrib["r"]] = text
    return values


def extract_lower_fertility() -> None:
    with BASE_FERTILITY.open(newline="", encoding="utf-8-sig") as handle:
        baseline = list(csv.reader(handle))
    baseline_years = [int(value) for value in baseline[1][1:] if value]
    baseline_by_age = {int(row[0]): row for row in baseline[2:] if row and row[0]}

    scenario: dict[tuple[int, int], str] = {}
    with ZipFile(FERT_WORKBOOK) as zf:
        strings = shared_strings(zf)
        paths = sheet_paths(zf)
        for year in range(2022, 2071):
            sheet_name = f"SK_{year}_1"
            cells = cell_values(zf, paths[sheet_name], strings)
            for column_index, age in enumerate(range(14, 51), start=3):
                column = ""
                number = column_index
                while number:
                    number, remainder = divmod(number - 1, 26)
                    column = chr(65 + remainder) + column
                scenario[(age, year)] = cells[f"{column}2"]

    years = baseline_years
    if years != list(range(2019, 2071)):
        raise ValueError(f"Unexpected baseline fertility years: {years[0]}-{years[-1]}")
    rows = [["age", "period", *("" for _ in range(len(years) - 1))], ["", *years]]
    for age in range(14, 51):
        values = []
        for year in years:
            if year <= 2021:
                values.append(baseline_by_age[age][years.index(year) + 1])
            else:
                values.append(scenario[(age, year)])
        rows.append([age, *values])
    with LOWER_FERTILITY.open("w", newline="", encoding="utf-8") as handle:
        csv.writer(handle, lineterminator="\n").writerows(rows)


def generate_configs() -> None:
    demo = BASE_DEMO.read_text(encoding="utf-8")
    old_align = "align='fertility_EUROPOP_stock_year_aligned.csv'"
    new_align = "align='fertility_AWG_2023_lower_stock_year_aligned.csv'"
    if demo.count(old_align) != 1:
        raise ValueError(f"Expected exactly one baseline fertility alignment, found {demo.count(old_align)}")
    LOWER_DEMO.write_text(demo.replace(old_align, new_align), encoding="utf-8")

    model = BASE_MODEL.read_text(encoding="utf-8")
    old_import = "- demo_cenzus_2021_01.yml"
    new_import = "- sensitivity_scenarios/demo_cenzus_2021_01_lower_fertility.generated.yml"
    if model.count(old_import) != 1:
        raise ValueError(f"Expected exactly one demographic import, found {model.count(old_import)}")
    output_pattern = re.compile(r'(?m)^(\s*path:\s*)"OUTPUT_DATA"\s*$')
    model, replacements = output_pattern.subn(rf'\1"{OUTPUT_DIR}"', model)
    if replacements != 1:
        raise ValueError(f"Expected exactly one simulation output path, found {replacements}")
    LOWER_MODEL.write_text(model.replace(old_import, new_import), encoding="utf-8")


def validate() -> None:
    with LOWER_FERTILITY.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    years = [int(value) for value in rows[1][1:]]
    if len(rows) != 39 or years != list(range(2019, 2071)):
        raise ValueError("Generated lower-fertility table has an unexpected shape")
    totals = {year: sum(float(row[years.index(year) + 1]) for row in rows[2:]) for year in (2022, 2030, 2050, 2070)}
    print("Lower-fertility TFR checks: " + ", ".join(f"{year}={value:.6f}" for year, value in totals.items()))
    print(f"Wrote {LOWER_FERTILITY.relative_to(ROOT)}")
    print(f"Wrote {LOWER_DEMO.name}")
    print(f"Wrote {LOWER_MODEL.name}")


if __name__ == "__main__":
    extract_lower_fertility()
    shift_wide_flow_table(LOWER_FERTILITY, LOWER_FERTILITY_STOCK_YEAR)
    generate_configs()
    validate()
