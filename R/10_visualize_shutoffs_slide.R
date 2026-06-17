# ── RE-AMP shutoffs slide graphic ────────────────────────────────────────────────
# Split ranked bar chart: 10 RE-AMP states ranked by combined shutoff rate per 100
# customers. Each bar is split into a light "later reconnected" segment (from 0)
# and a dark "not reconnected" segment (at the tip), with a "% not rec." text
# column on the right. Exported as two high-resolution PNGs (full-width and
# narrower callout variant) for a white-background Google Slides deck.
# Headline/subhead/footnote are added as live text in Slides.

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
DARK  <- "#E07B39"   # not reconnected — eep focus-orange, matches slides 08/09
LIGHT <- "#F4C9AC"   # later reconnected — light tint of the same hue
INK   <- "#1C3D5A"   # rate labels
GREY  <- "#53606E"   # % not-reconnected column
FAINT <- "#8A929B"   # column header

# ── Input ────────────────────────────────────────────────────────────────────────

shut_path <- paste0("outputs/", date_prefix, "-reamp-shutoffs-summary.csv")
shut <- read.csv(shut_path)

dir.create("plots", showWarnings = FALSE)

# ── Bar data ─────────────────────────────────────────────────────────────────────

bars <- shut %>%
  transmute(
    state,
    rate            = combined_shutoff_rate * 100,
    not_reconnected = net_shutoff_rate * 100,
    reconnected     = (combined_shutoff_rate - net_shutoff_rate) * 100,
    pct_nr          = pct_not_reconnected,
    flag            = as.logical(any_quality_flag)
  ) %>%
  arrange(desc(rate)) %>%
  mutate(state_f = fct_reorder(state, rate))

print(bars %>% select(state, rate, pct_nr, flag))   # verify vs brief

# Factor levels: "reconnected" first so light segment starts at 0;
# "not_reconnected" second so dark segment lands at the tip.
long <- bars %>%
  select(state_f, reconnected, not_reconnected) %>%
  pivot_longer(c(reconnected, not_reconnected), names_to = "segment", values_to = "val") %>%
  mutate(segment = factor(segment, levels = c("reconnected", "not_reconnected")))

# ── Aggregate verification ───────────────────────────────────────────────────────

agg <- shut %>%
  summarise(
    total_shutoffs = sum(combined_shutoffs),
    pct_nr         = 100 * sum(net_shutoffs) / sum(combined_shutoffs)
  )
print(agg)   # ≈ 1.85M shutoffs, ≈ 18% not reconnected

# ── Chart ────────────────────────────────────────────────────────────────────────

n     <- nrow(bars)
x_pct <- max(bars$rate) + 3

p <- ggplot(long, aes(x = val, y = state_f, fill = segment)) +
  geom_col(width = 0.66) +
  geom_text(
    data        = bars,
    mapping     = aes(
      x     = rate + 0.2,
      y     = state_f,
      label = paste0(formatC(rate, format = "f", digits = 1), ifelse(flag, "*", ""))
    ),
    inherit.aes = FALSE,
    hjust = 0, color = INK, family = body_font, size = 3.4
  ) +
  geom_text(
    data        = bars,
    mapping     = aes(
      x     = x_pct,
      y     = state_f,
      label = paste0(round(pct_nr), "%")
    ),
    inherit.aes = FALSE,
    hjust = 1, color = GREY, family = body_font, size = 3.4
  ) +
  annotate(
    "text",
    x = x_pct, y = n + 0.85,
    label = "% not rec.", hjust = 1,
    color = FAINT, family = body_font, size = 3.4
  ) +
  scale_fill_manual(
    values = c(reconnected = LIGHT, not_reconnected = DARK),
    breaks = c("reconnected", "not_reconnected"),
    labels = c("later reconnected", "not reconnected"),
    name   = NULL
  ) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.02))) +
  coord_cartesian(xlim = c(0, x_pct), clip = "off") +
  labs(subtitle = "Shutoffs per 100 customers (electric + gas)") +
  theme_eep_slide(grid_lines = "none", axis_lines = "none") +
  theme(
    legend.position      = "top",
    legend.justification = "left",
    legend.direction     = "horizontal",
    legend.text          = element_text(size = 9, family = body_font, color = INK),
    legend.key.size      = unit(0.45, "cm"),
    axis.title           = element_blank(),
    axis.text.x          = element_blank(),
    axis.ticks           = element_blank(),
    panel.border         = element_blank(),
    panel.grid           = element_blank(),
    axis.text.y          = element_text(size = 10, family = body_font, color = INK),
    plot.subtitle        = element_text(size = 9, color = FAINT, family = body_font),
    plot.margin          = margin(6, 10, 4, 6)
  )

# ── Export — two layouts ─────────────────────────────────────────────────────────
# (a) full-width 9.0 × 3.3 in; (b) narrower callout variant 6.4 × 3.3 in

full_file    <- paste0("plots/", date_prefix, "-reamp-shutoffs-figure.png")
callout_file <- paste0("plots/", date_prefix, "-reamp-shutoffs-figure-callout.png")

ggsave(full_file,    p, width = 9.0, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", full_file, "\n")

ggsave(callout_file, p, width = 6.4, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", callout_file, "\n")
