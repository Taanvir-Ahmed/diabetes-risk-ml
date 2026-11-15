# 08_decision_curve.R
# Decision curve analysis: is it useful to use the model to decide who gets
# an HbA1c test?
# For a risk threshold t (test everyone with predicted risk >= t):
#   net benefit = TP/n - FP/n * t / (1 - t)
# The weight t/(1-t) says how many unnecessary tests we accept for one found
# case. At t = 5% we accept 19 unnecessary tests per case found.
# The model is compared with "test everyone" and "test no one".
# Output: output/decision_curve.csv, output/screening_table.csv,
#         figures/fig7_decision_curve.png

source("R/00_setup.R")
preds <- readRDS("data/processed/predictions.rds")
test <- filter(preds, set == "test")
y <- test$undiag_dm
n <- length(y)
thresholds <- seq(0.01, 0.25, by = 0.005)

net_benefit <- function(p, t) {
  tp <- sum(p >= t & y == 1); fp <- sum(p >= t & y == 0)
  tp / n - fp / n * t / (1 - t)
}

dca <- bind_rows(
  lapply(names(model_cols), function(m)
    tibble(strategy = m, threshold = thresholds,
           net_benefit = sapply(thresholds, function(t) net_benefit(test[[m]], t)))),
  tibble(strategy = "Test everyone", threshold = thresholds,
         net_benefit = mean(y) - (1 - mean(y)) * thresholds / (1 - thresholds)),
  tibble(strategy = "Test no one", threshold = thresholds, net_benefit = 0)
)
write.csv(mutate(dca, net_benefit = round(net_benefit, 5)),
          "output/decision_curve.csv", row.names = FALSE)

# What happens at a few thresholds with the logistic model, per 1,000 people
screen <- bind_rows(lapply(c(0.02, 0.03, 0.05, 0.10), function(t) {
  p <- test$Logistic
  tibble(threshold = t,
         tested_per_1000 = round(1000 * mean(p >= t)),
         cases_found_per_1000 = round(1000 * mean(p >= t & y == 1), 1),
         cases_missed_per_1000 = round(1000 * mean(p < t & y == 1), 1),
         share_of_cases_found = round(mean(p[y == 1] >= t), 3),
         tests_per_case_found = round(sum(p >= t) / sum(p >= t & y == 1), 1))
}))
write.csv(screen, "output/screening_table.csv", row.names = FALSE)
print(screen)

# ---- Figure 7 ----------------------------------------------------------------
lv <- c(names(model_cols), "Test everyone", "Test no one")
plot_df <- dca |> mutate(strategy = factor(strategy, levels = lv))
p7 <- ggplot(plot_df, aes(threshold, net_benefit, colour = strategy,
                          linetype = strategy)) +
  geom_line(linewidth = 0.7) +
  scale_colour_manual(values = c(model_cols, "Test everyone" = "grey45",
                                 "Test no one" = "black"), name = NULL) +
  scale_linetype_manual(values = c("solid", "dashed", "dotdash", "longdash",
                                   "dotted", "solid"), name = NULL) +
  scale_x_continuous(labels = percent) +
  coord_cartesian(ylim = c(-0.005, mean(y) - 0.005)) +
  guides(colour = guide_legend(nrow = 2), linetype = guide_legend(nrow = 2)) +
  labs(title = "Decision curve: net benefit of testing by predicted risk",
       x = "Risk threshold for HbA1c testing",
       y = "Net benefit (true cases found per person)")
save_fig(p7, "fig7_decision_curve.png", w = 7, h = 5)
