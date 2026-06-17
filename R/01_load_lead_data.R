library(tidyverse)
library(arrow)

lead_path <- "../../Cleaned_Data/doe/lead/census_tract-lead-2022-national.parquet"
temp_path <- "temp/lead_national_slim.rds"

cols_needed <- c(
  "state", "fip", "fpl150",
  "units",
  "hincp_x_units", "hincp_valid_units",
  "elep_x_units",  "elep_valid_units",
  "gasp_x_units",  "gasp_valid_units",
  "fulp_x_units",  "fulp_valid_units"
)

fpl_levels <- c("0-100%", "100-150%", "150-200%", "200-400%", "400%+")

# FIPS → 2-letter state abbreviation (50 states + DC; excludes PR/FIPS 72)
fips_xwalk <- tribble(
  ~state_fips, ~state_abbr,
   1L, "AL",  2L, "AK",  4L, "AZ",  5L, "AR",  6L, "CA",
   8L, "CO",  9L, "CT", 10L, "DE", 11L, "DC", 12L, "FL",
  13L, "GA", 15L, "HI", 16L, "ID", 17L, "IL", 18L, "IN",
  19L, "IA", 20L, "KS", 21L, "KY", 22L, "LA", 23L, "ME",
  24L, "MD", 25L, "MA", 26L, "MI", 27L, "MN", 28L, "MS",
  29L, "MO", 30L, "MT", 31L, "NE", 32L, "NV", 33L, "NH",
  34L, "NJ", 35L, "NM", 36L, "NY", 37L, "NC", 38L, "ND",
  39L, "OH", 40L, "OK", 41L, "OR", 42L, "PA", 44L, "RI",
  45L, "SC", 46L, "SD", 47L, "TN", 48L, "TX", 49L, "UT",
  50L, "VT", 51L, "VA", 53L, "WA", 54L, "WV", 55L, "WI",
  56L, "WY"
)

# ── Load ───────────────────────────────────────────────────────────────────────

cat("Reading national LEAD parquet (selected columns)...\n")

lead_data <- arrow::read_parquet(lead_path, col_select = all_of(cols_needed)) %>%
  filter(state != 72L) %>%                        # drop Puerto Rico (FIPS 72)
  left_join(fips_xwalk, by = c("state" = "state_fips")) %>%
  select(-state) %>%
  mutate(fpl150 = factor(fpl150, levels = fpl_levels, ordered = TRUE))

# ── Verify ─────────────────────────────────────────────────────────────────────

n_states <- n_distinct(lead_data$state_abbr)
unmatched <- lead_data %>% filter(is.na(state_abbr)) %>% nrow()

cat(sprintf(
  "Loaded %s rows | %d jurisdictions | %d unmatched FIPS rows\n",
  format(nrow(lead_data), big.mark = ","), n_states, unmatched
))

if (n_states != 51) {
  warning(sprintf("Expected 51 jurisdictions (50 states + DC), got %d", n_states))
}
if (unmatched > 0) {
  warning(sprintf("%d rows could not be matched to a state abbreviation", unmatched))
}

# ── Cache ──────────────────────────────────────────────────────────────────────

dir.create("temp", showWarnings = FALSE)
saveRDS(lead_data, temp_path)
cat("Cached slim dataset to:", temp_path, "\n")
