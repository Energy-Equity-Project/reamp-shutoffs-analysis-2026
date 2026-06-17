# CLAUDE.md — reamp-shutoffs-analysis-2026

## Purpose
Energy burden and affordability analysis for RE-AMP Midwest states using DOE LEAD 2022
data. Produces per-state and per-FPL-bracket counts and percentages of households with
unaffordable energy burdens (>6% of income), plus a US-wide state ranking for national
context.

## Type
Research (consumes cleaned data; does not write to Cleaned_Data/)

## Status
Active — in development (2026-06)

## Data Dependencies
- `../../Cleaned_Data/doe/lead/census_tract-lead-2022-national.parquet` — DOE LEAD 2022
  national parquet (20M+ cohort rows; 50 states + DC + PR; read with `arrow::read_parquet()`)
- See `../../Cleaned_Data/doe/lead/CLEANED.md` for full column schema
- `../../Cleaned_Data/us_census/household_pulse_survey/02-04-2026-pulse-energy-puf-harmonized.csv` —
  Household Pulse Survey harmonized microdata (1,367,012 rows; 2023 weeks 53–63 + 2024 cycles 01–09)
- See `../../Cleaned_Data/us_census/household_pulse_survey/CLEANED.md` for full column schema

## RE-AMP States
MI, OH, IN, IL, WI, MN, IA, ND, SD, KS (10 Midwest states)

## Methodology
- **Affordability threshold**: energy burden > 6% of income (DOE standard)
- **Aggregation unit**: census tract × FPL bracket (`state`, `fip`, `fpl150`) — avoids
  double-counting across the tenure/fuel cohort dimensions (`ten_ybl6`, `ten_bld`, `ten_hfl`)
- **Burden calculation**: aggregate-ratio method — pool `*_x_units` / `*_valid_units`
  within each tract×FPL group, then compute energy_cost / income
- **Zero-fuel rule**: if a fuel's `*_valid_units` sums to 0, that cost = 0 (not NA)
- **Drop rule**: if income `*_valid_units` = 0 or computed income ≤ 0, drop the group
  and track dropped households as a coverage figure
- **Costs are annual** (no ×12 needed; DOE LEAD stores annualized values)
- **Energy insecurity metrics**: three self-reported measures from HPS — forgo basic needs
  (`energy`), unsafe temperature (`hse_temp`), unable to pay bill (`enrgy_bill`) — plus a
  union measure (`energy_insecure`) = any of the three; computed from 2024 Phase 4 cycles only
- **YES / NO / NA coding**: YES = `almost_every_month | some_months | 1_or_2_months`;
  NO = `never`; NA = item non-response, excluded from denominator
- **Equal-cycle averaging**: per-cycle pct and yes_wt each averaged with equal weight across
  the 9 cycles of 2024; `pct_*` and `n_*` are independent averages, not algebraically linked
- **Union computation**: `insecure` flag set at the respondent level (person-level OR) so the
  union is a proper logical union, not a sum of marginals

## Key Files
- `R/01_load_lead_data.R` — reads parquet (selected columns only), drops FIPS 72 (PR),
  joins FIPS→state abbreviation crosswalk, sets `fpl150` as ordered factor; caches to `temp/`
- `R/02_calculate_energy_burden.R` — core analysis: tract×FPL aggregation, burden
  computation, affordable/unaffordable classification, state and FPL-per-state summaries,
  US rankings; writes three output CSVs
- `R/03_visualize_burden.R` — ggplot2 charts for presentation
- `R/04_load_pulse_data.R` — reads HPS harmonized microdata, filters to 2024, selects 7
  columns, validates cycle/state counts; caches to `temp/pulse_2024_slim.rds`
- `R/05_calculate_energy_insecurity.R` — builds respondent-level YES flags and union,
  computes per-cycle weighted counts, equal-cycle averages, state rankings; writes two CSVs

## Outputs (outputs/, dd-mm-yyyy prefix)
- `17-06-2026-reamp-state-energy-burden-summary.csv` — RE-AMP states, state-level metrics
- `17-06-2026-reamp-fpl-energy-burden-summary.csv` — RE-AMP states × FPL bracket
- `17-06-2026-us-state-burden-rankings.csv` — all 51 jurisdictions ranked by % unaffordable
- `{date}-reamp-energy-insecurity-summary.csv` — RE-AMP states: pct_* and n_* for all four insecurity metrics
- `{date}-us-energy-insecurity-rankings.csv` — all 51 jurisdictions: pct_*, n_*, rank_* for all four metrics

## Reference Scripts
- `../../Internal/data-pipelines/eep-pipeline-core/processors/doe-lead_processor.R`
- `../../External/sierra-club-co-shutoffs-analysis-2026/R/03_energy_burden.R`
- `../../External/brief-johnson-mi-house-insecurity-affordability-2025/R/05_energy_burden_analysis.R`
