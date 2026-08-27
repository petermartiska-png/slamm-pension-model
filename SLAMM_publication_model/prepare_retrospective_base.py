"""Collapse the LIAM2 retrospective panel to a 2021 prospective base file.

This reproduces the non-confidential part of OUTPUT_Stata/Retro_output.do using
only Python's standard library. Pension donor-cell enrichment is deliberately
not performed here; see README.txt.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


TRACKED_MAXIMA = ("cumulative_omb", "roky_pomb", "odp", "rok_priz")


def numeric(value: str) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    with args.input.open("r", encoding="utf-8-sig", newline="") as stream:
        rows = csv.reader(stream)
        header = None
        for candidate in rows:
            normalized = [item.strip().lower() for item in candidate]
            if "id" in normalized and "cumulative_omb" in normalized:
                header = [item.strip() for item in candidate]
                break
        if header is None:
            raise SystemExit("Could not find the LIAM2 CSV header.")

        required = {"id", "period", *TRACKED_MAXIMA}
        missing = required.difference(header)
        if missing:
            raise SystemExit(f"Missing retrospective columns: {sorted(missing)}")

        first: dict[str, dict[str, str]] = {}
        maxima: dict[str, dict[str, float]] = {}
        for values in rows:
            if len(values) != len(header):
                continue
            row = dict(zip(header, values))
            person_id = row["id"].strip()
            period = numeric(row["period"])
            if not person_id or person_id.lower() == "id" or period is None:
                continue
            if person_id not in first or period < (numeric(first[person_id]["period"]) or float("inf")):
                first[person_id] = row
            person_max = maxima.setdefault(person_id, {})
            for field in TRACKED_MAXIMA:
                value = numeric(row[field])
                if field == "rok_priz" and value is not None and value <= 0:
                    value = None
                if value is not None:
                    person_max[field] = max(value, person_max.get(field, value))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output_header = header + (["historical_year"] if "historical_year" not in header else [])
    with args.output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=output_header, extrasaction="ignore")
        writer.writeheader()
        for person_id, row in first.items():
            row.update({key: format(value, ".15g") for key, value in maxima[person_id].items()})
            row["period"] = "2021"
            row["historical_year"] = "2022"
            writer.writerow(row)

    print(f"Wrote {len(first):,} persons to {args.output}")


if __name__ == "__main__":
    main()
