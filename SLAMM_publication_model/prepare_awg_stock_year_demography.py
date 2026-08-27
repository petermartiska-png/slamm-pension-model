"""Create demographic flow tables aligned to the year of the resulting stock.

AWG flows labelled year t describe the transition from stock t to stock t+1.
SLAMM reports the resulting stock in its current simulation period, so the
table value exposed in period t must come from the AWG flow labelled t-1.
Original source tables are never modified.
"""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "INPUT_DATA"


def shift_wide_flow_table(source: Path, target: Path) -> None:
    with source.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.reader(stream))
    if len(rows) < 3 or len(rows[1]) < 2:
        raise ValueError(f"Unexpected wide demographic table: {source}")
    years = [int(value) for value in rows[1][1:] if value]
    if len(years) != len(rows[1]) - 1:
        raise ValueError(f"Blank or invalid year in {source}")
    source_index = {year: index + 1 for index, year in enumerate(years)}
    shifted = [rows[0], rows[1]]
    for row in rows[2:]:
        if not row:
            shifted.append(row)
            continue
        values = [row[0]]
        for stock_year in years:
            flow_year = stock_year - 1
            if flow_year not in source_index:
                flow_year = stock_year
            values.append(row[source_index[flow_year]])
        shifted.append(values)
    with target.open("w", encoding="utf-8", newline="") as stream:
        csv.writer(stream, lineterminator="\n").writerows(shifted)


def shift_row_flow_table(source: Path, target: Path) -> None:
    with source.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        rows = {int(row["PERIOD"]): row for row in reader}
        fields = reader.fieldnames
    if not fields or "PERIOD" not in fields:
        raise ValueError(f"Missing PERIOD in {source}")
    years = sorted(rows)
    shifted = []
    for stock_year in years:
        flow_year = stock_year - 1 if stock_year - 1 in rows else stock_year
        row = dict(rows[flow_year])
        row["PERIOD"] = str(stock_year)
        shifted.append(row)
    with target.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(shifted)


def main() -> None:
    wide_tables = [
        ("fertility_EUROPOP.csv", "fertility_EUROPOP_stock_year_aligned.csv"),
        ("mortality_male_EUROPOP.csv", "mortality_male_EUROPOP_stock_year_aligned.csv"),
        ("mortality_female_EUROPOP.csv", "mortality_female_EUROPOP_stock_year_aligned.csv"),
    ]
    for source_name, target_name in wide_tables:
        shift_wide_flow_table(INPUT / source_name, INPUT / target_name)
        print(f"Wrote INPUT_DATA/{target_name}")
    shift_row_flow_table(
        INPUT / "awg_net_migration_5y_sample_20.csv",
        INPUT / "awg_net_migration_5y_sample_20_stock_year_aligned.csv",
    )
    print("Wrote INPUT_DATA/awg_net_migration_5y_sample_20_stock_year_aligned.csv")


if __name__ == "__main__":
    main()
