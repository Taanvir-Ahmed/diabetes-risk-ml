# 06_fairness.R
# Does the model work equally well for men and women, young and old, and
# different ethnic groups? For each subgroup in the test set we compute:
#   AUC   - can the model rank people with diabetes above people without?
#   O/E   - observed cases / expected cases (sum of predicted risks).
#           1 is perfect, >1 means the model under-predicts risk in the group.
#   Sensitivity at a 5% risk threshold - share of cases the model would flag.
# Output: output/fairness.csv, figures/fig4_fairness.png

source("R/00_setup.R")
preds <- readRDS("data/processed/predictions.rds")
test <- filter(preds, set == "test")
models_used <- c("Logistic", "Boosting")
threshold <- 0.05

# Fast AUC (Mann-Whitney formula), same result as pROC
fast_auc <- function(y, p) {
  r <- rank(p)
  n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

group_measures <- function(y, p) {
  c(auc = fast_auc(y, p),
    oe = sum(y) / sum(p),
    sens = mean(p[y == 1] >= threshold),
    flagged = mean(p >= threshold))
}

long <- test |>
  mutate(across(c(sex, age_group, ethnicity), as.character)) |>
  pivot_longer(c(sex, age_group, ethnicity), names_to = "variable",
               values_to = "level")

out <- list()
for (m in models_used) {
  for (g in unique(paste(long$variable, long$level, sep = "|"))) {
    v <- strsplit(g, "\\|")[[1]]
    sub <- filter(long, variable == v[1], level == v[2])
    y <- sub$undiag_dm; p <- sub[[m]]
    est <- group_measures(y, p)
    boot <- replicate(n_boot, {
      i <- sample(length(y), replace = TRUE)
      if (sum(y[i]) == 0) return(rep(NA, 4))   # no cases in this resample
      group_measures(y[i], p[i])
    })
    out[[paste(m, g)]] <- tibble(
      model = m, variable = v[1], level = v[2], n = length(y), cases = sum(y),
      measure = names(est), estimate = est,
      lower = apply(boot, 1, quantile, 0.025, na.rm = TRUE),
      upper = apply(boot, 1, quantile, 0.975, na.rm = TRUE))
  }
}
fair <- bind_rows(out) |> mutate(across(estimate:upper, ~ round(.x, 3)))
write.csv(fair, "output/fairness.csv", row.names = FALSE)

fair |>
  filter(model == "Logistic") |>
  select(variable, level, n, cases, measure, estimate) |>
  pivot_wider(names_from = measure, values_from = estimate) |>
  print(n = 30)

# ---- Figure 4 ----------------------------------------------------------------
lvl <- c("Male", "Female", "20-39", "40-59", "60-79",
         "White", "Black", "Hispanic", "Asian", "Other")
plot_df <- fair |>
  filter(measure %in% c("auc", "oe")) |>
  mutate(level = factor(level, levels = rev(lvl)),
         variable = factor(variable, levels = c("sex", "age_group", "ethnicity"),
                           labels = c("Sex", "Age", "Ethnicity")),
         measure = factor(measure, levels = c("auc", "oe"),
                          labels = c("AUC", "Observed / expected cases")),
         model = factor(model, levels = models_used))

ref <- tibble(measure = factor(c("AUC", "Observed / expected cases"),
                               levels = levels(plot_df$measure)),
              x = c(0.5, 1))

p4 <- ggplot(plot_df, aes(estimate, level, colour = model, shape = model)) +
  geom_vline(data = ref, aes(xintercept = x), linetype = "dashed", colour = "grey50") +
  geom_pointrange(aes(xmin = lower, xmax = upper),
                  position = position_dodge(width = 0.6), size = 0.35) +
  facet_grid(variable ~ measure, scales = "free", space = "free_y") +
  scale_colour_manual(values = model_cols[models_used], name = NULL) +
  scale_shape_manual(values = c(16, 17), name = NULL) +
  labs(title = "Performance by subgroup on the test set (95% bootstrap CI)",
       x = NULL, y = NULL) +
  theme(strip.text.y = element_text(angle = 0))
save_fig(p4, "fig4_fairness.png", w = 8.5, h = 6)
