# ── RE-AMP utility profits slide graphic ─────────────────────────────────────
# Horizontal ranked bar: top 10 RE-AMP IOUs by 2025 profit ($ millions),
# each labeled with the profit value and a right-side growth-vs-2021 column.
# Exported as full-width (9.0 × 3.3 in) and callout (6.4 × 3.3 in) PNGs.

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
HOT  <- "#E07B39"   # profit bars (deck focus-orange)
UP   <- "#993C1D"   # growth up
DOWN <- "#888780"   # growth down
NA_C <- "#B4B2A9"   # no 2021 baseline
INK  <- "#1C3D5A"   # profit value labels
FAINT <- "#8A929B"  # "vs '21" column header / subtitle

# ── Input ─────────────────────────────────────────────────────────────────────

profits_path <- paste0("outputs/", date_prefix, "-reamp-utility-profits-summary.csv")
prof <- read.csv(profits_path)

dir.create("plots", showWarnings = FALSE)

# ── Wrangle — top 10 + display labels ─────────────────────────────────────────

name_lookup <- c(
  "Xcel (electric subsidiaries)"      = "Xcel Energy",
  "DTE Energy (Electric-only)"        = "DTE Energy",
  "ComEd"                             = "ComEd",
  "Consumers Energy"                  = "Consumers Energy",
  "Midamerican"                       = "MidAmerican Energy",
  "CenterPoint"                       = "CenterPoint",
  "Ameren Illinois (combined G&E)"    = "Ameren Illinois",
  "Wisconsin Electric"                = "We Energies",
  "Northern Indiana Public Service Co.*" = "NIPSCO",
  "Evergy Kansas Central"             = "Evergy Kansas Central"
)

parent_lookup <- c(
  "Xcel Energy"          = NA_character_,
  "DTE Energy"           = NA_character_,
  "ComEd"                = "Exelon",
  "Consumers Energy"     = "CMS Energy",
  "MidAmerican Energy"   = "Berkshire Hathaway Energy",
  "CenterPoint"          = "Black Hills Corp.",
  "Ameren Illinois"      = NA_character_,
  "We Energies"          = "WEC Energy",
  "NIPSCO"               = "NiSource",
  "Evergy Kansas Central" = "Evergy"
)

top <- prof %>%
  arrange(desc(profit_2025_millions)) %>%
  slice_head(n = 10) %>%
  mutate(
    name   = recode(utility, !!!name_lookup),
    parent = unname(parent_lookup[name]),
    disp   = ifelse(is.na(parent), name, paste0(name, " (", parent, ")")),
    growth = (profit_change_ratio - 1) * 100,
    grw_col = case_when(
      is.na(growth) ~ "na",
      growth > 0    ~ "up",
      TRUE          ~ "down"
    ),
    grw_label = case_when(
      is.na(growth) ~ "—",
      growth < 0    ~ paste0("−", round(abs(growth)), "%"),
      TRUE          ~ paste0("+", round(growth), "%")
    ),
    disp = fct_reorder(disp, profit_2025_millions)
  )

# ── Verification print ─────────────────────────────────────────────────────────

print(top %>% select(disp, profit_2025_millions, growth))

total   <- round(sum(prof$profit_2025_millions, na.rm = TRUE))
over_1b <- sum(prof$profit_2025_millions >= 1000, na.rm = TRUE)
cat("total:", total, "| over_1b:", over_1b, "| nrow:", nrow(prof), "\n")

# ── Chart ──────────────────────────────────────────────────────────────────────

x_grw <- max(top$profit_2025_millions) * 1.45

p <- ggplot(top, aes(x = profit_2025_millions, y = disp)) +
  geom_col(fill = HOT, width = 0.66) +
  geom_text(
    aes(
      x     = profit_2025_millions,
      label = comma(round(profit_2025_millions))
    ),
    hjust  = -0.12,
    size   = 3.3,
    color  = INK,
    family = body_font
  ) +
  geom_text(
    aes(
      x     = x_grw,
      label = grw_label,
      color = grw_col
    ),
    hjust  = 1,
    size   = 3.3,
    family = body_font
  ) +
  scale_color_manual(
    values = c(up = UP, down = DOWN, na = NA_C),
    guide  = "none"
  ) +
  annotate(
    "text",
    x = x_grw, y = 10.7,
    label  = "vs '21",
    hjust  = 1,
    size   = 3,
    color  = FAINT,
    family = body_font
  ) +
  coord_cartesian(xlim = c(0, x_grw), clip = "off") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.02))) +
  labs(subtitle = "2025 profit, $ millions") +
  theme_eep_slide(grid_lines = "none", axis_lines = "none") +
  theme(
    legend.position = "none",
    axis.title      = element_blank(),
    axis.text.x     = element_blank(),
    axis.ticks      = element_blank(),
    panel.border    = element_blank(),
    panel.grid      = element_blank(),
    axis.text.y     = element_text(size = 11, family = body_font, color = INK),
    plot.subtitle   = element_text(size = 9, family = body_font, color = FAINT),
    plot.margin     = margin(6, 12, 4, 6)
  )

# ── Export — two layouts ───────────────────────────────────────────────────────
# (a) full-width 9.0 × 3.3 in; (b) narrower callout variant 6.4 × 3.3 in

full_file    <- paste0("plots/", date_prefix, "-reamp-profits-figure.png")
callout_file <- paste0("plots/", date_prefix, "-reamp-profits-figure-callout.png")

ggsave(full_file,    p, width = 9.0, height = 3.3, units = "in", dpi = 300, bg = "white")
ggsave(callout_file, p, width = 6.4, height = 3.3, units = "in", dpi = 300, bg = "white")
cat("Written:", full_file, "\n", callout_file, "\n")
