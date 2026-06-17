library(tidyverse)
library(readxl)
library(janitor)

reamp_states <- c("MI", "OH", "IN", "IL", "WI", "MN", "IA", "ND", "SD", "KS")
date_prefix  <- format(Sys.Date(), "%d-%m-%Y")

# ── Load + clean ────────────────────────────────────────────────────────────────

cat("Reading EPI utility profits data...\n")

profits_raw <- read_excel(
  "../../Data/epi/2021 - 2025 Utility Profits (Make a copy to edit) _ Last Updated 5_8_26.xlsx",
  sheet = "Data"
) %>%
  clean_names()

cat(sprintf("Rows loaded: %d\n", nrow(profits_raw)))

# ── Parse character profit columns + strip footnote markers ────────────────────
# 2025 and 2021 columns import as character due to "N/A" strings in the source;
# parse_number() converts those to NA and handles stray currency formatting.
# Footnote markers (*/**/***/****) are captured before stripping from utility name:
#   **   = Form 1 data instead of SEC 10-K
#   ***  = reports end of fiscal year
#   **** = bought by private equity in 2025; no longer reports to SEC

profits <- profits_raw %>%
  mutate(
    across(
      c(x2025_profit_millions, x2025_profit_portion_of_bill_percent,
        x2021_profit_millions, x2021_profit_portion_of_bill_percent),
      ~ readr::parse_number(as.character(.x), na = c("", "NA", "N/A"))
    ),
    name_footnote = str_extract(utility, "[*]+$"),
    utility       = str_remove(utility, "[*]+$") %>% str_trim()
  )

# ── RE-AMP state attribution ────────────────────────────────────────────────────
# Any utility whose service_state_s contains ≥1 RE-AMP state is included.
# reamp_states_served captures only the RE-AMP subset; one row per utility.

profits <- profits %>%
  mutate(
    reamp_states_served = map_chr(service_state_s, function(x) {
      states <- trimws(strsplit(x, ",\\s*")[[1]])
      paste(intersect(states, reamp_states), collapse = ", ")
    }),
    is_reamp = nchar(reamp_states_served) > 0
  )

# ── Metric computation ──────────────────────────────────────────────────────────
# Guard: missing or zero 2021 base → change ratio NA (avoids divide-by-zero and
# undefined ratios for utilities with no 2021 reporting).

profits <- profits %>%
  mutate(
    profit_change_ratio = case_when(
      is.na(x2021_profit_millions) | x2021_profit_millions == 0 ~ NA_real_,
      TRUE ~ x2025_profit_millions / x2021_profit_millions
    ),
    pob_change_ratio = case_when(
      is.na(x2021_profit_portion_of_bill_percent) | x2021_profit_portion_of_bill_percent == 0 ~ NA_real_,
      TRUE ~ x2025_profit_portion_of_bill_percent / x2021_profit_portion_of_bill_percent
    )
  )

# ── Verification logging ────────────────────────────────────────────────────────

if (nrow(profits) != 110) {
  cat(sprintf("Warning: expected 110 utilities, loaded %d\n", nrow(profits)))
} else {
  cat("Verification: 110 utilities confirmed.\n")
}

n_reamp <- sum(profits$is_reamp)
reamp_states_found <- profits %>%
  filter(is_reamp) %>%
  pull(reamp_states_served) %>%
  strsplit(",\\s*") %>%
  unlist() %>%
  unique() %>%
  sort()
cat(sprintf(
  "RE-AMP utilities: %d | RE-AMP states represented: %s\n",
  n_reamp, paste(reamp_states_found, collapse = ", ")
))

cat(sprintf(
  "NA counts — profit_2025: %d | profit_2021: %d | pob_2025: %d | pob_2021: %d\n",
  sum(is.na(profits$x2025_profit_millions)),
  sum(is.na(profits$x2021_profit_millions)),
  sum(is.na(profits$x2025_profit_portion_of_bill_percent)),
  sum(is.na(profits$x2021_profit_portion_of_bill_percent))
))

no_ratio <- profits %>%
  filter(is.na(profit_change_ratio)) %>%
  pull(utility)
cat(sprintf(
  "Utilities excluded from profit change ratio (%d): %s\n",
  length(no_ratio), paste(no_ratio, collapse = "; ")
))

# ── RE-AMP summary ────────────────────────────────────────────────────────────────

reamp_summary <- profits %>%
  filter(is_reamp) %>%
  arrange(desc(x2025_profit_millions)) %>%
  select(
    utility,
    parent_company,
    reamp_states_served,
    service_states        = service_state_s,
    hq_state,
    iso_rto,
    profit_2021_millions  = x2021_profit_millions,
    profit_2025_millions  = x2025_profit_millions,
    profit_change_ratio,
    pob_2021              = x2021_profit_portion_of_bill_percent,
    pob_2025              = x2025_profit_portion_of_bill_percent,
    pob_change_ratio,
    name_footnote
  )

# ── US rankings ──────────────────────────────────────────────────────────────────
# Rank 1 = largest value. NAs are excluded from ranking (retain NA in rank column).

us_rankings <- profits %>%
  mutate(
    rank_profit_2025   = rank(desc(x2025_profit_millions),               ties.method = "first"),
    rank_profit_2021   = rank(desc(x2021_profit_millions),               ties.method = "first"),
    rank_profit_change = rank(desc(profit_change_ratio),                  ties.method = "first"),
    rank_pob_2025      = rank(desc(x2025_profit_portion_of_bill_percent), ties.method = "first"),
    rank_pob_change    = rank(desc(pob_change_ratio),                     ties.method = "first")
  ) %>%
  arrange(rank_profit_2025) %>%
  select(
    utility,
    parent_company,
    service_states        = service_state_s,
    hq_state,
    iso_rto,
    is_reamp,
    profit_2021_millions  = x2021_profit_millions,  rank_profit_2021,
    profit_2025_millions  = x2025_profit_millions,  rank_profit_2025,
    profit_change_ratio,                             rank_profit_change,
    pob_2021              = x2021_profit_portion_of_bill_percent,
    pob_2025              = x2025_profit_portion_of_bill_percent, rank_pob_2025,
    pob_change_ratio,                                rank_pob_change,
    name_footnote
  )

cat(sprintf(
  "US rankings: %d utilities | is_reamp TRUE: %d\n",
  nrow(us_rankings), sum(us_rankings$is_reamp)
))

# ── Write outputs ──────────────────────────────────────────────────────────────

dir.create("outputs", showWarnings = FALSE)

write.csv(
  reamp_summary,
  paste0("outputs/", date_prefix, "-reamp-utility-profits-summary.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-reamp-utility-profits-summary.csv\n", sep = "")

write.csv(
  us_rankings,
  paste0("outputs/", date_prefix, "-us-utility-profits-rankings.csv"),
  row.names = FALSE
)
cat("Written: outputs/", date_prefix, "-us-utility-profits-rankings.csv\n", sep = "")

cat("\nDone.\n")
