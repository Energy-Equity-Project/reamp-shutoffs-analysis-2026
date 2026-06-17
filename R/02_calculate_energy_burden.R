library(tidyverse)

reamp_states <- c("MI", "OH", "IN", "IL", "WI", "MN", "IA", "ND", "SD", "KS")
date_prefix  <- format(Sys.Date(), "%d-%m-%Y")

# ── Weighted median helper ─────────────────────────────────────────────────────
# Returns the smallest x where cumulative weight reaches 50% of the total.
wtd_median <- function(x, w) {
  if (length(x) == 0 || sum(w, na.rm = TRUE) == 0) return(NA_real_)
  ord  <- order(x)
  cumw <- cumsum(w[ord]) / sum(w[ord])
  x[ord][which(cumw >= 0.5)[1]]
}

# ── Load data ──────────────────────────────────────────────────────────────────

temp_path <- "temp/lead_national_slim.rds"

if (file.exists(temp_path)) {
  cat("Loading cached data from temp/\n")
  lead_data <- readRDS(temp_path)
} else {
  source("R/01_load_lead_data.R")
}

# ── Step 1: Aggregate raw cohort rows to tract × FPL groups ───────────────────
# Each raw row is one cohort cell (state × tract × FPL × tenure × fuel × housing type).
# Summing within (state_abbr, fip, fpl150) pools all cohort dimensions with no double-count.

cat("Aggregating to census tract × FPL groups...\n")

tract_fpl <- lead_data %>%
  group_by(state_abbr, fip, fpl150) %>%
  summarise(
    households    = sum(units,              na.rm = TRUE),
    s_hincp_x     = sum(hincp_x_units,     na.rm = TRUE),
    s_hincp_valid = sum(hincp_valid_units,  na.rm = TRUE),
    s_elep_x      = sum(elep_x_units,      na.rm = TRUE),
    s_elep_valid  = sum(elep_valid_units,   na.rm = TRUE),
    s_gasp_x      = sum(gasp_x_units,      na.rm = TRUE),
    s_gasp_valid  = sum(gasp_valid_units,   na.rm = TRUE),
    s_fulp_x      = sum(fulp_x_units,      na.rm = TRUE),
    s_fulp_valid  = sum(fulp_valid_units,   na.rm = TRUE)
  ) %>%
  ungroup()

cat(sprintf("Tract × FPL groups: %s\n", format(nrow(tract_fpl), big.mark = ",")))

# ── Step 2: Compute aggregate-ratio burden per group ──────────────────────────
# Fuel with zero valid units → cost = 0 (households genuinely pay $0 for that fuel).
# Zero income valid units → income = NA (group will be dropped in step 3).

tract_fpl <- tract_fpl %>%
  mutate(
    elec_cost  = case_when(s_elep_valid > 0 ~ s_elep_x / s_elep_valid, TRUE ~ 0),
    gas_cost   = case_when(s_gasp_valid > 0 ~ s_gasp_x / s_gasp_valid, TRUE ~ 0),
    other_cost = case_when(s_fulp_valid > 0 ~ s_fulp_x / s_fulp_valid, TRUE ~ 0),
    income     = case_when(s_hincp_valid > 0 ~ s_hincp_x / s_hincp_valid, TRUE ~ NA_real_),
    energy_burden = (elec_cost + gas_cost + other_cost) / income
  )

# ── Step 3: Track coverage and drop groups with invalid income ─────────────────

coverage_by_state <- left_join(
  tract_fpl %>%
    group_by(state_abbr) %>%
    summarise(total_households_pre = sum(households, na.rm = TRUE)) %>%
    ungroup(),
  tract_fpl %>%
    filter(is.na(income) | income <= 0) %>%
    group_by(state_abbr) %>%
    summarise(dropped_households = sum(households, na.rm = TRUE)) %>%
    ungroup(),
  by = "state_abbr"
) %>%
  mutate(
    dropped_households    = replace_na(dropped_households, 0),
    pct_households_retained = 100 * (total_households_pre - dropped_households) / total_households_pre
  )

total_pre     <- sum(coverage_by_state$total_households_pre)
total_dropped <- sum(coverage_by_state$dropped_households)
cat(sprintf(
  "Coverage: %.2f%% of households retained (%s dropped for missing/non-positive income)\n",
  100 * (1 - total_dropped / total_pre),
  format(total_dropped, big.mark = ",")
))

tract_fpl_valid <- tract_fpl %>%
  filter(!is.na(income), income > 0) %>%
  mutate(unaffordable = energy_burden > 0.06)

# Flag extreme burdens as data quality note (kept; still counted as unaffordable)
n_extreme <- sum(tract_fpl_valid$energy_burden > 1, na.rm = TRUE)
if (n_extreme > 0) {
  cat(sprintf(
    "Data quality note: %d tract-FPL groups have energy burden > 100%% (retained as unaffordable)\n",
    n_extreme
  ))
}

# ── Step 4: State-level summary ────────────────────────────────────────────────

cat("Computing state-level summaries...\n")

