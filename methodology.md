# Methodology — reamp-shutoffs-analysis-2026

This document records the analytical methods, formulas, and data provenance behind the
analyses in this repository. The current scope covers the energy affordability analysis
for the ten RE-AMP Midwest states (MI, OH, IN, IL, WI, MN, IA, ND, SD, KS). Additional
sections will be appended as the analysis expands (e.g., utility shutoffs).

---

## 1. Energy Affordability Methodology

### 1.1 Definition and affordability threshold

**Energy burden** is the share of annual household income spent on home energy:

```
energy_burden = annual_home_energy_cost / annual_household_income
```

A household (or tract×FPL group) is classified as **unaffordable** when
`energy_burden > 0.06` (i.e., more than 6% of income). This is the DOE standard
affordability threshold. (`02_calculate_energy_burden.R:91`)

### 1.2 Unit of aggregation

Raw LEAD data contains one row per cohort cell: each unique combination of
census tract × FPL bracket × tenure type × housing age × heating fuel type. To avoid
double-counting households that appear in multiple cohort dimensions, all rows are first
collapsed to the **census tract × FPL bracket** level, grouping on
`(state_abbr, fip, fpl150)`. (`02_calculate_energy_burden.R:32–45`)

This aggregation sums `units` (households) and the `*_x_units` / `*_valid_units`
columns across all cohort dimensions within a group before any burden calculation is
performed.

### 1.3 Aggregate-ratio burden calculation

Within each tract×FPL group, weighted-average costs and income are computed using the
**aggregate-ratio method**: pool the cross-product numerators (`*_x_units`) and the
valid-household denominators (`*_valid_units`) across all cohort rows, then divide.
(`02_calculate_energy_burden.R:53–59`)

```
income      = Σ hincp_x_units / Σ hincp_valid_units
elec_cost   = Σ elep_x_units  / Σ elep_valid_units
gas_cost    = Σ gasp_x_units  / Σ gasp_valid_units
other_cost  = Σ fulp_x_units  / Σ fulp_valid_units

energy_burden = (elec_cost + gas_cost + other_cost) / income
```

`*_x_units` is the product of the variable value and household count for each raw cohort
row; dividing by the count of households with valid data recovers the weighted mean.

### 1.4 Decision rules

**Zero-fuel rule.** If a fuel's `Σ *_valid_units` equals 0, that fuel's cost is set to 0
rather than NA. A zero count indicates households in the group genuinely do not use that
fuel (e.g., no gas connections). (`02_calculate_energy_burden.R:55–57`)

**Drop rule.** If income `Σ hincp_valid_units` equals 0, income is set to NA and the
entire tract×FPL group is excluded from the analysis. Groups where the computed income is
non-positive are also dropped. These represent data-quality edge cases where a meaningful
burden ratio cannot be calculated. (`02_calculate_energy_burden.R:58, 89–90`)

**Coverage tracking.** Dropped households are counted per state and summarised as a
`pct_households_retained` figure. This appears in the state-level output CSV so readers
can assess how much of each state's population is represented.
(`02_calculate_energy_burden.R:64–87`)

**Extreme-burden note.** Tract×FPL groups where the computed burden exceeds 100% are
flagged as a data-quality note but **retained** and counted as unaffordable. Excluding
them would undercount high-burden households.
(`02_calculate_energy_burden.R:93–100`)

**Annual values.** DOE LEAD stores energy costs and income as annualized values. No
monthly-to-annual conversion (×12) is applied.

### 1.5 Classification and counting

After dropping invalid groups, each tract×FPL group is classified as affordable
(`energy_burden ≤ 0.06`) or unaffordable (`energy_burden > 0.06`).

Counts and percentages are **household-weighted**:

```
pct_unaffordable = 100 × Σ households[unaffordable groups] / Σ households[all groups]
```

State-level and FPL-per-state summaries also report a household-weighted mean burden
(aggregate-ratio across all tracts within a state/bracket) and a household-weighted
median burden using the `wtd_median()` helper defined at
`02_calculate_energy_burden.R:8–13`. (`02_calculate_energy_burden.R:106–171`)

### 1.6 FPL brackets

