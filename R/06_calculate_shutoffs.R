library(tidyverse)

reamp_states <- c("MI", "OH", "IN", "IL", "WI", "MN", "IA", "ND", "SD", "KS")
date_prefix  <- format(Sys.Date(), "%d-%m-%Y")

# ── Load data ──────────────────────────────────────────────────────────────────

cat("Reading EIA Form 112 shutoffs data...\n")

shutoffs_raw <- read.csv(
  "../../Cleaned_Data/eia/112/20-04-2026-eia-112-shutoffs.csv",
  stringsAsFactors = FALSE
)

cat(sprintf("Rows loaded: %s\n", format(nrow(shutoffs_raw), big.mark = ",")))

# ── State name → abbreviation crosswalk ────────────────────────────────────────
# Base R state.name / state.abb cover the 50 states; DC is added manually.
# The LEAD FIPS crosswalk in 01_load_lead_data.R is keyed on FIPS, which this
# CSV lacks, so a name-based map is used here instead.

state_crosswalk <- tibble(
  state_name = c(state.name, "District of Columbia"),
  state_abbr = c(state.abb, "DC")
)

shutoffs <- shutoffs_raw %>%
  left_join(state_crosswalk, by = c("state" = "state_name"))

unmatched <- shutoffs %>% filter(is.na(state_abbr)) %>% distinct(state)
if (nrow(unmatched) > 0) {
  cat("Warning: unmatched state names (check crosswalk):\n")
  print(unmatched)
}

# ── Compute monthly rate columns ────────────────────────────────────────────────
# Guard: denominator 0 or NA → that month's rate is NA (excluded from annual sum).
# Combined rates use electric_customers as denominator (electric is near-universal;
# proxies total households). Gas rates use gas_customers.

shutoffs <- shutoffs %>%
  mutate(
    monthly_elec_notice_rate      = case_when(
      is.na(electric_customers) | electric_customers == 0 ~ NA_real_,
      TRUE ~ electric_shutoff_notices / electric_customers
    ),
    monthly_elec_shutoff_rate     = case_when(
      is.na(electric_customers) | electric_customers == 0 ~ NA_real_,
      TRUE ~ electric_shutoffs / electric_customers
    ),
    monthly_gas_notice_rate       = case_when(
      is.na(gas_customers) | gas_customers == 0 ~ NA_real_,
      TRUE ~ gas_shutoff_notices / gas_customers
    ),
    monthly_gas_shutoff_rate      = case_when(
      is.na(gas_customers) | gas_customers == 0 ~ NA_real_,
      TRUE ~ gas_shutoffs / gas_customers
    ),
    monthly_combined_notice_rate  = case_when(
      is.na(electric_customers) | electric_customers == 0 ~ NA_real_,
      TRUE ~ (electric_shutoff_notices + gas_shutoff_notices) / electric_customers
    ),
    monthly_combined_shutoff_rate = case_when(
      is.na(electric_customers) | electric_customers == 0 ~ NA_real_,
      TRUE ~ (electric_shutoffs + gas_shutoffs) / electric_customers
    ),
    monthly_net_shutoff_rate      = case_when(
      is.na(electric_customers) | electric_customers == 0 ~ NA_real_,
      TRUE ~ (electric_shutoffs + gas_shutoffs - electric_reconnections - gas_reconnections) / electric_customers
    )
  )

# ── Aggregate to annual state totals ────────────────────────────────────────────
# Counts: sum across months (na.rm = TRUE).
# Rates: sum of the 12 monthly per-customer rates = cumulative annual incidence.
# any_quality_flag: TRUE if any *_flag column carries "Q" or "R" in any month.

cat("Aggregating to annual state totals...\n")

state_summary <- shutoffs %>%
  group_by(state_abbr) %>%
  summarise(
    n_months               = n(),
    elec_notices           = sum(electric_shutoff_notices,     na.rm = TRUE),
    gas_notices            = sum(gas_shutoff_notices,          na.rm = TRUE),
    elec_shutoffs          = sum(electric_shutoffs,             na.rm = TRUE),
    gas_shutoffs           = sum(gas_shutoffs,                  na.rm = TRUE),
    elec_reconnections_sum = sum(electric_reconnections,        na.rm = TRUE),
    gas_reconnections_sum  = sum(gas_reconnections,             na.rm = TRUE),
    elec_notice_rate       = sum(monthly_elec_notice_rate,     na.rm = TRUE),
    gas_notice_rate        = sum(monthly_gas_notice_rate,      na.rm = TRUE),
    combined_notice_rate   = sum(monthly_combined_notice_rate, na.rm = TRUE),
    elec_shutoff_rate      = sum(monthly_elec_shutoff_rate,    na.rm = TRUE),
    gas_shutoff_rate       = sum(monthly_gas_shutoff_rate,     na.rm = TRUE),
    combined_shutoff_rate  = sum(monthly_combined_shutoff_rate, na.rm = TRUE),
    net_shutoff_rate       = sum(monthly_net_shutoff_rate,     na.rm = TRUE),
    any_quality_flag       = any(
      electric_shutoff_notices_flag %in% c("Q", "R") |
      electric_shutoffs_flag        %in% c("Q", "R") |
      electric_reconnections_flag   %in% c("Q", "R") |
      gas_shutoff_notices_flag      %in% c("Q", "R") |
      gas_shutoffs_flag             %in% c("Q", "R") |
      gas_reconnections_flag        %in% c("Q", "R"),
      na.rm = TRUE
    )
  ) %>%
  ungroup() %>%
  mutate(
    combined_notices       = elec_notices + gas_notices,
    combined_shutoffs      = elec_shutoffs + gas_shutoffs,
    combined_reconnections = elec_reconnections_sum + gas_reconnections_sum,
    net_shutoffs           = combined_shutoffs - combined_reconnections,
    pct_not_reconnected    = case_when(
      combined_shutoffs > 0 ~ (combined_shutoffs - combined_reconnections) / combined_shutoffs * 100,
      TRUE                  ~ NA_real_
    )
  ) %>%
  select(-elec_reconnections_sum, -gas_reconnections_sum)

