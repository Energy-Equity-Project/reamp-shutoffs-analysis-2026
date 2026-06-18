library(tidyverse)

reamp_states <- c("MI", "OH", "IN", "IL", "WI", "MN", "IA", "ND", "SD", "KS")
date_prefix  <- format(Sys.Date(), "%d-%m-%Y")

# ── Load & validate ──────────────────────────────────────────────────────────

cat("Reading EIA Form 112 utility-annual data...\n")

utility_raw <- read.csv(
  "../../Internal/data-pipelines/eia-112-data-pipeline/outputs/09-06-2026-eia-112-utility-annual.csv",
  stringsAsFactors = FALSE
)

cat(sprintf("Rows loaded: %s\n", format(nrow(utility_raw), big.mark = ",")))

if (nrow(utility_raw) != 2148) {
  cat(sprintf("Warning: expected ~2,148 rows, got %d\n", nrow(utility_raw)))
} else {
  cat("Verification: ~2,148 rows confirmed.\n")
}

n_states <- n_distinct(utility_raw$state)
cat(sprintf("Jurisdictions present: %d\n", n_states))

ownership_cats <- sort(unique(utility_raw$ownership))
cat(sprintf("Ownership categories (%d): %s\n", length(ownership_cats), paste(ownership_cats, collapse = ", ")))

# ── Per-utility metrics ───────────────────────────────────────────────────────

utilities <- utility_raw %>%
  mutate(
    net_shutoffs        = shutoffs - reconnections,
    net_shutoff_rate    = case_when(
      customer_count > 0 ~ net_shutoffs / customer_count,
      TRUE               ~ NA_real_
    ),
    pct_not_reconnected = case_when(
      shutoffs > 0 ~ (shutoffs - reconnections) / shutoffs * 100,
      TRUE         ~ NA_real_
    ),
    is_flagged          = !is.na(bad_data_flag) & bad_data_flag == "Y",
    is_reamp            = state %in% reamp_states
  )

# ── Output A: RE-AMP utility summary ─────────────────────────────────────────
# All RE-AMP utilities retained (flagged rows kept but marked); sorted by
# energy_type then descending shutoff_rate.

reamp_summary <- utilities %>%
  filter(is_reamp) %>%
  arrange(energy_type, desc(shutoff_rate)) %>%
  select(
    state, utility_name, energy_type, ownership, parent,
    customer_count, shutoffs, reconnections, final_notices,
    net_shutoffs, shutoff_rate, final_notice_rate, reconnection_rate,
    net_shutoff_rate, pct_not_reconnected, is_flagged, data_quality_note
  )

cat(sprintf(
  "RE-AMP summary: %d rows (%d utilities; %d flagged)\n",
  nrow(reamp_summary),
  n_distinct(paste(reamp_summary$utility_name, reamp_summary$state)),
  sum(reamp_summary$is_flagged)
))

# ── Output B: US utility rankings ─────────────────────────────────────────────
# Exclude flagged rows; rank within each energy_type (rank 1 = worst = highest rate).

us_rankings <- utilities %>%
  filter(!is_flagged) %>%
  group_by(energy_type) %>%
  mutate(
    rank_shutoff_rate        = rank(desc(shutoff_rate),        ties.method = "first"),
    rank_pct_not_reconnected = rank(desc(pct_not_reconnected), ties.method = "first")
  ) %>%
  ungroup() %>%
  arrange(energy_type, rank_shutoff_rate) %>%
  select(
    state, utility_name, energy_type, ownership, is_reamp,
    customer_count, shutoffs, reconnections, net_shutoffs,
    shutoff_rate, rank_shutoff_rate,
    pct_not_reconnected, rank_pct_not_reconnected,
    final_notice_rate
  )

reamp_best_ranks <- us_rankings %>%
  filter(is_reamp) %>%
  group_by(energy_type) %>%
  summarise(best_rank = min(rank_shutoff_rate), .groups = "drop")

cat(sprintf(
  "US rankings: %d rows (flagged excluded) | RE-AMP best (lowest) shutoff_rate rank by fuel: %s\n",
  nrow(us_rankings),
  paste(
    sprintf("%s=%d", reamp_best_ranks$energy_type, reamp_best_ranks$best_rank),
    collapse = ", "
  )
))

# ── Output C: ownership summary ───────────────────────────────────────────────
# Exclude flagged rows; aggregate-ratio (pool counts) by ownership × energy_type.
# Run for RE-AMP and US separately, then stack with a scope column.

summarise_ownership <- function(df, scope_label) {
  df %>%
    group_by(ownership, energy_type) %>%
    summarise(
      n_utilities         = n(),
      total_customers     = sum(customer_count,   na.rm = TRUE),
      total_shutoffs      = sum(shutoffs,          na.rm = TRUE),
      total_reconnections = sum(reconnections,     na.rm = TRUE),
      total_final_notices = sum(final_notices,     na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      shutoff_rate         = total_shutoffs      / total_customers,
      reconnection_rate    = total_reconnections / total_shutoffs,
      final_notice_rate    = total_final_notices / total_customers,
      net_shutoff_rate     = (total_shutoffs - total_reconnections) / total_customers,
      pct_not_reconnected  = (total_shutoffs - total_reconnections) / total_shutoffs * 100,
      scope                = scope_label
    )
}

unflagged <- utilities %>% filter(!is_flagged)

ownership_summary <- bind_rows(
  summarise_ownership(unflagged %>% filter(is_reamp), "reamp"),
  summarise_ownership(unflagged,                       "us")
) %>%
  arrange(scope, energy_type, desc(shutoff_rate)) %>%
  select(
    scope, ownership, energy_type, n_utilities, total_customers,
    total_shutoffs, total_reconnections, total_final_notices,
    shutoff_rate, reconnection_rate, final_notice_rate,
    net_shutoff_rate, pct_not_reconnected
  )

cat(sprintf(
  "Ownership summary: %d rows | scopes: %s\n",
  nrow(ownership_summary),
  paste(unique(ownership_summary$scope), collapse = ", ")
))

# ── Write outputs ─────────────────────────────────────────────────────────────

dir.create("outputs", showWarnings = FALSE)

write.csv(
  reamp_summary,
  paste0("outputs/", date_prefix, "-reamp-utility-shutoffs-summary.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-reamp-utility-shutoffs-summary.csv\n", sep = "")

write.csv(
  us_rankings,
  paste0("outputs/", date_prefix, "-us-utility-shutoffs-rankings.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-us-utility-shutoffs-rankings.csv\n", sep = "")

write.csv(
  ownership_summary,
  paste0("outputs/", date_prefix, "-ownership-shutoffs-summary.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-ownership-shutoffs-summary.csv\n", sep = "")

cat("\nDone.\n")
