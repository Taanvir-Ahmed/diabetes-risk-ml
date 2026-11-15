# 07_shap.R
# SHAP values: how much each predictor pushes one person's predicted risk up
# or down (on the log-odds scale), compared with an average person.
#   Logistic model: SHAP has an exact formula, beta * (x - mean of x).
#   Boosting model: estimated by Monte Carlo sampling of feature orders
#   (Strumbelj and Kononenko, 2014), because there is no simple formula.
# Output: output/shap_importance.csv, figures/fig5_shap_importance.png,
#         figures/fig6_shap_dependence.png

source("R/00_setup.R")
obj <- readRDS("data/processed/models.rds")
train <- obj$train; test <- obj$test; feats <- obj$predictors
n_explain <- 500       # number of test-set people to explain
n_iter <- 100          # Monte Carlo samples per person and feature

explain <- test[sample(nrow(test), n_explain), ]

# ---- Logistic: exact SHAP ------------------------------------------------------
lr <- obj$models$Logistic
X_tr <- model.matrix(obj$formula, train)[, -1]
X_ex <- model.matrix(obj$formula, explain)[, -1]
b <- coef(lr)[-1]
contrib <- sweep(sweep(X_ex, 2, colMeans(X_tr)), 2, b, "*")
# add up dummy columns that belong to the same variable (e.g. 4 ethnicity dummies)
col_var <- sapply(colnames(X_ex), function(cn) feats[startsWith(cn, feats)][1])
shap_lr <- sapply(feats, function(v) rowSums(contrib[, col_var == v, drop = FALSE]))

# ---- Boosting: Monte Carlo SHAP --------------------------------------------------
gb <- obj$models$Boosting
f_link <- function(nd) predict(gb, nd, n.trees = gb$n.trees, type = "link")

shap_gb <- matrix(0, n_explain, length(feats), dimnames = list(NULL, feats))
rows_x <- rep(seq_len(n_explain), each = n_iter)
for (j in seq_along(feats)) {
  z <- train[sample(nrow(train), length(rows_x), replace = TRUE), feats]
  x <- explain[rows_x, feats]
  # random feature order: feature k comes before j if its random number is smaller
  u <- matrix(runif(length(rows_x) * length(feats)), ncol = length(feats))
  before_j <- u < u[, j]
  x_plus <- z; x_minus <- z
  for (k in seq_along(feats)) {
    take_x <- before_j[, k]
    x_plus[take_x, k] <- x[take_x, k]
    x_minus[take_x, k] <- x[take_x, k]
  }
  x_plus[, j] <- x[, j]          # with feature j from the person
  diff <- f_link(x_plus) - f_link(x_minus)
  shap_gb[, j] <- tapply(diff, rows_x, mean)
  cat("SHAP done for", feats[j], "\n")
}

# Check: SHAP values should add up to f(x) - average f
check <- cor(rowSums(shap_gb), f_link(explain) - mean(f_link(train)))
cat("Correlation of summed SHAP with prediction:", round(check, 3), "\n")

# ---- Importance table ----------------------------------------------------------
labels <- c(age = "Age", sex = "Sex", ethnicity = "Ethnicity", education = "Education",
            income = "Income", bmi = "BMI", waist = "Waist", sbp = "Systolic BP",
            dbp = "Diastolic BP", total_chol = "Total cholesterol", hdl = "HDL",
            smoking = "Smoking", active = "Physical activity",
            family_history = "Family history")
imp <- tibble(variable = feats, label = labels[feats],
              Logistic = colMeans(abs(shap_lr)), Boosting = colMeans(abs(shap_gb))) |>
  arrange(desc(Boosting))
write.csv(mutate(imp, across(c(Logistic, Boosting), ~ round(.x, 3))),
          "output/shap_importance.csv", row.names = FALSE)
print(imp)

# ---- Figure 5: mean |SHAP| ---------------------------------------------------------
imp_long <- imp |>
  pivot_longer(c(Logistic, Boosting), names_to = "model", values_to = "value") |>
  mutate(label = factor(label, levels = rev(imp$label)),
         model = factor(model, levels = c("Logistic", "Boosting")))
p5 <- ggplot(imp_long, aes(value, label, fill = model)) +
  geom_col(position = position_dodge2(reverse = TRUE, padding = 0.1), width = 0.75) +
  scale_fill_manual(values = model_cols[c("Logistic", "Boosting")], name = NULL) +
  labs(title = "Which predictors matter most?",
       subtitle = "Mean absolute SHAP value, 500 test-set people",
       x = "Mean |SHAP| (log-odds)", y = NULL)
save_fig(p5, "fig5_shap_importance.png", w = 7, h = 5.5)

# ---- Figure 6: dependence plots for the boosting model --------------------------------
dep_vars <- c("age", "waist", "hdl", "bmi")
dep <- bind_rows(lapply(dep_vars, function(v)
  tibble(variable = labels[v], x = explain[[v]], shap = shap_gb[, v])))
dep$variable <- factor(dep$variable, levels = labels[dep_vars])
p6 <- ggplot(dep, aes(x, shap)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_point(alpha = 0.35, size = 1.2, colour = model_cols[["Boosting"]]) +
  facet_wrap(~variable, scales = "free_x") +
  labs(title = "How the boosting model uses four measures",
       subtitle = "Each dot is one person. Above 0 = higher predicted risk.",
       x = "Value of the predictor", y = "SHAP value (log-odds)")
save_fig(p6, "fig6_shap_dependence.png", w = 7.5, h = 6)
