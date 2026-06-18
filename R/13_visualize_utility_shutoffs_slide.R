# ── RE-AMP utility-level shutoffs slide graphics ─────────────────────────────
# Two charts for the utility-level shutoffs slide:
#   Figure 1 — Named hero: 8 RE-AMP electric utilities with most shutoffs,
#               bars split into reconnected vs. not-reconnected
#   Figure 2 — Ownership panel: IOU / municipal / cooperative on three metrics
#               (share of shutoffs, rate per 100 customers, % not reconnected)
# Electric utilities only. Company-level aggregation for the hero (multi-state
# utilities collapse to one bar). Headline/subhead/footnote are live text in Slides.

library(tidyverse)
library(scales)
library(eeptheme)

# Register the eeptheme body font (Inter) for brand-consistent typography.
# Prefer the package helper; if its Google Fonts fetch fails (e.g. offline),
# register Inter from local system files; otherwise fall back to system sans.
body_font <- tryCatch({
  eep_fonts_setup()
  showtext::showtext_auto()
  showtext::showtext_opts(dpi = 300)
  eep_font_body
}, error = function(e) {
  inter <- sysfonts::font_files() %>% filter(family == "Inter")
  if (nrow(inter) > 0) {
    sysfonts::font_add(
      family  = "Inter",
      regular = file.path(inter$path[1], inter$file[inter$face == "Regular"][1])
    )
    showtext::showtext_auto()
    showtext::showtext_opts(dpi = 300)
    "Inter"
  } else {
    "sans"
  }
})

cat("Using body font:", body_font, "\n")

date_prefix <- format(Sys.Date(), "%d-%m-%Y")

# Color tokens
DARK  <- "#E07B39"   # not reconnected — focus-orange (matches R/10)
LIGHT <- "#F4C9AC"   # reconnected — light tint (matches R/10)
INK   <- "#1C3D5A"   # value labels
GREY  <- "#53606E"   # secondary text
FAINT <- "#8A929B"   # column headers / hints
DEEP  <- "#993C1D"   # % not reconnected metric accent (matches R/11)

# ── Inputs ────────────────────────────────────────────────────────────────────

rankings_path <- paste0("outputs/", date_prefix, "-us-utility-shutoffs-rankings.csv")
own_path      <- paste0("outputs/", date_prefix, "-ownership-shutoffs-summary.csv")

dir.create("plots", showWarnings = FALSE)

# ── Figure 1 data prep ────────────────────────────────────────────────────────

# Strip state suffixes so multi-state utilities collapse to a single company key.
# Handles " - (IN)" and " - MN" patterns; "Northern States Power Co - Minnesota"
# stays as-is (full state name) and gets a display-name recode below.
norm_name <- function(n) n %>%
  str_remove("\\s*-\\s*\\([A-Z]{2}\\)\\s*$") %>%
  str_remove("\\s*-\\s*[A-Z]{2}\\s*$") %>%
  str_trim()

comp <- read.csv(rankings_path) %>%
  filter(is_reamp, energy_type == "electric") %>%
  mutate(co = norm_name(utility_name)) %>%
  group_by(co) %>%
  summarise(
    ownership     = first(ownership),
    states        = paste(sort(unique(state)), collapse = "·"),
    customers     = sum(customer_count),
    shutoffs      = sum(shutoffs),
    reconnections = sum(reconnections)
  ) %>%
  ungroup() %>%
  mutate(
    not_recon     = shutoffs - reconnections,
    pct_not_recon = not_recon / shutoffs * 100,
    rate100       = shutoffs / customers * 100
  )

total_e <- sum(comp$shutoffs)   # expect 1,419,333
cat("total_e:", total_e, "\n")

top8 <- comp %>% slice_max(shutoffs, n = 8)

print(top8 %>% select(co, states, shutoffs, rate100, pct_not_recon))
cat("top8 share:", round(sum(top8$shutoffs) / total_e * 100, 1), "%\n")

# Clean display labels; two-line for multi-state utilities
top8 <- top8 %>%
  mutate(
    display = case_when(
      co == "Northern States Power Co - Minnesota" ~ "Northern States Power\n(Xcel, MN·ND)",
      co == "Indiana Michigan Power Co"            ~ "Indiana Michigan\nPower (IN·MI)",
      TRUE ~ co
    ),
    label = fct_reorder(display, shutoffs)
  )

# Long format for stacked bars; factor levels ensure light segment starts at 0
long1 <- top8 %>%
  select(label, reconnections, not_recon) %>%
  rename(reconnected = reconnections, not_reconnected = not_recon) %>%
  pivot_longer(c(reconnected, not_reconnected), names_to = "segment", values_to = "val") %>%
  mutate(segment = factor(segment, levels = c("reconnected", "not_reconnected")))

# ── Figure 1 chart ────────────────────────────────────────────────────────────

