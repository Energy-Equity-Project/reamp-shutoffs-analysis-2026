library(tidyverse)
library(scales)

date_prefix <- format(Sys.Date(), "%d-%m-%Y")
fpl_levels  <- c("0-100%", "100-150%", "150-200%", "200-400%", "400%+")

# ── Load outputs ───────────────────────────────────────────────────────────────

us_rankings        <- read.csv(paste0("outputs/", date_prefix, "-us-state-burden-rankings.csv"))
reamp_state_summary <- read.csv(paste0("outputs/", date_prefix, "-reamp-state-energy-burden-summary.csv"))
reamp_fpl_summary   <- read.csv(paste0("outputs/", date_prefix, "-reamp-fpl-energy-burden-summary.csv")) %>%
  mutate(fpl150 = factor(fpl150, levels = fpl_levels, ordered = TRUE))

dir.create("plots", showWarnings = FALSE)

# ── Plot 1: US state rankings ──────────────────────────────────────────────────
# Bar chart of all 51 jurisdictions ranked by % with unaffordable burden;
# RE-AMP states highlighted in dark blue.

p1_data <- us_rankings %>%
  arrange(rank) %>%
  mutate(
    state   = factor(state, levels = rev(state)),
    is_reamp = as.logical(is_reamp)
  )

p1 <- ggplot(p1_data, aes(x = state, y = pct_unaffordable, fill = is_reamp)) +
  geom_col() +
  coord_flip() +
  scale_fill_manual(
    values = c("TRUE" = "#002e55", "FALSE" = "#b0c4de"),
    labels = c("TRUE" = "RE-AMP state", "FALSE" = "Other"),
    name   = NULL
  ) +
  scale_y_continuous(
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title    = "Share of Households with Unaffordable Energy Burden (>6%)",
    subtitle = "All 50 states + DC  |  DOE LEAD 2022",
    x        = NULL,
    y        = "% of Households"
  ) +
  theme_bw() +
  theme(
    plot.title    = element_text(face = "bold", size = 13),
    legend.position = "bottom",
    axis.text.y   = element_text(size = 7)
  )

ggsave(
  paste0("plots/", date_prefix, "-us-state-burden-rankings.jpeg"),
  plot = p1, width = 10, height = 14, dpi = 300
)
cat("Written: plots/", date_prefix, "-us-state-burden-rankings.jpeg\n", sep = "")

# ── Plot 2: % unaffordable by FPL bracket, faceted by RE-AMP state ────────────

p2 <- ggplot(reamp_fpl_summary, aes(x = fpl150, y = pct_within_bracket)) +
  geom_col(fill = "#002e55", alpha = 0.9) +
  geom_text(
    aes(label = paste0(round(pct_within_bracket, 0), "%")),
    vjust = -0.4, size = 2.6
  ) +
  facet_wrap(~state, ncol = 5) +
  scale_y_continuous(
    labels  = function(x) paste0(x, "%"),
    expand  = expansion(mult = c(0, 0.18))
  ) +
  labs(
    title    = "Share of Households with Energy Burden >6% by FPL Bracket",
    subtitle = "RE-AMP states  |  DOE LEAD 2022",
    x        = "Federal Poverty Level",
    y        = "% of Households in Bracket"
  ) +
  theme_bw() +
  theme(
    plot.title   = element_text(face = "bold", size = 13),
    axis.text.x  = element_text(angle = 45, hjust = 1, size = 7),
    strip.text   = element_text(face = "bold")
  )

ggsave(
  paste0("plots/", date_prefix, "-reamp-fpl-unaffordable-share.jpeg"),
  plot = p2, width = 14, height = 7, dpi = 300
)
cat("Written: plots/", date_prefix, "-reamp-fpl-unaffordable-share.jpeg\n", sep = "")

# ── Plot 3: Weighted mean vs. weighted median burden — RE-AMP states ───────────

p3_data <- reamp_state_summary %>%
  pivot_longer(
    cols      = c(weighted_mean_burden, weighted_median_burden),
    names_to  = "measure",
    values_to = "burden"
  ) %>%
  mutate(
    burden_pct = 100 * burden,
    measure    = case_when(
      measure == "weighted_mean_burden"   ~ "Weighted Mean",
      measure == "weighted_median_burden" ~ "Weighted Median"
    )
  )

# Order states by mean burden (descending) for readability
state_order <- reamp_state_summary %>%
  arrange(desc(weighted_mean_burden)) %>%
  pull(state)

p3_data <- p3_data %>%
  mutate(state = factor(state, levels = rev(state_order)))

p3 <- ggplot(p3_data, aes(x = state, y = burden_pct, fill = measure)) +
  geom_col(position = "dodge") +
  geom_hline(yintercept = 6, color = "red", linetype = "dashed", linewidth = 0.8) +
  coord_flip() +
  annotate("text", x = 0.7, y = 6.3, label = "6% threshold", color = "red", size = 3, hjust = 0) +
  scale_fill_manual(
    values = c("Weighted Mean" = "#002e55", "Weighted Median" = "#4a90d9"),
    name   = NULL
  ) +
  scale_y_continuous(
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title    = "Weighted Mean vs. Median Energy Burden",
    subtitle = "RE-AMP states  |  DOE LEAD 2022",
    x        = NULL,
    y        = "Energy Burden"
  ) +
  theme_bw() +
  theme(
    plot.title      = element_text(face = "bold", size = 13),
    legend.position = "bottom"
  )

ggsave(
  paste0("plots/", date_prefix, "-reamp-mean-vs-median-burden.jpeg"),
  plot = p3, width = 10, height = 7, dpi = 300
)
cat("Written: plots/", date_prefix, "-reamp-mean-vs-median-burden.jpeg\n", sep = "")

cat("\nAll visualizations complete.\n")