Income is categorised into five Federal Poverty Level brackets, stored as an ordered
factor in the analysis: `0-100%`, `100-150%`, `150-200%`, `200-400%`, `400%+`.
(`01_load_lead_data.R:16`)

### 1.7 Outputs produced

Three CSVs are written to `outputs/` with a `dd-mm-yyyy` date prefix
(`02_calculate_energy_burden.R:215–250`):

| File | Contents |
|------|----------|
| `{date}-reamp-state-energy-burden-summary.csv` | State-level metrics for the 10 RE-AMP states |
| `{date}-reamp-fpl-energy-burden-summary.csv` | FPL-bracket × state metrics for the 10 RE-AMP states |
| `{date}-us-state-burden-rankings.csv` | All 51 jurisdictions ranked by `pct_unaffordable` |

---

## 2. Energy Insecurity Methodology

### 2.1 Definition and the three metrics

**Energy insecurity** captures self-reported hardship in meeting home energy needs. Three
measures are derived from Household Pulse Survey (HPS) questions asked of adults 18+:

| Metric | HPS variable | Plain-language question |
|--------|-------------|-------------------------|
| **Forgo basic needs** | `energy` | In the past 12 months, did your household reduce or forgo expenses for basic needs (food, medicine, rent) to pay an energy or heating/cooling bill? |
| **Unsafe temperature** | `hse_temp` | In the past 12 months, was your household unable to heat or cool your home to a safe temperature? |
| **Unable to pay bill** | `enrgy_bill` | In the past 12 months, was there a time when your household received an energy or heating/cooling bill you were unable to pay in full? |

An overall **energy insecure** indicator equals `TRUE` for any respondent who answers YES
to at least one of the three questions (a proper person-level OR, not a sum of marginals).
(`05_calculate_energy_insecurity.R:36–57`)

### 2.2 Response coding (YES / NO / NA)

Each question has five possible response values:

- **YES** = `almost_every_month`, `some_months`, or `1_or_2_months`
- **NO** = `never`
- **NA** = item non-response — excluded from that question's denominator

A respondent coded NA for a question does not contribute to its `base_wt` (denominator).
NA values therefore represent missing data, not negative responses.
(`05_calculate_energy_insecurity.R:22–45`)

### 2.3 Survey scope and equal-cycle averaging

Analysis is restricted to **2024 Phase 4 cycles** (`survey_year == 2024`), comprising
nine cycles labelled `cycle_01` through `cycle_09`. (`04_load_pulse_data.R`)

For each state × cycle, weighted counts are computed:

```
yes_wt  = Σ person_weight  [respondents with YES]
base_wt = Σ person_weight  [respondents with non-NA response]
pct_cycle = 100 × yes_wt / base_wt
```

**Equal-cycle averaging** treats all nine cycles as having equal importance (simple mean),
rather than weighting by sample size:

```
pct_<metric> = mean(pct_cycle)   over cycles 01–09
n_<metric>   = mean(yes_wt)      over cycles 01–09
```

Both `pct_` and `n_` columns are independently averaged across cycles and are not
algebraically linked to each other. If a state appears in fewer than nine cycles, the mean
is taken over the cycles actually observed and a warning is logged.
(`05_calculate_energy_insecurity.R:63–84`)

### 2.4 Person-weight caveat

Weights used are **PWEIGHT** (person weights), not household weights — the harmonized
microdata does not carry a separate household weight. `n_<metric>` therefore represents
weighted **adults (18+)** in affected households, not a household count. This is noted
in all outputs and should be communicated clearly when citing the `n_` columns.

### 2.5 Union computation

The `energy_insecure` flag is computed at the respondent level before aggregation,
ensuring it is a true logical union rather than a mathematical combination of marginals:

```
insecure = flag_forgo_needs OR flag_unsafe_temp OR flag_unable_pay
         (where at least one of the three is non-NA)
```

A respondent is included in the union denominator (`base_wt`) if they answered at least
one of the three questions (≥ 1 non-NA). The union percentage will always be ≥ each
individual component percentage for every state.
(`05_calculate_energy_insecurity.R:48–57, 87–97`)

