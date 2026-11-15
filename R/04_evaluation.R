# 04_evaluation.R
# Test-set performance: discrimination (AUC), calibration and Brier score,
# with bootstrap 95% confidence intervals.
# Output: output/performance.csv, figures/fig1_roc.png, figures/fig2_calibration.png

source("R/00_setup.R")
preds <- readRDS("data/processed/predictions.rds")
test <- filter(preds, set == "test")
mods <- names(model_cols)
y <- test$undiag_dm

logit <- function(p) { p <- pmin(pmax(p, 1e-6), 1 - 1e-6); log(p / (1 - p)) }

# All measures for one vector of predictions
measures <- function(y, p) {
  lp <- logit(p)
  c(auc = as.numeric(auc(y, p, quiet = TRUE)),
    brier = mean((p - y)^2),
    # calibration intercept: 0 is ideal (are predictions too high or too low on average?)
    cal_intercept = unname(coef(glm(y ~ offset(lp), family = binomial))[1]),
    # calibration slope: 1 is ideal (<1 means predictions are too extreme)
    cal_slope = unname(coef(glm(y ~ lp, family = binomial))[2]),
    mean_pred = mean(p),
    observed = mean(y))
}

point <- sapply(mods, function(m) measures(y, test[[m]]))

# Bootstrap: resample test-set people with replacement
boot <- replicate(n_boot, {
  i <- sample(nrow(test), replace = TRUE)
  sapply(mods, function(m) measures(y[i], test[[m]][i]))
}, simplify = "array")

perf <- bind_rows(lapply(mods, function(m) {
  tibble(model = m, measure = rownames(point), estimate = point[, m],
         lower = apply(boot[, m, ], 1, quantile, 0.025),
         upper = apply(boot[, m, ], 1, quantile, 0.975))
})) |>
  mutate(across(estimate:upper, ~ round(.x, 3)))
write.csv(perf, "output/performance.csv", row.names = FALSE)
print(filter(perf, measure %in% c("auc", "brier", "cal_intercept", "cal_slope")), n = 20)

# Is any model better than logistic regression? Bootstrap AUC difference.
auc_diff <- bind_rows(lapply(mods[-1], function(m) {
  dd <- boot["auc", m, ] - boot["auc", "Logistic", ]
  tibble(model = m, diff_vs_logistic = point["auc", m] - point["auc", "Logistic"],
         lower = quantile(dd, 0.025), upper = quantile(dd, 0.975))
})) |> mutate(across(-model, ~ round(.x, 3)))
write.csv(auc_diff, "output/auc_difference.csv", row.names = FALSE)
print(auc_diff)

# ---- Figure 1: ROC curves ----------------------------------------------------
roc_df <- bind_rows(lapply(mods, function(m) {
  r <- roc(y, test[[m]], quiet = TRUE)
  tibble(model = m, fpr = 1 - r$specificities, tpr = r$sensitivities)
})) |>
  mutate(model = factor(model, levels = mods)) |>
  arrange(model, fpr, tpr)

auc_lab <- perf |> filter(measure == "auc") |>
  mutate(label = sprintf("%s: %.2f (%.2f-%.2f)", model, estimate, lower, upper))
roc_df$model_lab <- factor(auc_lab$label[match(roc_df$model, auc_lab$model)],
                           levels = auc_lab$label)

p1 <- ggplot(roc_df, aes(fpr, tpr, colour = model_lab, linetype = model_lab)) +
  geom_abline(colour = "grey60", linetype = "dotted") +
  geom_step(linewidth = 0.7) +
  scale_colour_manual(values = unname(model_cols), name = "AUC (95% CI)") +
  scale_linetype_manual(values = c("solid", "dashed", "dotdash", "longdash"),
                        name = "AUC (95% CI)") +
  coord_equal() +
  guides(colour = guide_legend(ncol = 2), linetype = guide_legend(ncol = 2)) +
  labs(title = "ROC curves on the test set",
       x = "False positive rate (1 - specificity)",
       y = "True positive rate (sensitivity)")
save_fig(p1, "fig1_roc.png", w = 6.5, h = 6.5)

# ---- Figure 2: calibration -------------------------------------------------
# Group people into 10 groups by predicted risk and compare the mean predicted
# risk with the observed proportion in each group.
cal_df <- bind_rows(lapply(mods, function(m) {
  test |>
    mutate(p = .data[[m]], bin = ntile(p, 10)) |>
    group_by(bin) |>
    summarise(pred = mean(p), obs = mean(undiag_dm), n = n(), .groups = "drop") |>
    mutate(se = sqrt(pmax(obs * (1 - obs), 1e-4) / n),
           lower = pmax(obs - 1.96 * se, 0), upper = obs + 1.96 * se,
           model = m)
})) |> mutate(model = factor(model, levels = mods))

cal_lab <- perf |>
  filter(measure %in% c("cal_intercept", "cal_slope")) |>
  select(model, measure, estimate) |>
  pivot_wider(names_from = measure, values_from = estimate) |>
  mutate(label = sprintf("intercept %.2f\nslope %.2f", cal_intercept, cal_slope),
         model = factor(model, levels = mods))

lim <- max(c(cal_df$upper, cal_df$pred)) * 1.05
p2 <- ggplot(cal_df, aes(pred, obs)) +
  geom_abline(colour = "grey60", linetype = "dotted") +
  geom_errorbar(aes(ymin = lower, ymax = upper, colour = model), width = 0) +
  geom_line(aes(colour = model), linewidth = 0.5) +
  geom_point(aes(colour = model), size = 2.2) +
  geom_text(data = cal_lab, aes(x = 0, y = lim, label = label),
            hjust = 0, vjust = 1, size = 3, colour = "grey20") +
  facet_wrap(~model, nrow = 2) +
  scale_colour_manual(values = model_cols, guide = "none") +
  scale_x_continuous(labels = percent, limits = c(0, lim)) +
  scale_y_continuous(labels = percent, limits = c(0, lim)) +
  coord_equal() +
  labs(title = "Calibration on the test set (10 risk groups)",
       x = "Mean predicted risk", y = "Observed proportion with undiagnosed diabetes")
save_fig(p2, "fig2_calibration.png", w = 7, h = 7.5)
