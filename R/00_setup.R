# 00_setup.R
# Packages, settings and plot style used by all scripts.

pkgs <- c("haven", "dplyr", "tidyr", "ggplot2", "patchwork", "glmnet",
          "ranger", "gbm", "pROC", "survey", "scales")
missing_pkgs <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(missing_pkgs) > 0) {
  stop("Please install: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
  library(glmnet)
  library(ranger)
  library(gbm)
  library(pROC)
  library(survey)
  library(scales)
})

set.seed(2026)

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
dir.create("output", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

# Number of bootstrap samples for confidence intervals
n_boot <- 1000

# Colours (one per model, always in the same order)
model_cols <- c("Logistic" = "#2a78d6", "LASSO" = "#eb6834",
                "Random forest" = "#1baf7a", "Boosting" = "#eda100")

theme_set(
  theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major = element_line(colour = "grey90"),
          plot.title = element_text(face = "bold"),
          legend.position = "bottom",
          plot.background = element_rect(fill = "white", colour = NA))
)

save_fig <- function(p, file, w = 7, h = 5) {
  ggsave(file.path("figures", file), p, width = w, height = h, dpi = 200)
}
