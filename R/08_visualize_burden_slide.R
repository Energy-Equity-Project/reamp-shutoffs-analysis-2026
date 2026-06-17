# ── RE-AMP energy-burden slide graphics ────────────────────────────────────────
# Two slide-ready components, exported as separate high-resolution PNGs for a
# white-background pptx: (1) the "income cliff" descending bar chart and
# (2) the national-context ribbon. No title/subtitle/caption annotations — those
# are added in the deck. Colors: blue is primary (structure + context), orange is
# the secondary accent reserved for the at-risk focus (severe bands; RE-AMP dots).

library(tidyverse)
library(scales)
library(ggrepel)
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
fpl_levels  <- c("0-100%", "100-150%", "150-200%", "200-400%", "400%+")

# Color tokens — blue primary, orange/gold secondary accent
focus_orange <- "#E07B39"   # at-risk focus (severe bands, RE-AMP dots)
calm_blue    <- "#9DBAD6"   # receding "safe" / non-severe bands
navy         <- eep_navy    # "#002E55" — text and structure
tick_grey    <- "#C2CBD2"   # national distribution ticks

# ── Inputs (confirmed paths) ────────────────────────────────────────────────────

fpl_path      <- paste0("outputs/", date_prefix, "-reamp-fpl-energy-burden-summary.csv")
rankings_path <- paste0("outputs/", date_prefix, "-us-state-burden-rankings.csv")

fpl_raw      <- read.csv(fpl_path)
rankings_raw <- read.csv(rankings_path) %>%
  mutate(is_reamp = as.logical(is_reamp))

dir.create("plots", showWarnings = FALSE)

# ── Component A — hero cliff ─────────────────────────────────────────────────────
# Household-weighted regional rate per FPL band (pooled across the ten states).

cliff_data <- fpl_raw %>%
  mutate(fpl150 = factor(fpl150, levels = fpl_levels, ordered = TRUE)) %>%
  group_by(fpl150) %>%
  summarise(
    households       = sum(households),
    unaffordable     = sum(unaffordable_households),
    pct_unaffordable = 100 * unaffordable / households
  ) %>%
  ungroup() %>%
  mutate(
    severe   = fpl150 %in% c("0-100%", "100-150%", "150-200%"),
    bar_label = case_when(
      pct_unaffordable < 0.5 ~ "~0%",
      TRUE                   ~ paste0(round(pct_unaffordable), "%")
    )
  )

# Verification against the brief's expected band rates (99.4 / 89.0 / 64.1 / 5.9 / ~0)
print(cliff_data %>% select(fpl150, pct_unaffordable))

x_labels <- c(
  "0-100%"   = "Below poverty line\n0–100% FPL",
  "100-150%" = "Just above poverty\n100–150% FPL",
  "150-200%" = "Low income\n150–200% FPL",
  "200-400%" = "Moderate income\n200–400% FPL",
  "400%+"    = "Higher income\n400%+ FPL"
)

cliff_plot <- ggplot(cliff_data, aes(x = fpl150, y = pct_unaffordable, fill = severe)) +
  geom_col(width = 0.78) +
  geom_text(
    aes(label = bar_label),
    vjust = -0.45, family = body_font, fontface = "bold",
    size = 6, color = navy
  ) +
  scale_fill_manual(values = c(`TRUE` = focus_orange, `FALSE` = calm_blue), guide = "none") +
  scale_x_discrete(labels = x_labels, expand = expansion(add = 0.55)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.10))) +
  coord_cartesian(clip = "off") +
  theme_eep_slide(grid_lines = "none", axis_lines = "x") +
  theme(
    axis.title       = element_blank(),
    axis.text.y      = element_blank(),
    axis.text.x      = element_text(size = 15, color = navy, lineheight = 0.95),
    axis.ticks       = element_blank(),
    panel.border     = element_blank(),
    plot.margin      = margin(t = 8, r = 8, b = 4, l = 8)
  )

# ── Component B — national ribbon ────────────────────────────────────────────────
# Thin horizontal strip placing the ten RE-AMP states along the full national range.

nat_min <- min(rankings_raw$pct_unaffordable)   # ≈ 9.5  (UT)
nat_max <- max(rankings_raw$pct_unaffordable)   # ≈ 46.6 (ME)
nat_mid <- (nat_min + nat_max) / 2
reamp_dots <- filter(rankings_raw, is_reamp)

# Everything is positioned in data coordinates near the strip (no rendered axes),
# so the band stays compact regardless of theme base size.
ribbon_plot <- ggplot() +
  geom_point(
    data = rankings_raw, aes(x = pct_unaffordable, y = 0),
    shape = "|", size = 6, color = tick_grey, alpha = 0.6
  ) +
  geom_point(
    data = reamp_dots, aes(x = pct_unaffordable, y = 0),
    color = focus_orange, size = 3.2
  ) +
  geom_text_repel(
    data = reamp_dots,
    aes(x = pct_unaffordable, y = 0, label = paste0(state, " ", round(pct_unaffordable), "%")),
    nudge_y = 0.18, direction = "x", angle = 0,
    segment.size = 0.25, segment.color = navy, min.segment.length = 0,
    box.padding = 0.25, point.padding = 0.1, force = 1.4,
    size = 5, family = body_font, color = navy, seed = 42
  ) +
  # Endpoint labels just below the strip
  annotate("text", x = nat_min, y = -0.18, label = paste0(round(nat_min, 1), "% — lowest (Utah)"),
           hjust = 0, vjust = 1, size = 4.4, family = body_font, color = navy) +
  annotate("text", x = nat_max, y = -0.18, label = paste0(round(nat_max, 1), "% — highest (Maine)"),
           hjust = 1, vjust = 1, size = 4.4, family = body_font, color = navy) +
  # Descriptor centered below
  annotate("text", x = nat_mid, y = -0.42,
           label = "Where the region sits nationally — share of households, all 51 states",
           hjust = 0.5, vjust = 1, size = 4.4, family = body_font, color = navy) +
  scale_x_continuous(limits = c(nat_min, nat_max), expand = expansion(mult = 0.02)) +
  scale_y_continuous(limits = c(-0.5, 0.42)) +
  coord_cartesian(clip = "off") +
  theme_eep_slide(grid_lines = "none", axis_lines = "none") +
  theme(
    axis.title    = element_blank(),
    axis.text     = element_blank(),
    axis.ticks    = element_blank(),
    panel.border  = element_blank(),
    plot.margin   = margin(t = 6, r = 10, b = 4, l = 10)
  )

# ── Export — high-resolution PNGs, white background ──────────────────────────────
# Wide/flat assets sized to run the full content width of a 13.333 × 7.5 slide.
# Cliff: 12 × 3.2 in (3600 × 960 px). Ribbon: 12 × 1.5 in (3600 × 450 px).

cliff_file  <- paste0("plots/", date_prefix, "-reamp-burden-cliff.png")
ribbon_file <- paste0("plots/", date_prefix, "-reamp-burden-ribbon.png")

ggsave(cliff_file, cliff_plot, width = 12, height = 3.2, units = "in", dpi = 300, bg = "white")
cat("Written:", cliff_file, "\n")

ggsave(ribbon_file, ribbon_plot, width = 12, height = 1.5, units = "in", dpi = 300, bg = "white")
cat("Written:", ribbon_file, "\n")