# ── Verification checks ──────────────────────────────────────────────────────────

if (n_distinct(state_summary$state_abbr) != 51) {
  cat(sprintf(
    "Warning: expected 51 jurisdictions, found %d\n",
    n_distinct(state_summary$state_abbr)
  ))
} else {
  cat("Verification: 51 jurisdictions confirmed.\n")
}

cat(sprintf(
  "Coverage: n_months range %d–%d across all states\n",
  min(state_summary$n_months),
  max(state_summary$n_months)
))

n_flags <- sum(state_summary$any_quality_flag, na.rm = TRUE)
if (n_flags > 0) {
  flagged_states <- state_summary %>%
    filter(any_quality_flag) %>%
    pull(state_abbr) %>%
    paste(collapse = ", ")
  cat(sprintf("Quality flags (Q/R) present in %d state(s): %s\n", n_flags, flagged_states))
}

# ── RE-AMP summary ────────────────────────────────────────────────────────────────

reamp_summary <- state_summary %>%
  filter(state_abbr %in% reamp_states) %>%
  arrange(state_abbr) %>%
  select(
    state                  = state_abbr,
    n_months,
    elec_notices,
    gas_notices,
    combined_notices,
    elec_shutoffs,
    gas_shutoffs,
    combined_shutoffs,
    combined_reconnections,
    net_shutoffs,
    elec_notice_rate,
    gas_notice_rate,
    combined_notice_rate,
    elec_shutoff_rate,
    gas_shutoff_rate,
    combined_shutoff_rate,
    net_shutoff_rate,
    pct_not_reconnected,
    any_quality_flag
  )

# ── US rankings ────────────────────────────────────────────────────────────────
# Rate-based only; higher rate = rank 1 = worst.

us_rankings <- state_summary %>%
  mutate(
    is_reamp                    = state_abbr %in% reamp_states,
    rank_elec_notice_rate       = rank(desc(elec_notice_rate),       ties.method = "first"),
    rank_gas_notice_rate        = rank(desc(gas_notice_rate),        ties.method = "first"),
    rank_combined_notice_rate   = rank(desc(combined_notice_rate),   ties.method = "first"),
    rank_elec_shutoff_rate      = rank(desc(elec_shutoff_rate),      ties.method = "first"),
    rank_gas_shutoff_rate       = rank(desc(gas_shutoff_rate),       ties.method = "first"),
    rank_combined_shutoff_rate  = rank(desc(combined_shutoff_rate),  ties.method = "first"),
    rank_net_shutoff_rate       = rank(desc(net_shutoff_rate),       ties.method = "first"),
    rank_pct_not_reconnected    = rank(desc(pct_not_reconnected),    ties.method = "first")
  ) %>%
  arrange(rank_combined_shutoff_rate) %>%
  select(
    state                       = state_abbr,
    is_reamp,
    n_months,
    elec_notices,
    gas_notices,
    combined_notices,
    elec_shutoffs,
    gas_shutoffs,
    combined_shutoffs,
    combined_reconnections,
    net_shutoffs,
    elec_notice_rate,        rank_elec_notice_rate,
    gas_notice_rate,         rank_gas_notice_rate,
    combined_notice_rate,    rank_combined_notice_rate,
    elec_shutoff_rate,       rank_elec_shutoff_rate,
    gas_shutoff_rate,        rank_gas_shutoff_rate,
    combined_shutoff_rate,   rank_combined_shutoff_rate,
    net_shutoff_rate,        rank_net_shutoff_rate,
    pct_not_reconnected,     rank_pct_not_reconnected,
    any_quality_flag
  )

cat(sprintf(
  "US rankings: %d jurisdictions | RE-AMP states at combined_shutoff_rate ranks %s\n",
  nrow(us_rankings),
  paste(us_rankings$rank_combined_shutoff_rate[us_rankings$is_reamp], collapse = ", ")
))

# ── Write outputs ──────────────────────────────────────────────────────────────

dir.create("outputs", showWarnings = FALSE)

write.csv(
  reamp_summary,
  paste0("outputs/", date_prefix, "-reamp-shutoffs-summary.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-reamp-shutoffs-summary.csv\n", sep = "")

write.csv(
  us_rankings,
  paste0("outputs/", date_prefix, "-us-shutoffs-rankings.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-us-shutoffs-rankings.csv\n", sep = "")

cat("\nDone.\n")
