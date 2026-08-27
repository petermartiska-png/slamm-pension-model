import argparse
import csv
import math
from pathlib import Path


SAMPLE_WEIGHT = 5
PROGRESS_BYTES = 1_000_000_000


REQUIRED_COLUMNS = {
    "id",
    "period",
    "sex",
    "retired",
    "retired_early",
    "retired_new",
    "disabled",
    "cumulative_omb",
    "pomb",
    "odp",
    "odp_pension",
    "roky_pomb",
    "pension_new",
    "pension_total",
    "replacement_rate",
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


def sex_label(sex):
    return "male" if sex == "1" else "female"


def get_quintile_groups(rows, sort_index):
    sorted_rows = sorted(rows, key=lambda row: (row[sort_index], row[0]))
    groups = {f"Q{i}": [] for i in range(1, 6)}
    n = len(sorted_rows)
    for i, row in enumerate(sorted_rows):
        q = min(math.floor((i * 5) / n) + 1, 5)
        groups[f"Q{q}"].append(row)
    return groups


def new_retiree_summary(period, quintile, rows, year_sample_count, low_threshold, sex=""):
    sample_count = len(rows)
    pensions = [row[6] for row in rows]
    replacement_rates = [row[7] for row in rows if finite(row[7]) and row[7] > 0]
    low_count = sum(1 for value in pensions if finite(value) and value < low_threshold)

    result = {
        "year": period,
        "income_quintile": quintile,
        "n": sample_count * SAMPLE_WEIGHT,
        "share": sample_count / year_sample_count if year_sample_count else "",
        "avg_pomb_raw": mean(row[3] for row in rows),
        "med_pomb_raw": percentile((row[3] for row in rows), 50),
        "avg_pomb_formula": mean(row[4] for row in rows),
        "med_pomb_formula": percentile((row[4] for row in rows), 50),
        "avg_odp_pension": mean(row[8] for row in rows),
        "med_odp_pension": percentile((row[8] for row in rows), 50),
        "avg_odp": mean(row[5] for row in rows),
        "med_odp": percentile((row[5] for row in rows), 50),
        "avg_pension": mean(pensions),
        "med_pension": percentile(pensions, 50),
        "p10_pension": percentile(pensions, 10),
        "p25_pension": percentile(pensions, 25),
        "p75_pension": percentile(pensions, 75),
        "p90_pension": percentile(pensions, 90),
        "replacement_rate_n": len(replacement_rates) * SAMPLE_WEIGHT,
        "avg_replacement_rate": mean(replacement_rates),
        "med_replacement_rate": percentile(replacement_rates, 50),
        "p25_replacement_rate": percentile(replacement_rates, 25),
        "p75_replacement_rate": percentile(replacement_rates, 75),
        "low_pension_threshold": low_threshold,
        "low_pension_share": low_count / sample_count if sample_count else "",
    }

    if sex:
        result = {"year": period, "sex": sex, **{k: v for k, v in result.items() if k != "year"}}
    return result


def stock_summary(period, quintile, rows, year_sample_count, low_threshold, sex=""):
    sample_count = len(rows)
    incomes = [row[3] for row in rows]
    low_count = sum(1 for value in incomes if finite(value) and value < low_threshold)

    result = {
        "year": period,
        "income_quintile": quintile,
        "n": sample_count * SAMPLE_WEIGHT,
        "share": sample_count / year_sample_count if year_sample_count else "",
        "avg_income": mean(incomes),
        "med_income": percentile(incomes, 50),
        "p10_income": percentile(incomes, 10),
        "p25_income": percentile(incomes, 25),
        "p75_income": percentile(incomes, 75),
        "p90_income": percentile(incomes, 90),
        "avg_pomb_raw": mean(row[4] for row in rows),
        "med_pomb_raw": percentile((row[4] for row in rows), 50),
        "avg_pomb_formula": mean(row[5] for row in rows),
        "med_pomb_formula": percentile((row[5] for row in rows), 50),
        "avg_odp_pension": mean(row[7] for row in rows),
        "med_odp_pension": percentile((row[7] for row in rows), 50),
        "avg_odp": mean(row[6] for row in rows),
        "med_odp": percentile((row[6] for row in rows), 50),
        "low_income_threshold": low_threshold,
        "low_income_share": low_count / sample_count if sample_count else "",
    }

    if sex:
        result = {"year": period, "sex": sex, **{k: v for k, v in result.items() if k != "year"}}
    return result


def write_csv(path, rows):
    rows = list(rows)
    if rows:
        fieldnames = list(rows[0].keys())
    else:
        fieldnames = []
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def parse_sample(sample_path, max_rows=None):
    """Parse the period-sorted LIAM2 export using only one year's memory."""
    summary_rows = []
    summary_sex_rows = []
    stock_summary_rows = []
    stock_summary_sex_rows = []
    current_period = None
    period_rows = []
    stock_period_rows = []
    header_index = None
    lines = 0
    next_progress = PROGRESS_BYTES

    def finish_period(period, new_rows, stock_rows):
        if period is None:
            return
        if new_rows:
            low_threshold = 0.6 * percentile((row[6] for row in new_rows), 50)
            groups = get_quintile_groups(new_rows, 3)
            for quintile, quintile_rows in groups.items():
                if not quintile_rows:
                    continue
                summary_rows.append(new_retiree_summary(period, quintile, quintile_rows, len(new_rows), low_threshold))
                for sex in ("1", "2"):
                    sex_rows = [row for row in quintile_rows if row[2] == sex]
                    if sex_rows:
                        summary_sex_rows.append(new_retiree_summary(period, quintile, sex_rows, len(new_rows), low_threshold, sex_label(sex)))
        if stock_rows:
            low_threshold = 0.6 * percentile((row[3] for row in stock_rows), 50)
            groups = get_quintile_groups(stock_rows, 3)
            for quintile, quintile_rows in groups.items():
                if not quintile_rows:
                    continue
                stock_summary_rows.append(stock_summary(period, quintile, quintile_rows, len(stock_rows), low_threshold))
                for sex in ("1", "2"):
                    sex_rows = [row for row in quintile_rows if row[2] == sex]
                    if sex_rows:
                        stock_summary_sex_rows.append(stock_summary(period, quintile, sex_rows, len(stock_rows), low_threshold, sex_label(sex)))

    with sample_path.open("r", encoding="utf-8", newline="") as handle:
        while True:
            line = handle.readline()
            if line == "":
                break
            lines += 1
            if max_rows is not None and lines > max_rows:
                break

            position = handle.tell()
            if position >= next_progress:
                print(f"  read {position / 1_000_000_000:.1f} GB; processing period {current_period}", flush=True)
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
                finish_period(current_period, period_rows, stock_period_rows)
                current_period = period
                period_rows = []
                stock_period_rows = []
            cumulative_omb = to_float(values[header_index["cumulative_omb"]])
            roky_pomb = to_float(values[header_index["roky_pomb"]])
            if finite(cumulative_omb) and finite(roky_pomb):
                raw_denominator = max(roky_pomb, cumulative_omb / 3.0)
            else:
                raw_denominator = math.nan
            pomb_raw = cumulative_omb / raw_denominator if finite(raw_denominator) and raw_denominator > 0 else 0.0

            if values[header_index["retired_new"]] == "True":
                pension_new = to_float(values[header_index["pension_new"]])
                if finite(pension_new) and pension_new > 0:
                    period_rows.append((
                        int(values[header_index["id"]]),
                        period,
                        values[header_index["sex"]],
                        pomb_raw,
                        to_float(values[header_index["pomb"]]),
                        to_float(values[header_index["odp"]]),
                        pension_new,
                        to_float(values[header_index["replacement_rate"]]),
                        to_float(values[header_index["odp_pension"]]),
                    ))

            if (
                values[header_index["retired"]] == "True"
                and values[header_index["retired_early"]] != "True"
                and values[header_index["disabled"]] != "True"
            ):
                pension_total = to_float(values[header_index["pension_total"]])
                if finite(pension_total) and pension_total > 0:
                    stock_period_rows.append((
                        int(values[header_index["id"]]),
                        period,
                        values[header_index["sex"]],
                        pension_total,
                        pomb_raw,
                        to_float(values[header_index["pomb"]]),
                        to_float(values[header_index["odp"]]),
                        to_float(values[header_index["odp_pension"]]),
                    ))

    finish_period(current_period, period_rows, stock_period_rows)
    return summary_rows, summary_sex_rows, stock_summary_rows, stock_summary_sex_rows


def build_outputs(output_dir, max_rows=None):
    sample_path = output_dir / "simulation_prospective_pens_sample.csv"
    if not sample_path.exists():
        print(f"Distributional analysis skipped: {sample_path} was not found.")
        return []

    print(f"Reading distributional-analysis sample from {sample_path}", flush=True)
    summary_rows, summary_sex_rows, stock_summary_rows, stock_summary_sex_rows = parse_sample(
        sample_path, max_rows=max_rows
    )

    outputs = [
        (output_dir / "distribution_new_retirees_by_quintile.csv", summary_rows),
        (output_dir / "distribution_new_retirees_by_quintile_sex.csv", summary_sex_rows),
        (output_dir / "distribution_all_oldage_pensioners_by_pension_income_quintile.csv", stock_summary_rows),
        (output_dir / "distribution_all_oldage_pensioners_by_pension_income_quintile_sex.csv", stock_summary_sex_rows),
    ]
    for path, rows in outputs:
        write_csv(path, rows)
    return [path for path, _ in outputs]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="OUTPUT_DATA")
    parser.add_argument("--max-rows", type=int, default=None, help=argparse.SUPPRESS)
    args = parser.parse_args()

    model_dir = Path(__file__).resolve().parent
    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_dir = model_dir / output_dir

    paths = build_outputs(output_dir, max_rows=args.max_rows)
    if paths:
        print("Created distributional analysis outputs:")
        for path in paths:
            print(f"  {path}")


if __name__ == "__main__":
    main()