p1 <- ggplot(long1, aes(x = val, y = label, fill = segment)) +
  geom_col(width = 0.66) +
  geom_text(
    data    = top8,
    mapping = aes(
      x     = shutoffs,
      y     = label,
      label = paste0(round(shutoffs / 1000), "K · ", round(pct_not_recon), "% off")
    ),
    inherit.aes = FALSE,
    hjust = -0.08, color = INK, family = body_font, size = 3.2
  ) +
  scale_fill_manual(
    values = c(reconnected = LIGHT, not_reconnected = DARK),
    breaks = c("reconnected", "not_reconnected"),
    labels = c("later reconnected", "not reconnected"),
    name   = NULL
  ) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.32))) +
  coord_cartesian(clip = "off") +
  labs(subtitle = "Electric shutoffs — customers reconnected vs. still off") +
  theme_eep_slide(grid_lines = "none", axis_lines = "none") +
  theme(
    legend.position      = "top",
    legend.location      = "plot",
    legend.justification = "left",
    legend.direction     = "horizontal",
    legend.text          = element_text(size = 9, family = body_font, color = INK),
    legend.key.size      = unit(0.45, "cm"),
    axis.title           = element_blank(),
    axis.text.x          = element_blank(),
    axis.ticks           = element_blank(),
    panel.border         = element_blank(),
    panel.grid           = element_blank(),
    axis.text.y          = element_text(size = 9, family = body_font, color = INK),
    plot.subtitle        = element_text(size = 9, color = FAINT, family = body_font),
    plot.margin          = margin(6, 10, 4, 6)
  )

# ── Figure 2 data prep ────────────────────────────────────────────────────────

own_raw <- read.csv(own_path) %>%
  filter(scope == "reamp", energy_type == "electric")

# Denominator includes Political Subdivision so shares sum to 100 %
total_e_own <- sum(own_raw$total_shutoffs)   # expect 1,419,333
cat("total_e_own:", total_e_own, "\n")

own <- own_raw %>%
  filter(ownership != "Political Subdivision") %>%
  transmute(
    ownership,
    `Share of shutoffs`      = total_shutoffs / total_e_own * 100,
    `Rate per 100 customers` = shutoff_rate * 100,
    `% not reconnected`      = pct_not_reconnected
  ) %>%
  mutate(
    ownership = factor(ownership, levels = c("Cooperative", "Municipal", "Investor Owned"))
  )

print(own)   # verify: IOU 81.1/5.5/17.8 ; Muni 9.0/9.7/9.3 ; Coop 9.9/5.3/8.0

own_long <- own %>%
  pivot_longer(-ownership, names_to = "metric", values_to = "value") %>%
  mutate(
    metric = factor(
      metric,
      levels = c("Share of shutoffs", "Rate per 100 customers", "% not reconnected")
    ),
    label = case_when(
      metric == "Rate per 100 customers" ~ number(value, accuracy = 0.1),
      TRUE                               ~ paste0(round(value), "%")
    ),
    fill_col = case_when(
      metric == "Share of shutoffs"      ~ DARK,
      metric == "Rate per 100 customers" ~ FAINT,
      metric == "% not reconnected"      ~ DEEP
    )
  )

# ── Figure 2 chart ────────────────────────────────────────────────────────────

p2 <- ggplot(own_long, aes(x = value, y = ownership, fill = fill_col)) +
  geom_col(width = 0.62) +
  geom_text(
    aes(label = label),
    hjust = -0.15, color = INK, family = body_font, size = 3.2
  ) +
  scale_fill_identity(guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.32))) +
  facet_wrap(~ metric, scales = "free_x", ncol = 1) +
  theme_eep_slide(grid_lines = "none", axis_lines = "none") +
  theme(
    axis.title   = element_blank(),
    axis.text.x  = element_blank(),
    axis.ticks   = element_blank(),
    panel.border = element_blank(),
    panel.grid   = element_blank(),
    axis.text.y  = element_text(size = 9, family = body_font, color = INK),
    strip.text   = element_text(size = 9, hjust = 0, color = FAINT, family = body_font),
    plot.margin  = margin(6, 10, 4, 6)
  )

# ── Export ────────────────────────────────────────────────────────────────────
# Figure 1 — hero (matches R/10's exact full-width + callout sizing)

named_file         <- paste0("plots/", date_prefix, "-reamp-utility-shutoffs-named.png")
named_callout_file <- paste0("plots/", date_prefix, "-reamp-utility-shutoffs-named-callout.png")

ggsave(named_file,         p1, width = 6.3, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", named_file, "\n")

ggsave(named_callout_file, p1, width = 5.5, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", named_callout_file, "\n")

# Figure 2 — ownership panel (3-facet vertical stack; narrower than full-width)

panel_file      <- paste0("plots/", date_prefix, "-reamp-ownership-shutoffs-panel.png")
panel_wide_file <- paste0("plots/", date_prefix, "-reamp-ownership-shutoffs-panel-wide.png")

ggsave(panel_file,      p2, width = 3.6, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", panel_file, "\n")

ggsave(panel_wide_file, p2, width = 4.8, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", panel_wide_file, "\n")
