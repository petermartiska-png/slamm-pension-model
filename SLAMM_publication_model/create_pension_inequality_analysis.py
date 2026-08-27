import argparse
import math
from pathlib import Path

import csv


SAMPLE_WEIGHT = 5
PROGRESS_BYTES = 1_000_000_000


REQUIRED_COLUMNS = {
    "period",
    "retired",
    "retired_early",
    "retired_new",
    "disabled",
    "pension_new",
    "pension_total",
}


def to_float(value):
    if value == "" or value == "nan":
        return math.nan
    return float(value)


def finite(value):
    return math.isfinite(value)


def mean(values):
    valid = [value for value in values if finite(value)]
    if not valid:
        return ""
    return sum(valid) / len(valid)


def percentile(values, pct):
    valid = sorted(value for value in values if finite(value))
    n = len(valid)
    if n == 0:
        return ""
    if n == 1:
        return valid[0]

    rank = (pct / 100.0) * (n - 1)
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return valid[lower]

    weight = rank - lower
    return valid[lower] + ((valid[upper] - valid[lower]) * weight)


def gini(values):
    valid = sorted(value for value in values if finite(value) and value >= 0)
    n = len(valid)
    if n == 0:
        return ""

    total = sum(valid)
    if total <= 0:
        return 0

    ranked_sum = sum((i + 1) * value for i, value in enumerate(valid))
    return ((2.0 * ranked_sum) / (n * total)) - ((n + 1.0) / n)


def inequality_row(period, incomes, income_measure):
    p10 = percentile(incomes, 10)
    p90 = percentile(incomes, 90)
    return {
        "year": period,
        "population": len(incomes) * SAMPLE_WEIGHT,
        "income_measure": income_measure,
        "mean_income": mean(incomes),
        "median_income": percentile(incomes, 50),
        "gini": gini(incomes),
        "p10": p10,
        "p90": p90,
        "p90_p10_ratio": p90 / p10 if finite(p10) and p10 > 0 else "",
    }


def write_csv(path, rows):
    rows = list(rows)
    fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def parse_sample(sample_path):
    """Parse the period-sorted LIAM2 export using only one year's memory."""
    summary_rows = []
    new_retiree_summary_rows = []
    current_period = None
    period_rows = []
    new_period_rows = []
    header_index = None
    lines = 0
    next_progress = PROGRESS_BYTES

    with sample_path.open("r", encoding="utf-8", newline="") as handle:
        while True:
            line = handle.readline()
            if line == "":
                break
            lines += 1

            position = handle.tell()
            if position >= next_progress:
                print(
                    f"  read {position / 1_000_000_000:.1f} GB; kept "
                    f"processing period {current_period}",
                    flush=True,
                )
                next_progress += PROGRESS_BYTES

            line = line.rstrip("\r\n")
            if not line or (len(line) == 4 and line.isdigit()):
                continue

            if line.startswith("id,period,"):
                if header_index is None:
                    columns = line.split(",")
                    header_index = {column: i for i, column in enumerate(columns)}
                    missing = sorted(REQUIRED_COLUMNS.difference(header_index))
                    if missing:
                        raise RuntimeError(f"Required columns are missing from {sample_path}: {', '.join(missing)}")
                continue

            if header_index is None:
                continue

            values = line.split(",")
            period = int(values[header_index["period"]])
            if current_period is None:
                current_period = period
            elif period != current_period:
                if period < current_period:
                    raise RuntimeError("The LIAM2 export is not sorted by period.")
                if period_rows:
                    summary_rows.append(inequality_row(current_period, period_rows, "pension_total"))
                if new_period_rows:
                    new_retiree_summary_rows.append(inequality_row(current_period, new_period_rows, "pension_new"))
                current_period = period
                period_rows = []
                new_period_rows = []

            if values[header_index["retired_new"]] == "True":
                new_income = to_float(values[header_index["pension_new"]])
                if finite(new_income) and new_income > 0:
                    new_period_rows.append(new_income)

            if (
                values[header_index["retired"]] != "True"
                or values[header_index["retired_early"]] == "True"
                or values[header_index["disabled"]] == "True"
            ):
                continue

            income = to_float(values[header_index["pension_total"]])
            if finite(income) and income > 0:
                period_rows.append(income)

    if period_rows:
        summary_rows.append(inequality_row(current_period, period_rows, "pension_total"))
    if new_period_rows:
        new_retiree_summary_rows.append(inequality_row(current_period, new_period_rows, "pension_new"))
    return summary_rows, new_retiree_summary_rows


def build_outputs(output_dir):
    sample_path = output_dir / "simulation_prospective_pens_sample.csv"
    if not sample_path.exists():
        print(f"Pension inequality analysis skipped: {sample_path} was not found.")
        return []

    print(f"Reading pension inequality sample from {sample_path}", flush=True)
    summary_rows, new_retiree_summary_rows = parse_sample(sample_path)

    outputs = [
        (output_dir / "gini_oldage_pensioners_by_period.csv", summary_rows),
        (output_dir / "gini_new_retirees_by_period.csv", new_retiree_summary_rows),
    ]
    for path, rows in outputs:
        write_csv(path, rows)
    return [path for path, _ in outputs]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="OUTPUT_DATA")
    args = parser.parse_args()

    model_dir = Path(__file__).resolve().parent
    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_dir = model_dir / output_dir

    paths = build_outputs(output_dir)
    if paths:
        print("Created pension inequality outputs:")
        for path in paths:
            print(f"  {path}")


if __name__ == "__main__":
    main()
