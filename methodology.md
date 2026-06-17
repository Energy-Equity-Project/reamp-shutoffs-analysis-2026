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

## 3. Shutoffs (due to Non-Payment) Methodology

### 3.1 Definition and metrics

**Utility shutoff** (disconnection) data comes from EIA Form 112, the first federal survey
of residential utility disconnections. The following metrics are produced for each state:

| Metric | Description | Source columns |
|--------|-------------|----------------|
| `elec_notices` | Annual electric shutoff notices issued | `electric_shutoff_notices` |
| `gas_notices` | Annual gas shutoff notices issued | `gas_shutoff_notices` |
| `combined_notices` | Electric + gas notices | derived |
| `elec_shutoffs` | Annual residential electric shutoffs | `electric_shutoffs` |
| `gas_shutoffs` | Annual residential gas shutoffs | `gas_shutoffs` |
| `combined_shutoffs` | Electric + gas shutoffs | derived |
| `combined_reconnections` | Electric + gas reconnections | `electric_reconnections` + `gas_reconnections` |
| `net_shutoffs` | Combined shutoffs − combined reconnections | derived |
| `pct_not_reconnected` | Share of shutoffs not reversed by a reconnection (%) | derived |
| `combined_shutoff_rate` | Cumulative annual combined shutoff rate | derived |

(`06_calculate_shutoffs.R:80–118`)

### 3.2 Annual aggregation

**Counts** are summed across the 12 monthly rows per state with `na.rm = TRUE`.

**Rates** are computed as the **sum of the 12 monthly per-customer rates** — the
cumulative annual incidence of shutoffs experienced per customer:

```
annual_rate = Σ (monthly_count / monthly_customers)   over months 1–12
```

This approach avoids distortions from changing customer bases mid-year and is not
equivalent to dividing the annual count total by a single annual denominator.
(`06_calculate_shutoffs.R:41–71, 90–96`)

**Zero/NA denominator guard.** If a month's denominator (`electric_customers` or
`gas_customers`) is 0 or NA, that month's rate is set to NA and excluded from the annual
sum via `na.rm = TRUE`. (`06_calculate_shutoffs.R:43–70`)

### 3.3 Denominator convention

Combined shutoff, notice, and net rates all use **`electric_customers`** as the
denominator. Electric service is near-universal (covering >99% of U.S. households), making
the electric customer count a practical proxy for total households. Gas rates use
`gas_customers` as their denominator.

Caveat: in dual-fuel states, `combined_shutoffs` aggregates electric and gas events into a
single numerator but retains the electric-only denominator. This means the combined rate
can exceed 1.0 in states with very high dual-fuel shutoff activity.
(`06_calculate_shutoffs.R:37–39`)

### 3.4 Net shutoffs and % not reconnected

```
net_shutoffs        = combined_shutoffs − combined_reconnections
pct_not_reconnected = (combined_shutoffs − combined_reconnections) / combined_shutoffs × 100
```

`pct_not_reconnected` is the **share of shutoffs not reversed by a reconnection**: a
higher value means more customers remained disconnected (worse outcome). It is algebraically
equivalent to `net_shutoffs / combined_shutoffs × 100`, but the "% not reconnected"
framing makes directionality explicit.

Both metrics are computed from **annual totals** (after the monthly aggregate step), not
summed monthly values. (`06_calculate_shutoffs.R:112–116`)

**Important caveat:** EIA Form 112 reconnections may include customers reconnected from
prior-month shutoffs and customers who self-cured. Net shutoffs and `pct_not_reconnected`
are therefore accounting deltas, not a precise count of households that remained
disconnected at year-end. The percentage can be negative for states where reconnections
exceed shutoffs in the annual total.

### 3.5 Quality flags

EIA Form 112 uses two data quality flags on count columns:

- **Q** — response rate below 50%; estimate is based on imputation
- **R** — relative standard error (RSE) exceeds 50%; estimate is highly uncertain

A per-state logical `any_quality_flag` is TRUE if any `*_flag` column carries `Q` or `R`
in any month. Flagged states are surfaced in both output CSVs and logged to the console.
Flagged rows are **retained** (not dropped); users should treat their counts and rates as
indicative only.

