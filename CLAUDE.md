# CLAUDE.md — reamp-shutoffs-analysis-2026

## Purpose
Energy burden, energy insecurity, utility shutoff, and utility profits analysis for RE-AMP
Midwest states. Produces per-state and per-FPL-bracket energy burden metrics (DOE LEAD),
self-reported energy insecurity rates (Household Pulse Survey), state-level shutoff counts,
rates, and US-wide rankings (EIA Form 112), and utility-level profit metrics and rankings
(EPI, 2021–2025).

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
- `../../Cleaned_Data/eia/112/20-04-2026-eia-112-shutoffs.csv` — EIA Form 112 state-level
  monthly shutoffs, 2024 (51 jurisdictions × 12 months; first federal residential
  disconnections survey)
- See `../../Cleaned_Data/eia/112/CLEANED.md` for full column schema
- `../../Data/epi/2021 - 2025 Utility Profits (Make a copy to edit) _ Last Updated 5_8_26.xlsx`
  (sheet `"Data"`) — EPI utility profits workbook; 110 US utilities; wide format with
  2021–2025 profit ($ millions) and profit portion of bill (%); read from raw `Data/`
  (no cleaned version; no `SOURCE.md` currently exists for `Data/epi/`)

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
- **Shutoff rates**: sum of 12 monthly per-customer rates (cumulative annual incidence);
  combined rates use `electric_customers` as denominator (proxy for total households);
  `pct_not_reconnected` = share of shutoffs not reversed by a reconnection (higher = worse);
  quality flags (`Q`/`R`) surfaced via `any_quality_flag` (Georgia gas, Texas elec notices)

## Key Files
- `R/01_load_lead_data.R` — reads parquet (selected columns only), drops FIPS 72 (PR),
  joins FIPS→state abbreviation crosswalk, sets `fpl150` as ordered factor; caches to `temp/`
- `R/02_calculate_energy_burden.R` — core analysis: tract×FPL aggregation, burden
  computation, affordable/unaffordable classification, state and FPL-per-state summaries,
  US rankings; writes three output CSVs
- `R/03_visualize_burden.R` — ggplot2 charts for presentation
- `R/08_visualize_burden_slide.R` — slide-ready energy-burden graphics for the pptx deck:
  the "income cliff" descending bar chart (household-weighted % unaffordable by FPL band,
  pooled across the ten states) and the national-context ribbon (ten RE-AMP states placed
  along the full 51-jurisdiction range). No title/subtitle/caption annotations (added in the
  deck). Uses `eeptheme` (`theme_eep_slide`, Inter font); blue is primary, orange is the
  secondary accent for the at-risk focus (severe bands; RE-AMP dots). Writes two high-res
  PNGs (white background, 300 dpi) to `plots/`
- `R/04_load_pulse_data.R` — reads HPS harmonized microdata, filters to 2024, selects 7
  columns, validates cycle/state counts; caches to `temp/pulse_2024_slim.rds`
- `R/05_calculate_energy_insecurity.R` — builds respondent-level YES flags and union,
  computes per-cycle weighted counts, equal-cycle averages, state rankings; writes two CSVs
- `R/06_calculate_shutoffs.R` — reads EIA 112 CSV, crosswalks state names to abbreviations,
  computes monthly rate columns, aggregates to annual counts + cumulative rates, quality-flags
  states, produces RE-AMP summary and US rankings; writes two CSVs
- `R/07_calculate_utility_profits.R` — reads EPI workbook (sheet "Data"), coerces character
  profit columns via `parse_number()`, strips footnote markers, attributes RE-AMP states via
  "any overlap" rule, computes 2021/2025 profit and PoB metrics plus change ratios, produces
  RE-AMP summary (31 utilities) and US rankings (110 utilities); writes two CSVs
- `R/09_visualize_insecurity_slide.R` — slide-ready energy-insecurity graphics (HPS 2024):
  Panel A ranked composite bars (10 RE-AMP states, high→low) and Panel B region-wide
  component hardships on the same x-scale; composed with patchwork. Exports combined figure
  + two standalone PNGs (white background, 300 dpi) to `plots/`
