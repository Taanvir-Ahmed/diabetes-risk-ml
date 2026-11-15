# 05_conformal.R
# Conformal prediction: for each person, a prediction SET that should contain
# the true answer (diabetes yes/no) at least 90% of the time.
#
# Idea in short:
#   1. Nonconformity score = 1 - predicted probability of the TRUE class.
#      A large score means the model was surprised.
#   2. On the calibration set (not used for fitting), find the score q that
#      90% of people stay under.
#   3. For a new person, put a class in the set if its score would be <= q.
# "Standard" conformal uses one q for everybody. "Class-conditional"
# (Mondrian) conformal uses a separate q for people with and without diabetes,
# so that coverage is 90% in both groups. This matters when the outcome is rare.
#
# Output: output/conformal_coverage.csv, output/conformal_sets.csv,
#         output/conformal_thresholds.csv, figures/fig3_conformal.png

source("R/00_setup.R")
preds <- readRDS("data/processed/predictions.rds")
calib <- filter(preds, set == "calib")
test  <- filter(preds, set == "test")

alpha <- 0.10
models_used <- c("Logistic", "XGBoost")

conf_q <- function(scores, alpha) {
  n <- length(scores)
  sort(scores)[min(n, ceiling((n + 1) * (1 - alpha)))]
}

make_sets <- function(p, q0, q1) {
  # q0: threshold for the "No" class, q1: threshold for the "Yes" class
  in_no  <- p <= q0            # score for "No"  = 1 - (1 - p) = p
  in_yes <- (1 - p) <= q1      # score for "Yes" = 1 - p
  case_when(in_no & in_yes ~ "{No, Yes}: uncertain",
            in_no ~ "{No}",
            in_yes ~ "{Yes}",
            TRUE ~ "Empty set")
}

covers <- function(set, y) {
  (y == 0 & grepl("No", set)) | (y == 1 & grepl("Yes", set))
}

res <- list(); thr <- list()
for (m in models_used) {
  pc <- calib[[m]]; yc <- calib$undiag_dm
  score <- ifelse(yc == 1, 1 - pc, pc)

  q_all <- conf_q(score, alpha)
  q_no  <- conf_q(score[yc == 0], alpha)
  q_yes <- conf_q(score[yc == 1], alpha)
  thr[[m]] <- tibble(model = m, method = c("Standard", "Class-conditional"),
                     threshold_no = c(q_all, q_no), threshold_yes = c(q_all, q_yes),
                     no_in_set_if_risk_below = threshold_no,
                     yes_in_set_if_risk_above = 1 - threshold_yes)

  for (meth in c("Standard", "Class-conditional")) {
    s <- if (meth == "Standard") make_sets(test[[m]], q_all, q_all)
         else make_sets(test[[m]], q_no, q_yes)
    res[[paste(m, meth)]] <- test |>
      select(SEQN, undiag_dm, sex, age_group, ethnicity) |>
      mutate(model = m, method = meth, p = test[[m]], set = s,
             covered = covers(s, undiag_dm))
  }
}
res <- bind_rows(res)
thr <- bind_rows(thr) |> mutate(across(where(is.numeric), ~ round(.x, 4)))
write.csv(thr, "output/conformal_thresholds.csv", row.names = FALSE)

coverage <- res |>
  mutate(group = ifelse(undiag_dm == 1, "With diabetes", "Without diabetes")) |>
  bind_rows(mutate(res, group = "All")) |>
  group_by(model, method, group) |>
  summarise(n = n(), coverage = mean(covered), .groups = "drop") |>
  mutate(lower = coverage - 1.96 * sqrt(coverage * (1 - coverage) / n),
         upper = pmin(coverage + 1.96 * sqrt(coverage * (1 - coverage) / n), 1))
write.csv(mutate(coverage, across(coverage:upper, ~ round(.x, 3))),
          "output/conformal_coverage.csv", row.names = FALSE)
print(coverage)

set_sizes <- res |>
  count(model, method, set, undiag_dm) |>
  pivot_wider(names_from = undiag_dm, values_from = n, values_fill = 0,
              names_prefix = "y") |>
  rename(without_diabetes = y0, with_diabetes = y1) |>
  mutate(total = without_diabetes + with_diabetes)
write.csv(set_sizes, "output/conformal_sets.csv", row.names = FALSE)
print(set_sizes)

# Coverage by subgroup (class-conditional, logistic) for the fairness section
sub_cov <- res |>
  filter(model == "Logistic", method == "Class-conditional") |>
  pivot_longer(c(sex, age_group, ethnicity), names_to = "variable",
               values_to = "level") |>
  group_by(variable, level, undiag_dm) |>
  summarise(n = n(), coverage = round(mean(covered), 3), .groups = "drop")
write.csv(sub_cov, "output/conformal_coverage_subgroups.csv", row.names = FALSE)

# ---- Figure 3 ----------------------------------------------------------------
cov_plot <- coverage |>
  filter(model == "Logistic", group != "All") |>
  mutate(method = factor(method, levels = c("Standard", "Class-conditional")))

pa <- ggplot(cov_plot, aes(group, coverage, colour = method, shape = method)) +
  geom_hline(yintercept = 1 - alpha, linetype = "dashed", colour = "grey40") +
  geom_pointrange(aes(ymin = lower, ymax = upper),
                  position = position_dodge(width = 0.5), size = 0.5) +
  scale_colour_manual(values = c("#eb6834", "#2a78d6"), name = NULL) +
  scale_shape_manual(values = c(17, 16), name = NULL) +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  annotate("text", x = 0.5, y = 0.93, label = "target 90%", hjust = 0,
           size = 3, colour = "grey30") +
  labs(title = "A. Does the set contain the true answer?",
       x = NULL, y = "Coverage on the test set")

set_levels <- c("{No}", "{No, Yes}: uncertain", "{Yes}", "Empty set")
set_plot <- res |>
  filter(model == "Logistic", method == "Class-conditional") |>
  mutate(risk_group = cut(p, c(0, 0.01, 0.02, 0.05, 0.10, 0.20, 1),
                          labels = c("<1%", "1-2%", "2-5%", "5-10%", "10-20%", ">20%")),
         set = factor(set, levels = set_levels)) |>
  count(risk_group, set)

pb <- ggplot(set_plot, aes(risk_group, n, fill = set)) +
  geom_col(width = 0.7, colour = "white", linewidth = 0.3) +
  scale_fill_manual(values = c("{No}" = "#86b6ef", "{No, Yes}: uncertain" = "#b9b8b0",
                               "{Yes}" = "#d03b3b", "Empty set" = "black"),
                    drop = TRUE, name = NULL) +
  labs(title = "B. Class-conditional sets by predicted risk",
       x = "Predicted risk (logistic model)", y = "Number of test-set people")

p3 <- pa + pb + plot_layout(widths = c(1, 1.4)) &
  theme(legend.position = "bottom")
save_fig(p3, "fig3_conformal.png", w = 10, h = 5)