Known flags in 2024: Georgia gas data and Texas electric shutoff notices.
(`06_calculate_shutoffs.R:97–105, 137–144`)

### 3.6 State rankings

Rankings are **rate-based only** (count-based rankings would be dominated by state
population). Higher rate = rank 1 (worst). Ties are broken by first appearance
(`ties.method = "first"`). The primary ranking is `rank_combined_shutoff_rate`; separate
rankings are produced for all seven rate metrics plus `pct_not_reconnected`.
(`06_calculate_shutoffs.R:176–210`)

### 3.7 Outputs produced

Two CSVs are written to `outputs/` with a `dd-mm-yyyy` date prefix
(`06_calculate_shutoffs.R:221–241`):

| File | Contents |
|------|----------|
| `{date}-reamp-shutoffs-summary.csv` | All count + rate columns, `pct_not_reconnected`, `any_quality_flag` for the 10 RE-AMP states, sorted by `state` |
| `{date}-us-shutoffs-rankings.csv` | All 51 jurisdictions: counts (unranked) + rates + `rank_*` for all metrics, `is_reamp` flag, sorted by `rank_combined_shutoff_rate` |

---

## 4. Utility Profits Methodology

### 4.1 Definition and metrics

**Utility profit** is the net income (after-tax) reported by investor-owned utilities,
expressed in millions of dollars. **Profit as portion of bill (%)** is the share of the
average customer's bill attributable to utility profit (as reported by the Economic Policy
Institute).

The following metrics are produced per utility:

| Metric | Description |
|--------|-------------|
| `profit_2021_millions` | Net income in 2021 ($ millions) |
| `profit_2025_millions` | Net income in 2025 ($ millions) |
| `profit_change_ratio` | `profit_2025 / profit_2021` |
| `pob_2021` | Profit as % of bill in 2021 |
| `pob_2025` | Profit as % of bill in 2025 |
| `pob_change_ratio` | `pob_2025 / pob_2021` |

Change ratios greater than 1 indicate growth from 2021 to 2025.
(`07_calculate_utility_profits.R:49–58`)

### 4.2 Unit and state attribution

Analysis is at the **company level** (one row per utility). A utility is included in the
RE-AMP summary if its `Service state(s)` field contains at least one RE-AMP state
("any overlap" rule). The `reamp_states_served` column captures which RE-AMP states each
utility serves (comma-separated intersection).

**No per-state allocation is produced.** Because a company's net income is not divisible
across served states in a principled way, the analysis intentionally does not attempt to
attribute a share of profit to individual states. All metrics are company-wide totals.
(`07_calculate_utility_profits.R:35–44`)

### 4.3 Data cleaning

The 2021 and 2025 profit and portion-of-bill columns import as character type because the
source workbook contains the string `"N/A"` for utilities with missing data. These are
coerced to `NA` via `readr::parse_number()`. Years 2022–2024 import as numeric and require
no coercion. (`07_calculate_utility_profits.R:20–29`)

Utility names in the source carry footnote markers (`*`, `**`, `***`, `****`). These are
extracted into a `name_footnote` column and stripped from the utility name:

- `**` = Form 1 data (instead of SEC 10-K)
- `***` = reports end of fiscal year
- `****` = bought by private equity in 2025; no longer reports to the SEC

(`07_calculate_utility_profits.R:30–32`)

### 4.4 Decision rules

**Missing or zero 2021 base.** If `profit_2021_millions` is `NA` or `0`, the
`profit_change_ratio` is set to `NA` (analogously for `pob_change_ratio`). This applies
to utilities that did not report 2021 data or were newly formed/acquired. A list of
affected utilities is printed to the console at runtime.
(`07_calculate_utility_profits.R:49–58`)

**Known data-quality caveat — portion of bill (%).** Values in the source
`Profit Portion of Bill (%)` column span approximately 0.1% to 11% across utilities.
These are company-reported or EPI-derived figures from heterogeneous underlying sources;
cross-utility comparisons of `pob_*` values and `pob_change_ratio` rankings should be
treated with caution.

### 4.5 Rankings