### 2.6 State rankings

All 51 jurisdictions (50 states + DC) are ranked **descending** on each of the four
metrics (rank 1 = highest insecurity). Ties are broken by first appearance (`ties.method
= "first"`). Rankings appear in the US rankings output only; the RE-AMP summary contains
no rank columns. (`05_calculate_energy_insecurity.R:101–120`)

### 2.7 Outputs produced

Two CSVs are written to `outputs/` with a `dd-mm-yyyy` date prefix
(`05_calculate_energy_insecurity.R:124–143`):

| File | Contents |
|------|----------|
| `{date}-reamp-energy-insecurity-summary.csv` | `pct_*` and `n_*` for all four metrics, 10 RE-AMP states |
| `{date}-us-energy-insecurity-rankings.csv` | `pct_*`, `n_*`, and `rank_*` for all four metrics, all 51 jurisdictions, sorted by `rank_energy_insecure` |

---

## 3. Data Sources

### DOE LEAD 2022 (Low-Income Energy Affordability Data)

- **Provider:** U.S. Department of Energy / Office of Energy Efficiency & Renewable Energy (EERE)
- **Version:** 2022
- **Underlying source:** 2022 ACS 5-year PUMS, calibrated to EIA Form 861 (electricity
  sales) and Form 176 (natural gas)
- **Geographic level:** Census tract; rows represent cohort cells within each tract
  (FPL bracket × tenure type × housing age × heating fuel)
- **File used by this repo:**
  `../../Cleaned_Data/doe/lead/census_tract-lead-2022-national.parquet`,
  read with `arrow::read_parquet()` (selected columns only)
- **Columns consumed:** `state`, `fip`, `fpl150`, `units`, and the four
  `*_x_units` / `*_valid_units` pairs: `hincp`, `elep`, `gasp`, `fulp`
- **Raw data origin:** <https://data.openei.org/submissions/6219>
- **Cleaning script:**
  `../../Internal/data-pipelines/eep-pipeline-core/processors/doe-lead_processor.R`
- **Full column schema:** `../../Cleaned_Data/doe/lead/CLEANED.md`
- **Note:** Puerto Rico (FIPS 72) is dropped during load; 51 jurisdictions (50 states +
  DC) are retained. (`01_load_lead_data.R:39, 54–59`)

### FIPS → state abbreviation crosswalk

A 51-row lookup table (50 states + DC) is hard-coded as a `tribble` in
`01_load_lead_data.R:19–32`. It maps numeric state FIPS codes to 2-letter abbreviations
and is joined onto the LEAD data at load time. Puerto Rico (FIPS 72) is intentionally
absent, ensuring that `filter(state != 72L)` and the left-join together produce a clean
51-jurisdiction dataset.

### Household Pulse Survey (Self-Reported Energy Insecurity)

- **Provider:** U.S. Census Bureau
- **Version:** 2024 Phase 4, cycles 01–09 (nine biweekly collection periods)
- **Geographic level:** State (2-letter abbreviation; no FIPS crosswalk needed)
- **File used by this repo:**
  `../../Cleaned_Data/us_census/household_pulse_survey/02-04-2026-pulse-energy-puf-harmonized.csv`
  (1,367,012 rows covering 2023 weeks 53–63 + 2024 cycles 01–09; filtered to 2024 at load)
- **Columns consumed:** `survey_wave`, `survey_year`, `state`, `person_weight`,
  `energy`, `hse_temp`, `enrgy_bill`
- **Raw data origin:** <https://www.census.gov/programs-surveys/household-pulse-survey/datasets.html>
- **Cleaning script:**
  `../../Internal/data-pipelines/eep-pipeline-core/processors/pulse-energy_processor.R`
- **Full column schema:** `../../Cleaned_Data/us_census/household_pulse_survey/CLEANED.md`
- **Notes:**
  - October and December 2024 cycles are absent from Phase 4 because the Census Bureau did
    not release a state-level identifier or person weight for those collection periods.
  - Weights are PWEIGHT (person weights for adults 18+). No household weight is available
    in the harmonized microdata; `n_*` columns in outputs represent weighted persons, not
    households.
