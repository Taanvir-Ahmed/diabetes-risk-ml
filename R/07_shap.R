# 07_shap.R
# SHAP values: how much each predictor pushes one person's predicted risk up
# or down (on the log-odds scale), compared with an average person.
#   Logistic model: exact formula, beta * (x - mean of x).
#   XGBoost: exact TreeSHAP values, built into xgboost (predcontrib = TRUE).
# Output: output/shap_importance.csv, figures/fig5_shap_importance.png,
#         figures/fig6_shap_dependence.png

source("R/00_setup.R")
obj <- readRDS("data/processed/models.rds")
train <- obj$train; test <- obj$test; feats <- obj$predictors

mm <- function(data) model.matrix(obj$formula, data)[, -1]
X_tr <- mm(train)
X_te <- mm(test)

# Each dummy column belongs to one variable (e.g. 4 ethnicity dummies -> ethnicity)
col_var <- sapply(colnames(X_te), function(cn) feats[startsWith(cn, feats)][1])
by_variable <- function(contrib) {
  sapply(feats, function(v) rowSums(contrib[, col_var == v, drop = FALSE]))
}

# ---- Logistic: exact SHAP ------------------------------------------------------
b <- coef(obj$models$Logistic)[-1]
shap_lr <- by_variable(sweep(sweep(X_te, 2, colMeans(X_tr)), 2, b, "*"))

# ---- XGBoost: TreeSHAP -------------------------------------------------------
contrib_xgb <- predict(obj$models$XGBoost, xgb.DMatrix(X_te), predcontrib = TRUE)
contrib_xgb <- contrib_xgb[, colnames(X_te)]      # drop the bias (intercept) column
shap_xgb <- by_variable(contrib_xgb)

# ---- Importance table ----------------------------------------------------------
labels <- c(age = "Age", sex = "Sex", ethnicity = "Ethnicity", education = "Education",
            income = "Income", bmi = "BMI", waist = "Waist", sbp = "Systolic BP",
            dbp = "Diastolic BP", total_chol = "Total cholesterol", hdl = "HDL",
            smoking = "Smoking", active = "Physical activity",
            family_history = "Family history")
imp <- tibble(variable = feats, label = labels[feats],
              Logistic = colMeans(abs(shap_lr)), XGBoost = colMeans(abs(shap_xgb))) |>
  arrange(desc(XGBoost))
write.csv(mutate(imp, across(c(Logistic, XGBoost), ~ round(.x, 3))),
          "output/shap_importance.csv", row.names = FALSE)
print(imp)

# ---- Figure 5: mean |SHAP| ---------------------------------------------------------
imp_long <- imp |>
  pivot_longer(c(Logistic, XGBoost), names_to = "model", values_to = "value") |>
  mutate(label = factor(label, levels = rev(imp$label)),
         model = factor(model, levels = c("Logistic", "XGBoost")))
p5 <- ggplot(imp_long, aes(value, label, fill = model)) +
  geom_col(position = position_dodge2(reverse = TRUE, padding = 0.1), width = 0.75) +
  scale_fill_manual(values = model_cols[c("Logistic", "XGBoost")], name = NULL) +
  labs(title = "Which predictors matter most?",
       subtitle = "Mean absolute SHAP value in the test set",
       x = "Mean |SHAP| (log-odds)", y = NULL)
save_fig(p5, "fig5_shap_importance.png", w = 7, h = 5.5)

# ---- Figure 6: dependence plots for XGBoost --------------------------------
dep_vars <- c("age", "waist", "hdl", "bmi")
dep <- bind_rows(lapply(dep_vars, function(v)
  tibble(variable = labels[v], x = test[[v]], shap = shap_xgb[, v])))
dep$variable <- factor(dep$variable, levels = labels[dep_vars])
p6 <- ggplot(dep, aes(x, shap)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_point(alpha = 0.3, size = 1, colour = model_cols[["XGBoost"]]) +
  facet_wrap(~variable, scales = "free_x") +
  labs(title = "How XGBoost uses four measures",
       subtitle = "Each dot is one person. Above 0 = higher predicted risk.",
       x = "Value of the predictor", y = "SHAP value (log-odds)")
save_fig(p6, "fig6_shap_dependence.png", w = 7.5, h = 6)