Rankings are computed across all 110 utilities in the source, with **rank 1 = largest
value**. Ties are broken by first appearance (`ties.method = "first"`). Utilities with
`NA` for a metric receive `NA` rank for that metric; their presence does not affect the
ranks of other utilities. An `is_reamp` flag identifies the 31 RE-AMP-state utilities.
(`07_calculate_utility_profits.R:68–79`)

### 4.6 Outputs produced

Two CSVs are written to `outputs/` with a `dd-mm-yyyy` date prefix
(`07_calculate_utility_profits.R:92–106`):

| File | Contents |
|------|----------|
| `{date}-reamp-utility-profits-summary.csv` | 31 RE-AMP utilities: `utility`, `parent_company`, `reamp_states_served`, `service_states`, `hq_state`, `iso_rto`, 2021/2025 profit and PoB columns, change ratios, `name_footnote`; sorted by `profit_2025_millions` descending |
| `{date}-us-utility-profits-rankings.csv` | All 110 utilities: same metrics plus `is_reamp` flag and all five `rank_*` columns; sorted by `rank_profit_2025` |

---

## 5. Data Sources

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

### EIA Form 112 (Residential Utility Disconnections)

- **Provider:** U.S. Energy Information Administration (EIA)
- **Version:** 2024 (first reporting year; no prior-year data for trend comparison)
- **Underlying source:** Annual survey of electric and gas utilities on residential
  disconnections, reconnections, and shutoff notices
- **Geographic level:** State; rows represent state × month (12 monthly rows per state,
  51 jurisdictions)
- **File used by this repo:**
  `../../Cleaned_Data/eia/112/20-04-2026-eia-112-shutoffs.csv`
- **Columns consumed:** `state`, `year`, `month`, `electric_shutoff_notices`,
  `electric_shutoff_notices_flag`, `electric_shutoffs`, `electric_shutoffs_flag`,
  `electric_reconnections`, `electric_reconnections_flag`, `electric_customers`,
  `gas_shutoff_notices`, `gas_shutoff_notices_flag`, `gas_shutoffs`,
  `gas_shutoffs_flag`, `gas_reconnections`, `gas_reconnections_flag`, `gas_customers`
- **Raw data origin:** EIA Form EIA-112 survey (not yet publicly available as a
  downloadable dataset; sourced via EIA data request)
- **Cleaning script:**
  `../../Internal/data-pipelines/eep-pipeline-core/processors/eia-112_processor.R`
- **Full column schema:** `../../Cleaned_Data/eia/112/CLEANED.md`
- **Note:** 2024 is the first year EIA collected Form 112 data; no prior-year comparison
  is possible. Quality flags (`Q` = response rate < 50%; `R` = RSE > 50%) are present on
  Georgia gas data and Texas electric shutoff notices. 51 jurisdictions (50 states + DC).

### EPI Utility Profits (2021–2025)

- **Provider:** Economic Policy Institute (EPI)
- **Version:** Last updated 2026-05-08
- **Underlying source:** SEC 10-K filings, FERC Form 1, and company annual reports for
  investor-owned utilities reporting to the SEC; 110 utilities covering major US service
  territories
- **Geographic level:** Company (utility); each row is one utility with national-scope
  profit figures (not disaggregated by state)
- **File used by this repo:**
  `../../Data/epi/2021 - 2025 Utility Profits (Make a copy to edit) _ Last Updated 5_8_26.xlsx`,
  sheet `"Data"`, read with `readxl::read_excel()` — data is read from the raw `Data/`
  folder rather than `Cleaned_Data/` (no cleaning pipeline currently exists for this source)
- **Columns consumed:** `Utility`, `Parent Company`, `Service state(s)`, `HQ state`,
  `ISO/RTO`, `2021 Profit ($ millions)`, `2021 Profit Portion of Bill (%)`,
  `2025 Profit ($ millions)`, `2025 Profit Portion of Bill (%)`
- **Note:** No `SOURCE.md` currently exists for `Data/epi/` — this is a governance gap
  flagged for follow-up. Footnote markers on utility names (`*`/`**`/`***`/`****`) are
  defined in the workbook's `"Notes"` sheet; see section 4.3 above for handling.