- `R/10_visualize_shutoffs_slide.R` — slide-ready shutoffs graphic (EIA Form 112): split
  ranked bar chart (10 RE-AMP states, high→low) with light "later reconnected" segment from 0
  and dark "not reconnected" segment at the tip; "% not rec." text column on the right;
  asterisks on quality-flagged states (IA, ND, SD). Exports full-width (9.0 × 3.3 in) and
  callout-variant (6.4 × 3.3 in) PNGs (white background, 300 dpi) to `plots/`
- `R/11_visualize_profits_slide.R` — slide-ready utility profits graphic (EPI 2021–2025):
  horizontal ranked bar chart of top 10 RE-AMP IOUs by 2025 profit ($ millions), labeled
  with profit value and a right-side growth-vs-2021 column (dark coral = up, grey = down,
  light grey = no 2021 baseline). Uses deck focus-orange (#E07B39). Exports full-width
  (9.0 × 3.3 in) and callout-variant (6.4 × 3.3 in) PNGs (white background, 300 dpi) to `plots/`

## Outputs (outputs/, dd-mm-yyyy prefix)
- `17-06-2026-reamp-state-energy-burden-summary.csv` — RE-AMP states, state-level metrics
- `17-06-2026-reamp-fpl-energy-burden-summary.csv` — RE-AMP states × FPL bracket
- `17-06-2026-us-state-burden-rankings.csv` — all 51 jurisdictions ranked by % unaffordable
- `{date}-reamp-energy-insecurity-summary.csv` — RE-AMP states: pct_* and n_* for all four insecurity metrics
- `{date}-us-energy-insecurity-rankings.csv` — all 51 jurisdictions: pct_*, n_*, rank_* for all four metrics
- `{date}-reamp-shutoffs-summary.csv` — RE-AMP states: annual counts, cumulative rates, pct_not_reconnected, quality flags
- `{date}-us-shutoffs-rankings.csv` — all 51 jurisdictions: counts + rates + rank_* for all rate metrics, sorted by rank_combined_shutoff_rate
- `{date}-reamp-utility-profits-summary.csv` — 31 RE-AMP utilities: 2021/2025 profit ($ millions) + portion of bill (%), change ratios, reamp_states_served, footnote markers; sorted by profit_2025_millions descending
- `{date}-us-utility-profits-rankings.csv` — all 110 utilities: same metrics + is_reamp flag + rank_profit_2025/2021/change, rank_pob_2025/change; sorted by rank_profit_2025

## Outputs (plots/, dd-mm-yyyy prefix)
- `{date}-reamp-burden-cliff.png` — energy-burden income-cliff bar chart (slide 08); 12 × 3.2 in
- `{date}-reamp-burden-ribbon.png` — national-context ribbon (slide 08); 12 × 1.5 in
- `{date}-reamp-insecurity-figure.png` — combined two-panel insecurity figure (slide 09); 9.2 × 3.3 in
- `{date}-reamp-insecurity-composite.png` — Panel A only (state ranked bars); 5.3 × 3.3 in
- `{date}-reamp-insecurity-components.png` — Panel B only (region-wide components); 3.6 × 3.3 in
- `{date}-reamp-shutoffs-figure.png` — shutoffs split ranked bar chart (slide 10); 9.0 × 3.3 in
- `{date}-reamp-shutoffs-figure-callout.png` — callout variant (narrower, for stat callout column); 6.4 × 3.3 in
- `{date}-reamp-profits-figure.png` — utility profits ranked bar chart (slide 11); 9.0 × 3.3 in
- `{date}-reamp-profits-figure-callout.png` — callout variant (narrower, for stat callout column); 6.4 × 3.3 in

## Reference Scripts
- `../../Internal/data-pipelines/eep-pipeline-core/processors/doe-lead_processor.R`
- `../../External/sierra-club-co-shutoffs-analysis-2026/R/03_energy_burden.R`
- `../../External/brief-johnson-mi-house-insecurity-affordability-2025/R/05_energy_burden_analysis.R`
