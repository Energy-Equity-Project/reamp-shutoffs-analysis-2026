library(tidyverse)

pulse_path <- "../../Cleaned_Data/us_census/household_pulse_survey/02-04-2026-pulse-energy-puf-harmonized.csv"
temp_path  <- "temp/pulse_2024_slim.rds"

cols_needed <- c("survey_wave", "survey_year", "state", "person_weight",
                 "energy", "hse_temp", "enrgy_bill")

cat("Reading harmonized Household Pulse Survey microdata...\n")

pulse_2024 <- read.csv(pulse_path) %>%
  filter(survey_year == 2024) %>%
  select(all_of(cols_needed))

# ── Verify ─────────────────────────────────────────────────────────────────────

n_cycles <- n_distinct(pulse_2024$survey_wave)
n_states <- n_distinct(pulse_2024$state)

cat(sprintf(
  "Loaded %s rows | %d distinct cycles | %d distinct states\n",
  format(nrow(pulse_2024), big.mark = ","), n_cycles, n_states
))
cat("Cycles present:", paste(sort(unique(pulse_2024$survey_wave)), collapse = ", "), "\n")
cat("States present:", paste(sort(unique(pulse_2024$state)), collapse = ", "), "\n")

if (n_cycles != 9) {
  warning(sprintf("Expected 9 cycles (cycle_01-cycle_09), got %d", n_cycles))
}
if (n_states != 51) {
  warning(sprintf("Expected 51 jurisdictions (50 states + DC), got %d", n_states))
}

# ── Cache ──────────────────────────────────────────────────────────────────────

dir.create("temp", showWarnings = FALSE)
saveRDS(pulse_2024, temp_path)
cat("Cached slim dataset to:", temp_path, "\n")
