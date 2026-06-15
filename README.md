# RE-AMP Midwest Shutoffs & Energy Insecurity Analysis (2026)

Analysis of utility shutoffs, energy insecurity, and affordability across the [RE-AMP network](https://www.reamp.org/about/) member states in the Midwest.

---

## Background

Utility shutoffs and energy insecurity carry serious consequences for households that depend on electricity and natural gas for heating, cooling, and essential daily functions. In the Midwest, the stakes are especially high: cold winters make natural gas and electric heating a matter of health and safety, and low-income households face a compounding burden of high energy costs relative to income.

Despite the severity of the issue, data on disconnections, affordability, and energy insecurity is fragmented across multiple federal and state sources, making it difficult to draw consistent regional comparisons. This analysis brings those sources together to produce a clear picture of energy hardship across the RE-AMP network's 10 Midwest member states.

---

## Research Goals

This project surfaces state-level and Midwest-regional metrics on utility shutoffs, energy burden, and self-reported energy insecurity for the 10 states in the RE-AMP network:

**Michigan (MI), Ohio (OH), Indiana (IN), Illinois (IL), Wisconsin (WI), Minnesota (MN), Iowa (IA), North Dakota (ND), South Dakota (SD), Kansas (KS)**

The analysis is intended to support RE-AMP's advocacy and policy work by providing a shared empirical foundation for member organizations across the region.

---

## Scope

**Fuel types:** Electric and natural gas (both are essential for Midwest residential energy use).

**Sector:** Residential customers.

**Analytical framings:**

1. **State comparisons within the RE-AMP network** — rank and compare the 10 member states on disconnection rates, energy burden, and energy insecurity.
2. **Midwest vs. national benchmarking** — situate RE-AMP states relative to national averages to identify where the region over- or under-performs.
3. **Utility-level deep dives** — examine large utilities across the region on rates, customer counts, ownership type, and disconnection activity.
4. **Equity and demographic breakdowns** — disaggregate findings by income level, race/ethnicity, and household type to identify who bears disproportionate energy hardship.

---

## Research Questions

- How do residential electric and gas disconnection rates compare across RE-AMP states and against the national average? *(EIA Form 112)*
- How does energy burden vary by income level across the region, and which census tracts face the highest burden? *(DOE LEAD)*
- What share of households report energy insecurity (inability to pay bills, keeping home at an unsafe temperature), and how does this vary by state and demographic group? *(Household Pulse Survey)*
- How do electric rates and customer counts at large utilities relate to shutoff activity across the region? *(EIA Form 861 + EIA Form 112)*
- Which RE-AMP states and utilities show the greatest disconnection burden on low-income and minority households? *(DOE LEAD + EIA Form 112)*

---

## Data Sources

| Source | Description | Path (raw / cleaned) | Link |
|--------|-------------|----------------------|------|
| EIA Form 112 | Residential disconnections (electric + gas), state & utility level, 2024 | `../../Data/eia/112/` / `../../Cleaned_Data/eia/112/` | [EIA Form 112](https://www.eia.gov/analysis/requests/residential/utility/) |
| Household Pulse Survey | State-level self-reported energy insecurity, 2023–2024 | `../../Data/us_census/household_pulse_survey/` / `../../Cleaned_Data/us_census/household_pulse_survey/` | [Census Household Pulse](https://www.census.gov/data/experimental-data-products/household-pulse-survey.html) |
| DOE LEAD | Low-income energy affordability and burden, census-tract level, 2022 | `../../Data/doe/lead/` / `../../Cleaned_Data/doe/lead/` | [DOE LEAD Tool](https://data.openei.org/submissions/6219) |
| EIA Form 861 | Electric utility sales, customers, and rates, 1990–2024 | `../../Data/eia/861/` / `../../Cleaned_Data/eia/861/` | [EIA Form 861](https://www.eia.gov/electricity/data/eia861/) |

---

## Data Management

All data is referenced via relative paths to the shared `Data/` and `Cleaned_Data/` folders at the workspace root (e.g., `../../Data/eia/112/`). Raw and cleaned data files are **not** committed to this repository, per workspace data management rules. See the workspace `CLAUDE.md` for data governance details.

---

## Status

**Active — project scoping / setup**
