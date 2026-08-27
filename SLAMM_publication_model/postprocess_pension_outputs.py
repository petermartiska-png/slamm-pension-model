"""Make scenario pension CSV reports structurally identical to the baseline reports."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def read_rows(path: Path, delimiter: str = ",") -> list[list[str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.reader(handle, delimiter=delimiter))


def write_rows(path: Path, rows: list[list[str]], delimiter: str = ",") -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        csv.writer(handle, delimiter=delimiter, quoting=csv.QUOTE_ALL).writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--baseline-dir", default=Path("OUTPUT_DATA"), type=Path)
    args = parser.parse_args()

    output_dir = args.output_dir.resolve()
    baseline_dir = args.baseline_dir.resolve()

    raw_summary = output_dir / "pension_expenditure_summary.csv"
    labeled_summary = output_dir / "pension_expenditure_summary_labeled.csv"
    formatted_summary = output_dir / "pension_expenditure_summary_formatted.csv"
    benefit_detail = output_dir / "benefit_replacement_detail.csv"

    summary_schema = read_rows(baseline_dir / "pension_expenditure_summary_labeled.csv")[0]
    benefit_schema = read_rows(baseline_dir / "benefit_replacement_detail.csv")[0]
    baseline_formatted = read_rows(
        baseline_dir / "pension_expenditure_summary_formatted.csv", delimiter=";"
    )

    metadata: list[list[str]] = []
    seen: set[tuple[str, str, str]] = set()
    for row in baseline_formatted[1:]:
        key = (row[1], row[2], row[3])
        if key not in seen:
            seen.add(key)
            metadata.append([row[1], row[2], row[3]])

    if len(metadata) != len(summary_schema) - 1:
        raise ValueError("Baseline formatted metadata does not match the summary schema")

    summary_rows = read_rows(raw_summary)
    if summary_rows and summary_rows[0] == summary_schema:
        summary_data = summary_rows[1:]
    else:
        summary_data = summary_rows
    if any(len(row) != len(summary_schema) for row in summary_data):
        raise ValueError(f"Unexpected column count in {raw_summary}")

    write_rows(labeled_summary, [summary_schema, *summary_data])
    formatted_rows = [["period", "category", "measure", "unit", "value"]]
    for row in summary_data:
        for value, meta in zip(row[1:], metadata):
            formatted_rows.append([row[0], *meta, value])
    write_rows(formatted_summary, formatted_rows, delimiter=";")

    benefit_rows = read_rows(benefit_detail)
    if not benefit_rows or benefit_rows[0] != benefit_schema:
        if any(len(row) != len(benefit_schema) for row in benefit_rows):
            raise ValueError(f"Unexpected column count in {benefit_detail}")
        write_rows(benefit_detail, [benefit_schema, *benefit_rows])

    print(f"Post-processed pension reports in {output_dir}")


if __name__ == "__main__":
    main()
