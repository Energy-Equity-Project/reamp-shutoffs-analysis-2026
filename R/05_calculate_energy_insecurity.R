library(tidyverse)

reamp_states <- c("MI", "OH", "IN", "IL", "WI", "MN", "IA", "ND", "SD", "KS")
date_prefix  <- format(Sys.Date(), "%d-%m-%Y")

# ── Load data ──────────────────────────────────────────────────────────────────

temp_path <- "temp/pulse_2024_slim.rds"

if (file.exists(temp_path)) {
  cat("Loading cached data from temp/\n")
  pulse <- readRDS(temp_path)
} else {
  source("R/04_load_pulse_data.R")
  pulse <- readRDS(temp_path)
}

# ── Step 1: Respondent-level YES flags ─────────────────────────────────────────
# YES = almost_every_month | some_months | 1_or_2_months
# NO  = never
# NA  = item non-response; excluded from that question's denominator

yes_vals <- c("almost_every_month", "some_months", "1_or_2_months")

cat("Building respondent-level energy insecurity flags...\n")

pulse_flagged <- pulse %>%
  mutate(
    flag_forgo_needs = case_when(
      energy     %in% yes_vals ~ TRUE,
      energy     == "never"    ~ FALSE,
      TRUE                     ~ NA
    ),
    flag_unsafe_temp = case_when(
      hse_temp   %in% yes_vals ~ TRUE,
      hse_temp   == "never"    ~ FALSE,
      TRUE                     ~ NA
    ),
    flag_unable_pay = case_when(
      enrgy_bill %in% yes_vals ~ TRUE,
      enrgy_bill == "never"    ~ FALSE,
      TRUE                     ~ NA
    )
  ) %>%
  mutate(
    # Union: insecure if ANY of the three is YES; in scope if at least one is non-NA
    any_answered     = !is.na(flag_forgo_needs) | !is.na(flag_unsafe_temp) | !is.na(flag_unable_pay),
    flag_energy_insecure = case_when(
      flag_forgo_needs == TRUE | flag_unsafe_temp == TRUE | flag_unable_pay == TRUE ~ TRUE,
      any_answered                                                                   ~ FALSE,
      TRUE                                                                           ~ NA
    )
  ) %>%
  select(-any_answered)

# ── Step 2: Per-state × cycle × metric weighted counts ─────────────────────────
# Pivot the four flags long so each respondent contributes one row per metric.
# NA rows are excluded from that metric's denominator (filter before summarising).

cat("Computing per-cycle weighted counts by state and metric...\n")

pulse_long <- pulse_flagged %>%
  select(
    survey_wave, state, person_weight,
    forgo_needs     = flag_forgo_needs,
    unsafe_temp     = flag_unsafe_temp,
    unable_pay      = flag_unable_pay,
    energy_insecure = flag_energy_insecure
  ) %>%
  pivot_longer(
    cols      = c(forgo_needs, unsafe_temp, unable_pay, energy_insecure),
    names_to  = "metric",
    values_to = "is_yes"
  ) %>%
  filter(!is.na(is_yes))

cycle_stats <- pulse_long %>%
  group_by(state, survey_wave, metric) %>%
  summarise(
    yes_wt  = sum(person_weight[is_yes]),
    base_wt = sum(person_weight)
  ) %>%
  ungroup() %>%
  mutate(pct_cycle = 100 * yes_wt / base_wt)

# ── Step 3: Equal-weight average across cycles ─────────────────────────────────
# Average pct and yes_wt independently (both are equal-cycle means).
# Guard: flag states with fewer than 9 cycles.

cat("Averaging across cycles with equal weight...\n")

state_metric_avg <- cycle_stats %>%
  group_by(state, metric) %>%
  summarise(
    n_cycles = n(),
    pct      = mean(pct_cycle),
    n        = mean(yes_wt)
  ) %>%
  ungroup()

incomplete_states <- state_metric_avg %>%
  filter(n_cycles < 9) %>%
  distinct(state, metric, n_cycles)

if (nrow(incomplete_states) > 0) {
  cat("Warning: some state × metric combinations have fewer than 9 cycles:\n")
  print(incomplete_states)
}

# ── Step 4: Pivot wide — one row per state ─────────────────────────────────────

state_wide <- state_metric_avg %>%
  select(state, metric, pct, n) %>%
  pivot_wider(
    names_from  = metric,
    values_from = c(pct, n),
    names_glue  = "{.value}_{metric}"
  )

# ── Step 5: Sanity checks ──────────────────────────────────────────────────────

cat(sprintf(
  "\nSanity checks: %d states in wide table\n",
  nrow(state_wide)
))

# Union should be >= each component for every state
pct_check <- state_wide %>%
  filter(
    pct_energy_insecure < pct_forgo_needs |
    pct_energy_insecure < pct_unsafe_temp |
    pct_energy_insecure < pct_unable_pay
  )

if (nrow(pct_check) > 0) {
  cat("Warning: pct_energy_insecure < a component metric for these states:\n")
  print(pct_check$state)
} else {
  cat("Union dominance check passed (pct_energy_insecure >= all components for all states).\n")
}

# ── Step 6: Rankings ───────────────────────────────────────────────────────────
# Rank 1 = highest insecurity; ties broken by row_number() (first appearance)

us_rankings <- state_wide %>%
  mutate(
    is_reamp             = state %in% reamp_states,
    rank_forgo_needs     = rank(desc(pct_forgo_needs),     ties.method = "first"),
    rank_unsafe_temp     = rank(desc(pct_unsafe_temp),     ties.method = "first"),
    rank_unable_pay      = rank(desc(pct_unable_pay),      ties.method = "first"),
    rank_energy_insecure = rank(desc(pct_energy_insecure), ties.method = "first")
  ) %>%
  arrange(rank_energy_insecure) %>%
  select(
    state, is_reamp,
    pct_forgo_needs,     n_forgo_needs,     rank_forgo_needs,
    pct_unsafe_temp,     n_unsafe_temp,     rank_unsafe_temp,
    pct_unable_pay,      n_unable_pay,      rank_unable_pay,
    pct_energy_insecure, n_energy_insecure, rank_energy_insecure
  )

cat(sprintf(
  "US rankings: %d jurisdictions | RE-AMP states at energy_insecure ranks %s\n",
  nrow(us_rankings),
  paste(us_rankings$rank_energy_insecure[us_rankings$is_reamp], collapse = ", ")
))

# ── Step 7: Write outputs ──────────────────────────────────────────────────────

dir.create("outputs", showWarnings = FALSE)

# RE-AMP summary
reamp_summary <- state_wide %>%
  filter(state %in% reamp_states) %>%
  arrange(state) %>%
  select(
    state,
    pct_forgo_needs, n_forgo_needs,
    pct_unsafe_temp, n_unsafe_temp,
    pct_unable_pay,  n_unable_pay,
    pct_energy_insecure, n_energy_insecure
  )

write.csv(
  reamp_summary,
  paste0("outputs/", date_prefix, "-reamp-energy-insecurity-summary.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-reamp-energy-insecurity-summary.csv\n", sep = "")

# US rankings
write.csv(
  us_rankings,
  paste0("outputs/", date_prefix, "-us-energy-insecurity-rankings.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-us-energy-insecurity-rankings.csv\n", sep = "")

cat("\nDone.\n")
