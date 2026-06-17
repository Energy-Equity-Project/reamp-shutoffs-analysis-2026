# ── RE-AMP energy-insecurity slide graphics ─────────────────────────────────────
# Two-panel figure: (A) share of people energy insecure by state (10 RE-AMP states,
# ranked high→low) and (B) the three component hardships region-wide on the same
# x-scale. Exported as combined + two standalone high-resolution PNGs for a
# white-background Google Slides deck. Headline/subhead/footnote added live in Slides.
# Data source: Household Pulse Survey 2024 (not RECS).

library(tidyverse)
library(scales)
library(ggrepel)
library(eeptheme)
library(patchwork)

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
HOT <- "#E07B39"   # composite bars — matches focus_orange in slide 08
INK <- eep_navy    # "#002E55" — component bars + value labels

# ── Input ────────────────────────────────────────────────────────────────────────

ins_path <- paste0("outputs/", date_prefix, "-reamp-energy-insecurity-summary.csv")
ins <- read.csv(ins_path)

dir.create("plots", showWarnings = FALSE)

# ── Panel A — ranked composite bars ─────────────────────────────────────────────

compA <- ins %>%
  transmute(state, pct = pct_energy_insecure) %>%
  arrange(desc(pct))

print(compA)   # verify: IN 44.6 → MN 33.5

panelA <- ggplot(compA, aes(x = pct, y = fct_reorder(state, pct))) +
  geom_col(fill = HOT) +
  geom_text(
    aes(label = paste0(round(pct), "%")),
    hjust = -0.15, size = 3.4, color = INK, family = body_font
  ) +
  coord_cartesian(clip = "off") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = "Share of people who are energy insecure") +
  theme_eep_slide(grid_lines = "none", axis_lines = "none") +
  theme(
    axis.title       = element_blank(),
    axis.text.x      = element_blank(),
    axis.ticks.x     = element_blank(),
    axis.text.y      = element_text(size = 9, color = INK, family = body_font),
    plot.title       = element_text(size = 12, color = INK, family = body_font),
    plot.margin      = margin(6, 8, 4, 8)
  )

# ── Region-wide person-weighted totals ───────────────────────────────────────────

totals <- ins %>%
  mutate(persons = n_energy_insecure / (pct_energy_insecure / 100)) %>%
  summarise(
    persons   = sum(persons),
    n_insecure = sum(n_energy_insecure),
    n_forgo    = sum(n_forgo_needs),
    n_unable   = sum(n_unable_pay),
    n_unsafe   = sum(n_unsafe_temp)
  ) %>%
  mutate(
    pct_insecure = 100 * n_insecure / persons,
    pct_forgo    = 100 * n_forgo    / persons,
    pct_unable   = 100 * n_unable   / persons,
    pct_unsafe   = 100 * n_unsafe   / persons
  )

print(totals)   # verify ≈ 41 / 32 / 22 / 20 %, n_insecure ≈ 16.0M

# ── Panel B — component bars, same x-scale ───────────────────────────────────────

compB <- tibble::tribble(
  ~label,                      ~pct,
  "Going without necessities", totals$pct_forgo,
  "Unable to pay a bill",      totals$pct_unable,
  "Unsafe home temperature",   totals$pct_unsafe
)

panelB <- ggplot(compB, aes(x = pct, y = fct_reorder(label, pct))) +
  geom_col(fill = INK) +
  geom_text(
    aes(label = paste0(round(pct), "%")),
    hjust = -0.15, size = 3.4, color = INK, family = body_font
  ) +
  coord_cartesian(clip = "off") +
  scale_x_continuous(
    limits = c(0, max(compA$pct)),
    expand = expansion(mult = c(0, 0.12))
  ) +
  labs(
    title   = "How it shows up, region-wide",
    caption = "Same order in all ten states. People often live with more than one,\nso these overlap and don't sum to the total."
  ) +
  theme_eep_slide(grid_lines = "none", axis_lines = "none") +
  theme(
    axis.title       = element_blank(),
    axis.text.x      = element_blank(),
    axis.ticks.x     = element_blank(),
    axis.text.y      = element_text(size = 9, color = INK, family = body_font),
    plot.title       = element_text(size = 12, color = INK, family = body_font),
    plot.caption     = element_text(size = 7.5, color = INK, family = body_font,
                                    hjust = 0, lineheight = 1.2,
                                    margin = margin(t = 5, b = 4)),
    plot.margin      = margin(6, 8, 16, 8)
  )

# ── Compose ──────────────────────────────────────────────────────────────────────

insecurity_fig <- panelA + panelB + plot_layout(widths = c(1.3, 1))

# ── Export ───────────────────────────────────────────────────────────────────────

combined_file   <- paste0("plots/", date_prefix, "-reamp-insecurity-figure.png")
composite_file  <- paste0("plots/", date_prefix, "-reamp-insecurity-composite.png")
components_file <- paste0("plots/", date_prefix, "-reamp-insecurity-components.png")

ggsave(combined_file,   insecurity_fig, width = 9.2, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", combined_file, "\n")

ggsave(composite_file,  panelA,         width = 5.3, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", composite_file, "\n")

ggsave(components_file, panelB,         width = 3.6, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", components_file, "\n")