state_summary <- tract_fpl_valid %>%
  group_by(state_abbr) %>%
  summarise(
    total_households      = sum(households),
    unaffordable_households = sum(households[unaffordable]),
    weighted_median_burden = wtd_median(energy_burden, households),
    # Pool numerators and denominators for aggregate-ratio weighted mean
    sum_elep_x     = sum(s_elep_x),
    sum_elep_valid = sum(s_elep_valid),
    sum_gasp_x     = sum(s_gasp_x),
    sum_gasp_valid = sum(s_gasp_valid),
    sum_fulp_x     = sum(s_fulp_x),
    sum_fulp_valid = sum(s_fulp_valid),
    sum_hincp_x    = sum(s_hincp_x),
    sum_hincp_valid = sum(s_hincp_valid)
  ) %>%
  ungroup() %>%
  mutate(
    pct_unaffordable = 100 * unaffordable_households / total_households,
    weighted_mean_burden = (
      case_when(sum_elep_valid > 0 ~ sum_elep_x / sum_elep_valid, TRUE ~ 0) +
      case_when(sum_gasp_valid > 0 ~ sum_gasp_x / sum_gasp_valid, TRUE ~ 0) +
      case_when(sum_fulp_valid > 0 ~ sum_fulp_x / sum_fulp_valid, TRUE ~ 0)
    ) / (sum_hincp_x / sum_hincp_valid)
  ) %>%
  select(-starts_with("sum_")) %>%
  left_join(
    coverage_by_state %>% select(state_abbr, pct_households_retained),
    by = "state_abbr"
  )

# ── Step 5: FPL-per-state summary ─────────────────────────────────────────────

cat("Computing FPL-per-state summaries...\n")

fpl_state_summary <- tract_fpl_valid %>%
  group_by(state_abbr, fpl150) %>%
  summarise(
    total_households_in_bracket = sum(households),
    unaffordable_households     = sum(households[unaffordable]),
    weighted_median_burden      = wtd_median(energy_burden, households),
    sum_elep_x     = sum(s_elep_x),
    sum_elep_valid = sum(s_elep_valid),
    sum_gasp_x     = sum(s_gasp_x),
    sum_gasp_valid = sum(s_gasp_valid),
    sum_fulp_x     = sum(s_fulp_x),
    sum_fulp_valid = sum(s_fulp_valid),
    sum_hincp_x    = sum(s_hincp_x),
    sum_hincp_valid = sum(s_hincp_valid)
  ) %>%
  ungroup() %>%
  mutate(
    pct_within_bracket = 100 * unaffordable_households / total_households_in_bracket,
    weighted_mean_burden = (
      case_when(sum_elep_valid > 0 ~ sum_elep_x / sum_elep_valid, TRUE ~ 0) +
      case_when(sum_gasp_valid > 0 ~ sum_gasp_x / sum_gasp_valid, TRUE ~ 0) +
      case_when(sum_fulp_valid > 0 ~ sum_fulp_x / sum_fulp_valid, TRUE ~ 0)
    ) / (sum_hincp_x / sum_hincp_valid)
  ) %>%
  select(-starts_with("sum_")) %>%
  left_join(
    state_summary %>% select(state_abbr, state_total_households = total_households),
    by = "state_abbr"
  ) %>%
  mutate(pct_of_state_total = 100 * unaffordable_households / state_total_households) %>%
  select(-state_total_households)

# ── Step 6: US state rankings ──────────────────────────────────────────────────

us_rankings <- state_summary %>%
  arrange(desc(pct_unaffordable)) %>%
  mutate(
    rank     = row_number(),
    is_reamp = state_abbr %in% reamp_states
  ) %>%
  select(
    rank,
    state            = state_abbr,
    pct_unaffordable,
    unaffordable_households,
    total_households,
    weighted_mean_burden,
    is_reamp
  )

cat(sprintf(
  "US rankings: %d jurisdictions | RE-AMP states at ranks %s\n",
  nrow(us_rankings),
  paste(us_rankings$rank[us_rankings$is_reamp], collapse = ", ")
))

# ── Step 7: Write outputs ──────────────────────────────────────────────────────

dir.create("outputs", showWarnings = FALSE)

# RE-AMP state-level summary
reamp_state_out <- state_summary %>%
  filter(state_abbr %in% reamp_states) %>%
  arrange(state_abbr) %>%
  select(
    state                   = state_abbr,
    households              = total_households,
    unaffordable_households,
    pct_unaffordable,
    weighted_mean_burden,
    weighted_median_burden,
    pct_households_retained
  )

write.csv(
  reamp_state_out,
  paste0("outputs/", date_prefix, "-reamp-state-energy-burden-summary.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-reamp-state-energy-burden-summary.csv\n", sep = "")

# RE-AMP FPL-per-state summary
reamp_fpl_out <- fpl_state_summary %>%
  filter(state_abbr %in% reamp_states) %>%
  arrange(state_abbr, fpl150) %>%
  select(
    state                       = state_abbr,
    fpl150,
    households                  = total_households_in_bracket,
    unaffordable_households,
    pct_within_bracket,
    pct_of_state_total,
    weighted_mean_burden,
    weighted_median_burden
  )

write.csv(
  reamp_fpl_out,
  paste0("outputs/", date_prefix, "-reamp-fpl-energy-burden-summary.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-reamp-fpl-energy-burden-summary.csv\n", sep = "")

# US state rankings
write.csv(
  us_rankings,
  paste0("outputs/", date_prefix, "-us-state-burden-rankings.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-us-state-burden-rankings.csv\n", sep = "")

cat("\nDone. Run R/03_visualize_burden.R to generate charts.\n")
